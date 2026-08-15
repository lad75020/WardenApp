# Data and persistence

WardenApp stores conversation data locally with Core Data and keeps credentials in the macOS Keychain. The data model is defined in `Warden/Store/wardenDataModel.xcdatamodeld/`.

## Persistent container

`PersistenceController` creates an `NSPersistentContainer` named `wardenDataModel`.

The normal store configuration:

- Uses the persistent store configured by Core Data.
- Enables automatic merging of parent-context changes.
- Uses a property-object-trump merge policy.
- Enables persistent history tracking.
- Enables remote-change notifications.

The application can select an in-memory store for App Shell UI tests. Persistence recovery tests can also point at a temporary fixture store through launch arguments and environment values.

If the persistent store cannot be opened, WardenApp shows a user-facing warning and attempts an in-memory store. The fallback protects the existing persistent store from being silently replaced, but current-session changes are not durable.

## Core Data entities

| Entity | Purpose | Important relationships/fields |
| --- | --- | --- |
| `APIServiceEntity` | Saved non-secret AI service configuration | Stable UUID, name, type, URL, model, context size, stream flag, image-upload flag, token identifier, selected models, default persona |
| `ChatEntity` | Conversation metadata and state | Ordered messages, service, persona, project, parent/child chats for branches, model, system message, pin and waiting state |
| `MessageEntity` | One chronological user or assistant record | Body, role/ownership, timestamp, agent metadata, search metadata, tool-call JSON, multi-agent group, waiting state, parent chat |
| `FileEntity` | Stored file attachment data | File name, type, size, text content, image data, thumbnail, UUID |
| `ImageEntity` | Stored image bytes and thumbnail | Image data, format, thumbnail, UUID |
| `PersonaEntity` | Reusable instruction profile | Name, symbol/color field, system message, temperature, order, optional default service |
| `ProjectEntity` | Chat organization and project metadata | Name, description, custom instructions, color, archive state, sort/order, summary dates, chats |

`ChatEntity.messages` is an ordered relationship. Branching uses the chat parent/child relationship and branch source identifiers. Deleting a service nullifies the chat service relationship rather than deleting the chat.

Message records keep search metadata and tool-call metadata as serialized fields. This allows the user-facing message to retain source/tool context after reload.

## ChatStore responsibilities

`ChatStore` is the main observable store for chats and projects. It runs on the main actor and owns the managed object context used by the UI.

Responsibilities include:

- Fetching chats with deterministic ordering.
- Restoring and clearing the selected chat.
- Creating, renaming, deleting, clearing, pinning, and archiving chats.
- Creating and managing projects.
- Moving chats between projects.
- Paginating large chat lists.
- Preserving chats whose service is unavailable.
- Repairing an unavailable chat by remapping its service.
- Importing compatible chat data with deduplication.
- Migrating legacy JSON history when the old `chats.data` path is present.
- Applying persistence recovery state without silently deleting valid objects.

The store intentionally retains invalid/unavailable history until an explicit repair or delete action. Automatic cleanup must not be used as a migration shortcut.

## Startup migration and patching

`WardenApp` runs `DatabasePatcher` during initialization. Current patches include:

- Adding built-in personas once.
- Repairing persona ordering.
- Applying image-upload defaults to known API services.
- Converting legacy persona color values to symbol names.
- Migrating older Ollama `/api/generate` URLs to the chat endpoint.
- Migrating legacy UserDefaults API configuration into a Core Data service.
- Moving a legacy token into Keychain.
- Associating the migrated default service with the default persona.

Migration flags in UserDefaults prevent a completed migration from running repeatedly. A migration failure is logged as a category-level error and must not expose the migrated token, request bodies, or private content.

## Configuration versus secrets

### Core Data

Core Data stores non-secret service configuration such as provider type, endpoint, model, context settings, display name, and a token identifier. It must not store the credential itself.

### UserDefaults

UserDefaults stores ordinary preferences and migration state. Examples include:

- Preferred model and color scheme.
- Onboarding and migration flags.
- Tavily search depth, result count, and include-answer preference.
- MCP server configurations after sensitive environment values are sanitized.
- Hotkey display strings.
- Default service references.

UserDefaults is not a secret store. Never put a provider key, bearer value, or MCP secret in it.

### Keychain

`TokenManager` stores service-keyed tokens in a Keychain bundle. The current source uses the Keychain service `fr.dubertrand.WardenAI`, the token prefix `api_token_`, and a bundle key. Legacy per-item entries can be read and migrated into the bundle.

MCP sensitive environment values use a separate token namespace and are represented in persisted configuration by a marker such as a Keychain-backed MCP environment reference. The clear value is restored only when the environment is resolved for a connection.

Current setup guidance uses the same Keychain service identifier as `TokenManager`. Older installations may still contain legacy Keychain items; do not remove them by guessing a service or account.

## Attachments

Attachment data is represented by `FileEntity` and `ImageEntity` where the current preparation path stores it. The application keeps the association between the stored attachment and its message through the conversation model.

Attachment operations must tolerate missing files, unreadable data, decoding failures, extraction failures, cancellation, and save-destination errors. A failed save must not delete or mutate the source.

## Backup and import

The application exposes user-initiated JSON backup/export and import paths. Safe behavior requires:

- Cancellation leaves existing data unchanged.
- Malformed data produces a visible non-destructive error.
- Imported objects are deduplicated where supported.
- Existing valid history is not overwritten by a failed import.
- Export includes only content the user explicitly selected.
- Credentials, authorization headers, and diagnostic-only data are excluded.

Treat exported chat files as sensitive because they can contain prompts, responses, system instructions, source metadata, tool results, and attachment content.

## Persistence recovery behavior

Recovery is intentionally conservative:

- A stale selected-chat identifier is cleared without deleting unrelated history.
- A service with no valid configuration leaves its chat available as unavailable.
- A Core Data load failure triggers a warning and temporary memory fallback.
- Persistent recovery test fixtures can reset or reuse an isolated temporary SQLite store.
- Persistence errors are reported without dumping raw content or secrets.

When investigating a store issue, preserve the original store and make a backup before destructive repair.

## Data lifecycle checklist

When adding a new persisted field or entity:

1. Update `wardenDataModel.xcdatamodeld`.
2. Decide whether the value is secret, non-secret configuration, or chat content.
3. Keep secret values in Keychain only.
4. Add migration/recovery behavior for older stores.
5. Add tests for fresh stores, upgraded stores, malformed values, and missing relationships.
6. Update this document and the matching feature specification.
7. Run the persistence recovery UI tests when applicable.
