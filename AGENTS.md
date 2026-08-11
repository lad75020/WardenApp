# Warden Development Guide

**Warden** is a native macOS AI chat client (SwiftUI, Core Data) supporting 10+ AI providers.

## Build & Test
- **Build**: `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`
- **Test All**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'`
- **Single Test**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/TestClassName/testMethodName`
- **Format**: Preserve the established 4-space indentation and approximately 120-character lines. No formatter configuration is currently versioned, so do not claim an automated format gate exists.

## Architecture
- **Structure**: `Warden/UI/` (Views) → `Models/` (Data) → `Utilities/` (Helpers) → `Store/` (Core Data).
- **Pattern**: MVVM. `ChatStore.swift` is single source of truth. `APIServiceFactory` creates handlers.
- **AI Handlers**: `Utilities/APIHandlers/` implements `APIProtocol` for each provider.
- **Data**: Local-only Core Data. Schema in `warenDataModel.xcdatamodeld`. Privacy first—NO telemetry.

## Module Boundaries
- `Warden/UI/`: SwiftUI presentation and view models; do not place provider transport or direct Core Data ownership here.
- `Warden/Models/`: shared app data types; models must not depend on concrete views.
- `Warden/Utilities/`: services, managers, parsers, streaming, attachments, logging, and integrations.
- `Warden/Utilities/APIHandlers/`: provider implementations conforming to `APIProtocol`; use `APIServiceFactory` and shared base behavior.
- `Warden/Store/`: `ChatStore` and Core Data persistence/migration behavior.
- `Warden/Core/MCP/`: MCP configuration and runtime management.
- `Warden/Configuration/`: app-wide constants and static configuration.
- `WardenTests/` and `WardenUITests/`: XCTest and XCUITest ownership respectively; tests must not require real paid API credentials.
- `MLXZImageSwiftCLI/`: auxiliary command-line target. `Packages/`: local package boundaries; keep app-specific UI and persistence out of package APIs.

Changes crossing module boundaries must name the owning module in the implementation plan. Coordinate edits to shared hotspots such as `ChatStore.swift`, `APIProtocol.swift`, `APIServiceFactory.swift`, the Core Data model, and Xcode project settings rather than assigning them to parallel agents.

## Code Style
- **Naming**: `*View`, `*ViewModel`, `*Handler`. PascalCase types, camelCase properties.
- **State**: `@StateObject` (owner), `@ObservedObject` (passed in), `@EnvironmentObject` (global).
- **Concurrency**: `async`/`await`. Heavy work on background queues.
- **Security**: NEVER log API keys. Use Keychain for secrets. NO analytics/tracking.

<!-- SPECKIT START -->
## Active Spec Kit Plan
- `specs/001-app-shell-onboarding/plan.md`
<!-- SPECKIT END -->
