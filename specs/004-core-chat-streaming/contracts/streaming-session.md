# Internal Contract: Conversation-Owned Streaming Session

## Purpose

Define the lifecycle boundary between `ChatViewModel`/`ChatView`, `MessageManager`, and provider-neutral stream transport. This is an internal Swift contract, not a network API.

## Operations

### Resolve

`session(for conversationID: UUID) -> ChatStreamingSession`

Returns the same live session for a conversation while its request is active. Different conversation IDs never share mutable stream state.

### Begin

`begin(conversationID, requestID, retryTarget?)`

- Invalidates/cancels an older request for the same conversation.
- Clears stale transient text/error.
- Publishes `starting` immediately.
- Does not alter another conversation's request.

### Accept chunk

`append(chunk, conversationID, requestID) -> Bool`

- Accepts non-empty content only if both IDs are current.
- Coalesces visible publication without changing content order.
- Returns false for stale, cancelled, deleted, or finalized requests.

### Stop

`cancel(conversationID) -> Bool`

- Publishes `cancelling` immediately.
- Cancels the keyed task.
- Is idempotent.
- Does not cancel streams in other conversations.

### Finalize

`claimFinalization(conversationID, requestID) -> Bool`

- Exactly one caller receives true.
- All later success/error/cancel callbacks receive false and perform no persistence or completion-state mutation.
- Forces pending accepted chunks into the final snapshot before persistence.

### Detach/delete

`invalidate(conversationID)`

- Rejects all later callbacks for the old identity.
- Cancels and releases the task/session after safe terminal cleanup.
- Must happen before deleting the `ChatEntity`.

## Completion semantics

- Success with content: append or replace one assistant entity, clear waiting state, complete once.
- Success without content: clear waiting state and report a redacted empty-response error.
- Cancellation with partial content: persist/replace once, clear waiting state, report cancellation once.
- Cancellation without content: clear waiting state, persist nothing.
- Provider error/timeout/malformed terminal failure: clear waiting state; preserve prior retry response if no replacement content exists.
- Tool-call handoff transfers lifecycle ownership without an intermediate duplicate completion.

## Retry semantics

- Retry references an existing user turn.
- Provider history includes that user turn once and excludes the assistant response being replaced.
- Visible history never gains a duplicate user prompt.
- Useful completed or cancelled output replaces the target assistant entity.
- Immediate failure leaves the old assistant target unchanged.

## Privacy

Allowed diagnostics: IDs, state names, chunk/character counts, duration, provider-independent error category.

Forbidden diagnostics: prompt/response body, API key/token, authorization headers, raw provider payloads containing user data, attachment contents, or secret-bearing tool arguments.
