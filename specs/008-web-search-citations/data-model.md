# Data Model: Web Search and Citations

## Existing Persisted Types

### `MessageSearchMetadata`

**Ownership**: One assistant `MessageEntity` owns zero or one metadata value through the optional `searchMetadataJson` field.

| Field | Type | Rules |
|---|---|---|
| `query` | `String` | Original user search query. Persist only after a successful assistant response. Retain with its local conversation until deletion. Never log. |
| `sources` | `[SearchSource]` | Ordered source list belonging only to this request/message. May be empty for an empty-result response. |
| `searchTime` | `Date` | Timestamp of completed search. |
| `resultCount` | `Int` | Non-negative count matching returned source result count. |

**Serialization and compatibility**: JSON encoded in the existing optional `MessageEntity.searchMetadataJson`. Absent, malformed, or legacy JSON decodes as `nil`, preserving messages created before the feature. No Core Data model change or migration is planned.

### `SearchSource`

| Field | Type | Rules |
|---|---|---|
| `title` | `String` | User-readable source title; preserve as returned, render safely as text. |
| `url` | `String` | Provider-supplied original URL. Keep as readable source data; it is actionable only when normalized as an absolute HTTPS URL with host. |
| `score` | `Double` | Provider relevance value used only for visual indicator; clamp UI display range. |
| `publishedDate` | `String?` | Optional provider display value. |

## Transient Types

### `SearchStatus`

States: `searching(query)`, `fetchingResults(limit)`, `processingResults`, `completed(sources)`, and `failed(error)`.

**Lifecycle**: Transition on the main UI context. A terminal completed/failed state is cleared after its defined presentation lifecycle. Cancellation clears active progress without persisting partial metadata.

### `WebSearchAttempt` (planned internal value)

A focused internal result passed from `TavilySearchService`/`MessageManager` to the specific provider send:

| Field | Type | Rules |
|---|---|---|
| `query` | `String` | Request-scoped and not logged. |
| `formattedContext` | `String` | Transient provider-only context. |
| `sources` | `[SearchSource]` | Used to persist metadata only with the resulting assistant message. |
| `actionableURLs` | `[String]` | HTTPS-only URLs corresponding to source indexes for citation conversion. |

It is never independently persisted.

### `PendingSearchSend` (planned UI state)

Represents the unchanged composer content for a failed enabled-search attempt. It is held in Chat UI/view-model state only until the user retries, dismisses, or disables search. It must not trigger an automatic provider request.

## State and Retention Rules

1. User enables search → disclosure acknowledgement may be stored locally, without query content.
2. User sends prompt → `WebSearchAttempt` remains transient while search is active.
3. Search succeeds → provider receives formatted context for that request only.
4. Assistant response persists → metadata is JSON encoded on that assistant message.
5. Search or provider request is cancelled/fails before message persistence → no new metadata is stored.
6. User deletes the conversation → existing Core Data relationship deletion removes messages and their JSON metadata.
