import GitHubService
import Observation
import PRRadarCLIService
import PRRadarConfigService
import PRReviewFeature

@Observable @MainActor
final class RunsModel {

    private(set) var runs: [RunHistoryEntry] = []
    private(set) var loadState: LoadState = .idle
    private(set) var liveRunState: LiveRunState = .idle

    func loadHistory(config: PRRadarRepoConfig) async {
        loadState = .loading
        do {
            runs = try RunHistoryService.loadRuns(outputDir: config.resolvedOutputDir)
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func runAll(
        config: PRRadarRepoConfig,
        filter: PRFilter,
        rulesDir: String,
        rulesPathName: String?
    ) async {
        liveRunState = .running(logs: "", current: 0, total: 0)
        let useCase = RunAllUseCase(config: config)
        do {
            for try await event in useCase.execute(filter: filter, rulesDir: rulesDir, rulesPathName: rulesPathName) {
                switch event {
                case .running, .prepareStreamEvent, .taskEvent:
                    break
                case .log(let text):
                    appendLiveLog(text)
                case .progress(let current, let total):
                    updateProgress(current: current, total: total)
                case .completed(let output):
                    let entry = RunHistoryEntry(manifest: output.manifest, prEntries: output.prStats)
                    runs.insert(entry, at: 0)
                    liveRunState = .completed(entry)
                case .failed(let error, _):
                    liveRunState = .failed(error)
                }
            }
        } catch {
            liveRunState = .failed(error.localizedDescription)
        }
    }

    private func appendLiveLog(_ text: String) {
        guard case .running(let logs, let current, let total) = liveRunState else { return }
        liveRunState = .running(logs: logs + text, current: current, total: total)
    }

    private func updateProgress(current: Int, total: Int) {
        guard case .running(let logs, _, _) = liveRunState else { return }
        liveRunState = .running(logs: logs, current: current, total: total)
    }

    enum LoadState {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum LiveRunState {
        case idle
        case running(logs: String, current: Int, total: Int)
        case completed(RunHistoryEntry)
        case failed(String)
    }
}
