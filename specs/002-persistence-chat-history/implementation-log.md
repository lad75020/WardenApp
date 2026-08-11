# Implementation Log: Persistence and Chat History

## Inspection and design evidence

- Reviewed `spec.md`, `plan.md`, `research.md`, `data-model.md`, `quickstart.md`, `tasks.md`, and the constitution before implementation.
- Confirmed the former `ChatStore.loadFromCoreData()` and `cleanupInvalidChats()` paths deleted chats whose service was missing or invalid. The implementation now retains those chats and derives availability without a load-time save or delete.
- Reviewed the Core Data model. `ChatEntity.apiService` is optional with a nullify deletion rule, and `messages` is ordered. No schema or migration version change was made.
- The existing app-shell UI-test launch argument selects `PersistenceController(inMemory: true)`. The added recovery fixture uses that seam and contains only fixed local metadata; it does not create a credential or make a network request.

## Implemented behavior

- `ChatStore` classifies service availability, returns only valid repair candidates, remaps only explicitly selected valid candidates, and deletes unavailable chats only through the explicit deletion method.
- JSON import retains a legacy chat whose explicitly named service cannot be found instead of silently attaching a default service.
- Unavailable chats remain visible in the list and message list; their history remains readable while message sending is blocked. The recovery UI supplies textual status, a valid-service picker, settings routing when there are no candidates, and a destructive confirmation.
- The no-candidate action opens the existing Settings window on its API Services tab.
- Recovery/migration diagnostics were narrowed to non-sensitive outcome text. No recovery path reads or renders credentials or message bodies.

## Executed verification

- `set -o pipefail; xcodebuild test -quiet -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/ChatHistoryRecoveryTests 2>&1 | tee /tmp/warden-persistence-unit-tests.log`
  - PASS: 8 tests passed. Coverage includes retained missing/invalid services, explicit remap preservation, candidate filtering, explicit deletion, empty history, stale selection, malformed transformer input, and source-level recovery privacy checks.
- `set -o pipefail; xcodebuild test -quiet -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenUITests/PersistenceRecoveryUITests 2>&1 | tee /tmp/warden-persistence-ui-tests.log`
  - PASS: 2 tests passed. The isolated fixture verifies unavailable status, disabled-send communication, no-candidate settings affordance, delete control, and valid-candidate repair controls.
- `set -o pipefail; xcodebuild build -quiet -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' 2>&1 | tee /tmp/warden-persistence-build.log`
  - PASS (exit status 0). Existing generated-asset and Swift concurrency warnings remain.
- `set -o pipefail; xcodebuild test -quiet -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' 2>&1 | tee /tmp/warden-persistence-full-tests.log`
  - PASS. The full unit and UI test scheme completed, including the focused persistence suites.
- `git diff --check`
  - PASS: no whitespace errors.
- Static privacy review of changed recovery paths found no new secret retrieval, authorization header, full message-body diagnostic, telemetry, analytics, or remote-sync code. The fixed UI fixture URL is local loopback metadata only.

## Manual verification

- T034: NOT TESTABLE by this agent. VoiceOver output, keyboard traversal, non-colour presentation, and enlarged-text layout require a human macOS accessibility pass. This is not a pass.

## Second implementation and reconciliation pass (2026-08-11)

- Reconciled the dirty feature branch against `tasks.md`. Added deterministic in-memory coverage for load ordering, project/persona/service relationships, repeat load, duplicate legacy IDs, idempotent re-import, a named missing service, malformed transformer data, and malformed attachment references. Added an in-memory configuration migration test that proves an existing matching service is reused and an existing chat relationship is not overwritten.
- `ChatStore.saveToCoreData(chats:)` now deduplicates IDs in a single legacy input, returns the actual imported count, and rolls back partial inserted objects if saving fails. A legacy record that explicitly names a missing service remains unavailable rather than being assigned a default service.
- `DatabasePatcher.migrateExistingConfiguration(context:)` now reuses an exact legacy configuration and does not change existing chat-service relationships. It writes a legacy token only through `TokenManager`; the recovery UI has no Keychain/token access.
- UI fixture tests now exercise settings routing, disabled repair before selecting a valid service, repair after selection, cancel-before-delete, and confirmed deletion. The tests use only a fixed in-memory chat and loopback fixture metadata.
- `set -o pipefail; xcodebuild test -quiet -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/ChatHistoryRecoveryTests -only-testing:WardenTests/DatabasePatcherMigrationTests 2>&1 | tee /tmp/warden-feature-002-unit-second-pass.log`
  - PASS (exit status 0). Xcode emitted its multiple-destination warning plus existing generated-asset and Swift concurrency warnings; no test failure was reported.
- `set -o pipefail; xcodebuild test -quiet -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenUITests/PersistenceRecoveryUITests 2>&1 | tee /tmp/warden-feature-002-ui-second-pass.log`
  - PASS (exit status 0). Xcode emitted a debugger-version-store warning while launching, but no test failure.
- `git diff --check`
  - PASS: no whitespace errors after the second pass.
- T008 remains unchecked: no historical failing-before-fix execution was available. T012 remains unchecked because the fixture does not yet model a valid relaunch. T018 remains unchecked because an explicit Keychain-boundary behavior test is still not present. T025 remains unchecked because automated keyboard-focus traversal is not covered. T034 remains unchecked pending human accessibility verification.

## T017/T018 focused test completion attempt (2026-08-11)

- Extended `ChatHistoryRecoveryTests` with fixed legacy IDs for deterministic duplicate-input/idempotent import and missing named-service retention. The failed-save fixture now proves rollback leaves no chat and that a fresh, normal `ChatStore` can retry and import the same legacy record exactly once while retaining its missing-service state.
- Extended `DatabasePatcherMigrationTests` to prove the existing matching configuration patch is idempotent, preserves the chat relationship, and leaves an empty legacy token outside the Keychain boundary. A separate source-boundary test asserts `DatabasePatcher` delegates the one migration write to `TokenManager.setToken` and has no direct Keychain, token-read, or token-delete use. These tests use no live token or network access.
- `xcodebuild test -quiet -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/ChatHistoryRecoveryTests -only-testing:WardenTests/DatabasePatcherMigrationTests`
  - BLOCKED before compilation: sandboxed Xcode could not write the existing SwiftPM/Clang caches under `/Users/laurent/.cache/clang` and `/Users/laurent/Library/Caches/org.swift.swiftpm`.
- Retried with `CLANG_MODULE_CACHE_PATH=/tmp/warden-clang-module-cache` and `-derivedDataPath /tmp/warden-derived-data`.
  - BLOCKED before compilation: the clean derived-data location required resolving package dependencies, but network access is unavailable (`Could not resolve host: github.com`). No tests ran and this is not a test failure.
- T017 and T018 remain unchecked pending a focused XCTest run in an environment with the already-resolved package cache available. T008, T034, and the Time Machine queue were not modified.

## T017/T018 verified completion (2026-08-11)

- Hermes-configured XcodeMCP `BuildProject` completed successfully in 23.461 seconds with no build errors.
- XcodeMCP's cached test inventory did not expose the newly added methods, so the repository's canonical focused `xcodebuild` fallback was used for execution.
- `set -o pipefail; xcodebuild test -quiet -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:WardenTests/ChatHistoryRecoveryTests/testLegacyJSONImportIsIdempotentAndRetainsMissingNamedService -only-testing:WardenTests/ChatHistoryRecoveryTests/testFailedLegacyImportRollsBackPartialInserts -only-testing:WardenTests/DatabasePatcherMigrationTests/testExistingConfigurationPatchIsIdempotentWithoutTouchingChatRelationshipsOrKeychain -only-testing:WardenTests/DatabasePatcherMigrationTests/testConfigurationMigrationUsesTokenManagerAsItsOnlyKeychainBoundary 2>&1 | tee /tmp/warden-feature-002-t017-t018-final.log`
  - PASS (exit status 0): all four selected T017/T018 tests ran without a reported failure.
- A broader focused-suite run exposed an existing intermittent process exit in `testMalformedAttachmentReferencesRemainReadOnlyAndDoNotDeleteHistory`; that older test passes when selected alone. This does not alter the passing T017/T018 result and remains documented rather than hidden.
- T017 and T018 are complete. T008 remains unchecked because a historical pre-fix failure cannot be recreated honestly, and T034 remains pending the required human accessibility pass.

## T012/T025 focused UI-test attempt (2026-08-11)

- Added a deterministic valid-history UI fixture that uses a unique temporary Core Data store only when the dedicated persistence-recovery test launch argument is present. It seeds fixed local chat, service, and message metadata; it has no credential and makes no request. The fixture is retained through terminate/relaunch so the test can assert the same chat and ordered history are restored from the store rather than reseeded in memory.
- Extended the existing unavailable-workflow UI coverage with assertions for the disabled-send communication, repair selector and disabled/enabled repair state, API Services settings route, cancel and confirmed delete flow, accessible control labels, and actual Tab navigation from the repair picker to the repair button using `hasKeyboardFocus`.
- Attempted focused execution:
  `set -o pipefail; xcodebuild test -quiet -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:WardenUITests/PersistenceRecoveryUITests 2>&1 | tee /tmp/warden-feature-002-t012-t025-ui.log`
  - BLOCKED before compilation. The sandbox denied writes to the existing module and SwiftPM caches at `/Users/laurent/.cache/clang/ModuleCache` and `/Users/laurent/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading`; Xcode consequently could not load the standard library while resolving packages. No UI test ran.
- T012 and T025 remain unchecked until this focused suite runs successfully in an environment with writable resolved-package caches. T008, T034, the Time Machine queue, commits, and pushes were not changed.
