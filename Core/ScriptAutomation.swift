import Foundation

struct ScriptAutomationRequest: Codable, Sendable {
    enum Operation: String, Codable, Sendable { case add, list, open }
    var operation: Operation
    var title: String?
    var text: String?
    var scriptID: UUID?
    var query: String?
    var offset: Int?
    var limit: Int?

    func validate() throws {
        switch operation {
        case .add:
            guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  title.count <= 200, let text, text.utf8.count <= 500_000 else {
                throw ScriptAutomationError.invalidArguments("Provide a nonempty title (up to 200 characters) and text (up to 500 KB).")
            }
        case .list:
            guard (query?.count ?? 0) <= 200, (offset ?? 0) >= 0,
                  (1...100).contains(limit ?? 50) else {
                throw ScriptAutomationError.invalidArguments("Use a query up to 200 characters, a nonnegative offset, and a limit from 1 to 100.")
            }
        case .open:
            guard scriptID != nil else { throw ScriptAutomationError.invalidArguments("Provide a valid script UUID.") }
        }
    }
}

struct ScriptAutomationItem: Codable, Sendable {
    let id: UUID
    let title: String
    let wordCount: Int
    let modifiedAt: Date

    init(_ script: SavedScript) {
        id = script.id
        title = script.title
        wordCount = script.text.split(whereSeparator: \.isWhitespace).count
        modifiedAt = script.modifiedAt
    }
}

struct ScriptAutomationResponse: Codable, Sendable {
    var success: Bool
    var scripts: [ScriptAutomationItem] = []
    var activeID: UUID?
    var running: Bool = false
    var totalCount: Int?
    var nextOffset: Int?
    var error: String?

    static func failure(_ message: String) -> Self { Self(success: false, error: message) }
}

enum ScriptAutomationError: LocalizedError {
    case invalidArguments(String), unavailable(String), missingScript, transport(String)
    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message), .unavailable(let message), .transport(let message): message
        case .missingScript: "That script does not exist or is in Trash. List scripts to choose an available ID."
        }
    }
}
