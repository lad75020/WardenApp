# Native macOS UI Contracts

## Conversation Search

| Trigger | Contract |
|---|---|
| User changes the sidebar search query | Results are debounced, previous search work is cancelled, and a non-cancelled result for the active query replaces visible results. |
| User clears search or presses Escape | Query and result filtering clear; keyboard focus is dismissed without modifying conversations. |
| Search result | Matches title, system instruction, persona name, or message body with case/diacritic-insensitive local matching. |

## Organization

| User action | Contract |
|---|---|
| Pin/unpin | Persists the existing `isPinned` flag and displays pinned chats before date-grouped unpinned chats. |
| Move/rename/clear/delete | Uses current confirmation/error behavior; a destructive action does not affect unrelated chats. |
| Expand archived projects | Reveals existing archived projects and their chats; expansion alone does not restore/archive/delete data. |
| View project summary | Shows locally derived descriptive data, loading/empty/populated states, and does not call an AI provider. |

## Branching

| User action | Contract |
|---|---|
| Choose Branch at a message | Presents available configured models and an accessible dismissal action. |
| Select model | Creates a distinct child chat with copied history through the source message, inherited settings/project/persona, and selected service/model. |
| User-message branch | May generate the next reply through the user-selected configured provider. |
| Assistant-message branch | Creates an editable continuation without an automatic reply. |
| Failure | Leaves source unchanged, shows a user-safe error, and allows retry/dismissal. |

## Copy, Export, and Share

| User action | Contract |
|---|---|
| Choose Markdown, text, or JSON | Produces the selected format with complete conversation metadata, system instruction when present, and chronological messages. |
| Copy | Replaces clipboard text only after an explicit menu action. |
| Export | Presents a native save panel with a sanitized suggested name; cancellation writes no destination file. |
| Share | Creates a unique transient local file only after explicit action, then invokes `NSSharingServicePicker`. The file is removed if the picker is dismissed without choosing a service, after a sharing callback, or after a bounded five-minute fallback expiry if AppKit provides no callback. |
| Formatting/temp/write failure | Does not show an unusable picker or alter persisted chat data; gives a user-safe actionable error and logs non-sensitive diagnostic context. |

## Accessibility and Keyboard Behavior

- Search is command-F focusable, Escape clearable, and has a descriptive label.
- Menus and buttons expose format/action labels and hints through native controls.
- Decorative icons are hidden from VoiceOver where their adjacent label already conveys the action.
- Any new animation uses an explicit value trigger.
