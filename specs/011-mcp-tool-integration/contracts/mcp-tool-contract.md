# Contract: MCP Configuration, Secrets, and Tool Execution

This contract documents the behavioral guarantees of the MCP subsystem. It is an internal application contract (no external HTTP API is exposed by WardenApp).

## C1 — Configuration lifecycle (`MCPManager`)

- `addConfig(_:)` / `updateConfig(_:)` persist a sanitized config; `updateConfig` reconnects if the server is enabled and disconnects first.
- `deleteConfig(id:)` removes the config, disconnects, and deletes all associated Keychain secrets.
- `loadConfigs()` migrates any plaintext sensitive env values found in persisted config into the Keychain and rewrites markers.
- **Guarantee**: persisted config never contains a plaintext sensitive env value after a save/load cycle.

## C2 — Secret storage

- Input: `environment[key] = value` where `isSensitiveEnvironmentKey(key)` is true and `value` is non-empty and not already a marker.
- Effect: `value` stored at Keychain identity `mcp_<configID>_<key>`; persisted `environment[key]` becomes `keychain://mcp-env/<configID>/<key>`.
- `resolvedEnvironment(for:)` returns a dictionary with markers replaced by their Keychain values for subprocess launch.
- **Guarantee**: round-trip `store → marker → resolve` returns the original secret; delete removes it.

## C3 — Connection and discovery

- `connect(config:)` requires `enabled == true`; sets status `.connecting`, builds the transport, connects a `Client`, lists tools, caches them, updates `toolOwner`, and sets `.connected(toolsCount:)`. On failure sets `.error(message)` and rethrows.
- `testConnection(config:)` connects a throwaway client, lists tools, returns the count, and tears down the transport via `defer`.
- **Guarantee**: status reflects the real connection outcome; test connections do not leak a running subprocess.

## C4 — Tool execution (`MessageManager.handleToolCalls` + `MCPManager.callTool`)

- Preconditions: the model returned one or more `ToolCall`s; the named tool exists in `toolOwner` and its client is connected.
- Steps per call: publish `.calling` → `.executing`; parse arguments JSON; on valid args call `MCPManager.callTool`; append a tool-result message; publish `.completed`/`.failed`.
- After all calls: re-request the completion with `tools: nil`.
- Error mapping:
  - Unknown tool / disconnected agent → thrown `NSError(code: 404)`, recorded as `.failed`.
  - Malformed arguments JSON → result `{"error":"Invalid arguments JSON"}`, `success = false`.
  - Thrown execution error → result `{"error":"<localizedDescription>"}`, `.failed`.
  - `Task.isCancelled` → clear status and complete with `CancellationError()`.
- **Guarantee**: a single tool failure does not abort the final answer; cancellation leaves no dangling in-progress status; no secret/argument/result appears in release logs.

## C5 — Result normalization

- MCP content items map to JSON-compatible dictionaries: `text`→`{type:text,text}`, `image`/`audio`→`{type,mimeType}`, `resource`→`{type:resource,uri,mimeType?,text?}`, `resourceLink`→`{type:resource_link,uri,name,title?,description?,mimeType?}`.
- **Guarantee**: `callTool` returns `[[String: Any]]` serializable by `JSONSerialization`.

## C6 — Persistence of tool calls

- Completed `WardenToolCallStatus` values are stored on the message via `MessageEntity.toolCallsJson` and re-render as a collapsed "N tools used" control after reload.
- **Guarantee**: messages without tool calls are unaffected and render as before.
