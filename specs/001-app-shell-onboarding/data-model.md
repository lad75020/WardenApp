# Data Model: App Shell and Onboarding

No Core Data schema change is required. The feature uses existing local entities and preference values.

## Welcome Experience State

Derived, non-persisted presentation state.

### Inputs

- `configuredProviderCount: Int` — number of locally configured provider records; must be non-negative.
- `chatCount: Int` — number of locally stored chats; must be non-negative.
- `hasCompletedOnboarding: Bool` — persisted local completion preference.
- `hasSelectedChat: Bool` — current-window selection state.

### Derived Modes

- `setupRequired` — no configured provider is present.
- `readyForFirstChat` — at least one provider is present and no chats exist.
- `readyForSelection` — at least one provider and at least one chat exist, but no chat is selected.
- `contentSelected` — a chat or project is selected; the welcome view is not shown.

### Validation Rules

- Provider and chat counts below zero are treated as zero by the resolver.
- Completion state changes whether setup is promoted, not whether Settings remains accessible.
- State derivation performs no network or credential validation.

## Onboarding Flow State

Ephemeral state owned by the onboarding presentation.

### Fields

- `currentStep: welcome | providerSetup | ready`
- `isCompleting: Bool` — guards the terminal action against duplicate activation.
- `hasCompletedOnboarding: Bool` — existing persisted local preference, written only on successful completion.

### State Transitions

```text
welcome --Next--> providerSetup
providerSetup --Back--> welcome
providerSetup --Next--> ready
providerSetup --Open Settings--> providerSetup + Settings visible
ready --Back--> providerSetup
ready --Start--> completed + guide closes + one new-chat request
```

### Validation Rules

- Back is unavailable on `welcome`.
- Next is unavailable on `ready`.
- Open Settings belongs to `providerSetup` and does not advance or complete onboarding.
- Start belongs to `ready` and accepts only the first activation while completion is in progress.

## Appearance Preferences

Existing local preferences; no migration.

| Preference | Values | Default | Rule |
|---|---|---|---|
| `preferredColorScheme` | `0` System, `1` Light, `2` Dark | `0` | Unknown values resolve to System. |
| `chatFontSize` | 10...24 points | 14 | UI limits selection to supported values. |
| `showSidebarAIIcons` | Boolean | true | Affects presentation only. |

## Window State

Existing local window state; no schema change.

- Main-window frame autosave name: `MainWindow`.
- Settings-window frame autosave name: `SettingsWindow`.
- Last-chat preference: `lastOpenedChatId`, storing a UUID string only after a valid chat is selected.
- Invalid or missing chat identifiers resolve to no selected chat and the appropriate welcome mode.

## Existing Persistence Relationships

- `ContentView` reads existing `ChatEntity` and `APIServiceEntity` collections.
- `ChatStore` remains responsible for JSON backup loading/saving and Core Data coordination.
- Provider secrets remain outside these entities in macOS Keychain and are not represented by this feature model.
