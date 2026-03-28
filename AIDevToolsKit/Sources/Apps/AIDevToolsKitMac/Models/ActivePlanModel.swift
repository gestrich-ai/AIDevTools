import AIOutputSDK
import Foundation
import Observation

@Observable
@MainActor
final class ActivePlanModel {
    private(set) var content: String = ""
    private(set) var phases: [PlanPhase] = []
    private var watchTask: Task<Void, Never>?

    func startWatching(url: URL) {
        watchTask?.cancel()
        watchTask = Task {
            for await newContent in FileWatcher(url: url).contentStream() {
                self.content = newContent
                self.phases = MarkdownPlannerModel.parsePhases(from: newContent)
            }
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }
}
