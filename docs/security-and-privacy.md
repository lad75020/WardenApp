# Security and privacy

WardenApp is designed around local storage and explicit user-controlled provider connections. It is not a zero-risk environment: when a user selects a remote provider or enables web search, the relevant prompt, context, attachments, and response data can leave the device according to that service's behavior.

## Data boundaries

### Local by default

Core Data, UserDefaults preferences, local model paths, and Keychain entries are local macOS data. The application does not include a telemetry or analytics path in the documented architecture.

### Remote when selected

Data can leave the device when the user:

- Sends a request through a hosted provider.
- Enables web search.
- Connects to an MCP SSE endpoint.
- Uses a remote MCP Stdio process that itself communicates externally.
- Explicitly exports, copies, shares, or saves content to a selected location.

The user is responsible for choosing an appropriate provider, model, endpoint, and MCP server for sensitive conversations.

## Credential storage

Provider credentials are stored through `TokenManager` in the macOS Keychain. Core Data stores a token identifier, not the secret. UserDefaults, exported diagnostics, source fixtures, and release logs must not contain credentials.

MCP environment values that are classified as sensitive are also stored in Keychain. Persisted MCP configuration contains a marker and the clear value is resolved only when the environment is needed for a connection.

The current token manager source and setup guide use Keychain service `fr.dubertrand.WardenAI`. Older installations may contain legacy items, but a legacy identifier must not be assumed for new entries.

## Transport security

Before a request is sent, the shared provider path checks whether it carries a sensitive credential. Credential-bearing remote HTTP endpoints are rejected. HTTPS is required for remote credential transport. Loopback/local HTTP is allowed only through the intended local transport rule.

This validation does not make a remote provider trustworthy. It protects the transport choice made by the application; provider-side retention, logging, and policy remain external concerns.

## Sandbox and file access

The current entitlements enable:

- App Sandbox.
- Network client access.
- Network server access.
- User-selected file read/write access.

The user-selected file entitlement is not unrestricted filesystem access. Attachment import, export, and save actions should use explicit user-selected locations and should not disclose broader filesystem paths in logs.

## Logging and diagnostics

Use `WardenLog` with safe categories and values. Release diagnostics must exclude:

- API keys and bearer values.
- Authorization headers.
- Complete prompts and assistant responses.
- Raw provider request/response bodies.
- Attachment bytes and sensitive file contents.
- MCP environment values.
- Tool arguments/results when they contain private data.

Debug code may record bounded counts, lengths, provider names, sanitized error categories, or tool counts where that does not reveal private content. Debug-only logging is not permission to print secrets.

## HTML preview boundary

HTML preview is an explicitly user-initiated feature for HTML code blocks. The preview is isolated from network access, external navigation, script execution, persistent website data, and filesystem access. Treat it as a rendering surface, not as a browser or a trusted execution environment.

## Search and citations

When search is enabled, the prompt/query and request context are sent to the configured search service. The application retains source metadata with the message and turns only validated HTTPS citations into actionable links.

A search failure must not expose the search credential or raw error body. Malformed or non-HTTPS source URLs remain non-actionable text.

## MCP security boundary

MCP tools are external code and must be treated as untrusted integrations. Review a server command, arguments, URL, environment, and advertised tools before enabling it.

WardenApp provides these protections:

- Explicit server configuration and enablement.
- Stdio and SSE transport separation.
- Keychain storage for sensitive environment values.
- Per-chat selection of connected agents.
- Tool-owner mapping so a call goes to the intended agent.
- Status and failure reporting.
- Cancellation checks during tool execution.
- No automatic launch connection unless explicitly enabled.
- No release logging of secrets, tool arguments, or results.

These protections do not make a malicious MCP server safe. A configured server can access whatever the server process or endpoint can access.

## Persistence and recovery

If the Core Data store fails, the application may use an in-memory fallback. This protects the original store from silent replacement but means current-session changes are not durable. Users should repair or investigate the persistent store before continuing important work.

A chat with a missing service is retained as unavailable rather than deleted. This preserves conversation content but does not restore the deleted provider credential.

## Export and sharing

Copy, export, share, JSON backup, attachment save, and generated media reveal data only after an explicit user action. Treat exported files as sensitive because they may include messages, system instructions, search sources, tool results, and attachments.

Before sharing an export, inspect the content for private prompts, credentials accidentally pasted into a conversation, local paths, and tool output.

## Security review checklist

For any new feature or provider:

- Identify what data remains local and what data crosses the network.
- Keep secrets in Keychain and references in ordinary persisted configuration.
- Require HTTPS for remote credential transport.
- Validate URL schemes before making links actionable.
- Redact logs and error messages.
- Test cancellation, failure, and stale callback paths.
- Avoid unrestricted filesystem access.
- Update the threat boundary in this document and the matching functional specification.
