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
        // onAppear doesn't re-fire when the reused window is reopened.
        LaunchAtLogin.shared.refresh()
        show(id: Self.settingsID, title: "ClickKey Settings", resizable: true) { SettingsView() }
    }

    func showOnboarding() {
        show(id: Self.onboardingID, title: "Welcome to ClickKey", resizable: false) { OnboardingView() }
    }

    func close(_ id: String) {
        windows[id]?.close()
    }

    /// Closes onboarding and opens Settings; no-op if onboarding was already dismissed.
    func finishOnboarding() {
        guard windows[Self.onboardingID]?.isVisible == true else { return }
        close(Self.onboardingID)
        showSettings()
    }

    /// Relaunches the app; a fresh process picks up an Accessibility grant the old one missed.
    func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Bundle path is passed as $0 to avoid quoting issues; the delay lets us exit first.
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open -n \"$0\"", Bundle.main.bundlePath]
        do {
            try task.run()
        } catch {
            NSLog("ClickKey: relaunch failed: \(error)")
            return
        }
        NSApp.terminate(nil)
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
