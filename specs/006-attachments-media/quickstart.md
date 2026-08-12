# Quickstart: Verify Attachments and Media

## Automated checks

1. Run focused parser tests:
   ```bash
   xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/MessageParserTests
   ```
2. Run focused attachment/resolver/export tests added by the implementation.
3. Build the macOS app:
   ```bash
   xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build
   ```
4. Run the complete test suite before merge:
   ```bash
   xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'
   ```

## Manual macOS workflow

1. Open a conversation and attach a fixture image, text file, PDF, and unsupported binary file.
2. Confirm each preview exposes loading, ready, and error states appropriately; remove one item before sending.
3. Send a ready fixture attachment, quit/relaunch, and reopen the conversation. Confirm image/file history still renders.
4. Open an image from history; test zoom, pan, reset, keyboard controls, close, and Save As. Cancel a save panel and confirm no change.
5. Use a local video fixture or simulated Veo result; play inline, Reveal in Finder, and Save As to a new destination.
6. Remove or make a video source unreadable, then reopen the message. Confirm an unavailable state without a crash.
7. Inspect logs/error UI to confirm no keys, authorization headers, or private attachment content appear.
