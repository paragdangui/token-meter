import AppKit
import SwiftUI
import TokenMeterCore

/// UserDefaults keys for which providers appear in the menu bar item. This display preference
/// is the only persisted state; usage data is never stored.
enum MenuBarVisibility {
    static let showClaude = "menuBar.showClaude"
    static let showCodex = "menuBar.showCodex"
}

/// Menu bar item: per visible provider, an initial and "session/weekly" percentages, e.g. `C 12%/2%`.
/// Rendered to an image so each provider can be dimmed independently when stale and each
/// percentage colored by its usage level, which a plain MenuBarExtra Text label can't do.
struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore
    @AppStorage(MenuBarVisibility.showClaude) private var showClaude = true
    @AppStorage(MenuBarVisibility.showCodex) private var showCodex = true
    var body: some View {
        let visible = ProviderID.allCases.filter { $0 == .claude ? showClaude : showCodex }
        if visible.isEmpty {
            // Keep something clickable so the panel (and these toggles) stay reachable.
            Image(systemName: "gauge.with.dots.needle.50percent").accessibilityLabel("Token Meter")
        } else {
            Image(nsImage: Self.render(store.states, providers: visible, now: Date()))
                .accessibilityLabel(visible.map { id in
                    let snapshot = store.states[id]?.snapshot
                    return "\(id.title): session \(Self.percent(snapshot?.shortTerm)), weekly \(Self.percent(snapshot?.weekly))"
                }.joined(separator: "; "))
        }
    }

    private static func percent(_ window: UsageWindow?) -> String {
        window.map { "\(Int($0.usedPercent.rounded()))%" } ?? "–"
    }

    /// Colored text can't be a template image, so both appearances are rasterized and the
    /// menu bar button's own appearance picks one at draw time (it follows the wallpaper, not the app).
    private static func render(_ states: [ProviderID: ProviderState], providers: [ProviderID], now: Date) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let light = rasterize(states, providers: providers, now: now, dark: false, scale: scale),
              let dark = rasterize(states, providers: providers, now: now, dark: true, scale: scale) else { return NSImage() }
        let size = NSSize(width: CGFloat(light.width) / scale, height: CGFloat(light.height) / scale)
        return NSImage(size: size, flipped: false) { rect in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            NSGraphicsContext.current?.cgContext.draw(isDark ? dark : light, in: rect)
            return true
        }
    }

    private static func rasterize(_ states: [ProviderID: ProviderState], providers: [ProviderID], now: Date, dark: Bool, scale: CGFloat) -> CGImage? {
        let content = HStack(spacing: 7) {
            ForEach(providers, id: \.self) { id in
                let state = states[id] ?? ProviderState()
                HStack(spacing: 3) {
                    Text(id == .claude ? "C" : "G").font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 0) {
                        coloredPercent(state.snapshot?.shortTerm, dark: dark)
                        Text("/")
                        coloredPercent(state.snapshot?.weekly, dark: dark)
                    }
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                }
                // Stale values stay visible but dimmed, matching the panel's "Stale" marking.
                .opacity(state.isStale(at: now) ? 0.45 : 1)
            }
        }
        .foregroundStyle(.primary)
        .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        return renderer.cgImage
    }

    private static func coloredPercent(_ window: UsageWindow?, dark: Bool) -> some View {
        Text(percent(window)).foregroundStyle(window?.level.tint(dark: dark) ?? .primary)
    }
}
