import SwiftUI
import RealTodoKit

@main
struct RealTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The menu bar item and popover are owned by AppDelegate via AppKit
        // (NSStatusItem + autosaveName) so the icon keeps a stable, persistent
        // position across launches. Only the Settings window stays a SwiftUI scene.
        Settings {
            SettingsView()
        }
    }
}
