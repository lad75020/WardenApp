# Implementation Plan: Chat Organization and Sharing

**Branch**: `feature/time-machine-chat-organization-and-sharing` | **Date**: 2026-08-12 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `specs/009-chat-organization-sharing/spec.md`

## Summary

Complete the existing native macOS chat organization and sharing surface through a focused reliability and regression pass. Retain the current Core Data model, sidebar search/grouping, local project summary, branch UI/manager, and share menu. Strengthen test seams and deterministic coverage, harden export/share temporary-file and failure behavior, make accessibility semantics explicit in touched controls, and verify that all disclosure remains user initiated and local-first.

## Technical Context

**Language/Version**: Swift 5.9  
**Primary Frameworks**: SwiftUI, AppKit, Core Data, Foundation  
**Persistence**: Existing Core Data `ChatEntity`, `MessageEntity`, and `ProjectEntity`, coordinated by `ChatStore` and `PersistenceController`; Keychain remains the only secret store  
**Testing**: XCTest in `WardenTests/` with `PersistenceController(inMemory: true)` fixtures; focused manual macOS UX validation; XCUITest only where test identifiers and stable launch data are available  
**Target Platform**: Native macOS 26.0  
**Project Type**: Xcode macOS application with unit/UI test targets and an auxiliary CLI target  
**Build Command**: `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`  
**Test Command**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'`  
**Performance Goals**: Search applies the active local query within one second after typing settles, without blocking the main actor; no additional remote work  
**Constraints**: Privacy-first, no telemetry, no Core Data schema change, no new package/dependency, user-controlled copy/save/share disclosure, existing provider behavior unchanged  
**Scale/Scope**: Existing chat search, pin/project/archive UI, local project summary, branch manager/popover, three existing export formats, focused unit tests, and native smoke verification

## Constitution Check

*GATE: Passed before research and re-checked after design.*

- [x] Native macOS and privacy-first behavior is preserved: all UI remains SwiftUI/AppKit and no new network/telemetry path is introduced.
- [x] Each changed file belongs to its documented module: UI changes stay under `Warden/UI/`; share/branch logic stays under `Warden/Utilities/`; tests stay under `WardenTests/`.
- [x] Provider work conforms to `APIProtocol` and uses existing factory/base abstractions: no provider contract change is planned; branches use the existing `APIServiceFactory` path.
- [x] Secrets remain in Keychain and are excluded from Core Data, fixtures, exports, temporary files, and logs.
- [x] Core Data changes include migration and existing-user compatibility analysis: no schema/model change; existing entities are read in place.
- [x] Async/streaming work preserves cancellation, failure, and actor safety: preserve existing cancellable search and `@MainActor` branch manager; do not move managed objects across contexts.
- [x] Focused XCTest coverage is identified and does not require paid credentials.
- [x] No new dependency or abstraction is added without a concrete justification: a private export formatter/result is permitted only as a test seam and file-safety boundary.

## Architecture Impact

### Affected Modules

| Module | Path | Planned responsibility/change |
|---|---|---|
| App entry/config | `Warden/WardenApp.swift` | Use Core Data's `NSInMemoryStoreType` for `PersistenceController(inMemory: true)` so isolated XCTest stores do not race through a shared `/dev/null` SQLite destination. |
| UI / view models | `Warden/UI/ChatList/ChatListView.swift` | Preserve debounced search and keyboard behavior; add only targeted accessibility/error-state fixes found during implementation. |
| UI / view models | `Warden/UI/Chat/BubbleView/ChatBubbleView.swift`, `Warden/UI/Chat/Components/BranchPopover.swift` | Preserve branch invocation/progress/retry/open flow; add labels/hints or correctness fixes only where validated. |
| UI / view models | `Warden/UI/Components/ChatShareMenu.swift` | Retain all three formats for share/copy/export; make labels/hints and service errors clear and accessible. |
| UI / view models | `Warden/UI/Chat/ProjectSummaryView.swift`, `Warden/UI/Chat/ProjectSummaryButton.swift` | Preserve local descriptive activity/statistics; no provider-backed synthesis. |
| Shared models | `Warden/Models/Models.swift` | No schema change; use existing `ChatBackup` only if its JSON export meets the full-context contract. |
| Services/managers | `Warden/Utilities/ChatSharingService.swift` | Make formatting testable, generate sanitized unique temporary output, handle write/picker errors safely, and clean temporary output where possible. |
| Services/managers | `Warden/Utilities/ChatBranchingManager.swift` | Preserve ancestry/copy behavior; add a narrow correctness seam/fix only if focused regression tests reveal one. |
| Provider handlers | `Warden/Utilities/APIHandlers/` | No change. |
| Persistence | `Warden/Store/ChatStore.swift`, Core Data model | No change. Existing persistence supports pin, project/archive, and branch fields. |
| MCP | `Warden/Core/MCP/` | No change. |
| Unit tests | `WardenTests/Persistence/ChatHistoryRecoveryTests.swift` | Host target-member `ChatSharingServiceTests` and `ChatBranchingManagerTests` in the established in-memory Core Data setup; add deterministic export, branch, and safe failure coverage. |
| UI tests | `WardenUITests/` | Manual smoke validation is planned unless stable seeded-data/accessibility identifiers make an existing UI-test path practical. |
| CLI/local packages | `MLXZImageSwiftCLI/`, `Packages/` | No change. |

### Dependency Flow

`ChatListView` owns local query UI state and queries Core Data through a background context, publishing only matching chat IDs to SwiftUI. Existing `ChatStore` remains the coordinator for project and chat creation/persistence. `BranchToolbarButton` presents `BranchPopover`; the popover selects an existing `APIServiceEntity` and asks `ChatBranchingManager` to create/save a branch in the view context. `ChatShareMenu` invokes `ChatSharingService`, which formats an existing `ChatEntity` into a transient representation then either writes the user-selected destination, puts text on the pasteboard, or passes a transient file to `NSSharingServicePicker`. No UI type owns provider transport or Core Data migration logic.

### Provider/API Contract

No new provider/API contract. The current branch continuation keeps this sequence:

1. `BranchPopover` selects an already configured `APIServiceEntity` and model.
2. `ChatBranchingManager` creates the independent branch and saves it before any response generation.
3. For a user-origin branch only, `APIServiceManager.createAPIConfiguration` and `APIServiceFactory` construct the existing handler.
4. Existing streamed/non-streamed `MessageManager` APIs handle completion/failure.

No API key, authorization header, or raw private content may be added to diagnostics or export metadata.

### Persistence and Migration

**No schema change.** Existing fields already cover pinning, project membership, archive state, message order, source settings, and branch ancestry. The plan must preserve existing `ChatEntity`/`MessageEntity` IDs and relationships. A failed branch save rolls back the context; share/export failure must never save or alter conversation data. Existing stores remain compatible with no migration work.

### Security and Privacy

- Search, organization, and project summaries remain entirely local.
- Copy, save, and macOS sharing are explicit user actions; no public link/cloud upload is introduced.
- Exports include the product-selected full conversation scope (metadata, system instruction when present, chronological messages) but exclude API keys, authorization headers, diagnostic state, and non-user-facing secret material.
- Suggested export filenames are sanitized to a filename component; temporary sharing files are unique, safely written, and removed after use where AppKit lifecycle callbacks allow.
- Use `WardenLog` with non-sensitive diagnostics only; never log exported conversation body, system instruction, or secret material.

## Project Structure

### Feature Documentation

```text
specs/009-chat-organization-sharing/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── ui-contracts.md
└── tasks.md
```

### Source Paths

```text
Warden/
├── Models/Models.swift
├── Store/ChatStore.swift
├── UI/
│   ├── Chat/BubbleView/ChatBubbleView.swift
│   ├── Chat/Components/BranchPopover.swift
│   ├── Chat/ProjectSummaryButton.swift
│   ├── Chat/ProjectSummaryView.swift
│   ├── ChatList/ChatListView.swift
│   └── Components/ChatShareMenu.swift
└── Utilities/
    ├── ChatBranchingManager.swift
    └── ChatSharingService.swift

WardenTests/
├── TestSupport/InMemoryChatFixture.swift
└── Persistence/
    └── ChatHistoryRecoveryTests.swift (target-member host for focused sharing/branching test classes)
```

**Structure Decision**: Modify the established focused UI and utility files rather than introduce a new feature module. The current Xcode test target uses explicit source-file membership, so the focused `ChatSharingServiceTests` and `ChatBranchingManagerTests` classes are hosted in the existing target-member `WardenTests/Persistence/ChatHistoryRecoveryTests.swift`; this preserves the requested no-project-file-change scope while reusing the in-memory fixture. No Xcode project file change is expected.

## Test and Verification Plan

1. **Regression first**: Add tests that demonstrate the pre-hardening failure or missing contract: safe suggested filename/temporary creation error, complete chronological exports, and branch source immutability/history boundary.
2. **Focused unit tests**: Use `PersistenceController(inMemory: true)` to seed chat/persona/project/service/messages. Verify export output per format, copy payload through an injectable or pure formatting seam, branch metadata/history, and failure without provider credentials.
3. **UI workflow**: Manually exercise Command-F/Escape, pin/date grouping, archived project expansion, local summary, user/assistant branch flows, all share/copy/save choices, save cancellation, keyboard navigation, and VoiceOver labels. Add/update XCUITest only if existing launch fixtures and identifiers make the checks deterministic.
4. **Build**: Run the documented macOS build command.
5. **Full tests**: Run the documented repository test command before merge; record only actual environment failures.
6. **Privacy review**: Inspect changed log calls and export payloads for secret/header/debug exclusions, confirm no network request from local actions, and ensure temporary output uses safe filename/lifecycle behavior.

## Delivery Phases

### Phase 0 — Baseline and Regression Seams

- Read the relevant target membership and existing in-memory fixture helpers.
- Capture focused tests for existing branch/export contracts before changing code.
- Run the relevant current test target to identify pre-existing blockers.

### Phase 1 — Export/Sharing Reliability

- Refactor only the non-UI formatting/output boundary needed for deterministic XCTest.
- Guarantee full context in plain text, Markdown, and JSON; normalize chronological ordering.
- Sanitize filename input, use unique temporary files, propagate failure before showing a share picker, and clean transient output when possible.
- Preserve native `NSSavePanel`, pasteboard, and `NSSharingServicePicker` ownership and explicit user disclosure.

### Phase 2 — Organization and Branch Regression Hardening

- Confirm `ChatListView` cancellation/published-result behavior and apply a targeted correction only if tests/manual validation expose a stale-result, accessibility, or main-actor flaw.
- Validate `ChatBranchingManager` creates a separate child, copies only selected history, preserves intended settings/context, saves before generation, and leaves the source untouched on all failures.
- Keep project summaries local; tighten empty/loading/accessibility behavior only when needed.

### Phase 3 — Native macOS UI Polish

- Ensure touched buttons and menu rows have meaningful VoiceOver labels/hints, keyboard focus behavior, and no redundant decorative labels.
- Retain native AppKit controls for save/share and SwiftUI `Button`/`Menu` for user actions.
- Do not broadly migrate unrelated visual APIs or introduce Liquid Glass.

### Phase 4 — Verification and Documentation

- Run feature-focused XCTest, build, then full test suite.
- Run the manual smoke and privacy workflow in [quickstart.md](quickstart.md).
- Update only documentation that has become inaccurate from implementation decisions.

## Complexity Tracking

No constitution violation or new dependency is planned.

## Implementation Evidence (2026-08-12)

- Focused XCTest passed for `ChatHistoryRecoveryTests`, `ChatSharingServiceTests`, and `ChatBranchingManagerTests` using in-memory Core Data; no provider credentials or network calls were required. Coverage includes local search matching and temporary share-file cleanup when the picker is cancelled.
- The final build passed with `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -derivedDataPath /private/tmp/warden-verify-derived build`.
- A fresh full retry of `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -derivedDataPath /private/tmp/warden-verify-derived test` passed. A preceding run had one transient timeout in `AppShellUITests.testMalformedImportShowsNonDestructiveFeedback`; it passed in isolation and the retry completed with no unexpected failures.
- An ad-hoc temporary `hermes-verify-` script exercised deterministic export ordering, diagnostic exclusion, unique mode-600 temporary-file behavior, and the branch navigation seam. It passed and was removed; it is supporting verification, not suite-green evidence.
- Native interactive smoke checks for search/archive behavior, save-panel cancellation, share picker, and VoiceOver remain documented in [quickstart.md](quickstart.md) for a human macOS session.
