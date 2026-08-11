# App Shell UI Contract

This contract defines observable behavior for the native app shell. It is not a network API.

## Welcome Routing

| Local state | Required presentation | Primary actions |
|---|---|---|
| No configured provider | Setup-required welcome | Start interactive setup; Open Settings |
| Provider configured, zero chats | First-chat welcome | New Chat |
| Provider configured, chats exist, no selection | Selection welcome | Select a chat or New Chat; optional setup guide |
| Chat/project selected | Feature content | Shell navigation and menus remain available |

## Onboarding Controls

| Step | Back | Primary | Secondary |
|---|---|---|---|
| Welcome | Hidden/disabled | Next | None |
| Provider setup | Back | Open Settings | Next |
| Ready | Back | Start | None |

- Progress exposes the current step and total step count to accessibility clients.
- Open Settings does not alter onboarding completion or current step.
- Start writes completion once, dismisses the guide, and issues exactly one new-chat action.
- The guide can be revisited from the supported welcome/help state after completion.

## Settings Window

- Every Settings entry point routes through one reusable window owner.
- If visible, a Settings request activates and raises the existing window.
- After close, a later request creates a functional replacement window.
- The window reflects System, Light, or Dark preference changes without duplicate creation.

## General Preferences

- Theme accepts exactly System, Light, or Dark.
- Chat font size accepts supported menu values from 10 through 24 points.
- Sidebar service-icon visibility is Boolean.
- Values persist across relaunch and do not trigger network access.

## Backup Feedback

- Export cancellation changes nothing and shows no failure.
- Import cancellation changes nothing and shows no failure.
- Read, decode, persistence, encode, or write failure produces a visible error.
- Failure reporting must not include backup contents, provider secrets, or private prompts in logs.

## Accessibility Identifiers

Stable identifiers should cover, at minimum:

- Welcome container and setup/new-chat/settings actions.
- Onboarding container, progress, Back, Next, Open Settings, and Start controls.
- Settings window and General tab.
- Theme selector, chat-font selector, and sidebar-icon toggle.

Identifiers are test hooks and accessibility aids; user-visible labels remain localized, meaningful text.
