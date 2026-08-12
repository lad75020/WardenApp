# UI Contract: Personas and Model Selection

## Scope

This contract describes observable native macOS behavior. It does not create a network API or alter provider request contracts.

## Persona Selector

### Controls

| Control | Accessible name / state | Result |
|---|---|---|
| Persona trigger | `Assistant Personas` | Opens the persona selector for the active chat. |
| No-persona option | `No assistant` and selected state | Clears `chat.persona`; preserves current service/model. |
| Persona option | Persona name, selected state | Selects that persona; applies its system message and temperature to subsequent requests through existing request construction; preserves current service/model. |
| Apply default service | `Use <service name> default` | Present only when the selected persona has a default service. Validates its service/model before changing the active pair. |

### Explicit default-service outcomes

| Precondition | Outcome |
|---|---|
| Default service and its configured model are still selectable | Update chat service/model together, save, and recreate that chat's message manager. |
| Default service was deleted, lacks a usable provider/model, or its model is unavailable | Keep the existing active pair; show an understandable recoverable message. |
| Persona has no default service | Do not show a switch action; selection still works. |
| Context save fails | Do not report a successful selection/switch; keep or restore a consistent persisted state and show a recoverable error. |

## Model Selector

### Display rules

1. The trigger states the current provider/model or an explicit `Select Model` empty state.
2. The popover groups models by configured provider, identifies the current provider/model pair, and exposes a provider/model search field.
3. Rows use a stable provider/model identity; identical model IDs from different providers remain distinct.
4. Only valid, configured, visible, compatible model pairs are actionable.
5. Empty, loading, unavailable, malformed-preference, and metadata-absent states have clear non-sensitive text and do not crash.

### Selection action

Given an actionable model row:
1. Resolve its configured API service.
2. Update `chat.apiService` and `chat.gptModel` together.
3. Update `chat.updatedDate`, save, and refresh the relevant UI.
4. Send `RecreateMessageManager` only with the current chat ID after the save succeeds.
5. If validation/save fails, keep the prior pair and present a recoverable non-sensitive error.

## Favorites and Information

| Interaction | Required behavior |
|---|---|
| Favorite/unfavorite | Uses provider/model identity, persists locally, and immediately updates selector/favorite UI. |
| Quick access favorite | Shows only actionable configured pairs; duplicate model IDs across providers are independently identifiable. |
| Hover/details | Presents available capability, context, pricing, latency/cost, and freshness data through existing metadata UI. Missing/stale metadata produces a reduced informative state, not a block. |

## Accessibility and Keyboard Behavior

- All actions use SwiftUI `Button` controls; no primary control relies solely on `onTapGesture`.
- Primary controls provide explicit labels, hints where an outcome is not self-evident, selected values, and disabled/unavailable explanation.
- Popovers and search are keyboard navigable; default action/cancel behavior follows established macOS conventions.
- Loading/failure state changes are exposed as readable text, with no secret, endpoint, prompt, or conversation content included.

## Non-Goals

- No new AI provider or provider endpoint.
- No credential editing or secret persistence in persona/favorite metadata.
- No cloud sync, analytics, telemetry, or background catalog fetch caused merely by rendering a selector row.
