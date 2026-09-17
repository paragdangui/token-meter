# Token Meter

A macOS menu bar app for personal use. It shows how much of your **Claude Code** and **ChatGPT (Codex)** subscription allowance you've used, as four meters: a session window and a weekly window per provider. It refreshes every 60 seconds, including while the panel is closed.

## Build and run

Requires macOS 13+ and a Swift toolchain. Command Line Tools is enough; Xcode is not needed.

```bash
scripts/build-app.sh
```

```bash
open "dist/Token Meter.app"
```

The app has no Dock icon. The menu bar item shows percentages and time until reset as `session / weekly`: **C** is Claude Code and **G** is ChatGPT (Codex), e.g. `C 12% (4.2h) / 2% (5d 1h)`. A dimmed provider is stale, and `–` means unavailable. Click it to open the full panel with Reload, Quit, and **Show in menu bar** checkboxes for hiding either provider from the menu bar. Hiding both shows a gauge icon instead. The checkboxes are remembered across launches; this is the only thing the app saves.

Run the tests with `scripts/test.sh`. Add `--filter <name>` to run a single suite or test.

## Prerequisites

- **Claude Code:** installed and signed in with a Claude subscription (`claude auth login`). Token Meter reads Claude Code's own saved sign-in from the macOS Keychain. The first time, macOS may ask you to allow access.
- **ChatGPT (Codex):** the ChatGPT desktop app installed in `/Applications`, with Codex signed in using your ChatGPT account (not an API key). Token Meter starts the bundled `codex app-server` briefly for each refresh. To use a different binary, set `TOKEN_METER_CODEX_PATH`.

Token Meter stores no credentials, usage history or telemetry of its own.

## What the meters mean

- **Percent used** is subscription allowance used, as the provider reports it. It is not token counts, API billing or context-window fullness.
- **Session (5h)** is the provider's rolling short-term window. Neither provider currently exposes a daily quota, so nothing is labelled "Daily" unless a provider returns a 24-hour window.
- **Weekly** is the provider's 7-day window.
- **Unavailable** means the provider didn't return that window. It never means 0%.
- **Stale · Updated 12:34** means the last refresh failed, or the value is more than two minutes old. The numbers shown come from that earlier time.
- Both the menu bar and tray panel show time until each window resets, updated every 30 seconds. Session countdowns use hours rounded up to a tenth; weekly countdowns use days and hours rounded up to the next hour. Missing reset times are unavailable; elapsed reset times show `0.0h` or `0d 0h` until fresh data arrives. Hover a bar to see the exact reset date and time.

"ChatGPT" here means **Codex usage included with your ChatGPT plan**, not general ChatGPT chat usage. No usage API covers general ChatGPT chat.

## Reconnecting

| Message | Fix |
| --- | --- |
| Run claude auth login in Terminal. | Sign in to Claude Code again, then press Reload. |
| Claude sign-in token expired. Run claude once in Terminal to refresh it. | Start `claude` (any session) so it refreshes its token, then press Reload. |
| Sign in to Codex with ChatGPT. | Open Codex and sign in with your ChatGPT account, then press Reload. |
| Install Codex, then reopen Token Meter. | Install the ChatGPT desktop app, or set `TOKEN_METER_CODEX_PATH`. |
| Rate limited until … | Wait. Reload doesn't bypass provider throttling. |
| Request timed out / Will retry. | Usually transient; the next automatic refresh retries. |

## Data sources and maintenance risk

- **Codex:** the documented `codex app-server` JSON-RPC protocol (`initialize` → `account/read` → `account/rateLimits/read`). The app reads the `codex` bucket from `rateLimitsByLimitId` and never substitutes another model's bucket. Last validated with codex-cli 0.154.
- **Claude Code:** there is no documented subscription-usage API. The app reads Claude Code's OAuth token from the Keychain item `Claude Code-credentials` and calls `GET https://api.anthropic.com/api/oauth/usage` (`five_hour`, `seven_day`), the same data behind `/usage`. **This endpoint and the credential format are undocumented and may change without notice.** All knowledge of them is isolated in `ClaudeProvider` and `UsageParsing.claude`. Last validated with Claude Code 2.1.267.

`scripts/probe_sources.py` fetches both sources read-only, without printing secrets. Use it to check them after a CLI update.
