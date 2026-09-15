import Foundation
import Combine

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    /// Implementations must bound all network and helper operations.
    func fetch() async throws -> UsageSnapshot
}

@MainActor public final class UsageStore: ObservableObject {
    @Published public private(set) var states: [ProviderID: ProviderState] = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, ProviderState()) })
    @Published public private(set) var isRefreshing = false
    private let providers: [any UsageProvider]
    private let now: () -> Date
    private let sleep: (UInt64) async throws -> Void
    private var timer: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var generation = 0
    public init(providers: [any UsageProvider], now: @escaping () -> Date = Date.init,
                sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.providers = providers; self.now = now; self.sleep = sleep
    }
    public func start() {
        guard timer == nil else { return }
        reload()
        timer = Task { [weak self, sleep] in
            while !Task.isCancelled {
                do { try await sleep(60_000_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                self?.reload()
            }
        }
    }
    public func suspend() { timer?.cancel(); timer = nil }
    public func wake() { suspend(); start() }
    public func stop() {
        suspend(); generation += 1
        refreshTask?.cancel(); refreshTask = nil; isRefreshing = false
        for id in ProviderID.allCases { states[id]?.isLoading = false }
    }
    public func reload() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            self.refreshTask = nil
        }
    }
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let currentGeneration = generation
        let due = providers.filter { (states[$0.id]?.retryAt ?? .distantPast) <= now() }
        for provider in due { states[provider.id]?.isLoading = true }
        await withTaskGroup(of: (ProviderID, Result<UsageSnapshot, UsageFailure>).self) { group in
            for provider in due {
                group.addTask {
                    do { return (provider.id, .success(try await provider.fetch())) }
                    catch let error as UsageFailure { return (provider.id, .failure(error)) }
                    catch { return (provider.id, .failure(.unavailable("Usage unavailable. Will retry."))) }
                }
            }
            for await (id, result) in group {
                guard currentGeneration == generation, !Task.isCancelled else { continue }
                states[id]?.isLoading = false
                switch result {
                case .success(let snapshot):
                    states[id]?.snapshot = snapshot; states[id]?.failure = nil; states[id]?.retryAt = nil
                case .failure(let failure):
                    states[id]?.failure = failure
                    if case .throttled(let date) = failure { states[id]?.retryAt = date }
                }
            }
        }
        if currentGeneration == generation { isRefreshing = false }
    }
}
