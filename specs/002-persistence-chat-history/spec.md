# Feature Specification: Persistence and Chat History

**Feature Branch**: `feature/time-machine-persistence-and-chat-history`  
**Created**: 2026-08-11  
**Status**: Draft  
**Input**: User description: "Stores conversations, messages, projects, personas, and service configuration locally while preserving data through migrations and recovery paths."

## Clarifications

### Session 2026-08-11

- Q: For legacy chats whose provider configuration is missing or invalid, which recovery policy should Warden use? → A: Preserve the chat as unavailable and offer an explicit repair or delete action.
- Q: What should the explicit Repair action do for an unavailable chat? → A: Remap the chat to an existing valid service; if none exists, guide the user to the existing service settings.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Preserve Conversation History (Priority: P1)

A user can quit and relaunch Warden without losing their existing conversations, messages, projects, selected context, or ordering, so they can reliably resume local work.

**Why this priority**: Reliable recovery of existing conversation history is the minimum value of local persistence and protects the user’s primary content.

**Independent Test**: Create representative conversations with messages and projects, relaunch using an isolated test data location, and verify the same records, relationships, ordering, and selected valid conversation are restored without live provider credentials.

**Acceptance Scenarios**:

1. **Given** existing conversations, messages, and projects, **When** the user relaunches the app, **Then** the same valid history is available in its prior relationships and deterministic order.
2. **Given** the previously selected conversation no longer exists, **When** the app restores history, **Then** it clears the stale selection and presents a safe valid state without deleting remaining history.
3. **Given** an empty local history, **When** the user opens Warden, **Then** the app presents an empty-state experience without creating duplicate or placeholder conversations.

---

### User Story 2 - Safely Evolve Existing Local Data (Priority: P2)

A user upgrading Warden retains compatible local history and receives understandable, non-sensitive recovery feedback if their local data cannot be opened normally.

**Why this priority**: Users must not be forced to choose between an upgrade and preserving their accumulated local work.

**Independent Test**: Exercise supported prior-data fixtures and malformed or unavailable local-data conditions in isolated test storage; verify preserved valid records and a safe, actionable outcome for unrecoverable input.

**Acceptance Scenarios**:

1. **Given** compatible prior local data, **When** the user launches an updated app, **Then** their conversations and related records remain available with no user data reset.
2. **Given** a recoverable local-data upgrade condition, **When** the app opens its history, **Then** it completes recovery once and retains the valid data.
3. **Given** local data cannot be opened safely, **When** the user launches Warden, **Then** the app avoids destructive overwrite, shows non-sensitive recovery guidance, and remains usable where possible.

---

### User Story 3 - Retain Configuration Without Exposing Secrets (Priority: P3)

A user’s local projects, personas, and non-secret service configuration remain available after relaunch while authentication secrets retain their existing secure ownership and are never displayed, logged, or stored with chat history.

**Why this priority**: History is only useful when its associated local context survives, but configuration persistence must not weaken privacy protections.

**Independent Test**: Persist representative project, persona, and non-secret service metadata in isolated storage, relaunch, and assert restoration while scanning persistence and diagnostics paths for secret values.

**Acceptance Scenarios**:

1. **Given** user-created projects, personas, and non-secret service settings, **When** the user relaunches, **Then** the same valid context is available to their conversations.
2. **Given** a service needs authentication, **When** its configuration is saved or restored, **Then** no secret is written to ordinary history records, error messages, or diagnostics.
3. **Given** a persisted chat has a missing or invalid service configuration, **When** history is restored, **Then** the chat remains available but marked unavailable until the user explicitly repairs or deletes it.
4. **Given** an invalid or duplicate persisted relationship, **When** history is restored, **Then** the app resolves it deterministically without corrupting unrelated records.
5. **Given** an unavailable chat and one or more valid services, **When** the user chooses repair and selects a service, **Then** the chat is remapped to that service and becomes available without changing its history.
6. **Given** an unavailable chat and no valid services, **When** the user chooses repair, **Then** the app guides them to the existing service settings and keeps the chat unavailable until a valid service is selected.

### Edge Cases

- What happens when a history record refers to a deleted chat, project, persona, or service? A chat with a missing or invalid service configuration remains available as unavailable until the user explicitly deletes it or remaps it to a valid existing service; if none exists, repair guides them to existing service settings.
- What happens when local storage is unavailable, malformed, partially migrated, or interrupted during a write?
- How are duplicate saves, repeated lifecycle callbacks, and stale selected-chat identifiers prevented?
- What data remains after an app upgrade, migration, recovery attempt, or in-memory test fallback?
- How does the app handle a message payload that a newer or older version cannot fully interpret?
- How are recovery errors kept non-sensitive and separate from API credentials, chat content, and diagnostic logs?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: WardenApp MUST persist valid conversations, messages, projects, personas, and non-secret service configuration locally and restore their valid relationships after relaunch.
- **FR-002**: The app MUST preserve a deterministic conversation and message ordering and clear stale selected-conversation state without deleting unrelated history.
- **FR-003**: Users MUST retain compatible existing local history through supported data-model changes without manually recreating their content.
- **FR-004**: The app MUST handle unavailable, malformed, or unrecoverable local data without silently overwriting valid user data; recovery feedback MUST be understandable and must not disclose private content or secrets.
- **FR-005**: The app MUST prevent duplicate lifecycle saves and avoid creating duplicate chats, messages, projects, personas, or service records during repeated restoration.
- **FR-006**: Existing chat presentation, message streaming, provider behavior, and appearance settings MUST continue to behave as before when persisted data is valid.
- **FR-007**: Persisted message content MUST remain compatible with supported local history and safely handle unsupported or incomplete content without crashing the app.
- **FR-008**: A chat with a missing or invalid service configuration MUST remain in local history as unavailable and expose only explicit user-initiated repair or delete actions; automatic restoration MUST NOT delete it.
- **FR-009**: Repairing an unavailable chat MUST remap it to a user-selected existing valid service without changing its message history; when no valid service exists, the app MUST guide the user to existing service settings and keep the chat unavailable.

### macOS UX Requirements *(include for UI features)*

- **UX-001**: History loading, empty state, and recovery state MUST be distinguishable through text and accessible controls, not color alone.
- **UX-002**: A user-facing local-data recovery failure MUST provide a safe next step without blocking access to unaffected app functionality; unavailable chats MUST expose explicit repair and delete actions rather than disappearing, and repair MUST allow selection from valid services or direct the user to existing service settings when none exists.
- **UX-003**: History restoration and recovery feedback MUST support keyboard navigation and meaningful VoiceOver labels.

### Data, Migration, and Privacy Requirements *(include when data or secrets are involved)*

- **DP-001**: Local history records MUST maintain explicit ownership and relationship integrity among chats, messages, projects, personas, and service configuration.
- **DP-002**: A supported data-model upgrade MUST preserve compatible existing records and execute recovery or migration idempotently.
- **DP-003**: API keys, passwords, bearer credentials, and equivalent secrets MUST remain outside ordinary local-history records and MUST NOT appear in logs, diagnostics, error messages, or recovery UI.
- **DP-004**: This feature MUST remain local-only; it MUST NOT add telemetry, tracking, or an unrequested remote sync destination for chat history.

### Key Entities *(include if feature involves data)*

- **Conversation**: A user-owned history container with messages, optional project context, a valid selection state, timestamps, and stable ordering.
- **Message**: An ordered item in a conversation whose supported content and metadata survive relaunch without exposing credentials.
- **Project**: User-managed grouping and context associated with conversations and retained across relaunches.
- **Persona**: User-owned reusable conversation context retained locally and associated only through valid references.
- **Service Configuration**: Local non-secret provider metadata required to identify a service; authenticating secrets retain their separate secure lifecycle.
- **Recovery State**: User-visible, non-sensitive result of restoring, migrating, or safely isolating local data, including an unavailable status for chats whose service configuration requires explicit deletion or remapping to a valid service.

## Compatibility and Scope

- **Affected modules**: `Warden/Store/`, `Warden/Models/Models.swift`, `Warden/Models/MessageContent.swift`, `Warden/Models/RequestMessagesTransformer.swift`, `Warden/Utilities/DatabasePatcher.swift`, `Warden/Store/wardenDataModel.xcdatamodeld/`, and focused test targets.
- **Existing behavior preserved**: Current valid conversations, message rendering, provider requests, settings, and local-first privacy posture.
- **Out of scope**: Cloud synchronization, account sharing, encryption-format redesign, a new backup/export user interface, a broad provider configuration UI redesign beyond selecting an existing service or opening the current settings flow from unavailable-chat repair, and changes to message streaming behavior unrelated to restoration.
- **Dependencies**: Existing local persistence, model, and secure credential ownership components; no new network service is assumed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In automated isolated-storage scenarios, 100% of representative valid conversations, messages, projects, personas, and non-secret service settings remain available after relaunch with their verified relationships intact.
- **SC-002**: In supported upgrade fixtures, 100% of valid pre-existing history remains accessible after the first updated launch, with no duplicate records introduced by a second launch.
- **SC-003**: In malformed or unavailable local-data scenarios, the app completes startup without crash or silent destructive reset, preserves chats with invalid service configuration as unavailable, and presents non-sensitive recovery feedback with explicit repair or delete actions; selecting a valid service restores availability without altering message history.
- **SC-004**: Relevant unit and UI tests pass deterministically without live provider credentials, and a standard macOS build succeeds.
- **SC-005**: Static review of changed persistence and recovery paths finds zero instances of API secrets, full chat content, telemetry, or build artifacts written to diagnostics or ordinary persistence records.

## Assumptions

- Warden remains a local-first native macOS client whose chat history has no unrequested cloud synchronization requirement.
- Existing secure credential storage remains the authority for authentication secrets; this feature persists only non-secret service metadata where needed.
- Existing valid history is the compatibility baseline; unsupported or corrupt input must be isolated or reported safely rather than silently transformed into a new empty history. A chat with invalid service configuration remains unavailable until the user explicitly repairs or deletes it.
- Test coverage can use isolated storage and fixtures but must not require an actual paid provider account or live network request.
