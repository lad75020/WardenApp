# Implementation Plan: App Shell and Onboarding

**Branch**: `feature/time-machine-app-shell-and-onboarding` | **Date**: 2026-08-11 | **Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from `/specs/001-app-shell-onboarding/spec.md`

## Summary

Harden the existing native macOS shell rather than replace it. Preserve the current `WindowGroup`, welcome screen, reusable Settings window, local preferences, and Core Data fallback while closing observable gaps in onboarding navigation, last-chat restoration, import-error feedback, appearance consistency, accessibility, and deterministic regression coverage. No provider, persistence-schema, package, or network contract changes are required.

## Technical Context

**Language/Version**: Swift 5.9  
**Primary Frameworks**: SwiftUI, AppKit where required, Foundation  
**Persistence**: Existing Core Data store through `ChatStore`; local UI state in app preferences; Keychain remains the sole secret store  
**Testing**: XCTest (`WardenTests/`) and XCUITest (`WardenUITests/`)  
**Target Platform**: Native macOS 26.0  
**Project Type**: Xcode macOS application with unit/UI test targets and an auxiliary CLI target  
**Build Command**: `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`  
**Test Command**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'`  
**Performance Goals**: Welcome-state transitions and Settings activation remain perceptibly immediate; no blocking I/O is added to launch or SwiftUI rendering  
**Constraints**: Privacy-first, no telemetry, no new secret storage, no Core Data schema change, native keyboard/accessibility behavior, deterministic tests without paid credentials  
**Scale/Scope**: Main app entry, content/welcome/onboarding views, general Settings, Settings window manager, focused unit/UI tests; all provider and message-streaming implementations remain unchanged

## Constitution Check

*GATE: Passed before research and re-checked after design.*

- [x] Native macOS and privacy-first behavior is preserved.
- [x] Each changed file belongs to its documented module.
- [x] Provider work conforms to `APIProtocol` and uses existing factory/base abstractions. No provider work is planned.
- [x] Secrets remain in Keychain and are excluded from Core Data, fixtures, and logs.
- [x] Core Data changes include migration and existing-user compatibility analysis. No schema change is planned.
- [x] Async/streaming work has cancellation, failure, and actor-safety behavior. No streaming work is planned; import feedback remains main-actor safe.
- [x] Focused XCTest/XCUITest coverage is identified and does not require paid credentials.
- [x] No new dependency or abstraction is added without a concrete justification.

Post-design re-check: all gates remain satisfied. The UI-state seams are small internal types under the owning UI module, no new package is introduced, and the contract expressly preserves local-only behavior.

## Architecture Impact

### Affected Modules

| Module | Path | Planned responsibility/change |
|---|---|---|
| App entry/config | `Warden/WardenApp.swift` | Preserve launch, menu, persistence fallback, and window behavior; add only stable accessibility/test-facing shell behavior if required by UI verification. |
| UI / view models | `Warden/UI/ContentView.swift`, `Warden/UI/WelcomeScreen/`, `Warden/UI/Preferences/TabGeneralSettingsView.swift` | Correct onboarding actions, persist valid last-chat selection, expose deterministic welcome/onboarding states, improve error feedback and accessibility. |
| Shared models | `Warden/Models/` | No change. |
| Services/managers | `Warden/Utilities/SettingsWindowManager.swift` | Preserve the single reusable Settings window and appearance synchronization; make only focused lifecycle corrections discovered by regression tests. |
| Provider handlers | `Warden/Utilities/APIHandlers/` | No change. |
| Persistence | `Warden/Store/` | No schema or production persistence change. Existing `ChatStore` import/export APIs are reused. |
| MCP | `Warden/Core/MCP/` | No change. |
| Unit tests | `WardenTests/AppShell/` | Add deterministic tests for welcome-state resolution and onboarding flow/state contracts. |
| UI tests | `WardenUITests/AppShellUITests.swift` | Cover launch/welcome, onboarding navigation, and Settings single-window workflow where stable under the local test container. |
| CLI/local packages | `MLXZImageSwiftCLI/`, `Packages/` | No change. |

### Dependency Flow

`WardenApp` owns the application scene, shared persistence controller, and shared `ChatStore`. `ContentView` derives shell state from fetched local entities and routes to `WelcomeScreen` or feature content. `WelcomeScreen` derives a small presentation state and invokes injected actions; `InteractiveOnboardingView` owns only ephemeral step navigation plus the persisted completion flag. Settings presentation stays behind `SettingsWindowManager`, and general preferences continue to use local preference storage and existing `ChatStore` backup APIs. No view gains direct provider transport or new persistence ownership.

### Provider/API Contract *(if applicable)*

Not applicable. The implementation must not call providers, validate credentials, or change `APIProtocol`, `APIServiceFactory`, handlers, request transformation, streaming, cancellation, timeout, or provider error mapping.

### Persistence and Migration *(if applicable)*

No Core Data schema change. Existing chats, projects, providers, and personas remain compatible. Local preference keys remain stable: `hasCompletedOnboarding`, `preferredColorScheme`, `chatFontSize`, `showSidebarAIIcons`, `lastOpenedChatId`, and existing window-frame autosave names. Last-chat persistence records only a valid selected chat identifier. Existing database-load failure behavior continues to warn the user and fall back to in-memory storage for the current session.

### Security and Privacy

No new data leaves the Mac. The shell and onboarding never read or log API keys. Backup import/export remains explicitly user initiated and local; malformed input produces a user-visible error without logging backup content. Diagnostics continue through `WardenLog`, never `print`. UI tests use no credentials, private prompts, or production user data.

## Project Structure

### Feature Documentation

```text
specs/001-app-shell-onboarding/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── app-shell-ui-contract.md
└── tasks.md
```

### Source Paths

```text
Warden/
├── WardenApp.swift
├── UI/
│   ├── ContentView.swift
│   ├── WelcomeScreen/
│   │   ├── WelcomeScreen.swift
│   │   └── InteractiveOnboardingView.swift
│   └── Preferences/TabGeneralSettingsView.swift
└── Utilities/SettingsWindowManager.swift

WardenTests/AppShell/
WardenUITests/AppShellUITests.swift
```

**Structure Decision**: Extend the current shell types in place. Introduce at most a focused internal welcome/onboarding state helper under `Warden/UI/WelcomeScreen/` when needed to make state transitions testable without UI-introspection dependencies. Add tests only to the existing test targets. Do not add a package, global coordinator, new store, or duplicate Settings implementation.

## Test and Verification Plan

1. **Regression first**: Add failing tests for the provider-step Settings action, valid last-chat selection persistence, welcome-state resolution, and malformed import feedback/testable outcome before production edits.
2. **Focused unit tests**: Add `WardenTests/AppShell/WelcomeExperienceStateTests.swift` and `WardenTests/AppShell/OnboardingFlowTests.swift`; run `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/WelcomeExperienceStateTests -only-testing:WardenTests/OnboardingFlowTests`.
3. **UI workflow**: Add or update `WardenUITests/AppShellUITests.swift` for clean launch, onboarding Back/Next/Open Settings/Start behavior, Settings activation, and stable accessibility identifiers. If macOS automation permissions block execution, record the exact blocker and perform a focused manual workflow without claiming UI-suite success.
4. **Build**: Run `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`.
5. **Full tests**: Run `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'` before considering the feature complete; document only real environment blockers.
6. **Privacy review**: Inspect diffs for credential access, backup-content logging, telemetry, direct network calls, and accidental generated/user-state files.

## Delivery Phases

### Phase 0 — Research and Risk Reduction

Confirm current shell behavior from source, identify unreachable or inconsistent onboarding actions, map stable local preference keys, and select test seams that do not require a new dependency or live provider setup.

### Phase 1 — Models, Contracts, and Persistence

Define the internal welcome/onboarding state contract and tests. Preserve all preference keys and Core Data schema. Add last-chat selection persistence using the existing identifier preference only after a valid chat is selected.

### Phase 2 — Services and Provider Integration

Keep provider code unchanged. Apply any test-proven Settings-window lifecycle correction within `SettingsWindowManager`; preserve one reusable window and main-actor ownership.

### Phase 3 — Native macOS UI

Correct onboarding control routing, prevent duplicate completion, add meaningful accessibility identifiers/labels, retain optional guide access, and show a non-destructive user-facing error for malformed chat imports. Keep System/Light/Dark appearance synchronized without disruptive window recreation.

### Phase 4 — Verification and Documentation

Run focused tests, UI workflow, build, and full tests; inspect privacy-sensitive paths and repository status. Update feature artifacts only with actual results and blockers.

## Complexity Tracking

No Constitution Check violation or exceptional complexity is planned.
