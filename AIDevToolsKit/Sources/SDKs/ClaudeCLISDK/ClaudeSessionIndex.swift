import AIOutputSDK
import Foundation

struct ClaudeSessionIndex: Sendable {
    private let claudeHome: URL

    init(claudeHome: URL? = nil) {
        self.claudeHome = claudeHome ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
    }

    func listSessions() -> [ChatSession] {
        let indexURL = claudeHome.appendingPathComponent("session_index.jsonl")
        guard let data = try? Data(contentsOf: indexURL),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }

        var sessionsByID: [String: ChatSession] = [:]
        let decoder = JSONDecoder()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let entry = try? decoder.decode(SessionIndexEntry.self, from: lineData) else {
                continue
            }
            let date = dateFormatter.date(from: entry.updatedAt) ?? Date.distantPast
            sessionsByID[entry.id] = ChatSession(id: entry.id, lastModified: date, summary: entry.summary)
        }

        return sessionsByID.values.sorted { $0.lastModified > $1.lastModified }
    }

    func appendSession(id: String, summary: String) throws {
        let indexURL = claudeHome.appendingPathComponent("session_index.jsonl")
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let entry = SessionIndexEntry(id: id, summary: summary, updatedAt: dateFormatter.string(from: Date()))
        let data = try JSONEncoder().encode(entry)
        guard let line = String(data: data, encoding: .utf8) else { return }
        let lineWithNewline = line + "\n"
        if let handle = FileHandle(forWritingAtPath: indexURL.path) {
            handle.seekToEndOfFile()
            handle.write(Data(lineWithNewline.utf8))
            handle.closeFile()
        } else {
            try lineWithNewline.write(to: indexURL, atomically: false, encoding: .utf8)
        }
    }
}

private struct SessionIndexEntry: Codable {
    let id: String
    let summary: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case summary
        case updatedAt = "updated_at"
    }
}
