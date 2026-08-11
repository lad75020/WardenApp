---
description: "Actionable task list for safe local persistence and unavailable-chat recovery"
---

# Tasks: Persistence and Chat History

**Input**: Design documents in `specs/002-persistence-chat-history/`  
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/persistence-recovery-ui-contract.md`, and `quickstart.md`  
**Verification**: XCTest/XCUITest plus the Warden macOS build; tests use in-memory Core Data fixtures and no real provider credentials.

## Format: `[ID] [P?] [Story] Description`

- `[P]` tasks may be performed in parallel only after all shared prerequisites are stable and only when their files do not overlap.
- `[US#]` maps a task to its user story in `spec.md`.
- Every task names an exact WardenApp path.

## Phase 1: Baseline and Setup

**Purpose**: Establish current behavior and isolated test seams without touching user data.

- [x] T001 Record the current destructive invalid-chat behavior and affected paths in `specs/002-persistence-chat-history/implementation-log.md`.
- [x] T002 Run the existing macOS build with `set -o pipefail` and record its real result in `specs/002-persistence-chat-history/implementation-log.md`.
- [x] T003 [P] Inspect `Warden/WardenApp.swift` and `WardenTests/AppShell/OnboardingFlowTests.swift` to document the in-memory Core Data and UI-test launch-fixture seams in `specs/002-persistence-chat-history/implementation-log.md`.
- [x] T004 [P] Review `Warden/Store/wardenDataModel.xcdatamodeld/wardenDataModel.xcdatamodel/contents` against `specs/002-persistence-chat-history/data-model.md` and record that no schema change is needed in `specs/002-persistence-chat-history/implementation-log.md`.

**Checkpoint**: Baseline evidence, Core Data scope, and fixture seams are recorded without using a personal store.

---

## Phase 2: Foundational Recovery Contract and Test Harness

**Purpose**: Lock down the non-destructive persistence contract before changing store/UI behavior.

- [x] T005 Create deterministic in-memory fixture helpers for chats, messages, projects, personas, and valid/invalid services in `WardenTests/Persistence/ChatHistoryRecoveryTests.swift`.
- [x] T006 [P] Create isolated unavailable-chat UI-test fixture launch support in `WardenUITests/Persistence/PersistenceRecoveryTestSupport.swift`.
- [x] T007 Add `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` and `WardenUITests/Persistence/PersistenceRecoveryTestSupport.swift` to their correct targets in `Warden.xcodeproj/project.pbxproj`.
- [ ] T008 Run the new retained-unavailable-chat regression in `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` and record its expected failure against `Warden/Store/ChatStore.swift` in `specs/002-persistence-chat-history/implementation-log.md`.
- [x] T009 [P] Add secure transformer/message compatibility regression cases for retained history in `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` using `Warden/Models/RequestMessagesTransformer.swift` and `Warden/Models/MessageContent.swift`.
- [x] T010 [P] Add a static privacy regression check in `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` covering no token, authorization header, full message body, telemetry, or raw diagnostics in new recovery contracts.

**Checkpoint**: New tests compile, fail only for the missing behavior, and fixture data contains no secrets or live network dependency.

---

## Phase 3: User Story 1 — Preserve Conversation History (Priority: P1) 🎯 MVP

**Goal**: Restore valid local chats with their ordered messages, projects, personas, and valid service association without duplicates or stale selection damage.

**Independent Test**: `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` creates representative in-memory records, reloads them through `Warden/Store/ChatStore.swift`, and verifies relationship/order integrity, an empty-store result, idempotent repeated load/import, and safe stale selection clearing.

### Tests for User Story 1

- [x] T011 [US1] Add valid-history, ordered-message, project/persona, empty-history, repeated-load, and stale-selection regression cases in `WardenTests/Persistence/ChatHistoryRecoveryTests.swift`.
- [x] T012 [US1] Add an app-relaunch fixture scenario for valid persisted history in `WardenUITests/Persistence/PersistenceRecoveryUITests.swift`.

### Implementation for User Story 1

- [x] T013 [US1] Refactor `Warden/Store/ChatStore.swift` restoration fetches to retain all persisted chat entities and return deterministic backups without automated cleanup deletion.
- [x] T014 [US1] Add a focused availability classification API and a valid-service candidate query in `Warden/Store/ChatStore.swift` using the existing `APIServiceManager` validation path.
- [x] T015 [US1] Update stale selected-chat restoration in `Warden/UI/ContentView.swift` so a missing selection is cleared without deleting remaining history.
- [x] T016 [US1] Run the focused US1 unit/UI cases for `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` and `WardenUITests/Persistence/PersistenceRecoveryUITests.swift`, recording actual outcomes in `specs/002-persistence-chat-history/implementation-log.md`.

**Checkpoint**: Valid local history is independently restored and ordered, while empty/missing selection states are safe and non-destructive.

---

## Phase 4: User Story 2 — Safely Evolve Existing Local Data (Priority: P2)

**Goal**: Preserve compatible legacy data and offer non-sensitive recovery behavior for malformed, interrupted, or unavailable local persistence.

**Independent Test**: `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` exercises duplicate legacy IDs, missing/invalid relationships, interrupted JSON import, malformed transform data, and persistent-store fallback behavior without overwriting valid in-memory fixture records.

### Tests for User Story 2

- [x] T017 [US2] Add JSON-import idempotency, duplicate-ID, missing-service, and failed-save recovery cases in `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` for `Warden/Store/ChatStore.swift`.
- [x] T018 [P] [US2] Add existing configuration-patch idempotency and Keychain-boundary cases in `WardenTests/Persistence/DatabasePatcherMigrationTests.swift` for `Warden/Utilities/DatabasePatcher.swift`.
- [x] T019 [P] [US2] Add malformed `requestMessages` transform and incomplete attachment-reference recovery cases in `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` for `Warden/Models/RequestMessagesTransformer.swift` and `Warden/Models/MessageContent.swift`.

### Implementation for User Story 2

- [x] T020 [US2] Preserve source data and completion-flag idempotency in `Warden/Store/ChatStore.swift` while importing legacy JSON records that cannot resolve a service.
- [x] T021 [US2] Harden non-sensitive migration/recovery diagnostics in `Warden/Store/ChatStore.swift` and `Warden/Utilities/DatabasePatcher.swift` without logging credentials, chat content, raw Core Data payloads, or storage paths.
- [x] T022 [US2] Confirm `Warden/WardenApp.swift` maintains non-destructive persistent-store failure fallback and actionable, non-sensitive feedback without changing valid-store launch behavior.
- [x] T023 [US2] Run focused US2 migration/recovery tests in `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` and `WardenTests/Persistence/DatabasePatcherMigrationTests.swift`, recording actual outcomes in `specs/002-persistence-chat-history/implementation-log.md`.

**Checkpoint**: Compatible and retryable local recovery is idempotent, preserves valid records, and does not expose private data.

---

## Phase 5: User Story 3 — Retain Configuration Without Exposing Secrets (Priority: P3)

**Goal**: Retain chats with missing/invalid services as unavailable, then allow only explicit repair to an existing valid service or confirmed deletion.

**Independent Test**: A seeded unavailable chat remains in history after load; a valid selected service repairs it without message/context changes; the no-candidate case opens existing settings and leaves it unavailable; deletion requires confirmation and removes only the selected chat.

### Tests for User Story 3

- [x] T024 [US3] Add missing-service and invalid-service retention, repair-candidate filtering, remap-preservation, no-candidate, and explicit-delete cases in `WardenTests/Persistence/ChatHistoryRecoveryTests.swift`.
- [x] T025 [US3] Add unavailable-state, disabled-send, repair selector, settings-route, confirmed-delete, accessibility-label, and keyboard-focus cases in `WardenUITests/Persistence/PersistenceRecoveryUITests.swift`.

### Implementation for User Story 3

- [x] T026 [US3] Implement guarded explicit service remapping and explicit unavailable-chat deletion in `Warden/Store/ChatStore.swift`, preserving chat/message/project/persona/request-message identity on repair.
- [x] T027 [US3] Create `Warden/UI/Chat/UnavailableChatRecoveryView.swift` to render non-colour unavailable status, valid-service repair selection, existing-settings route, confirmed delete, and accessible controls.
- [x] T028 [US3] Integrate unavailable state and disabled chat sending in `Warden/UI/Chat/ChatView.swift` and `Warden/UI/Chat/ChatViewModel.swift` while preserving valid-chat behavior.
- [x] T029 [US3] Add unavailable-service state communication to `Warden/UI/ChatList/ChatListRow.swift` and `Warden/UI/ChatList/MessageCell.swift` without relying on color or hover-only controls.
- [x] T030 [US3] Wire the no-valid-service action in `Warden/UI/Chat/UnavailableChatRecoveryView.swift` through `Warden/Utilities/SettingsWindowManager.swift` to the existing service settings flow.
- [x] T031 [US3] Run focused US3 unit/UI cases in `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` and `WardenUITests/Persistence/PersistenceRecoveryUITests.swift`, recording actual outcomes in `specs/002-persistence-chat-history/implementation-log.md`.

**Checkpoint**: An unavailable chat is retained and accessible; repair and delete are explicit, safe, and independently verifiable.

---

## Phase N: Cross-Cutting Verification and Polish

- [x] T032 [P] Verify `Warden/Store/wardenDataModel.xcdatamodeld/wardenDataModel.xcdatamodel/contents` remains schema-compatible and document any changed migration decision in `specs/002-persistence-chat-history/implementation-log.md`.
- [x] T033 [P] Review changed `Warden/Store/ChatStore.swift`, `Warden/UI/Chat/UnavailableChatRecoveryView.swift`, and `Warden/Utilities/DatabasePatcher.swift` for API keys, authorization headers, private prompts, full chat content, telemetry, local paths, and build artifacts; record findings in `specs/002-persistence-chat-history/implementation-log.md`.
- [ ] T034 Verify VoiceOver labels, keyboard focus/navigation, non-colour recovery status, and enlarged-text layout for `Warden/UI/Chat/UnavailableChatRecoveryView.swift`; record structured manual PASS/FAIL/NOT TESTABLE evidence in `specs/002-persistence-chat-history/implementation-log.md`.
- [x] T035 Run the macOS build for `Warden.xcodeproj/project.pbxproj` with `set -o pipefail` and record the actual output summary in `specs/002-persistence-chat-history/implementation-log.md`.
- [x] T036 Run the full Warden test scheme from `Warden.xcodeproj/project.pbxproj` with `set -o pipefail` and record actual pass/fail/blocker evidence in `specs/002-persistence-chat-history/implementation-log.md`.
- [x] T037 Run `git diff --check` for `specs/002-persistence-chat-history/tasks.md` and record clean/failed result in `specs/002-persistence-chat-history/implementation-log.md`.
- [x] T038 Update behavior/verification notes in `specs/002-persistence-chat-history/quickstart.md` and `specs/002-persistence-chat-history/implementation-log.md` with only real execution and manual QA evidence.

## Dependencies and Execution Order

1. Phase 1 baseline establishes the isolated storage and existing behavior evidence.
2. Phase 2 test harness and failing regressions block all production behavior changes.
3. US1 provides the retained-valid-history MVP and must pass before upgrade/recovery work.
4. US2 builds on the US1 preservation contract and can proceed after the shared `ChatStore` API stabilizes.
5. US3 builds on the availability classification from US1/US2 and must complete before cross-cutting verification.
6. Final verification follows all user stories; T034 requires a human tester and cannot be replaced by automated tests.

## Parallel Opportunities

- T003 and T004 can run in parallel because they only inspect/document separate app/model areas.
- T006, T009, and T010 can run in parallel after T005 starts because they use separate test files/seams.
- T018 and T019 can run in parallel after the foundational migration contract is stable.
- T032 and T033 can run in parallel after implementation because they are read-only review/documentation tasks.
- Do not parallelize edits to `Warden/Store/ChatStore.swift`, `Warden/Utilities/DatabasePatcher.swift`, `Warden.xcodeproj/project.pbxproj`, or shared XCUITest support.

## Implementation Strategy

1. **MVP**: Complete US1 so valid records restore deterministically and missing/invalid service records are retained rather than deleted.
2. **Recovery**: Complete US2 to prove idempotent/retry-safe import and non-sensitive local recovery.
3. **User control**: Complete US3 to expose clear repair/delete settings behavior with deterministic UI coverage.
4. **Finish honestly**: Complete final automated checks and the required manual accessibility evidence before marking the queue feature done.
