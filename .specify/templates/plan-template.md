# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]  
**Input**: Feature specification from `/specs/[###-feature-name]/spec.md`

## Summary

[Summarize the user requirement and the smallest architecture-aligned implementation approach.]

## Technical Context

**Language/Version**: Swift 5.9  
**Primary Frameworks**: SwiftUI, AppKit where required, Foundation  
**Persistence**: Core Data through `Warden/Store/ChatStore.swift`; Keychain for secrets  
**Testing**: XCTest (`WardenTests/`) and XCUITest (`WardenUITests/`)  
**Target Platform**: Native macOS 26.0  
**Project Type**: Xcode macOS application with unit/UI test targets and an auxiliary CLI target  
**Build Command**: `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`  
**Test Command**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'`  
**Performance Goals**: [UI responsiveness, streaming latency, memory, launch, or model-loading goal, or N/A]  
**Constraints**: Privacy-first, no telemetry, Keychain secrets, cancellable streaming, actor-safe UI state  
**Scale/Scope**: [Affected views, handlers, models, migrations, tests, and supported providers]

## Constitution Check

*GATE: Must pass before research and be re-checked after design.*

- [ ] Native macOS and privacy-first behavior is preserved.
- [ ] Each changed file belongs to its documented module.
- [ ] Provider work conforms to `APIProtocol` and uses existing factory/base abstractions.
- [ ] Secrets remain in Keychain and are excluded from Core Data, fixtures, and logs.
- [ ] Core Data changes include migration and existing-user compatibility analysis.
- [ ] Async/streaming work has cancellation, failure, and actor-safety behavior.
- [ ] Focused XCTest/XCUITest coverage is identified and does not require paid credentials.
- [ ] No new dependency or abstraction is added without a concrete justification.

Unmet gates MUST be resolved or listed under Complexity Tracking before implementation.

## Architecture Impact

### Affected Modules

| Module | Path | Planned responsibility/change |
|---|---|---|
| App entry/config | `Warden/WardenApp.swift`, `Warden/Configuration/` | [Change or N/A] |
| UI / view models | `Warden/UI/` | [Change or N/A] |
| Shared models | `Warden/Models/` | [Change or N/A] |
| Services/managers | `Warden/Utilities/` | [Change or N/A] |
| Provider handlers | `Warden/Utilities/APIHandlers/` | [Change or N/A] |
| Persistence | `Warden/Store/` | [Change or N/A] |
| MCP | `Warden/Core/MCP/` | [Change or N/A] |
| Unit tests | `WardenTests/` | [Coverage] |
| UI tests | `WardenUITests/` | [Coverage or N/A] |
| CLI/local packages | `MLXZImageSwiftCLI/`, `Packages/` | [Change or N/A] |

### Dependency Flow

[Describe concrete dependencies. Preserve the flow from SwiftUI presentation to models/view models and focused services, with persistence coordinated by the store. Provider handlers must remain presentation-independent.]

### Provider/API Contract *(if applicable)*

[Document `APIProtocol` methods, factory selection, request transformation, stream parsing, cancellation, timeout, and error mapping.]

### Persistence and Migration *(if applicable)*

[Document Core Data entities/versions, migration behavior, rollback or fallback behavior, and compatibility with existing chats. State `No schema change` when true.]

### Security and Privacy

[Document Keychain use, data leaving the device, logging/redaction, file access, and threat-sensitive failure behavior.]

## Project Structure

### Feature Documentation

```text
specs/[###-feature]/
├── spec.md
├── plan.md
├── research.md          # when technical uncertainty exists
├── data-model.md        # when persisted/shared entities change
├── quickstart.md        # verification workflow
├── contracts/           # provider/MCP/request contracts when applicable
└── tasks.md
```

### Source Paths

```text
Warden/
├── Configuration/
├── Core/MCP/
├── Models/
├── Store/
├── UI/
└── Utilities/
    └── APIHandlers/

WardenTests/
└── Utilities/           # existing parser-focused unit tests; add feature paths as appropriate

WardenUITests/
MLXZImageSwiftCLI/
```

**Structure Decision**: [List the exact files to create or modify and explain why each belongs there.]

## Test and Verification Plan

1. **Regression first**: [Test that fails before the fix/feature implementation.]
2. **Focused unit tests**: [Exact XCTest target/classes and command with `-only-testing` where useful.]
3. **UI workflow**: [XCUITest or explicit manual macOS verification.]
4. **Build**: Run the repository build command.
5. **Full tests**: Run the repository test command before merge; document only real environment blockers.
6. **Privacy review**: Verify logs, persisted data, Keychain lifecycle, and network disclosure.

## Delivery Phases

### Phase 0 — Research and Risk Reduction

[Resolve framework/API uncertainty, package compatibility, migration risk, and test seams.]

### Phase 1 — Models, Contracts, and Persistence

[Implement shared types, protocol changes, request contracts, or Core Data migration before dependent UI/services.]

### Phase 2 — Services and Provider Integration

[Implement utilities, managers, streaming, MCP, or provider behavior behind existing abstractions.]

### Phase 3 — Native macOS UI

[Implement SwiftUI/AppKit presentation, state ownership, accessibility, keyboard/focus behavior, and all UI states.]

### Phase 4 — Verification and Documentation

[Run focused/full tests and build, inspect privacy-sensitive paths, and update user/developer documentation.]

## Complexity Tracking

> Complete only when a Constitution Check gate is intentionally violated.

| Violation | Why Needed | Simpler Existing Pattern Rejected Because |
|---|---|---|
| [Violation] | [Concrete necessity] | [Evidence] |
