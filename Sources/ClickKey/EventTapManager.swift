import AppKit
import ApplicationServices
import CoreGraphics

/// C callback; the tap's run loop source is on the main run loop, so this runs on the main thread.
private let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.handle(type: type, event: event)
}

/// Owns the CGEventTap and the Accessibility trust polling.
///
/// Threading: everything here (tap callback, timer, SwiftUI updates) runs on the main
/// thread, so `activeMappings` is a plain value snapshot replaced wholesale by the store.
final class EventTapManager: ObservableObject {
    static let shared = EventTapManager()

    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var isRunning = false
    /// Shown ~10s after "Open System Settings" if the grant still hasn't been picked up.
    @Published private(set) var showRestartHint = false

    /// Snapshot of enabled mappings: button number -> action. Empty when globally disabled.
    var activeMappings: [Int: KeyAction] = [:]

    private var captureHandler: ((Int) -> Void)?
    /// Buttons whose down event we swallowed; their drag/up events are swallowed too.
    private var swallowed = Set<Int>()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pollTimer: Timer?
    private var loggedFailure = false
    private var accessibilityObserver: NSObjectProtocol?
    /// The tap was created while AXIsProcessTrusted() still reported false (stale cache).
    private var tapVerifiedWithoutAX = false
    private var settingsOpenedAt: Date?

    // MARK: Trust polling

    func startMonitoring() {
        poll()
        if accessibilityObserver == nil {
            // Posted when any app's Accessibility grant changes; AX state can lag, so recheck twice.
            accessibilityObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.accessibility.api"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                for delay in [0.5, 1.5] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.poll() }
                }
            }
        }
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        let axTrusted = AXIsProcessTrusted()
        if axTrusted { tapVerifiedWithoutAX = false }
        if !axTrusted, tap != nil, !tapVerifiedWithoutAX {
            // Revoked (or AX flickered): drop the tap and let the liveness test below decide.
            stopTap()
        }
        if tap == nil {
            // Also a liveness test: tapCreate succeeds once access is really granted,
            // even when AXIsProcessTrusted() hasn't caught up yet.
            let started = startTap(logFailure: axTrusted)
            tapVerifiedWithoutAX = started && !axTrusted
        } else if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            // Backstop in case a disable notification was missed.
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        let trusted = axTrusted || tap != nil
        if trusted != isTrusted { isTrusted = trusted }

        let hint = !isRunning && settingsOpenedAt.map { Date().timeIntervalSince($0) >= 10 } == true
        if hint != showRestartHint { showRestartHint = hint }
    }

    func requestAccessibility() {
        if settingsOpenedAt == nil { settingsOpenedAt = Date() }
        // Literal value of kAXTrustedCheckOptionPrompt (avoids Unmanaged/CFString import differences).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Capture (for "Add Mapping")

    func beginCapture(_ handler: @escaping (Int) -> Void) { captureHandler = handler }
    func endCapture() { captureHandler = nil }

    // MARK: Tap lifecycle

    @discardableResult
    private func startTap(logFailure: Bool) -> Bool {
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            if logFailure, !loggedFailure {
                NSLog("ClickKey: CGEvent.tapCreate failed. Try removing and re-adding ClickKey in Accessibility settings.")
                loggedFailure = true
            }
            if isRunning { isRunning = false }
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        loggedFailure = false
        isRunning = true
        return true
    }

    private func stopTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        swallowed.removeAll()
        isRunning = false
    }

    // MARK: Event handling

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass

        case .otherMouseDown:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            swallowed.remove(button) // clear any stale state from a missed up event
            if let handler = captureHandler {
                swallowed.insert(button)
                DispatchQueue.main.async { handler(button) }
                return nil
            }
            guard let action = activeMappings[button] else { return pass }
            swallowed.insert(button)
            action.perform()
            return nil

        case .otherMouseDragged:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            return swallowed.contains(button) ? nil : pass

        case .otherMouseUp:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            return swallowed.remove(button) != nil ? nil : pass

        default:
            return pass
        }
    }
}
