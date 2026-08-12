# Tasks: Core Chat and Streaming

**Input**: Design documents from `/specs/004-core-chat-streaming/`
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/streaming-session.md`, and `quickstart.md`
**Verification**: XCTest/XCUITest plus the Warden macOS build; tests use deterministic fakes and no real provider credentials

## Format: `[ID] [P?] [Story] Description`

- **[P]** means the task can run in parallel because it touches different files and has no unresolved dependency.
- **[US#]** maps implementation and verification to one user story.
- Test tasks precede the implementation they verify and must fail for the expected reason before implementation.

## Phase 1: Baseline and Setup

**Purpose**: Establish reproducible current behavior and credential-free test seams.

- [X] T001 Record current focused-test and build baselines with actual command outcomes in `specs/004-core-chat-streaming/quickstart.md`
- [X] T002 [P] Add a deterministic delayed/chunked provider test double with cancellation and terminal-result control in `WardenTests/TestSupport/DeterministicStreamingService.swift`
- [X] T003 [P] Add an in-memory Core Data chat/message fixture that never loads provider credentials in `WardenTests/TestSupport/InMemoryChatFixture.swift`
- [X] T004 Confirm the fake stream fixtures contain no network endpoints, API keys, authorization data, prompts from real chats, or paid-provider calls in `WardenTests/TestSupport/`

**Checkpoint**: Existing failures are recorded and deterministic test support can drive all lifecycle paths.

---

## Phase 2: Foundational Conversation-Owned Stream Contract

**Purpose**: Establish shared request identity and session lifetime before story-specific behavior.

- [X] T005 Add failing request-identity, per-conversation isolation, stale-callback, and exactly-once-finalization tests in `WardenTests/Utilities/ChatStreamingSessionTests.swift`
- [X] T006 Add failing keyed replace, cancel, invalidate, and cross-conversation task-isolation tests in `WardenTests/Utilities/StreamingTaskControllerTests.swift`
- [X] T007 Implement the main-actor observable conversation-keyed session registry and lifecycle contract in `Warden/Utilities/ChatStreamingSession.swift`
- [X] T008 Refactor keyed task ownership, request-ID checks, cancellation, invalidation, and current-task cleanup in `Warden/Utilities/StreamingTaskController.swift`
- [X] T009 Wire `ChatViewModel` to resolve and publish only its chat's shared stream session in `Warden/UI/Chat/ChatViewModel.swift`
- [X] T010 Run the new foundational tests and record actual results in `specs/004-core-chat-streaming/quickstart.md`

**Checkpoint**: A stream can outlive its SwiftUI view while stale or cross-chat work cannot mutate its session.

---

## Phase 3: User Story 1 — Send and Stream a Response (Priority: P1) 🎯 MVP

**Goal**: Submit one prompt, show ordered incremental output responsively, and persist one final assistant response in the originating conversation.

**Independent Test**: A deterministic service emits delayed fragmented/combined chunks; the user message appears once, visible text grows in order, switching A→B→A preserves A's current stream, and final content is saved once in A only.

### Tests for User Story 1

- [X] T011 [P] [US1] Expand split-event, combined-event, CRLF, keep-alive, malformed-neighbor, multi-line data, and final-unterminated-event coverage in `WardenTests/Utilities/SSEStreamParserTests.swift`
- [X] T012 [P] [US1] Add failing ordered-chunk, empty-success, timeout/error cleanup, duplicate-finalization, and originating-conversation persistence tests in `WardenTests/Utilities/MessageManagerStreamingTests.swift`
- [X] T013 [P] [US1] Add failing background stream visibility and A→B→A isolation tests for recreated view models in `WardenTests/UI/ChatViewModelStreamingTests.swift`
- [X] T014 [P] [US1] Add failing user-scroll-intent/autoscroll decision tests in `WardenTests/UI/MessageListScrollBehaviorTests.swift`

### Implementation for User Story 1

- [X] T015 [US1] Harden structural SSE framing and EOF flushing without changing provider payload semantics in `Warden/Utilities/SSEStreamParser.swift`
- [X] T016 [US1] Refactor stream begin, guarded chunk accumulation, coalesced publication, empty-response failure, and exactly-once success persistence in `Warden/Utilities/MessageManager.swift`
- [X] T017 [US1] Derive Send/streaming/waiting/error presentation from the active chat session while preserving invalid-configuration drafts in `Warden/UI/Chat/ChatView.swift`
- [X] T018 [US1] Show the active session's current transient response and persisted messages without duplicate chunks in `Warden/UI/Chat/MessageListView.swift`
- [X] T019 [US1] Preserve user-controlled scroll position and only follow streaming output while near the bottom in `Warden/UI/Chat/MessageListView.swift`
- [X] T020 [US1] Keep Send/Stop controls responsive and expose meaningful non-color accessibility labels and keyboard behavior in `Warden/UI/Chat/BottomContainer/MessageInputView.swift`
- [X] T021 [US1] Run focused US1 and foundational tests and record actual outcomes in `specs/004-core-chat-streaming/quickstart.md`

**Checkpoint**: User Story 1 is independently usable with no live provider and no cross-conversation writes.

---

## Phase 4: User Story 2 — Stop an Active Response Safely (Priority: P2)

**Goal**: Stop the originating request promptly, reject later chunks, save at most one meaningful partial response, and restore a usable composer.

**Independent Test**: Cancel a deterministic long stream after known chunks, race cancellation with completion, and verify immediate cancelling state, no late text, one partial response at most, cleared indicators, and a subsequent send succeeds.

### Tests for User Story 2

- [X] T022 [P] [US2] Add failing pre-first-chunk, buffered-chunk, late-chunk, cancellation/completion race, and empty-partial tests in `WardenTests/Utilities/MessageManagerStreamingTests.swift`
- [X] T023 [P] [US2] Add failing Stop-after-navigation and active-chat deletion invalidation tests in `WardenTests/UI/ChatViewModelStreamingTests.swift`

### Implementation for User Story 2

- [X] T024 [US2] Implement immediate keyed Stop acknowledgement, forced accepted-buffer flush, one-time partial persistence, and terminal cleanup in `Warden/Utilities/MessageManager.swift`
- [X] T025 [US2] Route Stop through the originating conversation's shared controller and ignore stale terminal callbacks in `Warden/UI/Chat/ChatViewModel.swift`
- [X] T026 [US2] Invalidate and cancel a conversation stream before any chat deletion path completes in `Warden/UI/Chat/ChatViewModel.swift`
- [X] T027 [US2] Restore focus and coherent idle/error controls after cancellation without blocking the window in `Warden/UI/Chat/ChatView.swift`
- [X] T028 [US2] Run focused US2 tests plus all foundational and US1 regressions and record outcomes in `specs/004-core-chat-streaming/quickstart.md`

**Checkpoint**: Cancellation and deletion are race-safe, partial history is singular, and Stories 1–2 remain independently testable.

---

## Phase 5: User Story 3 — Retry and Continue the Conversation (Priority: P3)

**Goal**: Retry a failed, cancelled, or completed turn without duplicating its user prompt and replace the prior assistant response while preserving bounded context for later prompts.

**Independent Test**: Retry a completed response and a failed response with deterministic outcomes; visible/persisted history contains one original user message and one replacement assistant response, immediate failure preserves the old response, and a subsequent prompt uses clean bounded context.

### Tests for User Story 3

- [X] T029 [P] [US3] Add failing retry request-history, assistant replacement, failed-before-content preservation, partial replacement, and subsequent bounded-context tests in `WardenTests/Utilities/MessageManagerRetryTests.swift`
- [X] T030 [P] [US3] Add failing retry-target selection and retryable-versus-configuration-error state tests in `WardenTests/UI/ChatViewModelRetryTests.swift`

### Implementation for User Story 3

- [X] T031 [US3] Add explicit retry intent resolution and provider context construction that includes the original user turn once and excludes its prior assistant response in `Warden/Utilities/MessageManager.swift`
- [X] T032 [US3] Update or append exactly one assistant entity on retry and synchronize serialized request history with ordered visible history in `Warden/Utilities/MessageManager.swift`
- [X] T033 [US3] Route Retry with the concrete user turn and optional assistant replacement target instead of bare prompt text in `Warden/UI/Chat/ChatViewModel.swift`
- [X] T034 [US3] Bind menu, bubble, and error Retry actions to explicit retry intent while preserving drafts and accessibility in `Warden/UI/Chat/ChatView.swift`
- [X] T035 [US3] Run focused US3 tests plus all prior-story regressions and record actual outcomes in `specs/004-core-chat-streaming/quickstart.md`

**Checkpoint**: Retry produces one coherent turn and later sends start with clean lifecycle and context state.

---

## Phase 6: Polish & Cross-Cutting Verification

- [X] T036 [P] Add a deterministic 10,000-character responsiveness test for coalesced streaming and Stop acknowledgement in `WardenTests/Performance/ChatStreamingPerformanceTests.swift`
- [X] T037 [P] Audit changed diagnostics for IDs/counts/durations only and remove prompt, response, credential, authorization, and raw payload disclosure from `Warden/Utilities/MessageManager.swift`
- [X] T038 [P] Verify Send, Stop, Retry, status, keyboard/focus, and non-color state semantics in `Warden/UI/Chat/BottomContainer/MessageInputView.swift`
- [X] T039 Execute the deterministic A→B→A, Stop, Retry, failure, deletion, scroll, and 10,000-character workflows and record evidence in `specs/004-core-chat-streaming/quickstart.md`
- [X] T040 Run `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build` and record the real result in `specs/004-core-chat-streaming/quickstart.md`
- [X] T041 Run `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'` and record the real result in `specs/004-core-chat-streaming/quickstart.md`
- [X] T042 Verify the final diff contains no schema migration, API keys, private chat data, DerivedData, build output, provider-scope expansion, attachment redesign, or multi-agent redesign and record the audit in `specs/004-core-chat-streaming/quickstart.md`

## Dependencies and Execution Order

1. Phase 1 establishes deterministic fixtures and baseline evidence.
2. Phase 2 blocks all stories because request identity and conversation-keyed lifetime prevent stale/cross-chat mutation.
3. US1 is the MVP and establishes send, incremental display, persistence, navigation continuity, and parser correctness.
4. US2 depends on US1's lifecycle but is independently testable through cancellation and deletion races.
5. US3 depends on US1 persistence/context behavior and US2 partial-response semantics.
6. Final verification follows all selected stories.

## Parallel Opportunities

- T002 and T003 can proceed in parallel in separate test-support files.
- T011–T014 can proceed in parallel after Phase 2 because they target separate test files.
- T022 and T023 can proceed in parallel before US2 implementation.
- T029 and T030 can proceed in parallel before US3 implementation.
- T036–T038 can proceed in parallel after story implementation because they target performance tests, service logging, and UI accessibility respectively.
- Do not parallelize overlapping edits to `Warden/Utilities/MessageManager.swift`, `Warden/UI/Chat/ChatViewModel.swift`, or `Warden/UI/Chat/ChatView.swift`.

## Implementation Strategy

1. Deliver the conversation-keyed session foundation and US1 as the MVP.
2. Add race-safe Stop/deletion behavior without changing provider contracts.
3. Add explicit retry replacement on the stable lifecycle.
4. Run focused tests after each story, then the authoritative full build/test and privacy/scope audit.

## Completion Evidence

Mark a task complete only after its file change or command has been exercised. Build/test tasks require actual tool output; environment blockers must be recorded verbatim with the strongest unaffected verification, never inferred as success.
