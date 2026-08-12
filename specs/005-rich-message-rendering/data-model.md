# Data Model: Rich Message Rendering

## Persisted data

No Core Data entity, attribute, relationship, or migration changes are required. Existing message text remains the sole persisted source.

## Transient entities

| Entity | Fields | Lifecycle |
|---|---|---|
| Message element | type plus text/code/table/formula/reasoning/attachment payload | Derived from message text; discarded when the view is released or message changes. |
| Parse session | source length, partial elements, cancellable task/parser state | Owned by `MessageContentView`; reset when streaming finishes or source changes. |
| Preview state | visibility, viewport, zoom, refresh token | Owned by `CodeView`; never persisted. |

## Invariants

- Element ordering matches source ordering.
- Parsing failure never deletes or alters persisted source text.
- Preview state and rendered content never enter Core Data or diagnostics.
