# Tasks: Personas and Model Selection

**Input**: Design documents from `specs/007-personas-model-selection/`
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/personas-model-selection-ui-contract.md`, and `quickstart.md`
**Verification**: XCTest/XCUITest plus the Warden macOS build; tests use in-memory/local fixtures and no paid provider credentials

## Format: `[ID] [P?] [Story] Description`

- **[P]** means the task can proceed in parallel only after its stated prerequisite is fixed.
- **[US#]** maps implementation and verification to a user story from `spec.md`.
- Every task names an exact project-relative path.
- Test tasks precede the behavior they verify. Do not mark a task complete until its stated evidence is real.

## Phase 1: Baseline and Setup

**Purpose**: Establish the compiled source of truth and a reproducible test seam before implementation.

- [X] T001 Record the active branch, feature pointer, target membership, and affected paths in `specs/007-personas-model-selection/implementation-log.md`.
- [X] T002 Inspect and preserve the canonical compiled selector in `Warden/UI/Chat/BottomContainer/PersonaSelectorView.swift`; record the unreferenced duplicate decision for `Warden/UI/Chat/ChatParameters/PersonaSelectorView.swift` in `specs/007-personas-model-selection/implementation-log.md`.
- [X] T003 Run the current baseline build for `Warden.xcodeproj` using scheme `Warden` and record the real result in `specs/007-personas-model-selection/implementation-log.md`.
- [ ] T004 [P] Define credential-free service/model/persona fixtures and in-memory persistence support in `WardenTests/PersonasModelSelection/PersonasModelSelectionTestSupport.swift`.

**Checkpoint**: The compiled persona selector and test target strategy are known; no behavior has been changed.

---

## Phase 2: Foundational Policy, Safety, and Regression Tests

**Purpose**: Lock down lossless identity, availability, persistence, and chat-update semantics before UI actions call them.

- [X] T005 Add deterministic identity and availability tests in `WardenTests/Utilities/MessageParserTests.swift` for provider/model collisions, separators in model IDs, and configured-service/visibility absence.
- [ ] T006 [P] Add failing in-memory Core Data tests in `WardenTests/PersonasModelSelection/ChatModelSelectionCoordinatorTests.swift` for atomic service/model updates, failed save behavior, and a chat-scoped `RecreateMessageManager` notification.
- [ ] T007 [P] Add failing local-preference recovery tests in `WardenTests/PersonasModelSelection/FavoriteModelsManagerTests.swift` for malformed favorite values and provider/model favorite persistence without secrets.
- [X] T008 Add a lossless provider/model identity and availability policy in `Warden/Utilities/FavoriteModelsManager.swift` without delimiter-splitting opaque model IDs.
- [X] T009 Implement a validated atomic chat provider/model mutation coordinator in `Warden/Utilities/FavoriteModelsManager.swift`; it saves before notifying and retains the current pair on invalid service/model or save failure.
- [X] T010 Adapt local favorite persistence/recovery to use the canonical identity in `Warden/Utilities/FavoriteModelsManager.swift` without storing credentials, endpoints, prompts, or conversation content.
- [X] T011 Integrate existing `ModelCacheManager` and `SelectedModelsManager` visibility semantics through the policy in `Warden/Utilities/FavoriteModelsManager.swift` without changing provider transport or triggering render-time network calls.
- [X] T012 Run focused `PersonasModelSelectionRegressionTests` in `WardenTests/Utilities/MessageParserTests.swift` through scheme `Warden` and record the real result in `specs/007-personas-model-selection/implementation-log.md`.

**Checkpoint**: Validated selection policy is shared, deterministic, secret-safe, and covered below the UI.

---

## Phase 3: User Story 1 — Create and Apply a Persona (Priority: P1) 🎯 MVP

**Goal**: Users manage reusable personas and select one for a chat without silently changing its active service/model; they may explicitly apply a valid persona default service.

**Independent Test**: An in-memory Core Data test proves selection/clear preserves the active pair and the explicit default-service path changes only a valid available pair; manual native UI interaction confirms the separate control.

### Tests for User Story 1

- [ ] T013 [P] [US1] Add persona selection/default-service regression tests in `WardenTests/PersonasModelSelection/PersonaSelectionTests.swift` covering select, clear, deleted/default-unavailable service, and subsequent behavior settings.
- [ ] T014 [P] [US1] Add deterministic persona CRUD/order/persistence regression tests in `WardenTests/PersonasModelSelection/PersonaPersistenceTests.swift` using `WardenTests/PersonasModelSelection/PersonasModelSelectionTestSupport.swift`.

### Implementation for User Story 1

- [ ] T015 [US1] Update persona editor validation and accessible primary controls in `Warden/UI/Preferences/TabAIPersonasView.swift` while preserving existing local persistence/order and no-secret behavior.
- [X] T016 [US1] Update `Warden/UI/Chat/BottomContainer/PersonaSelectorView.swift` so selection/clear changes only `chat.persona`, persists safely, and requests chat-manager recreation only after a successful save.
- [X] T017 [US1] Add the distinct validated default-service action and recoverable unavailable/save-error state in `Warden/UI/Chat/BottomContainer/PersonaSelectorView.swift`, delegating service/model updates to the shared coordinator in `Warden/Utilities/FavoriteModelsManager.swift`.
- [X] T018 [US1] Decide that no change is needed to the noncompiled duplicate types in `Warden/UI/Chat/ChatParameters/PersonaSelectorView.swift`; do not add duplicate target membership.
- [ ] T019 [US1] Run focused persona tests under `WardenTests/PersonasModelSelection/` and complete the persona steps in `specs/007-personas-model-selection/quickstart.md`, recording real results in `specs/007-personas-model-selection/implementation-log.md`.

**Checkpoint**: Persona CRUD and selection are independently usable; changing provider/model is visible, optional, validated, and chat-scoped.

---

## Phase 4: User Story 2 — Find and Select an Available Model (Priority: P1)

**Goal**: Users find a configured valid model by provider/model search and select it through one atomic, chat-scoped path.

**Independent Test**: Fixture models from two providers—including matching model names—filter/search deterministically, expose only actionable pairs, and update only the selected chat after a valid choice.

### Tests for User Story 2

- [ ] T020 [P] [US2] Add selector view-model tests in `WardenTests/PersonasModelSelection/ModelSelectorViewModelTests.swift` for search, provider grouping, selected state, duplicate model IDs, and 500-model fixture responsiveness.
- [ ] T021 [P] [US2] Add an XCUITest in `WardenUITests/PersonasModelSelectionUITests.swift` only if `WardenUITests/PersonasModelSelectionLaunchFixture.swift` can seed local persona/service/model data without credentials; otherwise document the stable manual path in `specs/007-personas-model-selection/implementation-log.md`.

### Implementation for User Story 2

- [X] T022 [US2] Refactor model item/section identity and filtered availability in `Warden/UI/Components/ModelSelectorDropdown.swift` to use the shared policy in `Warden/Utilities/FavoriteModelsManager.swift` and stable provider/model identity.
- [X] T023 [US2] Route valid selector changes in `Warden/UI/Components/ModelSelectorDropdown.swift` through the shared coordinator in `Warden/Utilities/FavoriteModelsManager.swift`; retain the existing chat-scoped recreation contract and show non-sensitive recoverable failures.
- [X] T024 [US2] Add accessible search, selected, loading, empty, unavailable, and failure presentation in `Warden/UI/Components/ModelSelectorDropdown.swift` using native SwiftUI `Button` controls and keyboard-operable labels.
- [ ] T025 [US2] Run model selector focused tests and the model-selection manual steps in `specs/007-personas-model-selection/quickstart.md`, recording results in `specs/007-personas-model-selection/implementation-log.md`.

**Checkpoint**: Model selection is independently usable, provider/model identity is stable, and unavailable entries never become actionable.

---

## Phase 5: User Story 3 — Favorite and Inspect Models (Priority: P2)

**Goal**: Users persist non-secret provider/model favorites and inspect optional metadata without losing selection safety or exposing sensitive configuration.

**Independent Test**: Favorites persist/recover locally, same-named models from different providers remain distinct, and missing/stale metadata renders a reduced state without a network request.

### Tests for User Story 3

- [ ] T026 [P] [US3] Add favorite quick-access identity/eligibility tests in `WardenTests/PersonasModelSelection/FavoriteQuickAccessTests.swift` using configured and unavailable provider/model fixtures.
- [ ] T027 [P] [US3] Add optional metadata display/policy tests in `WardenTests/PersonasModelSelection/ModelMetadataPresentationTests.swift` for missing, stale, incomplete, and capability-bearing fixture metadata.

### Implementation for User Story 3

- [X] T028 [US3] Update provider/model identity, configured-pair filtering, and shared mutation use in `Warden/UI/Components/FavoriteQuickAccessBar.swift` so matching model IDs across providers cannot collide.
- [X] T029 [US3] Verify existing `Warden/UI/Components/ModelInfoTooltip.swift` already displays optional capability/context/pricing information without a render-time fetch or sensitive configuration.
- [ ] T030 [US3] Run favorite/metadata focused tests and the favorite/metadata manual steps in `specs/007-personas-model-selection/quickstart.md`, recording results in `specs/007-personas-model-selection/implementation-log.md`.

**Checkpoint**: Favorites and inspection enhance selection without bypassing configured availability or privacy constraints.

---

## Phase N: Cross-Cutting Verification and Polish

- [X] T031 [P] Review changed diagnostics and persistence in `Warden/Utilities/FavoriteModelsManager.swift` for Keychain-only secrets and safe `WardenLog` output.
- [X] T032 [P] Review macOS keyboard navigation, accessibility labels/values/hints, selected/empty/unavailable states, and duplicate type membership across `Warden/UI/Chat/BottomContainer/PersonaSelectorView.swift`, `Warden/UI/Components/ModelSelectorDropdown.swift`, and `Warden/UI/Components/FavoriteQuickAccessBar.swift`.
- [X] T033 Run the feature-focused XCTest added in `WardenTests/Utilities/MessageParserTests.swift`, then record exact commands/outcomes in `specs/007-personas-model-selection/implementation-log.md`.
- [X] T034 Run the macOS arm64 build for `Warden.xcodeproj` scheme `Warden`, inspect its `.xcresult`, and record the real result in `specs/007-personas-model-selection/implementation-log.md`.
- [X] T035 Run the complete macOS test suite for `Warden.xcodeproj` scheme `Warden`, inspect its `.xcresult`, and record the real result in `specs/007-personas-model-selection/implementation-log.md`.
- [ ] T036 Execute the full regression/manual privacy workflow in `specs/007-personas-model-selection/quickstart.md` and record actual observations in `specs/007-personas-model-selection/implementation-log.md`.
- [X] T037 Verify the feature diff and `AGENTS.md` contain no API keys, tokens, prompts, private chat content, build products, DerivedData, or unintended project-file changes; retain `AGENTS.md` active-plan reference in `AGENTS.md`.

## Dependencies and Execution Order

1. Phase 1 establishes the active compiled source and credential-free fixture strategy.
2. Phase 2 blocks all user stories because identity, availability, persistence, and atomic chat mutation are shared.
3. User Story 1 delivers persona behavior and can be validated independently after Phase 2.
4. User Story 2 depends on the shared coordinator/policy but not on User Story 1 UI.
5. User Story 3 depends on canonical identity/policy and can follow User Story 2 or proceed in parallel where files do not overlap.
6. Final verification follows all selected stories.

## Parallel Opportunities

- T004 can proceed alongside baseline documentation once target membership is confirmed.
- T005, T006, and T007 are parallel test-file work after the fixture seam exists.
- T013 and T014 can run in parallel after the foundational policies are fixed.
- T020 and T021 can run in parallel, but the UI test must not be claimed when deterministic launch seeding is unavailable.
- T026 and T027 can run in parallel after provider/model identity is stable.
- T031 and T032 can run in parallel after implementation; T033–T037 remain sequential evidence gates.

## Implementation Strategy

1. **MVP**: Complete phases 1–3 to make persona selection safe and explicit about service/model changes.
2. **Increment 2**: Complete phase 4 to make configured model discovery/selection deterministic and accessible.
3. **Increment 3**: Complete phase 5 to make favorites/metadata safe and useful.
4. **Release gate**: Do not mark the feature complete until phases 6 evidence is captured from actual focused tests, full build/test, `.xcresult`, and manual privacy verification.
