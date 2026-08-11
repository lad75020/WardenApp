# Feature Specification: App Shell and Onboarding

**Feature Branch**: `feature/time-machine-app-shell-and-onboarding`  
**Created**: 2026-08-11  
**Status**: Draft  
**Input**: User description: "Provide the native macOS application lifecycle, main window, first-run experience, preferences entry points, and appearance settings."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reach the Right Starting State (Priority: P1)

As a user launching Warden, I see a native main window and a clear next action based on whether I have configured an AI provider and whether chats already exist.

**Why this priority**: Every other capability depends on users reaching a usable and understandable application shell.

**Independent Test**: Launch with three isolated local states—no provider, provider with no chats, and provider with existing chats—and verify the welcome content and primary action for each state without live provider credentials.

**Acceptance Scenarios**:

1. **Given** no AI provider is configured, **When** Warden opens with no selected chat, **Then** the welcome screen offers interactive setup and direct access to Settings.
2. **Given** a provider is configured and no chats exist, **When** Warden opens, **Then** the welcome screen offers creation of the first chat.
3. **Given** chats already exist and none is selected, **When** Warden opens, **Then** the user is told to select a chat or create a new one and can reopen the setup guide.
4. **Given** a previously opened chat still exists, **When** the main view appears, **Then** that chat is restored as the active selection.

---

### User Story 2 - Complete Guided Setup (Priority: P2)

As a first-time user, I can follow a short guide that explains Warden, takes me to provider settings when needed, confirms local conversation storage, and starts my first chat.

**Why this priority**: Guided setup removes the largest first-run obstacle while remaining independently useful before any real provider request is made.

**Independent Test**: Reset the onboarding-completion preference, launch without configured providers, traverse the guide forward and backward, open Settings from the provider step, complete setup, and verify a new chat is selected.

**Acceptance Scenarios**:

1. **Given** onboarding has not been completed, **When** the user chooses interactive setup, **Then** a three-step guide presents welcome, provider setup, and readiness information with visible progress.
2. **Given** the user is beyond the first step, **When** Back is selected, **Then** the immediately preceding step appears without losing the guide state.
3. **Given** the provider-setup step is visible, **When** the user selects Open Settings, **Then** the Settings window comes to the front and the onboarding guide remains recoverable.
4. **Given** the final step is visible, **When** the user selects Start, **Then** onboarding is marked complete, the guide closes, and a new chat is created.
5. **Given** onboarding was completed previously, **When** an experienced user has existing chats, **Then** the setup guide remains available as optional help rather than being forced automatically.

---

### User Story 3 - Control the Native App Shell and Appearance (Priority: P3)

As a macOS user, I can use familiar windows, menus, keyboard shortcuts, and Settings to control Warden and choose an appearance that persists across launches.

**Why this priority**: Native controls and consistent appearance make the core experience efficient and predictable after initial setup.

**Independent Test**: Open Settings from both the application menu and welcome screen, change each appearance option, reopen Settings, exercise shell shortcuts, and relaunch to verify persistence.

**Acceptance Scenarios**:

1. **Given** the main window is active, **When** the user presses Command-Comma or chooses Settings, **Then** one reusable Settings window is shown and brought forward instead of creating duplicates.
2. **Given** Settings is open, **When** the user chooses System, Light, or Dark appearance, **Then** both the main and Settings windows reflect the choice and retain it after relaunch.
3. **Given** Settings is open, **When** the user changes chat font size or sidebar-icon visibility, **Then** the preference is retained and used by the corresponding UI.
4. **Given** the main window is active, **When** the user invokes New Chat, New Project, New Window, or Toggle Sidebar from the menu or shortcut, **Then** the action applies to the intended window and does not unexpectedly alter another window.
5. **Given** Warden has previously saved a main-window frame, **When** it relaunches, **Then** the saved frame is restored; otherwise, a sensible centered default is used.

### Edge Cases

- Reopening Settings while it is already visible brings the existing window forward.
- Closing Settings releases its presentation state so a later request opens a functional Settings window.
- A saved last-chat identifier that no longer resolves leaves the user on the correct welcome state without an error or crash.
- An onboarding completion action triggered more than once creates at most one intended new-chat transition.
- A Core Data store-load failure presents an understandable warning and allows temporary in-memory use while making clear that session changes will not persist.
- Appearance changes made while Settings is open stay consistent between all visible Warden windows.
- Cancelling an import or export panel leaves existing data unchanged; malformed import data produces a visible, non-destructive error.
- Window and onboarding state remain usable with no network connection and no provider credentials.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Warden MUST present a native macOS main window containing navigation and a detail area suitable for welcome, chat, project, and preview content.
- **FR-002**: The welcome experience MUST select its messaging and primary actions from the presence of configured providers, the number of chats, and onboarding completion state.
- **FR-003**: Users MUST be able to launch a three-step onboarding guide, move backward and forward, open Settings from the provider step, and finish by starting a chat.
- **FR-004**: Completing onboarding MUST persist across application launches while preserving an optional way to reopen the guide.
- **FR-005**: Settings MUST be accessible from the application menu and relevant in-app entry points.
- **FR-006**: Repeated Settings requests MUST activate one existing Settings window rather than create duplicate windows.
- **FR-007**: Users MUST be able to choose System, Light, or Dark appearance, a chat font size from 10 to 24 points, and whether AI service icons appear in the sidebar.
- **FR-008**: Appearance and general UI preferences MUST persist across application launches and update visible Warden windows consistently.
- **FR-009**: The app shell MUST expose native actions for New Chat, New Project, New Window, Settings, and Toggle Sidebar with standard discoverable keyboard shortcuts.
- **FR-010**: A New Chat command MUST target the intended main window when multiple windows exist.
- **FR-011**: The main window MUST restore its saved frame when available and otherwise open centered at a practical default size.
- **FR-012**: On launch, the app MUST restore the last selected chat when that chat still exists and otherwise show the appropriate welcome state.
- **FR-013**: A persistent-store startup failure MUST not crash the app; the user MUST receive a clear warning before the session continues with non-persistent fallback storage.
- **FR-014**: General Settings MUST support user-initiated JSON chat backup export and import, with cancellation and invalid-data paths that do not corrupt current data.
- **FR-015**: Existing unaffected provider, chat, project, and settings behavior MUST continue to operate as before.

### macOS UX Requirements

- **UX-001**: Window creation, activation, closing, resizing, frame restoration, menus, and shortcuts MUST follow native macOS conventions.
- **UX-002**: Welcome and onboarding states MUST provide an obvious primary action, visible progress, Back navigation where applicable, and understandable empty and failure messaging.
- **UX-003**: All onboarding, welcome, tab, and Settings controls MUST be keyboard reachable and expose meaningful accessibility labels; progress and state MUST not rely on color alone.
- **UX-004**: Appearance changes MUST avoid disruptive window recreation, unexpected focus loss, or duplicate Settings windows.
- **UX-005**: User-facing text MUST remain localizable and support increased text size without truncating primary actions.

### Data, Migration, and Privacy Requirements

- **DP-001**: This feature MUST NOT require a Core Data schema change; onboarding completion, appearance, font size, sidebar visibility, window frame, and last-chat selection are local application preferences.
- **DP-002**: Existing local preference values and persisted window frames MUST remain backward compatible after updates.
- **DP-003**: The shell and onboarding MUST NOT request, store, display, or log provider secrets; provider credentials remain owned by the provider-configuration flow and macOS Keychain.
- **DP-004**: Welcome, onboarding, window management, and appearance changes MUST work locally without network access or telemetry.
- **DP-005**: Chat backup files are user-selected, local, unencrypted JSON; the UI MUST disclose this before export or import and MUST NOT transmit backup contents.

### Key Entities

- **Onboarding State**: A local completion flag determining whether first-time setup is promoted; it remains resettable only through an explicit future capability.
- **Appearance Preferences**: Local selections for color scheme, chat font size, and sidebar service-icon visibility.
- **Window State**: Saved main and Settings window geometry plus the identifier of the last opened chat.
- **Welcome Context**: Derived state combining configured-provider presence, chat count, active selection, and onboarding completion.

## Compatibility and Scope

- **Affected modules**: `Warden/WardenApp.swift`, `Warden/UI/ContentView.swift`, `Warden/UI/WelcomeScreen/`, `Warden/UI/Preferences/SettingsView.swift`, `Warden/UI/Preferences/PreferencesView.swift`, `Warden/UI/Preferences/TabGeneralSettingsView.swift`, `Warden/Utilities/SettingsWindowManager.swift`, and focused tests in `WardenTests/` or `WardenUITests/`.
- **Existing behavior preserved**: Provider integrations, chat streaming, Core Data chat content, project management, model selection, MCP execution, quick chat, and media rendering remain functionally unchanged except where they are launched from the app shell.
- **Out of scope**: Provider credential validation, detailed chat persistence semantics, message streaming, project workflows, personas, search, attachments, local-model execution, MCP tool behavior, and multi-agent response behavior.
- **Dependencies**: Existing macOS windowing, local preferences, persistence, and application-command capabilities; no new third-party dependency is proposed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In each supported startup state, a user can identify and invoke the primary next action within 10 seconds of the welcome screen appearing.
- **SC-002**: A first-time user can traverse onboarding, reach provider settings, return, and start a chat in no more than 2 minutes, excluding time spent obtaining credentials.
- **SC-003**: Repeating the Settings command 10 times results in exactly one visible Settings window, and closing then reopening it succeeds.
- **SC-004**: Appearance, font-size, sidebar-icon, onboarding, main-window-frame, and last-chat preferences survive 5 consecutive relaunch checks without unintended reset.
- **SC-005**: All specified startup-state, onboarding-navigation, menu-command, duplicate-window, fallback-storage, and invalid-import tests pass deterministically without live credentials or network access.
- **SC-006**: Launch, welcome-state transitions, and Settings activation remain responsive, with visible feedback or the requested window appearing within 1 second under normal local conditions.
- **SC-007**: Failure and cancellation scenarios complete without a crash, leaked secret, corrupted existing chat data, or an unexplained blank screen.

## Assumptions

- Warden remains a single-user, privacy-first native macOS application.
- A configured provider is represented by at least one locally stored provider configuration; validating or repairing that configuration belongs to a later feature.
- Completing onboarding does not prove that provider credentials are valid; it records that the user finished or dismissed the guide.
- Multiple main windows may coexist, while Settings is intentionally a single reusable auxiliary window.
- Existing menu labels and standard shortcuts remain the baseline unless usability testing demonstrates a conflict.
