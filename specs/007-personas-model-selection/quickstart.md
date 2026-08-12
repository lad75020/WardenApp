# Quickstart: Verify Personas and Model Selection

## Preconditions

- Work from `feature/time-machine-personas-and-model-selection`.
- Do not use real provider credentials in tests or fixtures.
- Use an isolated/in-memory Core Data store and local model fixtures for focused tests.

## Focused verification

Run the feature's focused unit tests after adding them:

```bash
xcodebuild test \
  -project Warden.xcodeproj \
  -scheme Warden \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:WardenTests/PersonasModelSelectionTests
```

If UI coverage is added with deterministic launch fixtures, run it separately:

```bash
xcodebuild test \
  -project Warden.xcodeproj \
  -scheme Warden \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:WardenUITests/PersonasModelSelectionUITests
```

## Build and full regression gate

```bash
xcodebuild \
  -project Warden.xcodeproj \
  -scheme Warden \
  -destination 'platform=macOS,arch=arm64' \
  build

xcodebuild test \
  -project Warden.xcodeproj \
  -scheme Warden \
  -destination 'platform=macOS,arch=arm64'
```

Inspect each command's exit status and the generated `.xcresult` summary. CoreSimulator service warnings that do not change the command's final success status are non-blocking; compile/test failures are blocking.

## Manual native macOS path

1. Create a persona with a name, symbol, system message, temperature, and a default service.
2. Select it in an existing chat whose active service/model differs from the persona default. Confirm the active service/model remains unchanged and the next request uses the persona's behavior.
3. Invoke the separate default-service action. Confirm it switches only after the service/model is valid and the chat continues with the new pair.
4. Remove or make the referenced service/model unavailable. Confirm the explicit action is unavailable or displays a recoverable error without changing the chat.
5. Clear the persona. Confirm the chat retains its active service/model and uses its fallback behavior on later requests.
6. Open model selection. Search by provider and model, select a valid row, and confirm only the active chat refreshes.
7. Favorite a valid model, relaunch the app, confirm it reappears, and exercise two providers with the same model ID to verify distinct quick-access identity.
8. Inspect a model with metadata and one without/stale metadata. Confirm optional details degrade gracefully and no endpoint, credential, prompt, or conversation content appears.
9. Exercise keyboard navigation, visible selected states, empty lists, loading/unavailable states, and repeated favorite toggles.

## Privacy check

- Confirm no new `UserDefaults` value contains an API key, token, endpoint secret, prompt, or message content.
- Confirm diagnostics use `WardenLog` and disclose no sensitive content.
- Confirm this feature adds no telemetry, tracking, sync, or new network request destination.
