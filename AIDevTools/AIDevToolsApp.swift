import AIDevToolsKitMac
import LoggingSDK
import SwiftUI

@main
struct AIDevToolsApp: App {
    init() {
        AIDevToolsLogging.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            AIDevToolsKitMacEntryView()
        }
        Settings {
            AIDevToolsSettingsView()
        }
    }
}
