# Feature Specification: Chat Organization and Sharing

**Feature Branch**: `feature/time-machine-chat-organization-and-sharing`  
**Created**: 2026-08-12  
**Status**: Draft  
**Input**: User description: "Help users search, archive, group, branch, summarize, export, and share conversations and projects."

## Clarifications

### Session 2026-08-12

- Q: For copied/shared/exported conversations, which content scope should WardenApp use by default? → A: Full conversation including metadata, system instruction, and ordered messages.
- Q: What should “summarize projects” mean for this feature? → A: Keep project summaries local and descriptive; no AI-generated synthesis.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Find and organize conversations (Priority: P1)

A user can find a conversation by its title, instructions, persona, or message content; then manage it in the sidebar by pinning it, assigning it to a project, or working with archived projects without losing its history.

**Why this priority**: Finding and organizing existing work is the minimum useful increment for a growing local conversation library.

**Independent Test**: With locally seeded conversations, verify searching matches each supported source, pinned conversations appear ahead of dated groups, and archived projects can be expanded and opened without altering their chats.

**Acceptance Scenarios**:

1. **Given** conversations with matching titles, personas, instructions, and message bodies, **When** the user searches, **Then** all matching conversations are shown and non-matches are hidden.
2. **Given** a user pins a conversation or assigns it to a project, **When** the sidebar refreshes or the app restarts, **Then** the chosen organization remains visible and intact.
3. **Given** archived projects exist, **When** the user expands the archived-projects section, **Then** each archived project and its conversations remain accessible without being unintentionally restored or deleted.

---

### User Story 2 - Create and navigate conversation branches (Priority: P2)

A user can branch a conversation at a selected message, choose an available model, and continue in a new conversation while retaining the original conversation unchanged.

**Why this priority**: Branching enables safe exploration of alternate responses and models without destroying an established conversation path.

**Independent Test**: From a seeded conversation, create a branch at a user message and at an assistant message; confirm the branch preserves only the history through that point, retains relevant settings, and opens as a separate conversation.

**Acceptance Scenarios**:

1. **Given** a valid selected message and available service/model, **When** the user creates a branch, **Then** a distinct conversation opens with copied history through the selected message and a link to its parent context.
2. **Given** branch creation cannot save or the selected service is unavailable, **When** the user attempts to branch, **Then** the original conversation is unchanged and the user sees an understandable error without credentials or private content.

---

### User Story 3 - Export or share a conversation (Priority: P3)

A user can copy, save, or invoke the macOS share workflow for a conversation in plain text, Markdown, or JSON, using a clear format-specific action.

**Why this priority**: Portable exports and native sharing make completed work usable outside WardenApp while keeping disclosure user initiated.

**Independent Test**: For a seeded conversation containing metadata and ordered messages, verify each export formatter produces the selected format in chronological order, copying publishes the expected text, and a canceled save does not create a destination file.

**Acceptance Scenarios**:

1. **Given** a conversation with messages, **When** the user chooses a copy, export, or share action and a format, **Then** the resulting content contains the conversation metadata and messages in chronological order in that format.
2. **Given** the user cancels the save panel or the selected destination cannot be written, **When** export ends, **Then** no existing conversation data is changed and an actionable error is shown only for write failure.

### Edge Cases

- Empty conversations, missing optional persona/service data, and conversations with no messages remain searchable and exportable without crashing.
- Search requests are cancelled or superseded while the user types, and stale results do not replace a newer query.
- Deleted source conversations or messages, unavailable services, and save failures leave existing conversations unchanged.
- Branches copy the selected history only and do not mutate original messages, project membership, or provider credentials.
- Repeated share/export actions use distinct safe temporary output and do not overwrite unrelated local files.
- Export, clipboard, and sharing actions only disclose content after an explicit user action; credentials, authorization headers, and diagnostic-only data are excluded.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: WardenApp MUST let users search local conversations by title, system instruction, persona name, and message body using case- and diacritic-insensitive matching.
- **FR-002**: WardenApp MUST show pinned conversations before date-grouped unpinned conversations and preserve project membership, pinning, and archive state across relaunch.
- **FR-003**: WardenApp MUST allow users to create, open, rename, move, clear, delete, and view conversations and projects through accessible native controls.
- **FR-004**: WardenApp MUST create a branch as a separate conversation that preserves source settings and only the message history through the selected source message; it MUST leave the source conversation unchanged.
- **FR-005**: WardenApp MUST allow a user to copy, export, or share a chosen conversation as plain text, Markdown, or JSON; each output MUST include full conversation metadata, the system instruction when present, and messages in chronological order.
- **FR-006**: WardenApp MUST present understandable error feedback for failed search, branch, or export operations without exposing secrets or private conversation content in diagnostics.
- **FR-007**: Existing provider behavior, chat streaming, persisted conversations, and project data MUST remain compatible.

### macOS UX Requirements

- **UX-001**: Search is keyboard accessible and supports clearing or dismissing the current query without losing the underlying conversation data.
- **UX-002**: Archived projects are collapsible and visibly identified; project summaries provide clear empty, loading, and populated local descriptive states without contacting an AI provider.
- **UX-003**: Branch creation presents available models, indicates progress, supports dismissal/retry after failure, and opens the new conversation on success.
- **UX-004**: Share, copy, and export choices identify their output format and are reachable by keyboard and VoiceOver labels.

### Data, Migration, and Privacy Requirements

- **DP-001**: The feature uses existing conversation, message, project, service, and branch relationship data; no Core Data schema change is required unless implementation analysis proves one necessary.
- **DP-002**: Existing conversation/project relationships, archived state, and branch metadata remain readable after update; no migration may drop local chats or messages.
- **DP-003**: API keys, authorization headers, and service secrets MUST NOT appear in exports, clipboard output, temporary output, Core Data, or logs as a result of this feature.
- **DP-004**: Conversation content is sent outside the app only through an explicit copy, save, or macOS sharing action chosen by the user; project summaries are derived locally and do not send conversation content to a provider.

### Key Entities

- **Conversation**: A locally persisted chat with name, timestamps, settings, messages, optional project/persona/service, and optional branch ancestry.
- **Message**: An ordered user or assistant entry belonging to one conversation and used as a branch point or export record.
- **Project**: A local grouping of conversations with descriptive, color, and archived-state metadata.
- **Conversation branch**: A new conversation that records a parent conversation and source message while containing its own copied history.
- **Export representation**: A transient selected-format representation of one user-selected conversation; it is not retained unless the user saves or shares it.

## Compatibility and Scope

- **Affected modules**: `Warden/UI/ChatList/`, `Warden/UI/Chat/Components/BranchPopover.swift`, `Warden/UI/Chat/ProjectSummaryView.swift`, `Warden/UI/Chat/ProjectSummaryButton.swift`, `Warden/UI/Components/ChatShareMenu.swift`, `Warden/Utilities/ChatBranchingManager.swift`, `Warden/Utilities/ChatSharingService.swift`, `Warden/Store/`, and focused tests under `WardenTests/` or `WardenUITests/`.
- **Existing behavior preserved**: Provider configuration, streamed replies, local persistence, attachment handling, chat selection, and existing project relationships.
- **Out of scope**: Cloud synchronization, multi-user collaboration, server-hosted public links, project-level bulk export, new analytics/telemetry, and changing provider credentials.
- **Dependencies**: Existing native macOS sharing, clipboard, save-panel, Core Data, Swift concurrency, logging, and model-selection facilities.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can locate a seeded conversation by any supported searchable field and open it in no more than two interactions after entering a query.
- **SC-002**: In deterministic tests, a created branch contains exactly the source history through its chosen message and leaves source message count and content unchanged.
- **SC-003**: In deterministic tests, each of the three export formats contains all seeded messages in chronological order and excludes credentials.
- **SC-004**: Search feedback begins within one second after a user stops typing on a normal local conversation library, without the UI becoming unresponsive.
- **SC-005**: Focused tests and the macOS build pass without live provider credentials.

## Assumptions

- Existing local Core Data entities already store the fields required for project archiving and conversation branch ancestry.
- A native share picker, clipboard, and save panel are appropriate user-controlled disclosure mechanisms for macOS.
- The project summary remains a local overview rather than an AI-generated or cloud-backed summary.
