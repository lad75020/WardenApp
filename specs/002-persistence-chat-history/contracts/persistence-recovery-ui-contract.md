# Persistence Recovery UI Contract

## Purpose

Defines the native macOS contract between chat persistence availability, user-visible recovery presentation, and explicit recovery operations. This is an internal app UI contract, not a network API.

## Inputs

| Input | Source | Requirements |
|---|---|---|
| `chat` | Existing `ChatEntity` | Identifies retained history; never display credentials or raw diagnostic payloads. |
| `availability` | `ChatStore` classification using current service validation | Distinguish available, missing service, invalid service, and no repair candidate. |
| `repairCandidates` | `ChatStore` valid-service lookup | Include only locally configured services that pass existing validation; do not fetch network data. |

## User-visible States

| State | Required content | Interaction |
|---|---|---|
| Available | Existing chat presentation | Existing behavior unchanged. |
| Unavailable with candidates | Textual unavailable status plus the retained chat identity/history context | Sending is disabled. Provide a labeled Repair control that opens a candidate selector and a labeled Delete control with confirmation. |
| Unavailable without candidates | Textual unavailable status and a non-sensitive explanation that no usable service is configured | Sending is disabled. Provide Open Service Settings and Delete controls; preserve chat in place. |
| Repair save failure | Non-sensitive failure message | Keep chat unavailable and keep all history intact; allow retry/cancel. |

## Operations

### `repair(chat, selectedService)`

- Preconditions: target chat exists; selected service is a current valid repair candidate.
- Effect: assign `selectedService` to the existing chat and persist through `ChatStore`.
- Postconditions: message sequence, request messages, project, persona, chat ID, and existing metadata are unchanged; chat reclassifies as available.
- Failure: leave the service relationship/history unchanged where save fails; present non-sensitive recovery feedback.

### `openServiceSettings(chat)`

- Preconditions: chat remains unavailable and no valid repair candidate exists.
- Effect: open the application’s existing service settings flow.
- Postconditions: no chat/service data is created or altered by this operation. After the user creates/fixes a service, they must explicitly choose repair.

### `delete(chat)`

- Preconditions: explicit destructive confirmation.
- Effect: clear a selected reference to this chat, then use existing Core Data deletion/save behavior.
- Postconditions: only the selected chat and its normal Core Data deletion effects are removed.

## Accessibility and Keyboard Requirements

- The unavailable state has a concise visible text label and VoiceOver description; color/icon alone is insufficient.
- Repair, Open Service Settings, Delete, candidate selection, confirmation, cancel, and failure/retry controls have explicit accessibility labels.
- Keyboard focus order follows: unavailable summary → Repair or Open Service Settings → Delete → candidate selection/confirmation controls.
- Delete is visually and semantically destructive and requires confirmation; Repair is the default non-destructive path when candidates exist.
- Enlarged text must retain action labels without clipping; no hover-only access to recovery controls.

## Non-goals

- No inline editing or creation of service configuration.
- No credential entry or Keychain access in recovery presentation.
- No telemetry, remote sync, or remote recovery request.
