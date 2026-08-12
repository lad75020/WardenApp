# Tasks: Web Search and Citations

**Input**: Design documents from `specs/008-web-search-citations/`
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/web-search-ui-contract.md`, and `quickstart.md`
**Verification**: Deterministic XCTest/XCUITest plus the Warden macOS build; no live Tavily credential or external network is permitted in tests.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Work is parallelizable only when it has no unresolved dependency and edits distinct files.
- **[US#]**: Maps the task to its independently testable user story.
- Test tasks intentionally precede their production implementation.

## Phase 1: Baseline and Setup

**Purpose**: Establish an evidence-based baseline and preserve the clarified feature boundary.

- [X] T001 Record the target files, data boundaries, and no-schema-migration decision in `specs/008-web-search-citations/plan.md`.
- [ ] T002 Run the existing streaming regression suite in `WardenTests/Utilities/MessageManagerStreamingTests.swift` before touching `Warden/Utilities/MessageManager.swift`.
- [ ] T003 Run the baseline macOS build for `./Warden.xcodeproj` with scheme `Warden` and destination `platform=macOS`.
- [X] T004 [P] Confirm the feature test fixtures in `WardenTests/Utilities/TavilySearchServiceTests.swift` use injected URL loading and no credential from `Warden/Utilities/TavilyKeyManager.swift`.

**Checkpoint**: Existing build/test behavior is known and no implementation assumptions depend on real Tavily access.

---

## Phase 2: Foundational Contracts and Regression Tests

**Purpose**: Lock down shared HTTPS, request-isolation, persistence, and privacy behavior before changing send/UI paths.

- [X] T005 Add failing URL-validation and citation-conversion cases in `WardenTests/Utilities/TavilySearchServiceTests.swift` for valid HTTPS, HTTP, malformed/custom-scheme URLs, standalone citations, multi-byte text, and invalid citation indexes.
- [X] T006 [P] Add failing search-lifecycle/isolation cases in `WardenTests/Utilities/MessageManagerSearchTests.swift` for cancellation, failure without provider send, and no cross-request metadata attachment.
- [X] T007 [P] Add failing compatibility tests in `WardenTests/Persistence/MessageSearchMetadataTests.swift` for absent metadata, legacy JSON decoding, successful message-owned metadata persistence, and removal with its conversation.
- [X] T008 Create focused request-scoped search outcome and HTTPS-only source validation in `Warden/Models/SearchModels.swift` without changing `MessageSearchMetadata` decoding compatibility.
- [X] T009 Update citation conversion and Tavily error mapping in `Warden/Utilities/TavilySearchService.swift` so raw service body, credentials, and private query content are never included in user errors or logs.
- [X] T010 Verify all changes to `Warden/Utilities/TavilyKeyManager.swift`, `Warden/Utilities/TavilySearchService.swift`, and `Warden/Models/Models.swift` keep keys in Keychain and exclude them from Core Data, UserDefaults, fixtures, diagnostics, and rendered content.

**Checkpoint**: Deterministic tests demonstrate the security/persistence contract before dependent chat behavior changes.

---

## Phase 3: User Story 1 — Search an AI Prompt (Priority: P1) 🎯 MVP

**Goal**: An explicitly enabled search augments only its matching provider request, shows lifecycle state, is cancellable, and safely preserves an unsent prompt on failure.

**Independent Test**: Use injected Tavily responses in `WardenTests/Utilities/MessageManagerSearchTests.swift` to prove successful search context reaches only one provider request, then manually/XCUITest verify progress and failure recovery in `Warden/UI/Chat/ChatView.swift`.

### Tests for User Story 1

- [X] T011 [P] [US1] Extend `WardenTests/Utilities/MessageManagerSearchTests.swift` with successful streaming and non-streaming request-scoped search context and source metadata assertions.
- [ ] T012 [P] [US1] Extend `WardenTests/Utilities/MessageManagerSearchTests.swift` with missing-key, unauthorized, rate-limit, invalid-response, network-failure, and cancellation terminal-state assertions.
- [X] T013 [P] [US1] Add first-enable disclosure and failed-search composer-recovery coverage in `WardenUITests/WebSearchFlowUITests.swift`, or document the exact accessibility/manual blocker in `specs/008-web-search-citations/quickstart.md`.

### Implementation for User Story 1

- [X] T014 [US1] Refactor `Warden/Utilities/MessageManager.swift` to keep each search query, formatted context, source list, and citation URLs scoped to the active matching send rather than mutable last-search state.
- [X] T015 [US1] Update both search send paths in `Warden/Utilities/MessageManager.swift` to inject context only after a successful search, skip provider invocation after failure, clear progress on terminal states, and ignore cancellation/late callbacks.
- [X] T016 [US1] Update assistant persistence in `Warden/Utilities/MessageManager.swift` and compatibility access in `Warden/Models/Models.swift` to attach query, sources, time, and result count only to the matching completed assistant message.
- [X] T017 [US1] Add a one-time first-enable Tavily disclosure and acknowledgement preference in `Warden/UI/Chat/BottomContainer/MessageInputView.swift` and `Warden/Configuration/AppConstants.swift`, including Continue, Preferences, and Cancel routes.
- [X] T018 [US1] Update `Warden/UI/Chat/ChatView.swift` and `Warden/UI/Chat/Components/SearchErrorView.swift` so retry keeps the original pending prompt, disable-search restores the unchanged prompt to the composer without auto-sending, and Settings routes to Web Search preferences.
- [X] T019 [US1] Update `Warden/UI/Chat/Components/SearchProgressView.swift` and `Warden/UI/Chat/ChatView.swift` with accessible lifecycle/cancellation state that dismisses after completion, failure, or cancellation.
- [ ] T020 [US1] Run focused search manager and UI tests for `WardenTests/Utilities/MessageManagerSearchTests.swift` and `WardenUITests/WebSearchFlowUITests.swift`; record actual results in `specs/008-web-search-citations/quickstart.md` only if its procedure changes.

**Checkpoint**: Search P1 works independently; failed search never sends automatically and existing non-search chat behavior remains intact.

---

## Phase 4: User Story 2 — Inspect Sources and Citations (Priority: P2)

**Goal**: A completed web-assisted assistant message retains readable sources and opens only matching HTTPS destinations through valid citations or source controls.

**Independent Test**: Canned metadata and response text in `WardenTests/Utilities/TavilySearchServiceTests.swift` prove deterministic same-message citation behavior; source UI verifies non-HTTPS URLs are readable but non-actionable.

### Tests for User Story 2

- [X] T021 [P] [US2] Add UI-safe source-action and accessibility assertions in `WardenTests/Utilities/TavilySearchServiceTests.swift` for HTTPS-only destination acceptance and plain-text fallbacks.
- [X] T022 [P] [US2] Add message metadata reload coverage in `WardenTests/Persistence/MessageSearchMetadataTests.swift` proving sources remain associated with their assistant message after persistence reload.

### Implementation for User Story 2

- [X] T023 [US2] Update `Warden/UI/Chat/Components/MessageSourcesView.swift` to render every source as text but add cursor/open action only for absolute HTTPS URLs with hosts.
- [X] T024 [US2] Update `Warden/UI/Chat/Components/CitationBadgeView.swift` and any citation-opening path to reuse the shared HTTPS validator and preserve unsupported URLs/citations as non-actionable text.
- [X] T025 [US2] Update `Warden/UI/Chat/BubbleView/ChatBubbleView.swift` source presentation with keyboard-accessible labels and expanded/collapsed state semantics.
- [X] T026 [US2] Run focused citation/source/persistence tests in `WardenTests/Utilities/TavilySearchServiceTests.swift` and `WardenTests/Persistence/MessageSearchMetadataTests.swift` and re-run `WardenTests/Utilities/MessageManagerSearchTests.swift`.

**Checkpoint**: Source data survives reload with the correct message, and only well-formed HTTPS URLs can be opened.

---

## Phase 5: User Story 3 — Configure and Validate Search (Priority: P3)

**Goal**: Users can understand and securely configure Tavily credentials/options, then test connection failures without sensitive diagnostics.

**Independent Test**: Injected session responses verify preference values and safe connection-error mapping without a live Tavily key in `WardenTests/Utilities/TavilySearchServiceTests.swift`.

- [ ] T027 [P] [US3] Add deterministic settings and connection-error mapping tests in `WardenTests/Utilities/TavilySearchServiceTests.swift` using `URLSession` injection and a test-only credential seam.
- [X] T028 [US3] Update secure settings save/load and connection-test error handling in `Warden/UI/Preferences/TabTavilySearchView.swift` and `Warden/Utilities/TavilyKeyManager.swift` without placing the credential in `UserDefaults`.
- [X] T029 [US3] Update explanatory and accessibility copy in `Warden/UI/Preferences/TabTavilySearchView.swift` to describe the current-query disclosure, per-request globe control, configured limits, and non-secret remediation.
- [X] T030 [US3] Run focused configuration tests in `WardenTests/Utilities/TavilySearchServiceTests.swift` and inspect changed preference/Keychain/log paths for secret or private-query leakage.

**Checkpoint**: Configuration is understandable, reloadable, deterministic to test, and keeps credentials solely in Keychain.

---

## Phase 6: Cross-Cutting Verification and Polish

- [X] T031 [P] Review `Warden/Utilities/TavilySearchService.swift`, `Warden/Utilities/MessageManager.swift`, and `Warden/UI/Preferences/TabTavilySearchView.swift` for privacy-safe `WardenLog` usage and remove raw service/prompt/error-body logging.
- [X] T032 [P] Review `Warden/UI/Chat/BottomContainer/MessageInputView.swift`, `Warden/UI/Chat/ChatView.swift`, `Warden/UI/Chat/Components/SearchErrorView.swift`, and `Warden/UI/Chat/Components/MessageSourcesView.swift` for keyboard, VoiceOver, focus, and terminal-state behavior.
- [ ] T033 Execute all manual scenarios in `specs/008-web-search-citations/quickstart.md`, including disclosure, failure/retry/disable, cancellation, source reload, and HTTPS-only actionability.
- [X] T034 Run the macOS build for `./Warden.xcodeproj` with scheme `Warden` and destination `platform=macOS`.
- [ ] T035 Run the complete Warden test suite for `./Warden.xcodeproj` with scheme `Warden` and destination `platform=macOS`.
- [ ] T036 Inspect `./.git` with `git diff --check` and `git status --short` to ensure no API key, private chat data, DerivedData, build output, or package checkout is staged for commit.
- [X] T037 Update final behavior and actual verification evidence in `specs/008-web-search-citations/quickstart.md` and `specs/008-web-search-citations/plan.md` if implementation changes the documented procedure.

## Dependencies and Execution Order

1. Phase 1 establishes the reproducible baseline.
2. Phase 2 shared validation, error, and persistence contracts must complete before P1 implementation.
3. User Story 1 is the MVP and blocks integration-dependent source persistence.
4. User Story 2 can proceed after P1 request-scoped metadata and shared validation are stable.
5. User Story 3 can proceed in parallel with P2 only after Phase 2, except for shared `TavilySearchService.swift` changes which must be serialized.
6. Final verification follows all stories.

## Parallel Opportunities

- T005, T006, and T007 write separate deterministic test files and can proceed in parallel.
- T011, T012, and T013 can proceed in parallel after the foundational test seams are agreed.
- T021 and T022 can proceed in parallel after P1 metadata behavior is stable.
- T027 can proceed in parallel with P2 test work after shared error contract changes are complete.
- Do not parallelize `Warden/Utilities/MessageManager.swift`, `Warden/Utilities/TavilySearchService.swift`, or overlapping `ChatView.swift` edits.

## Implementation Strategy

1. Deliver MVP User Story 1 first: safe, per-request search and reliable failure/cancellation recovery.
2. Add User Story 2 source/citation actions after message-owned metadata is correct.
3. Complete User Story 3 preferences and connection polish without weakening Keychain boundaries.
4. Finish with actual test/build/manual/privacy evidence, not assumed results.
