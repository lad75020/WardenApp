---
description: "WardenApp task list template for native macOS feature implementation"
---

# Tasks: [FEATURE NAME]

**Input**: Design documents from `/specs/[###-feature-name]/`  
**Prerequisites**: `spec.md` and `plan.md`; include `research.md`, `data-model.md`, `contracts/`, and `quickstart.md` when applicable  
**Verification**: XCTest/XCUITest plus the Warden macOS build; tests do not use real paid credentials

## Format: `[ID] [P?] [Story] Description`

- **[P]** means the task can run in parallel because it touches different files and has no unresolved dependency.
- **[US#]** maps implementation and verification to one user story.
- Every task MUST name exact WardenApp file paths.
- Test tasks precede the implementation they verify and must fail for the expected reason before implementation.

## WardenApp Paths

- App/UI: `Warden/WardenApp.swift`, `Warden/UI/`, `Warden/Configuration/`
- Models/persistence: `Warden/Models/`, `Warden/Store/`
- Services/integrations: `Warden/Utilities/`, `Warden/Utilities/APIHandlers/`, `Warden/Core/MCP/`
- Unit tests: `WardenTests/`
- UI tests: `WardenUITests/`
- Auxiliary modules: `MLXZImageSwiftCLI/`, local packages under `Packages/`

<!-- Replace all sample tasks below with tasks derived from the feature spec and plan. Delete inapplicable phases and examples. -->

## Phase 1: Baseline and Setup

**Purpose**: Establish a reproducible baseline without changing project structure unnecessarily.

- [ ] T001 Record affected targets and exact files from `plan.md`
- [ ] T002 Run the most focused existing XCTest/XCUITest command for the affected behavior
- [ ] T003 Run `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`
- [ ] T004 [P] Confirm test doubles/fixtures avoid real provider credentials and network charges

**Checkpoint**: Existing behavior and environment are understood; failures are documented rather than hidden.

---

## Phase 2: Foundational Contracts and Regression Tests

**Purpose**: Lock down shared contracts, security, data, and failure behavior before dependent implementation.

- [ ] T005 Add a failing regression/unit test in `WardenTests/[FeaturePath]/[Feature]Tests.swift`
- [ ] T006 [P] Add deterministic provider/stream/file fixtures under the applicable `WardenTests/` path
- [ ] T007 [P] Define or update shared models in `Warden/Models/[Type].swift` when required
- [ ] T008 Define `APIProtocol`, MCP, or service contract changes in the existing owning file when required
- [ ] T009 Document and implement Core Data model migration/compatibility in `Warden/Store/` when required
- [ ] T010 Verify secrets remain in Keychain and are excluded from persistence, fixtures, and `WardenLog`

**Checkpoint**: Tests fail for the intended missing behavior; contracts and migration approach are stable.

---

## Phase 3: User Story 1 — [Title] (Priority: P1) 🎯 MVP

**Goal**: [Smallest independently useful macOS outcome]

**Independent Test**: [Exact focused XCTest/XCUITest or manual workflow]

### Tests for User Story 1

- [ ] T011 [P] [US1] Add focused XCTest coverage in `WardenTests/[Path]/[Name]Tests.swift`
- [ ] T012 [P] [US1] Add XCUITest coverage in `WardenUITests/[Name]Tests.swift` if interaction cannot be covered below UI
- [ ] T013 [P] [US1] Cover cancellation, malformed response, offline/provider failure, or persistence failure as applicable

### Implementation for User Story 1

- [ ] T014 [P] [US1] Implement model changes in `Warden/Models/[Name].swift`
- [ ] T015 [US1] Implement service/manager behavior in `Warden/Utilities/[Name].swift`
- [ ] T016 [US1] Implement provider behavior in `Warden/Utilities/APIHandlers/[Name]Handler.swift` through `APIProtocol` and the factory
- [ ] T017 [US1] Implement SwiftUI/view-model behavior in `Warden/UI/[Feature]/[Name]View.swift`
- [ ] T018 [US1] Add accessible loading, empty, success, cancellation, and error states
- [ ] T019 [US1] Run the focused US1 tests and demonstrate the independent workflow

**Checkpoint**: User Story 1 works independently without breaking unaffected providers or existing chats.

---

## Phase 4: User Story 2 — [Title] (Priority: P2)

**Goal**: [Next independently useful outcome]

**Independent Test**: [Exact focused verification]

### Tests for User Story 2

- [ ] T020 [P] [US2] Add focused XCTest coverage in `WardenTests/[Path]/[Name]Tests.swift`
- [ ] T021 [P] [US2] Add XCUITest coverage in `WardenUITests/[Name]Tests.swift` when required

### Implementation for User Story 2

- [ ] T022 [P] [US2] Implement story-specific model or fixture changes in the owning module
- [ ] T023 [US2] Implement story-specific service/provider behavior through existing abstractions
- [ ] T024 [US2] Implement native macOS presentation and state handling in `Warden/UI/[Feature]/`
- [ ] T025 [US2] Run focused US2 tests and re-run US1 regression tests

**Checkpoint**: User Stories 1 and 2 remain independently testable.

---

## Phase 5: User Story 3 — [Title] (Priority: P3)

**Goal**: [Optional/later outcome]

**Independent Test**: [Exact focused verification]

- [ ] T026 [P] [US3] Add failing focused tests in `WardenTests/` or `WardenUITests/`
- [ ] T027 [US3] Implement service/model changes in their owning Warden modules
- [ ] T028 [US3] Implement native macOS UI behavior in `Warden/UI/[Feature]/`
- [ ] T029 [US3] Run focused US3 tests and prior-story regression tests

---

## Final Phase: Cross-Cutting Verification and Polish

- [ ] T030 [P] Replace ad-hoc diagnostics with privacy-safe `WardenLog`/signposts
- [ ] T031 [P] Verify VoiceOver labels, keyboard/focus behavior, reduced motion, and localization impact where applicable
- [ ] T032 Exercise stream cancellation, provider failure, app restart, and Core Data migration paths as applicable
- [ ] T033 Run `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`
- [ ] T034 Run `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'`
- [ ] T035 Verify the diff contains no API keys, private user data, DerivedData, build output, or ignored package checkout content
- [ ] T036 [P] Update `README.md`, `CLAUDE.md`, `AGENTS.md`, or feature documentation only where behavior or commands changed
- [ ] T037 Execute and record the `quickstart.md` verification workflow

## Dependencies and Execution Order

1. Baseline and Setup establishes the environment.
2. Foundational tests/contracts block dependent user stories.
3. Each user story starts with failing focused tests, then models/contracts, services/providers, UI, and verification.
4. Stories may run in parallel only when their exact files and shared contracts do not overlap.
5. Cross-cutting verification follows all selected stories.

## Parallelization Rules

- Tests and fixtures in separate files may run in parallel.
- Independent model and UI files may run in parallel only after shared contracts are fixed.
- Do not parallelize edits to `ChatStore.swift`, `APIProtocol.swift`, `APIServiceFactory.swift`, the Core Data model, or the same Xcode project section.
- Local package work and app integration may run in parallel only after their public interface is agreed.

## Completion Evidence

A completed task list records actual commands and outcomes. Never mark build or tests complete based on expected output. If signing, package resolution, simulator/device, or environment configuration blocks a command, capture the real error and run the strongest unaffected verification instead.
