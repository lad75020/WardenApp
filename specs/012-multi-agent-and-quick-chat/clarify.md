# Clarifications: Multi-Agent and Quick Chat

**Date**: 2026-08-13  
**Phase**: clarify (human-gated)

## Resolved decisions

1. **Three-service concurrency cap** — Intended product behavior. The UI MUST prevent selecting more than three services (disable extra selections once three are chosen) rather than silently truncating. The `prefix(3)` runtime guard remains as a safety net.

2. **Global hotkey registration failure** — When Carbon `RegisterEventHotKey` returns a non-`noErr` status (e.g. the combination is owned by another app), the Hotkeys settings tab MUST surface a visible warning to the user and recommend choosing a different combination. The in-app menu shortcut path continues to work regardless.

3. **Test scope** — Pure-logic deterministic tests only, matching the MCP approach: `KeyboardShortcut` display-string round-trip, the three-agent concurrency cap, and `AgentResponse` state transitions. No AppKit/NSPanel focus or global-hotkey-firing tests (non-deterministic, side-effectful).

4. **Magic numbers** — Extract both the three-agent cap and the quick-chat panel height clamp (min 60, max 600 pt) into `AppConstants` as a single, testable source of truth. Call sites in `MultiAgentMessageManager` and `FloatingPanelManager` reference the constants.

## Spec impact

- FR-001 / UX-001: add UI enforcement of the ≤3 selection limit.
- FR-007 / UX-004: add a visible registration-failure warning surface.
- SC-005: test set fixed to the three pure-logic areas above.
- New constants: `AppConstants.MultiAgent.maxConcurrentServices = 3`, `AppConstants.QuickChat.minPanelHeight = 60`, `AppConstants.QuickChat.maxPanelHeight = 600`.
