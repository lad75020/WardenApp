# Implementation Log — Personas and Model Selection

## Scope and source-of-truth decisions

- **Branch:** `feature/time-machine-personas-and-model-selection`
- **Feature pointer:** `.specify/feature.json` → `specs/007-personas-model-selection`
- The Xcode target compiles `Warden/UI/Chat/BottomContainer/PersonaSelectorView.swift`. The similarly named file in `Warden/UI/Chat/ChatParameters/` is not a target member; it was left untouched to avoid duplicate type membership or unrelated refactoring.
- This legacy project enumerates source files explicitly in the Xcode project. The provider/model identity policy and mutation coordinator were deliberately co-located in the already-compiled `Warden/Utilities/FavoriteModelsManager.swift`; no `.pbxproj` edit or target-membership change was required.

## Implemented behavior

- Persona selection now changes only `chat.persona`, saves the managed-object context, and recreates the message manager only after a successful save.
- A persona default service is offered through a distinct explicit action. It never changes the chat model/service merely by selecting the persona.
- Shared model-selection code validates the requested provider/model against configured services and locally visible models, saves the provider/model pair atomically, then posts the existing chat-scoped `RecreateMessageManager` notification. Invalid or failed changes leave the previous pair intact.
- Provider/model identity is structured (`provider`, `modelID`) rather than delimiter-based, avoiding collisions and preserving opaque model identifiers. Existing colon-delimited favorites are migrated safely by splitting only their first delimiter.
- The selector and favorite quick-access bar use the shared policy/coordinator, expose recoverable non-sensitive error UI, and use accessible native SwiftUI buttons and stable provider/model identity.
- The message-input layout was enlarged so the explicit persona-default action is not clipped.
- Existing `ModelInfoTooltip` was retained: its metadata input is already optional and cache-derived, so missing or stale metadata degrades without a render-time fetch.
- Added credential-free regression coverage in the compiled existing test target file `WardenTests/Utilities/MessageParserTests.swift` for opaque identities, legacy favorite migration, and unavailable/invisible model rejection.

## Security and privacy review

Passive review of changed persistence and diagnostics found no high-impact issue:

- Favorite storage contains only non-secret provider/model identifiers in local app preferences.
- The new selection path neither persists nor logs API keys, endpoints, prompts, messages, or conversation content.
- Save-failure diagnostics use a generic `WardenLog` message.
- No telemetry, analytics, transport, Keychain, Core Data schema, or migration behavior was added.

## Automated verification

| Check | Command / authority | Result |
| --- | --- | --- |
| IDE build | XCodeMCP `BuildProject` (`windowtab3`) | Passed: “The project built successfully.” |
| macOS arm64 build | `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS,arch=arm64' -resultBundlePath /tmp/Warden-PersonasModelSelection-build.xcresult build` | Passed: `** BUILD SUCCEEDED **` |
| Build result bundle | `xcrun xcresulttool get object --legacy --path /tmp/Warden-PersonasModelSelection-build.xcresult --format json` | Passed: `BUILD_XCRESULT=VALID` |
| Focused XCTest | `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS,arch=arm64' -only-testing:WardenTests/PersonasModelSelectionRegressionTests test` | Passed: 3 tests, `** TEST SUCCEEDED **` |
| Full XCTest/XCUITest suite | `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS,arch=arm64' test` | Passed: `** TEST SUCCEEDED **`; UI suite: 9 tests, 0 failures |
| Full test result bundle | `xcrun xcresulttool get object --legacy --path /Volumes/WDBlack4TB/XCodeDerivedData/Warden-ctfytbkwcebgvoaldciocvdteqwy/Logs/Test/Test-Warden-2026.08.12_04-29-28-+0200.xcresult --format json` | Passed: `TEST_XCRESULT=VALID` |

The full-suite run emitted non-fatal LLDB launch snapshot messages; the authoritative `xcodebuild` exit status was 0 and its result bundle was valid.

## Manual verification status

The manual privacy workflow in `quickstart.md` was **not run**. It needs a real configured local service, model, persona, and chat, and would mutate existing persisted Warden configuration/chat state. No stable credential-free UI fixture exists. This is an explicit remaining manual verification item, not a passed check.
