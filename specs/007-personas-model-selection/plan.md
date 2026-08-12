# Implementation Plan: Personas and Model Selection

**Branch**: `feature/time-machine-personas-and-model-selection` | **Date**: 2026-08-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/007-personas-model-selection/spec.md`

## Summary

Complete the existing native macOS persona and model-selection experience without adding a provider, network API, dependency, or Core Data schema change. Persona selection will update only the reusable persona relationship so its existing system-message and temperature behavior applies to later requests. A persona's default service becomes a separate, explicit action that validates the exact configured provider/model before an atomic chat update. Model dropdown, quick-access favorites, and persona default-service changes will share one validated chat-configuration mutation path; model identity will be provider-plus-model rather than ambiguous string concatenation.

## Technical Context

**Language/Version**: Swift 5.9
**Primary Frameworks**: SwiftUI, Core Data, Foundation, AppKit where existing alert/presentation patterns require it
**Persistence**: Existing Core Data entities (`ChatEntity`, `PersonaEntity`, `APIServiceEntity`) and existing local non-secret favorite preference; Keychain remains the secret store
**Testing**: XCTest (`WardenTests/`) with an isolated/in-memory Core Data store; XCUITest (`WardenUITests/`) only if deterministic launch fixtures/accessibility identifiers can cover the popover workflow
**Target Platform**: Native macOS 26.0
**Project Type**: Xcode macOS application with unit/UI test targets and an auxiliary CLI target
**Build Command**: `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS,arch=arm64' build`
**Test Command**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS,arch=arm64'`
**Performance Goals**: Filter a local fixture catalog of 500 models without blocking interaction; search remains debounced; no catalog/metadata fetch from row rendering or hover
**Constraints**: Privacy-first and local-only state; no telemetry; secrets remain in Keychain; no prompt/content/credential logging; actor-safe SwiftUI state; preserve existing message-manager recreation and provider behavior
**Scale/Scope**: Existing persona editor/selector, model selector, favorite quick access, model metadata display, selection/favorite utilities, focused tests; no provider handler, streaming parser, Core Data model, or package API changes

## Constitution Check

*GATE: Passed before research; re-checked after design.*

- [x] Native macOS and privacy-first behavior is preserved: native SwiftUI controls only; no analytics, sync, or remote destination.
- [x] Each changed file belongs to its documented module: presentation stays in `Warden/UI/`; selection policy/coordinator stays in `Warden/Utilities/`; tests remain in test targets.
- [x] Provider work conforms to `APIProtocol` and uses existing factory/base abstractions: no provider transport or API contract changes are planned.
- [x] Secrets remain in Keychain and are excluded from Core Data, fixtures, and logs: favorites contain only provider/model identifiers; diagnostics are non-sensitive.
- [x] Core Data changes include migration and existing-user compatibility analysis: no schema change/model version; existing relationships are reused.
- [x] Async/streaming work has cancellation, failure, and actor-safety behavior: this feature adds no new remote work; existing cache fetch lifecycle remains responsible for refreshes and `@MainActor` cache ownership is preserved.
- [x] Focused XCTest/XCUITest coverage is identified and does not require paid credentials: fixtures/in-memory persistence are required; UI coverage is conditional on a stable fixture seam.
- [x] No new dependency or abstraction is added without a concrete justification: one focused local coordinator removes divergent validation/save/notification behavior.

No Constitution Check violation or exceptional complexity is planned.

## Architecture Impact

### Affected Modules

| Module | Path | Planned responsibility/change |
|---|---|---|
| UI / preferences | `Warden/UI/Preferences/TabAIPersonasView.swift` | Preserve persona CRUD/order editor; add validation/accessibility only where needed for an explicit default-service flow. |
| UI / chat personas | `Warden/UI/Chat/BottomContainer/PersonaSelectorView.swift` | Canonical target-member selector: select/clear persona without a service switch; expose the explicit default-service action and recoverable state. |
| UI / unreferenced duplicate | `Warden/UI/Chat/ChatParameters/PersonaSelectorView.swift` | Do not evolve independently; remove/rename only if needed to eliminate duplicate type ambiguity after confirming target membership. |
| UI / model selection | `Warden/UI/Components/ModelSelectorDropdown.swift` | Consume canonical availability/mutation policy; stable row identity; accessible loading/empty/error states; preserve optional metadata presentation. |
| UI / favorites | `Warden/UI/Components/FavoriteQuickAccessBar.swift` | Use provider/model identity, filter invalid favorites, and call shared mutation path. |
| UI / metadata | `Warden/UI/Components/ModelInfoTooltip.swift` | Reuse cache-derived optional metadata; ensure missing/stale data has a safe reduced presentation. |
| Utilities | `Warden/Utilities/FavoriteModelsManager.swift` | Adopt lossless identity persistence and deterministic safe recovery for non-secret favorite identifiers. |
| Utilities | `Warden/Utilities/SelectedModelsManager.swift`, `Warden/Utilities/ModelCacheManager.swift` | Expose/reuse one availability policy respecting custom visibility, configured services, and capability filtering. |
| Utilities | `Warden/Utilities/ModelSelectionCoordinator.swift` (new, if extraction is necessary) | Validate/apply a service/model pair atomically, save, and send one chat-scoped recreation notification. |
| Shared models | `Warden/Models/Models.swift` | No schema/entity field change anticipated. |
| Persistence | `Warden/Store/wardenDataModel.xcdatamodeld`, `Warden/Store/ChatStore.swift` | No modification expected; validate compatibility through focused in-memory/store tests. |
| Provider handlers | `Warden/Utilities/APIHandlers/` | No change. |
| Unit tests | `WardenTests/PersonasModelSelection/` (new directory, target membership confirmed before add) | Fixture-driven identity, availability, mutation, recovery, and persona persistence coverage. |
| UI tests | `WardenUITests/PersonasModelSelectionUITests.swift` (conditional) | User-critical popover/selection coverage only with deterministic launch fixtures. |

### Dependency Flow

`MessageInputView` opens the canonical persona/model controls in `Warden/UI/`. Those views read observed Core Data entities and `@MainActor` model/favorite managers, then call a focused utility coordinator rather than mutating chats independently. The coordinator validates a configured `APIServiceEntity` and model through cached visibility/capability policy, saves the existing managed context once, and emits the existing `RecreateMessageManager` notification with the current chat UUID only after success. Existing `ChatView` remains the subscriber that rebuilds the corresponding request/message manager. Existing request construction and message managers continue to read `chat.persona` for prompt/temperature, so no provider request transformation changes are needed.

### Provider/API Contract

No `APIProtocol`, factory, handler, endpoint, transport, streaming parser, cancellation, or error-mapping change is planned. The feature consumes existing configured services and cached/static model catalogs. It must not perform a live catalog or metadata request only to render a row, hover a tooltip, or select a persona.

### Persistence and Migration

**No schema change.** Existing `ChatEntity.persona`, `ChatEntity.apiService`, `ChatEntity.gptModel`, `PersonaEntity.defaultApiService`, `APIServiceEntity.selectedModels`, and non-secret favorite preference represent the required state. Existing stores require no version migration. The implementation must preserve existing chats/personas and safely decode malformed optional JSON data; it must not copy credentials, endpoint secrets, messages, or prompts into preferences or logs.

### Security and Privacy

- API credentials/tokens stay in existing Keychain-backed paths; neither persona/default-service application nor favorites writes them to `UserDefaults`, Core Data, fixtures, or logs.
- A default-service action validates a live configured relationship and an allowable model before changing a chat. Deleted/stale/unavailable references keep the current pair intact.
- Use `WardenLog`, and log only safe diagnostics; never log API keys, authorization headers, prompts, message content, or service URLs that could embed a secret.
- Metadata is optional local cache data. Missing/stale metadata reduces displayed information rather than triggering an implicit request or blocking a valid selection.
- No telemetry, analytics, tracking, cloud sync, or new network destination is added.

## Project Structure

### Feature Documentation

```text
specs/007-personas-model-selection/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── contracts/
│   └── personas-model-selection-ui-contract.md
├── quickstart.md
└── tasks.md
```

### Source Paths

```text
Warden/
├── Models/
│   └── Models.swift                         # existing entities; no schema field expected
├── Store/
│   └── wardenDataModel.xcdatamodeld/         # no migration planned
├── UI/
│   ├── Chat/BottomContainer/
│   │   ├── MessageInputView.swift
│   │   └── PersonaSelectorView.swift
│   ├── Components/
│   │   ├── ModelSelectorDropdown.swift
│   │   ├── ModelInfoTooltip.swift
│   │   └── FavoriteQuickAccessBar.swift
│   └── Preferences/
│       └── TabAIPersonasView.swift
└── Utilities/
    ├── ModelSelectionCoordinator.swift       # focused new policy/mutation seam if needed
    ├── ModelCacheManager.swift
    ├── SelectedModelsManager.swift
    └── FavoriteModelsManager.swift

WardenTests/
└── PersonasModelSelection/

WardenUITests/
└── PersonasModelSelectionUITests.swift       # only with reliable fixture setup
```

**Structure Decision**: Keep user interaction in existing SwiftUI components and Core Data relationships in their existing entities. Add at most one focused utility for provider/model policy plus atomic persistence/notification, rather than creating a new persistence model or putting business validation in each view. Maintain only the project-listed BottomContainer persona selector; do not sustain two source definitions of the same SwiftUI types.

## Test and Verification Plan

1. **Regression first**: Add failing unit tests proving a persona selection preserves `apiService`/`gptModel`, an explicit default-service action rejects stale/unavailable references without mutation, and valid provider/model selection saves/recreates only the chosen chat context.
2. **Focused unit tests**: Add `WardenTests/PersonasModelSelection/PersonasModelSelectionTests.swift` with in-memory Core Data and fixture model/cache inputs. Cover lossless provider/model identity, duplicate model IDs across providers, custom empty/all visibility, image capability filtering, malformed favorite/selection data, and optional stale/missing metadata. Run `-only-testing:WardenTests/PersonasModelSelectionTests`.
3. **UI workflow**: Add accessibility labels/identifiers and a focused `WardenUITests` scenario only if a local launch fixture can seed persona/service/model data without credentials. Otherwise execute every path in `quickstart.md` manually and document the real result.
4. **Build**: Run `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS,arch=arm64' build`.
5. **Full tests**: Run `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS,arch=arm64'` before merge. Treat command exit status and `.xcresult` summary as authoritative.
6. **Privacy review**: Inspect the changed persistence/logging paths to confirm no secret/user content is written or emitted, and that no model metadata render path makes a new network request.

## Delivery Phases

### Phase 0 — Research and Risk Reduction

Completed in `research.md`: confirm canonical persona-selector target membership, reuse current Core Data relationships, make the default-service action explicit, centralize exact provider/model identity and mutation behavior, and keep cache-derived metadata optional.

### Phase 1 — Models, Contracts, and Persistence

Define the lossless provider/model identity and availability policy; add a focused selection coordinator if needed. Reuse existing Core Data fields with no schema change. Add deterministic fixture/in-memory tests before changing view actions.

### Phase 2 — Services and Provider Integration

Wire the coordinator to `ModelCacheManager`, `SelectedModelsManager`, and `FavoriteModelsManager`. Validate configured service/model availability and make chat pair changes atomic. Retain the existing chat-scoped recreation notification and existing provider/streaming contracts.

### Phase 3 — Native macOS UI

Update the compiled BottomContainer persona selector to preserve service/model on persona selection and add the separate default-service action. Update model dropdown and quick-access favorites to use stable identity, validated mutation, accurate enabled/empty/error states, modern SwiftUI `Button`/accessibility patterns, and optional metadata display. Do not modify the unreferenced duplicate selector as a second source of truth.

### Phase 4 — Verification and Documentation

Complete focused tests, run the full macOS build and test suite, inspect `.xcresult` results, execute the manual interaction/privacy path, update `tasks.md` evidence, and record only actual blockers.

## Complexity Tracking

> No intentional Constitution Check violation.

| Violation | Why Needed | Simpler Existing Pattern Rejected Because |
|---|---|---|
| None | N/A | Existing Core Data relationships, cache managers, and message-manager recreation already satisfy the feature. |
