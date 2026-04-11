import SwiftUI

struct ExperimentalSettingsView: View {
    @State private var experimentalSettings = ExperimentalSettings()

    var body: some View {
        Form {
            Section {
                Label(
                    "These features are under active development and may be incomplete, unstable, or change without notice.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.secondary)
            }

            Section("Features") {
                Toggle("Architecture Planner", isOn: Binding(
                    get: { experimentalSettings.isArchitecturePlannerEnabled },
                    set: { experimentalSettings.isArchitecturePlannerEnabled = $0 }
                ))

                Text("Shows the Architecture tab in the workspace. Walks a feature description through an AI pipeline that maps it to your codebase's architecture and produces a structured report.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
