# WardenApp

WardenApp is a fork of Warden, a native SwiftUI macOS AI chat client with multi-provider, local-model, search, and developer-tool support.

## Highlights

- Native macOS app built in SwiftUI; no Electron or web wrapper.
- Supports hosted providers such as OpenAI, Anthropic, Gemini, Perplexity, and OpenRouter, plus local Ollama and LM Studio workflows.
- Stores chat data with Core Data and includes database migration/patch helpers.
- Stores API tokens in the macOS Keychain rather than Core Data.
- Includes web search, code-oriented workflows, syntax highlighting, file/image attachments, and Apple Silicon-friendly native UI behavior.
- This fork notes additional library support compared with the upstream SidhuK/WardenApp project.

## Repository layout

- `Warden/` - app source, SwiftUI UI, models, stores, utilities, assets, Core Data model, and entitlements.
- `Warden.xcodeproj/` - Xcode project.
- `WardenTests/` - unit tests.
- `WardenUITests/` - UI tests.
- `Warden.xctestplan` - shared test plan covering unit and UI test targets.
- `Packages/` - local package dependencies used by the app.
- `MLXZImageSwiftCLI/` - related local CLI/package support.
- `assets/` and `AppIcon.icon/` - app branding and screenshots.
- `scripts/` - local automation helpers.
- `Setup.MD` - OpenRouter setup guide and token-storage notes.

## Prerequisites

- macOS with a recent Xcode capable of building the project.
- Swift toolchain supplied by Xcode.
- API keys for hosted providers you want to use, or local Ollama/LM Studio services for local models.
- Developer signing configuration if you plan to distribute a built app.

## Installation and setup

Open the project in Xcode:

```bash
open Warden.xcodeproj
```

Build and run from Xcode with `Cmd+R`.

To configure OpenRouter after launching the app:

1. Open Warden preferences with `Cmd+,`.
2. Choose the API Services tab.
3. Add a service, set API Type to `OpenRouter`, and keep the default API URL unless you need a custom endpoint.
4. Paste the API token, choose or refresh the model list, test the connection, and save.
5. Set the service as default if desired.

## Documentation

The full documentation set is in [`docs/`](docs/README.md):

- [Getting started](docs/getting-started.md) - build, launch, and configure a first service.
- [User guide](docs/user-guide.md) - chats, models, attachments, search, MCP, and Quick Chat.
- [Functional requirements](docs/functional-requirements.md) - consolidated index for the twelve feature specifications.
- [Architecture](docs/architecture.md) - application layers, request flows, persistence, and integrations.
- [Provider reference](docs/provider-reference.md) - hosted and local provider behavior.
- [Developer guide](docs/developer-guide.md) - source layout, build, test, and extension workflow.
- [Security and privacy](docs/security-and-privacy.md) - credentials, transport, sandbox, logging, and data boundaries.
- [Troubleshooting](docs/troubleshooting.md) - common provider, persistence, search, MCP, and runtime issues.

## Run and development commands

The inspected README documents the source workflow as:

```bash
git clone https://github.com/lad75020/WardenApp.git
cd WardenApp
open Warden.xcodeproj
```

Then build/run in Xcode. No root package-manager scripts were present in the project root.

## Testing and checks

The test plan includes `WardenTests` and `WardenUITests`. Run them from Xcode, or with xcodebuild when the local scheme is available:

```bash
xcodebuild -project Warden.xcodeproj -scheme Warden -testPlan Warden test
```

If the scheme or destination differs locally, choose the matching scheme and macOS destination from Xcode.

## Configuration and security notes

- API tokens are stored in the macOS Keychain under the app's service/account scheme.
- Deleting an API service may stop use of a token but may not remove the underlying Keychain entry; remove it manually in Keychain Access if needed.
- Provider requests leave the device only for the API service or local endpoint selected by the user.
- Core Data load failures fall back to an in-memory store for the current session where implemented, so investigate database errors before relying on persistence.
