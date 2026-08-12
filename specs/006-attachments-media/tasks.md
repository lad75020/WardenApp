# Tasks: Attachments and Media

**Input**: Design documents from `specs/006-attachments-media/`  
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/attachment-message-contract.md`, `quickstart.md`  
**Verification**: XCTest/XCUITest plus the Warden macOS build; no real paid credentials.

## Phase 1: Baseline and Setup

- [X] T001 Record current attachment composition, rendering, export, and test seams in `specs/006-attachments-media/plan.md`.
- [X] T002 Run the parser regression suite in `WardenTests/Utilities/MessageParserTests.swift`.
- [X] T003 Run the macOS build for `./Warden.xcodeproj` using the `Warden` scheme.

## Phase 2: Foundational Contracts and Regression Tests

- [X] T004 Add image/file/video marker, malformed-marker, and unavailable-media regression tests in `WardenTests/Utilities/MessageParserTests.swift`.
- [X] T005 [P] Add deterministic attachment preparation/resolution fixtures and tests in the existing compiled `WardenTests/Utilities/MessageParserTests.swift` (the Xcode test target has an explicit sources list, so new test files are not auto-included).
- [X] T006 [P] Define safe local-video availability and export decision tests in the existing compiled `WardenTests/Utilities/MessageParserTests.swift` (the Xcode test target has an explicit sources list, so new test files are not auto-included).
- [X] T007 Document persistence/no-migration compatibility, serialization ordering, and transient-video contract in `specs/006-attachments-media/data-model.md` and `specs/006-attachments-media/contracts/attachment-message-contract.md`.

## Phase 3: User Story 1 — Attach and send supported content (Priority: P1) 🎯 MVP

**Goal**: Users can prepare, review, remove, and send multiple ready images/files without silently omitting failed or loading content.

**Independent Test**: Fixture image/file preparation completes in arbitrary order; a failed item leaves the draft usable and blocks a misleading send.

- [X] T008 [US1] Add readiness/error predicates and deterministic preparation tests in `Warden/Models/ImageAttachment.swift`, `Warden/Models/FileAttachment.swift`, and the existing compiled `WardenTests/Utilities/MessageParserTests.swift`.
- [X] T009 [US1] Gate draft send/clear behavior on ready attachments in `Warden/UI/Chat/ChatView.swift` and `Warden/UI/Chat/QuickChatView.swift`.
- [X] T010 [US1] Surface attachment-local loading/error/removal state and send accessibility feedback in `Warden/UI/Chat/BottomContainer/MessageInputView.swift` and `Warden/UI/Components/FilePreviewView.swift`.
- [X] T011 [US1] Verify ready attachment persistence precedes UUID marker serialization in `Warden/UI/Chat/ChatView.swift` and `Warden/UI/Chat/QuickChatView.swift`.
- [X] T012 [US1] Run focused attachment, resolver, video-support, and parser tests in the existing compiled `WardenTests/Utilities/MessageParserTests.swift`.

## Phase 4: User Story 2 — Render and interact with sent images/files (Priority: P2)

**Goal**: Stored images/files render after restart and can be opened, zoomed, revealed, or exported; missing data is nonfatal.

**Independent Test**: A durable UUID resolves from fixture persistence; an unknown/corrupt UUID produces an unavailable element while adjacent content renders.

- [X] T013 [US2] Implement nonfatal resolution outcome handling and cache-safe background lookup in `Warden/Utilities/AttachmentResolver.swift` and `Warden/Utilities/BackgroundDataLoader.swift`.
- [X] T014 [P] [US2] Preserve attachment marker parsing, including malformed fallback, in `Warden/Utilities/MessageParser.swift`, `Warden/Utilities/IncrementalMessageParser.swift`, and `WardenTests/Utilities/MessageParserTests.swift`.
- [X] T015 [US2] Render explicit unavailable image/file states and retain neighboring message content in `Warden/UI/Chat/BubbleView/MessageContentView.swift`.
- [X] T016 [US2] Make image zoom/reset/close/save behavior safe and keyboard-accessible in `Warden/UI/Chat/ZoomableImageView.swift`.
- [ ] T017 [US2] Run focused resolution/parser tests and manually exercise the durable-history workflow in `specs/006-attachments-media/quickstart.md`.

## Phase 5: User Story 3 — Generated video (Priority: P3)

**Goal**: Local generated videos play inline, can be revealed/saved, and show a clear unavailable/error state after local removal or restart.

**Independent Test**: A local fixture video URL is accepted; absent/malformed URLs never crash or overwrite a destination.

- [X] T018 [US3] Add transient video URL, local-readability, and safe-copy regression tests in the existing compiled `WardenTests/Utilities/MessageParserTests.swift` (the Xcode test target has an explicit sources list, so new test files are not auto-included).
- [X] T019 [US3] Validate transient result creation, cancellation/failure mapping, and redacted diagnostics in `Warden/Utilities/APIHandlers/VeoHandler.swift`.
- [X] T020 [US3] Render available/unavailable video media and avoid indefinite loading in `Warden/UI/Chat/BubbleView/MessageContentView.swift` and `Warden/UI/Chat/BubbleView/VideoAttachmentView.swift`.
- [X] T021 [US3] Implement reveal/save guards that never remove an existing destination in `Warden/UI/Chat/BubbleView/VideoAttachmentView.swift`.
- [ ] T022 [US3] Run focused video tests and manually exercise playback, Finder reveal, save cancellation, save conflict, and missing-file paths from `specs/006-attachments-media/quickstart.md`.

## Phase 6: Cross-Cutting Verification and Polish

- [X] T023 Review attachment/provider diagnostics for privacy-safe `WardenLog` use in `Warden/Models/`, `Warden/Utilities/`, and `Warden/UI/Chat/`.
- [x] T024 Validate VoiceOver labels, keyboard actions, cancellation, app-restart persistence, and transient-video unavailability using `specs/006-attachments-media/quickstart.md`.
- [X] T025 Run the macOS build for `./Warden.xcodeproj` using the `Warden` scheme.
- [x] T026 Run the full XCTest suite for `./Warden.xcodeproj` using the `Warden` scheme.
- [X] T027 Confirm no secrets, private fixture data, DerivedData, or build outputs appear in the `./.git/` repository diff using `git status` and `git diff`.

## Dependencies and Execution Order

1. T001–T007 establish evidence and testable contracts.
2. T008–T012 deliver the P1 send workflow.
3. T013–T017 build durable historical rendering on the P1 persistence path.
4. T018–T022 complete the independent transient-video workflow.
5. T023–T027 are final verification and privacy gates.

## Parallel Opportunities

- T004–T006 may proceed in parallel because they add independent test files.
- After T007, T013 and T014 can proceed in parallel with separate ownership.
- T018 and T019 can proceed in parallel before UI integration in T020–T021.

## Implementation Strategy

Deliver P1 first: protect user intent in draft preparation and persistence. Add P2 historical recovery/rendering next. Complete P3 only after its local-file contract and safe-export behavior are covered. Do not add a Core Data migration or persist generated video bytes.
