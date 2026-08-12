# Implementation Plan: Core Chat and Streaming

**Branch**: `feature/time-machine-core-chat-and-streaming` | **Date**: 2026-08-12 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/004-core-chat-streaming/spec.md`

## Summary

Deliver reliable single-conversation chat composition and provider streaming while preserving request ownership when the user navigates between conversations. The smallest architecture-aligned change is to make each in-flight stream a conversation-keyed utility session that survives `ChatView` recreation, give every request an immutable ID and conversation ID, and make finalization idempotent. `ChatViewModel` observes the session for its chat, `MessageManager` owns request construction/persistence, and retry explicitly targets the prior assistant message so it is replaced without duplicating the user prompt. Existing provider handlers and Core Data schema remain unchanged.

## Technical Context

**Language/Version**: Swift 5.9
**Primary Frameworks**: SwiftUI, AppKit where required, Foundation, Combine, Core Data
**Persistence**: Core Data through `Warden/Store/ChatStore.swift`; Keychain for secrets
**Testing**: XCTest (`WardenTests/`) and XCUITest (`WardenUITests/`)
**Target Platform**: Native macOS 26.0
**Project Type**: Xcode macOS application with unit/UI test targets and an auxiliary CLI target
**Build Command**: `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`
**Test Command**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'`
**Performance Goals**: Stop/send acknowledgement and visible streaming updates within 200 ms under normal conditions for a representative 10,000-character response; bounded/coalesced main-actor updates; no forced autoscroll after intentional upward scrolling.
**Constraints**: Privacy-first; no telemetry; no credentials or message bodies in logs; Keychain secrets; deterministic tests without live providers; cancellable streaming; request-ID guarded and main-actor-safe UI/persistence state.
**Scale/Scope**: One active stream per conversation, independent streams may exist in different conversations; affected chat view/view-model, message manager, stream parser/controller/session state, and focused unit/UI tests; all existing streaming providers continue through `ChatService`/`APIProtocol`.

## Constitution Check

*GATE: Must pass before research and be re-checked after design.*

- [x] Native macOS and privacy-first behavior is preserved.
- [x] Each changed file belongs to its documented module.
- [x] Provider work conforms to `APIProtocol` and uses existing factory/base abstractions; no provider contract change is required.
- [x] Secrets remain in Keychain and are excluded from Core Data, fixtures, and logs.
- [x] No Core Data schema change is planned; existing chats remain compatible.
- [x] Async/streaming work specifies cancellation, failure, conversation ownership, idempotent finalization, and actor safety.
- [x] Focused XCTest/XCUITest coverage is identified and does not require paid credentials.
- [x] The only new abstraction is a conversation-keyed streaming session registry, justified by streams outliving a SwiftUI view instance.

Post-design re-check: PASS. The design remains inside existing UI/Utilities boundaries, changes no provider or persistence schema, and adds no dependency.

## Architecture Impact

### Affected Modules

| Module | Path | Planned responsibility/change |
|---|---|---|
| App entry/config | `Warden/WardenApp.swift`, `Warden/Configuration/` | N/A. Existing Retry command continues to post its notification. |
| UI / view models | `Warden/UI/Chat/ChatView.swift`, `Warden/UI/Chat/ChatViewModel.swift`, `Warden/UI/Chat/MessageListView.swift`, `Warden/UI/Chat/BottomContainer/MessageInputView.swift` | Bind send/stop/loading state to the active chat's shared stream session; carry an explicit retry target; preserve scroll intent and accessibility labels. |
| Shared models | `Warden/Models/` | No persisted/shared domain model change. |
| Services/managers | `Warden/Utilities/MessageManager.swift`, `Warden/Utilities/StreamingTaskController.swift`, new `Warden/Utilities/ChatStreamingSession.swift`, `Warden/Utilities/SSEStreamParser.swift`, `Warden/Utilities/IncrementalMessageParser.swift` as gaps require | Own conversation-keyed request state, retry request construction, cancellation, callback gating, exactly-once finalization, and robust stream parsing. |
| Provider handlers | `Warden/Utilities/APIHandlers/` | N/A unless a focused test exposes a provider-specific violation of the existing stream callback contract. |
| Persistence | `Warden/Store/` | No schema/store change. Message replacement uses the existing managed-object context and ordered relationship. |
| MCP | `Warden/Core/MCP/` | N/A; selected tool lookup remains existing behavior. |
| Unit tests | `WardenTests/Utilities/SSEStreamParserTests.swift`, new focused `MessageManagerStreamingTests.swift`, `StreamingTaskControllerTests.swift` or equivalent | Boundary parsing, stale callbacks, cancellation/partial finalization, retry replacement, and conversation ownership with fakes. |
| UI tests | `WardenUITests/` | Add deterministic navigation/stop/retry coverage only where the test seam can avoid provider credentials; otherwise execute documented manual workflow. |
| CLI/local packages | `MLXZImageSwiftCLI/`, `Packages/` | N/A. |

### Dependency Flow

`ChatView` sends a normal prompt or an explicit retry intent to its `ChatViewModel`. The view model resolves the `ChatStreamingSession` keyed by `chat.id`, so a recreated view observes the same transient text/state and can cancel the original request. `MessageManager` prepares provider-neutral request history, starts `ChatService.sendStream`, and routes chunks through the immutable `(conversationID, requestID)` session identity. The session coalesces published text on the main actor. Completion/cancellation claims finalization once, then `MessageManager` appends a new assistant message or updates the retry target in the original chat and saves through the existing managed-object context. Provider handlers remain presentation- and Core-Data-independent.

A request from conversation A never reads the currently selected conversation. Navigation to B only changes which keyed session the UI observes. Starting a newer request in A supersedes/cancels the prior A request; callbacks carrying the old request ID are ignored. Deletion first cancels/detaches A's session and waits for its ownership to be invalidated before removing the managed object.

### Provider/API Contract

No `APIProtocol` signature or provider selection change is planned. `ChatService.sendStream` continues to provide incremental chunks and an optional tool-call result. The feature adds an internal orchestration contract:

- request identity is created before task launch and includes the initiating conversation ID;
- chunk callbacks are accepted only while that identity is current;
- Stop cancels the keyed task and acknowledges immediately in session state;
- timeout/provider/malformed-event errors terminate waiting state exactly once;
- malformed payloads may be ignored by provider decoding without corrupting adjacent valid SSE events;
- a final unterminated SSE event is flushed at end-of-stream;
- empty success becomes a terminal empty-response failure rather than a permanent waiting state;
- completion is delivered once, including tool-call handoff paths.

See [contracts/streaming-session.md](./contracts/streaming-session.md).

### Persistence and Migration

**No schema change.** Normal sends append one user entity and one assistant entity. Retry identifies the user message and the immediately associated assistant response in ordered chat history, excludes that response from provider context, does not append another user entity, and updates/replaces the existing assistant entity only when useful replacement content is available. Cancellation with non-empty partial output may replace the retry target; failure before output leaves the prior response intact. `chat.requestMessages` is rebuilt or updated to mirror visible ordered history so no duplicate retry prompt/assistant response remains. Existing chats need no migration.

Deletion safety is coordinated before `viewContext.delete(chat)`: invalidate the session identity, cancel its task, and ensure late callbacks cannot mutate the deleted `ChatEntity`.

### Security and Privacy

Prompts and provider responses leave the device only through the already selected provider. No telemetry or analytics is introduced. Diagnostic logs may include request/conversation identifiers, counts, durations, and error categories, but never prompt text, response bodies, authorization headers, tokens, tool arguments containing user data, or credentials. Provider secrets remain in Keychain. Test fixtures use synthetic content and fake services. Errors shown to users are actionable but redact transport secrets and response bodies.

## Project Structure

### Feature Documentation

```text
specs/004-core-chat-streaming/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── streaming-session.md
└── tasks.md
```

### Source Paths

```text
Warden/
├── UI/Chat/
│   ├── ChatView.swift
│   ├── ChatViewModel.swift
│   ├── MessageListView.swift
│   └── BottomContainer/MessageInputView.swift
└── Utilities/
    ├── ChatStreamingSession.swift          # new transient per-chat session/registry
    ├── MessageManager.swift
    ├── StreamingTaskController.swift
    ├── SSEStreamParser.swift
    └── IncrementalMessageParser.swift

WardenTests/
└── Utilities/
    ├── SSEStreamParserTests.swift
    ├── StreamingTaskControllerTests.swift
    └── MessageManagerStreamingTests.swift

WardenUITests/                               # optional deterministic UI workflow coverage
```

**Structure Decision**: Keep presentation and retry command routing in `UI/Chat`; keep stream lifetime, token gating, parsing, and persistence orchestration in `Utilities`. Create `ChatStreamingSession.swift` because the existing `MessageManager` is owned by a `ChatViewModel` and cannot expose ongoing transient state or Stop after that view is recreated. Modify parser/controller files only for requirements not already covered. Do not touch provider handlers, Core Data model, app configuration, rich rendering, attachments, or multi-agent behavior unless required to keep existing calls compiling.

## Test and Verification Plan

1. **Regression first**: add failing tests for stale chunks after replacement, conversation A continuing while B is selected, cancellation persisting one partial response, retry replacing rather than appending, empty/malformed terminal streams clearing waiting state, and split/combined/keep-alive/unterminated SSE input.
2. **Focused unit tests**: run `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/SSEStreamParserTests -only-testing:WardenTests/StreamingTaskControllerTests -only-testing:WardenTests/MessageManagerStreamingTests` (adjust test class names to implemented names).
3. **UI workflow**: with a deterministic local fake/delayed service, verify send, incremental output, intentional upward scroll, Stop, retry after completed/failed response, switch A→B→A during streaming, and deletion of a streaming chat. Confirm keyboard and VoiceOver labels for Send/Stop/Retry.
4. **Performance**: stream a synthetic 10,000-character response and measure observable send/Stop acknowledgement and update latency; confirm no unbounded per-chunk main-actor work or forced autoscroll.
5. **Build**: run `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`.
6. **Full tests**: run `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'`; report only real blockers.
7. **Privacy review**: inspect changed logging, persisted request history, Keychain boundaries, error surfaces, and synthetic fixtures for message/secret disclosure.

## Delivery Phases

### Phase 0 — Research and Risk Reduction

Capture current stream ownership, retry duplication, parser boundary, deletion, and autoscroll behavior as focused failing tests. Introduce a deterministic fake stream producer or injected stream operation at the narrowest existing seam; do not contact live providers.

### Phase 1 — Models, Contracts, and Persistence

Implement transient `ChatStreamingSession` state and conversation-keyed registry plus request/finalization identity. Add explicit retry context (`user message`, optional assistant replacement target) without a Core Data migration. Implement ordered-history request construction and replacement persistence so visible messages and `requestMessages` stay consistent.

### Phase 2 — Services and Provider Integration

Refactor `MessageManager.sendMessageStream` into testable lifecycle stages: begin, accept guarded chunks, flush/coalesce, claim finalization, persist once, and finish. Extend `StreamingTaskController` for keyed identity/invalidation as needed. Close SSE parser gaps for arbitrary byte/event boundaries and malformed-neighbor handling while preserving existing provider delivery modes.

### Phase 3 — Native macOS UI

Bind `ChatViewModel` and `ChatView` to the keyed session instead of view-local `isStreaming` truth. Route Stop and Retry with explicit identities, restore partial text when returning to a conversation, coordinate deletion, and retain user-controlled scroll position. Preserve responsive Send/Stop controls and accessibility help/labels.

### Phase 4 — Verification and Documentation

Run focused tests, deterministic UI/manual workflows, the authoritative build, and full test suite. Inspect logs and persistence for privacy and duplicate history. Record actual verification results in `quickstart.md` or implementation notes without claiming unrun checks.

## Complexity Tracking

No Constitution Check violations are planned.
