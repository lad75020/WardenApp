# Rendering Contract

## Input
Existing message string plus presentation context: sender role, streaming state, font size, and color scheme.

## Output
An ordered, transient sequence of message elements for plain text, tables, fenced code, display mathematics, reasoning, and existing attachment markers.

## Safety
- Unknown or malformed syntax degrades to selectable text.
- Streaming input may expose only finalized blocks plus a readable pending segment.
- HTML previews use local, nonpersistent rendering with scripts, navigation, networking, forms, frames, and external content blocked.
- Source text is copied without transformation; no response body is emitted to diagnostics.
