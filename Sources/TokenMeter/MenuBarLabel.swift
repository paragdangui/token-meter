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
/// Rendered to a template image so each provider can be dimmed independently when stale,
/// which a plain MenuBarExtra Text label can't do.
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

    private static func render(_ states: [ProviderID: ProviderState], providers: [ProviderID], now: Date) -> NSImage {
        let content = HStack(spacing: 7) {
            ForEach(providers, id: \.self) { id in
                let state = states[id] ?? ProviderState()
                HStack(spacing: 3) {
                    Text(id == .claude ? "C" : "G").font(.system(size: 13, weight: .semibold))
                    Text("\(percent(state.snapshot?.shortTerm))/\(percent(state.snapshot?.weekly))")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                }
                // Stale values stay visible but dimmed, matching the panel's "Stale" marking.
                .opacity(state.isStale(at: now) ? 0.45 : 1)
            }
        }
        .foregroundStyle(.black)
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }
}
