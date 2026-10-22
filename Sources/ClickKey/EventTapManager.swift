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

    /// Snapshot of enabled mappings: button number -> action. Empty when globally disabled.
    var activeMappings: [Int: KeyAction] = [:]

    private var captureHandler: ((Int) -> Void)?
    /// Buttons whose down event we swallowed; their drag/up events are swallowed too.
    private var swallowed = Set<Int>()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pollTimer: Timer?
    private var loggedFailure = false

    // MARK: Trust polling

    func startMonitoring() {
        poll()
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
        if trusted, tap == nil {
            startTap()
        } else if !trusted, tap != nil {
            stopTap()
        } else if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            // Backstop in case a disable notification was missed.
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func requestAccessibility() {
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

    private func startTap() {
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
            if !loggedFailure {
                NSLog("ClickKey: CGEvent.tapCreate failed. Try removing and re-adding ClickKey in Accessibility settings.")
                loggedFailure = true
            }
            if isRunning { isRunning = false }
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        loggedFailure = false
        isRunning = true
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
