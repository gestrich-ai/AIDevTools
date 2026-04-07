import LoggingSDK
import LogsFeature
import Observation

@Observable
@MainActor
final class LogsModel {
    private let streamLogsUseCase: StreamLogsUseCase
    private let clearLogsUseCase: ClearLogsUseCase
    private(set) var items: [LogItem] = []
    var searchText: String = ""
    private(set) var state: ModelState = .idle
    private var nextID = 0

    init(
        streamLogsUseCase: StreamLogsUseCase = StreamLogsUseCase(),
        clearLogsUseCase: ClearLogsUseCase = ClearLogsUseCase()
    ) {
        self.streamLogsUseCase = streamLogsUseCase
        self.clearLogsUseCase = clearLogsUseCase
    }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    var filteredItems: [LogItem] {
        guard !searchText.isEmpty else { return items }
        let query = searchText.lowercased()
        return items.filter { item in
            item.entry.message.lowercased().contains(query) ||
            item.entry.label.lowercased().contains(query) ||
            item.entry.level.lowercased().contains(query) ||
            (item.entry.source?.lowercased().contains(query) ?? false)
        }
    }

    func load() async {
        guard case .idle = state else { return }
        state = .loading
        do {
            for try await newEntries in streamLogsUseCase.stream() {
                state = .streaming
                append(newEntries)
            }
        } catch is CancellationError {
        } catch {
            state = .error(error)
        }
    }

    func deleteLogs() {
        clearLogsUseCase.execute()
        items = []
        nextID = 0
    }

    private func append(_ entries: [LogEntry]) {
        let newItems = entries.enumerated().map { offset, entry in
            LogItem(id: nextID + offset, entry: entry)
        }
        nextID += entries.count
        items.append(contentsOf: newItems)
    }

    enum ModelState {
        case idle
        case loading
        case streaming
        case error(Error)
    }
}

struct LogItem: Identifiable {
    let id: Int
    let entry: LogEntry
}
