# Quickstart: Multi-Agent and Quick Chat Verification

## Automated verification commands

Run these commands from the repository root (`/Volumes/WDBlack4TB/Code/WardenApp`).

```bash
cd /Volumes/WDBlack4TB/Code/WardenApp

# Replace <TestTargetName> with the actual test class/file after implementation
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS,arch=arm64' -only-testing:WardenTests/<TestTargetName>

xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS,arch=arm64'

xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS,arch=arm64' build


git diff --check
```

## Expected evidence

- Focused tests (single run) should include:
  - `KeyboardShortcut` round-trip parse/format behavior.
  - three-service cap behavior tied to `AppConstants.MultiAgent.maxConcurrentServices`.
  - `AgentResponse` state transitions for complete and error paths.
- Build should complete with `** BUILD SUCCEEDED **`.
- Full test pass should succeed for feature tests and report no new failures introduced by this feature.

## Manual verification (optional, non-blocking for CI-only evidence)

1. Configure 4 services in the app.
2. Open Multi-Agent selector and confirm after reaching the limit, additional service row actions are disabled and count remains capped.
3. Trigger a multi-agent send and confirm capped request fan-out.
4. In Hotkeys, change the Quick Chat shortcut and confirm:
   - success when registration is accepted,
   - visible warning if registration fails.
5. Press Escape / focus-lost behavior on quick-chat panel from normal UI usage and confirm current close behavior remains unchanged.

### Quick-chat smoke command

After a successful Debug build, launch the built application and perform steps 4–5 above:

```bash
open /Volumes/WDBlack4TB/XCodeDerivedData/Build/Products/Debug/Warden.app
```

This is a manual UI smoke check only; automated tests intentionally do not focus an `NSPanel` or fire Carbon hotkey events.

## Notes

- No live provider credentials, paid API calls, or live global hotkey event injection should be used in automated verification.
- This is a deterministic verification plan aligned to the user’s constraints.

## Verification Log

### 2026-08-13 — Automated verification (XCodeMCP, scheme Warden, macOS arm64)

**Build** (`BuildProject`): `The project built successfully.` — 0 errors, 3 unused-variable warnings
(`MultiAgentResponseView.swift:214` `isStreaming`, `MultiAgentMessageManager.swift:142` `index`,
`MultiAgentServiceSelector.swift:88` `serviceName`).

**Tests** (`RunSomeTests`, feature suites): **All 17 tests passed** — 0 failures, 42s.
Suites: `MultiAgentMessageManagerTests`, `MultiAgentServiceSelectorTests`, `MultiAgentQuickChatTests`,
`HotkeyModelsTests`, `GlobalHotkeyHandlerTests`, `FloatingPanelManagerTests`, `TabHotkeysViewTests`.

**Secret scan** (`git diff --check` + pattern grep over `Warden/`, `WardenTests/`): clean — no
whitespace/conflict errors, no secrets found in changed files.

_Manual US1/US2/US3 steps require an interactive GUI session (global hotkey, NSPanel focus) and are
left to the operator; they are intentionally excluded from automated unit coverage per plan.md._
