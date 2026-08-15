# Feature reference

This document connects the user-visible feature areas to the current implementation entry points. It is a navigation and behavior reference, not a replacement for the detailed specifications.

## Feature map

| Feature | Current behavior | Primary implementation areas | Specification |
| --- | --- | --- | --- |
| App shell and onboarding | Native window, welcome state, onboarding, Preferences, menu commands, appearance, frame restoration | `Warden/WardenApp.swift`, `Warden/UI/ContentView.swift`, `Warden/UI/WelcomeScreen/` | [001](../specs/001-app-shell-onboarding/spec.md) |
| Persistence and chat history | Core Data store, migration, recovery, chat/project/persona/service relationships, JSON legacy import | `Warden/Store/ChatStore.swift`, `Warden/WardenApp.swift`, `Warden/Utilities/DatabasePatcher.swift` | [002](../specs/002-persistence-chat-history/spec.md) |
| Provider configuration | Service lifecycle, Keychain credentials, endpoint validation, factory-created handlers, model discovery | `Warden/Utilities/APIServiceManager.swift`, `Warden/Utilities/APIServiceFactory.swift`, `Warden/Utilities/TokenManager.swift` | [003](../specs/003-provider-model-configuration/spec.md) |
| Chat and streaming | Request construction, streaming sessions, cancellation, retry, persistence, MCP/search integration | `Warden/Utilities/MessageManager.swift`, `Warden/Utilities/ChatStreamingSession.swift`, `Warden/Utilities/StreamingTaskController.swift` | [004](../specs/004-core-chat-streaming/spec.md) |
| Rich rendering | Markdown, code, tables, formulas, reasoning, attachment markers, HTML preview, copy actions | `Warden/UI/Components/`, `Warden/UI/Chat/BubbleView/`, `Warden/Utilities/ChatStreamingSession.swift` | [005](../specs/005-rich-message-rendering/spec.md) |
| Attachments and media | Draft preparation, text extraction, persistent images/files, image viewer, generated video playback/export | `Warden/Utilities/AttachmentResolver.swift`, `Warden/Models/FileAttachment.swift`, `Warden/Models/ImageAttachment.swift`, `Warden/UI/` | [006](../specs/006-attachments-media/spec.md) |
| Personas and models | Reusable instruction profiles, compatible model selector, favorites, metadata cache | `Warden/Models/`, `Warden/UI/Preferences/`, `Warden/Utilities/SelectedModelsManager.swift`, `Warden/Utilities/FavoriteModelsManager.swift` | [007](../specs/007-personas-model-selection/spec.md) |
| Web search and citations | Opt-in Tavily search, progress states, source metadata, numbered HTTPS citations | `Warden/Utilities/TavilySearchService.swift`, `Warden/Models/TavilyModels.swift`, `Warden/Utilities/MessageManager.swift` | [008](../specs/008-web-search-citations/spec.md) |
| Organization and sharing | Search, pin/archive/project organization, branches, copy/export/share formats | `Warden/Store/ChatStore.swift`, `Warden/Utilities/ChatBranchingManager.swift`, `Warden/Utilities/ChatSharingService.swift` | [009](../specs/009-chat-organization-sharing/spec.md) |
| Local AI and generation | Ollama, LM Studio, MLX, Hugging Face, Core ML, local capability routing | `Warden/Utilities/APIHandlers/OllamaHandler.swift`, `Warden/Utilities/APIHandlers/LMStudioHandler.swift`, `Warden/Utilities/APIHandlers/MLXHandler.swift`, `Warden/Utilities/` | [010](../specs/010-local-ai-generation/spec.md) |
| MCP tool integration | Stdio/SSE configuration, secure environment values, server status, tool discovery/execution | `Warden/Core/MCP/MCPManager.swift`, `Warden/Core/MCP/MCPServerConfig.swift` | [011](../specs/011-mcp-tool-integration/spec.md) |
| Multi-agent and Quick Chat | Parallel comparison, floating panel, global and in-app hotkeys | `Warden/Utilities/MultiAgentMessageManager.swift`, `Warden/Utilities/FloatingPanelManager.swift`, `Warden/Utilities/GlobalHotkeyHandler.swift`, `Warden/UI/QuickChatView.swift` | [012](../specs/012-multi-agent-and-quick-chat/spec.md) |

## Implemented limits and defaults

These values are defined in `Warden/Configuration/AppConstants.swift` or the corresponding service code:

- Request timeout: 180 seconds.
- Streaming UI update interval: 0.05 seconds.
- Large-message threshold: 25,000 symbols.
- Maximum concurrent multi-agent services: 3.
- Quick Chat panel height: 60 through 600 points.
- Tavily default result count: 5.
- Tavily configured maximum: 10.
- Search aliases: `/search`, `/web`, and `/google`.
- Chat font size setting: 10 through 24 points.

The values are implementation defaults, not a promise that every remote provider accepts the same context, output, or media limits.

## Runtime behavior by feature

### Request ownership

A message request belongs to the chat where it starts. `ChatStreamingSession` and `StreamingTaskController` coordinate incremental output and cancellation. Late callbacks must not append to a different selected chat or overwrite newer request state.

### Provider selection

`APIServiceManager` owns service lifecycle and validation. `APIServiceFactory` creates the provider implementation. `APIService` and `BaseAPIHandler` provide the shared request/response path, while individual handlers implement provider-specific formats.

### Search

`TavilySearchService` reads search preferences, performs the search, tracks progress, and returns source data. `MessageManager` integrates the search context into the selected request and persists source metadata with the message.

### MCP

`MCPManager` persists sanitized configurations, restores sensitive environment values from Keychain, connects using Stdio or SSE, discovers tools, maps tool names to their owning agent, and converts results into message-compatible data.

### Persistence

`ChatStore` is the main observable store for chat/project state. `PersistenceController` owns the Core Data container. `DatabasePatcher` applies default-data and compatibility patches before normal use.

## Evidence rules

A feature is documented as implemented only when its behavior is supported by one or more of:

- Current source in the implementation path listed above.
- A current unit/UI test.
- The matching feature specification.
- Existing project documentation that describes an actively supported workflow.

Where a requirement is specified but its implementation evidence is incomplete, the gap is recorded in [Evidence packet](evidence.md) rather than presented as a guaranteed feature.

## Change checklist

When modifying a feature:

- Identify the owning module and shared hotspots.
- Preserve the request, persistence, and credential boundaries.
- Update the matching specification and this reference.
- Add or update tests without requiring paid credentials.
- Run the verified build/test commands.
- Refresh codebase-memory after the final source and documentation changes.
