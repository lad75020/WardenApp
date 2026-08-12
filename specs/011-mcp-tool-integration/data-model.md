# Data Model: MCP Tool Integration

> No Core Data schema change. Server configs and per-chat selections live in `UserDefaults`; secrets live in the Keychain; completed tool calls reuse `MessageEntity.toolCallsJson`.

## MCPServerConfig (`Warden/Core/MCP/MCPServerConfig.swift`)

`Codable, Identifiable, Hashable` value type.

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | Stable identity; namespaces Keychain secret identifiers. |
| `name` | `String` | User-facing label. Required (non-empty) for a valid config. |
| `transportType` | `TransportType` (`stdio` \| `sse`) | Selects execution path. |
| `command` | `String?` | Required for `stdio`; resolved via `/usr/bin/env`. |
| `arguments` | `[String]` | Split from a space-separated field in the sheet. |
| `environment` | `[String: String]` | Sensitive values replaced by keychain markers when persisted. |
| `url` | `URL?` | Required for `sse`. |
| `enabled` | `Bool` | Disabled agents cannot be selected in chat. |

**Validation**: `name` non-empty AND (`stdio` ⇒ `command` non-empty) OR (`sse` ⇒ `url` non-empty). Enforced by the add/edit sheet's `isFormValid`.

**Persistence**: Encoded array under `UserDefaults` key `MCPServerConfigs`. `sanitizedConfigForStorage` rewrites sensitive env values to `keychain://mcp-env/<id>/<key>`; `resolvedEnvironment` reverses this at connect time.

## Secret marker scheme

- Sensitive detection: key lowercased contains any of `token, key, secret, password, passwd, auth, bearer, credential`.
- Keychain identity: `TokenManager.setToken(value, for: "mcp_env", identifier: "mcp_<configID>_<key>")`.
- Persisted marker: `keychain://mcp-env/<configID>/<environmentKey>`.
- Lifecycle: written on save when a raw sensitive value is present; resolved on connect; deleted on config delete via `cleanupEnvironmentSecrets`.

## Tool (MCP SDK `Tool`)

- Discovered via `client.listTools()` on connect and cached in `serverTools[configID]`.
- Routed by name through `toolOwner: [String: UUID]` to the owning client for execution.

## WardenToolCallStatus (`Warden/Models/SearchModels.swift`)

`Equatable, Identifiable, Codable` enum. `id == toolName`.

| Case | Payload | Meaning |
|---|---|---|
| `calling` | `toolName` | Model requested the tool; execution not started. |
| `executing` | `toolName`, `progress?` | Tool is running. |
| `completed` | `toolName`, `success`, `result?` | Tool finished; `result` is JSON-compatible string. |
| `failed` | `toolName`, `error` | Tool failed; `error` is a readable message. |

**Persistence**: Encoded as JSON into `MessageEntity.toolCallsJson` (associated-object cached). Live state is published via `MessageManager.activeToolCalls` and `messageToolCalls`.

## Per-chat agent selection (`Warden/UI/Chat/ChatViewModel.swift`)

- `selectedMCPAgents: Set<UUID>` persisted under `UserDefaults` key `SelectedMCPAgents_<chatID>` as encoded JSON.
- Only enabled + connected agents contribute tools during a request.

## State transitions (server status)

```
disconnected → connecting → connected(toolsCount)
connecting → error(message)
connected → disconnected (manual or on delete)
```
