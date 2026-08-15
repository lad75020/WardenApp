# Architecture

WardenApp is a native macOS SwiftUI application with AppKit integration, Core Data persistence, Keychain-backed credentials, and a provider abstraction for hosted and local AI services.

## Architectural goals

- Keep the app usable as a native macOS application rather than a web wrapper.
- Keep local conversation state in one observable store.
- Separate SwiftUI presentation from persistence and provider transport.
- Route all provider creation through a factory and shared protocol path.
- Keep long-running work cancellable and tied to its originating conversation.
- Keep credentials out of Core Data, UserDefaults, logs, exports, and source fixtures.
- Preserve local data when a configuration becomes unavailable.

## High-level view

```text
+---------------------------+
| SwiftUI/AppKit application|
| WardenApp, ContentView,   |
| chat, settings, welcome   |
+-------------+-------------+
              |
              v
+---------------------------+
| View models and managers  |
| ChatStore, MessageManager,|
| APIServiceManager, MCP,   |
| search, branches, sharing |
+------+------+-------------+
       |      |       |
       |      |       +-------------------+
       |      |                           |
       v      v                           v
+------+--+ +--+----------------+  +-----+------+
| Core   | | APIServiceFactory |  | Integration |
| Data   | | APIService/Base   |  | Tavily/MCP  |
| store  | | provider handlers |  | local AI    |
+--------+ +---------+---------+  +------------+
                     |
                     v
           +----------------------+
           | Remote or local model|
           | endpoint/runtime     |
           +----------------------+
```

The diagram shows responsibility boundaries, not a strict compile-time dependency graph. The source layout is described in `AGENTS.md` and `CLAUDE.md`.

## Application shell

`Warden/WardenApp.swift` is the application entry point. It:

- Creates the main `ChatStore` from `PersistenceController.shared`.
- Registers the data transformer used by persisted request messages.
- Applies database patches and legacy configuration migration at startup.
- Restores preferences such as model and appearance.
- Installs menu commands and application notifications.
- Initializes caches, hotkeys, and MCP runtime behavior after the main shell appears.
- Uses special launch arguments/environment values for persistence recovery UI tests.

`ContentView` receives the managed object context and store and hosts the main navigation/detail layout. Settings is presented through a single-window flow so repeated requests activate the existing window.

## Layer boundaries

### UI

`Warden/UI/` contains SwiftUI views, view models, controls, settings tabs, chat rendering, welcome/onboarding, Quick Chat, previews, and user interaction. It should not own provider transport or the Core Data container.

### Models

`Warden/Models/` contains Core Data models and shared value types such as message content, attachments, Tavily results, model metadata, and hotkey state. Models should not depend on concrete views.

### Utilities and services

`Warden/Utilities/` contains provider handlers, service managers, streaming, attachment resolution, search, sharing, branching, hotkeys, local inference adapters, and logging.

### Persistence

`Warden/Store/` contains `ChatStore` and the `wardenDataModel` Core Data model. It owns durable chat/project operations and recovery-aware state.

### MCP core

`Warden/Core/MCP/` contains MCP configuration and runtime management. MCP is kept separate from ordinary provider handlers because it has its own transport, agent status, tool ownership, and secret-handling rules.

### Packages and CLI

`Packages/` contains local package boundaries such as `flux.swift` and `MLXZImageSwift`. `MLXZImageSwiftCLI/` is an auxiliary command-line target. App-specific UI and persistence should not leak into package APIs.

## Message request flow

A normal request follows this conceptual path:

1. The chat input view validates that the prompt is non-empty.
2. The active chat state supplies the service, model, persona, context, attachments, and optional search/MCP selection.
3. `ChatViewModel` and `MessageManager` prepare the request messages and persist the user message once.
4. `APIServiceManager` and `APIServiceFactory` select the configured provider implementation.
5. The handler constructs and validates a URL request.
6. For a stream, `ChatStreamingSession` parses logical events and `StreamingTaskController` owns cancellation.
7. The view model publishes incremental text to the originating chat.
8. The final assistant message, tool-call data, search metadata, and attachment associations are persisted through the store path.
9. Failure or cancellation clears transient state and leaves a recoverable chat state.

The actual call graph is wider because provider-specific parsing, MCP tool calls, search, chat naming, metadata, and attachment persistence participate conditionally.

## Provider architecture

`Warden/Utilities/APIHandlers/APIProtocol.swift` defines the internal `APIService` abstraction. It covers:

- Provider name, base URL, URL session, and model.
- Non-streaming message requests.
- Streaming message requests.
- Model discovery.
- Request preparation.
- Full-response and delta-response parsing.
- Standard HTTP error classification.
- Credential transport validation.

`BaseAPIHandler` supplies common behavior. Individual handlers adapt provider-specific request and response formats. `APIServiceFactory` creates the concrete implementation and configures URL sessions with bounded request/resource timeouts and connection limits.

The protocol is an internal Swift integration contract. It is not a documented public HTTP API for other applications.

## Streaming and concurrency

Streaming work is deliberately detached from the currently selected sidebar chat. A request carries its originating chat identity and transient session state. This prevents a user switching chats while a request is active from redirecting chunks.

Important safeguards include:

- Empty prompts are rejected before request creation.
- Duplicate rapid submissions are rejected or superseded.
- Stream events can be split across transport deliveries.
- Keep-alive/comment lines are ignored.
- A final valid event is processed even without a trailing delimiter.
- Cancellation can occur before the first chunk, during parsing, during saving, or at completion.
- Late callbacks cannot replace newer request state.
- Deleting a chat with an active request detaches or cancels that request before deletion completes.

The UI update interval and large-message threshold are defined centrally in `AppConstants`.

## Search integration

When explicitly enabled, `MessageManager` checks the search command, invokes `TavilySearchService`, formats the returned context, and preserves source metadata. Search progress is represented separately from provider streaming. A search failure does not silently send the original prompt without search; the user must retry or explicitly disable search.

Citation conversion validates that a numbered citation belongs to a source in the same message and that the source is a valid HTTPS URL before making it actionable.

## MCP integration

`MCPManager` is a main-actor observable runtime. It stores server configurations, client connections, statuses, discovered tools, and tool ownership.

- Stdio uses a subprocess transport with command, arguments, and resolved environment.
- SSE uses an HTTP streaming transport with a configured URL.
- Connecting discovers tools and records a connected tool count.
- Tool names are mapped to their owning agent so calls route correctly.
- Tool results are converted to text/image/audio/resource/resource-link records.
- Selected MCP tools are passed into a provider request and are not re-offered after execution to prevent loops.
- Sensitive environment values are stored in Keychain and represented by safe markers in UserDefaults.

Startup auto-connect is opt-in and controlled by the application preference.

## Local AI integration

Local services use the same service-selection path but route to local runtimes or model assets. The current configuration includes Ollama, LM Studio, Hugging Face, Core ML text generation, and MLX paths. `MLXHandler` also covers local image generation flows where supported.

Local model discovery and inference are validated independently from remote provider credentials. Missing model assets, unsupported capabilities, and unavailable local runtimes are surfaced as actionable failures without corrupting the chat draft.

## Multi-agent and Quick Chat

`MultiAgentMessageManager` sends to a bounded set of services concurrently and maintains per-agent status. The runtime cap is three services, defined in `AppConstants.MultiAgent.maxConcurrentServices`.

`FloatingPanelManager` owns the non-activating Quick Chat panel and its clamped geometry. `GlobalHotkeyHandler` registers system-wide combinations; ordinary application actions use notifications and do not require Accessibility permissions.

## Persistence boundary

`ChatStore` is the main source of truth for chat/project state. `PersistenceController` configures `NSPersistentContainer`, persistent history tracking, merge behavior, and the in-memory fallback. `DatabasePatcher` handles compatibility patches and legacy migration before normal use.

Secrets are intentionally outside Core Data. Service records carry a token identifier, while `TokenManager` stores the token in the Keychain. MCP environment values use the same separation.

## Extension points

### Add a provider

1. Add a provider type and safe defaults in `AppConstants`.
2. Add or reuse a handler conforming to `APIService`.
3. Register the handler in `APIServiceFactory`.
4. Implement provider-specific request and response parsing.
5. Confirm endpoint and credential transport validation.
6. Add model discovery only when the provider supports it.
7. Add tests for success, streaming, malformed response, auth, rate limit, timeout, and cancellation paths.
8. Update [Provider reference](provider-reference.md) and the matching specification.

### Add a feature

1. Identify the owning layer and shared hotspots.
2. Keep UI state in views/view models, persistence in `ChatStore`/Core Data, and external work in a service or manager.
3. Make asynchronous work cancellable and associate it with a stable request/chat identity.
4. Keep secrets and private content out of logs and diagnostics.
5. Add unit/UI coverage without paid credentials.
6. Update the functional and feature references.

## Known architecture boundaries

- No public server-side Warden API is defined by this repository.
- External provider contracts can change independently of WardenApp and are adapted in handlers.
- Local model support depends on assets and runtime availability outside the application.
- Core Data fallback is a recovery mechanism, not a durable replication strategy.
- MCP tool safety depends both on WardenApp validation and on the configured server/tool implementation.
