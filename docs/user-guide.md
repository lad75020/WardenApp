# User guide

WardenApp is a native macOS chat application. The exact arrangement of controls can evolve, but the workflows below describe the behavior implemented by the current project.

## The application shell

The main window provides navigation and a detail area for the welcome state, chats, projects, and previews. The application restores the last selected chat when it still exists. If the saved selection is stale, it returns to the appropriate welcome state instead of failing.

The shell supports:

- New Chat: `Cmd+N`.
- New Project: `Cmd+Shift+N`.
- New Window: `Cmd+Option+N`.
- Toggle Sidebar: `Cmd+S`.
- Preferences: `Cmd+,`.
- Retry and copy/export commands from the application menu.

The window frame is saved and restored. A practical default frame is used when no saved frame exists.

## Onboarding and Preferences

The welcome flow selects its message and actions from the current provider configuration, chat count, and onboarding state. Onboarding has a guided provider step and can open Preferences without creating duplicate settings windows.

Preferences cover the main application settings, including:

- API service configuration.
- Personas.
- Model selection and favorites.
- Web search settings.
- MCP servers and tools.
- Appearance and chat font size.
- Sidebar service-icon visibility.
- Hotkeys and Quick Chat preferences.
- Backup and import actions where enabled by the current build.

Appearance choices are System, Light, and Dark. The supported chat font-size range is 10 through 24 points.

## Services and models

A service is the saved connection configuration used by a chat. It contains a stable identity, display name, provider type, endpoint, selected model, context settings, streaming preference, and a Keychain-backed credential reference when required.

From API Services, a user can:

1. Add a service.
2. Inspect and edit its connection and model fields.
3. Test the connection.
4. Refresh models when discovery is supported.
5. Choose a discovered, preset, or custom model identifier.
6. Duplicate a service into a new identity.
7. Set one service as the default.
8. Delete a service.

Deleting a service does not silently delete conversations that used it. A chat whose service is gone remains available as an unavailable chat until the user remaps it or deletes it.

A model refresh must not replace the previously selected model merely because discovery failed. Save a deliberate model choice after a successful refresh or manual selection.

## Personas

A persona is a reusable instruction profile. It contains a name, symbol, system message, temperature, and optional default service.

Users can:

- Create, edit, reorder, and delete personas.
- Choose a persona for a conversation.
- Apply its system message and temperature.
- Explicitly apply its default service when one exists and remains valid.

Applying a persona does not automatically replace the conversation service or model. Applying a persona service is a separate action, and the app checks that the service and model still exist before switching.

The first run may create the built-in persona set through the database patcher. Existing personas are preserved through normal migration behavior.

## Sending a chat message

1. Open or create a chat.
2. Choose the service, model, and optional persona.
3. Type a non-empty prompt.
4. Add attachments or enable search if needed.
5. Submit with the primary send control or the established keyboard action.

The user message is added exactly once. For a streaming-capable service, the assistant response appears incrementally and is finalized as one message. Non-streaming operations use the same waiting, success, and failure lifecycle without presenting a false stream.

The active request is tied to the conversation where it began. Switching to another conversation does not move later chunks to the newly selected chat.

### Stop and retry

- Stop cancels an active response and clears waiting/streaming indicators.
- Meaningful partial content can be retained at most once.
- Retry reuses an eligible prompt without duplicating the original user message.
- A retry replaces the prior assistant result rather than leaving duplicate assistant responses.
- A failed request leaves the conversation in a recoverable state.

## Rich messages

Assistant content can contain prose, headings, emphasis, lists, links, quotations, inline code, tables, formulas, reasoning blocks, and attachment markers. The renderer preserves source order.

Users can:

- Select response text.
- Copy a whole message.
- Copy a code block.
- Copy a table as tabular text or JSON.
- Open an explicitly requested HTML preview.
- Refresh, resize, zoom, and close the HTML preview.

Incomplete or malformed Markdown remains readable. Unclosed fences, invalid tables, unsupported language names, malformed links, and invalid math must not crash the chat interface.

The HTML preview is intentionally user initiated. It is not a general browser window and should not be used as a trusted execution environment.

## Attachments and media

Users can add supported local files and images to the draft before sending. Each attachment shows its name, available size, type-appropriate preview or icon, and preparation state.

The application may extract text, store image bytes and thumbnails, and include prepared content in a provider request. Failed or unavailable content is not sent as if it were complete.

For available images, users can:

- Open a larger viewer.
- Zoom and pan.
- Reset the view.
- Close the viewer.
- Save a copy to a user-selected location.

Generated videos can be shown inline with playback controls, saved to a selected location, or revealed in Finder when the local file is still readable. A save or reveal failure does not delete or overwrite the source.

Attachment files, paths, and credentials are not appropriate content for diagnostics. Share or export an attachment only through an explicit user action.

## Chat organization

The sidebar supports local conversation search, projects, pinning, archiving, and date grouping. Search matching is case and diacritic insensitive and includes chat title, system instruction, persona name, and message body.

Users can:

- Create, rename, open, move, clear, and delete chats.
- Create, rename, archive, and manage projects.
- Pin conversations.
- Search existing local history.
- Move a chat into a project.

Pinned chats appear before date-grouped unpinned chats. Empty chats and chats with missing optional data remain searchable and exportable.

### Branching

A branch is a separate conversation created from the selected source message. It copies the relevant history and source settings without mutating the original conversation, its project membership, or its credentials.

### Copy, export, and share

A chosen conversation can be copied, exported, or shared as plain text, Markdown, or JSON. The output includes conversation metadata, the system instruction when present, and messages in chronological order. The action is explicit; credentials and diagnostic-only data are excluded.

## Web search and citations

Web search is opt-in per request. The supported command aliases are `/search`, `/web`, and `/google`.

When search is enabled:

1. Enter the search command and query.
2. WardenApp performs a search through the configured search service.
3. Results are converted into delimited context for the selected provider.
4. The source list, timestamp, and result count are associated with the resulting assistant message.
5. Numbered citations that match sources for that message become links.

Search progress exposes starting, retrieving, processing, completion, cancellation, and failure states. A failed search keeps the prompt unsent until the user retries or explicitly disables search and sends the unchanged prompt.

Only well-formed `https://` sources are actionable. Other schemes and malformed URLs remain readable but non-actionable.

The default search result limit is five and the configured upper limit is ten. Search credentials are stored separately from chat content.

## Local AI

WardenApp can route local requests through Ollama, LM Studio, MLX, Hugging Face, or Core ML configurations depending on the selected service and build support.

Local model behavior includes:

- Local text inference through the same cancellable conversation workflow.
- Capability-aware routing for vision and image generation.
- Model discovery for supported Ollama and LM Studio endpoints.
- Actionable errors for missing assets, incompatible models, unavailable runtimes, and malformed local responses.
- Preservation of the current usable model selection when discovery fails.

Local model paths and prompts should remain local unless the user deliberately chooses a remote service.

## MCP tools

MCP servers are configured in Preferences. A server uses either:

- Stdio: command, arguments, and environment.
- SSE: a server URL.

Users can add, edit, enable, disable, delete, and test configurations. A successful test reports the discovered tool count. Connected servers expose a status and tool list.

For each chat, users can select one or more connected agents. The selected tools are forwarded to the active provider. WardenApp executes a requested tool against its owning agent, records the result, and requests a final assistant response without re-offering the same tools to avoid loops.

Tool progress is shown as calling, executing, completed, or failed. Completed tool calls can be expanded later from the resulting message.

MCP environment values that look sensitive are stored in the Keychain and represented in UserDefaults by a marker. MCP servers do not auto-connect at launch unless the user enables the auto-connect preference, which is disabled by default.

## Multi-agent comparison

Multi-agent mode sends one prompt to multiple configured services in parallel. At most three services are used for a turn. Each agent renders independently with its service name and model, and each has separate completion and error state.

One stop action cancels all in-flight agents. A service that fails does not corrupt the successful results from the other selected services.

## Quick Chat and hotkeys

Quick Chat is a floating, non-activating panel that can be summoned while WardenApp is not frontmost. It is positioned near the top center of the main screen, focuses its input on open, hides on Escape or focus loss, and resets its panel state when opened.

The panel height follows content between 60 and 600 points while keeping its bottom edge anchored. It can use clipboard context when the captured content is below the configured safety limit.

The global Quick Chat hotkey and other actions are configurable in Preferences. Shortcuts persist across launches. A failed global registration produces a visible warning and does not disable the in-app menu shortcut path.

## Backups and recovery

Use the application backup/export controls for JSON chat backup when available. Canceling a panel or providing malformed data must leave current data unchanged.

If a persistent-store failure triggers the in-memory fallback, changes in that session are not durable. Restart and repair the store before continuing important work.

## Related references

- [Configuration reference](configuration-reference.md)
- [Data and persistence](data-and-persistence.md)
- [Security and privacy](security-and-privacy.md)
- [Troubleshooting](troubleshooting.md)
