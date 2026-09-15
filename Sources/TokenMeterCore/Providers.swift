import Foundation

public struct CodexProvider: UsageProvider {
    public let id = ProviderID.codex
    public init() {}
    private static func executable() throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [ProcessInfo.processInfo.environment["TOKEN_METER_CODEX_PATH"],
                     "/Applications/ChatGPT.app/Contents/Resources/codex",
                     "/Applications/Codex.app/Contents/Resources/codex",
                     home + "/Applications/ChatGPT.app/Contents/Resources/codex",
                     home + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        if let path = paths.compactMap({ $0 }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return path }
        throw UsageFailure.unavailable("Install Codex, then reopen Token Meter.")
    }
    public func fetch() async throws -> UsageSnapshot {
        try await blocking {
            let helper = try HelperProcess(path: Self.executable(), arguments: ["app-server", "-c", "analytics.enabled=false"], timeout: 25)
            defer { helper.close() }
            try helper.send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "token_meter", "version": "1.0.0"]]])
            _ = try helper.response(id: 1)
            try helper.send(["method": "initialized", "params": [:]])
            try helper.send(["id": 2, "method": "account/read", "params": [:]])
            let account = try helper.response(id: 2)
            guard let detail = account["account"] as? [String: Any], detail["type"] as? String == "chatgpt" else { throw UsageFailure.signedOut }
            try helper.send(["id": 3, "method": "account/rateLimits/read", "params": [:]])
            let result = try helper.response(id: 3)
            return try UsageParsing.codex(JSONSerialization.data(withJSONObject: result), now: Date())
        }
    }
}

/// Validated against Claude Code 2.1.247. This OAuth endpoint and Keychain format
/// are undocumented, so keep all knowledge of them in this adapter.
public struct ClaudeProvider: UsageProvider {
    public let id = ProviderID.claude
    public init() {}
    public func fetch() async throws -> UsageSnapshot {
        let token: String = try await blocking {
            let helper = try HelperProcess(path: "/usr/bin/security", arguments: ["find-generic-password", "-s", "Claude Code-credentials", "-w"], timeout: 8)
            defer { helper.close() }
            let data = try helper.readToEnd()
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let oauth = object["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String, !token.isEmpty else { throw UsageFailure.signedOut }
            if let expiry = oauth["expiresAt"] as? Double, expiry / 1000 <= Date().timeIntervalSince1970 { throw UsageFailure.signedOut }
            return token
        }
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 20
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 25
        config.httpCookieStorage = nil; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UsageFailure.unavailable("Invalid Claude response.") }
            if http.statusCode == 401 || http.statusCode == 403 { throw UsageFailure.signedOut }
            if http.statusCode == 429 || (http.statusCode == 503 && http.value(forHTTPHeaderField: "Retry-After") != nil) {
                throw UsageFailure.throttled(UsageParsing.retryDate(http.value(forHTTPHeaderField: "Retry-After"), now: Date()))
            }
            guard http.statusCode == 200 else { throw UsageFailure.unavailable("Claude usage unavailable (HTTP \(http.statusCode)).") }
            return try UsageParsing.claude(data, now: Date())
        } catch let error as URLError where error.code == .timedOut { throw UsageFailure.timeout }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
