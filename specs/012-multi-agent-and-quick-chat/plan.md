# Plan: Multi-Agent and Quick Chat

**Feature Branch**: `feature/time-machine-multi-agent-and-quick-chat`  
**Date**: 2026-08-13  
**Spec**: `spec.md`

## Summary

This feature hardens the already-implemented Multi-Agent and Quick Chat flow with a small, bounded set of production-safe changes:

- extract shared constants for multi-agent and quick-chat limits,
- enforce the three-service cap in both UI and runtime call site,
- surface global hotkey registration failure as an actionable state in Hotkeys preferences,
- keep the existing architecture (existing factories/managers/view flows), while adding deterministic logic-only coverage for pure behavior.

No major feature redesign or Core Data migration is planned.

## Implementation Status

- 2026-08-13: Confirmed `specs/012-multi-agent-and-quick-chat` as the active SDD feature and `feature/time-machine-multi-agent-and-quick-chat` as the active branch.
- 2026-08-13: The prerequisite check completed with all required feature artifacts present.
- 2026-08-13: The pre-implementation macOS arm64 build completed with `** BUILD SUCCEEDED **`.
- 2026-08-13: Implement phase verified — build succeeded (0 errors), all 17 feature tests passed (7 suites), secret scan clean. tasks.md T001–T026 complete; T027 (interactive GUI manual checks) left to operator.

## Technical Context

- **Language / Version**: Swift 5.9 / SwiftUI / AppKit / Foundation / Core Data / Carbon
- **Target**: Native macOS app (arm64)
- **Platform behavior**: global hotkey and floating `NSPanel` for quick chat
- **Persistence**:
  - UserDefaults for hotkey shortcuts (`hotkey_<actionId>`)
  - Core Data for chat/message history (already existing)
  - Keychain for service tokens (existing path)
- **Testing constraints**:
  - deterministic tests only: `KeyboardShortcut` parse/format, multi-agent cap behavior, `AgentResponse` transitions
  - no AppKit/NSPanel focus tests
  - no Carbon event-firing tests
  - no live network/provider calls in unit tests

## Constitution / Safety Check

- [x] Existing UI and chat flows remain primary owners; no architecture replacement for provider routing.
- [x] No schema migration; no new persistence tables.
- [x] No new credentials or secrets introduced in app settings.
- [x] No telemetry/logging expansion beyond existing debug-safe logs.
- [x] Tests cover logic seams, not live side effects.

## Architecture Impact (Planned)

| Module | Planned change |
|---|---|
| `Warden/Utilities/MultiAgentMessageManager.swift` | Replace hard-coded `prefix(3)` with `AppConstants.MultiAgent.maxConcurrentServices`; keep dispatch concurrency behavior and `stopStreaming` completion/error marking contract. |
| `Warden/UI/Chat/MultiAgentServiceSelector.swift` | Replace `maxSelectedServices = 3` with `AppConstants.MultiAgent.maxConcurrentServices`; preserve selection disablement and “Select Best 3” behavior. |
| `Warden/Utilities/FloatingPanelManager.swift` | Replace literal height clamp `60...600` with `AppConstants.QuickChat.minPanelHeight` / `AppConstants.QuickChat.maxPanelHeight`. |
| `Warden/Models/HotkeyModels.swift` | Keep structure and persistence model; ensure quick-chat shortcut registration outcome remains explicit and observable. |
| `Warden/Utilities/GlobalHotkeyHandler.swift` | Add a registration outcome state (success/failure/mapping-failure) and emit observable failure for UI warning; preserve existing install/uninstall and callback behavior. |
| `Warden/UI/Preferences/TabHotkeysView.swift` | Consume global registration status and render visible warning recommending alternative quick-chat shortcut when registration fails. |
| `Warden/Configuration/AppConstants.swift` | Add `MultiAgent` + `QuickChat` constant containers with `maxConcurrentServices`, `minPanelHeight`, `maxPanelHeight`.
| `WardenTests/Utilities/…` (new) | Add pure-unit tests for shortcut round-trip, three-service cap helper/constant usage, and `AgentResponse` state transitions.

## Scope

### In scope

1. **Constants extraction**
   - `AppConstants.MultiAgent.maxConcurrentServices`
   - `AppConstants.QuickChat.minPanelHeight`
   - `AppConstants.QuickChat.maxPanelHeight`
2. **Runtime hardening by cap sharing**
   - Use shared constants in UI and message manager runtime guard.
3. **Global-hotkey failure visibility**
   - Add an observable registration state for quick-chat hotkey and show in-UI warning text.
4. **Focused determinism tests**
   - Three pure logic test areas from clarification.
5. **Docs and tasks**
   - `plan`, `research`, `data-model`, `quickstart`, `contract`, then tasks implementation.

### Explicit non-goals

- Changing the three-service maximum.
- Adding any fallback or automatic remapping for global hotkey conflicts.
- Introducing AppKit/NSPanel focus automation tests.
- Reworking quick-chat panel UI/feature behavior unrelated to constraints above.
- Changing provider routing, streaming protocol, or Core Data model.

## Implementation Phases

### Phase 1 — Constants and shared boundary

- Add `AppConstants.MultiAgent` and `AppConstants.QuickChat`.
- Replace literal limits in `MultiAgentMessageManager`, `MultiAgentServiceSelector`, `FloatingPanelManager`.

### Phase 2 — Global hotkey registration state

- Extend `GlobalHotkeyHandler` with explicit success/failure status for last registration attempt.
- Ensure status is updated for both unsupported key mapping and Carbon failure.
- Keep existing notification callback (`FloatingPanelManager.shared.togglePanel()`) as the runtime action.

### Phase 3 — Warning UI

- Update `TabHotkeysView` to surface warning for quick-chat registration failure with recommendation:
  - e.g. “Quick Chat shortcut could not be registered. Try another combination.”
- Ensure no secrets/user prompt text is shown.

### Phase 4 — Deterministic tests and verification

- Add focused utility tests:
  - `KeyboardShortcut` from/display-string round-trip
  - limit enforcement with `AppConstants.MultiAgent.maxConcurrentServices`
  - `AgentResponse` transition: incomplete -> in-progress response updates -> complete + error transitions
- Run verification commands listed in `quickstart.md`.

## Delivery/Acceptance Checklist

- [ ] Constants extracted and used consistently in source call-sites.
- [ ] Multi-agent UI and runtime truncation both reference the same constant.
- [ ] Hotkey registration failure state exists and is visible to the Hotkeys preferences user.
- [ ] Quick-chat panel uses constant-based height clamp.
- [ ] No AppKit/OS global-event side-effect tests are added.
- [ ] Tests + build commands in `quickstart.md` run.
- [ ] Queue phase advances only after docs/tasks completion and implementation readiness gate.
