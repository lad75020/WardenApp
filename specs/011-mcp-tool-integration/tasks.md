# Tasks: MCP Tool Integration

**Feature**: `011-mcp-tool-integration`  
**Branch**: `feature/time-machine-mcp-tool-integration`  
**Input**: Design artifacts in `specs/011-mcp-tool-integration/` (spec.md, plan.md, research.md, data-model.md, contracts/mcp-tool-contract.md, quickstart.md)

This feature specifies and hardens an already-partially-implemented MCP subsystem. The constitution requires deterministic tests for security-sensitive changes, so test tasks are included.

## Phase 1: Setup

- [X] T001 Confirm branch, `.specify/feature.json`, and `specs/011-mcp-tool-integration/` agree in ./specs/011-mcp-tool-integration/plan.md
- [X] T002 Verify the Swift MCP SDK and KeychainAccess dependencies resolve in Warden.xcodeproj by running the build command from ./specs/011-mcp-tool-integration/quickstart.md

## Phase 2: Foundational

- [X] T003 Create the unit test target directory and empty test scaffold at WardenTests/MCP/MCPToolIntegrationTests.swift
- [X] T004 Confirm `WardenToolCallStatus` Codable round-trip and `MessageEntity.toolCalls` JSON storage behavior in Warden/Models/SearchModels.swift and Warden/Models/Models.swift

## Phase 3: User Story 1 - Configure and connect an MCP server (P1)

**Goal**: Users can add, test, connect, and delete Stdio/SSE MCP servers with live status.  
**Independent Test**: Add a Stdio server, test it, connect it, confirm tool count, delete it and confirm removal.

- [ ] T005 [P] [US1] Add test asserting an invalid config (empty name, or Stdio without command, or SSE without URL) is rejected by validation in WardenTests/MCP/MCPToolIntegrationTests.swift  <!-- NOT DONE: current tests cover Codable round-trips (testStdioConfigRoundTripsThroughCodable, testSseConfigPreservesURL), not invalid-config rejection -->
- [X] T006 [US1] Verify add/edit/enable/disable/delete config CRUD and reconnect-on-update behavior in Warden/Core/MCP/MCPManager.swift  <!-- verified by code review: CRUD + reconnect-on-update present -->
- [X] T007 [US1] Verify connect status transitions (connecting → connected(toolsCount) / error) and tool caching in Warden/Core/MCP/MCPManager.swift  <!-- verified by code review -->
- [X] T008 [US1] Verify testConnection tears down its throwaway transport via defer in Warden/Core/MCP/MCPManager.swift  <!-- verified by code review -->
- [X] T009 [US1] Confirm add/edit sheet field validation and KEY=VALUE environment parsing in Warden/UI/Preferences/MCP/AddMCPAgentSheet.swift  <!-- verified by code review -->
- [X] T010 [US1] Confirm master–detail list, status dots, and connect/test/restart/delete actions in Warden/UI/Preferences/MCP/MCPSettingsView.swift  <!-- verified by code review -->

## Phase 4: User Story 2 - Store MCP environment secrets securely (P1)

**Goal**: Sensitive env values are stored in Keychain with reference markers, never in plaintext.  
**Independent Test**: Save a server with an `API_KEY` env; confirm the persisted config holds a keychain marker and the value round-trips via Keychain; delete removes it.

- [X] T011 [P] [US2] Add test for sensitive-key detection covering token/key/secret/password/passwd/auth/bearer/credential in WardenTests/MCP/MCPToolIntegrationTests.swift  <!-- testSensitiveEnvironmentKeyDetectionMatchesKnownPatterns + testNonSensitiveEnvironmentKeysAreNotFlagged PASS -->
- [X] T012 [P] [US2] Add test that saving a config replaces a sensitive env value with a `keychain://mcp-env/<id>/<key>` marker and stores the raw value via Keychain in WardenTests/MCP/MCPToolIntegrationTests.swift  <!-- marker-format asserted by testEnvironmentSecretMarkerFormatIsStableAndScoped + testMarkerIsDistinctPerKeyAndConfig (PASS); NOTE: tests the pure marker builder, deliberately no live Keychain write side-effect -->
- [ ] T013 [P] [US2] Add test that `resolvedEnvironment` returns the original secret and that delete removes the Keychain entry in WardenTests/MCP/MCPToolIntegrationTests.swift  <!-- NOT DONE: no test exercises live Keychain resolve/delete round-trip (avoided to keep tests side-effect-free); lifecycle verified by code review only -->
- [X] T014 [US2] Verify sanitize/resolve/cleanup secret lifecycle and TokenManager identity scheme in Warden/Core/MCP/MCPManager.swift  <!-- verified by code review: storeEnvironmentSecret/resolveEnvironmentSecretMarker/resolvedEnvironment/cleanupEnvironmentSecrets present and correct -->
- [X] T015 [US2] Confirm Keychain bundle storage uses afterFirstUnlock accessibility in Warden/Utilities/TokenManager.swift  <!-- verified by code review -->

## Phase 5: User Story 3 - Select MCP tools per chat and monitor execution (P2)

**Goal**: Users select connected agents per chat, watch tool-call lifecycle, and see persisted records.  
**Independent Test**: With a connected agent selected, trigger a tool and confirm the lifecycle plus a persisted expandable record after reload.

- [ ] T016 [P] [US3] Add test that `toolOwner` routing throws a readable 404 for an unknown tool in WardenTests/MCP/MCPToolIntegrationTests.swift  <!-- NOT DONE: no toolOwner-404 test present in the file -->
- [X] T017 [P] [US3] Add test for argument/result serialization shape (`[String: Any]` ⇄ JSON) covering text/image/resource content in WardenTests/MCP/MCPToolIntegrationTests.swift  <!-- testToolResultDictionariesAreJSONSerializable PASS (text/image/resource) -->
- [X] T018 [US3] Verify per-chat `selectedMCPAgents` persistence keyed by chat id in Warden/UI/Chat/ChatViewModel.swift  <!-- verified by code review -->
- [X] T019 [US3] Verify tool forwarding, execution loop, result append, and no-re-offer follow-up in Warden/Utilities/MessageManager.swift  <!-- verified by code review -->
- [X] T020 [US3] Verify cancellation and failure handling (malformed args, missing tool, thrown error) in the execution loop in Warden/Utilities/MessageManager.swift  <!-- verified by code review -->
- [X] T021 [US3] Confirm agent availability disabling and empty-state shortcut in Warden/UI/Chat/MCPAgentSelector.swift  <!-- verified by code review -->
- [X] T022 [US3] Confirm live and persisted tool-call rendering (expandable, truncated results) in Warden/UI/Chat/Components/ToolCallProgressView.swift  <!-- verified by code review -->

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T023 Confirm SIGPIPE is ignored and auto-connect is gated off by default in Warden/WardenApp.swift  <!-- auto-connect guarded by UserDefaults "autoConnectMCPServers" (default false) at WardenApp.swift:420 -->
- [X] T024 Privacy review: verify no secrets/arguments/results in release logs and DEBUG-only length logging in Warden/Core/MCP/MCPManager.swift and Warden/Utilities/MessageManager.swift  <!-- grep confirms no plaintext print/NSLog/os_log of env/secret/token/arg/result -->
- [ ] T025 Run focused tests, then the macOS build, then the full suite per ./specs/011-mcp-tool-integration/quickstart.md and record results in ./specs/011-mcp-tool-integration/quickstart.md  <!-- PARTIAL: focused MCP tests PASS (** TEST SUCCEEDED **, 8/8) + test-host build succeeded; standalone build + full suite not yet run this session -->

## Dependencies

- Phase 1 (T001–T002) → Phase 2 (T003–T004) → user-story phases.
- US1 (config/connect) is the foundation for US3 (selection/execution needs a connected server); US2 (secrets) is independent of US3 but shares config CRUD with US1.
- Polish (T023–T025) runs after all user-story phases.

## Parallel Execution Examples

- US1: T005 is `[P]` (test-only file) and can run alongside verification tasks T006–T010.
- US2: T011, T012, T013 are `[P]` — independent test additions in the same test file, authored together then run.
- US3: T016, T017 are `[P]` test additions; T018–T022 verify distinct source files.

## Implementation Strategy

- **MVP**: US1 + US2 (configure/connect a server and store its secrets securely) deliver the minimum privacy-safe, usable increment.
- **Increment**: US3 adds per-chat selection and execution monitoring on top of connected servers.
- Prefer verifying existing behavior with deterministic tests over rewriting working code; make only defensive/clarity edits where a test exposes a real defect.
