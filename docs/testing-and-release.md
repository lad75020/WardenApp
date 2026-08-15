# Testing and release

This guide records the commands and checks confirmed for the current WardenApp project. It distinguishes verified repository facts from release steps that still require local signing and distribution decisions.

## Xcode targets and schemes

`xcodebuild -project Warden.xcodeproj -list` resolves the package graph and reports these targets:

- `Warden`
- `WardenTests`
- `WardenUITests`
- `MLXZImageSwiftCLI`

The project reports a `Warden` scheme and additional package/library schemes. Use the `Warden` scheme for the application and its test plan unless a focused package target is under test.

## Build checks

Build the application for macOS:

```bash
xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build
```

Open and run in Xcode:

```bash
open Warden.xcodeproj
```

The build resolves local packages and remote Swift packages. A first run can require network access for uncached package versions.

## Test checks

Run all tests for the macOS destination:

```bash
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'
```

Run the shared test plan:

```bash
xcodebuild -project Warden.xcodeproj -scheme Warden -testPlan Warden test
```

Run one test with Xcode's focused-test syntax:

```bash
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/TestClassName/testMethodName
```

The exact test class and method must be replaced with a real test identifier discovered from the current test target. Do not put secrets or private prompts in a test name or fixture.

## Test responsibilities

### Unit tests

Unit coverage should protect:

- Provider request construction and response parsing.
- HTTP error classification.
- Sensitive transport validation.
- Stream event boundaries and final undelimited events.
- Cancellation and stale request identity.
- Search citation validation and source association.
- MCP marker generation and sensitive-key classification.
- Attachment parsing and save failure behavior.
- Persistence migration and deduplication.
- Model favorites and metadata fallback.

### UI tests

UI coverage should protect:

- App shell launch and onboarding.
- Preferences presentation without duplicate windows.
- Main window commands and appearance.
- Chat creation, send, stop, retry, and navigation.
- Provider configuration without a paid credential.
- Persistence recovery and unavailable-chat repair.
- Attachment and export cancellation paths.
- MCP configuration/status controls.
- Quick Chat and hotkey failure feedback.

### No paid credentials

Tests must not require a real hosted-provider credential. Prefer in-memory Core Data, fake handlers, deterministic streams, local fixtures, or a local runtime explicitly controlled by the test.

## Persistence recovery fixtures

The application source includes special modes used by UI tests. Current names include:

- `-AppShellUITestMode`.
- `-PersistenceRecoveryUITestMode`.
- `-PersistenceRecoveryPersistentFixtureMode`.
- `WARDEN_PERSISTENCE_RECOVERY_FIXTURE`.
- `WARDEN_PERSISTENCE_RECOVERY_HAS_CANDIDATE`.
- `WARDEN_PERSISTENCE_RECOVERY_STORE_ID`.
- `WARDEN_PERSISTENCE_RECOVERY_RESET_STORE`.

Use the existing support classes in `WardenUITests/Persistence/` as the source of truth for how these values combine. A test fixture must isolate its SQLite store and must not modify a user's real chat database.

## Documentation checks

Before a documentation-only change is committed:

1. Check every local Markdown link.
2. Check that fenced code blocks are balanced.
3. Check that command examples reference existing targets and paths.
4. Search for credential-like values, authorization headers, and private data.
5. Run:

   ```bash
   git diff --check
   ```

6. Review `git status --short` and the complete diff.

## Release build preparation

A release build requires local decisions that are not fully automated by this repository:

- Select the correct Apple Developer team and signing identity.
- Confirm bundle identifiers and entitlements.
- Resolve and build all required Swift packages.
- Run the `Warden` unit/UI test suite.
- Exercise first launch, provider setup, local fallback, and data migration.
- Verify that no credentials or private fixtures are packaged.
- Validate the app's behavior with the intended macOS deployment target.

The repository does not contain a verified CI/CD workflow or a complete notarization/publishing script. Do not claim a release is distributable until signing, archive, notarization, and install testing have succeeded in the target environment.

## Post-change verification

After a source or Core Data change:

1. Run the focused tests.
2. Run the complete `Warden` test suite.
3. Run the application build.
4. Inspect the final diff for secrets and stale docs.
5. Refresh the codebase-memory index.
6. Confirm the indexed project is ready and the documentation files are visible to the repository.
