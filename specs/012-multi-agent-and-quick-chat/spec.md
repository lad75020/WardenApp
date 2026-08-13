# Feature Specification: Multi-Agent and Quick Chat

**Feature Branch**: `feature/time-machine-multi-agent-and-quick-chat`  
**Created**: 2026-08-13  
**Status**: Draft  
**Input**: User description: "Supports side-by-side responses from multiple services and a global-hotkey floating chat for fast access from anywhere on macOS."

This feature specifies and hardens two already-implemented, related capabilities: **Multi-Agent** (fan-out one prompt to several AI services and compare answers side by side) and **Quick Chat** (a Spotlight-style floating panel summoned by a global hotkey), together with the **hotkey configuration** that binds them.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Compare responses from multiple services (Priority: P1)

A user selects two or three configured AI services, sends one prompt, and watches each service's answer stream into its own column simultaneously, so they can compare quality, tone, and speed before choosing one.

**Why this priority**: Side-by-side comparison is the headline value of multi-agent mode; without it the other pieces have no payoff.

**Independent Test**: Select 2–3 services, send a prompt, and confirm each column streams independently, completes or errors independently, and that a single "stop" cancels all in-flight agents.

**Acceptance Scenarios**:

1. **Given** three or more services are configured, **When** the user selects services and sends a prompt, **Then** at most three agents run concurrently and each renders in its own column with its service name and model.
2. **Given** agents are streaming, **When** one service errors, **Then** only that column shows the error while the others continue to completion.
3. **Given** agents are streaming, **When** the user taps Stop, **Then** every in-flight agent is cancelled, marked complete, and shows a "cancelled" state without corrupting chat state.
4. **Given** a service that does not support streaming, **When** it is selected, **Then** its column shows a single final response rather than incremental text.

---

### User Story 2 - Summon a floating quick chat with a global hotkey (Priority: P1)

From any app on macOS, the user presses a configurable global hotkey to open a floating, Spotlight-style chat panel centered near the top of the screen, types a prompt, gets an answer, and dismisses the panel by pressing Escape or clicking away — without the main window stealing focus workflow.

**Why this priority**: The global-hotkey floating panel is the "fast access from anywhere" promise and is independently useful even without multi-agent mode.

**Independent Test**: With the app running in the background, press the quick-chat hotkey, confirm the panel appears top-center, accepts input, grows within bounds as content arrives, and closes on Escape or focus loss.

**Acceptance Scenarios**:

1. **Given** the app is not frontmost, **When** the user presses the registered quick-chat hotkey, **Then** the floating panel appears centered near the top of the main screen and becomes key for text entry.
2. **Given** the panel is open, **When** the user presses Escape or clicks another window (focus loss), **Then** the panel hides.
3. **Given** a response is rendering, **When** its content changes height, **Then** the panel height animates within a clamped range (min 60, max 600 pt) without moving its bottom anchor.
4. **Given** the panel is re-opened, **When** it appears, **Then** its chat state is reset for a fresh prompt.

---

### User Story 3 - Configure hotkeys for actions (Priority: P2)

A user opens the Hotkeys settings tab, sees the available actions grouped by category (Chat, Clipboard, Navigation), records a new shortcut by pressing a key combination, and the change takes effect immediately and persists across launches; they can reset one or all shortcuts to defaults.

**Why this priority**: Customization is valuable but the defaults already make US1/US2 usable, so this is a secondary increment.

**Independent Test**: Change the quick-chat shortcut, confirm the old combo no longer opens the panel and the new one does, relaunch, and confirm the new combo persists; reset to default and confirm restoration.

**Acceptance Scenarios**:

1. **Given** the Hotkeys tab, **When** the user records a new combination for an action, **Then** its display string (e.g. `⌘⇧C`) updates and the value persists in preferences.
2. **Given** the quick-chat action's shortcut is changed, **When** the change is saved, **Then** the previous global registration is removed and the new combination is registered globally.
3. **Given** customized shortcuts, **When** the user chooses "reset to defaults", **Then** each action returns to its default combination and re-registers as needed.

### Edge Cases

- What happens when more than three services are selected for multi-agent? Only the first three run; the rest are ignored for that turn (documented limit).
- What happens when a global hotkey key cannot be mapped to a key code? Registration is skipped safely (no crash); in DEBUG a diagnostic is logged without leaking the combination as private data.
- What happens when the global hotkey fails to register (OS returns non-`noErr`)? The failure is logged and the app continues; the in-app menu shortcut path still works.
- What happens when the quick-chat panel loses focus mid-stream? The panel hides; the underlying request lifecycle is not required to persist panel-visible state.
- What data persists across launches? Only hotkey display strings in preferences; no chat content is persisted by the panel itself beyond normal chat storage.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: WardenApp MUST let the user select multiple configured services and send one prompt to all of them, running at most three concurrently. The three-service limit is intended behavior and MUST be enforced in the UI (extra selections disabled once three are chosen); `prefix(3)` remains a runtime safety net. The limit is defined in `AppConstants.MultiAgent.maxConcurrentServices`.
- **FR-002**: Each agent MUST render independently with its service name and model, supporting both streamed and non-streamed responses, and MUST record per-agent completion and error state.
- **FR-003**: A single stop action MUST cancel all in-flight agents, mark them complete, and leave chat state uncorrupted.
- **FR-004**: WardenApp MUST provide a floating, non-activating quick-chat panel that can be summoned while the app is not frontmost, positioned Spotlight-style near the top-center of the main screen.
- **FR-005**: The quick-chat panel MUST become key for input on open, hide on Escape and on focus loss, and reset its chat state when opened.
- **FR-006**: The quick-chat panel height MUST adjust to content within a clamped range defined by `AppConstants.QuickChat.minPanelHeight` (60) and `AppConstants.QuickChat.maxPanelHeight` (600) while keeping its bottom edge anchored.
- **FR-007**: WardenApp MUST register the user's chosen quick-chat combination as a system-wide global hotkey and toggle the panel when it fires. When registration fails (Carbon returns non-`noErr`, e.g. the combination is owned by another app), the Hotkeys settings tab MUST surface a visible warning recommending a different combination; the in-app menu shortcut path MUST continue to work.
- **FR-008**: WardenApp MUST provide configurable actions grouped by category, persist each shortcut across launches, and support per-action and reset-all-to-default operations.
- **FR-009**: Non-global actions (clipboard/chat/navigation) MUST be dispatched in-app via notifications and MUST NOT require Accessibility permissions.
- **FR-010**: Existing single-service chat, settings, and persistence MUST continue to behave as before whether or not multi-agent or quick chat is used.

### macOS UX Requirements

- **UX-001**: The multi-agent service selector MUST show each configured service with its model, allow selecting up to `AppConstants.MultiAgent.maxConcurrentServices`, disable further selection once the limit is reached, and clearly indicate the limit.
- **UX-002**: Agent columns MUST clearly show which service produced each answer, streaming progress, and any per-column error.
- **UX-003**: The quick-chat panel MUST be borderless and visually distinct (Spotlight-like), draw its own shadow/shape, and handle dragging within its SwiftUI content rather than relying on native title-bar movement.
- **UX-004**: The Hotkeys settings tab MUST group actions by category with icons, show current display strings, provide inline recording plus reset controls, and display a visible warning when the global quick-chat hotkey fails to register.

### Data, Migration, and Privacy Requirements

- **DP-001**: Hotkey configurations are persisted as display strings in application preferences keyed by action id; no Core Data schema change is required.
- **DP-002**: The global hotkey uses the Carbon `RegisterEventHotKey` API scoped to the application event target; it MUST unregister cleanly before re-registering to avoid duplicate handlers.
- **DP-003**: Diagnostic logging around hotkeys MUST NOT expose user data; key names are treated as low-sensitivity and any richer logging is DEBUG-only.
- **DP-004**: Multi-agent dispatch MUST reuse existing per-service credentials/handlers; it MUST NOT introduce a new plaintext secret store or transmit prompts to services the user did not select.

### Key Entities

- **AgentResponse**: One service's contribution to a multi-agent turn — service name, service type, model, accumulating response text, completion flag, optional error, timestamp.
- **KeyboardShortcut**: A key plus a modifier OptionSet (command/option/control/shift), round-trippable to/from a display string like `⌘⇧C`.
- **HotkeyAction**: A configurable action with id, name, description, default shortcut, notification name, and category (Chat/Clipboard/Navigation).
- **Quick Chat Panel**: A borderless floating `NSPanel` hosting the quick-chat SwiftUI view, with clamped dynamic height and focus-driven visibility.

## Compatibility and Scope

- **Affected modules**: `Warden/Utilities/MultiAgentMessageManager.swift`, `Warden/UI/Chat/MultiAgentServiceSelector.swift`, `Warden/UI/Chat/MultiAgentResponseView.swift`, `Warden/UI/Chat/QuickChatView.swift`, `Warden/Utilities/FloatingPanelManager.swift`, `Warden/Utilities/GlobalHotkeyHandler.swift`, `Warden/Models/HotkeyModels.swift`, `Warden/UI/Preferences/TabHotkeysView.swift`, plus focused tests under `WardenTests/`.
- **Existing behavior preserved**: All single-service flows, persistence, and settings remain unchanged when these features are unused.
- **Out of scope**: Increasing the three-agent concurrency limit; merging multi-agent answers automatically; global hotkeys for actions other than quick chat; Accessibility-based system automation.
- **Dependencies**: Carbon HIToolbox (`RegisterEventHotKey`), AppKit `NSPanel`, existing `APIServiceFactory`/`ChatService`, and `AppConstants.DefaultHotkeys`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can send one prompt to up to three services and see three independent, correctly-labeled answers in a single turn.
- **SC-002**: Stopping a multi-agent turn cancels every in-flight agent with no dangling in-progress state.
- **SC-003**: The quick-chat panel can be summoned by hotkey while another app is frontmost and dismissed by Escape or focus loss.
- **SC-004**: A changed quick-chat shortcut persists across relaunch and the previous combination no longer triggers the panel.
- **SC-005**: Deterministic XCTest coverage for `KeyboardShortcut` display-string round-trip, the three-agent concurrency cap (`AppConstants.MultiAgent.maxConcurrentServices`), and `AgentResponse` state transitions passes without live credentials or paid providers. No AppKit/NSPanel-focus or global-hotkey-firing tests are included (non-deterministic).

## Assumptions

- The three-service concurrency limit (`prefix(3)`) is intended product behavior, not an accident.
- Carbon `RegisterEventHotKey` remains available and does not require Accessibility permission for a single app-scoped hotkey.
- Non-global hotkey actions are delivered through `NotificationCenter` and handled by the appropriate in-app views.
- `KeyEquivalent`/key-code maps cover the supported ASCII/navigation keys; unmapped keys degrade gracefully.
