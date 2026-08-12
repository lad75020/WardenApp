# Verification Quickstart: Chat Organization and Sharing

All verification runs locally and does not require a provider API key.

## 1. Focused XCTest coverage

Run the focused in-memory Core Data tests:

```bash
xcodebuild test -project Warden.xcodeproj -scheme Warden \
  -destination 'platform=macOS' \
  -only-testing:WardenTests/ChatHistoryRecoveryTests \
  -only-testing:WardenTests/ChatSharingServiceTests \
  -only-testing:WardenTests/ChatBranchingManagerTests
```

Expected checks:

- Search matches title, system instruction, persona, and message body; a cancelled/stale request cannot overwrite the active query.
- A branch preserves source settings and copied history only through the selected message, leaving source messages unchanged.
- Markdown, text, and JSON contain complete selected context in chronological order and no credential/header material.
- Filename sanitization/temporary output failure does not alter persisted data.

## 2. Build

```bash
xcodebuild -project Warden.xcodeproj -scheme Warden \
  -destination 'platform=macOS' build
```

## 3. Full regression suite

```bash
xcodebuild test -project Warden.xcodeproj -scheme Warden \
  -destination 'platform=macOS'
```

## 4. Manual native macOS smoke test

1. Launch a debug build with locally seeded/sample chats in at least one active and archived project.
2. Command-F into sidebar search. Verify matches by title, system instruction, persona, and message text; clear with Escape.
3. Pin a chat and confirm it appears before date groups. Open archived projects and verify data remains accessible.
4. Create a branch at both a user and assistant message. Confirm the original is unchanged and the new chat opens with only the expected history.
5. Open the share menu; copy, export, and share each supported format. Inspect output for full metadata, system instruction when present, chronological messages, and absence of credentials/authorization data.
6. Cancel the save panel and verify no destination file is created. Simulate/observe a write failure if practical; verify a safe error and no chat mutation.
7. Enable VoiceOver or use keyboard navigation to confirm action labels, focused search, menu access, and dismissal/retry controls.

## Privacy Review

- No remote request is triggered by sidebar search, organization, local project summary, copy, or save.
- Native sharing is only launched from an explicit user selection; its transient input file is removed when the picker is dismissed without choosing a service, after a share callback, or after a bounded five-minute fallback expiry if AppKit provides no callback.
- No API key, authorization header, or private chat body appears in diagnostics beyond the explicit user-exported content.

## Recorded Evidence (2026-08-12)

- Focused feature XCTest: **TEST SUCCEEDED** using an isolated DerivedData path. It exercised chat-history recovery, local search predicates, sharing/export including picker-cancellation cleanup, and branch-manager contracts with in-memory Core Data and no provider credentials.
- Build: `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -derivedDataPath /private/tmp/warden-verify-derived build` returned **BUILD SUCCEEDED** after the final feature edits.
- Full regression suite: a fresh retry of `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -derivedDataPath /private/tmp/warden-verify-derived test` returned **TEST SUCCEEDED**. A preceding full run had one transient timeout in `AppShellUITests.testMalformedImportShowsNonDestructiveFeedback`; the same test passed in isolation, and the full retry passed with no unexpected failures.
- Ad-hoc verification: a temporary `hermes-verify-` script checked deterministic export ordering, exclusion of representative tool-call/authorization diagnostics, unique mode-600 temporary output, and branch navigation injection; it passed and was removed. This is ad-hoc verification, not suite-green evidence.
- Remaining human checks: execute the manual native macOS smoke test above for Command-F/Escape, archived-project expansion, save-panel cancellation, share picker behavior, and VoiceOver/keyboard traversal. These interactions were not automated.
