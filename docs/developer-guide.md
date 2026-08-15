# Developer guide

This guide is for contributors changing the WardenApp source, tests, Core Data model, or local packages.

## Repository layout

| Path | Responsibility |
| --- | --- |
| `Warden/` | Main macOS application source, resources, Core Data model, and entitlements |
| `Warden/UI/` | SwiftUI views, view models, settings, chat rendering, previews, and onboarding |
| `Warden/Models/` | Core Data classes and shared value models |
| `Warden/Store/` | `ChatStore` and `wardenDataModel.xcdatamodeld` |
| `Warden/Utilities/` | Provider handlers, managers, streaming, search, sharing, attachments, and integrations |
| `Warden/Core/MCP/` | MCP configuration and runtime management |
| `Warden/Configuration/` | Application-wide constants and defaults |
| `WardenTests/` | Unit and integration-oriented XCTest coverage |
| `WardenUITests/` | XCUITest coverage, including shell and persistence recovery paths |
| `Warden.xctestplan` | Shared test plan |
| `Packages/` | Local Swift package boundaries, including Flux and MLX image support |
| `MLXZImageSwiftCLI/` | Auxiliary local command-line target |
| `scripts/` | Repository-local helper scripts |
| `specs/` | Feature specifications, plans, tasks, and contracts |

## Build and test

Build the application for macOS:

```bash
xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build
```

Run all tests for the macOS destination:

```bash
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'
```

Run the shared test plan:

```bash
xcodebuild -project Warden.xcodeproj -scheme Warden -testPlan Warden test
```

Run one test:

```bash
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/TestClassName/testMethodName
```

Open the project in Xcode for previews and UI interaction:

```bash
open Warden.xcodeproj
```

The project currently resolves both local and remote Swift packages. A first build may require package-network access.

## Source conventions

- Use PascalCase for types and camelCase for members.
- Follow the established four-space indentation and approximately 120-character line style.
- Use `@StateObject` for an object owner, `@ObservedObject` for a passed object, and `@EnvironmentObject` for shared environment state.
- Use `async`/`await` for asynchronous work and move expensive work away from the main actor when safe.
- Use `WardenLog` instead of `print`.
- Never log API keys, authorization headers, complete prompts, raw provider bodies, or private tool results.
- Use preview fixtures through the existing preview state helpers rather than real services.

`AGENTS.md` notes that no formatter configuration is currently versioned. Keep the established style and do not describe formatting as an automated repository gate unless a formatter configuration and check are added.

## Ownership and module boundaries

- UI owns presentation and user interaction.
- Models own shared data representations and must not depend on concrete views.
- Utilities own integrations, parsers, managers, and transport.
- `APIHandlers` own provider-specific request and response behavior.
- Store owns Core Data and durable chat/project operations.
- MCP core owns MCP configuration, transports, tools, and agent status.
- Tests must not require paid provider credentials.

Shared hotspots need coordinated changes:

- `Warden/Store/ChatStore.swift`
- `Warden/Utilities/APIHandlers/APIProtocol.swift`
- `Warden/Utilities/APIServiceFactory.swift`
- `Warden/Utilities/APIServiceManager.swift`
- `Warden/Utilities/MessageManager.swift`
- `Warden/Store/wardenDataModel.xcdatamodeld/`
- `Warden.xcodeproj/`

## Adding a provider

1. Define a stable provider type and safe default configuration.
2. Decide whether an existing compatible handler can be reused.
3. Add a dedicated handler only for provider-specific request, authentication, or response behavior.
4. Register the type in `APIServiceFactory`.
5. Confirm model discovery, streaming, image-upload, vision, and media flags.
6. Use the shared sensitive-transport validation.
7. Add tests for valid responses, malformed responses, auth errors, rate limits, timeouts, cancellation, and stream boundaries.
8. Update `docs/provider-reference.md` and the matching feature specification.

## Adding a persisted field

1. Update the Core Data model.
2. Decide whether the field is secret, configuration, message content, or derived metadata.
3. Keep secrets out of Core Data.
4. Add upgrade and malformed-value behavior.
5. Add fresh-store and migrated-store tests.
6. Verify that unavailable relationships do not delete user data.
7. Update `docs/data-and-persistence.md`.

## Adding a request flow

1. Start from the originating chat identity, service identity, and model.
2. Validate the prompt and request options before persisting or sending.
3. Prepare the request through the service abstraction.
4. Use `ChatStreamingSession` and `StreamingTaskController` for cancellable streams.
5. Keep search, MCP, attachment, and media state separate from provider transport state.
6. Persist the final result once.
7. Clear waiting state for success, failure, and cancellation.
8. Ensure late callbacks cannot target a new chat or newer request.
9. Add tests for switching chats, deletion during work, cancellation timing, and repeated callbacks.

## Testing without paid credentials

Unit and UI tests should use:

- In-memory Core Data where appropriate.
- Existing mock/fake services and fixture paths.
- Local Ollama/LM Studio only when a test explicitly requires a local runtime.
- Deterministic parser data and mock streams.
- Persistence recovery fixture launch arguments.

Do not commit credentials, local filesystem secrets, real prompts from private conversations, or provider response bodies.

## Persistence recovery test modes

`WardenApp` recognizes launch arguments and environment values used by persistence recovery UI tests, including the App Shell UI test mode and isolated persistent fixture settings. Read the current test support classes before adding a new fixture variable; do not invent a new environment contract in documentation alone.

## Codebase memory

The repository uses the dedicated `codebase-memory-mcp` service for structural code analysis. After substantial source or documentation changes:

1. Confirm the repository root.
2. Check the current project index status.
3. Re-index the repository with the appropriate fast/moderate/full mode.
4. Confirm the resulting project is ready.
5. Use the graph to verify new symbols or changed ownership when relevant.

## Documentation workflow

For a feature change:

- Update the relevant `specs/*/spec.md`, plan, or task artifact.
- Update the appropriate technical and functional documents.
- Add a source path and test path for non-obvious behavior.
- Run Markdown checks, `git diff --check`, build, and tests.
- Review the final diff for secrets, stale commands, and unsupported claims.
