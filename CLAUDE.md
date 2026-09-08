# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

Pre-implementation. The directory contains only [PLAN.md](PLAN.md) — no source, no Xcode project, no build system, and not a git repository. PLAN.md is the specification; read it before writing anything, and update this file with real build/test commands as soon as a target exists.

Token Meter is a personal-use native macOS menu bar app showing Claude Code and ChatGPT (Codex) **subscription allowance used**, as four meters (session + weekly, per provider).

## Toolchain on this Mac (verified)

- macOS 26.6.2, Swift 6.3.3 (`swift` works standalone).
- **Xcode is not installed** — `xcode-select` points at `/Library/Developer/CommandLineTools`, so `xcodebuild` fails. PLAN.md's "build locally in Xcode" step is blocked until Xcode is installed and selected. A SwiftPM executable target with an `.app` bundle assembled by hand is the alternative; raise the choice with the user rather than silently switching.
- `claude` CLI: `~/.local/bin/claude`. `codex` is **not on PATH**, but `~/.codex/` exists with `auth.json` and `config.toml` — locate the actual Codex binary before assuming the app-server protocol is reachable.

## Build / test commands

None yet. Add them here when the target is created (build, run, and how to run a single test).

## Architecture (as planned)

Five responsibilities, kept separate:

- `TokenMeterApp` — `MenuBarExtra` lifecycle, `LSUIElement` agent app (no Dock icon).
- `UsageView` — two provider sections, four meters, status line, Reload, Quit.
- `UsageStore` — observable state plus the single refresh coordinator.
- `UsageProvider` — shared fetch interface; Claude and Codex adapters implement it.
- `UsageSnapshot` — provider, window duration/type, percent used, reset timestamp, last successful fetch time, fetch status.

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
- No persistence, telemetry, hosted backend, history, charts, notifications, or spending tracking. Quit is the only control beyond Reload.

## Open questions to resolve before the relevant integration

- Whether "ChatGPT subscription" means Codex usage on the ChatGPT plan (the working assumption) or general ChatGPT usage.
- Whether Claude Code exposes any supported structured source for the `/usage` subscription bars; if only an undocumented authenticated endpoint exists, validate it and document its maintenance risk before selecting it.

## Testing approach

Fixture tests for response parsing: missing windows, multiple rate-limit buckets, used-vs-remaining semantics. A controllable clock and provider stub for refresh coordination, overlap prevention, and error isolation. Finish with a live comparison against each provider's own usage screen and a manual menu-bar check — broad UI automation is out of scope.
