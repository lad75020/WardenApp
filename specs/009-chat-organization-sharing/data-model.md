# Data Model: Chat Organization and Sharing

## Migration Decision

**No Core Data schema change.** The existing model supports the feature. Existing user data is read in place; no migration, version bump, or backfill is planned.

## Persisted Entities

### ChatEntity

| Field / relationship | Role in this feature | Validation / invariant |
|---|---|---|
| `id`, `name`, `createdDate`, `updatedDate` | Search, display, output metadata, safe suggested filename source | Identifier remains stable; generated filename must not use untrusted path components. |
| `systemMessage`, `gptModel`, `behavior`, `temperature`, `top_p` | Full export context and branch settings | Export includes system instruction when non-empty; branch copies settings. |
| `messages` / `requestMessages` | Search, ordered export, branch history | Export order is chronological; branch receives only entries through the selected source message. |
| `isPinned`, `project`, `persona`, `apiService` | Organization, search, export metadata, branch context | Existing relationships survive all operations. |
| `parentChat`, `branchSourceMessageID`, `branchSourceRole`, `branchRootID` | Branch ancestry | A branch is a distinct chat; source chat/messages are never mutated by branch creation. |

### MessageEntity

| Field | Role | Validation / invariant |
|---|---|---|
| `id`, `timestamp`, `own`, `body`, `name` | Ordered display/export and copied branch history | No content mutation in source branch flow. |
| Provider/tool/search metadata | Historical fidelity in a branch | Copy only fields already supported by `ChatBranchingManager`; do not add secret-bearing data to export. |

### ProjectEntity

| Field / relationship | Role | Validation / invariant |
|---|---|---|
| `name`, `projectDescription`, `colorCode`, `isArchived`, `chats` | Project navigation and local descriptive summary | Archive state remains visible and does not delete or implicitly restore chats. |

## Transient Types

### ChatExportFormat

Existing three case value: Markdown (`.md`), plain text (`.txt`), JSON (`.json`).

### Proposed Export Representation

A non-persisted formatter result owned by `ChatSharingService` may contain:

| Field | Purpose |
|---|---|
| `content` | Fully formatted conversation: metadata, system instruction when present, ordered messages. |
| `format` | Chosen file extension/content type and presentation label. |
| `suggestedFilename` | Sanitized local filename derived from a chat title, never a path. |

The exact type may remain private to `ChatSharingService` if it enables focused testing without increasing shared model surface.

## State Transitions

```text
Search: idle -> debouncing -> searching -> results | idle
Branch: ready -> creating -> saved -> opened
                       \-> failed -> retry | dismissed
Export: ready -> formatted -> save panel/share picker -> saved/shared | cancelled | failed
```

- Cancellation returns the export flow to `ready` without creating a user-selected destination file.
- Temporary sharing output is transient, unique, and removed as soon as it is safe to do so.
- A save/write failure does not modify chat/project/message persistence.

## Privacy Boundaries

- No export-history, analytics, or new content persistence is introduced.
- Outputs omit API keys, authorization headers, internal diagnostics, and service-secret material.
- Full chat metadata, system instruction, and messages are disclosed only after the user explicitly selects copy, save, or share.
- Local project summaries never invoke a provider or send conversation content over the network.
