# Feature Specification: Personas and Model Selection

**Feature Branch**: `feature/time-machine-personas-and-model-selection`
**Created**: 2026-08-12
**Status**: Draft
**Input**: User description: "Lets users create reusable AI personas and quickly choose, favorite, and inspect models for each conversation."

## Clarifications

### Session 2026-08-12

- Q: When a user selects a persona with a default service in an existing conversation, how should service/model selection behave? → A: Apply the persona prompt and temperature only; offer its default service as an explicit optional change.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create and Apply a Persona (Priority: P1)

A user creates, edits, reorders, and removes reusable AI personas, then selects one for a conversation so its configured behavior and optional default AI service are applied predictably.

**Why this priority**: Reusable personas are the primary user value and must remain manageable without altering existing chats unexpectedly.

**Independent Test**: A deterministic unit test creates and updates persona data in an isolated persistent store; an interaction test verifies creating, editing, deleting, and selecting a persona from the relevant settings and chat controls.

**Acceptance Scenarios**:

1. **Given** a user has no custom assistants, **When** they create an assistant with a name, icon, system message, temperature, and optional default service, **Then** it appears in the ordered assistant list and can be selected for a conversation; selection applies the persona's prompt and temperature but does not automatically change that conversation's service/model.
2. **Given** an existing assistant is selected, **When** the user edits, reorders, or deletes it, **Then** the change is saved safely and the interface does not retain a stale selection.
3. **Given** a selected assistant has a default service, **When** the user chooses to use that default through an explicit control, **Then** the app changes the conversation's service/model only after validating that service and model are still configured and available.
4. **Given** an assistant has no default service, **When** it is used in a conversation, **Then** the conversation retains its existing global or chat-level service choice.

---

### User Story 2 - Find and Select an Available Model (Priority: P1)

A user opens the model selector in a conversation, searches available models, understands basic supported capabilities, and chooses a model supported by the selected service.

**Why this priority**: Selecting an appropriate model is required for every conversation and must be fast, clear, and compatible with service settings.

**Independent Test**: A focused model-selector test supplies fixture services, models, selections, and metadata; it verifies deterministic filtering, service-scoped selection, and safe handling of an unavailable model.

**Acceptance Scenarios**:

1. **Given** a configured service exposes models, **When** the user opens the selector, **Then** models are grouped by provider and the current selection is clearly identified.
2. **Given** several models are available, **When** the user searches by provider or model name, **Then** only matching selectable models are displayed.
3. **Given** the user chooses a model from a configured provider, **When** the choice is saved, **Then** the conversation uses that service and model and refreshes its message-management context.
4. **Given** a model is not selectable for the active service or required capability, **When** the selector is displayed, **Then** the unavailable model is not presented as an actionable choice.

---

### User Story 3 - Favorite and Inspect Models (Priority: P2)

A user marks frequently used models as favorites and sees concise model capability, context, pricing, or freshness information when it is available, without exposing sensitive service configuration.

**Why this priority**: Favorites and inspection reduce repetitive selection work while remaining secondary to basic persona and model selection.

**Independent Test**: Unit tests verify favorite persistence, malformed stored-value recovery, capability interpretation, display-name formatting, and metadata filtering using fixture data only.

**Acceptance Scenarios**:

1. **Given** an available model, **When** the user marks it as a favorite, **Then** it appears in a dedicated favorites area and remains available after relaunch.
2. **Given** model metadata is available, **When** the user views a model, **Then** applicable capabilities and non-sensitive availability information are shown clearly.
3. **Given** saved favorite or metadata data is malformed or stale, **When** the selector loads, **Then** the app continues safely, avoids a crash, and does not show credentials or private prompts.

### Edge Cases

- A persona name or system message is blank, duplicated, or contains large text.
- A persona is deleted while it is selected in the settings UI or referenced by a conversation.
- A saved default service or selected model is no longer configured or no longer advertises the chosen model.
- A provider has an explicit empty custom selection, no known models, duplicate model identifiers, or a model identifier containing a provider-style separator.
- Favorite data, selection data, or model metadata cannot be decoded after an upgrade.
- Metadata is missing, stale, or incomplete; the model remains selectable only when compatible information supports it.
- Repeated favorite toggles, rapid searches, and stale selector updates do not create inconsistent UI state.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: WardenApp MUST let users create, edit, reorder, and delete named reusable personas with an icon, system message, temperature, and optional default AI service.
- **FR-002**: Persona edits MUST be persisted locally and must preserve existing personas and conversations through normal store recovery and migration behavior.
- **FR-003**: WardenApp MUST let a user select a persona for a conversation and apply that persona's configured system message and temperature without automatically replacing the conversation's existing service or model.
- **FR-004**: When a selected persona has a default service, WardenApp MUST offer a separate explicit user action to apply it; the app MUST validate that the required service/model remains configured and available before changing the conversation's active service/model.
- **FR-005**: The app MUST list only models that are available for configured services and compatible with the required capability and current visibility selection.
- **FR-006**: The model selector MUST support provider/model search, identify the current selection, and update the conversation's service and model together after a valid selection.
- **FR-007**: Users MUST be able to mark and unmark an available model as a favorite; favorites must remain associated with the provider and model identifier and persist locally across relaunch.
- **FR-008**: The app MUST show non-sensitive model metadata only when present, including relevant capabilities and available pricing/context information, and must tolerate missing or stale metadata.
- **FR-009**: The app MUST recover safely from malformed locally stored favorite, model-selection, or metadata values; diagnostics must not include credentials, authorization headers, prompts, or conversation content.
- **FR-010**: Existing unaffected providers, chats, service configuration, attachments, and streaming behavior MUST continue to behave as before.

### macOS UX Requirements

- **UX-001**: Persona management and model-selection controls MUST be operable with standard macOS keyboard navigation, clear button labels, and accessible names for primary actions.
- **UX-002**: Persona and model lists MUST provide understandable empty, selected, unavailable, and recoverable-error states without retaining stale selected items.
- **UX-003**: Search and favorite controls MUST use stable identity and remain responsive during rapid input or repeated toggles.

### Provider and Streaming Requirements

- **PR-001**: A selected model MUST resolve to an existing configured service before it becomes the conversation's active service/model pair.
- **PR-002**: Changing a conversation's service or model MUST recreate only the conversation's message-management context so subsequent requests use the selected configuration.
- **PR-003**: Provider compatibility and image-generation capability filtering MUST respect the existing service configuration and not infer unsupported capabilities.

### Data, Migration, and Privacy Requirements

- **DP-001**: Persona data and per-service selected-model visibility data MUST use the existing persistence abstractions; this feature must document any schema change before implementation.
- **DP-002**: Existing chats, personas, service configuration, and selected-model settings MUST remain readable after upgrade; malformed optional local settings must fall back safely.
- **DP-003**: API keys, tokens, and other service secrets MUST remain in Keychain or existing secret-storage mechanisms and MUST NOT be copied into persona, favorite, metadata, Core Data diagnostic, or log records.
- **DP-004**: This feature MUST not add analytics, telemetry, tracking, or a new remote network destination for persona, favorite, or selection data.

### Key Entities

- **Persona**: A locally persisted reusable assistant configuration containing a display name, icon, system message, temperature, explicit order, and optional default service relationship.
- **Model selection**: The active provider/model pair on a conversation and the optional per-service visibility selection used to limit models in the selector.
- **Favorite model**: A locally persisted provider/model identifier marking an available model for quick access.
- **Model metadata**: Non-secret, locally cached capability and availability information keyed by provider and model identifier.

## Compatibility and Scope

- **Affected modules**: `Warden/UI/Preferences/TabAIPersonasView.swift`, `Warden/UI/Chat/ChatParameters/PersonaSelectorView.swift`, `Warden/UI/Chat/BottomContainer/PersonaSelectorView.swift`, `Warden/UI/Components/ModelSelectorDropdown.swift`, `Warden/UI/Components/ModelInfoTooltip.swift`, `Warden/UI/Components/FavoriteQuickAccessBar.swift`, `Warden/Utilities/FavoriteModelsManager.swift`, `Warden/Utilities/SelectedModelsManager.swift`, `Warden/Utilities/ModelCacheManager.swift`, `Warden/Utilities/ModelMetadata.swift`, and focused coverage under `WardenTests/` or `WardenUITests/`.
- **Existing behavior preserved**: Existing service configuration, Keychain secret storage, chat history, streaming, provider handlers, attachment behavior, and model availability behavior outside this selector remain unchanged.
- **Out of scope**: Adding a new AI provider, changing provider credential storage, synchronizing personas or favorites between devices, transmitting persona/favorite data remotely, billing, or changing model-provider API contracts.
- **Dependencies**: Existing Core Data store, SwiftUI/AppKit UI patterns, service configuration, model cache, and local preferences. No new third-party dependency is required.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can create a valid persona, save it, select it, edit it, and see each saved change reflected in the relevant UI without restarting the app.
- **SC-002**: With fixture services and models, a user can find and select a matching model through provider/model search in no more than two interactions after opening the selector.
- **SC-003**: Favoriting and unfavoriting a fixture model updates its quick-access presentation and survives a relaunch using local fixture storage.
- **SC-004**: Focused persona, model-selection, favorite, metadata, and recoverable-storage-error tests pass deterministically without live provider credentials.
- **SC-005**: The selector remains interactive while filtering a fixture catalog of at least 500 models, and stale/invalid optional local settings do not crash the app.

## Assumptions

- Existing `PersonaEntity`, conversation, service, model-cache, and manager abstractions remain the ownership boundaries for this feature.
- Existing local preference storage for favorites is acceptable for non-secret provider/model identifiers; service credentials remain outside this data.
- A model may be selected only if its configured service and allowed visibility/capability state make it available in the selector.
- Existing behavior for a persona with no default service continues to preserve the conversation's global or chat-level service selection.
- Selecting a persona applies its system message and temperature; a persona default service may be applied only through a separate explicit user action.
