# Feature Specification: Provider and Model Configuration

**Feature Branch**: `feature/time-machine-provider-and-model-configuration`
**Created**: 2026-08-11
**Status**: Draft
**Input**: User description: "Let users securely add, test, edit, select, and remove hosted or self-hosted AI services and their available models."

## Clarifications

### Session 2026-08-11

- Q: When the current default service is deleted, what should happen to the default selection? → A: Clear the default; require a deliberate new choice.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Configure a Usable AI Service (Priority: P1)

As a Warden user, I can create or edit a hosted or self-hosted AI service with its endpoint, credential when needed, model, and response preferences, then save it for use in chats.

**Why this priority**: A valid service configuration is the prerequisite for every remote or local AI chat capability.

**Independent Test**: With an isolated in-memory store and Keychain test double, create a hosted service with a credential and a local service without one; save, reload, and edit both without invoking a live provider.

**Acceptance Scenarios**:

1. **Given** no services are configured, **When** the user adds a service and supplies valid required settings, **Then** it appears in the services list and can be selected for chat use after relaunch.
2. **Given** a service requiring credentials, **When** the user saves a token, **Then** the configuration persists without embedding the token in the persistent service record or diagnostics.
3. **Given** a self-hosted service that does not require credentials, **When** the user saves a local endpoint, **Then** the configuration is accepted without requiring a blank or placeholder token.
4. **Given** an existing service, **When** the user changes its name, type, endpoint, model, or response options and saves, **Then** the edited service replaces the prior settings without creating a duplicate.
5. **Given** a remote HTTP endpoint and a non-empty credential, **When** the user attempts to save, **Then** Warden rejects the configuration and explains that HTTPS is required; loopback endpoints remain permitted for local services.

---

### User Story 2 - Validate and Select Models (Priority: P2)

As a user, I can test a configured service and select a supported discovered, preset, or custom model while receiving clear feedback that does not expose credentials or private provider payloads.

**Why this priority**: Validation prevents a user from discovering endpoint, authentication, and model failures only after composing a chat.

**Independent Test**: Use deterministic URL protocol fixtures for successful model discovery, authentication failure, missing endpoint, timeout, and malformed payload outcomes; verify the selected model is preserved and all user messages are safe.

**Acceptance Scenarios**:

1. **Given** a configured provider that supports model discovery, **When** the user refreshes the models, **Then** Warden shows the discovered models, preserves a still-valid selection, and allows a custom model when the desired model is absent.
2. **Given** discovery fails due to invalid credentials, an unreachable endpoint, a timeout, or an invalid response, **When** the user refreshes, **Then** Warden keeps the last safe model choices and shows an actionable error without displaying the token or raw sensitive response body.
3. **Given** a configured service and selected model, **When** the user runs the connection test, **Then** Warden reports success only after a valid provider response and otherwise identifies the recoverable category of failure.
4. **Given** a provider type that does not support remote discovery, **When** the user configures it, **Then** Warden offers its appropriate preset, custom, or local-model selection workflow without issuing an unsupported request.
5. **Given** an image-generation model type, **When** it is selected, **Then** Warden does not offer incompatible streaming behavior.

---

### User Story 3 - Manage Service Lifecycle and Default (Priority: P3)

As a user with multiple services, I can choose a default service, duplicate a configuration safely, and remove a service without leaving dangling defaults or credentials.

**Why this priority**: Multi-provider users need predictable organization and safe cleanup after the core configuration path works.

**Independent Test**: Create two services in an isolated store, mark one default, duplicate it, delete the default and another service, then verify the list, default selection, Keychain operations, and reload behavior.

**Acceptance Scenarios**:

1. **Given** multiple services, **When** the user marks one as default, **Then** the service list identifies it and later chat configuration resolves that same saved service.
2. **Given** a service with a stored credential, **When** the user duplicates it, **Then** the copy receives a separate identity and credential storage slot without changing the original.
3. **Given** a service with a stored credential, **When** the user confirms deletion, **Then** the service disappears from persistent storage and its credential is removed from Keychain.
4. **Given** the default service is removed, **When** the service list reloads, **Then** Warden clears the default and requires the user to deliberately choose another service rather than retaining an invalid identifier or silently switching providers.
5. **Given** deletion, duplication, or persistence fails, **When** the operation completes, **Then** the user receives a clear failure message and existing configurations remain usable.

### Edge Cases

- A malformed, unsupported, or empty endpoint is rejected before a test or model refresh starts.
- Service names and model identifiers may be duplicated, but each saved service retains a unique stable identity and credential slot.
- Changing provider type resets only type-dependent defaults; user-entered custom values are not silently discarded unless incompatible with the selected type.
- A transient model-discovery failure never overwrites the prior persisted model or turns a valid custom model into an empty selection.
- Connection tests and model refreshes remain cancellable or ignore stale completions when the selected service, endpoint, or credentials change during the request.
- Local-model folder access is requested only through an explicit macOS user action; denied access leaves existing paths and service settings intact.
- Duplicate, delete, save, and test actions do not log API keys, authorization headers, complete prompts, raw provider bodies, or local filesystem paths beyond the minimum safe diagnostics.
- Keychain read, write, migration, and deletion errors do not corrupt the persisted non-secret service configuration.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Warden MUST let users create, inspect, edit, duplicate, select, and delete persisted AI service configurations from Settings.
- **FR-002**: Each saved service MUST have a unique stable identity, a display name, provider type, endpoint, selected model, context and response preferences, and a separate non-persistent credential reference when a credential is applicable.
- **FR-003**: Warden MUST validate endpoint syntax before save, test, or model discovery and MUST reject a credential-bearing non-loopback HTTP endpoint.
- **FR-004**: Warden MUST store, retrieve, duplicate, migrate, and remove credentials through Keychain without persisting credentials in Core Data, UserDefaults, source fixtures, exported diagnostics, or logs.
- **FR-005**: Warden MUST construct provider clients through the established provider factory and shared protocol path, using provider-specific behavior only where needed.
- **FR-006**: Users MUST be able to request available models where the selected provider supports discovery, select a discovered or preset model, and enter a custom model identifier.
- **FR-007**: A model refresh MUST preserve the persisted selected model until the user explicitly chooses and saves another model.
- **FR-008**: Warden MUST test a configured service and model with a bounded request and provide user-facing success or actionable failure feedback.
- **FR-009**: User-facing validation, test, and discovery errors MUST classify invalid credentials, rate limits, missing endpoints, connection failures, timeouts, malformed responses, and server failures without exposing credentials or raw sensitive provider content.
- **FR-010**: Provider type changes MUST apply compatible defaults for endpoint, model, image-upload support, and streaming while preserving a safe editable configuration.
- **FR-011**: Warden MUST disable incompatible streamed-response behavior for provider/model types that do not support streaming.
- **FR-012**: Users MUST be able to mark one service as the default; when its service is deleted, Warden MUST clear the default and require a deliberate subsequent user selection.
- **FR-013**: Duplicating a service MUST create a new service identity and an independent credential storage entry; deleting a service MUST remove its associated credential after persistent deletion succeeds.
- **FR-014**: Existing service configurations, configured providers, selected models, chats, and local model settings MUST remain compatible after this feature's changes.

### macOS UX Requirements

- **UX-001**: The services Settings interface MUST present an accessible list, an empty state, clear add/duplicate/delete controls, and a detail editor for the selected service.
- **UX-002**: Credential entry MUST be visually protected when not focused and keyboard accessible; visible validation must not rely on color alone.
- **UX-003**: Model refresh and connection test controls MUST show pending, success, and failure states, prevent duplicate concurrent work for the same action, and return keyboard focus predictably.
- **UX-004**: Destructive deletion MUST require confirmation and identify the affected service without revealing its credential.
- **UX-005**: Local-model folder selection and permission prompts MUST use native macOS panels, explain why access is requested, and leave the configuration unchanged when cancelled or denied.

### Provider and Streaming Requirements

- **PR-001**: Each provider client MUST conform to the existing API service protocol and be instantiated through the factory/configuration path.
- **PR-002**: Discovery and connection-test requests MUST use the provider's supported endpoint and report standardized error categories without leaking authorization values or sensitive request/response content.
- **PR-003**: A request that contains credentials MUST pass the existing sensitive-transport policy before network transmission.
- **PR-004**: Model discovery and connection testing MUST not disrupt an active chat stream or mutate the active chat's selected model until the service configuration is explicitly saved and selected.

### Data, Migration, and Privacy Requirements

- **DP-001**: Service metadata may remain in the existing local service persistence model; this feature MUST not add credentials, tokens, authorization headers, or private provider payloads to that model.
- **DP-002**: Existing service records and Keychain entries MUST remain recoverable, including legacy credential entries that are migrated by the current token manager.
- **DP-003**: A failed Keychain or persistence operation MUST surface a user-safe error, preserve the last known-good configuration where possible, and avoid an orphaned credential on failed create or duplicate.
- **DP-004**: Network requests occur only after user-initiated model discovery or testing, or later user-initiated chat use; Warden MUST add no telemetry or background credential validation.

### Key Entities

- **AI Service Configuration**: Locally persisted non-secret identity and behavior for one provider endpoint, including display name, provider type, URL, model, response preferences, and default selection relationship.
- **Credential Reference**: A Keychain-owned credential mapped to a service's unique identity; it is never serialized into the service configuration.
- **Model Choice**: A user-selected discovered, preset, custom, or local model identifier associated with a service configuration.
- **Default Service Selection**: A local reference identifying the preferred configured service and cleared or repaired when its target no longer exists.

## Compatibility and Scope

- **Affected modules**: `Warden/Utilities/APIHandlers/APIProtocol.swift`, `Warden/Utilities/APIHandlers/APIServiceConfig.swift`, `Warden/Utilities/APIHandlers/BaseAPIHandler.swift`, `Warden/Utilities/APIServiceFactory.swift`, `Warden/Utilities/APIServiceManager.swift`, `Warden/Utilities/TokenManager.swift`, `Warden/UI/Preferences/TabAPIServicesView.swift`, `Warden/UI/Preferences/TabAPIServices/`, associated configuration/model utilities, and focused tests under `WardenTests/` or `WardenUITests/`.
- **Existing behavior preserved**: Chat persistence and history, active chat streaming, message rendering, attachments, personas, local inference, MCP, web search, and chat sharing remain unchanged except for using a newly saved or selected service through the existing configuration path.
- **Out of scope**: Adding a new paid provider, changing provider billing/accounts, cloud-syncing service configurations, importing or exporting credentials, provider-side model administration, executing chat messages, and redesigning unrelated Settings tabs.
- **Dependencies**: Existing SwiftUI/AppKit Settings UI, Core Data service entities, KeychainAccess-backed token manager, existing provider handlers, URL session policy, and service/model configuration constants; no new third-party dependency is proposed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can add and save a valid hosted or self-hosted service, choose its model, and make it available for chat configuration in under 2 minutes, excluding time spent obtaining a credential.
- **SC-002**: In deterministic fixtures for successful discovery, invalid credentials, unavailable host, timeout, malformed response, and server error, 100% of outcomes present a clear result without displaying the fixture's token or sensitive payload.
- **SC-003**: Across 10 save/edit/relaunch cycles for hosted and self-hosted services, the persisted non-secret configuration and selected model survive intact while credentials remain retrievable only through Keychain.
- **SC-004**: Repeating model refresh or connection test requests 10 times for one service never causes more than one active request per action and leaves the last saved model unchanged unless the user selects and saves a new one.
- **SC-005**: Duplicate and delete workflows leave no invalid default identifier or Keychain credential for a successfully deleted service, as verified by focused deterministic tests.
- **SC-006**: All focused provider-configuration, Keychain lifecycle, request-transport, model-discovery, and error-mapping tests pass without live credentials; the native macOS build passes.
- **SC-007**: Under normal local conditions, opening a saved service editor, saving valid changes, and presenting model-refresh or test status each provide visible feedback within 1 second; failure paths complete without a crash or corrupted prior configuration.

## Assumptions

- Warden remains a single-user, privacy-first native macOS app; users intentionally choose each remote provider endpoint before any request is made.
- Existing provider types, factory mappings, Core Data service entity, and Keychain token manager are the compatibility baseline; this feature hardens and completes their configuration lifecycle rather than introducing a new provider.
- A provider's discovered model list is advisory: a user may retain or enter a custom identifier for compatible providers.
- Loopback addresses are treated as local development or self-hosted endpoints; remote endpoints with a credential require HTTPS.
- Removing a service should remove its credential only after the service removal has been committed successfully; a failed deletion must preserve both for recovery. If the removed service was the default, Warden clears the default instead of automatically selecting a replacement.
