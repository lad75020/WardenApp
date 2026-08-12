# Implementation Plan: Provider and Model Configuration

**Branch**: `feature/time-machine-provider-and-model-configuration` | **Date**: 2026-08-11 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/003-provider-model-configuration/spec.md`

## Summary

Complete and harden Warden's existing native provider-configuration flow. The smallest architecture-aligned change keeps `APIServiceEntity` as local non-secret metadata, makes `TokenManager` the only credential owner, centralizes save/duplicate/delete/default lifecycle behavior in a focused service manager, and lets the SwiftUI Settings views present that behavior without owning persistence or secret logic. Model discovery and testing continue through `APIServiceFactory` and `APIProtocol`, with endpoint validation, stale-result protection, redacted errors, and no background requests.

## Technical Context

**Language/Version**: Swift 5.9
**Primary Frameworks**: SwiftUI, AppKit, Foundation, Core Data, KeychainAccess
**Persistence**: Existing `APIServiceEntity` Core Data metadata; `@AppStorage("defaultApiService")` default reference; Keychain bundle for credentials
**Testing**: XCTest (`WardenTests/`) with injected Keychain/service-client seams; focused native UI/manual Settings checks
**Target Platform**: Native macOS 26.0
**Project Type**: Xcode macOS application with unit/UI test targets and an auxiliary CLI target
**Build Command**: `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS,arch=arm64' build`
**Test Command**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS,arch=arm64' test`
**Performance Goals**: Editor/save feedback within 1 second; no duplicate model-discovery or test request per service action; preserve existing streaming behavior
**Constraints**: Privacy-first; no telemetry; credentials only in Keychain; local endpoints permitted; credential-bearing non-loopback endpoints require HTTPS; actor-safe UI updates; no live/paid credential dependency in tests
**Scale/Scope**: Existing service manager, Keychain lifecycle, provider configuration factory/model fetching, Settings service list/detail UI, and focused unit/UI coverage across existing provider types

## Constitution Check

*GATE: Passed before research and design; re-check after implementation.*

- [x] Native macOS and privacy-first behavior is preserved.
- [x] Each changed file belongs to its documented module.
- [x] Provider work conforms to `APIProtocol` and uses existing factory/base abstractions.
- [x] Secrets remain in Keychain and are excluded from Core Data, fixtures, and logs.
- [x] No Core Data schema change is proposed; existing records remain compatible.
- [x] Async model discovery/test work defines cancellation, stale-result, failure, and main-actor behavior.
- [x] Focused XCTest/manual macOS Settings coverage is identified and does not require paid credentials.
- [x] No new dependency or architectural layer is added without a concrete justification.

## Architecture Impact

### Affected Modules

| Module | Path | Planned responsibility/change |
|---|---|---|
| UI / view models | `Warden/UI/Preferences/TabAPIServicesView.swift` | Delegate list add/duplicate/default/delete lifecycle to a focused manager; preserve stable object identity and selection. |
| UI / view models | `Warden/UI/Preferences/TabAPIServices/APIServiceDetailViewModel.swift` | Make save/delete results transactional and user-visible; validate before requests; manage cancellation/stale model-discovery completion on the main actor. |
| UI / view models | `Warden/UI/Preferences/TabAPIServices/APIServiceDetailView.swift` | Use secure input, modern native confirmation UI, accessible status/error copy, disabled-progress states, and manager/view-model outcomes. |
| UI / view models | `Warden/UI/Preferences/TabAPIServices/ButtonTestApiTokenAndModel.swift` | Validate before testing; route redacted result through the detail view model rather than an unscoped modal with raw provider errors. |
| Services/managers | `Warden/Utilities/APIServiceManager.swift` | Provide transactional service metadata plus Keychain lifecycle operations; default clearing; explicit result/error semantics. |
| Services/managers | `Warden/Utilities/TokenManager.swift` | Expose only safe set/get/delete behavior required by manager, retain legacy migration, and avoid credential-bearing errors/logs. |
| Provider handlers | `Warden/Utilities/APIServiceFactory.swift`, `Warden/Utilities/APIHandlers/` | Preserve factory/protocol path and existing session policy; add test seam only if needed to deterministically exercise discovery/test behavior. |
| Configuration | `Warden/Configuration/AppConstants.swift` | Retain current provider defaults and type mapping; correct only invalid defaults discovered by tests. |
| Unit tests | `WardenTests/` | Add focused tests for endpoint transport policy, save/duplicate/delete/default lifecycle, error mapping/redaction, model-fetch races, and provider factory contracts. |
| UI tests | `WardenUITests/` | Add only stable Settings flow coverage if the app's target/supporting fixtures permit deterministic isolated storage. |

### Dependency Flow

`TabAPIServicesView` owns list selection and injects a selected `APIServiceEntity` into the detail view. `APIServiceDetailView` owns only presentation state and forwards user intent to `APIServiceDetailViewModel`. The view model validates field values and calls `APIServiceManager` for local metadata/Keychain transactions. It constructs temporary provider clients solely through `APIServiceConfig → APIServiceFactory → APIService`, retaining the factory's standard/streaming session policies. The manager coordinates Core Data save first where required, then token operations, rolls back/compensates safely on error, and reports a redacted domain result to the view model. Provider handlers remain presentation-independent.

### Provider/API Contract

- Keep `APIService`/`APIServiceConfiguration` as the source of normal send, streamed send, and model-fetch operations.
- `APIServiceFactory.createAPIService(config:)` remains the single supported client-construction path; inherited ChatGPT-compatible provider mapping remains intact.
- Model discovery and connection testing are explicit user actions. They must validate a URL before constructing the request and use the existing bounded, no-cache URL session configuration.
- The view model owns one cancellable task per model fetch/test action. It records a generation/identity snapshot and discards completion if the service type, endpoint, or credential input changed.
- Error translation uses safe `APIError` categories. No UI, alert, or log may interpolate credentials, authorization headers, full provider response bodies, or private prompts.
- Existing streaming is not altered; image-generation types remain non-streaming.

### Persistence and Migration

**No Core Data schema change.** Existing `APIServiceEntity` fields remain the persisted source for identity, display metadata, endpoint, model, context, streaming, image-upload, and persona settings. Service identity continues to map to the existing Keychain token key contract. The manager must preserve `TokenManager` legacy per-item token migration. `@AppStorage("defaultApiService")` contains only an object URI reference; deleting its selected entity clears this value after persistent deletion succeeds. Failed deletion preserves both metadata and credential for recovery. No configuration export/import is introduced.

### Security and Privacy

- Credentials remain exclusively in KeychainAccess under the existing service and accessibility policy; no credential is written to Core Data, `@AppStorage`, test fixtures, source, logs, notification text, or error alerts.
- Enforce `allowsSensitiveTransport`: an endpoint with a non-empty token may use HTTPS or loopback HTTP only; reject any remote plaintext HTTP configuration before save, test, or discovery.
- Keep the existing URL session behavior (timeouts, `waitsForConnectivity`, no URL cache, bounded connection counts). Do not add permissive trust delegates or certificate exceptions.
- Model discovery/testing occurs only after a user action. It is redacted, cancellable, and must not alter chat configuration until an explicit save.
- Local model access remains through explicit `NSOpenPanel` security-scoped-bookmark acquisition; cancel/deny leaves settings unchanged.
- Use synthetic credentials generated within tests, never realistic secrets or tool arguments.

## Project Structure

### Feature Documentation

```text
specs/003-provider-model-configuration/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/provider-configuration-contract.md
└── tasks.md
```

### Source Paths

```text
Warden/
├── Configuration/AppConstants.swift
├── UI/Preferences/TabAPIServicesView.swift
├── UI/Preferences/TabAPIServices/
│   ├── APIServiceDetailView.swift
│   ├── APIServiceDetailViewModel.swift
│   └── ButtonTestApiTokenAndModel.swift
└── Utilities/
    ├── APIServiceManager.swift
    ├── TokenManager.swift
    ├── APIServiceFactory.swift
    └── APIHandlers/

WardenTests/
WardenUITests/
```

**Structure Decision**: Keep provider lifecycle coordination in `Utilities/APIServiceManager.swift`, secret operations in `TokenManager.swift`, presentation state in the existing detail view model, and visual concerns in the existing Settings views. Add focused tests beside the existing test-target organization. Do not add a new persistence entity, a parallel provider client, or a new dependency.

## Test and Verification Plan

1. **Regression first**: Write focused failing tests for clearing a deleted default, deleting the matching Keychain credential only after successful save, copying credentials to a new identity, rejecting credential-bearing remote HTTP, and retaining a selected model across failed refresh.
2. **Focused unit tests**: Run the new API-service lifecycle, transport-validation, and redaction/model-refresh XCTest classes with `-only-testing` after each relevant phase.
3. **UI workflow**: Run the native macOS app; exercise add hosted service, reject remote HTTP with token, add local service, refresh/test with deterministic failure fixture, duplicate, set default, delete default, and cancel local-model access. Verify keyboard reachability and non-color-only states.
4. **Build**: Run the canonical arm64 macOS `xcodebuild` build command.
5. **Full tests**: Run the canonical `xcodebuild test` command before commit; record only real environment blockers.
6. **Privacy review**: Inspect changed source/diff for token persistence, transport, logging, raw error, Keychain orphan, and default-reference regressions.
7. **Xcode evidence**: Use Hermes-configured XcodeMCP build/test issue inspection before finalizing when an Xcode project is open; label CLI evidence as fallback if XcodeMCP cannot run.

## Delivery Phases

### Phase 0 — Research and Risk Reduction

Document provider-default mapping, current Keychain identity/key behavior, Core Data fields, existing endpoint policy, factory contract, and test seams. Confirm no schema change and settle the default-deletion product decision (clear default, do not auto-switch).

### Phase 1 — Lifecycle and Validation Contracts

Introduce or refine focused, testable service-lifecycle operations: endpoint validation, create/edit, duplicate with a distinct credential reference, transactional delete/credential cleanup, and clearing the default. Add redacted domain results/errors without changing provider handlers.

### Phase 2 — Discovery and Test Request Safety

Refactor model discovery and connection tests behind the validated factory path. Add cancellation/generation safeguards, progress state, safe user messages, and regression tests for stale/failing outcomes. Preserve existing timeouts, local server support, and streaming behavior.

### Phase 3 — Native macOS Settings UI

Wire manager/view-model outcomes into the service list and detail view. Apply secure credential entry, accessible labels/status, modern confirmation behavior, focused keyboard handling, disabled-in-flight controls, and local-model permission cancellation behavior.

### Phase 4 — Verification and Documentation

Run focused tests, native Settings manual verification, canonical build/full tests, source privacy review, and XcodeMCP evidence. Update task completion and the Time Machine queue only after real evidence succeeds.

## Complexity Tracking

No constitutional exceptions or added dependencies are required.
