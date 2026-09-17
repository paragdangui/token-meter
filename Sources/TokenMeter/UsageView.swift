import SwiftUI
import AppKit
import TokenMeterCore

struct UsageView: View {
    @ObservedObject var store: UsageStore
    @AppStorage(MenuBarVisibility.showClaude) private var showClaude = true
    @AppStorage(MenuBarVisibility.showCodex) private var showCodex = true
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(nsImage: TokenMeterLogo.image(size: 36))
                        .accessibilityHidden(true)
                    Text("Token Meter").font(.title3.weight(.semibold))
                    Spacer()
                }
                Divider()
                ForEach(ProviderID.allCases, id: \.self) { id in
                    section(id, now: context.date)
                    if id == .claude { Divider() }
                }
                Divider()
                HStack(spacing: 12) {
                    Text("Show in menu bar").foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Claude", isOn: $showClaude)
                    Toggle("Codex", isOn: $showCodex)
                }
                .toggleStyle(.checkbox).font(.subheadline)
                HStack {
                    if store.isRefreshing { ProgressView().controlSize(.small); Text("Refreshing…").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Reload") { store.reload() }.disabled(store.isRefreshing)
                    Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
                }
            }
            .padding(16).frame(width: 340)
        }
    }
    private func section(_ id: ProviderID, now: Date) -> some View {
        let state = store.states[id] ?? ProviderState()
        return VStack(alignment: .leading, spacing: 8) {
            Text(id.title).font(.headline)
            meter(state.snapshot?.shortTerm, placeholder: "Session", now: now)
            meter(state.snapshot?.weekly, placeholder: "Weekly", now: now)
            if let snapshot = state.snapshot {
                Text("\(state.isStale(at: now) ? "Stale · " : "")Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(state.isStale(at: now) ? Color.orange : Color.secondary)
                    .help(snapshot.fetchedAt.formatted(date: .abbreviated, time: .standard))
            }
            if state.isLoading && state.snapshot == nil {
                Text("Loading…").font(.caption).foregroundStyle(.secondary)
            } else if let failure = state.failure {
                Text(failure.message(for: id)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if state.snapshot?.isComplete != true {
                Text("Some quota windows are unavailable.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func meter(_ window: UsageWindow?, placeholder: String, now: Date) -> some View {
        let tint = window?.level.tint(dark: colorScheme == .dark)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window?.label ?? placeholder)
                Spacer()
                Text(window.map { "\(Int($0.usedPercent.rounded()))% used" } ?? "Unavailable")
                    .monospacedDigit().foregroundStyle(tint ?? .secondary)
            }.font(.subheadline)
            if let window {
                ProgressView(value: min(window.usedPercent, 100), total: 100)
                    .tint(tint ?? .accentColor)
                    .accessibilityLabel(window.label)
                    .accessibilityValue("\(Int(window.usedPercent.rounded())) percent used")
                    .help(window.resetsAt.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Reset time unavailable")
            } else {
                Capsule().fill(Color.secondary.opacity(0.15)).frame(height: 4)
                    .accessibilityLabel("\(placeholder) usage unavailable")
            }
            Text(window?.resetCountdown(at: now).map { "Resets in \($0)" } ?? "Reset time unavailable")
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
