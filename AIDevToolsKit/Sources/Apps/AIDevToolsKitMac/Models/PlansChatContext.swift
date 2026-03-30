import Foundation
import SwiftUI

@MainActor
final class PlansChatContext: ViewChatContext {

    let chatSystemPrompt: String = "You are an AI assistant embedded in the AIDevTools Mac app. Use the get_ui_state tool to check what tab and plan the user is currently viewing."

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
