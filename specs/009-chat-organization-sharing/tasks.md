---
description: "Dependency-ordered implementation tasks for native macOS chat organization and sharing"
---

# Tasks: Chat Organization and Sharing

**Input**: Design documents from `/specs/009-chat-organization-sharing/`  
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/ui-contracts.md`, and `quickstart.md`  
**Verification**: XCTest plus the Warden macOS build; all tests must use in-memory Core Data and no paid provider credentials

## Format: `[ID] [P?] [Story] Description`

- **[P]** means the task is safe to execute in parallel because it has a different file scope and no unresolved dependency.
- **[US#]** maps each task to the specified user story.
- Test tasks precede their implementation tasks and must initially demonstrate the missing/regressed contract.

## Phase 1: Baseline and Setup

**Purpose**: Confirm affected targets, current regression behavior, and deterministic test infrastructure before modifying app code.

- [X] T001 Inspect `Warden.xcodeproj/project.pbxproj`, `WardenTests/TestSupport/InMemoryChatFixture.swift`, and `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` to record target membership and the in-memory Core Data fixture pattern in `specs/009-chat-organization-sharing/plan.md`.
- [X] T002 Run the focused existing persistence regression command against `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` using `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/ChatHistoryRecoveryTests test`.
- [X] T003 Run the baseline build with `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build` and record actual outcome in `specs/009-chat-organization-sharing/quickstart.md`.
- [X] T004 [P] Verify `WardenTests/TestSupport/InMemoryChatFixture.swift` and all new fixtures avoid `Warden/Utilities/APIHandlers/`, live credentials, and network calls; record the constraint in `specs/009-chat-organization-sharing/research.md`.

**Checkpoint**: Target membership and a credential-free in-memory testing path are confirmed; any baseline failure is documented before feature edits.

---

## Phase 2: Foundational Privacy and Test Seams

**Purpose**: Lock down the no-migration, privacy, and testability contracts shared by later stories.

- [ ] T005 Add shared deterministic chat/project/persona/message fixture helpers in `WardenTests/TestSupport/InMemoryChatFixture.swift` for chronological messages, optional system instructions, pinning, archived projects, and branch source selection.
- [X] T006 [P] Add a privacy regression test in `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` proving representative API-key/authorization-like values are not part of export output or diagnostic contracts.
- [X] T007 Document the unchanged Core Data compatibility decision in `specs/009-chat-organization-sharing/data-model.md` after comparing `Warden/Models/Models.swift` with `Warden/Store/ChatStore.swift`; do not edit `Warden/Resources/warenDataModel.xcdatamodeld`.
- [X] T008 Define a narrow, non-persisted export formatter/result seam in `Warden/Utilities/ChatSharingService.swift` only if needed to test format content, filename safety, and file-write failures without presenting AppKit UI.

**Checkpoint**: No Core Data migration is introduced, fixture data stays local, and export behavior has a deterministic test boundary.

---

## Phase 3: User Story 1 — Find and organize conversations (Priority: P1) 🎯 MVP

**Goal**: Make the existing local sidebar search, pin/date grouping, project/archive navigation, and descriptive project-summary states reliably testable and accessible.

**Independent Test**: With in-memory seeded records, `WardenTests/UI/ChatListOrganizationTests.swift` verifies case/diacritic-insensitive matching across title, system instruction, persona, and message body; pinned-first ordering; and archived-project visibility without state mutation. Manual validation follows the search/project section of `specs/009-chat-organization-sharing/quickstart.md`.

### Tests for User Story 1

- [ ] T009 [P] [US1] Add local search predicate/result regression coverage in `WardenTests/UI/ChatListOrganizationTests.swift` for title, system instruction, persona name, message body, no-message chats, case/diacritic matching, and a stale/cancelled query not replacing the active query.
- [ ] T010 [P] [US1] Add persistence and ordering coverage in `WardenTests/UI/ChatListOrganizationTests.swift` for pinned-before-date-grouped chats, project assignment, and archived projects surviving context reload without restoration/deletion.
- [ ] T011 [P] [US1] Add locally derived empty, loading, and populated summary-state coverage in `WardenTests/UI/ProjectSummaryViewModelTests.swift` or an extracted testable helper under `Warden/UI/Chat/ProjectSummaryView.swift`, with no provider handler invocation.

### Implementation for User Story 1

- [X] T012 [US1] Refine only verified search cancellation/result-publication, focus/clear semantics, and explicit VoiceOver labels in `Warden/UI/ChatList/ChatListView.swift` while preserving background-context Core Data access and the one-second debounced-search goal.
- [X] T013 [US1] Refine only verified archive-expansion labels/state and project-row keyboard accessibility in `Warden/UI/ChatList/ProjectListView.swift` and `Warden/UI/ChatList/ChatListView.swift`, without changing archived-project persistence.
- [X] T014 [US1] Refine local empty/loading/populated descriptive presentation and accessibility in `Warden/UI/Chat/ProjectSummaryView.swift` and `Warden/UI/Chat/ProjectSummaryButton.swift`, without adding provider/network work.
- [ ] T015 [US1] Run the focused organization tests in `WardenTests/UI/ChatListOrganizationTests.swift` and manual search/project verification from `specs/009-chat-organization-sharing/quickstart.md`.

**Checkpoint**: The sidebar independently finds and organizes local chats, and project summaries remain local-only.

---

## Phase 4: User Story 2 — Create and navigate conversation branches (Priority: P2)

**Goal**: Preserve existing branch creation while proving source immutability, exact history cutoff, settings/context copying, user-safe error behavior, and accessible progress/retry UI.

**Independent Test**: `WardenTests/Utilities/ChatBranchingManagerTests.swift` creates user- and assistant-origin branches from in-memory chats and verifies a distinct child, copied history only through the source message, inherited intended settings/context, and unchanged source content after success/failure.

### Tests for User Story 2

- [X] T016 [P] [US2] Add in-memory success-path tests in `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` for child ancestry, exact ordered history cutoff, settings/project/persona copying, and source-chat/source-message immutability.
- [ ] T017 [P] [US2] Add in-memory error-path tests in `WardenTests/Utilities/ChatBranchingManagerTests.swift` for deleted/mismatched branch source, unavailable service/configuration, and failed save rollback without provider credentials or secret-bearing errors.

### Implementation for User Story 2

- [X] T018 [US2] Add a narrow injectable navigation seam in `Warden/Utilities/ChatBranchingManager.swift` for `WardenTests/Persistence/ChatHistoryRecoveryTests.swift`, preserving the existing `APIServiceFactory`, cancellable generation path, and production notification default.
- [X] T019 [US2] Add explicit accessible progress, retry, dismissal, and error semantics in `Warden/UI/Chat/Components/BranchPopover.swift`; preserve model selection and avoid exposing private source content in error text.
- [ ] T020 [US2] Verify `Warden/UI/Chat/BubbleView/ChatBubbleView.swift` keeps the original chat selection unchanged until a successful branch callback, then run `WardenTests/Utilities/ChatBranchingManagerTests.swift` and the manual branch workflow in `specs/009-chat-organization-sharing/quickstart.md`.

**Checkpoint**: Branching is independently safe: it creates an alternate conversation without damaging source history or provider configuration.

---

## Phase 5: User Story 3 — Export or share a conversation (Priority: P3)

**Goal**: Make copy/save/share format output complete, chronological, user-controlled, safe to write, and resilient to cancellation/failure.

**Independent Test**: `WardenTests/Utilities/ChatSharingServiceTests.swift` verifies Markdown, plain text, and JSON include seeded metadata, system instruction, chronological messages, and no credential material; file-name/output failure paths leave Core Data unchanged. Manual verification uses native clipboard, save panel, and share picker according to `specs/009-chat-organization-sharing/quickstart.md`.

### Tests for User Story 3

- [X] T021 [P] [US3] Add formatter tests in `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` for full metadata, optional system instruction, chronological message ordering, empty conversations, missing persona/service, and all `ChatExportFormat` cases.
- [X] T022 [P] [US3] Add safe-output tests in `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` for sanitized suggested filenames, unique temporary files, write failure, and no mutation of `ChatEntity`/`MessageEntity` persistence; save-panel cancellation remains a manual native-AppKit check.
- [X] T023 [P] [US3] Add clipboard/share action contract tests in `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` through a pure/injectable boundary that avoids invoking `NSSharingServicePicker` during XCTest.

### Implementation for User Story 3

- [X] T024 [US3] Implement complete, chronological, secret-excluding Markdown/plain-text/JSON formatting plus safe filename generation in `Warden/Utilities/ChatSharingService.swift` using the existing `ChatExportFormat` cases.
- [X] T025 [US3] Replace silent temporary-file write handling in `Warden/Utilities/ChatSharingService.swift` with unique safe output creation, user-safe error propagation, non-sensitive `WardenLog` diagnostics, and transient-file cleanup where AppKit lifecycle permits.
- [X] T026 [US3] Preserve native `NSSavePanel`, pasteboard, and `NSSharingServicePicker` user control while wiring format-specific labels, accessibility labels/hints, and safe failure feedback in `Warden/UI/Components/ChatShareMenu.swift`.
- [ ] T027 [US3] Run `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` and manually test copy, all save formats, save cancellation, share picker, and a write-failure path using `specs/009-chat-organization-sharing/quickstart.md`.

**Checkpoint**: Each output is complete and private by default; only an explicit user action copies, saves, or shares it.

---

## Phase 6: Polish and Cross-Cutting Verification

**Purpose**: Confirm compatibility, privacy, native accessibility, and actual project-wide verification.

- [X] T028 [P] Inspect changed calls in `Warden/Utilities/ChatSharingService.swift`, `Warden/Utilities/ChatBranchingManager.swift`, and `Warden/UI/ChatList/ChatListView.swift` for `WardenLog` privacy annotations; confirm no Keychain secret, key/header, or private-body diagnostic was introduced.
- [ ] T029 [P] Exercise keyboard navigation and VoiceOver labels for `Warden/UI/ChatList/ChatListView.swift`, `Warden/UI/Chat/Components/BranchPopover.swift`, and `Warden/UI/Components/ChatShareMenu.swift`; document actual results in `specs/009-chat-organization-sharing/quickstart.md`.
- [X] T030 Run feature-focused XCTest for `WardenTests/Persistence/ChatHistoryRecoveryTests.swift`, `ChatBranchingManagerTests`, and `ChatSharingServiceTests` using `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' test` with `-only-testing` filters.
- [X] T031 Run `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build` after all feature changes and record the actual outcome in `specs/009-chat-organization-sharing/quickstart.md`.
- [X] T032 Run `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'` and record actual outcome or an environment blocker in `specs/009-chat-organization-sharing/quickstart.md`.
- [X] T033 Review `git diff --check` and `git status --short` in `/Volumes/WDBlack4TB/Code/WardenApp` to ensure no API keys, private user data, DerivedData, build products, or unrelated files are included.
- [X] T034 Update feature evidence in `specs/009-chat-organization-sharing/plan.md`, `specs/009-chat-organization-sharing/quickstart.md`, and `AGENTS.md` only where implementation changes the documented behavior or active plan reference.

## Dependencies and Execution Order

1. **Phase 1** establishes the baseline and test environment.
2. **Phase 2** confirms no schema migration and creates shared fixture/export seams.
3. **US1 (P1)** delivers an independently useful local organization outcome and can proceed after Phase 2.
4. **US2 (P2)** depends on the shared fixture path from Phase 2 but not on US1 implementation; do not overlap edits to shared fixture files.
5. **US3 (P3)** depends on the export seam from Phase 2 and does not alter provider or Core Data contracts.
6. **Final phase** follows all selected user stories.

## Parallel Opportunities

- T004 can run independently from T002/T003 after initial target inspection.
- T006 and T007 can proceed in parallel once fixture expectations are known.
- T009–T011 are separate test files and can proceed in parallel after T005.
- T016 and T017 can proceed in parallel after T005.
- T021–T023 can proceed in parallel after T008.
- T028 and T029 can proceed in parallel after story implementations complete.

## Implementation Strategy

1. **MVP**: Complete Phase 1–2 and US1 to validate local organization without new persistence or network behavior.
2. **Increment 2**: Complete US2 with branch-manager regression coverage before touching provider behavior.
3. **Increment 3**: Complete US3 with privacy-safe export reliability and native UI feedback.
4. **Finish**: Complete the full build/test/manual/privacy gates, then update the Time Machine queue for the implementation phase.
