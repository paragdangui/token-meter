import Foundation
import Testing
@testable import TokenMeterCore

final class UsageParsingTests {
    let now = Date(timeIntervalSince1970: 1000)
    func data(_ json: String) -> Data { Data(json.utf8) }
    @Test func testKeyedCodexBucketAndReversedWindows() throws {
        let snapshot = try UsageParsing.codex(data("""
        {"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":300}},
         "rateLimitsByLimitId":{"other":{"primary":{"usedPercent":88,"windowDurationMins":300}},
         "codex":{"primary":{"usedPercent":14,"windowDurationMins":10080,"resetsAt":2000},
                    "secondary":{"usedPercent":86,"windowDurationMins":300}}}}
        """), now: now)
        XCTAssertEqual(snapshot.shortTerm?.usedPercent, 86)
        XCTAssertEqual(snapshot.shortTerm?.label, "Session (5h)")
        XCTAssertEqual(snapshot.weekly?.usedPercent, 14)
        XCTAssertEqual(snapshot.weekly?.resetsAt, Date(timeIntervalSince1970: 2000))
    }
    @Test func testMissingCodexBucketDoesNotFallBack() {
        XCTAssertThrowsError(try UsageParsing.codex(data("""
        {"rateLimits":{"limitId":"codex"},"rateLimitsByLimitId":{"other":{}}}
        """), now: now))
    }
    @Test func testMissingNullInvalidAndUnknownWindows() throws {
        for json in ["{}", "{\"rateLimits\":{}}", "{\"rateLimits\":{\"primary\":null}}"] {
            if json == "{}" { XCTAssertThrowsError(try UsageParsing.codex(data(json), now: now)); continue }
            let snapshot = try UsageParsing.codex(data(json), now: now)
            XCTAssertNil(snapshot.shortTerm); XCTAssertNil(snapshot.weekly)
        }
        let snapshot = try UsageParsing.codex(data("""
        {"rateLimits":{"primary":{"usedPercent":5,"windowDurationMins":null},
                       "secondary":{"usedPercent":-1,"windowDurationMins":10080}}}
        """), now: now)
        XCTAssertFalse(snapshot.isComplete)
        XCTAssertNil(snapshot.shortTerm); XCTAssertNil(snapshot.weekly)
    }
    @Test func testDailyOnlyWhenDurationIsDaily() throws {
        let snapshot = try UsageParsing.codex(data("""
        {"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":1440}}}
        """), now: now)
        XCTAssertEqual(snapshot.shortTerm?.label, "Daily")
        XCTAssertEqual(UsageWindow(minutes: 15, usedPercent: 2).label, "Session (15m)")
    }
    @Test func testClaudeUsedNotRemainingAndNullNotZero() throws {
        let snapshot = try UsageParsing.claude(data("""
        {"five_hour":{"utilization":5.5,"resets_at":"2026-09-08T07:29:59.513153+00:00"},
         "seven_day":{"utilization":0,"resets_at":"2026-09-11T12:59:59Z"},
         "seven_day_sonnet":{"utilization":88}}
        """), now: now)
        XCTAssertEqual(snapshot.shortTerm?.usedPercent, 5.5)
        XCTAssertEqual(snapshot.weekly?.usedPercent, 0)
        XCTAssertNotNil(snapshot.shortTerm?.resetsAt)
        XCTAssertNotNil(snapshot.weekly?.resetsAt)
        let missing = try UsageParsing.claude(data("{\"five_hour\":null,\"seven_day\":{\"utilization\":null}}"), now: now)
        XCTAssertNil(missing.shortTerm); XCTAssertNil(missing.weekly)
    }
    @Test func testRetryAfter() {
        XCTAssertEqual(UsageParsing.retryDate("120", now: now), now.addingTimeInterval(120))
        XCTAssertEqual(UsageParsing.retryDate(nil, now: now), now.addingTimeInterval(300))
        XCTAssertEqual(UsageParsing.retryDate("Thu, 01 Jan 1970 01:00:00 GMT", now: now), Date(timeIntervalSince1970: 3600))
    }
}

private actor StubProvider: UsageProvider {
    nonisolated let id: ProviderID
    var calls = 0
    var result: Result<UsageSnapshot, UsageFailure>
    var gate: CheckedContinuation<Void, Never>?
    var hold = false
    init(_ id: ProviderID, result: Result<UsageSnapshot, UsageFailure>) { self.id = id; self.result = result }
    func set(_ result: Result<UsageSnapshot, UsageFailure>) { self.result = result }
    func setHold() { hold = true }
    func release() { hold = false; gate?.resume(); gate = nil }
    func fetch() async throws -> UsageSnapshot {
        calls += 1
        if hold { await withCheckedContinuation { gate = $0 } }
        return try result.get()
    }
}

private actor TestSleeper {
    var intervals: [UInt64] = []
    var gates: [UUID: CheckedContinuation<Void, Error>] = [:]
    func sleep(_ interval: UInt64) async throws {
        let id = UUID(); intervals.append(interval)
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { gates[id] = $0 }
        }, onCancel: { Task { await self.cancel(id) } })
    }
    func cancel(_ id: UUID) { gates.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
    func tick() { let pending = gates; gates.removeAll(); for gate in pending.values { gate.resume() } }
    var pending: Int { gates.count }
}

@MainActor final class UsageStoreTests {
    var now = Date(timeIntervalSince1970: 1000)
    var snapshot: UsageSnapshot { UsageSnapshot(shortTerm: UsageWindow(minutes: 300, usedPercent: 42), weekly: UsageWindow(minutes: 10080, usedPercent: 7), fetchedAt: now) }
    func eventually(_ condition: () async -> Bool) async {
        for _ in 0..<1000 { if await condition() { return }; await Task.yield() }
        XCTFail("Condition did not become true")
    }
    @Test func testFailureRetainsStaleSnapshotAndOtherProviderUpdates() async {
        let claude = StubProvider(.claude, result: .success(snapshot))
        let codex = StubProvider(.codex, result: .success(snapshot))
        let store = UsageStore(providers: [claude, codex], now: { self.now })
        await store.refresh()
        let original = store.states[.claude]?.snapshot
        await claude.set(.failure(.signedOut)); now = now.addingTimeInterval(60)
        await codex.set(.success(snapshot)); await store.refresh()
        XCTAssertEqual(store.states[.claude]?.snapshot, original)
        XCTAssertEqual(store.states[.claude]?.isStale(at: now), true)
        XCTAssertEqual(store.states[.codex]?.snapshot?.fetchedAt, now)
        XCTAssertNil(store.states[.codex]?.failure)
    }
    @Test func testConcurrentReloadsCoalesceAndIndependentCompletion() async {
        let slow = StubProvider(.claude, result: .success(snapshot))
        let fast = StubProvider(.codex, result: .success(snapshot))
        await slow.setHold()
        let store = UsageStore(providers: [slow, fast])
        store.reload(); store.reload()
        await eventually { await slow.calls == 1 && store.states[.codex]?.snapshot != nil }
        await store.refresh() // must coalesce with the in-flight refresh
        let count = await slow.calls; XCTAssertEqual(count, 1)
        XCTAssertTrue(store.isRefreshing)
        await slow.release()
        await eventually { !store.isRefreshing }
        store.stop()
    }
    @Test func testThrottleCannotBeBypassedByReload() async {
        let provider = StubProvider(.claude, result: .failure(.throttled(now.addingTimeInterval(120))))
        let store = UsageStore(providers: [provider], now: { self.now })
        await store.refresh(); await store.refresh()
        var count = await provider.calls; XCTAssertEqual(count, 1)
        now = now.addingTimeInterval(120)
        await provider.set(.success(snapshot)); await store.refresh()
        count = await provider.calls; XCTAssertEqual(count, 2)
        XCTAssertNil(store.states[.claude]?.retryAt)
    }
    @Test func testStartupCadenceSleepWakeAndStop() async {
        let provider = StubProvider(.claude, result: .success(snapshot))
        let sleeper = TestSleeper()
        let store = UsageStore(providers: [provider], sleep: { try await sleeper.sleep($0) })
        store.start()
        await eventually { await provider.calls == 1 && !store.isRefreshing }
        await eventually { await sleeper.pending == 1 }
        let intervals = await sleeper.intervals; XCTAssertEqual(intervals, [60_000_000_000])
        await sleeper.tick()
        await eventually { await provider.calls == 2 && !store.isRefreshing }
        store.suspend()
        await eventually { await sleeper.pending == 0 }
        store.wake()
        await eventually { await provider.calls == 3 && !store.isRefreshing }
        store.stop()
        await eventually { await sleeper.pending == 0 }
        await sleeper.tick()
        let count = await provider.calls; XCTAssertEqual(count, 3)
    }
}

final class HelperProcessTests {
    @Test func testHungHelperTimesOutAndIsReaped() throws {
        let owner = HelperProcesses()
        let helper = try HelperProcess(path: "/bin/sleep", arguments: ["10"], timeout: 0.1, owner: owner)
        XCTAssertThrowsError(try helper.readToEnd()) { XCTAssertEqual($0 as? UsageFailure, .timeout) }
        helper.close()
        XCTAssertFalse(helper.process.isRunning)
    }
    @Test func testStopKillsOwnedHelper() throws {
        let owner = HelperProcesses()
        let helper = try HelperProcess(path: "/bin/sleep", arguments: ["10"], timeout: 1, owner: owner)
        owner.stop(); helper.close()
        XCTAssertFalse(helper.process.isRunning)
    }
}

// Small assertion helpers keep failures at the caller's source location.
private func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual == expected, sourceLocation: sourceLocation)
}
private func XCTAssertNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value == nil, sourceLocation: sourceLocation)
}
private func XCTAssertNotNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value != nil, sourceLocation: sourceLocation)
}
private func XCTAssertTrue(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value, sourceLocation: sourceLocation)
}
private func XCTAssertFalse(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!value, sourceLocation: sourceLocation)
}
private func XCTFail(_ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
    Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
}
private func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T,
                                    sourceLocation: SourceLocation = #_sourceLocation,
                                    check: (Error) -> Void = { _ in }) {
    do { _ = try expression(); Issue.record("Expected an error", sourceLocation: sourceLocation) }
    catch { check(error) }
}
