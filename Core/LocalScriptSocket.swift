import Darwin
import Foundation

/// A same-user Unix socket, separate from MCP's stdio transport. Only the GUI owns the library.
enum LocalScriptSocket {
    static let maximumMessageBytes = 1_048_576
    static var directory: URL {
        URL(fileURLWithPath: "/tmp/teleprompter-mcp-\(geteuid())", isDirectory: true)
    }
    static var url: URL { directory.appendingPathComponent("scripts.sock") }

    static func secureDirectory(_ url: URL) throws {
        if mkdir(url.path, 0o700) != 0 && errno != EEXIST { throw systemError("Create agent directory") }
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & S_IFMT == S_IFDIR else {
            throw ScriptAutomationError.transport("The agent directory must be a real directory owned by this user.")
        }
        guard chmod(url.path, 0o700) == 0 else { throw systemError("Secure agent directory") }
    }

    static func address(_ url: URL) throws -> sockaddr_un {
        var address = sockaddr_un()
        let bytes = Array(url.path.utf8) + [UInt8(0)]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw ScriptAutomationError.transport("The local agent socket path is too long.")
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }

    static func configure(_ fd: Int32) {
        // Darwin accept() inherits the listener's nonblocking flag. Client I/O uses bounded blocking reads.
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) }
        var enabled: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled)))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }

    static func verifyPeer(_ fd: Int32) throws {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == geteuid() else {
            throw ScriptAutomationError.transport("Agent access is restricted to this Mac user.")
        }
    }

    static func connect(to url: URL) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw systemError("Create agent socket") }
        configure(fd)
        do {
            var address = try address(url)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else { throw systemError("Connect to Teleprompter") }
            try verifyPeer(fd)
            return fd
        } catch { close(fd); throw error }
    }

    static func request(_ request: ScriptAutomationRequest, at url: URL = Self.url) throws -> ScriptAutomationResponse {
        try request.validate()
        let fd = try connect(to: url)
        defer { close(fd) }
        return try self.request(request, over: fd)
    }

    static func request(_ request: ScriptAutomationRequest, over fd: Int32) throws -> ScriptAutomationResponse {
        try request.validate()
        try writeLine(JSONEncoder().encode(request), to: fd)
        return try JSONDecoder().decode(ScriptAutomationResponse.self, from: readLine(from: fd))
    }

    static func readLine(from fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw systemError("Read agent response") }
            if let end = buffer[..<count].firstIndex(of: 10) {
                data.append(contentsOf: buffer[..<end])
                guard data.count <= maximumMessageBytes else { throw systemError("Agent message exceeds 1 MB") }
                return data
            }
            data.append(contentsOf: buffer[..<count])
            guard data.count <= maximumMessageBytes else { throw systemError("Agent message exceeds 1 MB") }
        }
    }

    static func writeLine(_ data: Data, to fd: Int32) throws {
        guard data.count <= maximumMessageBytes else {
            throw ScriptAutomationError.transport("Agent message exceeds 1 MB.")
        }
        let line = data + Data([10])
        try line.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw systemError("Write agent response") }
                offset += count
            }
        }
    }

    static func systemError(_ action: String) -> ScriptAutomationError {
        .transport("\(action): \(String(cString: strerror(errno))).")
    }
}

@MainActor final class ScriptAutomationSocketServer {
    typealias Handler = @MainActor @Sendable (ScriptAutomationRequest) -> ScriptAutomationResponse
    private var source: DispatchSourceRead?
    private var lockFD: Int32 = -1
    private let url: URL

    init(url: URL = LocalScriptSocket.url, handler: @escaping Handler) throws {
        self.url = url
        try LocalScriptSocket.secureDirectory(url.deletingLastPathComponent())
        let lock = url.appendingPathExtension("lock")
        lockFD = Darwin.open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lockFD >= 0 else { throw LocalScriptSocket.systemError("Lock agent access") }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            close(lockFD); lockFD = -1
            throw ScriptAutomationError.transport("Another Teleprompter instance already owns agent access.")
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { close(lockFD); lockFD = -1; throw LocalScriptSocket.systemError("Create agent listener") }
        do {
            var info = stat()
            if lstat(url.path, &info) == 0 {
                guard info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFSOCK else {
                    throw ScriptAutomationError.transport("An unexpected file occupies the agent socket path.")
                }
                guard unlink(url.path) == 0 else { throw LocalScriptSocket.systemError("Remove stale agent socket") }
            }
            var address = try LocalScriptSocket.address(url)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0, chmod(url.path, 0o600) == 0, listen(fd, 8) == 0 else {
                throw LocalScriptSocket.systemError("Listen for local agent requests")
            }
            _ = fcntl(fd, F_SETFL, O_NONBLOCK)
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            let slots = DispatchSemaphore(value: 4)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .utility))
            source.setEventHandler { @Sendable in
                while true {
                    let client = accept(fd, nil, nil)
                    if client < 0 { break }
                    guard slots.wait(timeout: .now()) == .success else { close(client); continue }
                    Task.detached(priority: .utility) {
                        defer { close(client); slots.signal() }
                        LocalScriptSocket.configure(client)
                        do {
                            try LocalScriptSocket.verifyPeer(client)
                            let data = try LocalScriptSocket.readLine(from: client)
                            let request = try JSONDecoder().decode(ScriptAutomationRequest.self, from: data)
                            try request.validate()
                            let response = await handler(request)
                            try LocalScriptSocket.writeLine(JSONEncoder().encode(response), to: client)
                        } catch {
                            if let data = try? JSONEncoder().encode(ScriptAutomationResponse.failure(error.localizedDescription)) {
                                try? LocalScriptSocket.writeLine(data, to: client)
                            }
                        }
                    }
                }
            }
            source.setCancelHandler { @Sendable in close(fd) }
            self.source = source
            source.resume()
        } catch {
            close(fd); close(lockFD); lockFD = -1
            throw error
        }
    }

    func stop() {
        guard source != nil else { return }
        source?.cancel(); source = nil
        unlink(url.path)
        close(lockFD); lockFD = -1
    }
}
