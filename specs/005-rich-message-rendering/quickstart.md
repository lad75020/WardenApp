# Verification Quickstart

1. Run parser-focused deterministic tests covering Markdown text, fenced code, pipe tables, display math, `<think>` blocks, malformed delimiters, and large text.
2. Run focused rendering/view-model tests for code copy, table copy/JSON serialization, streaming updates, and cancellation/stale update behavior.
3. Manually inspect light and dark appearance, keyboard access, VoiceOver labels, long-message loading, and HTML preview controls.
4. Verify HTML preview cannot execute script, navigate externally, connect to the network, retain website data, or access files.
5. Build with XcodeMCP, then run the relevant Xcode test target and the repository macOS build/test commands before merge.
