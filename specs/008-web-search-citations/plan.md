# Implementation Plan: Web Search and Citations

**Branch**: `feature/time-machine-web-search-and-citations` | **Date**: 2026-08-12 | **Spec**: [spec.md](spec.md)
**Input**: Clarified feature specification from `specs/008-web-search-citations/spec.md`

## Summary

Extend WardenApp’s existing Tavily web-search path so a user can explicitly opt into search for one chat request, see a cancellable lifecycle, receive a privacy-safe actionable failure without auto-sending their prompt, and retain message-owned sources/citations after reload. The smallest architecture-aligned approach keeps Tavily transport in `TavilySearchService`, coordinates request-scoped search state in `MessageManager`, persists the existing metadata JSON only with the matching assistant response, and updates native SwiftUI controls to disclose sharing once, recover unsent prompts, and open only validated HTTPS destinations.

## Technical Context

**Language/Version**: Swift 5.9
**Primary Frameworks**: SwiftUI, AppKit, Foundation, Core Data, Security/Keychain
**Persistence**: Existing optional `MessageEntity.searchMetadataJson` through `ChatStore`/Core Data; Tavily key through `TavilyKeyManager`/Keychain; local preference only for one-time disclosure acknowledgement
**Testing**: XCTest (`WardenTests/`) and targeted XCUITest/manual native workflow (`WardenUITests/`)
**Target Platform**: Native macOS 26.0
**Project Type**: Xcode macOS application with unit/UI test targets and auxiliary CLI target
**Build Command**: `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`
**Test Command**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'`
**Performance Goals**: Keep search asynchronous and cancellable; never block the main actor or ordinary composition; dismiss terminal progress promptly.
**Constraints**: Privacy-first, no telemetry, Keychain secrets only, only current query leaves device when enabled, request-scoped/cancellable streaming, actor-safe UI, no live credentials/network in tests.
**Scale/Scope**: Existing Tavily service/models, message send/persistence path, chat input/error/source UI, focused unit tests, and a focused accessibility/manual UI workflow; no search-provider switching or Core Data schema change.

## Constitution Check

*GATE: Passed before research; re-checked after design.*

- [x] Native macOS and privacy-first behavior is preserved: SwiftUI/AppKit remains native; only an explicitly enabled current query is sent to Tavily.
- [x] Each changed file belongs to its documented module: UI in `Warden/UI`, types in `Warden/Models`, service/coordination in `Warden/Utilities`, tests in `WardenTests`/`WardenUITests`.
- [x] Provider work conforms to `APIProtocol` and uses existing factory/base abstractions: no provider handler/factory change; Tavily remains a focused pre-provider utility.
- [x] Secrets remain in Keychain and are excluded from Core Data, fixtures, preferences, and logs.
- [x] Core Data changes include migration and existing-user compatibility analysis: no schema change; existing optional JSON continues to decode as `nil` when absent/malformed.
- [x] Async/streaming work has cancellation, failure, and actor-safety behavior: request-scoped search outcome, terminal status cleanup, and late-callback isolation are planned.
- [x] Focused XCTest/XCUITest coverage is identified and does not require paid credentials.
- [x] No new dependency or broad abstraction is added; existing service and persistence seams are extended.

**Post-design result**: All gates remain satisfied. No constitution violation or complexity exception is required.

## Architecture Impact

### Affected Modules

| Module | Path | Planned responsibility/change |
|---|---|---|
| App entry/config | `Warden/Configuration/AppConstants.swift` | Add a namespaced local preference key only if one is absent for disclosure acknowledgement. |
| UI / view models | `Warden/UI/Chat/ChatView.swift`, `Warden/UI/Chat/BottomContainer/MessageInputView.swift`, `Warden/UI/Chat/Components/SearchErrorView.swift`, `Warden/UI/Chat/Components/MessageSourcesView.swift`, `Warden/UI/Chat/Components/CitationBadgeView.swift` | One-time disclosure; pending failed-send recovery; status/error actions; accessible HTTPS-only source/citation affordances. |
| Shared models | `Warden/Models/SearchModels.swift`, `Warden/Models/Models.swift` | Add only focused request/outcome or URL-validation value types if needed; preserve metadata JSON compatibility. |
| Services/managers | `Warden/Utilities/TavilySearchService.swift`, `Warden/Utilities/MessageManager.swift`, `Warden/Utilities/TavilyKeyManager.swift` | Sanitize error mapping; produce request-scoped search result; validate citation destinations; attach metadata only to matching persisted assistant response; preserve cancellation. |
| Provider handlers | `Warden/Utilities/APIHandlers/` | No direct change; existing provider requests receive search context only for the associated enabled send. |
| Persistence | `Warden/Models/Models.swift`, existing `ChatStore` behavior | No model/schema migration; retain optional JSON with message/conversation and remove through existing deletion. |
| MCP | `Warden/Core/MCP/` | No change. |
| Unit tests | `WardenTests/Utilities/TavilySearchServiceTests.swift`, `WardenTests/Utilities/MessageManagerSearchTests.swift`, `WardenTests/Persistence/MessageSearchMetadataTests.swift` | Deterministic URL, citation, error, search lifecycle/isolation, and metadata compatibility coverage. |
| UI tests | `WardenUITests/` | Add/update focused disclosure and failed-search recovery coverage where accessibility test seams support it; otherwise execute documented manual verification. |
| CLI/local packages | `MLXZImageSwiftCLI/`, `Packages/` | No change. |

### Dependency Flow

`MessageInputView` owns the per-composer enable gesture and asks `ChatView` to present first-use disclosure before enabling. `ChatView` owns temporary failed-search prompt recovery and passes an enabled send to `ChatViewModel`/`MessageManager`. `MessageManager` derives a request-local query, invokes `TavilySearchService`, publishes `SearchStatus` on the main UI context, injects only the resulting formatted context into the associated existing provider send, and passes the same request-local source data through response persistence. `MessageEntity.searchMetadata` encodes the existing model JSON after the assistant response exists. `ChatBubbleView` renders `MessageSourcesView`, while shared HTTPS validation controls all clickable source/citation actions. Views never own provider transport or direct Core Data access.

### Provider/API Contract

No `APIProtocol`, `APIServiceFactory`, or handler contract changes are planned. Before the existing provider invocation, an enabled request calls:

```swift
func performSearch(query:onStatusUpdate:) async throws -> WebSearchAttempt
```

`WebSearchAttempt` is transient and carries `query`, delimited provider-only context, ordered sources, and HTTPS-valid citation destinations. On search success, `MessageManager` supplies the composed message to the existing `sendMessage`/`sendMessageStream` path. On failure, it reports a sanitized actionable error and does not invoke a provider. On cancellation or stale completion, it clears status and does not persist metadata. Existing streaming session ownership remains authoritative for late response rejection.

### Persistence and Migration

**No Core Data schema change.** `MessageEntity.searchMetadataJson` already stores optional `MessageSearchMetadata`. Persist query, ordered sources, completion time, and result count only after the matching assistant response is created. Old messages with absent metadata continue to return `nil`; malformed legacy JSON remains non-fatal. Existing message/conversation deletion removes the owning data, satisfying retention through conversation deletion. Do not store search context, API keys, disclosure text, or failed pending prompt in Core Data.

### Disclosure Compatibility Design

**No Core Data migration is used.** `ChatEntity` has no acknowledgement field, so the acknowledgement is a local `UserDefaults` boolean keyed as `tavilySearchDisclosureAcknowledged.<chat UUID>`. Both the standard and centered composers instantiate the same `MessageInputView`, which derives this key from its `chat`. The key stores no query or other chat content, applies only while that UUID identifies a retained conversation, and is removed by the supported single-chat, selected/all-chat, project-summary, and invalid-chat deletion paths. Existing global acknowledgement data is intentionally ignored rather than migrated, so every retained conversation obtains its own first-use disclosure.

### Security and Privacy

- Continue using `TavilyKeyManager`/Keychain for the credential; never move it to `UserDefaults`, Core Data, fixtures, or logs.
- First-use disclosure states that only the current enabled request query is sent to Tavily; it links/routes to Web Search preferences.
- Keep unrelated history, attachments, analytics, telemetry, and private chat content out of the Tavily request.
- Map external/network/server errors to non-secret user remediation. Never show raw error bodies or request data that could expose credentials or private content.
- Treat provider-returned URL strings as untrusted. Only absolute `https` URLs with a host can produce clickable citations or `NSWorkspace` opens; all other URLs remain visible plain text.
- Avoid logging query, full search context, credential, authorization header, or raw service payload. Category/count diagnostics only.

## Project Structure

### Feature Documentation

```text
specs/008-web-search-citations/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── web-search-ui-contract.md
└── tasks.md                  # generated in the next SDD phase
```

### Source Paths

```text
Warden/
├── Configuration/
│   └── AppConstants.swift
├── Models/
│   ├── Models.swift
│   └── SearchModels.swift
├── UI/Chat/
│   ├── ChatView.swift
│   ├── BottomContainer/MessageInputView.swift
│   └── Components/{SearchErrorView,MessageSourcesView,CitationBadgeView}.swift
└── Utilities/
    ├── MessageManager.swift
    ├── TavilyKeyManager.swift
    └── TavilySearchService.swift

WardenTests/
├── Utilities/{TavilySearchServiceTests,MessageManagerSearchTests}.swift
└── Persistence/MessageSearchMetadataTests.swift

WardenUITests/
└── WebSearchFlowUITests.swift  # only if deterministic UI seams exist
```

**Structure Decision**: Extend existing focused types instead of creating a cross-cutting search framework. URL validation belongs in a shared focused model/utility accessible by citation conversion and source views; request coordination belongs in `MessageManager`; native disclosure/recovery state belongs in chat UI. Tests are isolated by service, manager, persistence, and UI boundary.

## Test and Verification Plan

1. **Regression first**: Add failing deterministic tests for HTTPS-only URL acceptance, valid/invalid citation behavior, sanitized error mapping, and metadata not attaching across failed/cancelled/replaced sends.
2. **Focused unit tests**: Run `TavilySearchServiceTests`, `MessageManagerSearchTests`, and `MessageSearchMetadataTests` with injected `URLSession`/`URLProtocol` responses and isolated Core Data. No test may read a real key or contact Tavily.
3. **UI workflow**: XCUITest where accessible; otherwise follow `quickstart.md` to verify first-enable disclosure, status, failure retry, disable-search composer restoration, source expansion, accessibility labels, and only HTTPS openings.
4. **Build**: Run `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`.
5. **Full tests**: Run `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'` before merge; report real environment blockers only.
6. **Privacy review**: Inspect changed Keychain, preference, error, log, request, and metadata paths; confirm no key/query/raw response leaks and no Core Data migration was accidentally introduced.

## Delivery Phases

### Phase 0 — Research and Risk Reduction

Completed in [research.md](research.md): confirm existing boundaries, request isolation strategy, no-schema metadata retention, HTTPS validation, one-time disclosure, deterministic test seams, and non-live network testing.

### Phase 1 — Models, Contracts, and Persistence

1. Create a focused request-scoped search outcome and/or shared HTTPS source validator without breaking public metadata decoding.
2. Refactor citation conversion to accept only validated same-message HTTPS destinations and preserve invalid text.
3. Make assistant persistence accept the request-local search metadata rather than mutable manager-wide last-search state.
4. Add compatibility tests for absent/legacy metadata and message-owned retention/removal.

### Phase 2 — Services and Provider Integration

1. Make `TavilySearchService` return sanitized, bounded results and terminal lifecycle updates through its injected session.
2. In both streaming and non-streaming sends, create one search transaction; inject its context only into the matching provider request.
3. Map credential, transport, decoding, rate-limit, and server failures to non-sensitive user remediation.
4. Respect cancellation/session invalidation, clear terminal progress, and prevent late search/provider callbacks from attaching sources elsewhere.

### Phase 3 — Native macOS UI

1. Add the first-enable privacy disclosure with Continue, Preferences, and Cancel paths.
2. Preserve failed search prompts; Retry reuses the prompt, while Disable Search returns it to the composer and requires explicit send.
3. Update source and citation controls for keyboard/accessibility and HTTPS-only actionability; retain readable non-actionable URL text.
4. Ensure progress/error presentation does not block composition or cancellation and clears reliably.

### Phase 4 — Verification and Documentation

1. Execute focused deterministic tests, build, then full tests.
2. Follow `quickstart.md` manual UI verification when necessary.
3. Review logs, persistence, Keychain boundaries, preferences, and URLs for privacy/security compliance.
4. Update user-facing guidance only if the implemented UI makes current preference copy inaccurate.

## Complexity Tracking

No Constitution Check gate is intentionally violated.

## Verification Evidence (2026-08-12)

- `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build` completed successfully in the normal local Xcode environment.
- The focused deterministic suite for `TavilySearchServiceTests`, `MessageManagerSearchTests`, and `MessageSearchMetadataTests` completed successfully with injected URL-loading fixtures and no real Tavily credential.
- The existing `MessageManagerStreamingTests` target passed when included with the focused Feature 8 suite. The complete suite was run twice but remains blocked by a pre-existing Core Data test-host crash in `ChatHistoryRecoveryTests.testMalformedAttachmentReferencesRemainReadOnlyAndDoNotDeleteHistory()` (`EXC_BAD_ACCESS` in `clearFixtureEntities()` while deleting a managed object). The Feature 8 source does not modify that test or the Core Data model. The isolated app-shell UI test and the final full-suite UI run passed.
- Manual scenarios in `quickstart.md` remain required; they were not claimed as automated evidence. A temporary ad-hoc static verification checked that search-preview browser affordances use the shared strict HTTPS validator; it is supplemental, not a test-suite gate.
