# WardenApp documentation

This directory contains the technical, functional, operational, and end-user documentation for WardenApp.

The documents are written against the current checkout. The feature specifications under `../specs/` remain the normative product requirements; this directory explains the implemented behavior and provides a usable documentation entry point.

## Start here

- [Getting started](getting-started.md) - build or launch the app and complete the first setup.
- [User guide](user-guide.md) - use chats, projects, models, attachments, search, MCP, and Quick Chat.
- [Troubleshooting](troubleshooting.md) - diagnose the common local, provider, persistence, and integration failures.

## Functional reference

- [Functional requirements](functional-requirements.md) - consolidated index of the twelve feature specifications.
- [Feature reference](feature-reference.md) - current behavior, limits, implementation entry points, and source traceability.

## Technical reference

- [Architecture](architecture.md) - application layers and runtime data flows.
- [Data and persistence](data-and-persistence.md) - Core Data, migrations, recovery, Keychain, and local settings.
- [Provider reference](provider-reference.md) - supported provider types and the internal provider abstraction.
- [Configuration reference](configuration-reference.md) - user preferences, application constants, MCP, search, and sandbox settings.
- [Developer guide](developer-guide.md) - repository layout, build, test, extension points, and coding conventions.
- [Security and privacy](security-and-privacy.md) - storage, transport, logging, sandbox, and privacy boundaries.
- [Testing and release](testing-and-release.md) - verified build/test commands and release checks.
- [Deployment guide](deployment-guide.md) - signing and distribution guidance, including current automation gaps.

## Source of truth

Use the following order when sources disagree:

1. Current implementation and tests in `Warden/`, `WardenTests/`, and `WardenUITests/`.
2. The Core Data model at `Warden/Store/wardenDataModel.xcdatamodeld/`.
3. The feature specifications under `specs/`.
4. Existing project guidance such as `AGENTS.md`, `CLAUDE.md`, `README.md`, and `Setup.MD`.
5. This documentation set, which should be updated when the implementation changes.

Important examples:

- `AGENTS.md` states that no formatter configuration is currently versioned. The documentation therefore describes the established style rather than claiming an automated formatting gate.
- The current `TokenManager` source uses the Keychain service `fr.dubertrand.WardenAI`. The setup guide is aligned with this current identifier; older installations may still contain legacy Keychain items.
- No standalone public HTTP contract files were found. The provider documentation describes the internal Swift `APIService` protocol and provider behavior without inventing a public API surface.

## Scope

WardenApp is a native SwiftUI macOS application. It supports hosted and local AI services, persistent local chat history, rich message content, attachments, web search, MCP tools, multi-agent comparison, and a floating Quick Chat panel.

This set documents the application in the repository. It does not claim that every upstream provider feature, external service capability, release channel, or deployment pipeline is supported unless the behavior is present in the code or documented by the project.

## Evidence and maintenance

- [Evidence packet](evidence.md) records the repository facts used to write these documents and the remaining evidence gaps.
- Paths in this directory are repository-relative so they can be checked in code review.
- Credentials, authorization headers, prompts, and private conversation content must never be added to documentation or examples.
- After code changes, rerun the documentation checks and refresh the codebase-memory index as described in [Testing and release](testing-and-release.md).
