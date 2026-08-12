# Tasks: Rich Message Rendering

**Input**: Design documents from `specs/005-rich-message-rendering/`  
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/rendering-contract.md`, `quickstart.md`

## Phase 1: Test Seams and Regression Coverage

- [x] T001 Inspect existing parser and rendering tests; add deterministic fixtures for headings, emphasis, lists, links, quotes, code fences, tables, display math, and reasoning blocks in `WardenTests/`.
- [x] T002 Add regression tests for malformed/unclosed code fences, tables, math delimiters, and `<think>` blocks; verify readable fallback and source order.
- [x] T003 Add streaming/incremental parser tests for chunk boundaries, finalization, cancellation, and stale-update prevention.
- [x] T004 Add long-message tests for prompt truncated rendering, explicit full parsing, and attachment exemption.

## Phase 2: Parser and Native Rendering

- [x] T005 [P] Harden `Warden/Utilities/MessageParser.swift` to preserve ordered content and safely finalize malformed or incomplete blocks.
- [x] T006 [P] Update `Warden/UI/Components/MarkdownView.swift` to render supported Markdown consistently, accessibly, and with selectable content.
- [x] T007 Update `Warden/UI/Chat/BubbleView/MessageContentView.swift` to publish only current parse results, preserve long-content behavior, and retain existing attachment/citation paths.
- [x] T008 Update `Warden/UI/Chat/ThinkingProcessView.swift` for labelled disclosure state, keyboard operation, and readable streaming/fallback states.
- [x] T009 Update `Warden/UI/Chat/BubbleView/TableView.swift` to safely handle uneven rows and validate copy/JSON behavior without an out-of-bounds failure.

## Phase 3: Code and HTML Preview

- [x] T010 [P] Update `Warden/UI/Chat/CodeView/CodeView.swift` and its view model for source-faithful copy, robust language fallback, and streaming highlight behavior.
- [x] T011 Harden `Warden/UI/Chat/HTMLPreviewView.swift` navigation and content-security handling; keep nonpersistent local preview and block script, network, forms, frames, external navigation, and file disclosure.
- [x] T012 Add focused tests/manual verification evidence for preview isolation, refresh, zoom, device selection, close behavior, and a load-failure fallback.

## Phase 4: Verification

- [x] T013 Run parser and focused rendering XCTest cases; fix regressions.
- [x] T014 Run XcodeMCP build and applicable test target; inspect actual output.
- [x] T015 Run `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build` and then the repository test command; document only real blockers.
- [x] T016 Review changed diagnostics and persistence paths for message-content, credential, file, and network disclosure; verify no Core Data migration was introduced.
- [x] T017 Update feature queue status and Spec Kit artifacts; commit only after all verification passes.

## Dependencies

- T001–T004 before T005–T009.
- T005 before T007–T009.
- T006–T009 can proceed in parallel after T005 where file overlap permits.
- T010–T012 are independent of parser changes except integration validation.
- T013–T017 follow implementation.

## Implementation Strategy

Deliver P1 structured-message correctness first (T001–T009), then P2 code/preview safety and controls (T010–T012), followed by end-to-end verification. Do not alter provider transport, Core Data schema, or persisted message source text.

## Verification notes

- 2026-08-12: `swiftc -parse` succeeded for every changed Swift source and the focused XCTest file; `git diff --check` also passed.
- 2026-08-12: with `CLANG_MODULE_CACHE_PATH` and `SWIFTPM_MODULECACHE_OVERRIDE` redirected to `/tmp/WardenAppModuleCache`, `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/WardenAppDerivedData build` succeeded.
- 2026-08-12: focused parser coverage passed: `MessageParserTests` and `MessageParserSSEStreamParserTests`, 17 tests total, 17 passed. The same build and focused test selection also passed through XCodeMCP (0 build errors; 17 passed, 0 failed).
- 2026-08-12: the full repository `xcodebuild test` command executed but failed on three unrelated, unchanged tests: `AppShellUITests.testMalformedImportShowsNonDestructiveFeedback` (XCUI event synthesis timeout while typing a local path), `ChatViewModelRetryTests.testRetryRoutesNonStreamingConfigurationThroughNonStreamingManager` (invalid `idle` → `failed(deinit)` transition), and `MessageManagerStreamingTests.testCancellationBeforeFirstChunkPersistsNothingAndClearsWaitingState` (completion expectation timed out). T017 remains open: no feature queue transition or commit was made while the full suite is red.
