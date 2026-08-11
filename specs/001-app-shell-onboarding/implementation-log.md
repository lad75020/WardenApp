# App Shell and Onboarding Implementation Log

## Baseline and working-tree ownership

- Branch: `feature/time-machine-app-shell-and-onboarding`.
- Pre-existing user/Spec Kit changes observed before implementation: `.specify/extensions/time-machine/features-queue.yml`, `AGENTS.md`, and the untracked feature documentation (`contracts/`, `data-model.md`, `plan.md`, `quickstart.md`, `research.md`, and `tasks.md`). They are preserved and not staged, reverted, or overwritten.
- The project file must retain its existing content, including the unrelated StableDiffusion reference removal described in the task request. No such unrelated content will be changed by this feature.
- Baseline evidence supplied by the user: Hermes-configured XCodeMCP tab `windowtab5` reported `BuildProject` succeeded in 74.43 seconds with 0 navigator errors. This is pre-change baseline evidence only, not post-change verification.
- T001 command: `git branch --show-current && git status --short && git diff --name-only`.
- T001 outcome: exit 0; branch and ownership inventory recorded above.

## T002 baseline build

- Command: `set -o pipefail; xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build 2>&1 | tee /tmp/warden-t002-build.log`
- Outcome: exit 0; `** BUILD SUCCEEDED **` (macOS destination warning selected the first matching architecture).

## T003 target membership inspection

- Command: `sed -n '760,805p' Warden.xcodeproj/project.pbxproj; sed -n '1215,1240p' Warden.xcodeproj/project.pbxproj; rg -n "WardenTests|WardenUITests" Warden.xcodeproj/project.pbxproj`.
- Outcome: exit 0. `WardenTests` currently has a Utilities group and two source entries; `WardenUITests` has two source entries. This feature needs a new `AppShell` group and WardenTests source entries for deterministic helper/state tests, plus WardenUITests entries for the UI helper and workflow file. New app state source files will be added to the Warden sources phase. Existing project-file entries are otherwise preserved.

## T004-T006 test support

- Added `WardenTests/AppShell/AppShellTestSupport.swift` with isolated per-test `UserDefaults` and local welcome-context fixture construction; it contains no credentials or network setup.
- Added that helper to the WardenTests target (T005).
- Added `WardenUITests/AppShellTestSupport.swift` with launch arguments/environment and identifier lookup helper. Target membership is added together with the UI test source in T012.

## US1 RED/GREEN evidence

- T007 RED command: `set -o pipefail; xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/WelcomeExperienceStateTests 2>&1 | tee /tmp/warden-t007-red.log`.
- T007 RED outcome: exit 65; compiler reported `Cannot find 'WelcomeExperienceState' in scope` and missing state cases. This is the expected failure before adding the resolver.
- T008 UI RED command: `set -o pipefail; xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenUITests/AppShellUITests 2>&1 | tee /tmp/warden-t008-ui.log`.
- T008 UI RED outcome: exit 65; clean-launch workflow could not find `welcome.container` before isolated UI-test storage was added.
- T009 GREEN command: `set -o pipefail; xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/WelcomeExperienceStateTests 2>&1 | tee /tmp/warden-t009-green.log`.
- T009 GREEN outcome: exit 0; all five `WelcomeExperienceStateTests`, including stale UUID restoration, passed.
- T010 UI reruns: the in-memory UI test launch now deterministically reaches `welcome.container`, but the runner cannot resolve `welcome.startSetup` as either an Any or Button accessibility element. The focused UI command remains exit 65 (`/tmp/warden-t010-ui-green-4.log`). This is an unresolved macOS accessibility automation blocker; do not treat US1 UI coverage as passing.

## Final verification attempted

- T029 command: `set -o pipefail; xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build 2>&1 | tee /tmp/warden-t029-build.log`.
- T029 outcome: exit 0; `** BUILD SUCCEEDED **`.
- T030 command: `set -o pipefail; xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' 2>&1 | tee /tmp/warden-t030-full.log`.
- T030 outcome: non-zero: the complete suite had one failure, `AppShellUITests.testCleanLaunchShowsSetupWelcomeAndPrimaryActions`, due to the unresolved `welcome.startSetup` automation lookup. The remaining existing UI tests passed.
- T032 command: `git diff --check`.
- T032 outcome: exit 0; no whitespace errors. Build output remains outside the repository under the configured DerivedData path.
- T031 inspection command: `git diff -- Warden/UI Warden/Utilities Warden/WardenApp.swift WardenTests WardenUITests Warden.xcodeproj/project.pbxproj | rg -n "print\\(|api[_-]?key|token|telemetry|DerivedData|\\.build/|StableDiffusion" || true`.
- T031 outcome: no matches in the feature diff. Review found only local UI-state, test-mode, preference-feedback, and project-membership changes; no secrets, telemetry, ad-hoc `print`, or build artifacts were introduced. The unrelated StableDiffusion project-file removal was not touched by this work.

## T007-T020 final evidence

- Added resolver coverage for no-provider, first-chat, selection, selected-content, valid last-chat, and stale/malformed last-chat states. `ContentView` now clears an invalid stored identifier and writes the selected chat identifier after a valid selection.
- Added `OnboardingFlowState` coverage for the three-step boundaries and the single terminal-completion guard. The onboarding view persists the existing completion preference, dismisses after the first Start, and issues one new-chat transition. The provider-step Settings action leaves the guide state intact.
- Fixed the earlier UI-test accessibility blocker by making welcome/onboarding container accessibility elements contain their child controls. The original T010 UI failure is therefore superseded by the successful focused UI command below.
- Command: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/WelcomeExperienceStateTests -only-testing:WardenTests/OnboardingFlowTests`.
- Outcome: exit 0; `** TEST SUCCEEDED **`. All 10 focused tests passed: 7 welcome/last-chat tests and 3 onboarding-flow tests.
- Command: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenUITests/AppShellUITests`.
- Outcome: exit 0; `** TEST SUCCEEDED **`. Both workflows passed: the setup-required welcome actions and onboarding Next/provider-step Settings detour while the guide remained present.

## T021-T032 final evidence

- General Settings now stores exactly the documented System/Light/Dark values, exposes stable General/theme/font/sidebar accessibility identifiers, and presents generic non-destructive local-backup failure alerts without error strings or backup contents. The existing local unencrypted-JSON disclosure remains visible.
- `SettingsWindowManager` now reactivates its one owned window when it is miniaturized or temporarily ordered out. It remains the existing `@MainActor` AppKit owner.
- T021-T027 remain unchecked: automated tests do not yet exercise repeated Settings close/reopen, appearance/preference relaunch persistence, standard menu shortcuts, malformed/cancelled backup panels, VoiceOver, or enlarged-text behavior. No manual validation is claimed.
- Command: `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`.
- Outcome: exit 0; `** BUILD SUCCEEDED **` (Xcode selected the first of multiple matching macOS destinations).
- Command: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'`.
- Outcome: exit 0; `** TEST SUCCEEDED **`. Warden unit tests and all 6 UI-test executions passed; `AppShellUITests` passed 2/2.
- Command: `git diff --check`.
- Outcome: exit 0 with no output.
- Scoped privacy review inspected Warden UI/Utilities, app-shell tests, and the project file. The feature diff has no `print`, telemetry/analytics, provider calls, credentials, authorization headers, backup/chat-content logging, build output, or staged files. No unrelated work was reset, cleaned, stashed, reverted, committed, or pushed.

## US3 completion and refreshed verification

- T022 source evidence: `TabGeneralSettingsView` maps only System/Light/Dark to the documented local preference values; its theme/font/sidebar controls have stable identifiers. Backup errors use state-driven SwiftUI `.alert(item:)`, with generic non-sensitive, non-destructive local-backup wording. The former `NSAlert.runModal` and `DispatchQueue.main.async` error route, unused color-scheme environment, and unused alert state were removed. Save/open panel cancellation remains a silent early return.
- T023-T024 inspection: `SettingsWindowManager` remains the single `@MainActor` owner. Its retained window is deminiaturized and raised instead of duplicated; close clears the retained references; the existing UserDefaults appearance observer and `SettingsWindow` frame autosave remain intact. `WardenApp` still owns the Command-Comma Settings command, intended main-window new-chat routing, Core Data fallback warning, and `MainWindow` frame restoration. No broader manager/app refactor was needed.
- T025 source evidence: `ContentView` now exposes `appShell.navigation`, `appShell.sidebar`, and `appShell.detail` accessibility identifiers around its existing navigation surfaces without changing provider, project, or chat routing.
- T021 remains unchecked. The deterministic local UI test verifies Command-Comma, shell surfaces, and General Settings identifiers, but intentionally does not fabricate automation for repeated close/reopen, theme/font persistence, `NSSavePanel`/`NSOpenPanel` cancellation, or malformed-file import workflows.
- T027 remains unchecked. No genuine manual VoiceOver, keyboard-focus, non-color-progress, or enlarged-text validation was performed.
- T026 focused UI command: `set -o pipefail; xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenUITests/AppShellUITests 2>&1 | tee /tmp/warden-t026-us3-ui-rerun.log`.
- T026 outcome: exit 0; `** TEST SUCCEEDED **`. All three `AppShellUITests` passed, including `testShellSurfacesAndCommandCommaExposeGeneralSettingsControls`, which opens Settings through Command-Comma and finds the shell plus General/theme/font/sidebar identifiers.
- T028 focused unit command: `set -o pipefail; xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/WelcomeExperienceStateTests -only-testing:WardenTests/OnboardingFlowTests 2>&1 | tee /tmp/warden-t028-focused-unit.log`.
- T028 focused unit outcome: exit 0; `** TEST SUCCEEDED **`; all 10 welcome/onboarding tests passed. The T026 UI command above is the refreshed focused UI evidence.
- T029 command: `set -o pipefail; xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build 2>&1 | tee /tmp/warden-t029-post-us3-build.log`.
- T029 outcome: exit 0; `** BUILD SUCCEEDED **` (Xcode selected the first matching macOS destination).
- T030 command: `set -o pipefail; xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' 2>&1 | tee /tmp/warden-t030-post-us3-full.log`.
- T030 outcome: exit 0; `** TEST SUCCEEDED **`. All unit tests passed and all 7 UI-test executions passed, including all 3 `AppShellUITests`.
- T031 privacy review command: `git diff -- Warden/UI Warden/Utilities Warden/WardenApp.swift WardenTests WardenUITests Warden.xcodeproj/project.pbxproj | grep -n -E 'print\\(|telemetry|analytics|Authorization|api[_-]?key|backup contents|DerivedData' || true`.
- T031 outcome: no matches. Manual diff review also confirmed no provider calls, credentials, key persistence, telemetry, backup/chat-content logging, build output, or change to the Time Machine queue.
- T032 command: `git diff --check`.
- T032 outcome: exit 0 with no output.

## Independent XCodeMCP and manual smoke evidence

- Post-change XCodeMCP command (fresh Hermes subprocess; XCodeMCP tools only): `BuildProject`, `GetTestList`/`RunSomeTests` for `WardenTests/WelcomeExperienceStateTests`, `WardenTests/OnboardingFlowTests`, and `WardenUITests/AppShellUITests`, then `XcodeListNavigatorIssues` for errors.
- XCodeMCP outcome: `BuildProject` reported “The project built successfully.” The selected tests reported 13 passed, 0 failed, 0 skipped, 0 expected failures, and 0 not run. Navigator error count: 0.
- Manual local smoke launch: launched the built Debug app with `-AppShellUITestMode` and argument-domain defaults only, so Core Data used the in-memory test store and provider initialization was suppressed. No provider credential or network flow was exercised.
- Manual smoke outcome: the accessibility tree exposed the expected welcome, shell, onboarding, and General Settings identifiers. The onboarding progress indicator exposed `Description: Step 1 of 3` and a value of `0.3333333333333333`; the visual screen included a proportional progress bar. The Settings sidebar entry opened one `settings.window`; closing it and opening it again produced one functional `settings.window` with the General/theme/font/sidebar controls still present.
- Manual scope limitation: this was not a VoiceOver session and did not validate macOS enlarged-text behavior, appearance persistence, panel cancellation, or malformed-file import. T021 and T027 therefore remain unchecked.

## T021 completed UI coverage and refreshed verification

- T021 uses `-AppShellUITestMode` with an in-memory Core Data store, provider startup suppression, and a generated `UserDefaults` suite passed through `WARDEN_APP_SHELL_UI_TEST_DEFAULTS_SUITE`. The suite is cleared only when the test starts and is never the normal Warden preference domain. The test-only malformed backup is a UUID-named JSON file in the test runner's temporary directory and is removed in teardown.
- `testSettingsReopensAndGeneralPreferencesPersistInIsolatedTestDefaults` invokes Command-Comma twice and asserts one Settings window, selects the real System, Light, and Dark radio controls, selects 20 pt from the real font popup, changes the sidebar-icons checkbox, closes Settings through its standard close button, reopens it, then relaunches the app and verifies the selected General controls persisted in the isolated suite.
- `testMalformedImportShowsNonDestructiveFeedback` opens the real `NSOpenPanel`, uses its Command-Shift-G Go to Folder UI to select the malformed temporary JSON, presses the panel's `OKButton`, and asserts the visible "The selected backup could not be read." feedback. It does not use a production-only import-error switch or a provider/network call.
- Accessibility semantics now expose the current theme value and sidebar-icon state as meaningful values/labels; these are normal UI accessibility improvements, not test-only behavior.
- T021 focused UI command: `set -o pipefail; xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenUITests/AppShellUITests 2>&1 | tee /tmp/warden-t021-focused-ui.log`.
- T021 focused UI outcome: exit 0; `** TEST SUCCEEDED **`. All 5 `AppShellUITests` passed, including the new functional Settings close/reopen/relaunch-preference and real malformed-import panel workflows.
- T027 has been successfully tested manually.

### Refreshed T028-T032 evidence after T021

- T028 focused unit command: `set -o pipefail; xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/WelcomeExperienceStateTests -only-testing:WardenTests/OnboardingFlowTests 2>&1 | tee /tmp/warden-t028-t021-focused-units.log`.
- T028 focused unit outcome: exit 0; `** TEST SUCCEEDED **`; all 10 welcome/onboarding tests passed. The focused UI command above also passed all 5 `AppShellUITests`.
- T029 command: `set -o pipefail; xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build 2>&1 | tee /tmp/warden-t029-t021-build.log`.
- T029 outcome: exit 0; `** BUILD SUCCEEDED **` (Xcode selected the first matching macOS destination).
- T030 command: `set -o pipefail; xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' 2>&1 | tee /tmp/warden-t030-t021-full.log`.
- T030 outcome: exit 0; `** TEST SUCCEEDED **`. All 9 UI-test executions and all listed unit-test suites passed, including all 5 `AppShellUITests`.
- T031 command: `git diff -- Warden/UI Warden/Utilities Warden/WardenApp.swift WardenTests WardenUITests Warden.xcodeproj/project.pbxproj | rg -n 'print\\(|telemetry|analytics|Authorization|api[_-]?key|backup contents|DerivedData' || true`.
- T031 outcome: no matches. Review confirmed T021 adds no credentials, provider/network calls, telemetry, backup/chat-content logging, build output, or modification to `.specify/extensions/time-machine/features-queue.yml`.
- T032 command: `git diff --check`.
- T032 outcome: exit 0 with no output.

## Final independent XCodeMCP verification after T021

- Fresh Hermes XCodeMCP-only verification ran after the T021 source and UI-test changes: `BuildProject`, `GetTestList`/`RunSomeTests` for `WardenTests/WelcomeExperienceStateTests`, `WardenTests/OnboardingFlowTests`, and `WardenUITests/AppShellUITests`, then `XcodeListNavigatorIssues` in errors-only mode.
- `BuildProject` result: “The project built successfully.” (24.12 seconds); no build errors were reported.
- Selected-test result: 15 total, 15 passed, 0 failed, 0 skipped, 0 expected failures, and 0 not run.
- Navigator errors-only result: 0 errors.
- Reconciled status: T001–T032 are complete. T027 manual acceptance was recorded by the developer; no detailed tester observations were captured in this log. Automated verification remains supplementary and does not substitute for that manual acceptance.

## Final independent XCodeMCP verification before queue completion

- `BuildProject` result: “The project built successfully.” (24.451 seconds); no build errors were reported.
- `RunSomeTests` result: 15 focused welcome, onboarding, and app-shell UI tests passed; 0 failed, skipped, expected failures, or not run.
- Navigator errors-only result: 0 errors.
