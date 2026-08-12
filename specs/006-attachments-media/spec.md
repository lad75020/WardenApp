# Feature Specification: Attachments and Media

**Feature Branch**: `feature/time-machine-attachments-and-media`  
**Created**: 2026-08-12  
**Status**: Draft  
**Input**: User description: "Allows users to attach, preview, send, render, open, and save files, images, and generated video within conversations."

## Clarifications

### Session 2026-08-12

- Q: What attachment persistence policy should apply after app restart? → A: Persist image and file attachments; generated videos remain transient local files.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Attach and send supported content (Priority: P1)

A user adds one or more supported files or images to a conversation, sees an understandable preview while content is prepared, removes an item before sending if needed, and sends the resulting message with the attachment content included.

**Why this priority**: Attaching useful content to a prompt is the minimum independently valuable capability; without reliable preparation and removal, preview and saved-media features have no dependable input.

**Independent Test**: With fixture image, text, PDF, and unsupported-binary files, verify that each can be selected, displays its preparation state or a clear error, can be removed before send, and that a sent message retains the expected user-visible attachment representation without live provider credentials.

**Acceptance Scenarios**:

1. **Given** an open conversation and a supported local file or image, **When** the user selects it for attachment, **Then** the app shows its name, type, size, and a suitable preview or icon while it is prepared.
2. **Given** a file that cannot be read or decoded, **When** the user tries to attach it, **Then** the app shows a clear error, keeps the draft usable, and does not send partial or misleading content.
3. **Given** a prepared attachment in a draft, **When** the user removes it, **Then** it is absent from the draft and from the next sent message.
4. **Given** several attachments selected in one draft, **When** preparation completes in any order, **Then** every item remains associated with the intended draft and its own visible state.

---

### User Story 2 - Inspect received images and files (Priority: P2)

A user can understand attachments in conversation history, enlarge an image for inspection, and safely open or save user-accessible media without altering the original conversation.

**Why this priority**: Conversation attachments must remain useful after sending; readable previews and safe retrieval make stored conversations actionable.

**Independent Test**: Seed a conversation with image, PDF, text, and generic-file fixtures; verify image enlargement, preview metadata, and save actions using a temporary destination without a provider account.

**Acceptance Scenarios**:

1. **Given** a conversation containing an image attachment, **When** the user opens it, **Then** they can zoom, pan, reset the view, and close the viewer without modifying the stored message.
2. **Given** a file attachment in history, **When** the user views it, **Then** the app presents enough metadata and content or a fallback description to identify it.
3. **Given** an image or file available to the user, **When** they choose Save As and select a valid destination, **Then** the saved copy is usable and the original attachment remains unchanged.
4. **Given** the user cancels an open or save panel, **When** the panel closes, **Then** the conversation and attachment remain unchanged and no error is reported.

---

### User Story 3 - Use generated video (Priority: P3)

A user receives a completed generated video in a conversation, watches it inline, reveals it in Finder, or saves a copy while generation failures are communicated safely.

**Why this priority**: Generated video is valuable but depends on the primary conversation and attachment experience; it should not compromise the rest of the chat when unavailable.

**Independent Test**: Use a local video fixture and simulated completed, failed, and inaccessible generation outcomes to verify inline playback, reveal, Save As, and error feedback without a live generation service.

**Acceptance Scenarios**:

1. **Given** a completed generated video that is locally available, **When** the message is displayed, **Then** the user can play it inline and access Reveal and Save As actions.
2. **Given** a user selects Reveal for an available generated video, **When** the action completes, **Then** Finder selects the source video without changing conversation data.
3. **Given** copying a video to the chosen destination fails, **When** the failure occurs, **Then** the app explains the failure without deleting or replacing the source video.
4. **Given** video generation fails, is cancelled, or returns no usable media, **When** the result is handled, **Then** the user sees a clear failure state and can continue using the conversation.

### Edge Cases

- The user selects a missing, unreadable, malformed, password-protected, zero-byte, or very large attachment.
- A supported image format cannot be decoded, or metadata and file extension disagree.
- Text extraction fails or produces no text for a PDF, RTF, or binary file.
- The user cancels preparation, closes the window, or removes the attachment while background work is in progress.
- A conversation is reopened after restart and stored attachment bytes are missing, corrupted, or no longer decode.
- The selected save destination is unavailable, unwritable, identical to the source, or already contains a file with the same name.
- A generated-video operation fails, never completes, returns no media location, or downloaded media cannot be opened.
- Attachment content, file paths, and service credentials must not be exposed in diagnostics or user-visible error text beyond what is necessary to explain the issue.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: WardenApp MUST let users add supported local files and images to a conversation draft and remove any draft attachment before it is sent.
- **FR-002**: The app MUST show each selected attachment’s name, size when available, type-appropriate preview or icon, and preparation, success, or failure state.
- **FR-003**: The app MUST include prepared attachment content in the outgoing conversation request in a form appropriate to its content type and must not send unavailable or failed content as if it were complete.
- **FR-004**: The app MUST provide readable fallback information for unsupported or non-previewable files so the user can identify what was attached.
- **FR-005**: The app MUST preserve the user-visible association between an attachment and its conversation message across app restarts when the attachment was stored successfully.
- **FR-006**: The app MUST let users inspect attached images at a larger scale with zoom, pan, reset, keyboard-accessible controls, and a clear close action.
- **FR-007**: The app MUST let users save a copy of an available image or generated video to a user-selected location and must not alter or delete the source when a save fails or is cancelled.
- **FR-008**: The app MUST let users reveal an available generated-video file in Finder and present a comprehensible error if the action cannot be completed.
- **FR-009**: The app MUST display available generated videos inline with standard playback controls and a non-blocking loading or error state when media is unavailable.
- **FR-010**: The app MUST handle attachment reading, decoding, extraction, persistence, download, generation, cancellation, and save failures without crashing, corrupting the conversation, or exposing credentials.
- **FR-011**: Existing text-only messages, provider configuration, chat history, and unaffected message rendering MUST continue to behave as before.

### macOS UX Requirements *(include for UI features)*

- **UX-001**: Attachment previews MUST clearly distinguish loading, ready, error, and removable states; removal controls and media actions MUST be keyboard accessible and have meaningful accessibility labels.
- **UX-002**: The enlarged-image experience MUST provide visible zoom in, zoom out, reset, save, and close controls, with sensible keyboard shortcuts that do not prevent normal conversation navigation.
- **UX-003**: System file-selection and save panels MUST allow cancellation without a destructive side effect; feedback for unreadable attachments, failed copies, and unavailable video MUST be understandable and localized with the rest of the app.
- **UX-004**: Inline previews and video playback MUST remain responsive while large files are prepared or media actions are running.

### Provider and Streaming Requirements *(include for AI/provider features)*

- **PR-001**: When a configured video-generation service returns a completed result, WardenApp MUST associate only a successfully available media item with the originating conversation response.
- **PR-002**: The app MUST surface video-generation failures, cancellations, unavailable media, and invalid completion results as actionable message states rather than pretending the generation succeeded.
- **PR-003**: Service authentication values and full request headers MUST be redacted from diagnostics and never rendered in a conversation or attachment error.

### Data, Migration, and Privacy Requirements *(include when data or secrets are involved)*

- **DP-001**: Attachment metadata and the data needed to render stored image and file attachments MUST remain available to their owning conversation after restart; generated videos may remain transient local files and must present an unavailable state if no longer accessible.
- **DP-002**: Existing conversations and already stored attachments MUST remain readable after this feature is introduced; a missing or corrupt stored attachment MUST not prevent the conversation from loading.
- **DP-003**: Provider API keys and other secrets MUST remain outside conversation records, attachment records, filenames, previews, and diagnostics.
- **DP-004**: Local attachment bytes and extracted text MUST be disclosed to an AI service only when the user sends the containing conversation message; saving or revealing a rendered attachment MUST not transmit additional data.

### Key Entities *(include if feature involves data)*

- **Draft attachment**: A user-selected local file or image that has a display identity, preparation state, optional preview, content representation, and a temporary relationship to an unsent message.
- **Stored file attachment**: A durable conversation-owned record of a file’s identifying metadata, extracted readable content where available, and optional image or thumbnail data used to render historical messages.
- **Stored image attachment**: A durable conversation-owned image with format metadata, display data, and a thumbnail for efficient rendering in history.
- **Generated video**: A user-visible media result associated with a completed conversation response, represented by a locally accessible video file while available.

## Compatibility and Scope

- **Affected modules**: `Warden/Models/FileAttachment.swift`, `Warden/Models/ImageAttachment.swift`, `Warden/Utilities/AttachmentResolver.swift`, `Warden/Utilities/BackgroundDataLoader.swift`, `Warden/UI/Components/FilePreviewView.swift`, `Warden/UI/Chat/ZoomableImageView.swift`, `Warden/UI/Chat/BubbleView/VideoAttachmentView.swift`, `Warden/Utilities/APIHandlers/VeoHandler.swift`, and their direct message-composition and message-rendering call sites.
- **Existing behavior preserved**: Text-only chats, conversations without attachments, existing provider selection, preferences, and non-video message rendering retain their current behavior.
- **Out of scope**: Cloud file synchronization, collaboration or sharing permissions, malware scanning, editing attachments in place, permanent archival of generated-video files, and support for arbitrary proprietary document formats.
- **Dependencies**: Existing native file-selection, image, document, video-playback, persistence, and configured AI-service capabilities; no new external dependency is assumed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can attach, preview, remove, and send each supported fixture type in a deterministic test workflow without live provider credentials.
- **SC-002**: For fixture files that are readable on the test machine, the app presents an attachment-ready preview or a clear error within 3 seconds and keeps the conversation composer responsive.
- **SC-003**: In automated or repeatable manual tests, 100% of simulated read, decode, extraction, download, cancellation, and save failures leave the conversation usable and do not expose credentials.
- **SC-004**: A user can inspect, save, or reveal locally available image and video fixtures without changing the source attachment or its conversation history.
- **SC-005**: Reopening a fixture conversation preserves successfully stored image and file attachment rendering; a deliberately missing or corrupt attachment shows a recoverable unavailable state rather than preventing the conversation from loading.

## Assumptions

- Existing conversation composition and message rendering provide the integration points for draft and historical attachments.
- Supported file types follow the app’s existing capability classification: common images, text, CSV, PDF, JSON, XML/HTML, Markdown, and RTF; other types receive an identifiable fallback rather than guaranteed content extraction.
- Generated videos are intentionally stored as local transient files after a successful generation result, so their availability can change outside the app’s persistence lifecycle.
- The user has granted the normal macOS file access required to select, read, reveal, and save the media they choose.
- Automated tests will use local fixtures and service simulations instead of real provider credentials or network calls.
