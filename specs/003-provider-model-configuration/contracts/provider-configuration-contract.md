# Provider Configuration Contract

## Lifecycle API Contract

The provider configuration boundary returns user-safe, typed outcomes rather than relying on UI-side Core Data/Keychain/log inspection.

| Operation | Preconditions | Success | Failure invariants |
|---|---|---|---|
| Create | Valid endpoint; token transport is allowed | New saved service with unique UUID; Keychain credential stored only when applicable | No token in persistent service data/logs; no partially selected invalid default |
| Edit | Existing valid saved service; valid endpoint | Updated non-secret metadata and matching UUID credential state | Last known-good service remains recoverable; safe user error only |
| Duplicate | Existing saved service | New UUID/new object identity and independent copied credential slot | Original metadata/token untouched; no copy credential if metadata persistence fails |
| Delete | Existing saved service and explicit confirmation | Entity removed, matching credential removed, matching default cleared | Failed entity save leaves entity, credential, and default untouched |
| Set default | Existing persisted service | URI reference updated | Never save a transient/dangling object reference |

## Network Operation Contract

| Action | Preconditions | Required behavior |
|---|---|---|
| Fetch models | User initiated; syntactically valid endpoint; token transport policy passes | Create client via `APIServiceFactory`; use provider-supported discovery; preserve selected model on failure; ignore stale/cancelled result |
| Test service/model | User initiated; syntactically valid endpoint; token transport policy passes; local path access granted when needed | Use factory client with bounded request; report success only for valid response; map failures to redacted categories |
| Local-model access | Explicit user action | Native directory chooser creates/uses security-scoped bookmark; cancellation/denial changes no configuration |

## Safety Contract

- No operation sends a credential to remote plaintext HTTP.
- No operation emits credentials, authorization values, raw provider response bodies, or private prompts to UI, logs, or test diagnostics.
- Discovery/testing never changes persisted model/default/service values without an explicit save/set-default action.
- An image-generation configuration cannot expose streamed response behavior.
- Default deletion clears the default; it does not choose a replacement.
