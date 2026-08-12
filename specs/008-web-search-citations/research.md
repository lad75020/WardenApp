# Research: Web Search and Citations

## Decisions

### 1. Extend the existing Tavily integration rather than introduce a new search abstraction

**Decision**: Keep `TavilySearchService` as the focused network/context/citation utility. Add narrowly scoped validation and test seams only where needed.

**Rationale**: The repository already has Tavily request/response models, Keychain storage, a cancellable async service, search status, message metadata, source UI, and the chat send path. Replacing this implementation would duplicate credential and persistence responsibilities, enlarge the change surface, and risk regressions.

**Alternatives considered**:
- A generic multi-provider search layer — rejected as feature scope excludes provider switching.
- A web-view/browser integration — rejected by native macOS and opt-in privacy constraints.

### 2. Treat one send attempt as one isolated search transaction

**Decision**: Carry a request-scoped search outcome (query, sources, formatted context) through the specific send invocation; reject or ignore late completion after cancellation or request replacement.

**Rationale**: Existing `MessageManager` already uses streaming session IDs and cancellation. Search metadata must not be held solely as mutable manager-wide “last search” state because overlapping sends could attach sources to the wrong assistant message.

**Alternatives considered**:
- Continue using `lastSearchSources` / `lastSearchQuery` as the persistence source — rejected because these are manager-level state and can become stale.
- Persist search results before the provider response — rejected because failed/cancelled provider requests must not create unattached source records.

### 3. Preserve failed-search prompts in the composer, never auto-send without search

**Decision**: Search failure produces a recoverable pending-send state. Retry reuses the original prompt; disabling search returns the unchanged prompt to the composer and requires an explicit normal send.

**Rationale**: This implements the clarified user-control decision and avoids surprising provider requests after an external search failure.

**Alternatives considered**:
- Automatically send without search — rejected by the clarification.
- Discard the prompt — rejected because it loses user work.

### 4. Store source metadata with the existing message JSON property; do not change the Core Data schema

**Decision**: Continue encoding `MessageSearchMetadata` into the existing optional `MessageEntity.searchMetadataJson`, write it only when an assistant response is actually persisted, and rely on deletion of the parent conversation/message for removal.

**Rationale**: Existing messages without metadata already decode as `nil`; existing metadata fields meet the clarified retention requirement. No `.xcdatamodeld` change or migration is needed.

**Alternatives considered**:
- Add a source entity and relationship — rejected as an unnecessary schema migration for small message-owned metadata.
- UserDefaults storage — rejected because it is not conversation-owned and complicates deletion.

### 5. Accept and open only normalized HTTPS source URLs

**Decision**: Introduce a shared, testable source-URL validator used both while creating actionable citations and while rendering source UI. The validator accepts absolute `https` URLs with a host. All other strings remain readable, non-actionable text.

**Rationale**: Provider results are external input. Central validation prevents `http`, custom schemes, malformed URLs, and scheme-based app handoffs from being opened by `NSWorkspace`.

**Alternatives considered**:
- Allow `http` and `https` — rejected by the clarification.
- Trust every Tavily result — rejected because source URLs are untrusted external input.

### 6. Use a one-time local disclosure on first search enablement

**Decision**: Persist only acknowledgement of the disclosure in app preferences (never the query). When the globe control is first enabled, present a concise native alert/popover explaining that the current query is sent to Tavily, and provide a route to Web Search preferences.

**Rationale**: It meets the explicit consent boundary while avoiding a confirmation interruption for every request.

**Alternatives considered**:
- Preferences-only notice — rejected by clarification.
- Confirm every request — rejected as unnecessary repeated friction.

### 7. Test without a live Tavily key or external network

**Decision**: Add XCTest coverage for URL validation, citation conversion, error sanitization/mapping, metadata JSON round-trip, and request-scoped state with a stubbed `URLProtocol` or injected session. Add a focused XCUITest/manual workflow for first-enable disclosure and failed-search composer recovery if test accessibility permits.

**Rationale**: Constitution requires deterministic tests without paid credentials. `URLSession` injection already exists on `TavilySearchService`.

**Alternatives considered**:
- Exercise production Tavily during tests — rejected because it leaks fixtures externally and requires paid credentials.
