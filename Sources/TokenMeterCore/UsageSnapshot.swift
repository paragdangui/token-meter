import Foundation

public enum ProviderID: String, CaseIterable, Sendable {
    case claude, codex
    public var title: String { self == .claude ? "Claude Code" : "ChatGPT (Codex)" }
    public var signIn: String { self == .claude ? "Run claude auth login in Terminal." : "Sign in to Codex with ChatGPT." }
    public var refreshSignIn: String { self == .claude ? "Claude sign-in token expired. Run claude once in Terminal to refresh it." : signIn }
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
    /// Based on the rounded value so the color always agrees with the percentage shown.
    public var level: UsageLevel { UsageLevel(usedPercent: usedPercent.rounded()) }
}

/// How close a window is to its limit, for color-coding. Yellow, orange, red in the UI.
public enum UsageLevel: Int, Comparable, Sendable {
    case normal, elevated, high, critical
    public init(usedPercent: Double) {
        switch usedPercent {
        case 90...: self = .critical
        case 75..<90: self = .high
        case 50..<75: self = .elevated
        default: self = .normal
        }
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
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
    /// `signInExpired`: credentials exist but the provider's own client has not refreshed them yet.
    case signedOut, signInExpired, unavailable(String), timeout, throttled(Date)
    public func message(for provider: ProviderID) -> String {
        switch self {
        case .signedOut: return provider.signIn
        case .signInExpired: return provider.refreshSignIn
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
