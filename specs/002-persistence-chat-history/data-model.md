# Data Model: Persistence and Chat History

## Schema Decision

**No Core Data schema migration is planned.** The existing model already contains all entities and relationships needed for retained unavailable chats. Availability is derived at restoration time and is not separately stored.

## Existing Entities Used

### ChatEntity

| Field / relationship | Role in this feature | Rules |
|---|---|---|
| `id` | Stable chat identity | Must remain unchanged by load, repair, and retained-history flows. |
| `messages` (ordered) | Conversation history | Preserve member order and message values during availability classification and repair. |
| `requestMessages` | Provider request history | Preserve existing secure-transformer representation; malformed values must not trigger chat deletion. |
| `apiService` (optional) | Service association | `nil` means unavailable; a non-nil service is available only if existing configuration validation succeeds. |
| `persona`, `project` | Local context | Preserve relationships through load and remap. |
| `createdDate`, `updatedDate`, `gptModel` | Chat metadata | Do not overwrite during classification; only normal user-driven changes may update timestamps. |

### APIServiceEntity

| Field / relationship | Role in this feature | Rules |
|---|---|---|
| `id`, `name`, `type`, `url`, `model` | Non-secret service metadata | A repair candidate must pass the existing configuration validation. |
| `tokenIdentifier` | Keychain lookup key | Never read, render, log, or copy it in recovery UI or ordinary chat persistence. |
| `defaultPersona` | Existing context relationship | Unchanged by chat repair. |

### MessageEntity

| Field / relationship | Role in this feature | Rules |
|---|---|---|
| `id`, `body`, `timestamp`, `own`, `chat` | Ordered retained message content | Must remain associated with the original chat when repaired. The feature must not log body content. |
| tool/search/multi-agent metadata | Existing historical metadata | Preserve unchanged; no recovery-specific transform. |

### ProjectEntity and PersonaEntity

| Entity | Role in this feature | Rules |
|---|---|---|
| `ProjectEntity` | Chat grouping/context | Repair does not change project membership. |
| `PersonaEntity` | Chat persona/context | Repair does not change persona association. |

## Derived Availability State

| State | Predicate | UI behavior | Allowed mutations |
|---|---|---|---|
| Available | `apiService` exists and existing configuration validation succeeds | Normal chat interaction | Normal existing chat behavior |
| Unavailable: missing service | `apiService == nil` | Show retained history and non-color unavailable status; sending disabled | Explicit remap or confirmed delete |
| Unavailable: invalid service | `apiService` exists but existing configuration validation fails | Show retained history and non-color unavailable status; sending disabled | Explicit remap or confirmed delete |
| No repair candidate | No locally configured valid service exists | Keep chat unavailable; guide user to existing service settings | Existing service creation/editing, then explicit remap |

## State Transitions

```text
Persisted chat
  ├─ valid linked service ───────────────> Available
  ├─ no linked service ──────────────────> Unavailable: missing service
  └─ invalid linked service ─────────────> Unavailable: invalid service

Unavailable + select valid existing service ─> Available (same chat/history/context)
Unavailable + no valid services ─────────────> Unavailable + existing settings route
Unavailable + confirmed delete ──────────────> Deleted (selection cleared first)
```

## Invariants

1. Automated loading never deletes a chat merely because its service is missing or invalid.
2. Repair changes only the chat’s service relationship after validating the chosen service; it does not mutate messages, request messages, project, persona, or identifier.
3. A migration/import is idempotent: repeating it does not duplicate a chat with the same identity.
4. All credentials remain in Keychain and outside `ChatEntity`, `MessageEntity`, fixtures, logs, and recovery UI.
5. Any Core Data save failure leaves the in-memory object graph and persistent store in a non-destructive, user-safe state; recovery feedback does not reveal private content or secret material.
