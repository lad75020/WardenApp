# Research: Persistence and Chat History

## Decision 1: Model missing service as an existing optional relationship

- **Decision**: Do not add a Core Data attribute or a new model version for unavailable chats. Treat a `ChatEntity` with no `apiService`, or one whose existing service cannot form an `APIServiceConfiguration`, as unavailable at runtime.
- **Rationale**: The current model defines `ChatEntity.apiService` as an optional, nullifying relationship. It already represents a service deleted or unavailable through normal Core Data lifecycle, avoids a migration, and preserves the chat/messages/project/persona relationship.
- **Alternatives considered**:
  - Add a persisted availability enum: rejected because it duplicates derived validation state and introduces an unnecessary migration risk.
  - Delete invalid chats on load: rejected by the clarified requirement because it silently destroys user history.

## Decision 2: Keep `ChatStore` as lifecycle coordinator

- **Decision**: Put availability classification, valid-service lookup, remapping, and persistence mutation in `ChatStore`; keep SwiftUI views presentation-only.
- **Rationale**: `ChatStore` already owns Core Data chat loading, JSON import, deletion, project operations, and context saving. This preserves the project’s module boundaries and centralizes access to the view context.
- **Alternatives considered**:
  - Let `ChatView` directly fetch/mutate service records: rejected because it scatters Core Data ownership into presentation code.
  - Add a general recovery manager: rejected because the behavior is narrowly scoped to chat persistence and existing store methods.

## Decision 3: Repair by explicit remapping to an existing valid service

- **Decision**: A user selects an existing valid service to repair an unavailable chat. If no valid service exists, recovery navigates to the current service settings rather than offering inline provider creation/editing.
- **Rationale**: This is the clarified product decision. It retains control with the user, preserves message history, avoids secret handling in recovery UI, and reuses existing service validation/settings behavior.
- **Alternatives considered**:
  - Automatically attach a default service: rejected because it can silently change provider/model context.
  - Rebuild a full service editor inside chat recovery: rejected as out of scope and duplicates existing settings.
  - Keep unavailable chats hidden: rejected because it obscures retained user content.

## Decision 4: Preserve safe migration and local-store fallback behavior

- **Decision**: Keep the current one-time JSON import and persistent-store fallback semantics, but ensure neither causes unavailable chats to be deleted or diagnostic leakage to be added.
- **Rationale**: `migrateFromJSONIfNeeded()` already avoids setting its completion key and removing the source file after a failed save. `PersistenceController` already uses a temporary in-memory fallback if loading the store fails. This feature must preserve these recovery paths and provide user-safe state.
- **Alternatives considered**:
  - Reset the persistent store automatically: rejected because it destroys recoverable user data.
  - Add an automatic backup/export pipeline: rejected as out of scope.

## Decision 5: Preserve secure transformer/message compatibility

- **Decision**: Keep `RequestMessagesTransformer` secure-unarchive allow-list behavior and current message attachment reference format; add regression coverage around retained chats rather than replacing encodings.
- **Rationale**: The transformer already uses `NSSecureUnarchiveFromDataTransformer` and a limited class allow-list. The feature requires safe restoration, not a new message serialization format.
- **Alternatives considered**:
  - Migrate `requestMessages` to a new serialized schema: rejected because it adds migration complexity without a user need.
  - Treat a malformed request-message transform as grounds to delete a chat: rejected because recovery must preserve unrelated valid history.

## Decision 6: Test with isolated Core Data and controlled UI fixtures

- **Decision**: Use in-memory `PersistenceController` tests for store behavior and dedicated UI-test launch fixtures for unavailable/repaired/no-service states; do not invoke real providers.
- **Rationale**: Existing app-shell tests already establish launch-argument test mode. Core Data behavior can be deterministically tested below UI, while recovery affordances need an end-to-end accessibility/focus check.
- **Alternatives considered**:
  - Test against the user’s normal data store: rejected due to destructive-risk and nondeterminism.
  - Depend on a live provider: rejected by constitution and test determinism requirements.

## Risk Register

| Risk | Mitigation |
|---|---|
| Current `loadFromCoreData()` deletes invalid chats | Establish a failing regression test first; remove delete/save cleanup behavior and retain availability state. |
| Repair accidentally alters message/context history | Compare chat ID, ordered message IDs/bodies, request messages, project, persona, and timestamps before/after remap. |
| Selected-chat reference survives explicit deletion | Clear selection before deletion and test the resulting empty/safe state. |
| Recovery UI exposes credentials | Recovery takes existing `APIServiceEntity` choices only; it does not access `TokenManager` or credential text. |
| Core Data threading violation | Perform fetch/mutation/save through `ChatStore` on the view context queue and confine published/UI changes to main actor. |
| UI fixture cannot create a valid provider | Extend the existing test support seam to seed only local Core Data entities with no actual network activity. |
