import AppKit
import SwiftUI
import RealTodoKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let todayVM = TodayViewModel()
    private let allVM = TodoListViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()

        Task {
            await TimerService.shared.start()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            Task {
                _ = await NotificationService.shared.requestPermission()
            }
        }

        // When the calendar day rolls over (midnight, or wake into a new day),
        // yesterday's completed items should drop out of "today" and unfinished
        // ones carry forward — without needing an app restart.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dayChanged),
            name: .NSCalendarDayChanged,
            object: nil
        )
    }

    @objc private func dayChanged() {
        Task {
            try? await TimerService.shared.runRollover()
            await todayVM.loadTodayTodos()
            await allVM.loadAllTodos()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            await TimerService.shared.stop()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // autosaveName makes macOS persist this item's menu-bar position, so the
        // icon stays where the user puts it instead of being re-placed (often
        // under the notch) on every launch.
        item.autosaveName = "RealTodoStatusItem"
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "RealTodo")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        statusItem = item
    }

    private func setupPopover() {
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.behavior = .transient   // closes when the user clicks outside
        popover.contentViewController = NSHostingController(
            rootView: PopoverContainerView(todayVM: todayVM, allVM: allVM)
        )
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Refresh on open so the list reflects the current day and any
            // changes made via the CLI while the popover was closed.
            Task {
                await todayVM.loadTodayTodos()
                await allVM.loadAllTodos()
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
