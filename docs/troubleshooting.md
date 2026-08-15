# Troubleshooting

This guide focuses on failures that can be diagnosed from the current WardenApp implementation without exposing credentials or private chat content.

## The project does not build

1. Confirm that Xcode is selected as the active developer tool.
2. Open the project directly:

   ```bash
   open Warden.xcodeproj
   ```

3. Let Xcode resolve the package graph.
4. Confirm the `Warden` scheme and a macOS destination are selected.
5. Retry the verified build command:

   ```bash
   xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build
   ```

If package resolution fails, check local package paths under `Packages/` and the network connection required for uncached remote packages. Do not add credentials to a package URL or commit local package state.

## The app opens but no provider can send

Check the selected service in Preferences:

- The service is enabled and has a stable saved identity.
- The endpoint is a valid HTTP or HTTPS URL when the provider expects a URL.
- A remote endpoint carrying a credential uses HTTPS.
- A local loopback endpoint is intentional and points to a running local service.
- The model identifier is present and compatible with the provider.
- The credential was entered in the current service rather than another duplicated service.
- The service test succeeds before attempting a full chat.

For a hosted provider, re-enter the credential in Preferences and save before testing. For Ollama or LM Studio, start the local server and verify that its advertised model name matches the saved selection.

## The endpoint is rejected as insecure

WardenApp refuses to send a non-empty credential to an insecure remote HTTP endpoint. HTTPS is required for remote credential transport. HTTP is allowed only where the URL is recognized as an allowed local/loopback transport.

Change the endpoint to its HTTPS form, or use a deliberately local loopback service. Do not bypass the validation by placing a secret in a URL or in a custom header outside the provider configuration path.

## Models do not refresh

Model discovery is provider-specific. A failed refresh must not erase the previously saved model.

Try the following:

1. Confirm the endpoint and credential with **Test Connection**.
2. Check that the selected provider supports discovery.
3. Confirm that the local server is running for Ollama or LM Studio.
4. Retry the refresh after saving the connection.
5. Use a manually entered model identifier only when the provider supports custom selection.

If discovery still fails, keep the last known working model and inspect the user-facing error. Do not log the raw response or credential.

## A chat is marked unavailable

A chat remains in local history when its original service was deleted or is no longer valid. This is intentional data preservation.

Repair it from the chat/service controls by mapping it to an existing valid service. Repair changes the service mapping, not the message history. If no valid service exists, create one in Preferences first. Delete the chat only as an explicit user action.

## History is missing after launch

Check the following in order:

1. Confirm that the app opened the expected macOS user data location.
2. Look for a persistent-store warning from the application.
3. If a store-load failure occurred, remember that the fallback store is temporary and does not contain durable changes from the failed session.
4. Restart the app after closing any other WardenApp process that may be using the store.
5. Use the supported JSON backup/import flow only after confirming the source file is valid.
6. Do not delete the original store while investigating.

The application migrates legacy `chats.data` JSON history when present and applies database patches at launch. Malformed data should produce a recoverable state rather than silently overwriting valid history.

## The app reports a database error

`PersistenceController` attempts to load `wardenDataModel` with persistent history tracking and remote-change notifications. If loading fails, it presents a warning and attempts an in-memory store for the current session.

Consequences of the fallback:

- The app may remain usable for the current session.
- Existing persistent data is not intentionally replaced.
- New changes made while the fallback is active are not durable.
- Restarting without addressing the store may repeat the problem.

Use the repository's persistence recovery UI tests when diagnosing a development build. Avoid making destructive store changes until a backup exists.

## A request keeps showing as waiting

The request lifecycle should clear waiting and streaming indicators on success, failure, or cancellation. If the UI is stale:

1. Stop the response.
2. Switch back to the originating chat.
3. Retry the request after confirming the provider state.
4. Restart WardenApp if the stale state survives cancellation.

The stream controller and request identifiers are intended to prevent stale callbacks from overwriting newer work. Do not assume that a late provider callback belongs to the current chat.

## Search does not run

Web search is opt-in and uses the command aliases `/search`, `/web`, or `/google`. Confirm that:

- The query is not blank.
- A valid search credential is configured.
- The search depth, result limit, and include-answer settings are valid.
- Network access to the configured search service is available.

A failed search keeps the prompt unsent. Retry, or explicitly disable search and send the unchanged prompt. Empty results are a successful empty result, not a reason to invent citations.

Only HTTPS source URLs are actionable. A source that is displayed but not clickable may be malformed or use another scheme by design.

## MCP server does not connect

Confirm the configuration:

- Stdio has a command and correct arguments.
- SSE has a valid URL.
- The server is enabled.
- The executable is available to the application process.
- Required environment values are present.
- The server advertises the expected MCP tools.

Run **Test Connection** before saving or connecting. The status should move through connecting to connected with a tool count, or to an error with a readable message.

MCP does not auto-connect on launch unless the explicit preference is enabled. If an environment field is sensitive, its UserDefaults value may be a Keychain marker rather than the clear value. Do not replace that marker manually.

If a tool call fails, inspect the tool status and the expanded message record. Common causes are a disconnected owning server, a missing tool, malformed JSON arguments, or cancellation during execution.

## Attachments fail to prepare

Check that the selected file:

- Still exists and is readable.
- Is not zero bytes or password protected when extraction is required.
- Is supported by the current file/image path.
- Is not being deleted or moved while it is prepared.

A failed attachment should remain visibly failed or unavailable and must not be sent as complete content. Remove it from the draft and add a readable local copy if needed.

## An image or video cannot be saved

The save action uses a user-selected destination. Canceling or failing the panel must not delete the source.

Try another destination with write permission and confirm that the source media is still a readable regular local file. For generated video, use the reveal-in-Finder action only while the generated file remains available.

## HTML preview is blank or malformed

HTML preview is explicitly initiated from an HTML code block. Incomplete HTML, unsupported markup, or content that depends on external network resources may render poorly. Refresh or close the preview and inspect the source code instead.

The preview is intentionally isolated from external navigation, script execution, persistent website data, and filesystem access. It is not a general-purpose web browser.

## Hotkey registration fails

A global combination may already be owned by another application or may not map to a supported key code. Choose another combination in the Hotkeys settings. WardenApp continues to expose the in-app menu shortcut path even when system-wide registration fails.

Non-global actions are dispatched in-app and do not require Accessibility permissions.

## Keychain cleanup

The current `TokenManager` source uses the Keychain service `fr.dubertrand.WardenAI` and stores a bundle of service-keyed tokens. Older installations may contain legacy Keychain items from previous application versions.

Deleting a service from the application may not remove a legacy Keychain item. Use Keychain Access only after verifying the service identity and only as an explicit cleanup action. Never paste a secret into a bug report or diagnostic output.

## Testing a suspected bug

Run the relevant test target without paid credentials:

```bash
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'
```

For a focused unit test, use the standard Xcode syntax:

```bash
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/TestClassName/testMethodName
```

When reporting a failure, include the provider type, sanitized error category, scheme, destination, and reproducible steps. Exclude keys, authorization headers, complete prompts, response bodies, local secret values, and private conversation text.
