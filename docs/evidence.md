# Evidence packet

This file records the evidence used to write the WardenApp documentation set. It is intentionally concise and should be refreshed after substantial source changes.

## Repository evidence

- Repository root: `/Volumes/WDBlack4TB/Code/WardenApp`.
- Xcode project: `Warden.xcodeproj`.
- Application target: `Warden`.
- Unit-test target: `WardenTests`.
- UI-test target: `WardenUITests`.
- Shared test plan: `Warden.xctestplan`.
- Core Data model: `Warden/Store/wardenDataModel.xcdatamodeld/`.
- Local package roots: `Packages/flux.swift` and `Packages/MLXZImageSwift`.
- Auxiliary CLI target: `MLXZImageSwiftCLI`.
- Feature specifications: `specs/001` through `specs/012`.

## Codebase-memory evidence

The repository was already indexed before documentation work and reported:

- Project: `Volumes-WDBlack4TB-Code-WardenApp`.
- Status: ready.
- Nodes: 6,369.
- Edges: 16,380.
- The post-documentation fast index reported `ready`; generated documentation was excluded from the source graph by the indexer.
- Main structural packages: Utilities, UI, Models, Persistence, Store, Core, Configuration, AppShell, and test support.

The graph was used to locate and trace the following implementation areas:

- `WardenApp`, `ContentView`, and the application shell.
- `ChatStore`, `PersistenceController`, and `DatabasePatcher`.
- `APIServiceFactory`, `APIServiceManager`, `APIService`, and provider handlers.
- `MessageManager`, `ChatStreamingSession`, and `StreamingTaskController`.
- `TavilySearchService` and search message integration.
- `MCPManager` and `MCPServerConfig`.
- `MultiAgentMessageManager`, `QuickChatView`, and `FloatingPanelManager`.
- Attachment, branching, sharing, hotkey, model metadata, and local-generation services.

## Direct source evidence

The documents were checked against:

- `README.md` for project scope, layout, setup, testing, and security notes.
- `AGENTS.md` for architecture boundaries, commands, style, and no-paid-credential test policy.
- `CLAUDE.md` for feature inventory and source organization, with conflicts resolved against the current checkout and `AGENTS.md`.
- `Setup.MD` for the OpenRouter user workflow and the current Keychain storage guidance.
- `Warden/WardenApp.swift` for startup, menus, persistence fallback, and test modes.
- `Warden/Configuration/AppConstants.swift` for provider defaults, request timeout, search, hotkey, multi-agent, and Quick Chat limits.
- `Warden/Utilities/APIProtocol.swift` for the internal provider contract and error classes.
- `Warden/Utilities/APIServiceFactory.swift` and `APIHandlers/` for provider creation and handler boundaries.
- `Warden/Utilities/APIServiceManager.swift` for endpoint, credential transport, lifecycle, and streaming rules.
- `Warden/Utilities/TokenManager.swift` for current Keychain storage behavior.
- `Warden/Utilities/DatabasePatcher.swift` for migrations and compatibility patches.
- `Warden/Core/MCP/MCPManager.swift` and `MCPServerConfig.swift` for MCP transports, statuses, tools, and secret markers.
- `Warden/Store/wardenDataModel.xcdatamodeld/.../contents` for entity, attribute, and relationship definitions.
- The twelve `spec.md` files for user stories, functional requirements, and edge cases.

## Commands and checks performed before writing

- Confirmed the repository exists and is the Git root.
- Confirmed the starting Git worktree was clean.
- Confirmed the existing codebase-memory project was ready.
- Ran `xcodebuild -project Warden.xcodeproj -list` successfully; package resolution completed and targets/schemes were listed.
- Searched for `.sdd`; no `.sdd` directory was present.
- Searched for versioned YAML/YML workflows; no workflow files were found in the checked path.
- Searched for a versioned `.swift-format`; none was found in the checked path.
- Confirmed the current entitlements enable App Sandbox, network client/server, and user-selected read/write access.

## Evidence gaps

These gaps are stated explicitly rather than filled with assumptions:

- A full clean build and complete test run were not used as evidence while drafting this packet; they must be run during final validation.
- No public HTTP contract or OpenAPI document was found. Provider endpoints remain external integration details.
- No complete CI/CD, notarization, or publishing workflow was found.
- External provider model availability and pricing were not verified and are not promised by these documents.
- The repository contains an existing `CLAUDE.md` statement about a `.swift-format` file, but no such file was found in the current checkout; the documentation follows the current file inventory and `AGENTS.md`.
- The current `Setup.MD` is aligned with `TokenManager.swift`; older installed Keychain items may still exist and should be handled only through explicit cleanup.

## Maintenance rule

When a source or requirement changes:

1. Update the implementation/specification first.
2. Refresh the affected document and this evidence packet.
3. Run Markdown and Git checks.
4. Build and test the affected target.
5. Re-index with `codebase-memory` and confirm the project is ready.
