# Research: Rich Message Rendering

## Decisions

### Preserve the existing message-element pipeline
- **Decision**: Extend and harden `MessageParser` and existing `MessageElements` rendering rather than introduce a new persisted rich-text representation.
- **Rationale**: Existing message text is the compatibility boundary; transient parsing avoids Core Data migration and keeps old chats readable.
- **Alternatives considered**: Persisted render trees (migration and compatibility risk); a single WebView renderer (violates native UI and privacy-first design).

### Keep parsing incremental and cancellation-aware
- **Decision**: Retain incremental parsing for streaming and background parsing for long content, with final parse after streaming completes.
- **Rationale**: Avoids repeated whole-message work and stale UI updates.
- **Alternatives considered**: Reparse entire content on every chunk (poor responsiveness).

### Restrict HTML previews
- **Decision**: Preview only after explicit user action in a nonpersistent WebKit view with JavaScript, networking, external navigation, forms, and frames disabled.
- **Rationale**: The preview is visual inspection, not code execution or browsing.
- **Alternatives considered**: Full browser behavior (unacceptable disclosure and attack surface).
