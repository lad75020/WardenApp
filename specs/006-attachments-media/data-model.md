# Data Model: Attachments and Media

## Existing persisted entities (no schema change)

### ImageEntity / ImageAttachment

| Field | Meaning | Validation / lifecycle |
|---|---|---|
| `id` | Stable attachment reference used in a message marker | Required UUID; immutable after attachment is stored. |
| `image` | Renderable image bytes | Must decode before marking ready. |
| `thumbnail` | Smaller representation for previews/history | May be regenerated from valid image bytes. |
| `imageFormat` | Original format identifier | Best effort; never trusted over decodability. |

**Lifecycle**: selected → loading → ready or failed → stored when message is persisted → resolved or unavailable when history is rendered.

**Persistence ordering**: `saveToEntity` reports success only after the supplied Core Data context has saved. Composition must not serialize this attachment's UUID marker when that save fails, so a historical marker never intentionally precedes its durable record.

### FileEntity / FileAttachment

| Field | Meaning | Validation / lifecycle |
|---|---|---|
| `id` | Stable attachment reference used in a message marker | Required UUID; immutable after storage. |
| `fileName` | User-visible source filename | Display only; must not be treated as a path. |
| `fileSize` | Source byte count | Non-negative; used for display. |
| `fileType` | Best-effort type/extension classification | Used to select preview and request representation. |
| `textContent` | Extracted readable content or binary fallback | Must remain safe to display and request only after preparation succeeds. |
| `imageData` / `thumbnailData` | Optional renderable file-image bytes | Decode defensively on history resolution. |

**Lifecycle**: selected → loading → ready or failed → stored when message is persisted → resolved or unavailable when history is rendered.

**Persistence ordering**: `saveToEntity` reports success only after the supplied Core Data context has saved. Composition must not serialize this attachment's UUID marker when that save fails, so a historical marker never intentionally precedes its durable record.

## Transient entity

### Generated video

| Field | Meaning | Validation / lifecycle |
|---|---|---|
| `fileURL` | Local temporary result location embedded in the message’s video marker | Must be a local readable file before playback, reveal, or export. |
| `availability` | Derived state: available, loading, unavailable, export failed | Never persisted as a durable media record. |

**Lifecycle**: request started → service operation pending → local file available or failed/cancelled → rendered while available → unavailable after removal or restart if the temp file no longer exists.

## Relationships and integrity

- A message may contain zero or more stable image/file UUID markers and zero or more transient video URL markers.
- Stored image/file UUIDs resolve through the existing persistence loader; an unresolved UUID is displayed as unavailable and must not prevent rendering other message elements.
- An attachment is only serialized into a sendable message after it reaches the ready state.
- There is no new Core Data model version or migration for this feature.
