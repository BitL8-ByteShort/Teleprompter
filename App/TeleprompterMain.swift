import AppKit
import Darwin

@main enum TeleprompterMain {
    @MainActor static func main() {
        guard CommandLine.arguments.contains("--mcp") else { TeleprompterApp.main(); return }
        let overrideIndex = CommandLine.arguments.firstIndex(of: "--mcp-socket")
        let socketURL: URL
        if let index = overrideIndex {
            guard CommandLine.arguments.indices.contains(index + 1) else {
                FileHandle.standardError.write(Data("--mcp-socket needs a path.\n".utf8)); exit(2)
            }
            socketURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        } else { socketURL = LocalScriptSocket.url }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        MCPProtocol(version: version) { request in
            let fd = try connect(socketURL, launchApp: overrideIndex == nil)
            defer { close(fd) }
            // Never retry after sending: an add may have committed even if its reply was lost.
            return try LocalScriptSocket.request(request, over: fd)
        }.serve()
    }

    private static func connect(_ url: URL, launchApp: Bool) throws -> Int32 {
        do { return try LocalScriptSocket.connect(to: url) }
        catch {
            guard launchApp else { throw error }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-g", Bundle.main.bundleURL.path, "--args", "--agent-background"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ScriptAutomationError.unavailable("Teleprompter could not be opened. Launch the MCP-enabled app and try again.")
            }
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if let fd = try? LocalScriptSocket.connect(to: url) { return fd }
                Thread.sleep(forTimeInterval: 0.1)
            }
            throw ScriptAutomationError.unavailable("Agent access is unavailable. Quit any older Teleprompter copy, then open the MCP-enabled app. Your scripts have not been changed.")
        }
    }
}
