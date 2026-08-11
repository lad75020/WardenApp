# Quickstart: Verify App Shell and Onboarding

## Prerequisites

- macOS development environment with the Warden scheme available.
- No live provider credentials are required.
- Run commands from the repository root.

## 1. Focused Unit Tests

```bash
xcodebuild test \
  -project Warden.xcodeproj \
  -scheme Warden \
  -destination 'platform=macOS' \
  -only-testing:WardenTests/WelcomeExperienceStateTests \
  -only-testing:WardenTests/OnboardingFlowTests
```

Expected: welcome-state and onboarding-transition tests pass deterministically.

## 2. Focused UI Workflow

```bash
xcodebuild test \
  -project Warden.xcodeproj \
  -scheme Warden \
  -destination 'platform=macOS' \
  -only-testing:WardenUITests/AppShellUITests
```

Expected coverage:

1. Launch reaches a recognizable welcome or existing-content state.
2. Setup-required state exposes interactive setup and Settings.
3. Onboarding supports Next, Back, provider-step Settings, and one Start completion.
4. Repeating the Settings action does not create duplicate Settings windows.

If macOS accessibility/automation permission blocks XCUITest, record the exact failure and perform the same workflow manually; do not report the UI suite as passing.

## 3. Manual Appearance and Persistence Check

1. Open Settings with Command-Comma.
2. Select System, Light, and Dark; verify both main and Settings windows update.
3. Select a non-default chat font size and toggle sidebar icons.
4. Close and reopen Settings; verify one window and retained values.
5. Select a chat, quit, and relaunch; verify valid last-chat restoration.
6. Import malformed JSON; verify a visible non-destructive error.
7. Cancel import/export panels; verify no data change or failure alert.

## 4. Build

```bash
xcodebuild \
  -project Warden.xcodeproj \
  -scheme Warden \
  -destination 'platform=macOS' \
  build
```

## 5. Full Test Suite

```bash
xcodebuild test \
  -project Warden.xcodeproj \
  -scheme Warden \
  -destination 'platform=macOS'
```

## 6. Privacy Review

- Confirm no provider token access was added to shell/onboarding code.
- Confirm no chat or backup contents are logged.
- Confirm no telemetry or automatic network request was added.
- Confirm no DerivedData, user-state, backup, or local credential file is staged.
