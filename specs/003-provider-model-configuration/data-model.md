# Data Model: Provider and Model Configuration

## Existing Persisted Types (No Schema Change)

### API Service Configuration (`APIServiceEntity`)

| Field | Purpose | Privacy classification |
|---|---|---|
| `id: UUID` | Stable service identity and credential lookup key | Local non-secret identifier |
| `name` | User-facing service label | Local metadata |
| `type` | Provider/factory mapping key | Local metadata |
| `url: URL` | Provider/self-hosted endpoint | Local metadata; potentially sensitive endpoint but never a credential |
| `model` | Selected preset, discovered, custom, or local model identifier/path | Local metadata; local path remains protected by file access controls |
| `contextSize` | Configured message context size | Local metadata |
| `useStreamResponse` | Streaming preference | Local metadata |
| `generateChatNames` | Chat naming preference | Local metadata |
| `imageUploadsAllowed` | Image capability preference | Local metadata |
| `addedDate` / `editedDate` | Service ordering/audit metadata | Local metadata |
| `defaultPersona` | Optional local persona relationship | Local metadata relationship |

### Credential Reference (Keychain only)

| Element | Contract |
|---|---|
| Owner | `TokenManager` using KeychainAccess service `fr.dubertrand.WardenAI` |
| Lookup identity | Stable service UUID string |
| Storage | Existing Keychain token bundle plus legacy per-item migration |
| Prohibited locations | Core Data, UserDefaults, logs, error text, fixtures, source control, exports |
| Lifecycle | Create/update after metadata persistence succeeds; duplicate into a new UUID slot after copied metadata saves; delete after entity deletion succeeds; failed operation preserves recovery state |

### Default Service Reference (`@AppStorage("defaultApiService")`)

| Field | Contract |
|---|---|
| Value | Service managed-object URI string only |
| Set | Explicit user action in services Settings |
| Delete behavior | Clear after the referenced service has been deleted successfully |
| Invalid reference | Treat as no default; do not route silently to another provider |

## In-Memory UI State

- **Draft fields**: name, provider type, endpoint, credential (memory only until save), model, context/response choices.
- **Operation state**: one task/generation per model-refresh or connection-test action; operation identity includes type/endpoint/credential revision.
- **Model options**: discovered list when current and successful; otherwise provider defaults/custom choice. A failed refresh must never overwrite the persisted selected model.
- **User notification**: redacted category and actionable copy only; no raw request/response/credential.

## State Transitions

1. **Create**: Validate draft → persist new metadata with UUID → write credential if supplied/applicable → select newly saved entity. On token failure, report safe failure and retain/recover metadata according to the manager's explicit outcome contract.
2. **Edit**: Validate draft → persist non-secret metadata → update/clear Keychain token for same UUID as requested → retain prior known-good configuration if a transaction fails.
3. **Duplicate**: Make a new independent entity/UUID → save it → copy credential into new UUID slot only after save → select copy. The original remains unchanged.
4. **Delete**: Persist entity deletion → remove matching credential → clear default if its URI matches removed entity. A failed persistent deletion leaves credential/default untouched.
5. **Set default**: Save selected entity's managed-object URI to `@AppStorage` only after it is a valid persisted entity.
6. **Model refresh/test**: Validate URL/transport → create temporary factory client → run user-initiated operation → apply output only if still current; no persistence changes until explicit save.
