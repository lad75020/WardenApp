---
description: "Executable tasks for WardenApp App Shell and Onboarding"
---

# Tasks: App Shell and Onboarding

**Input**: Design documents from `/specs/001-app-shell-onboarding/`  
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/app-shell-ui-contract.md`, and `quickstart.md`  
**Verification**: XCTest/XCUITest plus the Warden macOS build; no test uses live provider credentials or network access

## Format: `[ID] [P?] [Story] Description`

- **[P]** means the task can run in parallel because it touches a different file and has no unresolved dependency.
- **[US#]** maps implementation and verification to one user story.
- Tests precede the production behavior they verify and must first fail for the intended missing behavior.

## Phase 1: Baseline and Setup

**Purpose**: Preserve unrelated working-tree changes and establish real pre-change evidence.

- [x] T001 Record the current branch, working-tree ownership cautions, and affected file inventory in `specs/001-app-shell-onboarding/implementation-log.md`
- [x] T002 Run the baseline `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build` and record its real outcome in `specs/001-app-shell-onboarding/implementation-log.md`
- [x] T003 [P] Confirm existing app, unit-test, and UI-test target membership in `Warden.xcodeproj/project.pbxproj` and record any required additions in `specs/001-app-shell-onboarding/implementation-log.md`

**Checkpoint**: The starting branch, pre-existing diffs, build state, and target-membership requirements are explicit.

---

## Phase 2: Foundational Test Support

**Purpose**: Create deterministic local-only seams shared by the story tests.

- [x] T004 Create isolated local preference and welcome-context fixtures without credentials in `WardenTests/AppShell/AppShellTestSupport.swift`
- [x] T005 Add `WardenTests/AppShell/AppShellTestSupport.swift` to the WardenTests target in `Warden.xcodeproj/project.pbxproj`
- [x] T006 [P] Add reusable launch configuration and accessibility lookup helpers in `WardenUITests/AppShellTestSupport.swift`

**Checkpoint**: Unit and UI tests can arrange shell state without paid credentials, telemetry, or provider network calls.

---

## Phase 3: User Story 1 — Reach the Right Starting State (Priority: P1) 🎯 MVP

**Goal**: Show the correct welcome state and restore or persist a valid last-chat selection.

**Independent Test**: Exercise no-provider, provider-without-chats, provider-with-chats, valid-last-chat, and stale-last-chat states using focused XCTest plus a clean local UI launch.

### Tests for User Story 1

- [x] T007 [P] [US1] Add failing welcome-state and stale-selection tests in `WardenTests/AppShell/WelcomeExperienceStateTests.swift`
- [x] T008 [P] [US1] Add failing startup-state and primary-action UI checks in `WardenUITests/AppShellUITests.swift`

### Implementation for User Story 1

- [x] T009 [US1] Implement deterministic welcome-context resolution in `Warden/UI/WelcomeScreen/WelcomeExperienceState.swift`
- [x] T010 [US1] Render setup-required, first-chat, and chat-selection states from the resolver with stable accessibility identifiers in `Warden/UI/WelcomeScreen/WelcomeScreen.swift`
- [x] T011 [US1] Restore only an existing `lastOpenedChatId` and persist each valid selected chat in `Warden/UI/ContentView.swift`
- [x] T012 [US1] Add new US1 source and test files to the Warden and test targets in `Warden.xcodeproj/project.pbxproj`
- [x] T013 [US1] Run focused US1 tests and record exact outcomes in `specs/001-app-shell-onboarding/implementation-log.md`

**Checkpoint**: Every supported startup context presents one understandable next action, while invalid restoration data falls back safely.

---

## Phase 4: User Story 2 — Complete Guided Setup (Priority: P2)

**Goal**: Make all three onboarding steps navigable, keep Settings reachable on the provider step, and complete exactly once.

**Independent Test**: Reset local onboarding state, navigate Next and Back, open Settings without losing guide state, invoke Start twice, and verify one completion/new-chat transition.

### Tests for User Story 2

- [x] T014 [P] [US2] Add failing transition and duplicate-completion tests in `WardenTests/AppShell/OnboardingFlowTests.swift`
- [x] T015 [P] [US2] Extend onboarding navigation and provider-step Settings checks in `WardenUITests/AppShellUITests.swift`

### Implementation for User Story 2

- [x] T016 [US2] Implement the internal onboarding step and completion-guard state in `Warden/UI/WelcomeScreen/OnboardingFlowState.swift`
- [x] T017 [US2] Route Back, Next, Open Settings, and Start through the flow state and expose progress semantics in `Warden/UI/WelcomeScreen/InteractiveOnboardingView.swift`
- [x] T018 [US2] Preserve optional guide access after completion and recover the guide after Settings activation in `Warden/UI/WelcomeScreen/WelcomeScreen.swift`
- [x] T019 [US2] Add new US2 source and test files to the Warden and WardenTests targets in `Warden.xcodeproj/project.pbxproj`
- [x] T020 [US2] Run focused US2 tests plus the US1 regression tests and record exact outcomes in `specs/001-app-shell-onboarding/implementation-log.md`

**Checkpoint**: Guided setup is keyboard/accessibility reachable, survives the Settings detour, and starts at most one chat per completion.

---

## Phase 5: User Story 3 — Control the Native App Shell and Appearance (Priority: P3)

**Goal**: Keep native window commands and one reusable Settings window while making appearance, general preferences, and backup feedback consistent.

**Independent Test**: Repeatedly open Settings, change System/Light/Dark and general preferences, close/reopen, exercise shell shortcuts, relaunch, cancel backup panels, and import malformed JSON.

### Tests for User Story 3

- [x] T021 [P] [US3] Add Settings reuse, appearance, preference, shortcut, and malformed-import UI checks in `WardenUITests/AppShellUITests.swift`

### Implementation for User Story 3

- [x] T022 [US3] Normalize System/Light/Dark updates, add accessibility identifiers, and show non-destructive import/export failures in `Warden/UI/Preferences/TabGeneralSettingsView.swift`
- [x] T023 [US3] Preserve one main-actor Settings window across repeated activation, close, reopen, and appearance changes in `Warden/Utilities/SettingsWindowManager.swift`
- [x] T024 [US3] Preserve intended-window routing, standard menu commands, fallback-storage warning, and practical frame restoration in `Warden/WardenApp.swift`
- [x] T025 [US3] Expose stable shell navigation identifiers without changing provider/chat behavior in `Warden/UI/ContentView.swift`
- [x] T026 [US3] Run focused US3 UI tests and record exact outcomes or the precise macOS automation blocker in `specs/001-app-shell-onboarding/implementation-log.md`

**Checkpoint**: Native commands target the intended window, Settings never duplicates, preferences persist, and backup failures are visible without data corruption.

---

## Phase 6: Cross-Cutting Verification and Polish

- [x] T027 [P] Verify VoiceOver labels, keyboard focus, non-color progress, and enlarged-text behavior against `specs/001-app-shell-onboarding/contracts/app-shell-ui-contract.md`
- [x] T028 Run all focused app-shell XCTest and XCUITest commands from `specs/001-app-shell-onboarding/quickstart.md` and record real outcomes in `specs/001-app-shell-onboarding/implementation-log.md`
- [x] T029 Run `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build` and record the real result in `specs/001-app-shell-onboarding/implementation-log.md`
- [x] T030 Run `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'` and record the real result or exact environment blocker in `specs/001-app-shell-onboarding/implementation-log.md`
- [x] T031 [P] Inspect `Warden/UI/`, `Warden/Utilities/`, `WardenTests/`, `WardenUITests/`, and `Warden.xcodeproj/project.pbxproj` diffs for Keychain/secret exposure, private data, telemetry, ad-hoc `print`, build output, and unrelated-change damage
- [x] T032 Re-run `git diff --check` and reconcile every requirement and success criterion in `specs/001-app-shell-onboarding/implementation-log.md`

## Dependencies and Execution Order

1. Phase 1 establishes trustworthy baseline evidence and protects pre-existing work.
2. Phase 2 provides shared credential-free test support and blocks all story phases.
3. US1 is the MVP and establishes welcome routing used by US2.
4. US2 depends on US1's welcome integration but can otherwise be tested independently through its flow state.
5. US3 uses the shell entry points established by US1 and US2; it does not depend on provider validation or chat streaming.
6. Final verification follows all three stories.

### User Story Dependency Graph

```text
Setup -> Test Support -> US1 -> US2 -> US3 -> Final Verification
```

### Parallel Opportunities

- T003 can run alongside T001-T002 because it inspects project membership rather than building.
- T006 can run alongside T004-T005 because it owns the UI-test support file.
- T007 and T008 can be authored in parallel before US1 production edits.
- T014 and T015 can be authored in parallel before US2 production edits.
- T021 can be authored before US3 implementation begins.
- T027 and T031 can run in parallel after production work stabilizes.
- Do not parallelize edits to `Warden/UI/WelcomeScreen/WelcomeScreen.swift`, `Warden/UI/ContentView.swift`, or `Warden.xcodeproj/project.pbxproj`.

## Incremental Implementation Strategy

1. Deliver US1 first as the minimum independently useful shell correction.
2. Add US2 without changing provider configuration or requiring credentials.
3. Add US3 by extending existing window and preference owners, not replacing them.
4. Run focused tests after each story and the full build/test gates only after all selected stories are integrated.

## Completion Evidence

A checked task records actual command output in `specs/001-app-shell-onboarding/implementation-log.md`. A build or test task is never marked complete from expected output. Signing, automation permission, package resolution, or environment failures must be captured verbatim and followed by the strongest unaffected verification.
