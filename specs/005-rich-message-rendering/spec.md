# Feature Specification: Rich Message Rendering

**Feature Branch**: `feature/time-machine-rich-message-rendering`  
**Created**: 2026-08-12  
**Status**: Draft  
**Input**: User description: "Displays AI responses as readable Markdown, highlighted code, tables, mathematics, thinking sections, and interactive previews."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read Structured Assistant Responses (Priority: P1)

A user can read a completed or streamed assistant response as structured prose, headings, emphasis, lists, links, quotations, tables, mathematics, and collapsible reasoning rather than raw markup.

**Why this priority**: Legible response content is the minimum useful experience for every chat and directly affects comprehension.

**Independent Test**: Feed representative response strings into parsing and rendering tests without a live provider; verify each supported block becomes the correct element and that malformed or unfinished input remains readable.

**Acceptance Scenarios**:

1. **Given** an assistant response with Markdown, a table, mathematics, and a reasoning section, **When** it is displayed, **Then** each content type is visually distinct, selectable where appropriate, and readable in the active appearance.
2. **Given** a response is still streaming or has incomplete delimiters, **When** new content arrives, **Then** the message remains responsive and preserves readable content without crashing or duplicating blocks.

---

### User Story 2 - Inspect and Reuse Code (Priority: P2)

A user can identify the language of a code block, read highlighted code, and copy its original content. For HTML, the user can open and close an inline preview with desktop, tablet, and phone layouts.

**Why this priority**: Generated code is a common response type and must be readable and safely reusable.

**Independent Test**: Exercise code parsing and view-model behavior using Swift tests; manually verify the inline preview with safe static HTML and each device selection.

**Acceptance Scenarios**:

1. **Given** a completed fenced code block with a language tag, **When** the response renders, **Then** the language and code are displayed distinctly and Copy places the unmodified code on the clipboard.
2. **Given** a static HTML code block, **When** the user selects Run, refreshes, changes zoom or device, or closes the preview, **Then** the preview responds locally and no external navigation, script execution, or network connection is permitted.

---

### User Story 3 - Handle Long and Invalid Content Gracefully (Priority: P3)

A user can continue reading a very long response without the chat freezing; the app shows an initial portion and provides an explicit way to load the rest.

**Why this priority**: It protects the responsiveness of ongoing conversations while preserving access to the complete response.

**Independent Test**: Test long-message truncation, background full parsing, parser edge cases, and selection/copy behavior with deterministic local fixtures.

**Acceptance Scenarios**:

1. **Given** a text-only response exceeding the app's large-message threshold, **When** it opens, **Then** the initial portion is shown promptly with a Show Full Message action.
2. **Given** parsing or preview loading fails, **When** the error occurs, **Then** the original response remains available as selectable text and the chat remains usable.

### Edge Cases

- Unclosed code fences, table delimiters, display-math markers, and reasoning tags remain visible as readable text or a safely finalized partial block.
- Empty cells, uneven table rows, malformed links, unsupported language identifiers, and invalid math do not crash rendering.
- A new stream update, appearance or font change, cancellation, or navigation away cancels obsolete parsing work and cannot replace newer content with stale output.
- HTML preview content is isolated from the network, external navigation, script execution, persistent website data, and filesystem access.
- Existing attachment rendering, citations, provider metadata, copy/retry controls, and persisted message text remain unchanged.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: WardenApp MUST parse supported response content into text, table, code, formula, reasoning, and existing attachment elements while preserving their source order.
- **FR-002**: The feature MUST render common Markdown prose, headings, emphasis, lists, links, quotations, inline code, and thematic breaks in an accessible chat bubble.
- **FR-003**: Users MUST be able to select response text, copy a whole message, copy a code block, and copy a table as tabular text or JSON.
- **FR-004**: The app MUST safely render incomplete, malformed, oversized, or rapidly streaming content without data loss, a crash, or a blocked chat interface.
- **FR-005**: Existing unaffected providers, chats, attachments, citations, persistence, and message actions MUST continue to behave as before.
- **FR-006**: For HTML code, the app MUST provide an explicitly user-initiated inline preview that can be refreshed, resized, zoomed, and closed.

### macOS UX Requirements *(include for UI features)*

- **UX-001**: Reasoning content MUST be presented in a clearly labelled disclosure control, with a visible expanded/collapsed state and keyboard-operable action.
- **UX-002**: Loading, long-content, preview, empty, malformed, streaming, and error states MUST preserve readable source content and communicate the current state without relying on color alone.
- **UX-003**: Interactive controls, tables, code, and preview actions MUST have accessible labels, keyboard access, selectable text where relevant, and work in light and dark appearances.

### Data, Migration, and Privacy Requirements *(include when data or secrets are involved)*

- **DP-001**: No new Core Data schema or message persistence format is required; rendering derives only from existing message content.
- **DP-002**: Existing stored chats MUST remain renderable, including messages without new markup.
- **DP-003**: Rendering and preview diagnostics MUST not log message bodies, credentials, or attachment contents.
- **DP-004**: HTML preview content MUST be handled locally with nonpersistent website data and no network, navigation, script, form, or external-frame access.

### Key Entities *(include if feature involves data)*

- **Message element**: A transient, ordered presentation segment derived from existing message text; it has a type and the minimum content needed to render it.
- **Inline preview state**: Per-code-block view state for visibility, device viewport, zoom, and refresh; it is not persisted with the chat.

## Compatibility and Scope

- **Affected modules**: `Warden/UI/Chat/BubbleView/`, `Warden/UI/Chat/CodeView/`, `Warden/UI/Chat/HTMLPreviewView.swift`, `Warden/UI/Chat/ThinkingProcessView.swift`, `Warden/UI/Components/MarkdownView.swift`, `Warden/UI/Components/StreamingAttributedTextView.swift`, `Warden/Utilities/MessageParser.swift`, and focused `WardenTests/` coverage.
- **Existing behavior preserved**: provider request/streaming transport, chat persistence, attachment handling, citations, message retry, and chat organization.
- **Out of scope**: executing arbitrary code; external browsing from generated HTML; adding new message formats, Core Data migrations, provider protocols, or cloud rendering services.
- **Dependencies**: Existing Markdown, syntax-highlighting, math, SwiftUI/AppKit, and WebKit capabilities already used by WardenApp.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can read and select each supported structured response type in a representative message without seeing raw delimiter syntax in completed valid content.
- **SC-002**: Deterministic tests cover valid and malformed streamed blocks, long-message fallback, code copy, table serialization, and preview isolation without live credentials.
- **SC-003**: A response with 100,000 plain-text characters presents an initial readable result without blocking the main UI, and the full response can be loaded on demand.
- **SC-004**: Static HTML preview actions complete locally without persistent site data, external navigation, script execution, or network access.

## Assumptions

- The current supported response markup (Markdown, fenced code, pipe tables, display math, and `<think>` blocks) remains the supported scope.
- Existing message content remains the source of truth; no rendered representation is persisted.
- HTML preview is a display-only convenience for user-selected static HTML, not a browser or code execution environment.
