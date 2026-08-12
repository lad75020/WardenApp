# Research: MCP Tool Integration

## R1 — Transport construction (Stdio vs SSE)

- **Decision**: Keep two transports: `ProcessStdioTransport` (custom actor wrapping `Process` via `/usr/bin/env`) for local commands, and the SDK's `HTTPClientTransport(endpoint:streaming:true)` for SSE.
- **Rationale**: Matches the current `MCPManager.connect` implementation; `/usr/bin/env` resolves `npx`/`node`/`uvx`/`python` in a GUI app's reduced PATH, and augmenting PATH with Homebrew/local bins prevents "command not found" for typical MCP servers.
- **Alternatives considered**: Launching commands directly (rejected — fails to resolve PATH-based tools); using only SSE (rejected — most MCP servers ship as local stdio processes).

## R2 — Secret storage and reference markers

- **Decision**: Persist configs in `UserDefaults`, but replace sensitive env values with `keychain://mcp-env/<configID>/<key>` markers and store the real value via `TokenManager` (Keychain). Resolve markers at connect time; delete secrets on config delete.
- **Rationale**: Satisfies the constitution's rule that secrets live in Keychain, not plaintext stores/logs, while keeping the non-secret config easy to serialize. Sensitive keys are detected by substring match against `token/key/secret/password/passwd/auth/bearer/credential`.
- **Alternatives considered**: Storing whole config in Keychain (rejected — heavier, unnecessary for non-secret fields); encrypting UserDefaults blob (rejected — Keychain already provides this and manages access control).

## R3 — Tool-owner routing and execution loop

- **Decision**: Maintain a `toolOwner: [String: UUID]` map populated on connect/list; `callTool` looks up the owning client, converts args to MCP `Value`, and normalizes results. `MessageManager` appends an assistant tool-call message and per-call tool-result messages, then re-requests the completion with `tools: nil` to avoid infinite tool loops.
- **Rationale**: Mirrors OpenAI-style tool-calling semantics already used by `ChatGPTHandler`; disabling tools on the follow-up prevents runaway loops while still letting the model produce a final answer.
- **Alternatives considered**: Re-offering tools on every follow-up (rejected — loop risk); global tool namespace without owner map (rejected — cannot route a call to the correct server).

## R4 — Cancellation and failure handling

- **Decision**: Check `Task.isCancelled` at the top of each tool iteration; on malformed arguments, missing tool, or thrown error, record a failed `WardenToolCallStatus` with a readable message and continue/return safely. Ignore SIGPIPE at app launch so a terminating subprocess pipe does not crash the app.
- **Rationale**: Keeps chat state consistent under Stop/replacement, and prevents subprocess teardown from crashing the host.
- **Alternatives considered**: Aborting the whole response on first tool failure (rejected — a single tool failure should still allow a final answer); no SIGPIPE handling (rejected — observed crash risk on subprocess exit).

## R5 — Deterministic test seams (no live server)

- **Decision**: Unit-test the pure logic that does not require a subprocess: sensitive-key detection, secret marker format/round-trip through a Keychain-backed `TokenManager`, `toolOwner` routing error for unknown tools, and `[String: Any]`→`Value`→JSON argument/result conversion shape. Avoid launching real MCP servers in tests.
- **Rationale**: The constitution forbids tests that need paid credentials or live services; the highest-risk logic (secrets, routing, serialization) is testable in isolation.
- **Alternatives considered**: Spinning up a fixture stdio server (rejected for this pass — environment-dependent and flaky in CI-less local verification); mocking the SDK `Client` (deferred — SDK types are not easily substitutable without an abstraction the constitution discourages adding).

## R6 — Auto-connect posture

- **Decision**: Keep `autoConnectMCPServers` defaulted to `false`; only connect enabled servers at launch when the user explicitly opts in.
- **Rationale**: Prevents persisted subprocess configs from running automatically on startup — a privacy/safety default.
- **Alternatives considered**: Auto-connecting all enabled servers by default (rejected — runs user-defined subprocesses without explicit consent).
