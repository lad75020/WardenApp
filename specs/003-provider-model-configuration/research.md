# Research: Provider and Model Configuration

## Decisions

### D1 — Keep service metadata and credentials separate

**Decision**: Continue persisting only non-secret service metadata in `APIServiceEntity`; use `TokenManager`/Keychain for all credentials, keyed by the service's stable UUID.

**Evidence**: Existing view-model save/load and `APIServiceManager.createAPIConfiguration` already resolve credentials through `TokenManager`. `TokenManager` migrates legacy per-item entries into its Keychain bundle.

**Rationale**: This meets the privacy-first constitution without schema migration or credential duplication.

### D2 — Clear the default when its service is deleted

**Decision**: After a successful persistent deletion of the default service, clear `defaultApiService`; never silently choose a fallback.

**Evidence**: Laurent selected this behavior during clarification on 2026-08-11.

**Rationale**: Automatically moving future chats to another provider may create unexpected privacy, billing, or model-routing consequences.

### D3 — Centralize lifecycle transactions in `APIServiceManager`

**Decision**: The manager should coordinate Core Data persistence, Keychain token lifecycle, and default cleanup. Views/view models should call it and render structured outcomes.

**Evidence**: Current list and detail views directly duplicate/delete/persist entities, while token operations are split among UI code. This risks copied credentials being written before Core Data save succeeds and service deletion not removing credentials/default state.

**Rationale**: One service boundary makes transaction ordering testable and prevents UI-specific persistence logic.

### D4 — Validate sensitive transport before creating a request

**Decision**: Apply the existing `URL.allowsSensitiveTransport` policy before save, model discovery, or connection test when a token is present. Permit HTTPS and loopback/local addresses; reject remote HTTP.

**Evidence**: `APIServiceDetailViewModel.saveAPIService` already enforces this for save but test/model-fetch paths currently build requests independently.

**Rationale**: A test/refresh must not become a bypass that sends a credential over plaintext transport.

### D5 — Preserve the factory and URL-session policy

**Decision**: Keep `APIServiceConfig → APIServiceFactory → APIService` as the client construction path, including request/resource timeout, waits-for-connectivity for local services, disabled URL cache, and per-host connection limits.

**Evidence**: `APIServiceFactory` owns provider selection and standard/streaming session settings.

**Rationale**: Bypassing it risks inconsistent provider mapping, timeout behavior, caching, and local-server support.

### D6 — Model fetches/tests must be user initiated and stale-safe

**Decision**: The detail view model owns cancellable operations and rejects results from an earlier endpoint/type/token/model generation. Failure keeps the last persisted selection.

**Evidence**: Current fetch starts from initialization and token/type changes, and a task may return after inputs change.

**Rationale**: This avoids accidental network requests, misleading model lists, and stale UI mutation while preserving a known-good saved model.

### D7 — Keep local-model permissions explicit

**Decision**: Local MLX/CoreML model folders retain their security-scoped bookmark path. Prompt only from an explicit grant-access/test action; cancellation/denial does not write a changed path.

**Evidence**: The existing settings view has `NSOpenPanel` and `SecurityScopedBookmarkStore` integration.

**Rationale**: This respects macOS sandbox/file authority and prevents surprising permission prompts.

## Rejected Alternatives

- **Store credentials directly on `APIServiceEntity`**: rejected because Core Data is not a secret store and would violate the constitution.
- **Auto-select any remaining service after deleting default**: rejected by product clarification; it could route a chat to an unintended provider.
- **Add a new provider abstraction or network dependency**: rejected because current protocol/factory abstractions already cover all supported types.
- **Use raw `URLSession` from Settings views**: rejected because it would bypass provider-specific behavior and established session policy.
- **Treat discovery lists as authoritative**: rejected because providers/local models may accept valid custom identifiers and discovery can fail transiently.
