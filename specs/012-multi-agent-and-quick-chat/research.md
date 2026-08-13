# Research: Multi-Agent and Quick Chat

## Decision 1 — Single-source limits

**Decision**: Use shared constants from `AppConstants` for both UI and runtime: `AppConstants.MultiAgent.maxConcurrentServices`, `AppConstants.QuickChat.minPanelHeight`, and `AppConstants.QuickChat.maxPanelHeight`.

**Rationale**: The feature already had duplicate caps and hard-coded sizing values (`3`, `60`, `600`) in separate layers. Shared constants remove drift risk and simplify tests.

**Alternatives rejected**:
- Keep duplicate literals in each file (regression-prone).
- Add a new manager for caps/sizing (over-engineering for three scalar values).

## Decision 2 — Keep dual guard (`UI limit` + `runtime limit`)

**Decision**: Keep UI disablement for service selection plus runtime `prefix(_:)` truncation in `MultiAgentMessageManager` as a defensive guard.

**Rationale**: Clarified behavior requires user-facing prevention at selection time. Runtime safety remains valuable if stale/unclean inputs reach the send path (e.g., older persisted state, race with stale binding).

**Alternatives rejected**:
- Runtime-only enforcement (fails UX requirement).
- UI-only enforcement only (unsafe if caller sends oversized list).

## Decision 3 — Global hotkey failure must be explicitly observable by UI

**Decision**: Extend hotkey registration logic to record last status and expose it to `TabHotkeysView` for warning display.

**Rationale**: Users need actionable feedback when registration conflicts or unsupported key mapping occurs; silent failure is insufficient and currently only logs to diagnostics.

**Alternatives rejected**:
- Log-only behavior (insufficient for non-developer users).
- Immediate fallback remapping strategy (user did not request).

## Decision 4 — Test boundaries

**Decision**: Only deterministic, logic-only tests are added:

1. `KeyboardShortcut` display-string round-trip
2. three-service cap behavior anchored to `AppConstants.MultiAgent.maxConcurrentServices`
3. `AgentResponse` state transitions (start / response append / complete / error)

**Rationale**: User explicitly chose no AppKit/NSPanel focus tests, no hotkey-fire tests, and no live provider calls.

**Alternatives rejected**:
- `NSPanel` integration tests and Carbon event dispatch tests (non-deterministic / brittle).
- Live API provider tests for multi-agent (external variability and secret handling concerns).

## Decision 5 — Quick-chat panel behavior boundaries

**Decision**: Do not change panel positioning, dragging model, activation, or focus semantics beyond min/max height constant usage.

**Rationale**: Current behavior is already implemented and aligned with feature intent. Scope is constrained to hardening and warning visibility.

**Alternatives rejected**:
- Visual redesign.
- Positioning or hide/show semantics changes unrelated to requirement.

## Security & privacy considerations

- Keep service credentials in existing Keychain flow and do not surface secrets in warnings, tests, or hotkey status.
- Do not display full prompts or response content in hotkey diagnostics.
- Continue treating quick-chat registration warning as actionable UX text only.

## Risks and mitigations

- **Risk**: global hotkey conflict remains user-configurable.
  - **Mitigation**: show explicit failure warning + recommendation to choose another combination.
- **Risk**: legacy state still carries more than 3 services.
  - **Mitigation**: runtime truncation remains in the manager.
- **Risk**: AppConstants currently has duplicate legacy key structs elsewhere.
  - **Mitigation**: place new constants in `AppConstants` nested structs adjacent to current hotkey/notification constants and avoid unrelated cleanup.
