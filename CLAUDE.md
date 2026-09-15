# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

Implemented. [PLAN.md](PLAN.md) is the specification and [README.md](README.md) is the user-facing doc. Token Meter is a personal-use native macOS menu bar app showing Claude Code and ChatGPT (Codex) **subscription allowance used**, as four meters (session + weekly, per provider).

## Toolchain on this Mac (verified)

- macOS 26.6.2, Swift 6.4, **Command Line Tools only (no Xcode)**. That's why this is a SwiftPM package with an `.app` bundle assembled by `scripts/build-app.sh`, not an Xcode project.
- Plain `swift test` fails here with "TestingMacros plugin not found". `scripts/test.sh` adds the CLT plugin path; always use it.
- `claude` CLI: `~/.local/bin/claude` (2.1.267). `codex` is not on PATH; the app uses `/Applications/ChatGPT.app/Contents/Resources/codex` (codex-cli 0.154).

## Build / test commands

```bash
scripts/test.sh                                  # all tests (Swift Testing)
scripts/test.sh --filter UsageParsingTests       # one suite or test name
swift build                                      # debug build
scripts/build-app.sh                             # release build -> dist/Token Meter.app (ad-hoc signed)
open "dist/Token Meter.app"
python3 scripts/probe_sources.py                 # live read-only check of both data sources (prints no secrets)
```

## Architecture

- `Sources/TokenMeterCore` (library, all the testable logic):
  - `UsageSnapshot.swift`: `ProviderID`, `UsageWindow` (label derived from duration), `UsageSnapshot`, `UsageFailure`, `ProviderState` (stale = failure or more than 120s old).
  - `UsageStore.swift`: the `UsageProvider` protocol and `UsageStore`, the single refresh coordinator. It covers the 60s timer, coalesced `reload()`, per-provider task group, `retryAt` throttle gate, `suspend`/`wake`/`stop`, and injectable `now`/`sleep` for tests.
  - `Providers.swift`: the `CodexProvider` and `ClaudeProvider` adapters.
  - `UsageParsing.swift`: pure response parsing plus `Retry-After`.
  - `HelperProcess.swift`: bounded child processes (poll-based read timeout, `F_SETNOSIGPIPE`, SIGKILL on close). `HelperProcesses.shared` kills owned helpers on quit.
- `Sources/TokenMeter` (app): `TokenMeterApp` (`MenuBarExtra`, accessory policy, sleep/wake observers), `UsageView` (the panel) and `MenuBarLabel`. `MenuBarLabel` shows `C 12%/2%  G 0%/1%` (session/weekly) in the menu bar. It renders a SwiftUI layout into an `NSImage` so a stale provider can be dimmed on its own and each percentage colored, which a `MenuBarExtra` Text label can't do. Colored text can't be a template image, so light and dark variants are rasterized and a drawing handler picks one by `NSAppearance.currentDrawing()` (the menu bar's appearance, not the app's). Usage colors come from `UsageLevel` (core: <50 normal, 50 yellow, 75 orange, 90 red, on the rounded percent) mapped to shades in `UsageLevelColor.swift`, shared by the panel and menu bar. Per-provider menu-bar visibility is stored with `@AppStorage` (keys in `MenuBarVisibility`); with both hidden, it falls back to a gauge icon.

Chosen data sources (validated live; see README for maintenance risk):

- **Codex:** spawn `codex app-server` per fetch, then `initialize` → `account/read` (must be `chatgpt`) → `account/rateLimits/read`, and read `rateLimitsByLimitId["codex"]`. Schema: `codex app-server generate-json-schema --out <dir>`.
- **Claude:** read the Keychain item `Claude Code-credentials` (`claudeAiOauth.accessToken`) via `/usr/bin/security`, then call `GET https://api.anthropic.com/api/oauth/usage` with `anthropic-beta: oauth-2025-04-20`. This is undocumented. Never refresh or write the token; that belongs to Claude Code.
- **Daily windows:** neither provider returns one. Both return 300-min + 10080-min windows.

The provider-specific fragility (undocumented endpoints, CLI protocols, auth) belongs behind the adapters; nothing above `UsageProvider` should know how a percentage was obtained.

## Constraints that are easy to violate

These come from PLAN.md and are the point of the project, not preferences:

- Percentages are **subscription allowance used** — never raw tokens, API billing, or context-window fullness.
- Never invent a daily window. Label whatever window the provider actually returns (e.g. `Session (5h)`, not `Daily`). Do not convert session percentages into daily ones, and do not average unrelated model buckets.
- A missing window renders `Unavailable`, never `0%`.
- Data access is proven **before** UI work (build sequence step 1). If no dependable read-only source exists for a provider, record the blocker and stop — do not fall back to polling interactive terminal output, scraping a browser, or reconstructing an account-wide percentage from local transcript token totals.
- Fixture data is for development only and must not remain in normal app operation.
- Fetch providers independently; one failure must leave the other usable, with stale values retained and visibly marked with their own timestamps.
- Refresh is 60s, fixed and not configurable. Reload shares the same fetch path, coalesces with in-flight work, and must **not** bypass provider throttling / `Retry-After`.
- Credentials go in the macOS Keychain — never in source, logs, or PLAN.md. Prefer reusing existing provider sign-in over building account management.
- No persistence of usage data, telemetry, hosted backend, history, charts, notifications, or spending tracking. The only controls are Reload, Quit, and the per-provider "Show in menu bar" checkboxes (added at the user's request). Those checkboxes are the only persisted state, in UserDefaults.

## Resolved questions

- "ChatGPT subscription" = Codex usage on the ChatGPT plan (PLAN.md's working assumption, kept). General ChatGPT usage has no usage API.
- Claude Code has no supported structured source for `/usage`, so the undocumented OAuth usage endpoint was validated and selected. Its risk is documented in README.md. Re-run the probe after CLI updates.

## Testing approach

Fixture tests for response parsing: missing windows, multiple rate-limit buckets, used-vs-remaining semantics. A controllable clock and provider stub for refresh coordination, overlap prevention, and error isolation. Finish with a live comparison against each provider's own usage screen and a manual menu-bar check — broad UI automation is out of scope.
