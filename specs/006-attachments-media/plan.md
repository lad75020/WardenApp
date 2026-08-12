# Implementation Plan: Attachments and Media

**Branch**: `feature/time-machine-attachments-and-media` | **Date**: 2026-08-12 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `specs/006-attachments-media/spec.md`

## Summary

Provide a resilient native macOS attachment workflow: select multiple images/files, prepare and preview them asynchronously, send only ready content, persist image/file data with conversation history, resolve and interact with historical content, and play/export transient generated videos. Extend the existing `ImageAttachment`, `FileAttachment`, `AttachmentResolver`, Core Data loader, message marker parser, and SwiftUI chat views instead of adding a new storage system. Generated videos deliberately remain local/transient per the confirmed product decision.

## Implementation Evidence

- Existing image/file composition, Core Data persistence, UUID marker parsing, and historical resolution paths were retained; no schema migration is required.
- The incremental parser lacked `<video-url>` handling. Rendering previously exposed unresolved image/file markers verbatim, and video export removed an existing destination before copying.
- Focused `MessageParserTests` now cover valid and malformed video markers, a video marker split across streaming chunks, and local-video/export safety decisions. Generated video URLs are validated as readable local regular files before playback, reveal, or export.

## Technical Context

**Language/Version**: Swift 5.9  
**Primary Frameworks**: SwiftUI, AppKit, Foundation, UniformTypeIdentifiers, AVKit, Core Data  
**Persistence**: Existing Core Data `ImageEntity` / `FileEntity` coordinated by `ChatStore` and `BackgroundDataLoader`; generated video files are transient local files  
**Testing**: XCTest (`WardenTests/`) and XCUITest/manual macOS workflows (`WardenUITests/`)  
**Target Platform**: Native macOS 26.0  
**Project Type**: Xcode macOS application with unit/UI test targets and an auxiliary CLI target  
**Build Command**: `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`  
**Test Command**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'`  
**Performance Goals**: Do not block the main actor for file reads, decoding, extraction, historical resolution, or video-player setup; present attachment-local progress and failures.  
**Constraints**: Privacy-first, local persistence, no telemetry, no credentials in logs/UI, cancellable background work, actor-safe SwiftUI state, system save/reveal interactions.  
**Scale/Scope**: Existing attachment models/loaders, chat composition, marker parsing/rendering, image/file/video interaction views, Veo result handling, focused tests; no provider protocol change and no Core Data schema migration.

## Constitution Check

*GATE: Must pass before research and be re-checked after design.*

- [x] Native macOS and privacy-first behavior is preserved: SwiftUI/AppKit/AVKit, local persistence, no telemetry.
- [x] Each changed file belongs to its documented module.
- [x] Provider work remains in the existing Veo handler and does not add a provider abstraction.
- [x] Secrets remain Keychain-managed and excluded from persistence, fixtures, UI, and logs.
- [x] No Core Data schema change is planned; existing persisted attachments retain compatibility.
- [x] Asynchronous file/video work uses existing background and cancellation patterns with main-actor UI updates.
- [x] Focused XCTest coverage plus manual/XCUITest workflows use fixtures/simulations rather than paid credentials.
- [x] No new dependency is planned; existing platform frameworks and app abstractions are extended.

**Post-design result**: Pass. Research resolved the persistence, transient-video, safety, concurrency, and export decisions without exceptions.

## Architecture Impact

### Affected Modules

| Module | Path | Planned responsibility/change |
|---|---|---|
| UI / composition | `Warden/UI/Chat/BottomContainer/MessageInputView.swift`, `Warden/UI/Chat/QuickChatView.swift` | Keep draft attachments, picker/drop ingestion, preparation state, removal, and send gating aligned. |
| UI / rendering | `Warden/UI/Chat/BubbleView/MessageContentView.swift`, `Warden/UI/Components/FilePreviewView.swift` | Render ready/unavailable image/file/video states without raw marker fallback as the only error experience. |
| UI / interaction | `Warden/UI/Chat/ZoomableImageView.swift`, `Warden/UI/Chat/BubbleView/VideoAttachmentView.swift` | Accessible zoom/play/reveal/save actions with safe copy/export semantics. |
| Shared models | `Warden/Models/ImageAttachment.swift`, `Warden/Models/FileAttachment.swift` | Make readiness/error state and prepared content reliable for multi-attachment composition. |
| Services/managers | `Warden/Utilities/AttachmentResolver.swift`, `Warden/Utilities/BackgroundDataLoader.swift` | Resolve durable historical attachment data asynchronously and distinguish unavailable data. |
| Parser | `Warden/Utilities/MessageParser.swift`, `Warden/Utilities/IncrementalMessageParser.swift` | Preserve image/file/video marker parsing and safe malformed-marker fallback. |
| Provider handler | `Warden/Utilities/APIHandlers/VeoHandler.swift` | Maintain transient local video result lifecycle, cancellation, download failure mapping, and credential redaction. |
| Persistence | `Warden/Store/ChatStore.swift` and existing entity use-sites if needed | Store images/files before message markers are persisted; no schema/model version change. |
| Unit tests | `WardenTests/Utilities/MessageParserTests.swift` and new focused attachment tests | Validate markers, preparation/error paths, persistence resolution, unavailable video/file states, and export decision logic. |
| UI tests | `WardenUITests/` | Add only stable accessibility-driven workflows feasible without provider access; document remaining native panel/video checks manually. |

### Dependency Flow

`MessageInputView`/`QuickChatView` own draft arrays of `ImageAttachment` and `FileAttachment`. Each model prepares content off the main actor and publishes ready/error state on the main actor. The send coordinator refuses a send that would omit a selected loading/failed attachment; when all selected attachments are ready, it persists image/file data through the existing store paths and emits UUID marker content. Provider handlers receive established representations only after explicit user send.

Stored message text flows through `MessageParser`/`IncrementalMessageParser` into `MessageContentView`. UUID markers resolve through `AttachmentResolver` and `BackgroundDataLoader` using a background Core Data context. Rendering failures remain local to an element, while neighboring text and attachments still render. Video URL markers are delegated to `VideoAttachmentView`, which validates the local file before player/reveal/export actions.

### Provider/API Contract

No `APIProtocol`, factory, or service-selection change. `VeoHandler` continues to:

- authenticate through existing configured credential handling;
- poll and download completed video output with cancellation/failure propagation;
- return a local `file://` URL encoded as `<video-url>…</video-url>` only after the local result exists;
- avoid logging API keys, authorization headers, prompts, or private attachment bytes.

Generated-video URLs are explicitly transient and are not persisted as a new Core Data media record. A missing local URL is rendered as unavailable rather than retried automatically or crashing.

### Persistence and Migration

**No schema change.** Existing `ImageEntity` and `FileEntity` retain durable image/file content referenced by UUID markers. Existing chats continue to resolve through `BackgroundDataLoader`; unreadable/missing bytes produce a nonfatal unavailable state. No model version, migration, or destructive store operation is required. Generated videos remain ordinary temporary local files and may be unavailable after restart or cleanup.

### Security and Privacy

- File selection and export use system UI; no attachment is uploaded except within an explicit user send to the chosen provider.
- User-facing errors disclose operation status, not credentials, authorization values, extracted private content, or unnecessary absolute paths.
- Export produces a copy and never deletes/replaces a destination automatically.
- File/video URLs are validated as local/readable before reveal, playback, or saving.
- Runtime diagnostics use existing logging facilities and redact secrets.

## Project Structure

### Feature Documentation

```text
specs/006-attachments-media/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── contracts/
│   └── attachment-message-contract.md
├── quickstart.md
└── tasks.md
```

### Source Paths

```text
Warden/
├── Models/
│   ├── FileAttachment.swift
│   └── ImageAttachment.swift
├── Store/
│   └── ChatStore.swift
├── UI/
│   ├── Components/FilePreviewView.swift
│   └── Chat/
│       ├── BottomContainer/MessageInputView.swift
│       ├── BubbleView/MessageContentView.swift
│       ├── BubbleView/VideoAttachmentView.swift
│       ├── QuickChatView.swift
│       └── ZoomableImageView.swift
└── Utilities/
    ├── APIHandlers/VeoHandler.swift
    ├── AttachmentResolver.swift
    ├── BackgroundDataLoader.swift
    ├── IncrementalMessageParser.swift
    └── MessageParser.swift

WardenTests/
└── Utilities/
```

**Structure Decision**: Extend the existing Models, Utilities, Store, and UI ownership boundaries. Tests live in their existing XCTest targets. Create only focused helper/test files if existing types cannot safely host a pure, independently testable seam.

## Test and Verification Plan

1. **Regression first**: Add failing parser/resolver/model tests for ready vs. failed attachments, malformed UUID/video markers, unavailable historical media, and no-silent-omission sending.
2. **Focused unit tests**: Run `MessageParserTests`, new attachment preparation/resolution tests, and any Veo response/file URL tests with fixtures only.
3. **UI workflow**: Add accessibility-driven XCUITest coverage where stable; manually validate NSOpenPanel/NSSavePanel, Finder reveal, AVKit playback, and zoom gestures using `quickstart.md`.
4. **Build**: Build via the Xcode project/scheme command after focused tests pass.
5. **Full tests**: Run repository-wide tests before merge; record only real local-environment blockers.
6. **Privacy review**: Inspect attachment logging, persistence fields, failure strings, and provider request construction for credentials/private-content leakage.

## Delivery Phases

### Phase 0 — Characterize Existing Behavior

- Locate the chat composition/persistence entry points and catalog current attachment serialization.
- Add regression tests around message marker parsing, attachment readiness, and unavailable resolution before behavior changes.

### Phase 1 — Durable Attachments and Send Integrity

- Harden `ImageAttachment`/`FileAttachment` preparation states, multi-item completion, cancellation/error behavior, and read/decode validation.
- Ensure the store persists ready images/files before UUID markers are saved; prevent sends that silently drop selected content.
- Preserve migration-free compatibility with historical conversations.

### Phase 2 — Resolution, Rendering, and Generated Video

- Improve resolver/background-loader failure results and element-local unavailable UI.
- Complete image/file rendering and interaction paths; retain marker parsing across ordinary and incremental parsing.
- Validate transient local video availability, player initialization, cancellation/error messaging, and secure Veo handling.

### Phase 3 — Native macOS Interaction

- Refine draft previews, removal, accessibility labels, and send readiness in the input UI.
- Make image zoom and video playback/reveal/save actions keyboard-accessible and safe.
- Consolidate copy/export semantics as needed without new third-party dependencies.

### Phase 4 — Verification and Documentation

- Run focused tests, build, full tests, and manual attachment/video workflow.
- Verify no schema migration is required and no logs/UI expose secrets or private content.
- Update feature documentation/tests to reflect durable images/files and transient videos.

## Complexity Tracking

No constitution-gate violation or new abstraction is planned.
