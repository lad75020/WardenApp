# Research: Core Chat and Streaming

## Decision 1 — Key transient stream state by conversation

**Decision**: Add a main-actor observable `ChatStreamingSession` resolved from a registry by `ChatEntity.id`. The session stores only transient request ID, phase, accumulated visible text, and cancellation/finalization state; task mutation remains actor-protected.

**Rationale**: `ChatView` owns `ChatViewModel` as a `StateObject`, and each view model lazily owns a `MessageManager`. The stream task retains its original manager and chat, so it can finish after navigation, but a newly created view cannot see or stop that manager's transient stream. A keyed session lets navigation change presentation without transferring ownership.

**Alternatives rejected**:
- Persist every partial chunk to Core Data: excessive writes and conflates transient rendering with durable history.
- Keep all chat views alive: fragile SwiftUI lifecycle dependency and unnecessary memory use.
- App-global unkeyed stream: cannot support isolated conversation ownership and risks cross-chat writes.

## Decision 2 — Immutable request IDs and exactly-once finalization

**Decision**: Every stream receives a UUID and initiating conversation UUID. Chunks, completion, error, cancellation, and tool-call handoff must prove the request is current before mutating state. Finalization is an atomic/actor-isolated claim and can happen once.

**Rationale**: Current nested `Task { @MainActor in ... }` chunk callbacks may execute after cancellation or after a replacement request begins. Request gating prevents stale callbacks from clearing or overwriting newer state and duplicate persistence.

**Alternatives rejected**:
- Rely only on `Task.isCancelled`: callback tasks have independent cancellation state.
- Rely only on chronological completion: network and main-actor scheduling are not ordered guarantees.

## Decision 3 — Retry carries a replacement target

**Decision**: Resolve retry to the selected/latest user message and its following assistant response. Build provider context through that user turn without appending the same prompt again, and update the assistant target on successful/non-empty partial completion. Preserve the old assistant response if retry fails before useful output.

**Rationale**: Current UI sends `retryContent` without saving a second visible user entity, but generic request construction can append the prompt to history that already contains it and successful handling always appends a new assistant entity. Explicit retry intent removes ambiguity and allows transactional replacement semantics.

**Alternatives rejected**:
- Delete old response before starting: loses useful content on immediate failure.
- Append a new response and hide the old one: leaves duplicate persisted history and inconsistent exports/context.
- Add a Core Data response-link field: unnecessary migration because ordered conversation turns already identify the adjacent response for this single-conversation feature.

## Decision 4 — Preserve the existing provider abstraction

**Decision**: Keep `APIProtocol`, `APIServiceFactory`, and `ChatService.sendStream` signatures unless tests prove an unavoidable gap. Add test seams around orchestration rather than provider implementations.

**Rationale**: The feature concerns lifecycle and ownership, not provider configuration. Existing handlers already emit chunks through shared paths, and expanding provider work would overlap later queue features.

## Decision 5 — Parse SSE structurally and flush EOF

**Decision**: Retain byte-based UTF-8 line assembly, SSE blank-line event boundaries, comment/non-data filtering, multi-line `data:` joining, and EOF flush. Add deterministic cases for split delivery, combined events, CRLF, keep-alives, malformed payloads between valid events, and an unterminated final event. Provider payload decoding—not framing—decides whether malformed data is ignored or fails the request.

**Rationale**: `URLSession.AsyncBytes.lines` may omit an unterminated final line. The existing parser already addresses several cases; tests should drive only missing behavior.

## Decision 6 — Coalesce UI updates and respect scroll intent

**Decision**: Continue buffered/coalesced text updates at a bounded interval on the main actor. Autoscroll only while the user remains near the bottom; intentional upward movement disables forced scrolling until an explicit send or return-to-bottom action.

**Rationale**: Per-token SwiftUI publication is expensive for long responses, while delayed Stop state makes cancellation appear broken. Control-state acknowledgement is immediate; text publication can remain coalesced.

## Decision 7 — Cancel/invalidate before chat deletion

**Decision**: Deletion first invalidates the conversation's session identity and cancels its task, then deletes the `ChatEntity`. Late callbacks are rejected by identity even if transport cancellation races.

**Rationale**: A stream task retains the managed object and can otherwise write after deletion, causing invalid Core Data access or resurrected/inconsistent state.
