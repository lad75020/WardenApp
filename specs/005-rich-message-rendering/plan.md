# Implementation Plan: Rich Message Rendering

**Branch**: `feature/time-machine-rich-message-rendering` | **Date**: 2026-08-12 | **Spec**: [spec.md](spec.md)

## Summary
Harden WardenApp's existing transient message parsing and native SwiftUI/AppKit renderers so completed and streamed assistant responses display Markdown, code, tables, math, reasoning, and controlled HTML previews safely and responsively. No provider protocol, Core Data, or persistence change is needed.

## Technical Context

**Language/Version**: Swift 5.9  
**Primary Frameworks**: SwiftUI, AppKit, WebKit, existing Markdown/highlighting/math packages  
**Persistence**: No schema change; existing message text only  
**Testing**: XCTest plus focused manual macOS accessibility/preview verification  
**Target Platform**: Native macOS 26.0  
**Build Command**: `xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build`  
**Test Command**: `xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'`  
**Performance Goals**: Initial long-message display remains responsive; stale parsing is cancelled.  
**Constraints**: Privacy-first, local preview only, no telemetry, actor-safe UI state.  

## Constitution Check

- [x] Native macOS presentation and privacy-first behavior are preserved.
- [x] Changes stay in UI and focused parsing utilities; provider and store boundaries remain intact.
- [x] No secrets or message bodies are added to persistence or logs.
- [x] No Core Data schema or migration change is required.
- [x] Streaming/background parsing retains cancellation and actor-safe publication.
- [x] Focused deterministic tests and Xcode-native build/test verification are planned.
- [x] Existing frameworks and focused types are extended; no dependency is added.

## Architecture Impact

| Module | Path | Change |
|---|---|---|
| Parsing | `Warden/Utilities/MessageParser.swift` | Robust block detection/finalization and malformed-input fallback. |
| Native message UI | `Warden/UI/Chat/BubbleView/`, `Warden/UI/Components/MarkdownView.swift`, `StreamingAttributedTextView.swift` | Accessible structured rendering, long-content and streaming behavior. |
| Code/preview | `Warden/UI/Chat/CodeView/`, `HTMLPreviewView.swift` | Highlight/copy controls and isolated local preview. |
| Tests | `WardenTests/` | Parser, copy, streaming, long-content, and preview-isolation regressions. |

## Security and Privacy

No new network destination or persisted data is introduced. WebKit remains nonpersistent and blocks JavaScript, remote loading, navigation, forms, frames, and external file access. Logs must contain only non-sensitive diagnostic metadata.

## Delivery Phases

1. Add parser and transient rendering regressions for valid, malformed, streaming, and long input.
2. Implement parser/rendering corrections while preserving existing attachment and citation pathways.
3. Harden code/table/reasoning/preview controls and accessibility.
4. Run focused tests, XcodeMCP build/test, manual preview/accessibility checks, and full macOS build/test.

## Complexity Tracking

No constitution violation or new abstraction is required.
