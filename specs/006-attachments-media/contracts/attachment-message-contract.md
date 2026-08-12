# Attachment Message Contract

## Durable message markers

| Marker | Payload | Producer | Consumer | Failure behavior |
|---|---|---|---|---|
| `<image-uuid>UUID</image-uuid>` | UUID of a persisted image | Message composition/persistence | `MessageParser`, `AttachmentResolver`, `MessageContentView` | Render unavailable attachment state if UUID cannot resolve. |
| `<file-uuid>UUID</file-uuid>` | UUID of a persisted file | Message composition/persistence | `MessageParser`, `AttachmentResolver`, `MessageContentView` | Render unavailable attachment state if UUID cannot resolve. |
| `<video-url>file://…</video-url>` | Local transient video URL | Video handler after completed download | `MessageParser`, `MessageContentView`, `VideoAttachmentView` | Render unavailable/error state if URL is malformed or file is absent. |

## Outgoing request contract

- A ready image attachment becomes the provider’s established image-content representation.
- A ready file attachment becomes its existing text/content representation.
- The image/file Core Data save must succeed before composition emits that attachment's UUID marker. If it fails, composition keeps the draft intact and sends no partial marker set.
- Loading or failed attachments are excluded from transmission and must prevent a send action that would silently omit user-selected content.
- Attachment content leaves the device only as part of the user’s explicit send action.
- Credentials, authorization headers, and internal filesystem paths are never included in attachment-marker content or user-visible errors.

## Export contract

- Export creates a user-selected copy; it never mutates or deletes the attachment source.
- Cancelling a save panel is a no-op.
- If the destination exists, the UI must ask the system/user to resolve the conflict or fail safely; code must not delete the destination automatically.
- Reveal is enabled only for an existing local file and reports an attachment-local error otherwise.
