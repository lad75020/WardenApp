# Quickstart Verification: Provider and Model Configuration

## Automated checks

1. Run focused lifecycle/validation/redaction tests added for this feature:
   ```sh
   xcodebuild test -project Warden.xcodeproj -scheme Warden \
     -destination 'platform=macOS,arch=arm64' \
     -only-testing:WardenTests/<ProviderConfigurationTestClass>
   ```
2. Run the full native test target:
   ```sh
   xcodebuild test -project Warden.xcodeproj -scheme Warden \
     -destination 'platform=macOS,arch=arm64'
   ```
3. Run the canonical app build:
   ```sh
   xcodebuild -project Warden.xcodeproj -scheme Warden \
     -destination 'platform=macOS,arch=arm64' build
   ```

## Manual macOS Settings smoke test

1. Open **Settings → API Services** and verify the empty/list/detail states are keyboard reachable and have labels beyond color.
2. Add a hosted service with an intentionally synthetic credential and a valid HTTPS endpoint. Save, reopen, and confirm metadata remains while the token is not rendered or logged.
3. Change its endpoint to a remote `http://` URL while retaining the credential. Verify save, test, and refresh are blocked with a safe HTTPS/localhost explanation.
4. Add a local Ollama/LM Studio service with a loopback HTTP endpoint and no credential. Verify it can be saved.
5. Trigger model refresh and test using deterministic fixture/failure conditions. Verify clear progress/failure text, no raw provider content, and unchanged saved model after failure.
6. Duplicate the hosted service. Verify a new list item/identity, original remains unchanged, and the copy can be edited independently.
7. Mark one service default, delete it through confirmation, and reopen Settings. Verify no service has an unintended Default badge and the default reference is cleared.
8. For MLX/CoreML, invoke **Grant Access**, cancel the chooser, and verify no model path/configuration changes. Repeat with a permitted test folder and verify access works.

## Privacy review

Inspect the final diff for `apiKey`, token fields, `UserDefaults`, Core Data entity assignment, `WardenLog`, HTTP endpoint validation, and default-reference handling. Test code must synthesize fake tokens at runtime and must not contain real provider credentials.
