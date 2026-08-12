# Feature Specification: MCP Tool Integration

**Feature Branch**: `feature/time-machine-mcp-tool-integration`  
**Created**: 2026-08-12  
**Status**: Draft  
**Input**: User description: "Lets users configure MCP servers, securely store their environment secrets, select tools for chats, and monitor tool execution."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Configure and connect an MCP server (Priority: P1)

A user opens Settings, adds a Model Context Protocol (MCP) server by giving it a name and a transport (a local Stdio command or a remote SSE URL), optionally supplies command arguments and environment variables, tests the connection, and saves it. The saved server appears in a list with a live status indicator and its discovered tool count.

**Why this priority**: Without the ability to add and connect a server, no other MCP capability is reachable. This is the minimum useful increment.

**Independent Test**: Add a Stdio server pointing at a known local MCP command, test the connection, and confirm the reported tool count matches the server's advertised tools; delete it and confirm it disappears and its secrets are removed.

**Acceptance Scenarios**:

1. **Given** no MCP servers configured, **When** the user adds a valid Stdio server and taps Test, **Then** the app reports success with the number of discovered tools without persisting the server until Save is tapped.
2. **Given** a saved server, **When** the user taps Connect, **Then** the status transitions Connecting → Connected and the tool count is shown; **When** the endpoint is unreachable, **Then** the status shows an Error state with a readable message and no secrets in the message.
3. **Given** a saved server with environment secrets, **When** the user deletes it, **Then** the server is removed from the list and its Keychain-stored environment secrets are deleted.

---

### User Story 2 - Store MCP environment secrets securely (Priority: P1)

A user provides environment variables for a Stdio MCP server, some of which are secrets (API keys, tokens, passwords). The app stores sensitive environment values in the Keychain rather than in plaintext configuration, and the persisted configuration only contains a non-sensitive reference marker for those values.

**Why this priority**: MCP servers commonly require credentials; leaking them into `UserDefaults` or plaintext violates the project's privacy-first constitution.

**Independent Test**: Save a server whose environment includes a key named like `API_KEY`; inspect the persisted configuration store and confirm the secret value is replaced by a `keychain://mcp-env/...` marker and the real value is retrievable only via the Keychain and injected into the subprocess environment at connect time.

**Acceptance Scenarios**:

1. **Given** an environment variable whose key matches a sensitive pattern (token/key/secret/password/auth/bearer/credential), **When** the config is saved, **Then** the stored config holds a keychain marker and the raw value is written to the Keychain.
2. **Given** a saved server with a secret marker, **When** the server connects, **Then** the real secret is resolved from the Keychain and passed to the subprocess environment, and never logged.
3. **Given** a server is deleted, **When** cleanup runs, **Then** every associated environment secret is removed from the Keychain.

---

### User Story 3 - Select MCP tools per chat and monitor execution (Priority: P2)

While chatting, a user opens a tool menu, selects one or more connected MCP agents to make their tools available to the assistant for that chat, sends a message, and watches each tool call progress through calling → executing → completed/failed states. Completed tool calls remain viewable (expandable to show results) on the persisted message after the response finishes.

**Why this priority**: Selection and monitoring are the user-facing payoff, but they depend on servers already being connected (P1).

**Independent Test**: With a connected server, select it for the current chat, send a prompt that triggers a tool, and confirm the progress view shows the lifecycle and the final assistant message retains an expandable record of the tool calls after reload.

**Acceptance Scenarios**:

1. **Given** a connected agent, **When** the user selects it for a chat and sends a message that invokes a tool, **Then** the UI shows the tool-call lifecycle and appends the tool result to the conversation before the final answer.
2. **Given** a disabled or disconnected agent, **When** the user opens the selector, **Then** the agent is shown as unavailable and cannot be used for the chat.
3. **Given** a completed tool-using response, **When** the chat is reloaded, **Then** the persisted message still shows the collapsed "N tools used" record that expands to the individual calls and results.

### Edge Cases

- What happens when a stream is cancelled mid tool execution? Tool execution loop checks for cancellation and stops without leaving a dangling status.
- What happens when a tool is not found or its owning agent is disconnected? A readable error is surfaced and recorded as a failed tool call without exposing internals.
- What happens when arguments JSON is malformed? The tool call is marked failed with an "Invalid arguments" result rather than crashing.
- What happens when a Stdio subprocess writes to stderr or terminates (SIGPIPE)? The app ignores SIGPIPE and does not crash; stderr is only surfaced as a length in debug builds.
- What data remains after app restart? Server configs persist (with secret markers), selected agents per chat persist, and completed tool-call records persist on messages.
- What sensitive values could reach logs? Tool names, arguments, results, and secrets must be excluded from release logs; only counts/lengths appear in debug logging.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: WardenApp MUST let users add, edit, enable/disable, and delete MCP server configurations, each with a name and a transport type of Stdio (command + arguments + environment) or SSE (URL).
- **FR-002**: WardenApp MUST let users test a server connection before saving and report success with a discovered tool count or a readable failure message.
- **FR-003**: WardenApp MUST connect enabled servers on demand and expose per-server status (connecting, connected with tool count, disconnected, error).
- **FR-004**: WardenApp MUST discover and list the tools advertised by a connected server.
- **FR-005**: Users MUST be able to select one or more connected agents to expose to a specific chat, and this selection MUST persist per chat.
- **FR-006**: WardenApp MUST forward selected agents' tools to the active provider, execute requested tool calls against the owning agent, append tool results to the conversation, and request a final assistant response without re-offering tools (to avoid loops).
- **FR-007**: WardenApp MUST show live tool-call progress (calling → executing → completed/failed) and MUST persist completed tool calls on the resulting message for later expandable viewing.
- **FR-008**: WardenApp MUST handle tool failures, missing tools, disconnected agents, malformed arguments, and stream cancellation without data loss, crash, or secret exposure.
- **FR-009**: Existing unaffected providers, chats, and settings MUST continue to behave as before whether or not any MCP agent is selected.
- **FR-010**: MCP servers MUST NOT auto-connect at launch unless the user explicitly enables the "Auto-connect on launch" preference (disabled by default).

### macOS UX Requirements

- **UX-001**: MCP configuration MUST live in a master–detail Settings pane listing agents with status dots and providing add/edit/delete/test/connect/restart actions.
- **UX-002**: The add/edit sheet MUST validate required fields (name, plus command for Stdio or URL for SSE) and disable Save/Test until valid; it MUST present environment variables as `KEY=VALUE` lines.
- **UX-003**: The in-chat tool selector MUST show each agent's name, transport icon, and availability, disabling agents that are disabled in settings, and MUST offer a shortcut to open MCP settings when none are configured.
- **UX-004**: Tool-call progress MUST be readable, with clear success/failure iconography and expandable results, and MUST truncate very large results for display.

### Data, Migration, and Privacy Requirements

- **DP-001**: Server configurations are persisted outside Core Data (application preferences); no Core Data schema change is required for configs. Completed tool-call records are persisted on existing message storage as encoded JSON.
- **DP-002**: Existing chats and settings MUST remain intact; messages without tool calls MUST render exactly as before.
- **DP-003**: Sensitive environment values (keys matching token/key/secret/password/passwd/auth/bearer/credential) MUST be stored in the Keychain and replaced by a `keychain://mcp-env/<configID>/<key>` marker in persisted config; secrets MUST be removed from the Keychain when the server is deleted.
- **DP-004**: Secrets, tool arguments, and tool results MUST NOT appear in release logs; the SSE transport for remote servers is user-controlled disclosure and MUST be treated as leaving the machine.

### Key Entities

- **MCP Server Config**: Identified configuration with name, transport type, optional command/arguments/environment (Stdio) or URL (SSE), and an enabled flag. Owns the lifecycle of its Keychain secrets.
- **Tool**: A capability advertised by a connected server, addressed by name, mapped back to its owning server for execution.
- **Tool Call Status**: The lifecycle record of a single tool invocation (calling, executing, completed with result, or failed with error) shown live and persisted on the resulting message.

## Compatibility and Scope

- **Affected modules**: `Warden/Core/MCP/`, `Warden/UI/Preferences/MCP/`, `Warden/UI/Chat/MCPAgentSelector.swift`, `Warden/UI/Chat/Components/ToolCallProgressView.swift`, `Warden/Utilities/MessageManager.swift`, plus focused tests under `WardenTests/`.
- **Existing behavior preserved**: All non-MCP provider flows, persistence, and chat rendering remain unchanged when no agent is selected.
- **Out of scope**: Adding new MCP transport types beyond Stdio and SSE; remote server authentication schemes beyond environment/URL; automatic tool selection without user consent.
- **Dependencies**: The Swift MCP SDK (`modelcontextprotocol/swift-sdk`) already integrated; `KeychainAccess` for secret storage; existing provider handlers and `APIServiceFactory`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can add, test, connect, and use an MCP server end-to-end, seeing the assistant invoke at least one of its tools within a single chat session.
- **SC-002**: After saving a server with a sensitive environment key, no plaintext secret is present in the persisted configuration store; the value is retrievable only through the Keychain.
- **SC-003**: Cancelling a response during tool execution leaves no dangling in-progress tool status and no corrupted chat state.
- **SC-004**: Deleting a server removes it from the list and deletes all of its associated Keychain secrets.
- **SC-005**: Focused XCTest coverage for secret marking/resolution, tool-owner routing, and argument/result serialization passes deterministically without live credentials or paid providers.

## Assumptions

- The Swift MCP SDK and `KeychainAccess` remain available and API-compatible with the current integration.
- Stdio commands are resolved via `/usr/bin/env` with common Homebrew/local paths added, matching current behavior.
- "Sensitive" environment keys are identified by substring match against a fixed set of patterns, consistent with the existing `isSensitiveEnvironmentKey` implementation.
- Tool-call records are small enough to encode as JSON on the message; oversized results are truncated for display only.
