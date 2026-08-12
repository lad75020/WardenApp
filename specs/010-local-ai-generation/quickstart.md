# Quickstart: Local AI and Generation Verification

## Focused deterministic checks

1. Build test fixtures for a valid and missing Core ML local directory.
2. Verify factory selection for MLX, Core ML, Hugging Face, Ollama, and LM Studio configurations.
3. Verify MLX text/vision classification and nested asset load-directory preparation.
4. Verify local metadata is identified as self-hosted/free and refresh failures preserve current selections.
5. Verify endpoint classification accepts loopback/private-LAN forms and does not expand to public endpoint behavior.
6. Verify cancellation/failure behavior does not append duplicate content or expose sensitive request data.

## Commands

```bash
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/LocalProviderTests
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/MLXHandlerModelTypeTests
xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'
git diff --check
```

Run no live model download or paid-provider request as part of automated verification.

## Verification record — 2026-08-12

All commands below used the macOS destination and ad-hoc signing where needed:
`CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-"`.

| Check | Outcome |
| --- | --- |
| XcodeMCP app build | **Passed** — final `BuildProject` completed successfully in 4.964 seconds after the Local AI changes. |
| CLI macOS app build | **Passed** earlier in this feature pass with `** BUILD SUCCEEDED **`. |
| `LocalProviderTests` focused selection | **Blocked before test execution** — test target compilation fails in pre-existing `WardenTests/Persistence/ChatHistoryRecoveryTests.swift`, including `SortComparator` inference and `ChatEntity`/`NSFetchRequestResult.objectID` type errors. This focused command exits 65; no LocalProvider test ran. |
| `MLXHandlerModelTypeTests` focused selection | **Blocked before test execution** by the same unrelated `ChatHistoryRecoveryTests.swift` compilation errors; exits 65. |
| Full `Warden` test suite | **Blocked before test execution** by the same unrelated `ChatHistoryRecoveryTests.swift` compilation errors; exits 65. |
| `git diff --check` | Pending final inspection after this record update. |

The deterministic tests use no live model server, model download, paid credential, or external network request. The app target builds; the current test-target compilation blocker must be resolved before the focused and full test commands can provide passing execution evidence.

## Verification record — 2026-08-12 (update: test-target unblocked, routing regression fixed)

The earlier `WardenTests` compilation blocker was resolved and the feature-010 test suite now executes and passes.

### Fixes applied

1. `WardenTests/Persistence/ChatHistoryRecoveryTests.swift`
   - Replaced non-generic `ChatEntity.fetchRequest()` / `ProjectEntity.fetchRequest()` calls (which returned `[any NSFetchRequestResult]` and broke `SortComparator`/`.objectID` inference) with explicit `NSFetchRequest<Entity>(entityName:)`.
   - Made the local `XCTAssertThrowsErrorAsync` helper generic (`<T>`) so it accepts throwing expressions that return a non-`Void` value (e.g. `createBranch` returning `ChatEntity`).
2. `Warden/Utilities/APIServiceFactory.swift`
   - Fixed a routing regression exposed by `LocalProviderTests.testFactoryRoutesEachLocalProviderToItsLocalService`: `lmstudio` was collapsed through its `inherits: "chatgpt"` config and returned a base `ChatGPTHandler`. The factory now routes `lmstudio` to its own `LMStudioHandler` (preserving local-endpoint validation) before applying `inherits`.

### Results

| Check | Outcome |
| --- | --- |
| XcodeMCP app build | **Passed** — `BuildProject` succeeded, 0 navigator issues. |
| CLI macOS app build | **Passed** — `** BUILD SUCCEEDED **`. |
| `LocalProviderTests` (all 9) | **Passed**. |
| `MLXHandlerModelTypeTests` (all 4) | **Passed**. |
| `ChatHistoryRecoveryTests` + branching/sharing suites | **Passed**. |
| Full `Warden` unit test suite | **Passed** (all non-UI tests green). |
| `AppShellUITests` (2 cases) | **Pre-existing failures** — `testCleanLaunchShowsSetupWelcomeAndPrimaryActions` (XCTAssertTrue on first-launch UI) and `testMalformedImportShowsNonDestructiveFeedback` (XCUITest "Failed to synthesize event: Timed out"). Verified to fail identically on the unmodified `a7d0d50` tree via `git stash`; they belong to feature 001 (app-shell) and are unrelated to feature 010. |
| `git diff --check` | **Clean** (no whitespace errors). |
| Secret/artifact inspection | **Clean** — diff limited to `APIServiceFactory.swift`, `ChatHistoryRecoveryTests.swift`, and spec artifacts; no keys, prompts, weights, or build output. |

Commands used the macOS `arm64` destination with ad-hoc signing (`CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-"`).
