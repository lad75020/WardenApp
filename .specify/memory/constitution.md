# WardenApp Constitution

## Project Identity

WardenApp is a privacy-first native macOS AI chat client written in Swift 5.9 with SwiftUI, AppKit integrations, Core Data persistence, and provider-specific HTTP/streaming clients. The app follows an MVVM-oriented structure with `ChatStore` as the primary persisted chat state and protocol-based AI provider handlers.

## Core Principles

### I. Native macOS and Privacy First

Features MUST remain native to macOS and use SwiftUI/AppKit rather than a web wrapper. User conversations and configuration remain local unless the user explicitly invokes a selected remote provider or search service. Analytics, telemetry, or tracking MUST NOT be added. Secrets MUST be stored in Keychain and MUST NOT be persisted in Core Data, source files, fixtures, or logs.

### II. Respect Module Boundaries

Production app code belongs under `Warden/`:

- `UI/`: SwiftUI views, view models, UI components, modifiers, preferences, onboarding, and chat presentation.
- `Models/`: value types and data representations shared by UI and services.
- `Utilities/`: services, managers, parsing, streaming, attachment handling, logging, and AI integrations.
- `Utilities/APIHandlers/`: provider implementations conforming to `APIProtocol`; shared behavior belongs in `BaseAPIHandler` or a focused shared utility.
- `Store/`: Core Data ownership and `ChatStore` persistence behavior.
- `Core/MCP/`: MCP configuration and runtime management.
- `Configuration/`: app-wide constants and static configuration.

`WardenTests/` owns unit tests and `WardenUITests/` owns end-to-end UI tests. `MLXZImageSwiftCLI/` is a separate tool target. Local packages referenced from `Packages/` MUST preserve their package APIs and tests; app-specific UI or persistence logic MUST NOT be moved into those packages.

Views MAY depend on models, view models, stores, and focused services. Provider handlers MUST NOT own SwiftUI presentation. Models MUST NOT depend on concrete views. Core Data access MUST remain coordinated through the store/persistence layer rather than being scattered through UI code.

### III. Protocol-Based Provider Integration

Each AI provider implementation MUST conform to `APIProtocol` and be constructed through `APIServiceFactory` or the existing configuration path. OpenAI-compatible providers SHOULD reuse the established compatible handler where behavior is equivalent. Streaming work MUST remain cancellable and parser changes MUST preserve incremental/SSE behavior. Provider errors MUST be surfaced without exposing API keys, authorization headers, private prompts, or sensitive response data in logs.

### IV. Testable Changes

Behavior changes MUST include focused XCTest coverage in `WardenTests/` when the behavior is testable below the UI. User-critical workflows or regressions that require interaction MUST include or update XCUITest coverage in `WardenUITests/`. Parser, streaming, persistence migration, provider request transformation, attachment resolution, and security-sensitive changes require regression tests. Tests MUST be deterministic and MUST NOT require real paid API credentials.

Before implementation is considered complete, the affected tests MUST pass. The repository-wide verification commands are:

```bash
xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'
```

### V. Safe Persistence, Concurrency, and Observability

Core Data model changes MUST include a migration/compatibility assessment and MUST preserve existing user chats whenever feasible. File and attachment access MUST validate paths and avoid blocking caller or main-actor work. New asynchronous behavior MUST use the existing `async`/`await`, cancellation, and background-work patterns; UI state changes remain actor-safe.

Runtime diagnostics MUST use `WardenLog` or the existing signpost facilities instead of ad-hoc `print` statements. Logs MUST be useful for debugging while excluding credentials and private user content.

## Naming and Code Conventions

- Swift types and files use PascalCase; properties, methods, and local variables use lower camel case.
- UI types use established suffixes such as `View` and `ViewModel`.
- Integrations use established suffixes such as `Handler`, `Manager`, and `Service`.
- SwiftUI state ownership follows current usage: `@StateObject` for owned observable state, `@ObservedObject` for injected state, and `@EnvironmentObject` for shared environment state.
- New feature branches use Spec Kit's `[###-feature-name]` form. Existing history does not establish a separate branch convention.
- No formatter or linter configuration is currently present in the repository; do not claim a formatting gate exists until one is added and versioned.

## Quality Gates

Every feature plan and review MUST confirm:

1. Module boundaries and existing provider/store abstractions are preserved.
2. Security and privacy impact is documented, including Keychain and logging behavior.
3. Core Data schema impact and migration needs are addressed.
4. Focused tests pass, followed by the macOS build; repository-wide tests run before merge unless a documented environment blocker prevents them.
5. No secret, user data, build output, DerivedData, or local package checkout is accidentally committed.
6. Any complexity or new abstraction is justified against extending an existing focused type.

No CI workflow is currently detected, so local `xcodebuild` verification is the authoritative gate until CI is introduced.

## Governance

This constitution governs Spec Kit artifacts and implementation work for WardenApp. `AGENTS.md` and `CLAUDE.md` provide operational guidance and MUST remain consistent with these rules. Amendments require an explicit rationale, review of affected templates, and a version change: MAJOR for incompatible governance changes, MINOR for new principles or materially expanded rules, and PATCH for clarifications.

**Version**: 1.0.0 | **Ratified**: 2026-08-11 | **Last Amended**: 2026-08-11
