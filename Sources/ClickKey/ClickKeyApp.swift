import AppKit
import SwiftUI

@main
struct ClickKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("ClickKey", systemImage: "computermouse") {
            MenuContent()
                .environmentObject(MappingStore.shared)
                .environmentObject(EventTapManager.shared)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dir = SnapshotRenderer.requestedDirectory() {
            SnapshotRenderer.run(to: dir)
            exit(0)
        }

        // Info.plist sets LSUIElement; this also covers `swift run` without a bundle.
        NSApp.setActivationPolicy(.accessory)

        let store = MappingStore.shared
        let tap = EventTapManager.shared
        store.onChange = { tap.activeMappings = $0 }
        tap.activeMappings = store.activeMap
        tap.startMonitoring()

        if !tap.isTrusted {
            WindowManager.shared.showOnboarding()
        }
    }
}

/// AppKit windows hosting SwiftUI: works reliably from an LSUIElement app on macOS 13,
/// including at launch (before any SwiftUI scene could call openWindow).
@MainActor
final class WindowManager {
    static let shared = WindowManager()
    static let settingsID = "settings"
    static let onboardingID = "onboarding"

    private var windows: [String: NSWindow] = [:]

    func showSettings() {
        show(id: Self.settingsID, title: "ClickKey Settings", resizable: true) { SettingsView() }
    }

    func showOnboarding() {
        show(id: Self.onboardingID, title: "Welcome to ClickKey", resizable: false) { OnboardingView() }
    }

    func close(_ id: String) {
        windows[id]?.close()
    }

    private func show<Content: View>(id: String, title: String, resizable: Bool, content: () -> Content) {
        NSApp.activate(ignoringOtherApps: true)
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        let root = content()
            .environmentObject(MappingStore.shared)
            .environmentObject(EventTapManager.shared)
            .environmentObject(LaunchAtLogin.shared)
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = resizable
            ? [.titled, .closable, .miniaturizable, .resizable]
            : [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(controller.view.fittingSize)
        window.center()
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
