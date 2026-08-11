# Implementation Plan: Persistence and Chat History

**Git Branch**: `feature/time-machine-persistence-and-chat-history` | **Spec Kit ID**: `002-persistence-chat-history` | **Date**: 2026-08-11 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `specs/002-persistence-chat-history/spec.md`

## Summary

Preserve Warden’s locally stored chats instead of deleting them when their linked service is missing or unusable. The smallest architecture-aligned implementation keeps Core Data as the source of truth: classify each chat’s service availability during restoration, retain unavailable chats, and add explicit recovery actions that either remap the chat to a user-selected existing valid service or delete it after confirmation. If there is no valid service, recovery routes to the existing service-settings workflow. Existing Core Data relationships already represent the required unavailable state through the optional `ChatEntity.apiService` relationship, so this plan does not introduce a schema version or migration.

## Technical Context

**Language/Version**: Swift 5.9  
**Primary Frameworks**: SwiftUI, AppKit, Foundation, Core Data  
**Persistence**: `Warden/Store/ChatStore.swift` with `PersistenceController`; Keychain through `TokenManager` for service credentials  
**Testing**: XCTest (`WardenTests/`) and XCUITest (`WardenUITests/`) using deterministic in-memory Core Data fixtures; no paid credentials  
**Target Platform**: Native macOS 26.0  
**Project Type**: Xcode macOS application with unit/UI test targets and an auxiliary CLI target  
**Build Command**: `set -o pipefail; xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build 2>&1 | tee /tmp/warden-persistence-build.log`  
**Test Command**: `set -o pipefail; xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' 2>&1 | tee /tmp/warden-persistence-test.log`  
**Performance Goals**: Restore and classify history without a main-thread blocking full scan; use the existing Core Data context queue and preserve current batched-fetch behavior.  
**Constraints**: Local-only, no telemetry, no secrets outside Keychain, no chat content or token values in diagnostics, explicit destructive actions only, actor-safe UI state.  
**Scale/Scope**: Existing Core Data entities and relationships; `ChatStore` restoration and JSON migration path; a focused unavailable-chat recovery presentation; focused unit/UI regression tests.

## Constitution Check

*Pre-design: PASS. Post-design: PASS. No intentional violation or new dependency is proposed.*

- [x] Native macOS and privacy-first behavior is preserved.
- [x] Each changed file belongs to its documented module.
- [x] No provider protocol or handler behavior changes; existing service configuration remains the authority.
- [x] Secrets remain in Keychain and are excluded from Core Data, fixtures, and logs.
- [x] No Core Data schema change is required; existing optional relationship semantics and JSON-import compatibility are assessed.
- [x] Restoration continues on the Core Data context queue; UI changes remain main-actor safe.
- [x] Focused XCTest and XCUITest coverage is planned without paid credentials.
- [x] No new dependency or general abstraction is added.

## Architecture Impact

### Affected Modules

| Module | Path | Planned responsibility/change |
|---|---|---|
| App entry/config | `Warden/WardenApp.swift` | Preserve transformer registration, patch ordering, persistent-history options, and in-memory fallback; no new app-wide persistence ownership. |
| UI / view models | `Warden/UI/Chat/ChatView.swift`, new focused recovery view under `Warden/UI/Chat/` | Display an unavailable chat safely, disable sending, provide keyboard/VoiceOver-accessible repair and delete actions, and route no-service recovery to existing settings. |
| Shared models | `Warden/Models/Models.swift`, `Warden/Models/MessageContent.swift`, `Warden/Models/RequestMessagesTransformer.swift` | Preserve current chat/message and secure transformer compatibility; add tests only unless an implementation discovery identifies a minimal decoding guard. |
| Services/managers | `Warden/Utilities/DatabasePatcher.swift` | Preserve idempotent configuration patches and Keychain token migration; do not broaden provider configuration behavior. |
| Provider handlers | `Warden/Utilities/APIHandlers/` | No change. Provider handlers remain independent of recovery UI. |
| Persistence | `Warden/Store/ChatStore.swift`, `Warden/Store/wardenDataModel.xcdatamodeld/` | Replace destructive invalid-chat filtering with availability classification, valid-service lookup, explicit remapping, and deliberate deletion. No model XML change is planned. |
| MCP | `Warden/Core/MCP/` | No change. |
| Unit tests | new focused files under `WardenTests/Persistence/` | Cover restoration, idempotency, missing/invalid service classification, remapping, no-service outcome, transformer compatibility, and no automatic deletion. |
| UI tests | new or extended files under `WardenUITests/Persistence/` | Seed deterministic unavailable-chat state and validate visible unavailable state, keyboard-accessible repair/delete affordances, successful remapping, and settings route when no valid service exists. |
| CLI/local packages | `MLXZImageSwiftCLI/`, `Packages/` | No change. |

### Dependency Flow

`ChatList/ChatView` → focused recovery presentation / `ChatViewModel` → `ChatStore` availability and mutation operations → `NSManagedObjectContext` and existing `APIServiceManager` validation → Core Data. The UI may request the existing settings window only through the current application settings route; it must not create provider configuration or access Keychain. `ChatStore` remains the coordinator for persisted-chat lifecycle operations. Provider handlers remain untouched.

### Provider/API Contract

No network or `APIProtocol` contract changes. A service is considered selectable for repair only when the existing `APIServiceManager.createAPIConfiguration(for:)` can construct its configuration. Selection changes the persisted chat-to-service relationship and does not read, display, or move Keychain credentials.

### Persistence and Migration

- **Core Data schema**: No model XML change. `ChatEntity.apiService` is already an optional, nullifying relationship and represents a missing-service unavailable chat without a data migration.
- **Load behavior**: Replace `loadFromCoreData()`’s current deletion of chats with missing or invalid service configurations. It must return/publish the retained history and classify availability without saving a cleanup deletion.
- **Explicit repair**: On the context queue, validate the selected existing service, assign it to the target chat, preserve messages/request messages/project/persona/timestamps, save with the existing retry/error convention, and re-evaluate availability.
- **Explicit delete**: Use the existing confirmed deletion path only after the user chooses it; clear stale selected-chat state before access to a deleted object.
- **Existing JSON import**: Preserve `migrateFromJSONIfNeeded()` idempotency: skip already-completed migration, do not remove the legacy file or set its completion key when import fails, and never manufacture duplicate chat IDs. An imported chat without a resolvable service remains unavailable instead of being discarded.
- **Store-load failure**: Preserve `PersistenceController`’s existing in-memory fallback as an availability/recovery message. Do not overwrite the failed store or disclose private content, credentials, or raw storage paths in user-facing UI/logs.

### Security and Privacy

- `APIServiceEntity` retains only non-secret service metadata; `TokenManager`/Keychain remains credential authority.
- No repair screen may show, serialize, log, or copy an API key, authorization header, prompt, or full message body.
- Diagnostic events use `WardenLog` with aggregate/state metadata only (for example, availability transition or save failure category), never chat body/name/UUID, token, URL query, or raw Core Data error payload.
- No data leaves the device and no telemetry, analytics, export, or sync behavior is added.

## Project Structure

### Feature Documentation

```text
specs/002-persistence-chat-history/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── persistence-recovery-ui-contract.md
└── tasks.md
```

### Source Paths

```text
Warden/
├── Models/
│   ├── Models.swift
│   ├── MessageContent.swift
│   └── RequestMessagesTransformer.swift
├── Store/
│   ├── ChatStore.swift
│   └── wardenDataModel.xcdatamodeld/
├── UI/
│   ├── Chat/
│   │   ├── ChatView.swift
│   │   └── UnavailableChatRecoveryView.swift
│   └── Preferences/
│       └── existing service settings flow
└── Utilities/
    └── DatabasePatcher.swift

WardenTests/Persistence/
WardenUITests/Persistence/
```

**Structure Decision**: Keep availability classification and Core Data mutations in `ChatStore`; keep presentation and accessibility in a new small chat UI view; reuse the existing service settings route rather than building provider configuration UI. Do not change Core Data model XML unless implementation proves the current optional service relationship cannot distinguish required states; any such discovery is a gate requiring plan/spec update before modification.

## Test and Verification Plan

1. **Regression first**: Add a unit test showing that a persisted chat with no service or an invalid service survives `loadFromCoreData()` and is classified unavailable; it must fail against the current destructive behavior.
2. **Focused unit tests**: Add `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` covering valid history, missing service, invalid service, remap to a valid service, no-valid-service result, second-load idempotency, preservation of messages/project/persona/request messages, and explicit delete. Add transformer/message-content compatibility tests only for affected behavior. Run the concrete `-only-testing` suite discovered from Xcode after files are added.
3. **UI workflow**: Add deterministic XCUITest fixture launch support under `WardenUITests/Persistence/`; validate unavailable state text, disabled sending, VoiceOver labels, keyboard focusability, repair selection, no-service settings route, and confirmed delete. Perform the required manual macOS accessibility pass before completion.
4. **Build**: Run the documented `xcodebuild` build command with `set -o pipefail`.
5. **Full tests**: Run the documented full test command before merge; record any real environment blocker verbatim.
6. **Privacy review**: Inspect changed persistence/recovery diagnostics and any test fixtures for tokens, chat body logging, telemetry, remote requests, and build artifacts.

## Delivery Phases

### Phase 0 — Research and Risk Reduction

Confirm the current failure modes: Core Data load currently deletes invalid chats; the optional `apiService` relationship already represents absence; JSON import associates a matching/default service; service migration moves legacy tokens to Keychain. Verify existing settings-navigation and XCUITest fixture seams before editing.

### Phase 1 — Models, Contracts, and Persistence

Add the availability and recovery contract, replace destructive loading, ensure imports retain unresolvable chats, expose valid-service lookup and guarded remapping/deletion through `ChatStore`, and add unit coverage. Preserve schema and transformer registration unless test evidence identifies an unrelated existing defect that blocks this feature.

### Phase 2 — Services and Provider Integration

No provider handler work. Reuse `APIServiceManager` validation and existing service settings rather than adding a new configuration service or network request.

### Phase 3 — Native macOS UI

Add unavailable-chat state to the chat presentation and a focused recovery view. Offer user-confirmed delete and repair-to-existing-service only; route the empty-service case to existing settings. Provide descriptive accessibility labels, deterministic focus order, and non-color status communication.

### Phase 4 — Verification and Documentation

Run focused tests, build, full tests, privacy review, and manual accessibility verification. Record actual commands/results and manual outcomes in the implementation log; then update the Time Machine queue only after all required evidence passes.

## Complexity Tracking

No constitution gates are intentionally violated.
