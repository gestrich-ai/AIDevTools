import Foundation
import SwiftUI

@MainActor
final class PlansChatContext: ViewChatContext {

    let chatSystemPrompt: String = "You are in the Plans tab. The user can view, generate, execute, and iterate on implementation plans."

    private let workspaceModel: WorkspaceModel

    var chatContextIdentifier: String {
        "plans-\(workspaceModel.selectedRepository?.id.uuidString ?? "none")"
    }

    var chatWorkingDirectory: String {
        workspaceModel.selectedRepository?.path.path(percentEncoded: false) ?? ""
    }

    init(workspaceModel: WorkspaceModel) {
        self.workspaceModel = workspaceModel
    }
}
