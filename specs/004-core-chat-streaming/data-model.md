# Data Model: Core Chat and Streaming

## Persisted entities

No Core Data schema change is required.

### ChatEntity (existing)

Relevant fields/relations:
- `id: UUID` — stable conversation ownership key.
- `messages: NSOrderedSet` — visible ordered user/assistant turns.
- `requestMessages` — provider-neutral serialized history; must mirror retry replacement.
- `waitingForResponse: Bool` — durable/UI compatibility flag that must be false after every terminal path.

### MessageEntity (existing)

Relevant fields:
- `id: Int64` — display/order metadata within the chat.
- `body: String`
- `own: Bool` — `true` user, `false` assistant.
- `timestamp: Date?`
- `waitingForResponse: Bool`
- provider/search/tool metadata retained when replacing as appropriate.

### Retry relationship (derived, not stored)

For a retrying user message, the replacement target is the first assistant message in the same ordered conversation immediately following that user turn and before the next user turn. If absent (failed response), retry appends the first assistant response. No user entity is added.

## Transient types

### ChatStreamingSession

Key: `conversationID: UUID`.

State:
- `requestID: UUID?`
- `phase: idle | starting | streaming | cancelling | finishing | failed`
- `visibleAssistantText: String`
- `hasReceivedContent: Bool`
- `terminalError: redacted error?`
- `replacementMessageObjectID: NSManagedObjectID?` or equivalent opaque target

Invariants:
1. Only the current request ID may mutate the session.
2. `idle` has no request ID and no active task.
3. Finalization can be claimed once.
4. Session state never contains credentials or authorization data.
5. Conversation A state cannot be returned for conversation B.

### Stream request identity

Fields:
- `conversationID: UUID`
- `requestID: UUID`

Used by all chunk and terminal callbacks. Equality of both fields is required before mutation.

### Retry intent

Fields:
- `userMessageObjectID` (or stable in-context reference)
- `assistantReplacementObjectID?`
- `promptBody`

The intent is resolved on the managed-object context before launch. It is not persisted separately.

## State transitions

```text
idle -> starting -> streaming -> finishing -> idle
                    |              ^
                    -> cancelling -|
                    -> failed -> idle
```

- New request in the same conversation invalidates/cancels the prior identity first.
- Navigation does not change the state.
- Stop moves to `cancelling` immediately; transport termination later claims finalization.
- Empty success and malformed/timeout failure clear `waitingForResponse` and end in `failed`/`idle` with an actionable redacted error.
- Deletion invalidates the identity before removing persisted objects.

## Persistence rules

- Normal send: append one user, then at most one assistant response.
- Retry: append no user; update existing assistant response or append one only if no target exists.
- Cancellation: persist at most one non-empty partial assistant response.
- Empty cancellation: persist nothing.
- Duplicate terminal callbacks: no persistence after the first finalization claim.
- Rebuild/update `requestMessages` after retry replacement to match visible ordered history.
