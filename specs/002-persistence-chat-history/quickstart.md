# Quickstart: Verify Persistence and Chat History

## Preconditions

- Work from `/Volumes/WDBlack4TB/Code/WardenApp` on `feature/time-machine-persistence-and-chat-history`.
- Do not use a personal production chat database for tests. Use in-memory Core Data and test-only launch fixtures.
- No provider credentials, real network request, telemetry destination, or external service is required.

## Focused Unit Verification

1. Run the new persistence recovery unit tests after implementation:

   ```zsh
   set -o pipefail
   xcodebuild test \
     -project Warden.xcodeproj \
     -scheme Warden \
     -destination 'platform=macOS' \
     -only-testing:WardenTests/ChatHistoryRecoveryTests \
     -only-testing:WardenTests/DatabasePatcherMigrationTests \
     2>&1 | tee /tmp/warden-persistence-unit-tests.log
   ```

2. Verify these deterministic cases:
   - Valid chat/service history restores unchanged.
   - Missing-service and invalid-service chats remain persisted and unavailable; neither is automatically deleted.
   - Repair to an existing valid service preserves chat ID, messages, request messages, project, and persona.
   - No valid candidate yields a settings-route result without mutating history.
   - Repeated load/import does not add duplicate chats.
   - Explicit delete, and only explicit delete, removes the chat after selection cleanup.

## UI Verification

1. Run the dedicated UI test cases once the test fixture seam exists:

   ```zsh
   set -o pipefail
   xcodebuild test \
     -project Warden.xcodeproj \
     -scheme Warden \
     -destination 'platform=macOS' \
     -only-testing:WardenUITests/PersistenceRecoveryUITests \
     2>&1 | tee /tmp/warden-persistence-ui-tests.log
   ```

2. Manually validate an isolated unavailable-chat fixture:
   - Unavailable status is visible and understandable without color alone.
   - VoiceOver announces the unavailable status and each recovery action.
   - Tab/keyboard focus reaches recovery actions in the documented order.
   - Repair exposes only valid existing services; choosing one preserves displayed history and enables normal chat use.
   - With no candidates, Open Service Settings opens the existing settings flow and does not delete or alter the chat.
   - Delete requires confirmation and clears the selected chat safely.
   - Enlarged text does not clip status/action labels.

Record exact PASS/FAIL results in `implementation-log.md`; `NOT TESTABLE` is evidence, not a pass.

## Current implementation evidence

- Project-file lint and changed-source syntax parsing passed.
- On 2026-08-11, the focused in-memory unit target (including the configuration idempotency case) and the isolated recovery UI target both exited successfully. The UI run emitted an Xcode debugger-version-store warning but no test failure.
- Manual VoiceOver, keyboard traversal, non-colour, and enlarged-text validation remains required and is not represented as an automated pass.

## Build and Full Regression

```zsh
set -o pipefail
xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build \
  2>&1 | tee /tmp/warden-persistence-build.log

set -o pipefail
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' \
  2>&1 | tee /tmp/warden-persistence-full-tests.log
```

## Privacy Check

Before queue completion, inspect changed source and fixtures to confirm:

- no `TokenManager` retrieval, API key, authorization header, prompt, or full message body is added to recovery UI/logs;
- no new network call, telemetry, analytics, or sync path was introduced;
- unavailable chats are retained, and automatic loading has no `delete` operation for missing/invalid service classification;
- any error text is non-sensitive and does not contain raw Core Data error payloads or local filesystem paths.
