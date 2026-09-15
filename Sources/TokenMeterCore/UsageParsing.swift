import Foundation

public enum UsageParsing {
    private struct CodexResponse: Decodable {
        let rateLimits: Bucket?
        let rateLimitsByLimitId: [String: Bucket]?
    }
    private struct Bucket: Decodable {
        let limitId: String?
        let primary: Window?
        let secondary: Window?
    }
    private struct Window: Decodable {
        let usedPercent: Double?
        let windowDurationMins: Int?
        let resetsAt: Double?
        var mapped: UsageWindow? {
            guard let minutes = windowDurationMins, minutes > 0,
                  let percent = usedPercent, percent.isFinite, (0...100).contains(percent) else { return nil }
            return UsageWindow(minutes: minutes, usedPercent: percent, resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:)))
        }
    }
    public static func codex(_ data: Data, now: Date) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(CodexResponse.self, from: data)
        let bucket: Bucket?
        if let buckets = response.rateLimitsByLimitId {
            bucket = buckets["codex"] // Never substitute another model bucket.
        } else if response.rateLimits?.limitId == nil || response.rateLimits?.limitId == "codex" {
            bucket = response.rateLimits
        } else { bucket = nil }
        guard let bucket else { throw UsageFailure.unavailable("Codex account quota bucket unavailable.") }
        let windows = [bucket.primary?.mapped, bucket.secondary?.mapped].compactMap { $0 }
        let short = windows.filter { $0.minutes < 10080 }.sorted { $0.minutes < $1.minutes }.first
        return UsageSnapshot(shortTerm: short, weekly: windows.first { $0.minutes == 10080 }, fetchedAt: now)
    }
    private struct ClaudeResponse: Decodable {
        let five_hour: ClaudeWindow?
        let seven_day: ClaudeWindow?
    }
    private struct ClaudeWindow: Decodable {
        let utilization: Double?
        let resets_at: String?
        func mapped(minutes: Int) -> UsageWindow? {
            guard let percent = utilization, percent.isFinite, (0...100).contains(percent) else { return nil }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date = resets_at.flatMap { fractional.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            return UsageWindow(minutes: minutes, usedPercent: percent, resetsAt: date)
        }
    }
    public static func claude(_ data: Data, now: Date) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        return UsageSnapshot(shortTerm: response.five_hour?.mapped(minutes: 300),
                             weekly: response.seven_day?.mapped(minutes: 10080), fetchedAt: now)
    }
    public static func retryDate(_ header: String?, now: Date) -> Date {
        if let header, let seconds = Double(header), seconds.isFinite {
            return now.addingTimeInterval(max(60, seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let header, let date = formatter.date(from: header) { return max(date, now.addingTimeInterval(60)) }
        return now.addingTimeInterval(300)
    }
}
