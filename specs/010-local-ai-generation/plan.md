# Implementation Plan: Local AI and Generation

**Branch**: `010-local-ai-generation` | **Date**: 2026-08-12 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `/specs/010-local-ai-generation/spec.md`

## Summary

Complete and harden the existing local-provider integration for MLX, Core ML LLM, Hugging Face local models, Ollama, and LM Studio. Preserve `APIService`/`APIServiceFactory` ownership, add deterministic capability and endpoint validation, correct streamed-delta behavior, and cover local metadata/catalog rules without downloading models or contacting a live server.

## Technical Context

**Language/Version**: Swift 5.9  
**Primary Frameworks**: SwiftUI, AppKit, Foundation, Core ML, MLX (conditional), swift-transformers packages  
**Persistence**: Core Data through `Warden/Store/ChatStore.swift`; Keychain for remote-provider secrets  
**Testing**: XCTest (`WardenTests/`) and XCUITest (`WardenUITests/`)  
**Target Platform**: Native macOS 26.0  
**Project Type**: Xcode macOS application with unit/UI test targets and an auxiliary CLI target  
**Build Command**: `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`  
**Test Command**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'`  
**Performance Goals**: Preserve incremental streaming; do not block the main actor during model validation/loading; do not add model downloads to catalog refresh.  
**Constraints**: Privacy-first, no telemetry, Keychain secrets, cancellable streaming, actor-safe UI state, no paid credentials or installed model requirement in tests.  
**Scale/Scope**: Existing local provider handlers, factory/configuration selection, model metadata/catalog paths, focused XCTest coverage, and local endpoint boundary validation.

## Constitution Check

*GATE: Passed before research and re-checked after design.*

- [x] Native macOS and privacy-first behavior is preserved: local inference remains on-device or explicitly configured loopback/private-LAN hosts; no telemetry is added.
- [x] Each changed file belongs to its documented module.
- [x] Provider work conforms to `APIService` and uses `APIServiceFactory`/existing configuration abstractions.
- [x] Secrets remain in Keychain and are excluded from Core Data, fixtures, and logs.
- [x] No Core Data schema change; existing chats and configurations remain compatible.
- [x] Async/streaming work has cancellation, failure, and actor-safety behavior.
- [x] Focused deterministic XCTest coverage is identified and requires neither paid credentials nor live models.
- [x] No new package dependency or broad abstraction is required.

## Architecture Impact

### Affected Modules

| Module | Path | Planned responsibility/change |
|---|---|---|
| App entry/config | `Warden/Configuration/` | N/A; retain existing configuration records. |
| UI / view models | `Warden/UI/` | N/A unless existing configuration UI needs validation feedback; keep transport out of UI. |
| Shared models | `Warden/Models/ModelMetadata.swift` and model catalog helpers | Preserve self-hosted/local metadata and provider capability identity. |
| Services/managers | `Warden/Utilities/APIServiceFactory.swift`, `Warden/Utilities/APIServiceManager.swift` | Keep factory selection and request lifecycle authoritative; add validation only at service boundaries. |
| Provider handlers | `Warden/Utilities/APIHandlers/MLXHandler.swift`, `CoreMLTextGenerationService.swift`, `OllamaHandler.swift`, `LMStudioHandler.swift`, `HuggingFaceService.swift` | Validate local assets/endpoints, preserve cancellation, and emit deltas without duplicate final content. |
| Persistence | `Warden/Store/` | No schema or migration change. |
| MCP | `Warden/Core/MCP/` | N/A. |
| Unit tests | `WardenTests/Utilities/LocalProviderTests.swift`, `WardenTests/Utilities/SSEStreamParserTests.swift` | Deterministic endpoint/factory/asset/metadata/streaming regressions. |
| UI tests | `WardenUITests/` | N/A: provider behavior is testable below UI without model installation. |
| CLI/local packages | `MLXZImageSwiftCLI/`, `Packages/` | N/A; retain package APIs. |

### Dependency Flow

SwiftUI chooses an existing persisted service configuration → `APIServiceManager` obtains it → `APIServiceFactory` creates the protocol-conforming local handler → handler validates filesystem assets or endpoint classification and creates a cancellable stream → `MessageManager` owns incremental assistant-message updates and persistence through `ChatStore`. Provider handlers remain presentation-independent; validation errors use privacy-safe `APIError` messages.

### Provider/API Contract

- `APIServiceFactory` maps `mlx`, `coreml llm`, `huggingface`, `ollama`, and `lmstudio` configurations to their current protocol-conforming implementations.
- MLX, Core ML, and Hugging Face local handlers perform no network request for inference. They validate readable local assets before load.
- Ollama and LM Studio use a user-configured loopback or private-LAN endpoint. This feature does not introduce public-endpoint routing.
- `sendMessageStream` must honor task cancellation and yield only new content; it must not append a full final response after previously yielded deltas.
- Request failures are actionable but do not log prompts, tokens, authorization values, or raw response bodies.

### Persistence and Migration

**No schema change.** Existing persisted API service settings and `ModelMetadata` behavior are reused. Invalid historical paths or unreachable endpoints fail recoverably at request time and do not mutate an existing chat.

### Security and Privacy

- Local files remain user-selected/model-owned; validate directory and required-assets before model load.
- Loopback and private-LAN endpoint support is explicitly allowed by the clarified product decision. Do not broaden this feature to public endpoints.
- Do not include credentials or user content in diagnostics. Keep existing sensitive-transport validation for any credential-bearing requests.
- No request telemetry, model catalog upload, or background model download is introduced.

## Project Structure

### Feature Documentation

```text
specs/010-local-ai-generation/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── local-provider-contract.md
└── tasks.md
```

### Source Paths

```text
Warden/
├── Models/
├── Store/
├── UI/
└── Utilities/
    ├── APIServiceFactory.swift
    ├── APIServiceManager.swift
    └── APIHandlers/
        ├── CoreMLTextGenerationService.swift
        ├── HuggingFaceService.swift
        ├── MLXHandler.swift
        ├── LMStudioHandler.swift
        └── OllamaHandler.swift

WardenTests/
└── Utilities/
    ├── LocalProviderTests.swift
    └── SSEStreamParserTests.swift
```

**Structure Decision**: Extend focused provider handlers and existing factory/configuration paths. Place deterministic, filesystem-backed tests under `WardenTests/Utilities`; do not create a second local-inference subsystem or a persistence model.

## Test and Verification Plan

1. **Regression first**: Add tests that demonstrate Core ML repeated cumulative streaming output is normalized to deltas and that invalid local assets/endpoints fail before dispatch.
2. **Focused unit tests**: Run `LocalProviderTests` and `MLXHandlerModelTypeTests` with `xcodebuild ... -only-testing` after implementation.
3. **UI workflow**: Manual configuration smoke check is optional; the runtime/model-dependent UI is covered by deterministic service tests rather than a live local-model test.
4. **Build**: Run the repository macOS build command after focused tests.
5. **Full tests**: Run the repository macOS test command before final feature completion; report real environment blockers only.
6. **Privacy review**: Inspect endpoint classification, sensitive transport validation, logs, model path handling, and no Core Data migration.

## Delivery Phases

### Phase 0 — Research and Risk Reduction

Document existing factory/streaming behavior, use the clarified endpoint boundary, and preserve the existing protocol/factory design. Completed in `research.md`.

### Phase 1 — Models, Contracts, and Persistence

Document local configuration/model metadata semantics, define the provider contract, and confirm no Core Data migration. Completed in `data-model.md` and `contracts/local-provider-contract.md`.

### Phase 2 — Services and Provider Integration

Add focused helpers/tests for local endpoint classification and model assets; fix local handler streaming/cancellation behavior; retain factory selection and metadata catalog behavior.

### Phase 3 — Native macOS UI

No new UI is required. Existing configuration screens surface service-level actionable errors; preserve current native controls and accessibility behavior.

### Phase 4 — Verification and Documentation

Run focused and full XCTest/build verification, inspect privacy-sensitive source paths, update task completion state, and record actual blockers if any.

## Complexity Tracking

No constitution gates are intentionally violated.
