# Quickstart & Verification: MCP Tool Integration

## Manual smoke test (optional, requires a local MCP server)

1. Open Settings → MCP Agents → +.
2. Name it, choose Stdio, set Command `npx`, Arguments `-y @modelcontextprotocol/server-filesystem /tmp`, tap Test → expect "Success! Found N tools."
3. Save, then Connect → status dot turns green with the tool count.
4. In a chat, open the MCP tools popover, enable the agent, and send a prompt that needs a filesystem tool.
5. Watch the tool-call progress (calling → executing → completed). After the answer, reload the chat and confirm the "N tools used" record persists and expands.
6. Add an env var `API_KEY=secret123`, save, and confirm (below) the value is not stored in plaintext.

## Deterministic verification (no live server)

Focused unit tests under `WardenTests/MCP/MCPToolIntegrationTests.swift` cover:

- Sensitive-key detection for `token/key/secret/password/passwd/auth/bearer/credential`.
- Secret marking on save produces a `keychain://mcp-env/<id>/<key>` marker and stores the raw value in the Keychain; resolution returns the original; delete removes it.
- `toolOwner` routing throws a readable 404 for an unknown tool.
- Argument/result serialization shape (`[String: Any]` ⇄ JSON) for text/image/resource content.

Run focused tests:

```bash
xcodebuild -project Warden.xcodeproj -scheme Warden \
  -destination 'platform=macOS,arch=arm64' test \
  -only-testing:WardenTests/MCPToolIntegrationTests
```

Build:

```bash
xcodebuild -project Warden.xcodeproj -scheme Warden \
  -destination 'platform=macOS,arch=arm64' build
```

Full suite (report only real, pre-existing blockers such as the known `AppShellUITests` failures):

```bash
xcodebuild test -project Warden.xcodeproj -scheme Warden \
  -destination 'platform=macOS,arch=arm64'
```

## Privacy review checklist

- [ ] Persisted `MCPServerConfigs` contains no plaintext sensitive env value (only markers).
- [ ] Deleting a server removes its Keychain env secrets.
- [ ] No tool arguments/results or secrets appear in release logs (DEBUG shows only counts/lengths).
- [ ] Auto-connect remains off by default.

## Verification record

_(to be filled during /speckit-implement)_
