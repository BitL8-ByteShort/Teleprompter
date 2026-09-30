import Foundation
import Testing
@testable import TeleprompterCore

@Suite struct MCPTests {
    private func rpc(_ server: MCPProtocol, id: Int = 1, method: String, params: [String: Any] = [:]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        return try JSONSerialization.jsonObject(with: #require(server.handle(data))) as! [String: Any]
    }
    private func initialize(_ server: MCPProtocol) throws {
        let response = try rpc(server, method: "initialize", params: ["protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "test", "version": "1"]])
        #expect((response["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-11-25")
        #expect(server.handle(Data("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}".utf8)) == nil)
    }

    @Test func legacyDiscoveryAndUnicodeToolCall() throws {
        var calls = [ScriptAutomationRequest]()
        let server = MCPProtocol(version: "1.2.0") { request in calls.append(request); return .init(success: true) }
        try initialize(server)
        let listed = try rpc(server, method: "tools/list")
        let tools = (listed["result"] as! [String: Any])["tools"] as! [[String: Any]]
        #expect(tools.compactMap { $0["name"] as? String } == ["add_script", "list_scripts", "open_script"])
        let result = try rpc(server, method: "tools/call", params: ["name": "add_script", "arguments": ["title": "Episode 🎥", "text": "Quotes: \"Hello\"\nCafé. 日本語."]])
        #expect((result["result"] as? [String: Any])?["isError"] as? Bool == false)
        #expect(calls.count == 1 && calls[0].text == "Quotes: \"Hello\"\nCafé. 日本語.")
    }

    @Test func statelessDiscoveryAndCallsDoNotNeedLegacyInitialize() throws {
        let server = MCPProtocol(version: "1.2.0") { _ in .init(success: true) }
        let discovery = try rpc(server, method: "server/discover")
        #expect(((discovery["result"] as? [String: Any])?["supportedVersions"] as? [String])?.contains("2026-07-28") == true)
        let response = try rpc(server, method: "tools/list", params: ["_meta": ["io.modelcontextprotocol/protocolVersion": "2026-07-28", "io.modelcontextprotocol/clientCapabilities": [:]]])
        #expect((response["result"] as? [String: Any])?["resultType"] as? String == "complete")
    }

    @Test func malformedRequestsAndInvalidArgumentsNeverWrite() throws {
        var calls = 0
        let server = MCPProtocol(version: "test") { _ in calls += 1; return .init(success: true) }
        #expect(server.handle(Data("not JSON".utf8)) != nil)
        let premature = try rpc(server, method: "tools/call", params: ["name": "add_script", "arguments": ["title": "Test", "text": "Body"]])
        #expect(premature["error"] != nil)
        try initialize(server)
        for arguments: [String: Any] in [
            ["title": " ", "text": "Body"], ["title": "Test", "text": 3],
            ["title": "Test", "text": String(repeating: "x", count: 500_001)],
            ["title": "Test", "text": "Body", "delete_all": true]
        ] {
            let response = try rpc(server, method: "tools/call", params: ["name": "add_script", "arguments": arguments])
            #expect(response["error"] != nil)
        }
        let boolLimit = try rpc(server, method: "tools/call", params: ["name": "list_scripts", "arguments": ["limit": true]])
        #expect(boolLimit["error"] != nil)
        let noID = try rpc(server, method: "tools/call", params: ["name": "open_script", "arguments": ["script_id": "missing"]])
        #expect(noID["error"] != nil)
        #expect(server.handle(Data("{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"add_script\",\"arguments\":{\"title\":\"Test\",\"text\":\"Body\"}}}".utf8)) == nil)
        #expect(calls == 0)
    }

    @Test func saveFailuresAreToolErrorsInsteadOfSuccess() throws {
        let server = MCPProtocol(version: "test") { _ in .failure("Disk is full") }
        try initialize(server)
        let response = try rpc(server, method: "tools/call", params: ["name": "add_script", "arguments": ["title": "Test", "text": "Body"]])
        let result = response["result"] as! [String: Any]
        #expect(result["isError"] as? Bool == true)
        #expect((result["structuredContent"] as? [String: Any])?["success"] as? Bool == false)
    }

    @Test func addingWithoutSelectionRetainsPositionAndUsesUniqueTitles() throws {
        var library = ScriptLibrary(defaultText: "One two three four")
        let initial = library.activeID
        library.updateActive(text: "Edited original", position: 1)
        let first = library.create(title: "Episode", text: "Agent text", select: false)
        let second = library.create(title: "Episode", text: "Other text", select: false)
        try library.validate()
        #expect(library.activeID == initial && library.activeScript?.position == 1)
        #expect(library.scripts.first { $0.id == first }?.title == "Episode")
        #expect(library.scripts.first { $0.id == second }?.title == "Episode 2")
    }

    @MainActor @Test func localSocketRoundTripAndSingleWriterLock() async throws {
        let folder = URL(fileURLWithPath: "/tmp/tp-mcp-test-\(UUID().uuidString)")
        let url = folder.appendingPathComponent("scripts.sock")
        let server = try ScriptAutomationSocketServer(url: url) { request in
            .init(success: request.operation == .list, totalCount: 7)
        }
        defer { server.stop(); try? FileManager.default.removeItem(at: folder) }
        let response = try await Task.detached { try LocalScriptSocket.request(.init(operation: .list), at: url) }.value
        #expect(response.error == nil)
        #expect(response.success && response.totalCount == 7)
        #expect(throws: (any Error).self) { try ScriptAutomationSocketServer(url: url) { _ in .init(success: true) } }
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }
}
