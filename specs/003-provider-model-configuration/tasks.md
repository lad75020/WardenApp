# Tasks: Provider and Model Configuration

**Input**: Design documents from `/specs/003-provider-model-configuration/`
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/provider-configuration-contract.md`, and `quickstart.md`
**Verification**: XCTest/XCUITest plus the Warden macOS build; tests use deterministic local stubs and synthetic runtime credentials only.

## Format: `[ID] [P?] [Story] Description`

- **[P]** means the task can run in parallel because it touches different files and has no unresolved dependency.
- **[US#]** maps implementation and verification to one user story.
- Every task names exact WardenApp file paths.
- Test tasks precede the implementation they verify and must fail for the expected reason before implementation.

## Phase 1: Baseline and Setup

**Purpose**: Establish real baseline evidence and a deterministic provider-configuration test seam.

- [ ] T001 Record provider configuration behavior and current test-target membership in `specs/003-provider-model-configuration/implementation-log.md`.
- [ ] T002 Run the narrowest existing provider-related test discovery/build command for `Warden.xcodeproj` and record actual results in `specs/003-provider-model-configuration/implementation-log.md`.
- [ ] T003 Inspect secret/transport/default lifecycle paths in `Warden/Utilities/TokenManager.swift`, `Warden/Utilities/APIServiceManager.swift`, and `Warden/UI/Preferences/TabAPIServicesView.swift` against `specs/003-provider-model-configuration/contracts/provider-configuration-contract.md`.
- [ ] T004 [P] Add deterministic synthetic provider configuration test support in `WardenTests/APIServiceConfigurationTests.swift` without using real credentials or network requests.

**Checkpoint**: Existing behavior and test-target constraints are captured; all fixtures are secret-free.

---

## Phase 2: Foundational Contracts and Regression Tests

**Purpose**: Lock down shared lifecycle, transport, privacy, and error behavior before dependent UI work.

- [ ] T005 Add failing endpoint/credential transport and redacted-error regression tests in `WardenTests/APIServiceConfigurationTests.swift`.
- [ ] T006 [P] Add failing transactional create/edit/duplicate/delete/default-clearing regression tests in `WardenTests/APIServiceConfigurationTests.swift`.
- [ ] T007 [P] Add failing stale/cancelled model-refresh and selected-model-retention tests in `WardenTests/APIServiceDetailViewModelTests.swift`.
- [ ] T008 Define focused user-safe lifecycle result/error types and endpoint-validation helpers in `Warden/Utilities/APIServiceManager.swift`.
- [ ] T009 Add dependency-injection seams required for deterministic Keychain and factory-client tests in `Warden/Utilities/TokenManager.swift` and `Warden/Utilities/APIServiceFactory.swift` without weakening production storage or transport behavior.
- [ ] T010 Verify no changed path stores/logs a token, authorization header, raw provider body, or private prompt by inspecting `Warden/Utilities/TokenManager.swift`, `Warden/Utilities/APIServiceManager.swift`, and `Warden/UI/Preferences/TabAPIServices/`.

**Checkpoint**: Shared tests fail for intended gaps; security and lifecycle contracts are independently testable.

---

## Phase 3: User Story 1 — Configure a Usable AI Service (Priority: P1) 🎯 MVP

**Goal**: Users can securely create and edit hosted or self-hosted service configurations without credential persistence or unsafe transport.

**Independent Test**: `WardenTests/APIServiceConfigurationTests.swift` creates/edits a hosted synthetic-credential service and a tokenless loopback service, then verifies persisted metadata and Keychain-only credential handling without live requests.

### Tests for User Story 1

- [ ] T011 [US1] Complete create/edit validation and Keychain-only lifecycle tests in `WardenTests/APIServiceConfigurationTests.swift`.
- [ ] T012 [US1] Add UI-state tests for invalid endpoint, remote HTTP with credential, and tokenless local endpoint feedback in `WardenTests/APIServiceDetailViewModelTests.swift`.

### Implementation for User Story 1

- [ ] T013 [US1] Implement validated create/edit metadata and credential transaction behavior in `Warden/Utilities/APIServiceManager.swift`.
- [ ] T014 [US1] Implement safe credential read/write error handling and preserve legacy migration in `Warden/Utilities/TokenManager.swift`.
- [ ] T015 [US1] Refactor draft validation, save outcome handling, and current-service identity handling in `Warden/UI/Preferences/TabAPIServices/APIServiceDetailViewModel.swift`.
- [ ] T016 [US1] Wire secure credential input, non-color validation/status text, and save state in `Warden/UI/Preferences/TabAPIServices/APIServiceDetailView.swift`.
- [ ] T017 [US1] Run the focused US1 XCTest classes from `WardenTests/APIServiceConfigurationTests.swift` and `WardenTests/APIServiceDetailViewModelTests.swift` and record actual output in `specs/003-provider-model-configuration/implementation-log.md`.

**Checkpoint**: Hosted HTTPS and self-hosted loopback configuration save/edit independently, and credentials are never persisted outside Keychain.

---

## Phase 4: User Story 2 — Validate and Select Models (Priority: P2)

**Goal**: Users can explicitly refresh/select models and test a configured service with safe, stale-proof feedback.

**Independent Test**: Deterministic provider test doubles in `WardenTests/APIServiceDetailViewModelTests.swift` cover success, unauthorized, unreachable, timeout, malformed response, cancellation, and input changes during a refresh/test without altering the saved model.

### Tests for User Story 2

- [ ] T018 [US2] Complete deterministic model-discovery, connection-test, error-category/redaction, and stale-completion tests in `WardenTests/APIServiceDetailViewModelTests.swift`.
- [ ] T019 [US2] Add factory/session-policy regression coverage for supported provider and local-service creation in `WardenTests/APIServiceFactoryTests.swift`.

### Implementation for User Story 2

- [ ] T020 [US2] Preserve factory mapping and add only needed testable client construction seams in `Warden/Utilities/APIServiceFactory.swift`.
- [ ] T021 [US2] Implement explicit user-initiated, validated, cancellable, generation-checked model discovery and connection test orchestration in `Warden/UI/Preferences/TabAPIServices/APIServiceDetailViewModel.swift`.
- [ ] T022 [US2] Replace raw/unscoped connection-test alert behavior with view-model-owned accessible pending/success/failure presentation in `Warden/UI/Preferences/TabAPIServices/ButtonTestApiTokenAndModel.swift` and `Warden/UI/Preferences/TabAPIServices/APIServiceDetailView.swift`.
- [ ] T023 [US2] Preserve selected/custom model state, disable incompatible image streaming, and keep local MLX/CoreML permission flows explicit in `Warden/UI/Preferences/TabAPIServices/APIServiceDetailView.swift`.
- [ ] T024 [US2] Run focused US2 XCTest classes from `WardenTests/APIServiceDetailViewModelTests.swift` and `WardenTests/APIServiceFactoryTests.swift`, then re-run US1 regressions and record actual results in `specs/003-provider-model-configuration/implementation-log.md`.

**Checkpoint**: Model/test actions are explicit, bounded, safe, and do not mutate persisted choices without save.

---

## Phase 5: User Story 3 — Manage Service Lifecycle and Default (Priority: P3)

**Goal**: Users can safely duplicate/delete services and explicitly control a default without dangling credentials or silent provider switching.

**Independent Test**: `WardenTests/APIServiceConfigurationTests.swift` creates two services, copies one, sets it default, deletes the default, and verifies unique credential identity, removed credential, and a cleared default reference.

### Tests for User Story 3

- [ ] T025 [US3] Complete duplicate/delete/default-clearing and failed-persistence recovery tests in `WardenTests/APIServiceConfigurationTests.swift`.
- [ ] T026 [US3] Add deterministic list-selection/default-badge/deletion outcome coverage in `WardenTests/TabAPIServicesViewModelTests.swift` or the nearest existing Settings test file.

### Implementation for User Story 3

- [ ] T027 [US3] Implement transactional duplicate/delete/default-clearing operations in `Warden/Utilities/APIServiceManager.swift`.
- [ ] T028 [US3] Delegate add/duplicate/default/list selection and successful deletion refresh behavior to the lifecycle boundary in `Warden/UI/Preferences/TabAPIServicesView.swift`.
- [ ] T029 [US3] Wire deletion confirmation and user-safe success/failure outcomes without prematurely dismissing/reselecting invalid services in `Warden/UI/Preferences/TabAPIServices/APIServiceDetailView.swift` and `Warden/UI/Preferences/TabAPIServices/APIServiceDetailViewModel.swift`.
- [ ] T030 [US3] Run focused US3 XCTest classes from `WardenTests/APIServiceConfigurationTests.swift` and `WardenTests/TabAPIServicesViewModelTests.swift`, then re-run US1/US2 regressions and record actual results in `specs/003-provider-model-configuration/implementation-log.md`.

**Checkpoint**: Duplicate has an independent identity/credential; successful default deletion clears default and matching Keychain credential without automatic provider fallback.

---

## Phase 6: Polish & Cross-Cutting Verification

- [ ] T031 [P] Review changed Swift source in `Warden/Utilities/` and `Warden/UI/Preferences/` for Keychain-only secrets, TLS/loopback transport policy, scoped local-model access, and privacy-safe `WardenLog` usage.
- [ ] T032 [P] Verify keyboard focus, VoiceOver labels/values/hints, delete confirmation, loading/error/success text, and non-color-only status in `Warden/UI/Preferences/TabAPIServicesView.swift` and `Warden/UI/Preferences/TabAPIServices/APIServiceDetailView.swift`.
- [ ] T033 Execute the manual native Settings smoke-test cases in `specs/003-provider-model-configuration/quickstart.md` and record actual pass/fail evidence in `specs/003-provider-model-configuration/implementation-log.md`.
- [ ] T034 Run the canonical build for `Warden.xcodeproj` with the Warden macOS scheme and record actual output in `specs/003-provider-model-configuration/implementation-log.md`.
- [ ] T035 Run the canonical full Warden test suite from `Warden.xcodeproj` and record actual output or environment blocker in `specs/003-provider-model-configuration/implementation-log.md`.
- [ ] T036 Use Hermes-configured XcodeMCP to inspect build/test issues for `Warden.xcodeproj` and record exact results in `specs/003-provider-model-configuration/implementation-log.md`.
- [ ] T037 Verify `git diff --check` and inspect changed paths against `specs/003-provider-model-configuration/contracts/provider-configuration-contract.md` before marking implementation tasks complete.

## Dependencies and Execution Order

1. Phase 1 captures baseline and deterministic test support.
2. Phase 2 establishes blocking lifecycle/transport/privacy contracts.
3. **US1 (P1)** is the MVP and must complete before safe model/test actions.
4. **US2 (P2)** depends on the shared validation/error contract and should preserve US1 behavior.
5. **US3 (P3)** depends on the lifecycle boundary from US1 and can proceed after it; it must not regress US2.
6. Final verification follows all stories and is required before queue completion/commit/push gate.

## Parallel Opportunities

- T004 and the independent foundational test definitions T005–T007 can proceed in parallel once the test target shape is confirmed.
- T011/T012, T018/T019, and T025/T026 are parallel only when they are implemented in separate test files and no common test helper is being edited.
- T031 and T032 are independent final reviews; do not run XcodeMCP and CLI test/build concurrently against the same project.

## Implementation Strategy

1. Deliver the P1 secure save/edit lifecycle and its tests first.
2. Add P2 model discovery/testing safeguards after the persistence/transport contract is stable.
3. Add P3 duplicate/delete/default cleanup with clear-default policy.
4. Finish with native macOS accessibility/manual QA, full build/test, security review, and XcodeMCP evidence.
