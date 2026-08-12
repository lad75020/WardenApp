# Tasks: Local AI and Generation

**Input**: Design documents from `/specs/010-local-ai-generation/`  
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/local-provider-contract.md`, and `quickstart.md`  
**Verification**: Deterministic XCTest plus the Warden macOS build; tests use neither paid credentials nor live model servers.

## Phase 1: Baseline and Setup

- [X] T001 Record local-provider source ownership and test scope in `specs/010-local-ai-generation/plan.md`.
- [X] T002 Run the focused existing MLX regression suite in `WardenTests/Utilities/SSEStreamParserTests.swift`.
- [X] T003 Confirm the local-provider privacy contract in `specs/010-local-ai-generation/contracts/local-provider-contract.md` permits only loopback/private-LAN endpoints.

---

## Phase 2: Foundational Contracts and Regression Tests

- [X] T004 Add deterministic endpoint-policy and local-provider factory tests in `WardenTests/Utilities/LocalProviderTests.swift`.
- [X] T005 [P] Add Core ML cumulative-stream delta and cancellation regression tests in `WardenTests/Utilities/LocalProviderTests.swift`.
- [X] T006 [P] Add local-metadata identity and refresh-preservation tests in `WardenTests/Utilities/LocalProviderTests.swift`.
- [X] T007 Implement loopback/private-LAN endpoint classification in `Warden/Utilities/LocalEndpointPolicy.swift`.
- [X] T008 Integrate endpoint validation into `Warden/Utilities/APIHandlers/LMStudioHandler.swift` and `Warden/Utilities/APIHandlers/OllamaHandler.swift` without logging credentials or prompt content.

**Checkpoint**: Tests fail for public endpoints and duplicate cumulative streaming before the corresponding implementation is added.

---

## Phase 3: User Story 1 — Use an Installed Local Text Model (Priority: P1) 🎯 MVP

**Goal**: Configure a local text provider, obtain a cancellable response, and safely reject invalid local paths/endpoints.

**Independent Test**: `WardenTests/Utilities/LocalProviderTests.swift` verifies factory routing, endpoint boundary, Core ML asset validation, and cumulative streaming deltas without live inference.

- [X] T009 [US1] Preserve correct local handler selection through `Warden/Utilities/APIServiceFactory.swift` for MLX, Core ML, Hugging Face, Ollama, and LM Studio.
- [X] T010 [US1] Make `Warden/Utilities/APIHandlers/CoreMLTextGenerationService.swift` emit only incremental stream deltas and cancel its generation task on stream termination.
- [X] T011 [US1] Harden local asset validation and recoverable errors in `Warden/Utilities/APIHandlers/CoreMLTextGenerationService.swift` and `Warden/Utilities/HuggingFaceService.swift`.
- [X] T012 [US1] Run focused User Story 1 tests using `WardenTests/Utilities/LocalProviderTests.swift`.

---

## Phase 4: User Story 2 — Use a Compatible Vision or Image Model (Priority: P2)

**Goal**: Route compatible MLX text, vision, and image-generation models through their correct local path and reject unsupported requests before inference.

**Independent Test**: `WardenTests/Utilities/SSEStreamParserTests.swift` verifies MLX model-type classification and sanitized load-directory behavior using temporary model fixtures.

- [X] T013 [P] [US2] Extend model-type/capability fixture coverage in `WardenTests/Utilities/SSEStreamParserTests.swift` only where an untested MLX routing edge is found.
- [X] T014 [US2] Preserve explicit MLX text, vision, Flux, and Stable Diffusion routing in `Warden/Utilities/APIHandlers/MLXHandler.swift` and `Warden/Utilities/APIHandlers/MLXHandler+Flux.swift`.
- [X] T015 [US2] Verify no image request is accidentally routed to an unrelated hosted provider through `Warden/Utilities/APIServiceFactory.swift`.
- [X] T016 [US2] Run focused MLX regression tests in `WardenTests/Utilities/SSEStreamParserTests.swift`.

---

## Phase 5: User Story 3 — Inspect Available Local Models (Priority: P3)

**Goal**: Retain usable local model metadata/selection when refresh fails and identify self-hosted models accurately.

**Independent Test**: `WardenTests/Utilities/LocalProviderTests.swift` verifies local metadata uses the selected provider identity and a failed/empty local refresh does not erase a cached selection.

- [X] T017 [US3] Preserve provider-specific self-hosted metadata in `Warden/Utilities/ModelMetadataFetcher.swift`.
- [X] T018 [US3] Prevent empty or failed local refreshes from replacing usable entries in `Warden/Utilities/ModelMetadataCache.swift`.
- [X] T019 [US3] Run focused User Story 3 tests in `WardenTests/Utilities/LocalProviderTests.swift`.

---

## Phase N: Cross-Cutting Verification and Polish

- [X] T020 [P] Verify privacy-safe logging and no public-endpoint expansion in `Warden/Utilities/APIHandlers/` and `Warden/Utilities/LocalEndpointPolicy.swift`.
- [X] T021 [P] Confirm no Core Data migration is introduced using `specs/010-local-ai-generation/data-model.md`.
- [X] T022 Run the macOS build from `Warden.xcodeproj` for the `Warden` scheme and record results in `specs/010-local-ai-generation/quickstart.md`.
- [X] T023 Run the macOS test suite from `Warden.xcodeproj` for the `Warden` scheme and record results in `specs/010-local-ai-generation/quickstart.md`.
- [X] T024 Verify `git diff --check` and inspect `Warden/` and `WardenTests/` changes for API keys, prompts, model weights, build output, or other private artifacts.
- [X] T025 Execute and record the deterministic parts of `specs/010-local-ai-generation/quickstart.md`.

## Dependencies and Execution Order

1. T001–T003 establish scope and baseline.
2. T004–T008 establish test-first endpoint/stream contracts.
3. US1 (T009–T012) is the MVP and precedes all later stories.
4. US2 (T013–T016) and US3 (T017–T019) may proceed after the foundational contracts; they share no implementation file.
5. T020–T025 complete only after all selected story work.

## Parallel Opportunities

- T005 and T006 can proceed in parallel with one coordinated edit to `WardenTests/Utilities/LocalProviderTests.swift`.
- T013 can run independently from US3 implementation.
- T020 and T021 are independent post-implementation inspections.

## Implementation Strategy

Deliver US1 first with deterministic tests and no live local runtime. Then retain existing MLX routing for US2 and harden metadata-refresh behavior for US3. Finish with full build/test verification and privacy inspection.