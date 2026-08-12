# Research: Chat Organization and Sharing

## Existing Capability Assessment

### Decision: Extend the existing organization, branching, and sharing surfaces

**Rationale**: The repository already implements the feature’s central behavior:

- `ChatListView` provides a debounced background Core Data search across name, system message, persona name, and message body, pin-first ordering, date grouping, selection, and archived-project expansion.
- `ChatBranchingManager` produces an independent child chat, copies history through a selected message, preserves source settings and project/persona context, saves atomically through the current context, and reports failures.
- `BranchPopover` supplies model selection, progress, retry, dismissal, and branch opening.
- `ChatShareMenu` exposes native share, clipboard, and save actions in Markdown, plain text, and JSON.
- `ProjectSummaryView` already derives local-only activity and statistics using a background Core Data context.

A parallel replacement would duplicate persistence and risk incompatibility with live chat data.

**Alternatives considered**:

1. Build a new organization store or sidebar: rejected; existing `ChatListView` and `ChatStore` own the related state.
2. Add an AI-generated project summary: rejected by product clarification and privacy-first constraints.
3. Add cloud/shared export links: rejected as out of scope and incompatible with local-first disclosure.

## Decision: Retain the current Core Data model

**Rationale**: `ChatEntity` already contains project, persona, pinning, provider, system message, and branch ancestry fields. `ProjectEntity` exposes archived state. No new persisted field is necessary to satisfy the selected requirements.

**Alternatives considered**: Adding an export-history or share-audit entity was rejected because it retains privacy-sensitive information without a user need and creates migration risk.

## Decision: Harden sharing with a value formatter and controlled temporary-file lifecycle

**Rationale**: The current sharing service builds a predictable three-format representation but creates a temporary URL with the raw chat name, silently ignores write errors, and leaves lifecycle ownership unclear. Introduce a focused formatter/export representation that can be unit tested without AppKit presentation, sanitize suggested filenames, create a unique file with restricted permissions, and report creation/write errors before presenting the native share picker. The share picker remains the macOS disclosure boundary.

**Alternatives considered**:

1. Share raw `String` directly: rejected because native services may need a file and no filename/content-type contract is retained.
2. Persist export files in app storage: rejected; user content should not be retained without explicit save.
3. Use `try?` for temporary output: rejected because it can present a non-existent file with no actionable feedback.

Temporary share files are deleted when the picker is dismissed without selecting a service or when the sharing service reports success or failure. A bounded five-minute expiry is retained as a privacy fallback if AppKit does not yield any picker/service callback; this is a safeguard, not persisted export history.

## Decision: Preserve current search and branch architecture; add regression seams

**Rationale**: Search is already cancellable and runs Core Data fetches on a background context. Branching already validates deleted/mismatched objects and rolls back on save failure. Extract or expose small pure helpers only where required for deterministic XCTest, then add in-memory Core Data tests for copied branch history, source immutability, export ordering, and secret exclusion. Keep UI ownership in existing SwiftUI views.

**Alternatives considered**: Full UI automation for every branch/export condition was rejected because native sharing and save panels are not deterministic without test-specific automation; their pure/service behavior is more reliable in unit tests.

## Decision: Use modern SwiftUI patterns only in touched UI

**Rationale**: Touched controls should remain native `Button`/`Menu` controls with explicit accessibility labels and hints, private state, stable `ForEach` identity, and `animation(_:value:)`. No iOS-26-only cosmetic API is necessary for this macOS feature.

**Alternatives considered**: Broad migration of existing styling APIs (for example all `foregroundColor` or `cornerRadius` calls) is out of scope and increases regression surface.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Conversation content exposed via a share/export action | Keep actions explicit, retain native save/share controls, exclude secrets/headers/diagnostics, and document user-controlled disclosure. |
| Temp-file collisions or stale content | Use a generated unique filename and delete temporary data after picker completion/cancellation where the platform callback permits. |
| Core Data thread misuse | Keep managed objects/context work on their owner context; pass IDs/primitives across contexts only. |
| Search staleness while typing | Keep cancellation and only apply a non-cancelled result for the active query. |
| Branch rollback leaves partial data | Preserve the existing save/rollback path and add in-memory regression coverage. |
| Paid credentials required for verification | Use in-memory Core Data fixtures and no network provider invocation. |
