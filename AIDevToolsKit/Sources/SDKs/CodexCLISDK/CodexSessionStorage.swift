import AIOutputSDK
import Foundation

struct CodexSessionStorage: Sendable {
    private let codexHome: URL

    init(codexHome: URL? = nil) {
        self.codexHome = codexHome ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
    }

    // MARK: - Session Listing

    func listSessions(workingDirectory: String) -> [ChatSession] {
        let indexPath = codexHome.appendingPathComponent("session_index.jsonl")
        guard let data = try? Data(contentsOf: indexPath),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }

        // Append-only file — newest entry wins for duplicate IDs.
        var sessionsByID: [String: ChatSession] = [:]
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let normalizedWorkingDirectory = normalizedPath(workingDirectory)

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  // Swallowing intentionally: malformed or stale index lines are skipped;
                  // the index is append-only so individual bad entries don't affect others.
                  let entry = try? JSONDecoder().decode(SessionIndexEntry.self, from: lineData) else {
                continue
            }
            guard sessionWorkingDirectory(sessionId: entry.id) == normalizedWorkingDirectory else {
                continue
            }
            let date = dateFormatter.date(from: entry.updatedAt) ?? Date.distantPast
            sessionsByID[entry.id] = ChatSession(id: entry.id, lastModified: date, summary: entry.threadName)
        }

        return sessionsByID.values.sorted { $0.lastModified > $1.lastModified }
    }

    func getSessionDetails(sessionId: String, summary: String, lastModified: Date) -> SessionDetails? {
        guard let fileURL = findRolloutFile(sessionId: sessionId),
              let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else { return nil }

        var cwd: String?
        var gitBranch: String?
        var rawJsonLines: [String] = []

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            rawJsonLines.append(trimmed)

            if let payload = parseSessionMeta(from: trimmed) {
                cwd = payload.cwd
                gitBranch = payload.git?.branch
            }
        }

        let session = ChatSession(id: sessionId, lastModified: lastModified, summary: summary)
        return SessionDetails(cwd: cwd, gitBranch: gitBranch, rawJsonLines: rawJsonLines, session: session)
    }

    func appendSession(id: String, threadName: String) throws {
        let indexPath = codexHome.appendingPathComponent("session_index.jsonl")
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let entry = SessionIndexEntry(id: id, threadName: threadName, updatedAt: dateFormatter.string(from: Date()))
        let encoded = try JSONEncoder().encode(entry)
        guard let line = String(data: encoded, encoding: .utf8) else { return }
        let lineWithNewline = line + "\n"
        if let handle = FileHandle(forWritingAtPath: indexPath.path) {
            handle.seekToEndOfFile()
            handle.write(Data(lineWithNewline.utf8))
            handle.closeFile()
        } else {
            try lineWithNewline.write(to: indexPath, atomically: false, encoding: .utf8)
        }
    }

    // MARK: - Message Loading

    func loadMessages(sessionId: String) -> [ChatSessionMessage] {
        guard let filePath = findRolloutFile(sessionId: sessionId) else {
            return []
        }

        let ext = filePath.pathExtension
        if ext == "jsonl" {
            return parseJSONLRollout(at: filePath)
        } else if ext == "json" {
            return parseLegacyJSON(at: filePath)
        }
        return []
    }

    // MARK: - Rollout File Discovery

    private func findRolloutFile(sessionId: String) -> URL? {
        let sessionsDir = codexHome.appendingPathComponent("sessions")
        return findFileRecursively(in: sessionsDir, containing: sessionId)
    }

    private func sessionWorkingDirectory(sessionId: String) -> String? {
        guard let fileURL = findRolloutFile(sessionId: sessionId),
              let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let payload = parseSessionMeta(from: trimmed), let cwd = payload.cwd {
                return normalizedPath(cwd)
            }
        }

        return nil
    }

    private func findFileRecursively(in directory: URL, containing sessionId: String) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent
            if filename.contains(sessionId) && (filename.hasSuffix(".jsonl") || filename.hasSuffix(".json")) {
                return fileURL
            }
        }
        return nil
    }

    // MARK: - JSONL Rollout Parsing (Current Codex format)

    private func parseJSONLRollout(at url: URL) -> [ChatSessionMessage] {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }

        var messages: [ChatSessionMessage] = []

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  obj["type"] as? String == "event_msg",
                  let payload = obj["payload"] as? [String: Any] else { continue }

            let payloadType = payload["type"] as? String

            if payloadType == "user_message",
               let message = payload["message"] as? String,
               !message.isEmpty {
                messages.append(ChatSessionMessage(content: message, role: .user))
            } else if payloadType == "agent_message",
                      let message = payload["message"] as? String,
                      !message.isEmpty {
                let phase = payload["phase"] as? String
                let role: ChatSessionMessage.ChatSessionMessageRole = phase == "commentary" ? .thinking : .assistant
                messages.append(ChatSessionMessage(content: message, role: role))
            }
        }

        return messages
    }

    // MARK: - Legacy JSON Parsing (Old Codex format)

    private func parseLegacyJSON(at url: URL) -> [ChatSessionMessage] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }

        var messages: [ChatSessionMessage] = []

        for item in items {
            guard item["type"] as? String == "message",
                  let role = item["role"] as? String,
                  role == "user" || role == "assistant" else {
                continue
            }

            let text = extractText(from: item["content"])
            guard !text.isEmpty else { continue }

            messages.append(ChatSessionMessage(
                content: text,
                role: role == "user" ? .user : .assistant
            ))
        }

        return messages
    }

    // MARK: - Content Extraction

    private func extractText(from content: Any?) -> String {
        if let text = content as? String {
            return text
        }

        if let contentArray = content as? [[String: Any]] {
            return contentArray.compactMap { obj -> String? in
                guard let type = obj["type"] as? String,
                      type == "input_text" || type == "output_text" || type == "text" else {
                    return nil
                }
                return obj["text"] as? String
            }.joined(separator: "\n")
        }

        return ""
    }

    private func parseSessionMeta(from line: String) -> SessionMetaPayload? {
        guard let data = line.data(using: .utf8),
              let meta = try? JSONDecoder().decode(SessionMetaLine.self, from: data),
              meta.type == "session_meta" else { return nil }
        return meta.payload
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}

// MARK: - Models

private struct SessionMetaLine: Codable {
    let type: String
    let payload: SessionMetaPayload?
}

private struct SessionMetaPayload: Codable {
    let cwd: String?
    let git: SessionMetaGit?
}

private struct SessionMetaGit: Codable {
    let branch: String?
}

private struct SessionIndexEntry: Codable {
    let id: String
    let threadName: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
        case updatedAt = "updated_at"
    }
}
