import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Menu bar

struct MenuContent: View {
    @EnvironmentObject var store: MappingStore
    @EnvironmentObject var tap: EventTapManager

    var body: some View {
        Toggle("Enabled", isOn: $store.globalEnabled)
        Button("Settings…") { WindowManager.shared.showSettings() }
            .keyboardShortcut(",")
        Divider()
        Button(accessibilityTitle) { WindowManager.shared.showOnboarding() }
        Divider()
        Button("Quit ClickKey") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var accessibilityTitle: String {
        if tap.isRunning { return "Accessibility: Granted ✓" }
        if tap.isTrusted { return "Accessibility: Granted, tap failed…" }
        return "Accessibility: Not Granted…"
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: MappingStore
    @EnvironmentObject var tap: EventTapManager
    @EnvironmentObject var login: LaunchAtLogin
    @State private var showingCapture = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable ClickKey", isOn: $store.globalEnabled)
                LabeledContent("Accessibility") { AccessibilityBadge() }
                Toggle("Launch at login", isOn: Binding(
                    get: { login.isEnabled },
                    set: { login.setEnabled($0) }
                ))
                if login.status == .requiresApproval {
                    LabeledContent {
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    } label: {
                        Text("Approve ClickKey in System Settings › General › Login Items.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = login.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section {
                if store.mappings.isEmpty {
                    Text("No mappings yet. Click “Add Mapping…” and press a mouse button.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.mappings) { mapping in
                    MappingRow(mapping: binding(for: mapping.id)) {
                        store.remove(id: mapping.id)
                    }
                }
            } header: {
                Text("Mappings")
            } footer: {
                HStack {
                    Text("ClickKey \(appVersion) · Fully local: no network, no telemetry.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Mapping…") { showingCapture = true }
                }
                .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
        // Size to content: the grouped Form is a scroll view whose ideal height would
        // otherwise be the fixed frame, leaving empty space below the last section.
        .scrollDisabled(true)
        .frame(minWidth: 540, idealWidth: 560)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $showingCapture) {
            CaptureSheet(existing: Set(store.mappings.map(\.button))) { store.add(button: $0) }
                .environmentObject(tap)
        }
        .onAppear { login.refresh() }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// Bind by id rather than index so deleting a row can't index out of range.
    private func binding(for id: UUID) -> Binding<Mapping> {
        Binding(
            get: { store.mappings.first(where: { $0.id == id }) ?? Mapping(button: 2) },
            set: { store.update($0) }
        )
    }
}

struct AccessibilityBadge: View {
    @EnvironmentObject var tap: EventTapManager

    var body: some View {
        if tap.isRunning {
            Label("Active", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if tap.isTrusted {
            Button {
                WindowManager.shared.showOnboarding()
            } label: {
                Label("Granted, but not working…", systemImage: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.orange)
        } else {
            Button("Grant Access…") { WindowManager.shared.showOnboarding() }
        }
    }
}

struct MappingRow: View {
    @Binding var mapping: Mapping
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Enabled", isOn: $mapping.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            Group {
                Label(ButtonNames.name(for: mapping.button), systemImage: "computermouse")
                    .frame(minWidth: 160, alignment: .leading)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
            }
            .opacity(mapping.enabled ? 1 : 0.5)
            ActionPicker(action: $mapping.action)
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete mapping")
        }
    }
}

struct ActionPicker: View {
    @Binding var action: KeyAction
    @State private var recording = false

    var body: some View {
        if recording {
            ShortcutRecorder(
                onRecord: { action = $0; recording = false },
                onCancel: { recording = false }
            )
        } else {
            Menu {
                Section("Keys") {
                    ForEach(ActionPreset.keys) { preset in
                        Button(preset.title) { action = preset.action }
                    }
                }
                Section("Media") {
                    ForEach(MediaKey.allCases) { key in
                        Button {
                            action = .media(key)
                        } label: {
                            Label(key.title, systemImage: key.systemImage)
                        }
                    }
                }
                Divider()
                Button("Record shortcut…") { recording = true }
            } label: {
                Text(action.displayName)
            }
            .fixedSize()
        }
    }
}

/// Captures the next key combo typed while the settings window is key.
struct ShortcutRecorder: View {
    let onRecord: (KeyAction) -> Void
    let onCancel: () -> Void
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "record.circle")
                .foregroundStyle(.red)
            Text("Type shortcut…")
                .foregroundStyle(.secondary)
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Cancel (Esc)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
        )
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let modifiers = KeyModifiers(event.modifierFlags)
                if event.keyCode == KeyCode.escape && modifiers.isEmpty {
                    onCancel()
                } else if !event.isARepeat {
                    onRecord(.key(code: event.keyCode, modifiers: modifiers))
                }
                return nil
            }
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

// MARK: - Capture sheet

struct CaptureSheet: View {
    let existing: Set<Int>
    let onAdd: (Int) -> Void

    @EnvironmentObject var tap: EventTapManager
    @Environment(\.dismiss) private var dismiss
    @State private var detected: Int?
    @State private var note: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "computermouse")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("Press the mouse button you want")
                .font(.title3.weight(.semibold))
            Text(detected.map { "Detected: \(ButtonNames.name(for: $0))" } ?? "Waiting for a button press…")
                .font(.headline)
                .foregroundStyle(detected == nil ? Color.secondary : Color.primary)
            if let note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Text("Works with middle, back, forward and extra buttons. Left and right clicks can't be remapped.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !tap.isRunning {
                Text("Tip: without Accessibility access, press the button while the pointer is over this window.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    if let detected { onAdd(detected) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(detected == nil || existing.contains(detected ?? -1))
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            // The event tap sees buttons even when we're not focused (and swallows them);
            // the local monitor covers the case where the tap isn't running yet.
            tap.beginCapture { handle(button: $0) }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .rightMouseDown]) { event in
                handle(button: event.buttonNumber)
                return nil
            }
        }
        .onDisappear {
            tap.endCapture()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }

    private func handle(button: Int) {
        guard button >= 2 else {
            note = "Left and right clicks can't be remapped — try another button."
            return
        }
        detected = button
        note = existing.contains(button) ? "\(ButtonNames.name(for: button)) is already mapped." : nil
    }
}

// MARK: - Accessibility onboarding

struct OnboardingView: View {
    @EnvironmentObject var tap: EventTapManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "computermouse")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to ClickKey")
                        .font(.title2.weight(.semibold))
                    Text("Turn extra mouse buttons into keystrokes.")
                        .foregroundStyle(.secondary)
                }
            }

            Text("ClickKey needs **Accessibility** access to see mouse button presses and send keystrokes on your behalf. Everything stays on your Mac — no network, no telemetry.")
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    step(1, "Click “Open System Settings”.")
                    step(2, "Turn on ClickKey under Privacy & Security › Accessibility.")
                    step(3, "Come back here — ClickKey starts automatically.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            Group {
                if tap.isRunning {
                    Label("Accessibility granted — ClickKey is active.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if tap.isTrusted {
                    Label("Permission looks granted, but the event tap couldn't start. Re-grant as described below.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for permission…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Text("Rebuilt or updated the app? macOS ties the permission to the app's code signature. If ClickKey is listed but doesn't work, select it, remove it with “–”, then add it again (or toggle it off and on).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Close") { WindowManager.shared.close(WindowManager.onboardingID) }
                    .keyboardShortcut(.cancelAction)
                Button("Open System Settings") { tap.requestAccessibility() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(tap.isRunning)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(text)
        }
    }
}
