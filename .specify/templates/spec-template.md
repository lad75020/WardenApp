# Feature Specification: [FEATURE NAME]

**Feature Branch**: `[###-feature-name]`  
**Created**: [DATE]  
**Status**: Draft  
**Input**: User description: "$ARGUMENTS"

## User Scenarios & Testing *(mandatory)*

<!-- Prioritize independently valuable macOS user journeys. Each story must be testable without real paid provider credentials. -->

### User Story 1 - [Brief Title] (Priority: P1)

[Describe the macOS user journey and the value delivered.]

**Why this priority**: [Explain why this is the minimum useful increment.]

**Independent Test**: [Describe a focused XCTest, XCUITest, or manual macOS workflow that validates this story independently.]

**Acceptance Scenarios**:

1. **Given** [initial app/provider/chat state], **When** [user action], **Then** [observable outcome]
2. **Given** [failure/offline/cancellation state], **When** [user action], **Then** [safe and understandable outcome]

---

### User Story 2 - [Brief Title] (Priority: P2)

[Describe the next independently useful journey.]

**Why this priority**: [Explain the value and ordering.]

**Independent Test**: [Explain how this story is verified without depending on later stories.]

**Acceptance Scenarios**:

1. **Given** [initial state], **When** [action], **Then** [expected outcome]

---

### User Story 3 - [Brief Title] (Priority: P3)

[Describe an optional or later journey.]

**Why this priority**: [Explain the value and ordering.]

**Independent Test**: [Explain how this story is verified independently.]

**Acceptance Scenarios**:

1. **Given** [initial state], **When** [action], **Then** [expected outcome]

### Edge Cases

- What happens when a stream is cancelled, interrupted, malformed, or resumed?
- What happens when a provider, local model endpoint, MCP server, or search service is unavailable?
- How does the feature behave with an empty chat, large response, large attachment, or inaccessible file?
- How are duplicate actions, repeated callbacks, and stale SwiftUI state prevented?
- What data remains after app restart, Core Data migration, or in-memory fallback?
- What sensitive values could reach Keychain, Core Data, files, diagnostics, or UI error messages?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: WardenApp MUST [specific user-visible capability].
- **FR-002**: The feature MUST [specific state, provider, or persistence behavior].
- **FR-003**: Users MUST be able to [key interaction].
- **FR-004**: The app MUST handle [failure/cancellation/offline scenario] without data loss or exposing secrets.
- **FR-005**: Existing unaffected providers, chats, and settings MUST continue to behave as before.

Mark unresolved product choices explicitly as `[NEEDS CLARIFICATION: question]`; do not select a provider, persistence, retention, or privacy policy by assumption.

### macOS UX Requirements *(include for UI features)*

- **UX-001**: [Window, sheet, popover, keyboard, focus, menu, or accessibility behavior.]
- **UX-002**: [Loading, empty, success, cancellation, and error states.]
- **UX-003**: [VoiceOver label, keyboard access, contrast, reduced-motion, or localization requirement.]

### Provider and Streaming Requirements *(include for AI/provider features)*

- **PR-001**: [Supported provider capability and `APIProtocol` behavior.]
- **PR-002**: [Streaming parser, cancellation, retry, timeout, and error mapping behavior.]
- **PR-003**: [Request/response compatibility and model capability behavior.]

### Data, Migration, and Privacy Requirements *(include when data or secrets are involved)*

- **DP-001**: [Core Data entities/fields affected, or explicitly state no schema change.]
- **DP-002**: [Migration and backward-compatibility requirement for existing chats/settings.]
- **DP-003**: [Keychain ownership and secret lifecycle; secrets must not enter Core Data or logs.]
- **DP-004**: [Network destinations and user-controlled disclosure of local data.]

### Key Entities *(include if feature involves data)*

- **[Entity 1]**: [Meaning, important attributes, ownership, persistence, and relationships.]
- **[Entity 2]**: [Meaning and relationship to existing Warden models.]

## Compatibility and Scope

- **Affected modules**: [Choose concrete paths under `Warden/`, `WardenTests/`, `WardenUITests/`, `MLXZImageSwiftCLI/`, or local packages.]
- **Existing behavior preserved**: [List unaffected providers, persistence, and UI behavior.]
- **Out of scope**: [Explicit exclusions.]
- **Dependencies**: [Existing framework/service/package dependencies; identify any proposed new dependency.]

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: [User completes the primary journey with an observable success condition.]
- **SC-002**: [Failure/cancellation path completes without crash, leaked secret, or corrupted chat state.]
- **SC-003**: [Relevant XCTest/XCUITest scenarios pass deterministically without live credentials.]
- **SC-004**: [Performance or responsiveness target appropriate to a native macOS app.]

## Assumptions

- [Assumption grounded in current Warden behavior.]
- [Supported macOS, provider, local-model, or data-state assumption.]
- [Dependency on an existing service or module.]
