import AppKit
import SwiftUI

/// `ClickKey --snapshot <dir>` renders the settings and onboarding views to PNG and exits.
/// No Screen Recording permission needed since nothing is captured from the screen.
///
/// Writes `<name>.png` via ImageRenderer (scale 2). ImageRenderer draws some AppKit-backed
/// controls (Form, switches, menus) as placeholders on macOS, so `<name>-appkit.png` is also
/// written by drawing an offscreen NSHostingView at 2x.
@MainActor
enum SnapshotRenderer {
    static func requestedDirectory(from arguments: [String] = CommandLine.arguments) -> URL? {
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    static func run(to dir: URL) {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("Cannot create \(dir.path): \(error.localizedDescription)\n".utf8))
            return
        }

        let sample = MappingStore(sample: [
            Mapping(button: 2, action: .media(.playPause)),
            Mapping(button: 3, action: .defaultAction),
            Mapping(button: 4, action: .key(code: 6, modifiers: [.command, .shift]), enabled: false),
        ])
        let settings = SettingsView()
            .environmentObject(sample)
            .environmentObject(EventTapManager.shared)
            .environmentObject(LaunchAtLogin.shared)
        let onboarding = OnboardingView()
            .environmentObject(EventTapManager.shared)

        render(settings, size: CGSize(width: 560, height: 520), name: "settings", in: dir)
        render(onboarding, size: nil, name: "onboarding", in: dir)
    }

    private static func render<V: View>(_ view: V, size: CGSize?, name: String, in dir: URL) {
        let content = view
            .frame(width: size?.width, height: size?.height)
            .background(Color(nsColor: .windowBackgroundColor))

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        if let cgImage = renderer.cgImage {
            write(NSBitmapImageRep(cgImage: cgImage), to: dir.appendingPathComponent("\(name).png"))
        }

        let host = NSHostingView(rootView: content)
        let pointSize = size ?? host.fittingSize
        host.frame = NSRect(origin: .zero, size: pointSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pointSize.width * 2),
            pixelsHigh: Int(pointSize.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }
        rep.size = pointSize
        host.cacheDisplay(in: host.bounds, to: rep)
        write(rep, to: dir.appendingPathComponent("\(name)-appkit.png"))
    }

    private static func write(_ rep: NSBitmapImageRep, to url: URL) {
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: url)
            print(url.path)
        } catch {
            FileHandle.standardError.write(Data("Failed to write \(url.path): \(error.localizedDescription)\n".utf8))
        }
    }
}
