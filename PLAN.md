# Token Meter — implementation plan

## Goal

Build a minimal native macOS menu bar app for personal use on this Mac. Show Claude Code and ChatGPT subscription usage as percentages, with short-term and weekly meters, a Reload button, and automatic refresh every 60 seconds. This document is the plan only; implementation has not started.

## Usage definitions and feasibility

- Percentages mean **subscription allowance used**, not raw tokens, API billing, or context-window fullness.
- Requested daily meters must use an actual provider daily quota if one exists. If the provider exposes a session window instead (for example, five hours), label it `Session (5h)` rather than `Daily`. Do not invent a daily allowance or convert session percentages into daily percentages.
- Working assumption: “ChatGPT subscription” means **Codex usage included with the ChatGPT plan**. Label that section `ChatGPT (Codex)`. General ChatGPT conversations are a different scope; the reviewed documentation does not establish a single daily/weekly percentage API covering all ChatGPT usage. Resolve this distinction before implementing that integration if general ChatGPT usage is intended.
- Availability of both quota windows is a feasibility requirement, not a promise. Missing windows display `Unavailable`, never `0%`. A missing required source must be reported before calling the app complete.

## Minimal interface

Use one small menu bar icon. Clicking it opens a compact panel with all four meters visible together. This assumes percentages belong in the opened menu, keeping the system menu bar uncluttered.

```text
Claude Code
Session (5h)   [████░░░░░░]  40% used
Weekly         [██░░░░░░░░]  20% used

ChatGPT (Codex)
Session (5h)   [███░░░░░░░]  30% used
Weekly         [█░░░░░░░░░]  10% used

Updated 12:34                  Reload
Quit
```

Example numbers and session durations above are placeholders. Labels follow actual returned windows. Keep styling native, with readable text and simple progress bars. Show a brief inline status only when loading, signed out, unavailable, or stale.

No dashboard, history, charts, notifications, model selector, spending tracker, configurable refresh interval, account management screen, or cloud service. Quit is the only additional operational control.

## Implementation approach

Use a native Swift/SwiftUI macOS app with `MenuBarExtra`, targeting macOS 13 or later after checking this Mac. Configure it as an agent app (`LSUIElement`) so it has no Dock icon or main window. Use Foundation networking/process support and minimal dependencies. Build locally in Xcode; no App Store distribution or hosting is needed.

Separate only the necessary responsibilities:

- `TokenMeterApp`: menu bar lifecycle and panel.
- `UsageView`: two provider sections, four meters, status, Reload, and Quit.
- `UsageStore`: observable state and one refresh coordinator.
- `UsageProvider`: shared fetch interface, implemented by Claude and Codex adapters.
- `UsageSnapshot`: provider, window duration/type, percentage used, reset timestamp when available, last successful fetch time, and fetch status.

## Data sources

### ChatGPT / Codex

Prefer the installed Codex CLI's documented app-server protocol with existing ChatGPT authentication. Initialize the connection, check account authentication, and call `account/rateLimits/read`; do not run a model prompt to fetch usage. The official protocol exposes `usedPercent`, `windowDurationMins`, and `resetsAt` and may return multiple rate-limit buckets. [Official app-server documentation](https://learn.chatgpt.com/docs/app-server)

Select the applicable Codex account bucket explicitly, prefer the keyed response when present, and interpret windows by their returned durations. Do not average unrelated model buckets or assume primary always means daily. Verify this behavior against the installed CLI schema. Manage the helper process lifecycle and stop it when the app quits.

The desktop assistant's usage tool is not an API the standalone app can call. API keys and API billing reports are not substitutes for subscription quota data.

### Claude Code

First validate a repeatable, read-only way to retrieve the same subscription bars shown by Claude Code's `/usage` screen. Anthropic documents subscriber plan bars there, separately from locally calculated token costs and local activity statistics. It also documents stale results when the usage endpoint is rate limited. [Official Claude Code usage documentation](https://code.claude.com/docs/en/costs#using-the-usage-command)

The reviewed documentation does not establish a supported public subscription quota API. During the feasibility spike, inspect the installed CLI's supported interfaces and confirm whether a structured usage source is available. If only an undocumented authenticated endpoint is available, validate its access requirements and response format before selecting it, isolate it behind the adapter, and document its maintenance risk. Do not assume an endpoint or credential format works without testing.

Avoid polling interactive terminal output or scraping a browser as the default implementation. If no dependable source exists, record the blocker and revisit the integration before building the finished UI. Local transcript token totals cannot reconstruct an account-wide allowance percentage.

Reuse existing sign-in through supported mechanisms where possible. Any app-owned credentials belong in macOS Keychain, never source files, logs, or the plan. Provide a concise sign-in instruction when authentication expires rather than implementing a new account system.

## Refresh behavior

- Fetch both providers at launch, then every 60 seconds while the app is running and the Mac is awake, including while the panel is closed.
- Reload invokes the same fetch path immediately; show an in-progress state and coalesce concurrent refresh requests.
- Fetch providers independently so one provider's failure does not prevent the other from updating.
- Bound each request/helper operation with a timeout. Retain last successful values after errors and visibly mark them stale with their own timestamps.
- On waking from sleep, refresh once and resume the normal cadence; do not replay missed ticks.
- Honor provider throttling and Retry-After. The normal target remains once per minute, but throttled providers wait until permitted; Reload must not bypass that restriction.
- Keep only current snapshots in memory. No persistent usage database or telemetry.

## Build sequence

1. **Prove data access.** Check macOS, build tools, installed CLI versions, and available authentication without exposing secrets. Fetch real subscription snapshots for both providers. Compare percentages and window labels with each provider's own usage screen. Establish whether a true daily window exists and confirm the ChatGPT scope. Record the chosen interfaces and any blocker.
2. **Create the native shell.** Add the local app target and menu panel, using fixture data only during development. Implement the four meters and minimal operational states.
3. **Connect live providers.** Add the two adapters, validated window mapping, authentication errors, and independent stale-state handling. Remove fixture fallback from normal app operation.
4. **Add refresh coordination.** Implement startup fetch, 60-second scheduling, Reload, wake handling, timeout, throttling, and helper cleanup.
5. **Validate and package locally.** Build a runnable `.app`, verify it on this Mac, and add a short README covering build/run, prerequisite sign-in, meter meanings, and reconnect steps. A developer membership, installer, auto-updater, and login-item feature are outside scope.

## Acceptance checks

- A single menu bar item opens both provider sections and their four requested meter slots together.
- Real percentages match authoritative provider usage within display rounding; unavailable values are explicit.
- Daily/session labels reflect actual quota windows; weekly values correspond to the provider's weekly quota.
- Reload refreshes both sources without duplicate in-flight work. Automatic refresh occurs every 60 seconds during normal operation, even with the panel closed.
- A failed provider leaves the other usable, and old values are visibly stale.
- Sleep/wake, expired sign-in, timeout, and rate limiting recover without hanging the UI.
- Quit stops timers and owned helper processes. No Dock icon, telemetry, or hosted backend is present.

Use focused fixture tests for response parsing, missing windows, multiple buckets, and used-versus-remaining semantics. Use a controllable clock/provider stub to verify refresh coordination, overlap prevention, and error isolation. Finish with a local live comparison and a short manual menu-bar check; broad UI automation is unnecessary for this small personal app.
