# Quickstart: Verify Core Chat and Streaming

## Prerequisites

- macOS development machine with the Warden Xcode project dependencies resolved.
- A deterministic local fake/delayed stream fixture; do not use paid or credentialed provider endpoints for automated verification.

## Focused tests

```sh
xcodebuild test \
  -project Warden.xcodeproj \
  -scheme Warden \
  -destination 'platform=macOS' \
  -only-testing:WardenTests/SSEStreamParserTests \
  -only-testing:WardenTests/StreamingTaskControllerTests \
  -only-testing:WardenTests/MessageManagerStreamingTests
```

Expected coverage:
- split and combined SSE events;
- comments/keep-alives, CRLF, malformed payload between valid events;
- final unterminated event;
- stale callbacks rejected after replacement;
- cancellation persists one partial response and completes once;
- empty/error/timeout paths clear waiting state;
- retry replaces the prior assistant response without a second user prompt;
- conversation A keeps ownership while conversation B is selected;
- deletion invalidates A before Core Data deletion.

## Build

```sh
xcodebuild \
  -project Warden.xcodeproj \
  -scheme Warden \
  -destination 'platform=macOS' \
  build
```

## Full tests

```sh
xcodebuild test \
  -project Warden.xcodeproj \
  -scheme Warden \
  -destination 'platform=macOS'
```

## Manual macOS workflow

1. Open conversation A and send a delayed deterministic streaming prompt.
2. Confirm text appears incrementally and Send changes to an accessible Stop control.
3. Scroll upward; confirm later chunks do not force the view back to the bottom.
4. Switch to conversation B; confirm A continues and no A chunk appears in B.
5. Return to A; confirm current partial text and Stop state are visible.
6. Stop A; confirm acknowledgement is immediate and one useful partial assistant response remains.
7. Retry that completed/partial response; confirm the user prompt is not duplicated and the assistant response is replaced.
8. Retry a request that fails before content; confirm the previous assistant response remains and waiting state clears.
9. Start a stream and delete its conversation; confirm no crash, later write, or reappearing chat.
10. Stream a synthetic 10,000-character response; verify Send/Stop acknowledgement remains under the 200 ms acceptance target under normal conditions.

## Privacy inspection

Search changed logs and fixtures. Confirm they contain only IDs/counts/durations/error categories and no prompts, response bodies, credentials, authorization data, or raw secret-bearing payloads.

## Results

Record commands and actual exit results here during implementation. Do not mark checks passed until run.

### 2026-08-12 implementation evidence

- Baseline focused command (SSE parser plus requested future test classes): exit 0. The existing
  `SSEStreamParserTests` passed; the requested session/manager test classes did not yet exist.
- RED: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'
  -only-testing:WardenTests/ChatStreamingSessionTests -only-testing:WardenTests/StreamingTaskControllerTests`
  failed as expected because `ChatStreamingSessionRegistry` and the keyed controller APIs were absent.
- GREEN: the same focused command passed after adding the conversation-owned session registry and keyed task
  controller (3 tests, 0 failures).
- Integrated focused command (session, controller, and SSE parser suites): exit 0; 6 tests, 0 failures.
- `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`: exit 0,
  `** BUILD SUCCEEDED **`.
- `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'`: exit 0,
  `** TEST SUCCEEDED **`; unit and UI suites completed with 0 failures (UI aggregate: 9 tests).
- `git diff --check`: exit 0. The changed feature code adds no Core Data model migration, provider API change,
  telemetry, credential, authorization, prompt, or response-body logging.

The deterministic provider/Core Data fixtures, MessageManager lifecycle tests, retry tests, scroll tests,
performance test, and deterministic UI workflow described by the task list remain outstanding.

### 2026-08-12 continuation evidence

- RED: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'
  -only-testing:WardenTests/SSEStreamParserTests` failed (exit 65) after the fragmented-CRLF test
  referenced the not-yet-implemented `SSEStreamParser.parse(chunks:)` entry point.
- GREEN: the same parser command passed (exit 0) after that entry point was added. The focused parser and
  session command also passed (exit 0) after compiling the deterministic stream and in-memory Core Data fixtures.
- `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build` passed (exit 0,
  `** BUILD SUCCEEDED **`) after session publication was made authoritative and coalesced.
- The full test command passed (exit 0) after the implementation change. The log output was piped through
  `tail` to keep the transcript bounded; its successful command status is the recorded outcome.
- `git diff --check` passed (exit 0). A targeted log/fixture audit found only a response character-count
  diagnostic in `MessageManager`; no fixture endpoint, credentials, authorization data, or chat body was found.

### 2026-08-12 UI/integration completion evidence

- RED: the new UI-focused command failed (exit 65) before implementation because
  `MessageListScrollBehavior`, `ChatViewModel.retryIntent(for:)`, and
  `ChatViewModel.retryState(for:)` did not exist. It also exposed that a recreated view model did not read an
  already-active session synchronously.
- GREEN: `ChatViewModelStreamingTests`, `ChatViewModelRetryTests`, and
  `MessageListScrollBehaviorTests` passed (7 tests, 0 failures). They cover A→B→A recreation/isolation,
  Stop after navigation, deletion invalidation without a manager, concrete retry target selection,
  configuration-error classification, and near-bottom follow versus upward-scroll intent.
- Foundation regression RED: the first all-focused pass found an incorrectly escaped CRLF fixture and missing
  explicit session publication in the coalesced-session test. After correcting those test fixtures, the parser
  and session run passed (6 tests, 0 failures).
- All Core Chat focused tests passed (exit 0; 21 tests, 0 failures): SSE/session/controller;
  MessageManager streaming, retry, and 10,000-character responsiveness/Stop evidence; and the three new UI
  suites. This is the relevant prior MessageManager focused/performance evidence.
- Full macOS build using isolated DerivedData passed (exit 0, `** BUILD SUCCEEDED **`). The shared
  `/Volumes/WDBlack4TB/XCodeDerivedData` build database was externally locked, so it was not used.
- Full-suite command was launched twice from that isolated DerivedData path. Both runs reached the existing UI
  test phase, but Xcode exited without a complete result bundle or final status; therefore no full-suite pass is
  claimed here.
- `git diff --check` passed after the focused verification.
- After adding the cancellation-to-composer focus handoff, the three UI-focused suites passed again
  (7 tests, 0 failures). The input restores the AppKit text editor as first responder when streaming transitions
  to idle, while Send/Stop retain explicit labels, values, and the Command-Return Send shortcut.
- Final XcodeMCP build passed in the configured Warden Xcode project (25.933 seconds, no errors).
- Final XcodeMCP active-plan run passed all 50 tests: 50 passed, 0 failed, 0 skipped, and 0 not run.
  This includes every Core Chat unit/performance test and all 8 UI tests.
- Final composer semantics review passed: Send and Stop use distinct icons and help text, explicit accessibility
  labels and values, disabled-state semantics, Command-Return Send, and focus restoration after streaming stops.
- Final staged-diff review found and fixed attachment-boundary duplication when deferred rendering begins.
  `MessageManagerStreamingTests.testAttachmentBoundaryChunkPersistsExactlyOnce` now covers the regression and
  the complete five-test MessageManager streaming suite passed.
- Post-fix XcodeMCP build passed (4.629 seconds, no errors). XcodeMCP cancelled two subsequent all-test actions,
  so the exact full-suite CLI command was rerun with isolated DerivedData instead of claiming an MCP result.
- Post-fix `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'
  -derivedDataPath /tmp/Warden-CoreChat-Final-DerivedData` exited 0 with `** TEST SUCCEEDED **`; all unit tests,
  including the attachment regression, and all 9 UI tests passed with 0 failures.
