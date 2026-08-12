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
