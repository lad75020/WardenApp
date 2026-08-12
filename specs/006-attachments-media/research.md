# Research: Attachments and Media

## Decision 1: Keep existing attachment persistence model

**Decision**: Persist images and file attachment metadata/content using the existing Core Data `ImageEntity` and `FileEntity` paths; do not add a schema change for this feature.

**Rationale**: `ImageAttachment` and `FileAttachment` already save renderable data and thumbnails, while `BackgroundDataLoader` resolves historical message references by UUID. This matches the approved policy to persist image and file attachments across restart.

**Alternatives considered**:
- Persist only filesystem bookmarks: rejected because moved or deleted source files would break chat history.
- Add a separate attachment entity: rejected because existing entities already represent the required durable data.

## Decision 2: Keep generated videos transient

**Decision**: Retain generated videos as local temporary files and render them only while their file URL remains accessible.

**Rationale**: This is the approved product policy. It avoids unbounded video growth in local chat storage and does not require a Core Data migration.

**Alternatives considered**:
- Persist video bytes in Core Data: rejected due to database growth and migration risk.
- Copy every generated video to an app-managed folder: rejected because it introduces retention, cleanup, and storage-policy work beyond scope.

## Decision 3: Make attachment failures explicit and non-destructive

**Decision**: Model loading/decoding errors as attachment-local UI states. Never include failed content in an outgoing request; preserve the draft and permit removal/retry.

**Rationale**: Existing attachment models already expose `isLoading` and `error`; the composition path needs to gate sending on a ready state.

**Alternatives considered**:
- Silently omit failed attachments: rejected because it violates user intent.
- Block the whole app with modal errors: rejected because an attachment failure should not interrupt unrelated chat work.

## Decision 4: Keep heavy file work off the main actor

**Decision**: Reuse `Task.detached`/background Core Data context patterns for file reads, image decoding, PDF/RTF extraction, and history resolution; marshal only state changes back to the main actor.

**Rationale**: This follows the existing model classes and the constitution’s responsiveness and actor-safety constraints.

## Decision 5: Centralize safe export behavior

**Decision**: Use a focused export helper or shared behavior used by image and video views to validate destination selection, avoid destructive replacement by default, and report failures without exposing private paths or credentials.

**Rationale**: `ZoomableImageView` and `VideoAttachmentView` currently own similar save-panel flows with inconsistent overwrite behavior.

## Decision 6: Define parser/rendering contract tests before UI changes

**Decision**: Extend parser tests for image/file/video marker validity and malformed markers, then add focused attachment model/resolver tests and manual/XCUITest coverage for the composition/export paths.

**Rationale**: Marker parsing and content resolution are deterministic seams that do not require providers or real credentials.
