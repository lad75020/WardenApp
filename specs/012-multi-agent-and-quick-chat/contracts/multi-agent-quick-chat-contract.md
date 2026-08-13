# Contract: Multi-Agent and Quick Chat

## 1) Multi-Agent Selection and Dispatch

### Interface and Limits

- Maximum concurrent services per dispatch MUST be `AppConstants.MultiAgent.maxConcurrentServices`.
- UI selection (`MultiAgentServiceSelector`) MUST disable adding services beyond the limit and show current count.
- Runtime manager (`MultiAgentMessageManager.sendMessageToMultipleServices`) MUST further constrain the active send set to the same limit.

### Per-Agent State

- Every dispatch creates one `AgentResponse` per selected service.
- Each `AgentResponse` MUST carry:
  - `serviceName`, `serviceType`, `model`
  - response text
  - completion flag
  - optional error
  - timestamp
- UI MUST render outputs independently by agent, preserving each column’s status.

### Cancellation

- Stop behavior MUST:
  - cancel all in-flight tasks,
  - mark incomplete responses as complete (with cancellation-state error text),
  - avoid dangling in-progress state.

## 2) Quick Chat Panel

### Global toggle flow

- Quick-chat hotkey invokes `FloatingPanelManager.shared.togglePanel()` through the existing action callback.
- `FloatingPanelManager` continues to control open/close behavior, reset notification, and focus handling.

### Sizing behavior

- Panel height MUST remain within:
  - minimum: `AppConstants.QuickChat.minPanelHeight`
  - maximum: `AppConstants.QuickChat.maxPanelHeight`
- Existing resize semantics remain: updates apply to panel bounds while keeping bottom edge anchor semantics stable.

## 3) Global Hotkey Registration and Failure UX

### Registration behavior

- Registration remains through Carbon `RegisterEventHotKey` and current target/handler model.
- On registration success: no warning is shown.
- On registration failure (e.g. Carbon non-`noErr` status) or unsupported key mapping: registration MUST be represented in a surfaced user state.

### User-visible warning

- `TabHotkeysView` MUST present a clear, accessible warning in the Hotkeys preferences when quick-chat registration fails.
- Warning must include recommendation to choose another combination.

## 4) Privacy and Safety

- No user prompts, credentials, or sensitive response content appear in hotkey-warning UI.
- Logging remains low-sensitivity and existing logging structure is preserved.
- No schema migration and no persistence model changes.

