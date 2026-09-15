import AppKit
import SwiftUI
import TokenMeterCore

@main struct TokenMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra {
            UsageView(store: delegate.store)
        } label: {
            MenuBarLabel(store: delegate.store)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore(providers: [ClaudeProvider(), CodexProvider()])
    private var observers: [NSObjectProtocol] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.store.wake() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.store.suspend() }
        })
        store.start()
    }
    func applicationWillTerminate(_ notification: Notification) {
        store.stop(); HelperProcesses.shared.stop()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
