# Functional requirements

This document is the consolidated functional index for WardenApp. The detailed requirement text and acceptance scenarios remain in the linked feature specifications under `../specs/`.

The identifiers repeat as `FR-001`, `FR-002`, and so on inside each feature specification. In this index, the specification number is shown first so each requirement is unambiguous.

## Functional scope

| Spec | Domain | Main user outcome | Normative source |
| --- | --- | --- | --- |
| 001 | App shell and onboarding | Reach a usable native shell and complete setup | [spec 001](../specs/001-app-shell-onboarding/spec.md) |
| 002 | Persistence and chat history | Preserve local conversations and recover safely | [spec 002](../specs/002-persistence-chat-history/spec.md) |
| 003 | Provider and model configuration | Configure, test, select, and manage services | [spec 003](../specs/003-provider-model-configuration/spec.md) |
| 004 | Core chat and streaming | Send, stream, stop, and retry responses | [spec 004](../specs/004-core-chat-streaming/spec.md) |
| 005 | Rich message rendering | Read and reuse structured responses | [spec 005](../specs/005-rich-message-rendering/spec.md) |
| 006 | Attachments and media | Send, inspect, save, and play supported media | [spec 006](../specs/006-attachments-media/spec.md) |
| 007 | Personas and model selection | Reuse personas and find compatible models | [spec 007](../specs/007-personas-model-selection/spec.md) |
| 008 | Web search and citations | Search explicitly and inspect grounded sources | [spec 008](../specs/008-web-search-citations/spec.md) |
| 009 | Chat organization and sharing | Find, branch, organize, export, and share chats | [spec 009](../specs/009-chat-organization-sharing/spec.md) |
| 010 | Local AI and generation | Use local text, vision, and image paths | [spec 010](../specs/010-local-ai-generation/spec.md) |
| 011 | MCP tool integration | Connect agents and run selected tools safely | [spec 011](../specs/011-mcp-tool-integration/spec.md) |
| 012 | Multi-agent and Quick Chat | Compare services and use a floating prompt panel | [spec 012](../specs/012-multi-agent-and-quick-chat/spec.md) |

## Cross-feature invariants

These rules apply across more than one feature:

- User prompts and assistant messages retain deterministic chronological order.
- Empty prompts do not create messages or provider requests.
- Cancellation clears transient waiting state and prevents stale work from appending content.
- Switching chats does not redirect an active request to the newly selected chat.
- Deleting or invalidating a service does not silently delete the chats that used it.
- Credentials, authorization headers, complete private prompts, raw provider bodies, and sensitive local paths are excluded from release diagnostics.
- Local data remains on the device unless the user selects a remote service, enables web search, or explicitly exports/shares content.
- Provider, search, MCP, attachment, and persistence failures are user-visible and recoverable where possible.
- Existing unaffected behavior must remain compatible after each feature change.

## 001 - App shell and onboarding

User stories:

- Reach the correct welcome, chat, or restored-chat state.
- Complete a three-step guided setup.
- Control native windows, appearance, settings, and shell actions.

Requirements:

- `001-FR-001` - Present a native macOS window with navigation and a detail area for welcome, chat, project, and preview content.
- `001-FR-002` - Choose welcome messaging and primary actions from provider presence, chat count, and onboarding state.
- `001-FR-003` - Provide a three-step onboarding flow with back/forward navigation, a provider settings entry point, and a finish action that starts a chat.
- `001-FR-004` - Persist onboarding completion while allowing the guide to be reopened.
- `001-FR-005` - Expose Preferences from the application menu and relevant in-app entry points.
- `001-FR-006` - Bring one existing Preferences window forward instead of creating duplicates.
- `001-FR-007` - Support System, Light, and Dark appearance, chat font size from 10 through 24 points, and sidebar service-icon visibility.
- `001-FR-008` - Persist general UI preferences and keep visible Warden windows consistent.
- `001-FR-009` - Expose New Chat, New Project, New Window, Preferences, and Toggle Sidebar with discoverable shortcuts.
- `001-FR-010` - Route New Chat to the intended main window when multiple windows exist.
- `001-FR-011` - Restore a saved main-window frame or use a centered practical default.
- `001-FR-012` - Restore the last selected chat when it still exists, otherwise show the correct welcome state.
- `001-FR-013` - Warn on persistent-store startup failure and continue with an explicitly non-persistent fallback instead of crashing.
- `001-FR-014` - Support user-initiated JSON chat backup export and import with safe cancellation and invalid-data paths.
- `001-FR-015` - Preserve unaffected provider, chat, project, and settings behavior.

Important edge cases include duplicate settings requests, stale selected-chat identifiers, repeated onboarding completion, canceled import/export panels, malformed backups, and offline launch.

## 002 - Persistence and chat history

User stories:

- Preserve conversations, messages, projects, and personas across launches.
- Evolve local data without destroying valid user content.
- Retain configuration without exposing credentials.

Requirements:

- `002-FR-001` - Persist valid conversations, messages, projects, personas, and non-secret service configuration with valid relationships.
- `002-FR-002` - Preserve deterministic conversation/message ordering and clear stale selection without deleting unrelated history.
- `002-FR-003` - Retain compatible local history through supported model changes.
- `002-FR-004` - Handle unavailable, malformed, or unrecoverable local data without silently overwriting valid data.
- `002-FR-005` - Prevent duplicate lifecycle saves and duplicate restored objects.
- `002-FR-006` - Keep valid persisted data compatible with chat presentation, streaming, providers, and appearance.
- `002-FR-007` - Safely handle unsupported or incomplete message content.
- `002-FR-008` - Keep chats with missing services as unavailable until explicit repair or delete.
- `002-FR-009` - Remap an unavailable chat to a valid user-selected service without changing its message history.

Important edge cases include stale object references, partial writes, interrupted migration, unsupported message payloads, and recovery errors that must not disclose content or secrets.

## 003 - Provider and model configuration

User stories:

- Configure a usable AI service.
- Validate and select an available or custom model.
- Manage service lifecycle and the default service.

Requirements:

- `003-FR-001` - Create, inspect, edit, duplicate, select, and delete persisted services.
- `003-FR-002` - Store stable service identity, name, provider, endpoint, model, context/response settings, and a non-persistent credential reference.
- `003-FR-003` - Validate endpoint syntax before save, test, or discovery and reject credential-bearing non-loopback HTTP.
- `003-FR-004` - Store, retrieve, migrate, duplicate, and delete credentials through Keychain only.
- `003-FR-005` - Construct provider clients through the established factory and shared protocol path.
- `003-FR-006` - Discover, choose, or manually enter a model when supported.
- `003-FR-007` - Preserve the saved model when discovery fails.
- `003-FR-008` - Test a service with bounded user-facing success/failure feedback.
- `003-FR-009` - Classify credential, rate-limit, endpoint, connection, timeout, response, and server failures without sensitive content.
- `003-FR-010` - Apply compatible type defaults without silently discarding compatible custom values.
- `003-FR-011` - Disable incompatible streaming for provider/model types that cannot stream.
- `003-FR-012` - Support one deliberate default service and clear it when that service is deleted.
- `003-FR-013` - Give duplicated services new identities and independent credential entries; clean up credentials after successful deletion.
- `003-FR-014` - Preserve existing services, selected models, chats, and local settings.

Important edge cases include duplicate display names, stale refresh completions, denied local folder access, and Keychain failures.

## 004 - Core chat and streaming

User stories:

- Send a prompt and see a streamed response.
- Stop an active response safely.
- Retry and continue a conversation.

Requirements:

- `004-FR-001` - Submit a non-empty prompt from the active conversation.
- `004-FR-002` - Add each user prompt exactly once in conversation order.
- `004-FR-003` - Stream incremental assistant text and finalize one assistant message for streaming services.
- `004-FR-004` - Provide a coherent non-streaming lifecycle without a false streaming state.
- `004-FR-005` - Stop active work and reject stale content afterward.
- `004-FR-006` - Retain meaningful partial content at most once and clear transient indicators.
- `004-FR-007` - Retry an eligible prompt without duplicating it and replace the prior assistant result.
- `004-FR-008` - Start each request with clean transient state and deterministic supersession/rejection of older work.
- `004-FR-009` - Derive request context from the active conversation and respect its context limit.
- `004-FR-010` - Convert provider, transport, parser, timeout, and cancellation failures into recoverable state.
- `004-FR-011` - Preserve logical stream events across arbitrary delivery boundaries and process a final undelimited event.
- `004-FR-012` - Mutate conversation state safely from asynchronous callbacks.
- `004-FR-013` - Preserve unaffected provider, attachment, search, local-generation, and multi-agent behavior.
- `004-FR-014` - Keep an active stream attached to its originating conversation when the user switches chats.

Important edge cases include empty responses, missing trailing delimiters, keep-alive lines, split events, deletion during a request, and navigation while streaming.

## 005 - Rich message rendering

User stories:

- Read structured assistant responses.
- Inspect and reuse code.
- Handle long, incomplete, or invalid content gracefully.

Requirements:

- `005-FR-001` - Parse supported text, table, code, formula, reasoning, and attachment elements in source order.
- `005-FR-002` - Render common Markdown prose and accessible chat-bubble content.
- `005-FR-003` - Support selecting text, copying a message, copying code, and copying tables as text or JSON.
- `005-FR-004` - Render incomplete, malformed, oversized, and rapidly streaming content without data loss or a crash.
- `005-FR-005` - Preserve provider, chat, attachment, citation, persistence, and message actions.
- `005-FR-006` - Provide explicit HTML preview with refresh, resize, zoom, and close actions.

## 006 - Attachments and media

User stories:

- Attach supported local content to a draft.
- Inspect received images and files.
- Use generated video.

Requirements:

- `006-FR-001` - Add and remove supported local files and images before sending.
- `006-FR-002` - Show attachment name, size when available, type preview/icon, and preparation state.
- `006-FR-003` - Include prepared content in the provider request and never send failed content as complete.
- `006-FR-004` - Provide readable fallback information for unsupported or non-previewable files.
- `006-FR-005` - Preserve stored attachment/message association across relaunch.
- `006-FR-006` - Inspect images with zoom, pan, reset, keyboard-accessible controls, and close.
- `006-FR-007` - Save a copy of an image or video without altering the source on failure/cancel.
- `006-FR-008` - Reveal available generated video in Finder with understandable failure feedback.
- `006-FR-009` - Play available generated videos inline with loading/error states.
- `006-FR-010` - Handle read, decode, extraction, persistence, download, generation, cancellation, and save failures safely.
- `006-FR-011` - Preserve text-only messages, providers, history, and unaffected rendering.

## 007 - Personas and model selection

User stories:

- Create and apply a persona.
- Find and select an available model.
- Favorite and inspect models.

Requirements:

- `007-FR-001` - Create, edit, reorder, and delete reusable personas with symbol, system message, temperature, and optional default service.
- `007-FR-002` - Persist persona edits through normal recovery and migration behavior.
- `007-FR-003` - Apply a persona system message and temperature without silently replacing service/model.
- `007-FR-004` - Offer a separate explicit action to apply a persona default service after validating it.
- `007-FR-005` - List only models available for configured services and compatible capabilities.
- `007-FR-006` - Search provider/model values and update service and model together after valid selection.
- `007-FR-007` - Persist favorites by provider and model identifier.
- `007-FR-008` - Show non-sensitive metadata only when present and tolerate stale metadata.
- `007-FR-009` - Recover safely from malformed local favorite, selection, and metadata values.
- `007-FR-010` - Preserve unaffected provider, chat, service, attachment, and stream behavior.

## 008 - Web search and citations

User stories:

- Search an explicit AI prompt.
- Inspect sources and citations.
- Configure and validate search.

Requirements:

- `008-FR-001` - Enable or disable search per request without changing search-disabled behavior.
- `008-FR-002` - Obtain the configured result limit, add delimited context, and preserve the source list with the assistant message.
- `008-FR-003` - Show starting, retrieving, processing, success, cancellation, and failure states without stale progress.
- `008-FR-004` - Map search failures to safe actionable messages and keep the prompt unsent until retry or explicit search disable.
- `008-FR-005` - Persist query, sources, timestamp, and result count with the message.
- `008-FR-006` - Link only valid standalone numbered citations that belong to the same message.
- `008-FR-007` - Allow users to view recorded sources and open only valid HTTPS sources.
- `008-FR-008` - Preserve normal chats and provider flow without search credentials.

## 009 - Chat organization and sharing

User stories:

- Find and organize conversations.
- Create and navigate branches.
- Export or share a conversation.

Requirements:

- `009-FR-001` - Search local conversations by title, system instruction, persona, and message body using case/diacritic-insensitive matching.
- `009-FR-002` - Show pinned chats first and preserve project, pin, and archive state.
- `009-FR-003` - Create, open, rename, move, clear, delete, and view conversations and projects through accessible controls.
- `009-FR-004` - Create an independent branch with source settings and history through the selected message.
- `009-FR-005` - Copy, export, or share full metadata, system instruction, and chronological messages as text, Markdown, or JSON.
- `009-FR-006` - Provide safe error feedback for search, branch, and export failures.
- `009-FR-007` - Preserve provider, streaming, conversation, and project compatibility.

## 010 - Local AI and generation

User stories:

- Use an installed local text model.
- Use compatible vision or image models.
- Inspect available local models.

Requirements:

- `010-FR-001` - Route MLX, Core ML, Hugging Face, Ollama, and LM Studio through the local provider path.
- `010-FR-002` - Support compatible local text inference through the cancellable conversation workflow.
- `010-FR-003` - Route vision and image generation only to a compatible local capability path.
- `010-FR-004` - Validate local assets/runtime and preserve the draft and prior state on failure.
- `010-FR-005` - Discover Ollama and LM Studio models and preserve the current usable selection when refresh fails.
- `010-FR-006` - Mark local models as local/self-hosted rather than paid remote catalog entries.
- `010-FR-007` - Preserve unaffected hosted providers, chats, settings, attachments, and media behavior.

## 011 - MCP tool integration

User stories:

- Configure and connect an MCP server.
- Store MCP environment secrets securely.
- Select tools per chat and monitor execution.

Requirements:

- `011-FR-001` - Add, edit, enable/disable, and delete Stdio or SSE server configurations.
- `011-FR-002` - Test a server before saving and report success with a discovered tool count or readable failure.
- `011-FR-003` - Connect enabled servers on demand and expose connecting, connected, disconnected, and error states.
- `011-FR-004` - Discover and list tools advertised by connected servers.
- `011-FR-005` - Select connected agents per chat and persist that selection.
- `011-FR-006` - Forward tools, execute calls against the owning agent, append results, and request a final response without re-offering tools.
- `011-FR-007` - Show live tool progress and persist completed calls on the resulting message.
- `011-FR-008` - Handle failures, missing tools, disconnected agents, malformed arguments, cancellation, and secrets safely.
- `011-FR-009` - Preserve normal behavior when no MCP agent is selected.
- `011-FR-010` - Do not auto-connect at launch unless the user explicitly enables the preference.

## 012 - Multi-agent and Quick Chat

User stories:

- Compare responses from multiple services.
- Summon Quick Chat with a global hotkey.
- Configure hotkeys for actions.

Requirements:

- `012-FR-001` - Send one prompt to multiple selected services with a maximum of three concurrent services, enforced in the UI and runtime.
- `012-FR-002` - Render independent streamed or non-streamed responses with service/model and per-agent outcome.
- `012-FR-003` - Cancel all in-flight agents with one stop action without corrupting chat state.
- `012-FR-004` - Provide a floating non-activating Quick Chat panel near the top center of the main screen.
- `012-FR-005` - Focus input on open, hide on Escape/focus loss, and reset panel chat state when opened.
- `012-FR-006` - Clamp panel height between 60 and 600 points while keeping its bottom edge anchored.
- `012-FR-007` - Register a system-wide hotkey, warn visibly on registration failure, and keep the in-app shortcut path.
- `012-FR-008` - Provide grouped configurable actions, persistence, per-action reset, and reset-all.
- `012-FR-009` - Dispatch non-global actions in-app without Accessibility permissions.
- `012-FR-010` - Preserve single-service chat, settings, and persistence behavior.

## Acceptance and traceability

The feature specifications also contain user scenarios, priorities, and edge cases. When a requirement is changed:

1. Update the relevant `specs/*/spec.md` first.
2. Update the corresponding implementation plan/tasks and tests.
3. Update this index and [Feature reference](feature-reference.md).
4. Run the build and test commands in [Testing and release](testing-and-release.md).
5. Refresh the codebase-memory index and record any new evidence gap.
