# Feature Specification: Web Search and Citations

**Feature Branch**: `feature/time-machine-web-search-and-citations`
**Created**: 2026-08-12
**Status**: Draft
**Input**: User description: "Augments prompts with Tavily web results and shows search progress, sources, citation badges, and actionable errors."

## Clarifications

### Session 2026-08-12

- Q: How long should the query and source metadata remain available? → A: Retain the search query and source metadata with the associated local conversation until that conversation is deleted.
- Q: Where should the data-sharing disclosure appear? → A: Show a concise disclosure the first time the user enables web search, with a link to Web Search preferences.
- Q: What should happen to a pending prompt if enabled search fails? → A: Keep the prompt unsent, show an actionable search error, and let the user retry or disable search before sending.
- Q: Which source links may WardenApp open? → A: Open only `https://` links; display all other URLs as non-actionable text.
- Q: After disabling search following a failed search, how should the preserved prompt proceed? → A: Return the unchanged prompt to the composer; the user explicitly sends it without search.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Search an AI Prompt (Priority: P1)

A user with web search enabled sends a chat prompt and receives an AI response informed by current web results, while the app clearly communicates the search lifecycle.

**Why this priority**: This is the core user value: combining current web context with an AI answer without leaving the chat.

**Independent Test**: With a deterministic search-service fixture, enable web search, send a prompt, and verify that the user sees the search lifecycle and that the provider receives the formatted search context before generating its response.

**Acceptance Scenarios**:

1. **Given** web search is enabled and a valid key is available, **When** a user sends a non-empty prompt, **Then** the app shows search progress, augments only that request with results, and continues with the AI response.
2. **Given** web search is enabled but no key is stored, **When** the user sends a prompt, **Then** the app presents an actionable configuration error and keeps the prompt unsent until the user retries or explicitly disables search.
3. **Given** an enabled search fails for any recoverable reason, **When** the failure is shown, **Then** the app keeps the prompt unsent and offers retry or an explicit disable-search path that returns the unchanged prompt to the composer for an explicit send.
4. **Given** the user cancels a request while search is running, **When** cancellation completes, **Then** progress is dismissed and no partial search context is retained in the conversation.

---

### User Story 2 - Inspect Sources and Citations (Priority: P2)

A user can inspect the sources used for a web-assisted answer and follow supported inline citations to their originating web pages.

**Why this priority**: Source visibility enables users to judge freshness and credibility of an answer.

**Independent Test**: With canned sources and response text, verify that valid numbered citations resolve to the corresponding source URL, invalid citation indexes remain plain text, and the source list exposes the title and destination for every result attached to the message.

**Acceptance Scenarios**:

1. **Given** a completed web-assisted answer with sources, **When** the user opens its source presentation, **Then** each source shows a readable title and opens its matching destination.
2. **Given** a response contains a valid standalone numbered citation, **When** it is rendered, **Then** the citation links only to the matching source in that message.
3. **Given** a response contains malformed, embedded, or out-of-range citation text, **When** it is rendered, **Then** the original text remains readable and no incorrect link is created.

---

### User Story 3 - Configure and Validate Search (Priority: P3)

A user can securely configure search credentials and options, test connectivity, and understand how to enable search in a conversation.

**Why this priority**: Search must be opt-in, controllable, and diagnosable before users depend on it.

**Independent Test**: Using an isolated credential store and a stubbed network session, save settings, reload the preferences view model state, then validate the configured search depth, result limit, answer option, and connection-error mapping.

**Acceptance Scenarios**:

1. **Given** a user enters a search credential and settings, **When** they save them, **Then** settings persist across app relaunch and the credential is retrievable only through the secure credential store.
2. **Given** a stored credential is invalid, rate-limited, or the service is unavailable, **When** the user tests the connection or starts a search, **Then** they see a clear, non-secret-bearing remediation message.

### Edge Cases

- A blank command-style search query does not invoke the search service and explains how to provide a query.
- Empty results complete cleanly, preserve the user prompt, and do not invent sources or citations.
- Network failures, invalid payloads, authentication failures, rate limiting, and server errors clear progress and do not expose credentials, authorization data, or private prompts.
- Repeated sends and stale completion callbacks cannot attach one request's source metadata to another message.
- Only well-formed `https://` source URLs are rendered as actionable links; malformed URLs and all other schemes remain non-actionable text.
- Existing non-search chats, saved conversations, providers, and settings remain unchanged.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: WardenApp MUST let a user explicitly enable or disable web search per chat request without changing the behavior of requests where search is disabled.
- **FR-002**: When enabled, the app MUST obtain up to the user-configured limit of current web results, convert them into clearly delimited context for that request, and preserve the source list with the resulting assistant message.
- **FR-003**: The app MUST surface the states of starting, retrieving, processing, successful completion, cancellation, and failure without leaving stale progress visible.
- **FR-004**: The app MUST map missing credentials, invalid credentials, rate limits, unavailable service, invalid responses, and connectivity failures to actionable user-facing errors without revealing secret values or private request content; after a search failure, it MUST keep the pending prompt unsent until the user retries or explicitly disables search, in which case it returns the unchanged prompt to the composer for an explicit send.
- **FR-005**: The app MUST keep a web-assisted message's query, source list, timestamp, and result count associated with that message through local persistence and reload.
- **FR-006**: The app MUST turn only valid standalone numbered citations into links to sources belonging to the same message; unmatched citations MUST remain plain readable text.
- **FR-007**: The app MUST allow users to view each recorded source while retaining access to the response even when the original destination later fails to load; it MUST open only well-formed `https://` sources and render all other source URLs as non-actionable text.
- **FR-008**: Existing non-search conversations, provider request flow, chat history, and preferences MUST continue to work without a configured web-search credential.

### macOS UX Requirements

- **UX-001**: The search control, progress, source presentation, and citation badges MUST be discoverable by keyboard and expose meaningful accessibility labels.
- **UX-002**: Search progress and errors MUST update on the main UI context, dismiss on terminal states, and avoid blocking message composition or cancellation.
- **UX-003**: The preferences screen MUST make the credential, search depth, result limit, summarized-answer option, connectivity test, and search activation flow understandable without external documentation.

### Provider and Streaming Requirements

- **PR-001**: Search context MUST be injected only before the associated provider request and MUST remain compatible with cancellable incremental response handling.
- **PR-002**: Response streaming MUST keep source metadata isolated to the active request and must not permit late callbacks to mutate another message.
- **PR-003**: Citation conversion MUST be deterministic for multi-byte text and preserve non-citation markdown content.

### Data, Migration, and Privacy Requirements

- **DP-001**: The existing message metadata persistence format MAY be extended only in a backward-compatible manner; messages without search metadata must continue to decode.
- **DP-002**: Stored web-search credentials MUST remain in Keychain; they MUST NOT be persisted in Core Data, user defaults, source fixtures, diagnostic logs, network error messages, or rendered chat content.
- **DP-003**: The app MUST show a concise disclosure the first time a user enables web search that the current request query is sent to the configured search service, with a route to Web Search preferences; no analytics, telemetry, or unrelated chat history may be sent.
- **DP-004**: Source titles, URLs, query, timestamp, and result count MUST be retained with the associated local conversation until that conversation is deleted, and are removable when that conversation is removed.

### Key Entities

- **Search Request**: A user-enabled request containing a query and selected search settings; it is transient and must be cancellable.
- **Search Source**: A result title, URL, relevance value, and optional publication date that belongs to one completed search request.
- **Message Search Metadata**: Locally persisted message-owned record of the query, sources, search time, and result count used to display sources and citations after reload.
- **Search Status**: The user-visible lifecycle state for a single active search request.

## Compatibility and Scope

- **Affected modules**: `Warden/Utilities/TavilySearchService.swift`, `Warden/Utilities/TavilyKeyManager.swift`, `Warden/Models/TavilyModels.swift`, `Warden/Models/SearchModels.swift`, `Warden/UI/Preferences/TabTavilySearchView.swift`, `Warden/UI/Chat/Components/SearchProgressView.swift`, `Warden/UI/Chat/Components/SearchResultsPreviewView.swift`, `Warden/UI/Chat/Components/SearchErrorView.swift`, `Warden/UI/Chat/Components/MessageSourcesView.swift`, `Warden/UI/Chat/Components/CitationBadgeView.swift`, and focused files in `WardenTests/` and `WardenUITests/`.
- **Existing behavior preserved**: Standard chat, streaming, existing providers, saved conversations, and preferences operate normally without web search enabled.
- **Out of scope**: Search-provider switching, crawled-page storage, automatic web browsing without user action, analytics, server-side conversation storage, and source-quality guarantees.
- **Dependencies**: Existing secure credential storage, app settings, message persistence, and the configured web-search service; no additional tracking or credential-storage system.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In deterministic test scenarios, 100% of enabled web-assisted requests show a terminal search state and either continue with associated sources or show an actionable error without crashing.
- **SC-002**: 100% of valid standalone numbered citations in fixture responses link to the matching message source, while 100% of malformed or out-of-range fixture citations remain unlinked.
- **SC-003**: All new and affected focused unit/UI tests execute without live paid credentials or external network access.
- **SC-004**: During a simulated slow search, the app remains responsive to cancellation and message UI interaction, and no stale progress remains after completion or failure.
- **SC-005**: Credential, privacy, and logging tests confirm that no test-observable secret is persisted or emitted in diagnostics.

## Assumptions

- Web search is opt-in per request and uses the existing web-search preference surface.
- The configured service returns a bounded ordered list of web results with titles and URLs.
- The existing message metadata path is the local persistence boundary for source display after conversation reload and until the user deletes the associated conversation.
- Users retain responsibility for evaluating source quality and may open an external URL from the source presentation.
