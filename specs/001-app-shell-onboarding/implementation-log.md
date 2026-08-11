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
