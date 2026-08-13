# Data Model: Multi-Agent and Quick Chat

## Persistence Scope

**No Core Data schema changes are required.**

### Hotkey persistence (existing)

- `HotkeyManager` stores per-action display shortcuts in `UserDefaults` under key: `hotkey_<actionId>`.
- Existing actions: `copyLastResponse`, `copyChat`, `exportChat`, `copyLastUserMessage`, `newChat`, `quickChat`.
- `quickChat` remains the only global system-hotkey action.

### Chat persistence (existing)

- Quick chat and regular chat messages continue through existing `ChatEntity` / `MessageEntity` Core Data models.
- Multi-agent responses are persisted with existing fields:
  - `MessageEntity.isMultiAgentResponse`
  - `MessageEntity.agentServiceName`
  - `MessageEntity.agentServiceType`
  - `MessageEntity.agentModel`
  - `MessageEntity.multiAgentGroupId`

No schema changes needed for this feature.

## Value/Object Model

### `AgentResponse`

- Location: `Warden/Utilities/MultiAgentMessageManager.swift`
- Fields:
  - `id: UUID`
  - `serviceName: String`
  - `serviceType: String`
  - `model: String`
  - `response: String`
  - `isComplete: Bool`
  - `error: APIError?`
  - `timestamp: Date`
  - derived `displayName` (`serviceName (model)`)

### `KeyboardShortcut`

- Location: `Warden/Models/HotkeyModels.swift`
- Fields:
  - `key: String`
  - `modifiers: KeyboardModifiers` (`command`, `option`, `control`, `shift`)
- Behavior:
  - `from(displayString:)` parses glyphs + key
  - `displayString` emits glyph string
  - `swiftUIShortcut` maps to `SwiftUI.KeyboardShortcut`

### App constants (new)

- Location: `Warden/Configuration/AppConstants.swift`
- New nested definitions:
  - `AppConstants.MultiAgent.maxConcurrentServices`
  - `AppConstants.QuickChat.minPanelHeight`
  - `AppConstants.QuickChat.maxPanelHeight`

### Global hotkey registration state (new)

To make registration failure user-visible, the hotkey handler will expose a state object/observable representing the last quick-chat registration outcome:

- `none` / `registered` / `unsupportedKey` / `registrationFailed(status)` / `error(message)`.
- This is consumed by `TabHotkeysView` as a warning surface.
- Failure states remain user-safe (no full key or credential details beyond safe combination text).

## Invariants

1. Multi-agent selection and dispatch never exceed `AppConstants.MultiAgent.maxConcurrentServices` in effective execution.
2. Quick chat panel height remains within `[AppConstants.QuickChat.minPanelHeight, AppConstants.QuickChat.maxPanelHeight]`.
3. Quick-chat shortcut failure is visible and actionable instead of silent-only behavior.
4. Existing chat persistence remains unchanged when these features are unused.

