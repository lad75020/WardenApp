# Feature Specification: Core Chat and Streaming

**Feature Branch**: `feature/time-machine-core-chat-and-streaming`
**Created**: 2026-08-11
**Status**: Draft
**Input**: User description: "Feature: Core Chat and Streaming. Description: Enables users to compose prompts, receive cancellable streamed responses, retry messages, and manage the active conversation. Relevant files: Warden/UI/Chat/ChatView.swift, Warden/UI/Chat/ChatViewModel.swift, Warden/UI/Chat/MessageListView.swift, Warden/UI/Chat/BottomContainer/, Warden/Utilities/MessageManager.swift, Warden/Utilities/SSEStreamParser.swift, Warden/Utilities/StreamingTaskController.swift, Warden/Utilities/IncrementalMessageParser.swift. Focus on this feature only; do not modify other features."

## Clarifications

### Session 2026-08-11

- Q: When retrying a prompt that already has an assistant response, what should happen to the previous response? → A: Replace the previous assistant response.
- Q: What happens when the user switches conversations during an active stream? → A: Continue streaming in the original conversation.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Send and Stream a Response (Priority: P1)

A macOS user enters a non-empty prompt in the active conversation and sees the assistant response appear progressively while the app remains responsive. The completed response becomes part of the conversation history.

**Why this priority**: Sending a prompt and receiving a readable response is the minimum useful chat experience.

**Independent Test**: Use a deterministic mock provider that emits several delayed chunks, send one prompt, and verify that the user message appears once, response text grows in order, controls remain responsive, and the final assistant message is persisted once.

**Acceptance Scenarios**:

1. **Given** an active conversation with a configured streaming-capable service, **When** the user submits a non-empty prompt, **Then** the prompt appears once and ordered response content becomes visible incrementally until completion.
2. **Given** a response is streaming, **When** chunks arrive with partial event boundaries or multiple events in one delivery, **Then** the visible and persisted response preserves the provider's logical text order without dropped or duplicated content.
3. **Given** no usable service is configured, **When** the user attempts to send, **Then** the app preserves the draft and presents an actionable error without creating a stuck response.

---

### User Story 2 - Stop an Active Response Safely (Priority: P2)

A user can stop a response that is no longer useful. The app ends the active request promptly, keeps any meaningful partial answer, and returns the composer to a usable state.

**Why this priority**: Cancellation protects user control, time, and provider usage during long or incorrect responses.

**Independent Test**: Start a deterministic long-running mock stream, cancel after known chunks, and verify that no later chunks appear, the partial response is saved at most once, waiting indicators clear, and another prompt can be sent immediately.

**Acceptance Scenarios**:

1. **Given** a response is streaming, **When** the user activates Stop, **Then** the active work is cancelled, streaming indicators end, and received content remains available as one partial assistant response.
2. **Given** cancellation races with normal completion, **When** both signals occur nearly together, **Then** the app records at most one assistant response and finishes in a non-streaming state.
3. **Given** no response is active, **When** a stale cancellation callback arrives, **Then** it does not alter the current conversation or a newer request.

---

### User Story 3 - Retry and Continue the Conversation (Priority: P3)

A user can retry a failed or unsatisfactory exchange without duplicating the original user message, and can continue sending subsequent prompts in the same active conversation.

**Why this priority**: Recoverable errors and revision are essential for dependable daily use but depend on the core send path.

**Independent Test**: Make a mock request fail, invoke retry, then succeed; verify that only one original user message remains, one successful assistant result is added, and a subsequent prompt uses the expected conversation context.

**Acceptance Scenarios**:

1. **Given** a retryable failed or completed response, **When** the user retries, **Then** the original prompt is resubmitted without adding a duplicate user message and the prior assistant response is replaced by the retried result.
2. **Given** a response has completed or been cancelled, **When** the user sends another prompt, **Then** the new request uses the active conversation's bounded context and does not inherit stale stream state.
3. **Given** a request fails, **When** the error is shown, **Then** the user can distinguish a retryable failure from a configuration problem and can continue using the conversation after corrective action.

### Edge Cases

- Empty or whitespace-only prompts do not create messages or requests.
- Rapid repeated submission does not create overlapping requests or duplicate user messages.
- A stream may end without a trailing newline, split an event across deliveries, combine multiple events, contain keep-alive lines, or provide malformed payloads among valid events.
- Cancellation may occur before the first chunk, during buffered parsing, while saving, or concurrently with completion.
- Empty successful responses, provider timeouts, offline failures, and malformed streams leave no permanent waiting state.
- Switching conversations while a request is running keeps that request active and routes all subsequent chunks and finalization exclusively to its original conversation.
- Deleting a conversation with an active request safely cancels or detaches that request before deletion completes so no later write targets deleted state.
- Large responses remain scrollable and the UI does not force the user to the bottom after they intentionally scroll upward.
- Repeated callbacks and stale asynchronous work cannot overwrite a newer request's state.
- Private prompts, response bodies, credentials, and authorization data are excluded from diagnostics and user-facing technical details.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: WardenApp MUST allow users to submit a non-empty prompt from the active conversation using the primary send control and the established keyboard action.
- **FR-002**: The app MUST add each submitted user prompt to the active conversation exactly once and MUST preserve its ordering relative to assistant responses.
- **FR-003**: For a streaming-capable selected service, the app MUST show assistant text incrementally in provider-defined order and MUST finalize it as one assistant message.
- **FR-004**: For services or operations that do not stream, the app MUST provide the same coherent waiting, success, and failure lifecycle without presenting a false streaming state.
- **FR-005**: Users MUST be able to stop an active response, after which no stale content from that request may be appended.
- **FR-006**: Cancellation MUST preserve meaningful partial response content at most once and MUST clear all waiting and streaming indicators.
- **FR-007**: The app MUST support retrying an eligible failed or prior prompt without duplicating the original user message; the retried result MUST replace the prior assistant response rather than preserving both.
- **FR-008**: A new request MUST start with clean transient stream state and MUST supersede or reject older active work deterministically.
- **FR-009**: Request context MUST be derived from the active conversation and respect its configured context limit.
- **FR-010**: Provider, transport, parsing, timeout, and cancellation failures MUST produce an understandable recoverable state without corrupting conversation history.
- **FR-011**: Stream parsing MUST preserve complete logical events across arbitrary delivery boundaries and MUST process a final valid event even when the transport ends without a trailing delimiter.
- **FR-012**: Conversation mutations and observable chat state MUST occur safely and consistently when callbacks arrive from asynchronous work.
- **FR-013**: Existing unaffected provider selection, saved conversations, attachments, web search, local generation, and multi-agent behavior MUST continue to behave as before.
- **FR-014**: Switching to another conversation MUST NOT cancel an active stream; the request MUST continue against its originating conversation and MUST never append content to the newly active conversation.

### macOS UX Requirements

- **UX-001**: The composer MUST provide clear Send and Stop states, preserve keyboard navigation, and maintain predictable input focus after success, cancellation, or recoverable failure.
- **UX-002**: Empty, waiting, streaming, cancelled, completed, and error states MUST be visually distinguishable without blocking the main window.
- **UX-003**: Send, Stop, Retry, and error actions MUST have meaningful accessibility labels and keyboard access; status changes MUST not rely on color alone.
- **UX-004**: During streaming, automatic scrolling MUST follow new content only while the user has not intentionally moved away from the latest response.
- **UX-005**: User-entered draft text MUST not be lost when submission cannot begin because configuration or validation fails.
- **UX-006**: Returning to a conversation with a background stream MUST show its current response and accurate streaming status without replaying or duplicating chunks.

### Provider and Streaming Requirements

- **PR-001**: Chat sending MUST use the selected service's established provider contract and honor whether the operation supports streaming.
- **PR-002**: Streaming work MUST be cancellable end-to-end, including transport, parsing, response accumulation, and UI finalization.
- **PR-003**: Event-stream parsing MUST tolerate fragmented and combined event deliveries, ignore non-content control lines, and surface malformed or failed streams without crashing.
- **PR-004**: Completion, failure, and cancellation callbacks MUST be delivered once per request and MUST not finalize a superseded request.
- **PR-005**: Diagnostics MAY record public operational metadata such as durations and chunk counts but MUST NOT include credentials, full prompts, full responses, or authorization headers.

### Data, Migration, and Privacy Requirements

- **DP-001**: This feature MUST NOT require a persistent data-model schema change; it uses the existing conversation and message entities.
- **DP-002**: Existing conversations and messages MUST remain readable and writable without migration or destructive reset.
- **DP-003**: Provider secrets remain owned by the existing Keychain-backed configuration flow and MUST NOT enter chat persistence or logs.
- **DP-004**: Prompt and conversation content MUST be disclosed only to the user-selected provider and explicitly enabled services; retry and cancellation MUST NOT introduce additional destinations.
- **DP-005**: Partial responses saved after cancellation MUST follow the same local retention and deletion behavior as completed assistant messages.

### Key Entities

- **Active Conversation**: The currently selected local chat, including ordered messages, selected service, context limit, waiting state, and persistence ownership.
- **Chat Message**: A user or assistant entry with content, role, ordering metadata, and optional response-related metadata, owned by one conversation.
- **Streaming Request**: Ephemeral work for one prompt, identified independently from persisted messages and carrying cancellation and lifecycle state.
- **Stream Event**: One logical provider delivery unit whose content may span transport chunks before being emitted in order.

## Compatibility and Scope

- **Affected modules**: `Warden/UI/Chat/ChatView.swift`, `Warden/UI/Chat/ChatViewModel.swift`, `Warden/UI/Chat/MessageListView.swift`, `Warden/UI/Chat/BottomContainer/`, `Warden/Utilities/MessageManager.swift`, `Warden/Utilities/SSEStreamParser.swift`, `Warden/Utilities/StreamingTaskController.swift`, `Warden/Utilities/IncrementalMessageParser.swift`, and focused tests under `WardenTests/` or `WardenUITests/`.
- **Existing behavior preserved**: Provider/model configuration, Core Data ownership, attachment handling, web-search enrichment, rich rendering, local model generation, multi-agent mode, quick chat, and conversation organization remain compatible.
- **Out of scope**: New providers, new message rendering formats, attachment/media workflows, search/citation behavior, persona/model-selection UI, multi-agent orchestration, and persistent schema redesign.
- **Dependencies**: Existing provider protocol and factory, local chat store, Core Data model, Swift concurrency and cancellation, URL loading, and existing logging/signpost facilities. No new external dependency is proposed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In deterministic tests, 100% of emitted mock text events appear in the visible and final response in the original order with no duplication.
- **SC-002**: A user-initiated stop prevents later mock chunks from appearing, clears active indicators within one second, and saves no more than one partial assistant message.
- **SC-003**: Retry scenarios retain exactly one copy of the original user prompt and exactly one corresponding assistant response, with the retried result replacing the prior response without recreating the conversation.
- **SC-004**: Empty, offline, timeout, malformed-stream, cancellation, and completion scenarios finish without a crash, leaked sensitive content, corrupted chat state, or permanently active waiting indicator.
- **SC-005**: Focused deterministic tests cover event fragmentation, final unterminated events, cancellation races, duplicate-finalization prevention, retry behavior, and user-controlled scrolling without live provider credentials.
- **SC-006**: During a representative 10,000-character streamed response, the composer remains interactive and user input or Stop actions receive visible acknowledgement within 200 milliseconds under normal test conditions.
- **SC-007**: In deterministic conversation-switching tests, an original conversation receives 100% of its background stream events in order while the newly selected conversation receives none of them.

## Assumptions

- One standard chat conversation has at most one active response request, while separate conversations may retain independent background stream state; multi-agent concurrency is governed by its separate feature.
- The selected provider configuration and model capability determine whether the standard chat path streams or completes as one response.
- Existing conversation persistence remains authoritative for completed and intentionally retained partial messages.
- A cancelled partial response is useful user-visible history and may be deleted through existing message or conversation controls.
- Existing attachments, web search, tool calls, and image-generation routing remain integrations around this lifecycle rather than being redesigned here.
