# Implementation Plan: MCP Tool Integration

**Branch**: `feature/time-machine-mcp-tool-integration` | **Date**: 2026-08-12 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `/specs/011-mcp-tool-integration/spec.md`

## Summary

Specify, harden, and add deterministic test coverage to the existing MCP subsystem: server configuration (Stdio/SSE), Keychain-backed environment secret storage with reference markers, per-chat agent selection, tool discovery/execution routed to the owning server, and live + persisted tool-call progress. Preserve `MCPManager` as the single `@MainActor` coordinator and keep tool execution behind `MessageManager` without re-offering tools (loop avoidance). No Core Data schema change.

## Technical Context

**Language/Version**: Swift 5.9  
**Primary Frameworks**: SwiftUI, AppKit where required, Foundation, swift-sdk (MCP), swift-log  
**Persistence**: MCP server configs in `UserDefaults` (with Keychain secret markers); completed tool calls encoded as JSON on existing `MessageEntity`; Keychain via `KeychainAccess`/`TokenManager`  
**Testing**: XCTest (`WardenTests/`) and XCUITest (`WardenUITests/`)  
**Target Platform**: Native macOS 26.0  
**Project Type**: Xcode macOS application with unit/UI test targets and an auxiliary CLI target  
**Build Command**: `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`  
**Test Command**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'`  
**Performance Goals**: Tool-call UI updates remain actor-safe; tool execution loop honors cancellation; no main-actor blocking during subprocess I/O.  
**Constraints**: Privacy-first, no telemetry, secrets in Keychain and never logged, cancellable execution, actor-safe UI state, no live network or paid credentials in tests.  
**Scale/Scope**: Existing MCP manager/config/UI, tool-call execution in `MessageManager`, per-chat selection persistence, and focused deterministic XCTest coverage.

## Constitution Check

*GATE: Passed before research and re-checked after design.*

- [x] Native macOS and privacy-first behavior is preserved: MCP is opt-in per chat, auto-connect is off by default, remote SSE disclosure is user-controlled.
- [x] Each changed file belongs to its documented module (`Core/MCP/`, `UI/Preferences/MCP/`, `UI/Chat/`, `Utilities/`).
- [x] Tool execution routes through `MCPManager`/`MessageManager`; provider handlers stay presentation-independent and conform to `APIProtocol`.
- [x] Secrets remain in Keychain via `TokenManager`; persisted config holds only `keychain://mcp-env/...` markers; secrets excluded from logs/fixtures.
- [x] No Core Data schema change; completed tool calls reuse existing `MessageEntity.toolCallsJson` storage; existing chats stay compatible.
- [x] Async subprocess/stream work has cancellation, failure, and actor-safety behavior; SIGPIPE is ignored.
- [x] Focused deterministic XCTest coverage is identified and requires neither paid credentials nor a live MCP server.
- [x] No new package dependency or broad abstraction is required (MCP SDK + KeychainAccess already integrated).

## Architecture Impact

### Affected Modules

| Module | Path | Planned responsibility/change |
|---|---|---|
| App entry/config | `Warden/WardenApp.swift` | Preserve SIGPIPE ignore and gated auto-connect; no behavior change. |
| UI / view models | `Warden/UI/Preferences/MCP/MCPSettingsView.swift`, `AddMCPAgentSheet.swift`, `Warden/UI/Chat/MCPAgentSelector.swift`, `Warden/UI/Chat/Components/ToolCallProgressView.swift`, `Warden/UI/Chat/ChatViewModel.swift` | Preserve add/edit/test/connect UI, per-chat selection persistence, and live/persisted tool-call rendering; only defensive/clarity edits. |
| Shared models | `Warden/Models/SearchModels.swift`, `Warden/Models/Models.swift` | Preserve `WardenToolCallStatus` Codable lifecycle and `MessageEntity.toolCalls` JSON storage. |
| Services/managers | `Warden/Utilities/MessageManager.swift`, `Warden/Utilities/TokenManager.swift` | Preserve tool execution loop (cancellation, result append, no re-offer); keep Keychain bundle behavior. |
| Provider handlers | `Warden/Utilities/APIHandlers/` | Consume forwarded tools; no MCP presentation logic. |
| Persistence | `Warden/Store/` | No schema/migration change. |
| MCP | `Warden/Core/MCP/MCPManager.swift`, `MCPServerConfig.swift` | Central coordinator: config CRUD, connect/disconnect, tool discovery, secret marking/resolution, tool-owner routing, argument/result conversion. |
| Unit tests | `WardenTests/MCP/MCPToolIntegrationTests.swift` (new) | Deterministic secret marking/resolution, tool-owner routing, argument/result serialization, sensitive-key detection. |
| UI tests | `WardenUITests/` | N/A: behavior is testable below UI without a live server. |
| CLI/local packages | `MLXZImageSwiftCLI/`, `Packages/` | N/A. |

### Dependency Flow

Settings UI edits an `MCPServerConfig` → `MCPManager` (`@MainActor`) persists sanitized config (secrets → Keychain markers) → on connect, `MCPManager` resolves secrets and builds a `ProcessStdioTransport` (Stdio) or `HTTPClientTransport` (SSE) → discovered tools are cached and mapped to their owning config. In chat, `ChatViewModel` holds `selectedMCPAgents` (persisted per chat) → `MessageManager` fetches tools for selected agents, forwards them to the provider, executes returned tool calls via `MCPManager.callTool`, appends results, then requests a final response with tools disabled. Tool-call lifecycle is published for live display and encoded onto the persisted message.

### Provider/API Contract

- Tools discovered from connected servers are converted to the OpenAI-compatible tool schema in `MessageManager` before dispatch.
- `MCPManager.callTool(name:arguments:)` resolves the owning agent via a `toolOwner` map, converts `[String: Any]` arguments to MCP `Value`, and normalizes returned content (text/image/audio/resource/resource_link) to JSON-compatible dictionaries.
- The execution loop appends an assistant tool-call message and one tool-result message per call, then re-requests without tools to avoid loops.
- Failures (missing tool, disconnected agent, malformed args, cancellation) produce readable, secret-free results/statuses.

### Persistence and Migration

**No schema change.** Server configs persist in `UserDefaults` under `MCPServerConfigs` with sensitive env values replaced by `keychain://mcp-env/<configID>/<key>` markers. Per-chat agent selection persists in `UserDefaults` keyed by chat id. Completed tool calls encode to `MessageEntity.toolCallsJson`. Existing chats without tool calls render unchanged.

### Security and Privacy

- Sensitive env keys (token/key/secret/password/passwd/auth/bearer/credential substring match) are stored via `TokenManager` (Keychain, `afterFirstUnlock`) and never persisted in plaintext or logged.
- Deleting a server calls `cleanupEnvironmentSecrets` to remove its Keychain entries.
- Stdio subprocesses run through `/usr/bin/env` with augmented PATH; stderr is surfaced only as a length in DEBUG.
- SSE endpoints are remote disclosure and user-controlled; tool arguments/results are excluded from release logs (only counts/lengths in DEBUG).

## Project Structure

### Feature Documentation

```text
specs/011-mcp-tool-integration/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── mcp-tool-contract.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Paths

```text
Warden/
├── Core/MCP/
│   ├── MCPManager.swift
│   └── MCPServerConfig.swift
├── Models/
│   ├── SearchModels.swift
│   └── Models.swift
├── UI/
│   ├── Preferences/MCP/
│   │   ├── MCPSettingsView.swift
│   │   └── AddMCPAgentSheet.swift
│   └── Chat/
│       ├── MCPAgentSelector.swift
│       └── Components/ToolCallProgressView.swift
└── Utilities/
    ├── MessageManager.swift
    └── TokenManager.swift

WardenTests/
└── MCP/
    └── MCPToolIntegrationTests.swift
```

**Structure Decision**: Keep `MCPManager` the single coordinator; add deterministic tests under `WardenTests/MCP/`. Do not introduce a parallel MCP subsystem, and do not move tool execution out of `MessageManager`.

## Test and Verification Plan

1. **Regression first**: Add tests asserting sensitive env values are replaced by keychain markers on save and resolved on connect, and that `toolOwner` routing throws a readable error for unknown tools.
2. **Focused unit tests**: Run `WardenTests/MCPToolIntegrationTests` (and existing suites) with `xcodebuild ... -only-testing`.
3. **UI workflow**: Manual smoke check of add/test/connect and in-chat selection is optional; core logic is covered by deterministic tests without a live server.
4. **Build**: Run the repository macOS build command after focused tests.
5. **Full tests**: Run the repository macOS test command before completion; report only real environment blockers (e.g. pre-existing `AppShellUITests`).
6. **Privacy review**: Verify Keychain marker persistence, secret cleanup on delete, and absence of secrets/arguments/results in release logs.

## Delivery Phases

### Phase 0 — Research and Risk Reduction

Document existing MCP SDK transport usage, secret-marker scheme, tool-owner routing, and test seams that avoid launching real subprocesses. Completed in `research.md`.

### Phase 1 — Models, Contracts, and Persistence

Document `MCPServerConfig`, `WardenToolCallStatus`, secret-marker persistence, and the tool execution contract; confirm no Core Data migration. Completed in `data-model.md` and `contracts/mcp-tool-contract.md`.

### Phase 2 — Services and Provider Integration

Add focused helpers/tests for sensitive-key detection, secret marking/resolution, tool-owner routing, and argument/result conversion; verify cancellation and error paths in the execution loop without a live server.

### Phase 3 — Native macOS UI

No new UI required. Preserve add/edit/test/connect flows, per-chat selection, availability disabling, and expandable tool-call rendering; make only defensive/clarity edits if needed.

### Phase 4 — Verification and Documentation

Run focused and full XCTest/build verification, inspect privacy-sensitive paths, update task state and quickstart, and record actual blockers if any.

## Complexity Tracking

No constitution gates are intentionally violated.
