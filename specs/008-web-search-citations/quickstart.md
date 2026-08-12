# Verification Quickstart: Web Search and Citations

Run all commands from repository root.

## Focused deterministic tests

```bash
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' \
  -only-testing:WardenTests/TavilySearchServiceTests \
  -only-testing:WardenTests/MessageManagerSearchTests \
  -only-testing:WardenTests/MessageSearchMetadataTests
```

Tests must use injected/stubbed URL loading and Keychain boundaries; they must not contact Tavily or require a real credential.

The focused suite now covers Tavily HTTPS/HTTP/malformed URL actionability, citation slot alignment (including multi-byte text), sanitized transport errors, search failure without provider invocation, raw-prompt request isolation, and absent/legacy/message-owned metadata decoding. Search cancellation remains a manual UI verification: `MessageManager` has an injected Tavily service and stream dispatcher, but the UI-owned pending-message deletion/recovery state is not exposed as a deterministic XCTest seam.

## Manual native macOS workflow

1. Launch the app and open a chat.
2. Enable the globe control for the first time. Confirm the disclosure says the current query goes to Tavily and can open Web Search preferences.
3. With no key, attempt a search. Confirm an actionable error appears and the prompt remains unsent.
4. Choose Disable Search. Confirm the unchanged prompt returns to the composer and does not send automatically.
5. Configure a test/stubbed search result. Send a web-assisted prompt and verify source metadata appears under the assistant response.
6. Verify valid standalone `[1]` opens only an HTTPS source; malformed, HTTP, custom-scheme, and out-of-range citations remain non-actionable text.
7. Relaunch and confirm source metadata remains with the local conversation. Delete that conversation and confirm it is removed with the messages.

## Required project gates

```bash
xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'
```

Before merge, inspect changed logs, fixtures, persisted JSON, and preferences to confirm no API key or private query is accidentally stored or emitted.

## Automated verification evidence (2026-08-12)

The following commands completed in the normal local Xcode environment:

```bash
xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build

xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' \
  -only-testing:WardenTests/TavilySearchServiceTests \
  -only-testing:WardenTests/MessageManagerSearchTests \
  -only-testing:WardenTests/MessageSearchMetadataTests
```

The build and focused deterministic suite reported success. The focused run also included the existing `MessageManagerStreamingTests` regression target, which passed.

The complete `xcodebuild test` suite was run twice and remains **not green** because the pre-existing `ChatHistoryRecoveryTests.testMalformedAttachmentReferencesRemainReadOnlyAndDoNotDeleteHistory()` test-host process crashes with `EXC_BAD_ACCESS` in `clearFixtureEntities()` while calling `NSManagedObjectContext.deleteObject:`. The Feature 8 source does not modify that test or the Core Data model. The app-shell UI test that failed during the first full run passed when run alone and during the final full-suite attempt. Treat the complete-suite gate as blocked until the Core Data test-host crash is resolved.

Manual native UI scenarios remain required because they need an interactive configured app and deliberate verification of disclosure, retry/disable recovery, cancellation, and browser-opening behavior. An ad-hoc temporary verification script checked that `SearchResultsPreviewView` gates browser actions and pointer affordance through the shared strict HTTPS validator; this is supplemental evidence, not a suite result.
