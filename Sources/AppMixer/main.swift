import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let manager = AudioManager()
    private let hotKey = HotKeyManager()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var panel: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        appLog("AppMixer: applicationDidFinishLaunching")

        // Menu bar item.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "slider.horizontal.3",
                                   accessibilityDescription: "AppMixer")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Popover anchored to the menu bar item.
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.contentViewController = NSHostingController(rootView: MenuView(manager: manager))

        // Standalone panel summoned by the global hotkey — works even when the
        // menu bar icon is hidden behind the notch.
        let hosting = NSHostingController(rootView: MenuView(manager: manager))
        panel = NSWindow(contentViewController: hosting)
        panel.title = "App 音量"
        panel.styleMask = [.titled, .closable, .resizable]
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.setContentSize(NSSize(width: 360, height: 480))

        // Global hotkey: ⌃⌥⌘M
        hotKey.onTrigger = { [weak self] in self?.togglePanel() }
        hotKey.register()

        // Show once on launch so it's obvious the app started.
        showPanel()
        appLog("AppMixer: launch complete")
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func togglePanel() {
        appLog("AppMixer: togglePanel (visible=\(panel.isVisible))")
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Entry point

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let appDelegate = AppDelegate()
    application.delegate = appDelegate
    application.setActivationPolicy(.accessory)
    application.run()
}
