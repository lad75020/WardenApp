# Research: App Shell and Onboarding

## Decision 1: Harden the Existing Shell

- **Decision**: Extend the existing `WindowGroup`, `ContentView`, welcome/onboarding views, and `SettingsWindowManager` rather than introducing a new app coordinator.
- **Rationale**: Current ownership already follows the project boundaries and covers window restoration, menus, fallback persistence, welcome routing, and a single auxiliary Settings window. The identified gaps are localized behavior and testability issues.
- **Alternatives considered**: A global navigation coordinator or replacement scene architecture was rejected because it adds cross-module state and migration risk without user value.

## Decision 2: Preserve Existing Local Preference Keys

- **Decision**: Keep the established onboarding, appearance, font, sidebar, last-chat, and frame-autosave keys.
- **Rationale**: Existing users retain their settings without migration, and the feature requires no Core Data model change.
- **Alternatives considered**: Moving shell preferences into Core Data was rejected because they are device-local UI state and would unnecessarily couple shell presentation to persistence migrations.

## Decision 3: Use Focused Internal State Contracts for Tests

- **Decision**: Isolate only the welcome-state and onboarding-transition logic needed for deterministic XCTest coverage under `Warden/UI/WelcomeScreen/`.
- **Rationale**: Pure internal state resolution can be tested without paid credentials, UI-introspection libraries, or fragile pixel assertions while SwiftUI remains responsible for rendering.
- **Alternatives considered**: Snapshot/ViewInspector dependencies were rejected because the repository has no such dependency and this feature does not justify adding one. XCUITest-only coverage was rejected because it would make all state regression checks slower and more environment-sensitive.

## Decision 4: Retain One Reusable Settings Window

- **Decision**: Keep `SettingsWindowManager` as the single main-actor owner of the auxiliary Settings window and bring an existing visible window forward.
- **Rationale**: This matches native macOS expectations and prevents duplicate state trees.
- **Alternatives considered**: A separate Settings scene was not selected because the current app deliberately routes all entry points through a reusable AppKit window and replacing it would exceed the feature's smallest safe scope.

## Decision 5: Make Backup Failures Visible but Non-Destructive

- **Decision**: Continue user-selected local JSON import/export and surface decode/read/write failures through existing user-facing error presentation without logging chat contents.
- **Rationale**: The current format and store APIs are already established. The missing requirement is consistent feedback, not a new backup format.
- **Alternatives considered**: Silent logging was rejected as unusable; automatic repair or partial import was rejected because it changes data semantics and belongs to persistence planning.

## Decision 6: No Provider or Network Work

- **Decision**: Treat provider presence only as local configured-state input to the welcome experience.
- **Rationale**: Onboarding explains provider setup but must remain functional offline and must not validate credentials itself.
- **Alternatives considered**: Live provider validation during onboarding was rejected because it would duplicate provider-configuration behavior, require credentials in tests, and expand privacy/network scope.

## Resolved Unknowns

No technical or product clarification markers remain. Existing source and the project constitution determine the platform, persistence boundary, window ownership, preference compatibility, testing surfaces, and privacy constraints.
