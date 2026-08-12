# Native Web Search UI Contract

## Search Enable Control

- **Location**: Chat message input toolbar.
- **Action**: Toggle web search for the next send only; normal chat remains unchanged while disabled.
- **First enable**: Present one concise, accessible disclosure: “Web Search sends the current message query to Tavily. Your other chat history is not sent.”
- **Disclosure actions**: Continue enabling search; open Web Search preferences; cancel/leave search disabled.
- **Persistence**: Store only local acknowledgement that the disclosure was shown. Do not store the query in preferences.
- **Accessibility**: Label must state whether web search is enabled; help text explains it applies to the next message.

## Search Status Presentation

| State | Required UI behavior |
|---|---|
| searching / fetching / processing | Show accessible progress above composer; keep cancellation available. |
| completed | Briefly show completion, then dismiss; source metadata remains attached to response. |
| failed | Show actionable error and clear progress. Preserve prompt unsent. |
| cancelled | Dismiss progress and persist neither partial sources nor search context. |

## Search Failure Actions

- **Retry**: Resubmit the unchanged preserved prompt with search enabled.
- **Settings**: Open the Web Search preferences tab for missing/invalid credentials.
- **Disable Search**: Switch off search, restore the unchanged prompt to the composer, and require the user to press Send explicitly.
- **Dismiss**: Remove error presentation while retaining the unsent prompt in the composer.

## Source and Citation Presentation

- Show message-owned ordered sources after a web-assisted assistant response, including title, visible URL/domain, relevance display, and optional date.
- A source title/URL must remain visible even if non-actionable.
- Only absolute HTTPS URLs with a host receive an Open action, hand cursor, or clickable inline citation.
- Valid standalone `[n]` citation text maps only to the same message’s nth actionable source. Out-of-range, malformed, embedded, and non-HTTPS citations remain plain text.
- Source controls expose accessible names including source number and title; collapsed/expanded controls expose their state.
