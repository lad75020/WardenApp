# Getting started

This guide takes a new developer or user from a clean WardenApp checkout to a first working chat.

## Prerequisites

- macOS with a recent Xcode version capable of building this project.
- The Swift toolchain supplied by Xcode.
- A code-signing configuration if the app will be distributed rather than run locally.
- Either a credential for a hosted provider or a local Ollama or LM Studio service for local inference.
- Network access on the first build if Xcode must resolve uncached remote Swift packages.

WardenApp can open its native shell without provider credentials or a network connection. A configured AI service is required only to send a request.

## Open the project

From the repository root:

```bash
open Warden.xcodeproj
```

In Xcode, select the `Warden` scheme and run with `Cmd+R`.

For a command-line build, use the verified macOS destination:

```bash
xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build
```

The project resolves local packages from `Packages/` and remote Swift packages through the Xcode package graph. The project currently exposes the application, unit-test, UI-test, and auxiliary image CLI targets; see [Testing and release](testing-and-release.md).

## Complete the first setup

1. Launch WardenApp.
2. If the welcome screen is shown, follow the onboarding steps. The onboarding flow can move backward and forward and can open Settings during provider setup.
3. Open Preferences with `Cmd+,`.
4. Open the **API Services** tab.
5. Add a service with the `+` control.
6. Choose the provider type, service name, endpoint, and model.
7. Enter the provider credential in the credential field when the selected provider needs one.
8. Use **Test Connection** before saving when the provider supports a bounded test request.
9. Save the service and optionally make it the default for new chats.
10. Start a new chat with `Cmd+N`, select the service/model if necessary, and send a non-empty prompt.

Credentials are stored through the Keychain-backed token manager. Do not put credentials in source files, UserDefaults, exported diagnostics, or shell history.

## OpenRouter example

The repository includes a detailed OpenRouter walkthrough in [Setup.MD](../Setup.MD). The current default service configuration uses:

```text
https://openrouter.ai/api/v1/chat/completions
```

The setup flow is the same as above: choose `OpenRouter`, enter the credential in Preferences, choose or refresh a model, test the connection, save, and set the service as default if desired. Use the endpoint already shown by the application unless a deliberate custom endpoint is required.

## Use a local service

### Ollama

1. Start Ollama outside WardenApp.
2. Add an `Ollama` service in API Services.
3. Keep the local endpoint supplied by the provider defaults unless the local service uses another port.
4. Refresh the model list when discovery is available.
5. Select a model and save the service.

The source defaults identify Ollama as a local provider and the migration code upgrades older `/api/generate` configurations to the chat endpoint when required.

### LM Studio

1. Start the LM Studio local server.
2. Add an `LM Studio` service.
3. Set the endpoint and the model identifier exposed by the local server.
4. Refresh models when the server supports discovery.
5. Test and save the service.

### Other local runtimes

The provider configuration also contains local paths for Hugging Face, Core ML text generation, and MLX. These paths require local model assets and the runtime support included by the target build. If assets are missing or incompatible, keep the draft configuration and use the error message to correct the model selection.

## First useful actions

- `Cmd+N` creates a new chat.
- `Cmd+Shift+N` creates a new project.
- `Cmd+Option+N` opens a new window.
- `Cmd+S` toggles the sidebar.
- `Cmd+,` opens Preferences.
- The application menu also exposes copy, export, retry, and Quick Chat actions.

The configured appearance, chat font size, sidebar icon preference, selected chat, and service configuration are persisted locally.

## First test run

Run the unit and UI tests from the project root:

```bash
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'
```

The shared test plan can also be invoked as follows:

```bash
xcodebuild -project Warden.xcodeproj -scheme Warden -testPlan Warden test
```

Tests are designed to run without paid provider credentials. Provider-dependent behavior should be exercised with test doubles, local services, or the existing fixture paths rather than with a real secret.

## What happens on a database failure

If the persistent store cannot be opened, WardenApp presents a user-facing warning and attempts to use a temporary in-memory store for the current session. Existing data is not intentionally replaced by that fallback, but changes made in the fallback session are not durable. Restart the app and investigate the underlying store before relying on those changes.

## Next steps

- Read the [User guide](user-guide.md) for end-user workflows.
- Read the [Provider reference](provider-reference.md) before adding or diagnosing a service.
- Read the [Developer guide](developer-guide.md) before changing shared runtime paths.
- Read [Security and privacy](security-and-privacy.md) before handling credentials, MCP configuration, or export data.
