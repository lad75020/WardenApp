# Feature Specification: Local AI and Generation

**Feature Branch**: `feature/time-machine-local-ai-and-generation`  
**Created**: 2026-08-12  
**Status**: Draft  
**Input**: User description: "Runs compatible text, vision, and image-generation models locally through MLX, Core ML, Hugging Face, Ollama, and LM Studio integrations."

## Clarifications

### Session 2026-08-12

- Q: Which local endpoint privacy boundary should WardenApp enforce? → A: Permit loopback and private-LAN endpoints automatically.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Use an Installed Local Text Model (Priority: P1)

A user configures an installed compatible local model and uses it to receive a text response without sending the conversation to a hosted AI provider.

**Why this priority**: Local text chat is the minimum useful capability and establishes the privacy-preserving provider path.

**Independent Test**: A deterministic XCTest verifies that each configured local-provider type resolves to its correct service implementation and that unavailable local-model paths return a safe, actionable error without a network request.

**Acceptance Scenarios**:

1. **Given** a valid local model configuration, **When** the user sends a text prompt, **Then** WardenApp selects the configured local provider and displays its response in the active conversation.
2. **Given** a local runtime is unavailable, a configured path is missing, or model assets are incomplete, **When** the user starts a request, **Then** WardenApp preserves the draft and conversation and shows an understandable error that contains no secret or private prompt content.

---

### User Story 2 - Use a Compatible Vision or Image Model (Priority: P2)

A user can use a compatible locally available MLX vision or image-generation model with the appropriate prompt or image input and receive a usable result in the conversation.

**Why this priority**: It extends local inference to the media-capable models users deliberately install while keeping text chat independently useful.

**Independent Test**: Focused XCTest coverage verifies local model capability classification, model-load directory preparation, and the request/result behavior that distinguishes supported text, vision, and image-generation paths without requiring model downloads or live inference.

**Acceptance Scenarios**:

1. **Given** a compatible local vision model and a supported image attachment, **When** the user sends the prompt, **Then** WardenApp selects the vision-capable local path and presents the result as an assistant response.
2. **Given** a local image-generation model returns image data, **When** generation completes, **Then** WardenApp presents the generated media using the existing attachment/result experience.
3. **Given** the selected local model does not support the requested input or output capability, **When** the user submits the request, **Then** WardenApp rejects it before generation with clear corrective guidance.

---

### User Story 3 - Inspect Available Local Models (Priority: P3)

A user refreshes local-provider model choices and can distinguish locally hosted or installed models from remote catalog entries.

**Why this priority**: Clear discovery and metadata prevent accidental provider selection and make local capabilities understandable before starting a chat.

**Independent Test**: XCTest coverage verifies local provider metadata is categorized as self-hosted and that metadata failures do not prevent existing model selections from remaining usable.

**Acceptance Scenarios**:

1. **Given** an available Ollama or LM Studio server, **When** the user refreshes models, **Then** WardenApp displays the server-reported local models for that configured service.
2. **Given** a local server cannot be reached, **When** the user refreshes models, **Then** WardenApp retains the last valid selection and displays a recoverable failure state.

### Edge Cases

- Cancellation stops local generation and does not append partial duplicate content or corrupt the active chat.
- Missing model folders, incomplete tokenizer/model assets, unsupported model types, malformed local responses, and unavailable local endpoints fail safely.
- A model load or inference request cannot overwrite results from a newer request or selection.
- Local model paths and user prompts are not written to diagnostics except where the existing privacy-safe logging policy permits non-sensitive identifiers.
- Existing hosted providers, provider settings, persisted chats, and attachments retain their behavior.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: WardenApp MUST resolve MLX, Core ML, Hugging Face, Ollama, and LM Studio configurations through the existing provider-selection path without routing local requests to an unrelated hosted provider.
- **FR-002**: WardenApp MUST support compatible local text inference and expose responses through the same cancellable conversation workflow used by other providers.
- **FR-003**: WardenApp MUST classify and route compatible local vision and image-generation requests only to a local model path that supports the requested capability.
- **FR-004**: WardenApp MUST validate required local model assets and local-runtime availability before or during generation, return actionable failures, and preserve the user’s draft and prior conversation state.
- **FR-005**: WardenApp MUST make locally hosted model discovery available for configured Ollama and LM Studio services and retain the current usable selection when a refresh fails.
- **FR-006**: Local-model metadata MUST identify local/self-hosted models without representing them as paid remote catalog models.
- **FR-007**: Existing unaffected hosted providers, chats, settings, attachments, and generated media behavior MUST continue to behave as before.

### macOS UX Requirements *(include for UI features)*

- **UX-001**: Local model errors MUST identify the unavailable runtime, incompatible capability, or missing model requirement in user-facing language without exposing credentials or private prompt contents.
- **UX-002**: The existing chat UI MUST show an in-progress local request, allow cancellation, and return to a usable compose state after success, cancellation, or failure.
- **UX-003**: Local model identity and failure states MUST remain accessible through existing keyboard and VoiceOver-compatible controls.

### Provider and Streaming Requirements *(include for AI/provider features)*

- **PR-001**: Each local provider implementation MUST conform to the established provider protocol and be created through the existing service factory/configuration path.
- **PR-002**: Local streamed responses MUST honor cancellation and must not emit duplicate final content after incremental content has already been delivered.
- **PR-003**: Requests that are local by configuration MUST not add remote network destinations; local server requests remain limited to a user-configured loopback or private-LAN endpoint.

### Data, Migration, and Privacy Requirements *(include when data or secrets are involved)*

- **DP-001**: This feature MUST NOT require a Core Data schema change; existing service configurations and chats remain readable.
- **DP-002**: Existing persisted local-provider selections MUST continue to resolve after app restart; invalid legacy paths fail safely rather than corrupting configuration.
- **DP-003**: Local provider secrets, if a user supplies one for a compatible endpoint, remain owned by the existing Keychain mechanism and MUST NOT enter Core Data, fixtures, or logs.
- **DP-004**: Model files and conversation content remain local except for requests explicitly sent to a user-configured local endpoint; no telemetry or tracking is introduced.

### Key Entities *(include if feature involves data)*

- **Local provider configuration**: The existing saved service configuration identifying a local provider type, endpoint where applicable, and selected model/path.
- **Local model metadata**: The existing metadata representation used to identify a model as self-hosted and describe supported capabilities.
- **Local model assets**: User-installed model, tokenizer, and configuration files used for compatibility validation and inference; assets are owned outside the chat persistence store.

## Compatibility and Scope

- **Affected modules**: `Warden/Utilities/APIHandlers/MLXHandler.swift`, `Warden/Utilities/APIHandlers/MLXHandler+Flux.swift`, `Warden/Utilities/APIHandlers/CoreMLTextGenerationService.swift`, `Warden/Utilities/APIHandlers/OllamaHandler.swift`, `Warden/Utilities/APIHandlers/LMStudioHandler.swift`, `Warden/Utilities/HuggingFaceService.swift`, `Warden/Utilities/APIServiceFactory.swift`, `Warden/Utilities/ModelMetadataFetcher.swift`, `Warden/Utilities/ModelMetadataCache.swift`, relevant `WardenTests/` coverage, and `MLXZImageSwiftCLI/` only if its current interface requires a compatible local image-generation fix.
- **Existing behavior preserved**: Hosted provider handling, Keychain-backed secret handling, Core Data chat persistence, attachment persistence, and non-local model discovery.
- **Out of scope**: Downloading or distributing model weights, adding telemetry, adding new cloud providers, changing Core Data schema, or guaranteeing performance for unsupported hardware/model combinations.
- **Dependencies**: Existing MLX, Core ML, local model packages, Ollama and LM Studio compatible endpoints, and existing Warden provider abstractions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Focused deterministic tests verify correct service-factory selection and safe local-provider failure behavior for every supported local provider type without live paid credentials.
- **SC-002**: 100% of tested missing-path, unavailable-endpoint, incompatible-capability, cancellation, and malformed-response cases preserve the existing chat and expose no credentials or private prompt content.
- **SC-003**: A user with an already compatible installed local model can begin a local text or supported media-capable request in no more than two provider/model selection actions plus sending the prompt.
- **SC-004**: The Warden macOS target builds successfully and all focused local-provider regression tests pass.

## Assumptions

- Users acquire and install model weights separately and only configure local paths or endpoints that they are authorized to use.
- Existing provider settings and chat UI already provide the selection and request lifecycle; this feature strengthens compatibility, routing, failures, and test coverage rather than introducing a separate local-model manager.
- Local endpoint URLs are user-configured and should normally refer to loopback or a user-controlled LAN host.
