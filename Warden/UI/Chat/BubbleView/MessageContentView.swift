import Foundation
import AttributedText
import SwiftUI
import os

struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: NSImage
}
struct MessageContentView: View {
    let message: String
    let isStreaming: Bool
    let own: Bool
    let effectiveFontSize: Double
    let colorScheme: ColorScheme

    @State private var showFullMessage = false
    @State private var isParsingFullMessage = false
    @State private var selectedImage: IdentifiableImage?
    @State private var resolvedImages: [UUID: NSImage] = [:]
    @State private var resolvedFiles: [UUID: FileAttachment] = [:]
    @State private var missingImages: Set<UUID> = []
    @State private var missingFiles: Set<UUID> = []

    @State private var truncatedParsedElements: [MessageElements]
    @State private var fullParsedElements: [MessageElements]
    @State private var lastTruncatedMessage: String
    @State private var fullParseTask: Task<Void, Never>?
    @State private var truncatedParseTask: Task<Void, Never>?
    
    // Incremental parsing state
    @State private var incrementalParser: IncrementalMessageParser?
    @State private var lastProcessedLength: Int = 0

    private let largeMessageSymbolsThreshold = AppConstants.largeMessageSymbolsThreshold

    init(message: String, isStreaming: Bool, own: Bool, effectiveFontSize: Double, colorScheme: ColorScheme) {
        self.message = message
        self.isStreaming = isStreaming
        self.own = own
        self.effectiveFontSize = effectiveFontSize
        self.colorScheme = colorScheme

        let shouldRenderPartial = message.count > AppConstants.largeMessageSymbolsThreshold && !message.containsAttachment
        if shouldRenderPartial {
            let truncated = String(message.prefix(AppConstants.largeMessageSymbolsThreshold))
            let parser = MessageParser(colorScheme: colorScheme)
            _truncatedParsedElements = State(initialValue: parser.parseMessageFromString(input: truncated))
            _fullParsedElements = State(initialValue: [])
            _lastTruncatedMessage = State(initialValue: truncated)
        } else {
            let parser = MessageParser(colorScheme: colorScheme)
            _truncatedParsedElements = State(initialValue: [])
            _fullParsedElements = State(initialValue: parser.parseMessageFromString(input: message))
            _lastTruncatedMessage = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            // Check if message contains image data or JSON with image_url before applying truncation
            if message.count > largeMessageSymbolsThreshold && !showFullMessage && !containsImageData(message) {
                renderPartialContent()
            }
            else {
                renderFullContent()
            }
        }
        .animation(nil, value: message)
        .onChange(of: message) { _ in
            refreshParsedElements()
        }
        .onChange(of: isStreaming) { _, newValue in
            guard !newValue else { return }
            // Streaming ended - reset incremental parser and do final full parse
            incrementalParser = nil
            lastProcessedLength = 0
            truncatedParseTask?.cancel()
            fullParseTask?.cancel()
            refreshParsedElements(force: true)
        }
        .onChange(of: colorScheme) { _ in
            refreshParsedElements(force: true)
        }
    }

    private func containsImageData(_ message: String) -> Bool {
        // Existing attachment markers
        if message.containsAttachment { return true }
        
        // Inline image URL tags produced by parsers/handlers
        if message.contains("<image-url>") { return true }
        
        // Data URL scheme for images
        if message.contains("data:image/") { return true }
        
        // Quick heuristic for embedded base64 image blobs (PNG/JPEG/GIF/BMP)
        // These prefixes are distinctive and help us avoid truncating messages that contain images
        let magicPrefixes = ["iVBORw0KGgo", "/9j/", "R0lGOD", "Qk"]
        if magicPrefixes.contains(where: { message.contains($0) }) {
            return true
        }
        
        return false
    }

    @ViewBuilder
    private func renderPartialContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(truncatedParsedElements.indices, id: \.self) { index in
                renderElement(truncatedParsedElements[index])
            }

            HStack(spacing: 8) {
                Button(action: {
                    isParsingFullMessage = true
                    // Parse the full message in background: very long messages may take long time to parse (and even cause app crash)
                    fullParseTask?.cancel()
                    fullParseTask = Task.detached(priority: .userInitiated) {
                        let parser = MessageParser(colorScheme: colorScheme)
                        let elements = parser.parseMessageFromString(input: message)
                        await MainActor.run {
                            fullParsedElements = elements
                            showFullMessage = true
                            isParsingFullMessage = false
                        }
                    }
                }) {
                    Text("Show Full Message")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(16)
                }
                .buttonStyle(PlainButtonStyle())

                if isParsingFullMessage {
                    ProgressView()
                        .scaleEffect(0.4)
                        .frame(width: 12, height: 12)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func renderFullContent() -> some View {
        ForEach(fullParsedElements.indices, id: \.self) { index in
            renderElement(fullParsedElements[index])
        }
    }

    private func refreshParsedElements(force: Bool = false) {
        let shouldRenderPartial = message.count > largeMessageSymbolsThreshold && !showFullMessage && !containsImageData(message)

        if shouldRenderPartial {
            let truncated = String(message.prefix(largeMessageSymbolsThreshold))
            guard force || truncated != lastTruncatedMessage else { return }
            lastTruncatedMessage = truncated

            truncatedParseTask?.cancel()
            if isStreaming {
                truncatedParseTask = Task.detached(priority: .userInitiated) {
                    let parser = MessageParser(colorScheme: colorScheme)
                    #if DEBUG
                    let signpostID = OSSignpostID(log: WardenSignpost.rendering)
                    os_signpost(
                        .begin,
                        log: WardenSignpost.rendering,
                        name: "MessageParse",
                        signpostID: signpostID,
                        "mode=%{public}s chars=%{public}d",
                        "truncated",
                        truncated.count
                    )
                    #endif
                    let elements = parser.parseMessageFromString(input: truncated)
                    #if DEBUG
                    os_signpost(.end, log: WardenSignpost.rendering, name: "MessageParse", signpostID: signpostID)
                    #endif
                    await MainActor.run {
                        truncatedParsedElements = elements
                    }
                }
            } else {
                let parser = MessageParser(colorScheme: colorScheme)
                truncatedParsedElements = parser.parseMessageFromString(input: truncated)
            }
            return
        }

        truncatedParseTask?.cancel()

        if isStreaming {
            // Use incremental parsing if enabled
            if AppConstants.useIncrementalParsing {
                refreshWithIncrementalParser()
            } else {
                refreshWithFullParser()
            }
        } else {
            let parser = MessageParser(colorScheme: colorScheme)
            fullParsedElements = parser.parseMessageFromString(input: message)
        }
    }
    
    /// Incremental parsing - only process new content
    private func refreshWithIncrementalParser() {
        // Initialize parser if needed
        if incrementalParser == nil {
            incrementalParser = IncrementalMessageParser(colorScheme: colorScheme)
            lastProcessedLength = 0
        }
        
        guard let parser = incrementalParser else { return }
        
        // Only process new content
        if message.count > lastProcessedLength {
            let newContent = String(message.dropFirst(lastProcessedLength))
            parser.appendChunk(newContent)
            lastProcessedLength = message.count
        }
        
        // Get all elements including pending
        fullParsedElements = parser.getAllElements()
    }
    
    /// Full re-parsing (original behavior)
    private func refreshWithFullParser() {
        fullParseTask?.cancel()
        fullParseTask = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return }
            let parser = MessageParser(colorScheme: colorScheme)
            #if DEBUG
            let signpostID = OSSignpostID(log: WardenSignpost.rendering)
            os_signpost(
                .begin,
                log: WardenSignpost.rendering,
                name: "MessageParse",
                signpostID: signpostID,
                "mode=%{public}s chars=%{public}d",
                "stream",
                message.count
            )
            #endif
            let elements = parser.parseMessageFromString(input: message)
            #if DEBUG
            os_signpost(.end, log: WardenSignpost.rendering, name: "MessageParse", signpostID: signpostID)
            #endif
            await MainActor.run {
                fullParsedElements = elements
            }
        }
    }
    
    @ViewBuilder
    private func renderElement(_ element: MessageElements) -> some View {
        switch element {
        case .thinking(let content, _):
            ThinkingProcessView(content: content)
                .padding(.vertical, 4)

        case .text(let text):
            renderText(text)

        case .table(let header, let data):
            TableView(header: header, tableData: data)
                .padding()

        case .code(let code, let lang, let indent):
            renderCode(code: code, lang: lang, indent: indent, isStreaming: isStreaming)

        case .formula(let formula):
            if isStreaming {
                Text(formula).textSelection(.enabled)
            }
            else {
                AdaptiveMathView(equation: formula, fontSize: NSFont.systemFontSize + CGFloat(2))
                    .padding(.vertical, 16)
            }

        case .image(let imageUUID):
            renderImageAttachment(uuid: imageUUID)
            
        case .imageURL(let urlString):
            renderRemoteImage(urlString: urlString)

        case .file(let fileUUID):
            renderFileAttachmentReference(uuid: fileUUID)
        }
    }

    @ViewBuilder
    private func renderImageAttachment(uuid: UUID) -> some View {
        if let image = resolvedImages[uuid] {
            renderImage(image)
        } else if missingImages.contains(uuid) {
            Text("\(MessageContent.imageTagStart)\(uuid.uuidString)\(MessageContent.imageTagEnd)")
                .textSelection(.enabled)
        } else {
            ProgressView()
                .scaleEffect(0.8)
                .frame(width: 24, height: 24)
                .padding(.bottom, 3)
                .task(id: uuid) {
                    let image = await AttachmentResolver.shared.image(for: uuid)
                    if let image {
                        resolvedImages[uuid] = image
                    } else {
                        missingImages.insert(uuid)
                    }
                }
        }
    }
    
    @ViewBuilder
    private func renderRemoteImage(urlString: String) -> some View {
        // 1) Try to decode as a bare base64 image (possibly surrounded by other text)
        if let base64Image = decodeBase64Image(from: urlString) {
            renderImage(base64Image)
        }
        // 2) Handle data URLs (e.g., data:image/png;base64,....) directly
        else if urlString.hasPrefix("data:") {
            if let commaIndex = urlString.firstIndex(of: ",") {
                let base64Part = String(urlString[urlString.index(after: commaIndex)...])
                if let data = Data(base64Encoded: base64Part, options: [.ignoreUnknownCharacters]),
                   let nsImage = NSImage(data: data) {
                    renderImage(nsImage)
                } else {
                    Text(urlString)
                        .textSelection(.enabled)
                }
            } else {
                Text(urlString)
                    .textSelection(.enabled)
            }
        }
        // 3) Try as a normal URL
        else if let url = URL(string: urlString) {
            ZStack {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 24, height: 24)
                    .padding(.bottom, 3)
                
                if let data = try? Data(contentsOf: url), let nsImage = NSImage(data: data) {
                    renderImage(nsImage)
                }
            }
            .task(id: urlString) {
                if let data = try? Data(contentsOf: url), let nsImage = NSImage(data: data) {
                    var hasher = Hasher()
                    hasher.combine(urlString)
                    let hash = hasher.finalize()
                    let uuidBytes = withUnsafeBytes(of: hash.bigEndian) { Data($0) }
                    let padded = uuidBytes + Data(repeating: 0, count: max(0, 16 - uuidBytes.count))
                    let uuid = padded.withUnsafeBytes { ptr -> UUID in
                        let bytes = ptr.bindMemory(to: UInt8.self)
                        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
                    }
                    resolvedImages[uuid] = nsImage
                }
            }
        }
        // 4) Fallback to showing raw text
        else {
            Text(urlString)
                .textSelection(.enabled)
        }
    }
    
    // Attempts to extract and decode a base64-encoded image from an arbitrary string.
    // It tolerates surrounding noise like progress logs (e.g., "Generating: step 9/9...") and looks for a long base64-looking run.
    private func decodeBase64Image(from text: String) -> NSImage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // Helper to strip everything except base64 characters (tolerate whitespace that may be interspersed)
        func cleanedBase64(_ s: String) -> String {
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
            return String(s.unicodeScalars.filter { allowed.contains($0) })
        }
        
        func normalizePadding(_ s: String) -> String {
            let length = s.count
            let remainder = length % 4
            if remainder == 0 { return s }
            if remainder == 1 { return s } // invalid length; don't attempt to pad
            let padCount = 4 - remainder
            return s + String(repeating: "=", count: padCount)
        }
        
        // 0) Try to detect known base64 magic prefixes inside noisy text and decode from there
        // PNG: iVBORw0KGgo, JPEG: /9j/, GIF: R0lGOD, BMP: Qk
        let magicPrefixes = ["iVBORw0KGgo", "/9j/", "R0lGOD", "Qk"]
        if let startIndex = magicPrefixes.compactMap({ prefix in trimmed.range(of: prefix) }).map({ $0.lowerBound }).min() {
            let candidateRaw = String(trimmed[startIndex...])
            let candidate = normalizePadding(cleanedBase64(candidateRaw))
            if let data = Data(base64Encoded: candidate, options: [.ignoreUnknownCharacters]),
               let image = NSImage(data: data) {
                return image
            }
        }
        
        // 1) If the whole string is likely base64 (after cleaning), try decoding directly first.
        let wholeCleaned = normalizePadding(cleanedBase64(trimmed))
        if wholeCleaned.count >= 100, isLikelyBase64(wholeCleaned),
           let data = Data(base64Encoded: wholeCleaned, options: [.ignoreUnknownCharacters]),
           let image = NSImage(data: data) {
            return image
        }
        
        // 2) Otherwise, search for the longest base64-looking chunk within the text.
        // Lowered threshold to 256 to work better with streaming outputs; allow whitespace within the run.
        let pattern = "[A-Za-z0-9+/=\\s]{256,}"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            let matches = regex.matches(in: trimmed, options: [], range: nsRange)
            // Try the longest match first
            let sorted = matches.sorted { $0.range.length > $1.range.length }
            for match in sorted {
                if let range = Range(match.range, in: trimmed) {
                    let candidateRaw = String(trimmed[range])
                    let candidate = normalizePadding(cleanedBase64(candidateRaw))
                    if let data = Data(base64Encoded: candidate, options: [.ignoreUnknownCharacters]),
                       let image = NSImage(data: data) {
                        return image
                    }
                }
            }
        }
        
        #if DEBUG
        WardenLog.rendering.debug("decodeBase64Image: no decodable image found (length=\(trimmed.count, privacy: .public))")
        #endif
        
        return nil
    }
    
    // Heuristic check that a string contains only base64 characters and reasonable padding
    private func isLikelyBase64(_ s: String) -> Bool {
        // Allow whitespace/newlines in the input; remove them for validation
        let whitespace = CharacterSet.whitespacesAndNewlines
        let compact = String(s.unicodeScalars.filter { !whitespace.contains($0) })
        
        // Fast pre-check: allowed base64 chars only (after removing whitespace)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        if compact.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return false
        }
        
        // Length should be a multiple of 4 (or close, with padding)
        return compact.count % 4 == 0 || compact.hasSuffix("=") || compact.hasSuffix("==")
    }

    @ViewBuilder
    private func renderFileAttachmentReference(uuid: UUID) -> some View {
        if let attachment = resolvedFiles[uuid] {
            renderFileAttachment(attachment)
        } else if missingFiles.contains(uuid) {
            Text("\(MessageContent.fileTagStart)\(uuid.uuidString)\(MessageContent.fileTagEnd)")
                .textSelection(.enabled)
        } else {
            ProgressView()
                .scaleEffect(0.8)
                .frame(width: 24, height: 24)
                .padding(.bottom, 3)
                .task(id: uuid) {
                    let attachment = await AttachmentResolver.shared.fileAttachment(for: uuid)
                    if let attachment {
                        resolvedFiles[uuid] = attachment
                    } else {
                        missingFiles.insert(uuid)
                    }
                }
        }
    }

    @ViewBuilder
    private func renderText(_ text: String) -> some View {
        // Detect and render bare base64 image blobs that may be embedded in plain text
        if let base64Image = decodeBase64Image(from: text) {
            renderImage(base64Image)
        } else {
            let hasMarkdown = containsMarkdownFormatting(text, useCache: !isStreaming)
            #if DEBUG
            let _ = WardenLog.rendering.debug(
                "renderText hasMarkdown=\(hasMarkdown, privacy: .public), length=\(text.count, privacy: .public)"
            )
            #endif

            if hasMarkdown {
                MarkdownView(
                    markdownText: text,
                    effectiveFontSize: effectiveFontSize,
                    own: own,
                    colorScheme: colorScheme
                )
            } else {
                // Fallback to the original method for simple text
                let attributedString: NSAttributedString = {
                    let options = AttributedString.MarkdownParsingOptions(
                        interpretedSyntax: .inlineOnlyPreservingWhitespace
                    )
                    let initialAttributedString =
                        (try? NSAttributedString(markdown: text, options: options))
                        ?? NSAttributedString(string: text)

                    let mutableAttributedString = NSMutableAttributedString(
                        attributedString: initialAttributedString
                    )
                    let fullRange = NSRange(location: 0, length: mutableAttributedString.length)
                    let systemFont = NSFont.systemFont(ofSize: effectiveFontSize)

                    mutableAttributedString.addAttribute(.font, value: systemFont, range: fullRange)
                    mutableAttributedString.addAttribute(
                        .foregroundColor,
                        value: own ? NSColor.white : NSColor.textColor,
                        range: fullRange
                    )
                    return mutableAttributedString
                }()

                if isStreaming {
                    StreamingAttributedTextView(attributedString: attributedString)
                } else if text.count > AppConstants.longStringCount {
                    AttributedText(attributedString)
                        .textSelection(.enabled)
                } else {
                    Text(.init(attributedString))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func containsMarkdownFormatting(_ text: String, useCache: Bool) -> Bool {
        if useCache, let cached = Self.markdownDetectionCache.object(forKey: text as NSString) {
            return cached.boolValue
        }

        // Don't use MarkdownView if MessageParser should handle these
        if text.contains("```") || // Code blocks - handled by MessageParser
           text.contains("<think>") || // Thinking blocks - handled by MessageParser
           text.contains(MessageContent.imageTagStart) || // Images - handled by MessageParser
           text.contains(MessageContent.fileTagStart) || // Files - handled by MessageParser
           text.contains("\\[") || text.contains("\\]") || // LaTeX - handled by MessageParser
           text.first == "|" { // Tables - handled by MessageParser
            if useCache {
                Self.markdownDetectionCache.setObject(NSNumber(value: false), forKey: text as NSString, cost: text.count)
            }
            return false
        }
        
        // Cheap pre-filter to avoid regex work for plain text.
        if !text.contains("#"),
           !text.contains("*"),
           !text.contains("_"),
           !text.contains("~"),
           !text.contains(">"),
           !text.contains("-"),
           !text.contains("`"),
           !text.contains("["),
           !text.contains("]") {
            if useCache {
                Self.markdownDetectionCache.setObject(NSNumber(value: false), forKey: text as NSString, cost: text.count)
            }
            return false
        }

        var result = false
        if let regex = Self.blockMarkdownRegex {
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, options: [], range: range) != nil {
                result = true
            }
        }
        if !result, let regex = Self.linkMarkdownRegex {
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, options: [], range: range) != nil {
                result = true
            }
        }
        
        // Also check for inline formatting that suggests structured content
        if !result,
           (text.contains("**") || text.contains("__") || // Bold
            text.contains("~~")) { // Strikethrough
            result = true
        }
        
        // Be more selective with asterisks and underscores to avoid false positives
        // Only consider it markdown if there are pairs of them
        if !result,
           (hasAtLeastTwoOccurrences(of: "*", in: text) ||
            hasAtLeastTwoOccurrences(of: "_", in: text) ||
            hasAtLeastTwoOccurrences(of: "`", in: text)) {
            result = true
        }

        if useCache {
            Self.markdownDetectionCache.setObject(NSNumber(value: result), forKey: text as NSString, cost: text.count)
        }
        return result
    }

    private static let blockMarkdownRegex: NSRegularExpression? = {
        let pattern = "^#{1,6}\\s+|^\\s*[*+-]\\s+|^\\s*\\d+\\.\\s+|^\\s*>\\s+|^\\s*(---|\\*\\*\\*)\\s*$"
        return try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }()

    private static let linkMarkdownRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\[.*?\\]\\(.*?\\)", options: [])
    }()

    private static let markdownDetectionCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 512
        cache.totalCostLimit = 250_000
        return cache
    }()

    private func hasAtLeastTwoOccurrences(of needle: Character, in text: String) -> Bool {
        var count = 0
        for character in text {
            if character == needle {
                count += 1
                if count >= 2 {
                    return true
                }
            }
        }
        return false
    }

    @ViewBuilder
    private func renderCode(code: String, lang: String, indent: Int, isStreaming: Bool) -> some View {
        CodeView(code: code, lang: lang, isStreaming: isStreaming)
            .padding(.bottom, 8)
            .padding(.leading, CGFloat(indent) * 4)
            .onAppear {
                NotificationCenter.default.post(name: NSNotification.Name("CodeBlockRendered"), object: nil)
            }
    }

    @ViewBuilder
    private func renderImage(_ image: NSImage) -> some View {
        let maxWidth: CGFloat = 300
        let aspectRatio = image.size.width / image.size.height
        let displayHeight = maxWidth / aspectRatio

        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: maxWidth, maxHeight: displayHeight)
            .cornerRadius(8)
            .padding(.bottom, 3)
            .onTapGesture {
                selectedImage = IdentifiableImage(image: image)
            }
            .sheet(item: $selectedImage) { identifiableImage in
                ZoomableImageView(image: identifiableImage.image, imageAspectRatio: aspectRatio)

            }
    }

    @ViewBuilder
    private func renderFileAttachment(_ fileAttachment: FileAttachment) -> some View {
        HStack(spacing: 12) {
            // File icon/thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(fileAttachment.fileType.color.opacity(0.1))
                    .frame(width: 60, height: 60)
                
                if let thumbnail = fileAttachment.thumbnail {
                    // Show thumbnail for files that have one (images, PDFs)
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipped()
                        .cornerRadius(6)
                } else {
                    // Show file type icon
                    Image(systemName: fileAttachment.fileType.icon)
                        .foregroundColor(fileAttachment.fileType.color)
                        .font(.title2)
                }
            }
            
            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(fileAttachment.fileName)
                    .font(.system(size: effectiveFontSize, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                if fileAttachment.fileSize > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: fileAttachment.fileSize, countStyle: .file))
                        .font(.system(size: effectiveFontSize - 2))
                        .foregroundColor(.secondary)
                }
                
                // Show file type
                Text(fileAttachment.fileType.displayName)
                    .font(.system(size: effectiveFontSize - 2))
                    .foregroundColor(fileAttachment.fileType.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(fileAttachment.fileType.color.opacity(0.1))
                    .cornerRadius(4)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
        .frame(maxWidth: 300)
        .padding(.bottom, 4)
    }

}
