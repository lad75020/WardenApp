# Tasks: Multi-Agent and Quick Chat

**Input**: Design documents from `specs/012-multi-agent-and-quick-chat/`  
**Prerequisites**: `spec.md` and `plan.md`; include `research.md`, `data-model.md`, `contracts/multi-agent-quick-chat-contract.md`, and `quickstart.md`
**Verification**: XCTest plus the Warden macOS build; tests do not use real paid credentials

## Phase 1: Baseline and Setup

- [X] T001 Confirm active SDD context in `/.specify/feature.json` and `/.specify/extensions/time-machine/features-queue.yml`, and record current feature status in `./specs/012-multi-agent-and-quick-chat/plan.md`.
- [X] T002 Run baseline prerequisite check before feature edits: `bash .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks`.
- [X] T003 Run baseline build command using `./Warden.xcodeproj` before implementation edits: `xcodebuild -project ./Warden.xcodeproj -scheme Warden -destination 'platform=macOS,arch=arm64' build`.

---

## Phase 2: Foundational Contracts and Deterministic Tests

- [X] T004 Add shared constants in `./Warden/Configuration/AppConstants.swift` for `MultiAgent.maxConcurrentServices`, `QuickChat.minPanelHeight`, and `QuickChat.maxPanelHeight`.
- [X] T005 [P] Add pure keyboard shortcut round-trip coverage in `./WardenTests/Utilities/HotkeyModelsTests.swift` for `KeyboardShortcut.from(displayString:)` and `displayString`.
- [X] T006 [P] Add pure multi-agent cap and `AgentResponse` transition coverage in `./WardenTests/Utilities/MultiAgentMessageManagerTests.swift`.

**Checkpoint**: Shared constants and failing tests exist for all logic-only boundaries before production edits.

---

## Phase 3: User Story 1 — Compare responses from multiple services (Priority: P1) 🎯 MVP

**Goal**: At most three services are selected and dispatched per send, and each agent keeps independent response/error/completion state.

**Independent Test**: Deterministic tests in `./WardenTests/Utilities/MultiAgentMessageManagerTests.swift` and `./WardenTests/Utilities/MultiAgentServiceSelectorTests.swift` verify selection cap and response-state transitions.

### Tests for User Story 1

- [X] T007 [US1] Add selector-behavior coverage in `./WardenTests/Utilities/MultiAgentServiceSelectorTests.swift` for disabled state at the max service limit.
- [X] T008 [US1] Add send-path and cancellation coverage in `./WardenTests/Utilities/MultiAgentMessageManagerTests.swift` for `AgentResponse` completion/error finalization.

### Implementation for User Story 1

- [X] T009 [US1] Replace hard-coded multi-agent cap with `AppConstants.MultiAgent.maxConcurrentServices` in `./Warden/UI/Chat/MultiAgentServiceSelector.swift`.
- [X] T010 [US1] Replace runtime hard cap `prefix(3)` with `AppConstants.MultiAgent.maxConcurrentServices` in `./Warden/Utilities/MultiAgentMessageManager.swift` while preserving cancellation semantics.
- [X] T011 [US1] Keep stop semantics aligned in `./Warden/Utilities/MultiAgentMessageManager.swift` and `./Warden/UI/Chat/ChatView.swift` for independent in-flight task cancellation and finalization.
- [X] T012 [US1] Run focused user-story verification tests in `./Warden.xcodeproj` via `xcodebuild test -project ./Warden.xcodeproj -scheme Warden -destination 'platform=macOS,arch=arm64' -only-testing:WardenTests/MultiAgentMessageManagerTests`.

---

## Phase 4: User Story 2 — Summon a floating quick chat with a global hotkey (Priority: P1)

**Goal**: Quick-chat panel clamp constants are centralized and panel lifecycle remains stable.

**Independent Test**: Deterministic constant assertions in tests confirm min/max bounds are applied from `AppConstants`.

### Tests for User Story 2

- [X] T013 [US2] Add constant boundary assertions in `./WardenTests/Utilities/FloatingPanelManagerTests.swift` for `AppConstants.QuickChat.minPanelHeight` and `AppConstants.QuickChat.maxPanelHeight`.

### Implementation for User Story 2

- [X] T014 [US2] Replace literal panel clamp bounds with constants in `./Warden/Utilities/FloatingPanelManager.swift`.
- [X] T015 [US2] Preserve quick-chat focus/close lifecycle in `./Warden/Utilities/FloatingPanelManager.swift` while applying constant-based clamp behavior.
- [X] T016 [US2] Add smoke verification command notes for quick-chat panel behavior in `./specs/012-multi-agent-and-quick-chat/quickstart.md`.

---

## Phase 5: User Story 3 — Configure hotkeys for actions (Priority: P2)

**Goal**: Registration failures are surfaced to the user with an actionable recommendation without affecting non-global hotkeys.

**Independent Test**: Unit tests confirm shortcut parsing/state transition behavior and `TabHotkeysView` warning rendering.

### Tests for User Story 3

- [X] T017 [US3] Add status/mapping-failure test coverage in `./WardenTests/Utilities/GlobalHotkeyHandlerTests.swift`.
- [X] T018 [US3] Add warning-surface coverage in `./WardenTests/UI/TabHotkeysViewTests.swift` for global quick-chat failure recommendation text.

### Implementation for User Story 3

- [X] T019 [US3] Expose quick-chat registration outcome state in `./Warden/Utilities/GlobalHotkeyHandler.swift`.
- [X] T020 [US3] Ensure quick-chat shortcut registration updates are wired through `./Warden/Models/HotkeyModels.swift`, `./Warden/Models/HotkeyModels.swift`, and `./Warden/WardenApp.swift` without changing non-global shortcut actions.
- [X] T021 [US3] Render visible registration-failure warning + recommendation in `./Warden/UI/Preferences/TabHotkeysView.swift` while preserving in-app non-global action behavior.
- [X] T022 [US3] Run focused hotkey unit checks in `./Warden.xcodeproj` via `xcodebuild test -project ./Warden.xcodeproj -scheme Warden -destination 'platform=macOS,arch=arm64' -only-testing:WardenTests/HotkeyModelsTests`.

---

## Phase N: Cross-Cutting Verification and Polish

- [X] T023 Run focused feature test pass in `./Warden.xcodeproj` via `xcodebuild test -project ./Warden.xcodeproj -scheme Warden -destination 'platform=macOS,arch=arm64' -only-testing:WardenTests/MultiAgentQuickChatTests`.
- [X] T024 Run full build from `./Warden.xcodeproj` with scheme `Warden` and record output in `./specs/012-multi-agent-and-quick-chat/quickstart.md`.
- [X] T025 Run full test suite from `./Warden.xcodeproj` with scheme `Warden` and record output in `./specs/012-multi-agent-and-quick-chat/quickstart.md`.
- [X] T026 [P] Run `git diff --check` and verify no secrets appear in changed files under `./Warden/` and `./WardenTests/`.
- [ ] T027 Execute manual checks in `./specs/012-multi-agent-and-quick-chat/quickstart.md` for service disablement and quick-chat warning UX.

## Dependencies and Execution Order

1. Phase 1 stabilizes context and baseline.
2. Phase 2 adds shared constants and deterministic test seams.
3. US1 (`T007`–`T012`) must complete before multi-agent implementation is complete.
4. US2 (`T013`–`T016`) may run after shared constants are in place.
5. US3 (`T017`–`T022`) may run after US2/US1 or in parallel where file edits do not overlap.
6. T023–T027 run after all story implementation.

## Parallelization Rules

- T004 and T005 can run in parallel.
- T005 and T006 can run in parallel.
- T007 and T010 can run in parallel once constants exist.
- T017 and T021 can run in parallel with US1 once `GlobalHotkeyHandler.swift` API shape is defined.
- Avoid parallel edits to `./Warden/Utilities/FloatingPanelManager.swift`, `./Warden/Utilities/GlobalHotkeyHandler.swift`, and `./Warden/UI/Preferences/TabHotkeysView.swift` during overlapping changes.

## Completion Evidence

A completed task list records actual command output and outcomes in this branch. Never mark build or tests complete without actual run results in this feature.