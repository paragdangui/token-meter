import Foundation

public enum ProviderID: String, CaseIterable, Sendable {
    case claude, codex
    public var title: String { self == .claude ? "Claude Code" : "ChatGPT (Codex)" }
    public var signIn: String { self == .claude ? "Run claude auth login in Terminal." : "Sign in to Codex with ChatGPT." }
}

public struct UsageWindow: Equatable, Sendable {
    public let minutes: Int
    public let usedPercent: Double
    public let resetsAt: Date?
    public init(minutes: Int, usedPercent: Double, resetsAt: Date? = nil) {
        self.minutes = minutes; self.usedPercent = usedPercent; self.resetsAt = resetsAt
    }
    public var label: String {
        if minutes == 10080 { return "Weekly" }
        if minutes == 1440 { return "Daily" }
        let duration = minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes)m"
        return "Session (\(duration))"
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public let shortTerm: UsageWindow?
    public let weekly: UsageWindow?
    public let fetchedAt: Date
    public init(shortTerm: UsageWindow?, weekly: UsageWindow?, fetchedAt: Date) {
        self.shortTerm = shortTerm; self.weekly = weekly; self.fetchedAt = fetchedAt
    }
    public var isComplete: Bool { shortTerm != nil && weekly != nil }
}

public enum UsageFailure: Error, Equatable, Sendable {
    case signedOut, unavailable(String), timeout, throttled(Date)
    public func message(for provider: ProviderID) -> String {
        switch self {
        case .signedOut: return provider.signIn
        case .unavailable(let message): return message
        case .timeout: return "Request timed out. Will retry."
        case .throttled(let date): return "Rate limited until \(date.formatted(date: .omitted, time: .shortened))."
        }
    }
}

public struct ProviderState: Sendable {
    public var snapshot: UsageSnapshot?
    public var failure: UsageFailure?
    public var isLoading = false
    public var retryAt: Date?
    public init() {}
    public func isStale(at now: Date) -> Bool {
        guard let snapshot else { return false }
        return failure != nil || now.timeIntervalSince(snapshot.fetchedAt) > 120
    }
}
