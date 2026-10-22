import Foundation
import ServiceManagement

struct Mapping: Codable, Identifiable, Hashable {
    var id = UUID()
    var button: Int
    var action: KeyAction = .defaultAction
    var enabled = true
}

enum ButtonNames {
    static func name(for button: Int) -> String {
        switch button {
        case 0: return "Left"
        case 1: return "Right"
        case 2: return "Middle"
        case 3: return "Button 4 (Back)"
        case 4: return "Button 5 (Forward)"
        default: return "Button \(button + 1)"
        }
    }
}

/// Mappings + global on/off, persisted to UserDefaults as JSON.
final class MappingStore: ObservableObject {
    static let shared = MappingStore(defaults: .standard)

    private static let mappingsKey = "mappings"
    private static let enabledKey = "globalEnabled"

    @Published var mappings: [Mapping] { didSet { persistAndPublish() } }
    @Published var globalEnabled: Bool { didSet { persistAndPublish() } }

    /// Called with a fresh button -> action snapshot whenever anything changes.
    var onChange: (([Int: KeyAction]) -> Void)?

    private let defaults: UserDefaults?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        var loaded: [Mapping] = []
        if let data = defaults.data(forKey: Self.mappingsKey),
           let decoded = try? JSONDecoder().decode([Mapping].self, from: data) {
            loaded = decoded
        }
        self.mappings = loaded
        self.globalEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// In-memory store (used for --snapshot).
    init(sample: [Mapping]) {
        self.defaults = nil
        self.mappings = sample
        self.globalEnabled = true
    }

    var activeMap: [Int: KeyAction] {
        guard globalEnabled else { return [:] }
        return Dictionary(
            mappings.filter(\.enabled).map { ($0.button, $0.action) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func add(button: Int) {
        guard !mappings.contains(where: { $0.button == button }) else { return }
        var updated = mappings
        updated.append(Mapping(button: button))
        updated.sort { $0.button < $1.button }
        mappings = updated
    }

    func update(_ mapping: Mapping) {
        guard let index = mappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        mappings[index] = mapping
    }

    func remove(id: UUID) {
        mappings.removeAll { $0.id == id }
    }

    private func persistAndPublish() {
        if let defaults {
            if let data = try? JSONEncoder().encode(mappings) {
                defaults.set(data, forKey: Self.mappingsKey)
            }
            defaults.set(globalEnabled, forKey: Self.enabledKey)
        }
        onChange?(activeMap)
    }
}

/// Launch at login via SMAppService (macOS 13+).
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    @Published private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    @Published private(set) var errorMessage: String?

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "Couldn't \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
        }
        refresh()
    }
}
