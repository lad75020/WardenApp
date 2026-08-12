# Research: Personas and Model Selection

## Decision 1: Make persona selection behavior-only

- **Decision**: Selecting or clearing a persona changes only `ChatEntity.persona`; it does not change the chat's `apiService` or `gptModel`.
- **Rationale**: The approved clarification requires a persona's system message and temperature to take effect without unexpectedly moving an active conversation to another service or model. Existing request construction already reads `chat.persona?.systemMessage`, and request managers already derive temperature from `chat.persona?.temperature` for subsequent requests.
- **Alternatives considered**:
  - Automatically apply `PersonaEntity.defaultApiService` during selection — rejected because it violates the approved behavior and silently changes provider/model.
  - Copy a persona's message and temperature into chat fields — rejected because it duplicates state and loses the reusable persona relationship.

## Decision 2: Make default-service application explicit, validated, and atomic

- **Decision**: Show an explicit action only when the selected persona has a default service. Before changing the chat, validate that the default service belongs to the current managed-object context, has a usable type and model, and that the model is currently selectable through the same cache/visibility/capability rules as the model selector. On success, update service and model together, save once, then post the chat-scoped `RecreateMessageManager` notification.
- **Rationale**: This preserves the existing message-manager recreation boundary while preventing a stale/deleted service or an unavailable model from becoming active.
- **Alternatives considered**:
  - Trust the Core Data relationship alone — rejected because the service may be deleted, malformed, or no longer expose its configured model.
  - Re-fetch models synchronously from the network before changing — rejected because a UI action must remain responsive and must not create an unnecessary remote request. Cached/configured availability is authoritative for this interaction; an unavailable state can ask the user to refresh through existing model-fetch lifecycle.

## Decision 3: Centralize the chat configuration mutation

- **Decision**: Extract an app-owned, testable utility/service for validating and applying a provider/model pair to a chat. `StandaloneModelSelector`, `FavoriteQuickAccessBar`, and the persona default-service action call that single path.
- **Rationale**: The repository currently duplicates mutation/save/notification logic, and those paths differ in validation. One coordinator preserves an atomic update and a consistent failure result without moving Core Data ownership into view rendering code.
- **Alternatives considered**:
  - Patch each UI action independently — rejected because validation and failure behavior would drift.
  - Add provider-specific logic to `APIProtocol` — rejected because this is local UI/persistence coordination, not transport behavior.

## Decision 4: Treat provider plus model as the stable identity

- **Decision**: Use a typed or encoded provider/model key whose encoding cannot collide when model identifiers contain underscores, colons, or other provider-like separators. Use this identity for SwiftUI `ForEach`, favorites, filtering, and selected-state comparisons.
- **Rationale**: The current selector uses `"provider_model"`, while favorites use `"provider:model"`; both formats are fragile for arbitrary model IDs and the quick-access bar identifies rows by model only. Stable identity is required by UX-003 and prevents duplicate-provider rows from being rendered or updated incorrectly.
- **Alternatives considered**:
  - Keep `ForEach(..., id: \.model)` — rejected because two providers can expose the same model identifier.
  - Infer identity by splitting strings in each UI view — rejected because parsing rules would be inconsistent and unsafe for separators in IDs.

## Decision 5: Preserve existing persistence; add no Core Data model version

- **Decision**: Reuse `ChatEntity.persona`, `ChatEntity.apiService`, `ChatEntity.gptModel`, `PersonaEntity.defaultApiService`, `APIServiceEntity.selectedModels`, and the existing non-secret favorite preference. Do not change the Core Data model.
- **Rationale**: These fields express the required relationships. Avoiding a schema change protects existing stores and eliminates migration risk.
- **Alternatives considered**:
  - Persist an extra per-chat persona-service preference — rejected because the explicit action changes the existing active pair and has no separate state requirement.
  - Store credentials or full service configuration in favorites/personas — rejected by the privacy model; only non-secret identifiers may remain in local preferences.

## Decision 6: Resolve canonical UI ownership before editing duplicates

- **Decision**: Treat `Warden/UI/Chat/BottomContainer/PersonaSelectorView.swift` as the current target-member implementation: it is the file referenced by `Warden.xcodeproj`. Remove or rename the unreferenced duplicate under `Warden/UI/Chat/ChatParameters/` only if needed to eliminate future ambiguity, rather than changing both copies.
- **Rationale**: Two files define identical Swift view types, but the Xcode project lists only the BottomContainer copy. Editing both would obscure the canonical behavior and risks duplicate symbols if target membership changes.
- **Alternatives considered**:
  - Update both duplicate files — rejected because it creates divergent sources with the same type names.
  - Alter target membership immediately — rejected because this feature needs a minimal behavioral change, not broad project-file churn.

## Decision 7: Keep model metadata optional and local-cache derived

- **Decision**: Reuse `ModelInfoTooltip` and `ModelMetadataCache` only for already-available metadata. Render capabilities, pricing, context, freshness, and unknown states defensively; do not fetch metadata from view rendering.
- **Rationale**: Metadata may be absent or stale. The selector must keep working without it and must not surface API keys, prompts, or service secrets.
- **Alternatives considered**:
  - Require metadata before displaying a model — rejected because metadata is optional and would hide otherwise valid choices.
  - Trigger network refresh from every hover/row render — rejected for privacy, latency, and performance reasons.

## Decision 8: Test deterministic extracted policy, then verify native UI

- **Decision**: Add XCTest coverage for provider/model identity, availability policy, malformed local preference recovery, and chat mutation decisions with an in-memory Core Data store. Add a focused XCUITest only for the user-visible controls if stable launch-state fixtures can be installed without credentials; otherwise record a precise manual macOS test path.
- **Rationale**: The constitution requires deterministic tests without paid credentials. Pure policy tests are reliable; native popovers and persistent application state need test fixtures/accessibility identifiers before an end-to-end test is credible.
- **Alternatives considered**:
  - Test against live provider catalogs — rejected because it needs credentials, makes tests nondeterministic, and may invoke paid services.
  - Rely only on manual testing — rejected because critical persistence/validation behavior is unit-testable.
