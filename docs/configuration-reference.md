# Configuration reference

This document describes configuration that is visible in the current source. It distinguishes user preferences, non-secret service configuration, credentials, and sandbox permissions.

## Application constants

The central file is `Warden/Configuration/AppConstants.swift`.

| Area | Current value or rule |
| --- | --- |
| Request timeout | 180 seconds |
| Streamed UI update interval | 0.05 seconds |
| Large message threshold | 25,000 symbols |
| Multi-agent maximum | 3 concurrent services |
| Quick Chat panel height | 60 to 600 points |
| Tavily default depth | `basic` |
| Tavily default result count | 5 |
| Tavily maximum result count | 10 |
| Search command aliases | `/search`, `/web`, `/google` |
| Chat font-size setting | 10 to 24 points |
| Default chat model constant | `gpt-5` in the current source |
| Default context size constant | 10 in the current source |

These values are application defaults. Provider-specific limits and remote service behavior still apply.

## API service configuration

A saved API service contains non-secret values such as:

- Stable UUID.
- Display name.
- Provider type.
- Endpoint URL.
- Selected model.
- Context size.
- Streaming preference.
- Chat-name generation preference.
- Image-upload capability.
- Selected-model metadata.
- Keychain token identifier.

A credential is entered through the service UI and stored through `TokenManager`. It must not be added to Core Data, UserDefaults, source fixtures, exported diagnostics, or logs.

The service editor supports create, edit, duplicate, test, model refresh, custom model selection, save, set default, and delete operations.

## Appearance and shell preferences

The application shell uses persistent preferences for values including:

- Preferred color scheme.
- Chat font size.
- Sidebar AI-service icon visibility.
- Onboarding completion.
- Last selected chat.
- Main window frame restoration.
- Default service reference.

The main window commands are:

| Action | Current shortcut |
| --- | --- |
| Preferences | `Cmd+,` |
| New Chat | `Cmd+N` |
| New Project | `Cmd+Shift+N` |
| New Window | `Cmd+Option+N` |
| Toggle Sidebar | `Cmd+S` |

The exact menu label can follow the macOS version and current UI localization, but the underlying commands are defined by `WardenApp` and `AppConstants`.

## Search configuration

Tavily search reads these preference values through its service code:

- Search depth.
- Maximum result count.
- Whether an answer summary is included.

The default search service base URL is defined in `AppConstants.TavilyConfig`. The service uses POST search requests and validates the response before converting sources into message metadata.

Search is opt-in per request. A missing search credential is a user-facing error, not a reason to send the prompt without its requested search context.

## MCP configuration

MCP configurations are persisted under the `MCPServerConfigs` preference key after sanitization. A configuration contains:

- UUID.
- Display name.
- Transport type: `stdio` or `sse`.
- Stdio command and arguments when applicable.
- Environment values.
- SSE URL when applicable.
- Enabled flag.

Sensitive environment keys are identified by names containing terms such as token, key, secret, password, auth, bearer, or credential. Their values are placed in Keychain storage and replaced in the persisted configuration by a marker. Do not edit the marker as if it were a clear environment value.

MCP auto-connect is disabled by default and is enabled only by the explicit launch preference.

## Hotkey configuration

The application defines persisted display values for actions such as:

- Copy last response.
- Copy chat.
- Export chat.
- Copy last user message.
- New chat.
- Quick Chat.

The source defaults include menu/action combinations and a Quick Chat global combination. The settings UI can change actions individually or reset all actions. A failed system-wide registration does not disable the in-app menu action.

## User data and migration flags

Migration state is stored in UserDefaults so one-time patches are not repeatedly applied. Current patch/migration concerns include:

- Default personas.
- Persona ordering.
- Image-upload defaults.
- Persona color-to-symbol conversion.
- Ollama chat endpoint conversion.
- Legacy API service migration.
- Legacy token migration.
- Persona symbol migration.

Migration flags are implementation details. Treat them as opaque and do not manually toggle them unless a recovery procedure specifically requires it.

## Sandbox entitlements

`Warden/Warden.entitlements` currently enables:

- App Sandbox.
- Network client access.
- Network server access.
- User-selected file read/write access.

The user-selected file entitlement does not mean that the app has unrestricted filesystem access. File access should be acquired through explicit user selection and kept within the intended operation.

## Configuration precedence

When a value can come from several places, use this order:

1. Explicit value saved for the selected service or chat.
2. User-selected value in Preferences.
3. Current provider default in `AppConstants`.
4. Safe application fallback.

A failed model refresh or transient discovery error must not overwrite a working saved selection with an empty value.

## Configuration safety

- Do not put credentials in URLs, command examples, source code, fixtures, or documentation.
- Do not treat UserDefaults or Core Data as secret storage.
- Do not log full local paths when a safe category or count is sufficient.
- Use HTTPS for credential-bearing remote endpoints.
- Use local HTTP only for intentional loopback services.
- Make configuration changes through the application UI so Keychain cleanup and stable identities are handled together.
