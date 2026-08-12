# Data Model: Personas and Model Selection

## Schema Decision

**No Core Data schema change.** The feature reuses existing entities and attributes. Existing persistent stores remain compatible; no new model version or migration is required.

## Existing Persistent Entities

### PersonaEntity

| Field / relationship | Role | Validation / behavior |
|---|---|---|
| `id` | Stable local persona identity | Assigned for new personas; never use a display name as identity. |
| `name` | User-visible name | Required, trimmed/non-empty before save; duplicates may be presented but must not break selection identity. |
| `color` | SF Symbol name | Optional; render a safe default (`person.circle`) when absent or invalid. |
| `systemMessage` | Reusable instruction text | Required by existing editor; may be large; never log its content. Used only in subsequent request construction. |
| `temperature` | Persona generation setting | Persisted to one decimal place; used by existing message managers for subsequent requests. |
| `order` | Display ordering | Existing list sorts ascending; reordering must keep deterministic ordering. |
| `defaultApiService` | Optional configured service relationship | Never applied merely by selecting the persona. May be explicitly applied after availability validation. |

### ChatEntity

| Field / relationship | Role | State transition |
|---|---|---|
| `persona` | Active reusable behavior configuration | Persona select/clear updates this relationship, saves, and recreates only this chat's message manager. It leaves `apiService` and `gptModel` unchanged. |
| `apiService` | Active configured provider service | Changes only through validated explicit model/default-service action. |
| `gptModel` | Active model identifier | Changes in the same transaction as `apiService`; must be selectable for that service. |
| `updatedDate` | Update timestamp | Refresh when a provider/model pair changes. |
| `systemMessage`, `temperature` | Chat fallback behavior | Remain unchanged when a persona is selected; request construction already prioritizes the persona. |

### APIServiceEntity

| Field / relationship | Role | Validation / behavior |
|---|---|---|
| `type` | Provider identifier | Required to resolve cache, visibility, and display rules. |
| `model` | Service's configured default model | Used only after it passes availability validation. |
| `url` | Configured endpoint | Existing quick access verifies a non-empty URL; no endpoint or secret is displayed in selector metadata. |
| `selectedModels` | Optional JSON-encoded visibility selection | `nil` means show all; an empty set means explicitly show none. Decode errors fall back safely and are logged without sensitive data. |
| `imageUploadsAllowed` | Capability constraint | Image-generation metadata is actionable only when the configured service permits it. |

## Local Preference Data

### Favorite model

A favorite represents a provider/model pair only. It contains no credential, endpoint, prompt, or conversation data.

| Property | Rule |
|---|---|
| Provider | Normalized configured provider identifier. |
| Model ID | Opaque provider model identifier; do not split it on a delimiter without a lossless encoding. |
| Persistence | Existing `@AppStorage("favoriteModels")` JSON data remains local. |
| Malformed stored data | Decode failure produces an empty in-memory set and safe diagnostic; the selector remains usable. |
| Eligibility | A favorite is displayed/actionable only if its provider is currently configured and the exact pair passes availability policy. |

## Derived Types / Policies

### ModelIdentity

A small `Equatable`, `Hashable`, `Sendable` value owned by `Warden/Utilities/` should hold `provider` and `modelID` as independent fields. It is the source of truth for view identity and favorite keys. If a serialized preference key is required, encode/decode it losslessly and reject malformed input rather than guessing.

### ModelAvailability

A derived policy result for a candidate pair:

| Condition | Result |
|---|---|
| No configured service with matching provider or referenced service is deleted | unavailable; do not mutate chat. |
| Model missing from cache/configured static model list | unavailable until existing refresh path provides it. |
| Custom visibility exists and excludes the model | unavailable, except only where existing documented favorite-visibility behavior permits it. |
| Metadata explicitly identifies image generation but service disallows image uploads | unavailable. |
| Metadata absent/stale/incomplete | do not reject an otherwise available model; show reduced metadata. |
| Valid service and model | eligible for an atomic active-pair update. |

## State Transitions

### Persona selection

`no persona` or `persona A` → `persona B`:
1. Assign `chat.persona`.
2. Preserve `chat.apiService` and `chat.gptModel`.
3. Save the managed object context.
4. On success, notify `RecreateMessageManager` with only that chat's UUID.
5. On save failure, restore/refresh safely and show an accessible recoverable error; do not claim the new persona is selected.

### Explicit persona default-service application

`selected persona with default service` → `validated active provider/model pair`:
1. Resolve the persona's current service relationship.
2. Validate the provider/model against the availability policy.
3. Set `chat.apiService`, `chat.gptModel`, and `updatedDate` together.
4. Save once.
5. On success, emit the chat-scoped recreation notification.
6. On failure, leave the previously active pair intact and present a non-sensitive error.

### Favorite toggle

`not favorite` ↔ `favorite`:
1. Toggle the provider/model identity in local non-secret preference storage.
2. Encode safely.
3. If persistence fails, preserve a usable UI state and log only the error category/details permitted by privacy policy.

## Compatibility and Privacy

- No model, persona, favorite, or metadata operation stores API keys/tokens in Core Data or `UserDefaults`.
- Existing chats retain their relationships and fallback system messages/temperatures.
- Existing favorites and selected-model JSON are read defensively; malformed optional values cannot crash startup or selector rendering.
- This feature introduces no sync, analytics, tracking, or new remote destination.
