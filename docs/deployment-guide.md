# Deployment guide

WardenApp is a native macOS application distributed from an Xcode project. This guide covers the repository-supported preparation path and identifies release actions that require local Apple signing and publishing decisions.

## Deployment scope

The project contains the `Warden` application target and an auxiliary `MLXZImageSwiftCLI` target. The main application is built from `Warden.xcodeproj` using the `Warden` scheme.

No complete deployment pipeline, notarization script, or CI/CD workflow was found in the current checkout. The steps below are therefore a release checklist rather than a claim that publishing is automated.

## Prepare a release candidate

1. Start from a clean working tree or record all deliberate changes.
2. Resolve local and remote Swift packages in Xcode.
3. Select the intended Apple Developer team and signing configuration.
4. Confirm the application target, bundle identifiers, entitlements, and macOS deployment target.
5. Build the Release configuration for the `Warden` scheme.
6. Run unit and UI tests on the intended macOS environment.
7. Exercise first launch, onboarding, provider setup, a local service, persistence recovery, export, and cancellation paths.
8. Inspect the built application for unexpected files, credentials, debug-only data, or development endpoints.
9. Archive, sign, and install the candidate on a clean test account or machine.

The repository does not define a single canonical signing identity or distribution profile, so those values must come from the release environment and must not be added to this documentation.

## Useful Xcode actions

The verified development build command is:

```bash
xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build
```

For a release build, select **Product > Archive** in Xcode after choosing the intended Release configuration and signing settings. Confirm the archive and signing result in Xcode Organizer before exporting.

An archive command can be used only after confirming the local signing configuration and archive destination. Do not copy signing-specific arguments from another machine into the repository without reviewing their security implications.

## Release verification

### Functional

- App launches without a provider credential.
- Onboarding and Preferences open correctly.
- A service can be created, tested, saved, selected, and deleted.
- A chat can send, stream, stop, retry, and persist.
- A missing service leaves its chat recoverable as unavailable.
- Attachments, search, citations, MCP, local models, multi-agent mode, and Quick Chat fail safely when their dependencies are absent.
- Backup/export and sharing are explicit and complete.

### Security

- The application remains sandboxed with only the intended entitlements.
- Remote credential-bearing endpoints use HTTPS.
- Credentials are in Keychain, not Core Data or UserDefaults.
- Release logs do not contain keys, prompts, response bodies, tool values, or attachment content.
- No development endpoint or local machine path is accidentally used as a hosted default.
- HTML preview remains isolated.

### Operational

- The target macOS version is supported by the chosen build.
- All package dependencies resolve deterministically for the release environment.
- The app can be installed and removed cleanly.
- The persistent store opens on a clean account.
- A migration from a representative previous data store is tested before distribution.
- The release artifact, archive, and exported installer are retained according to the project release policy.

## Distribution decisions not encoded in the repository

The following require an explicit release-owner decision and are intentionally not guessed here:

- Developer team and signing identity.
- Distribution channel.
- Notarization and stapling service.
- Minimum supported macOS version for the release.
- Update mechanism.
- Public provider support policy and current model catalog.
- Retention policy for user exports and crash reports.

Record these decisions in the project release process before publishing.

## Rollback and data safety

A new application build must not silently overwrite a user's valid persistent store. Before distributing a migration that changes Core Data:

- Keep a tested backup/export path.
- Exercise upgrade and rollback-adjacent scenarios with a copy of representative data.
- Test unavailable service and missing attachment behavior.
- Preserve a recovery path when the persistent store cannot be opened.

A release rollback does not restore a deleted provider credential or undo an explicit user export. Treat the data store and Keychain as separate recovery assets.
