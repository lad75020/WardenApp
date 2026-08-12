

import XCTest
import WebKit
import AppKit
import CoreData
import UniformTypeIdentifiers
@testable import Warden

class MessageParserTests: XCTestCase {

    var parser: MessageParser!

    override func setUp() {
        super.setUp()
        parser = MessageParser(colorScheme: .light)
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }


    /*
     Test generic message with table
     */
    func testParseMessageFromStringGeneric() {
        let input = """
        This is a sample text.

        Table: Test Table
        | Column 1 | Column 2 |
        | -------- | -------- |
        | Value 1  | Value 2  |
        | Value 3  | Value 4  |

        This is another sample text.
        """

        let result = parser.parseMessageFromString(input: input)
        XCTAssertEqual(result.count, 3)

        switch result[0] {
        case .text(let text):
            XCTAssertEqual(text, """
            This is a sample text.
            
            Table: Test Table
            """)
        default:
            XCTFail("Expected .text element")
        }

        switch result[1] {
        case .table(header: let header, data: let data):
            XCTAssertEqual(header, ["Column 1", "Column 2"])
            XCTAssertEqual(data, [["Value 1", "Value 2"], ["Value 3", "Value 4"]])
        default:
            XCTFail("Expected .table element")
        }

        switch result[2] {
        case .text(let text):
            XCTAssertEqual(text, "This is another sample text.")
        default:
            XCTFail("Expected .text element")
        }
    }
    
    /*
     Test incomplete message in response
     https://github.com/Renset/macai/issues/15
     */
    func testParseMessageFromStringGitHubIssue15() {
        let input = """
        Here's a FizzBuzz implementation in Shakespeare Programming Language:

        ```
        The Infamous FizzBuzz Program.
        By ChatGPT.

        Act 1: The Setup
        Scene 1: Initializing Variables.
        [Enter Romeo and Juliet]
        """
        
        let result = parser.parseMessageFromString(input: input)
        XCTAssertEqual(result.count, 2)

        switch result[0] {
        case .text(let text):
            XCTAssertEqual(text, "Here's a FizzBuzz implementation in Shakespeare Programming Language:\n")
        default:
            XCTFail("Expected .text element")
        }
        
        switch result[1] {
        case .code(code: let highlightedCode):
            XCTAssertEqual(String(highlightedCode.code), """
            The Infamous FizzBuzz Program.
            By ChatGPT.
            
            Act 1: The Setup
            Scene 1: Initializing Variables.
            [Enter Romeo and Juliet]
            """)
        default:
            XCTFail("Expected .code element")
        }
    }
    
    /*
     Test message with the mix of tables and code blocks
     */
    func testParseMessageFromStringTableAndCode() {
        let input = """
        Table: Test Table
        | Column 1 | Column 2 |
        | -------- | -------- |
        | Value 1  | Value 2  |
        | Value 3  | Value 4  |

        ```
        This is a code block
        ```

        **Table 2: Test Table
        | Column 1 | Column 2 |
        | -------- | -------- |
        | Value 1  | Value 2  |
        | Value 3  | Value 4  |
        
        **Table 3: Test Table
        | Column 1 | Column 2 |
        | -------- | -------- |
        | Value 1  | Value 2  |
        | Value 3  | Value 4  |
        
        Some random text. Bla-bla-bla...
        
        **Table 4: Test Table
        | Column 1 | Column 2 |
        | -------- | -------- |
        | Value 1  | Value 2  |
        | Value 3  | Value 4  |
        
        """

        let result = parser.parseMessageFromString(input: input)
        XCTAssertEqual(result.count, 11)

        switch result[1] {
        case .table(header: let header, data: let data):
            XCTAssertEqual(header, ["Column 1", "Column 2"])
            XCTAssertEqual(data, [["Value 1", "Value 2"], ["Value 3", "Value 4"]])
        default:
            XCTFail("Expected .table element")
        }

        switch result[3] {
        case .code(code: let highlightedCode):
            XCTAssertEqual(String(highlightedCode.code), """
            This is a code block
            """)
        default:
            XCTFail("Expected .code element")
        }

        switch result[5] {
        case .table(header: let header, data: let data):
            XCTAssertEqual(header, ["Column 1", "Column 2"])
            XCTAssertEqual(data, [["Value 1", "Value 2"], ["Value 3", "Value 4"]])
        default:
            XCTFail("Expected .table element")
        }
        
        switch result[7] {
        case .table(header: let header, data: let data):
            XCTAssertEqual(header, ["Column 1", "Column 2"])
            XCTAssertEqual(data, [["Value 1", "Value 2"], ["Value 3", "Value 4"]])
        default:
            XCTFail("Expected .table element")
        }
        
        switch result[8] {
        case .text(let text):
            XCTAssertEqual(text, """
            Some random text. Bla-bla-bla...

            **Table 4: Test Table
            """)
        default:
            XCTFail("Expected .text element")
        }
        
        switch result[9] {
        case .table(header: let header, data: let data):
            XCTAssertEqual(header, ["Column 1", "Column 2"])
            XCTAssertEqual(data, [["Value 1", "Value 2"], ["Value 3", "Value 4"]])
        default:
            XCTFail("Expected .table element")
        }
    }
    
    func testParseMessageFromStringMathEquation() {
        let input = """
        Sure, here’s a complex formula from the field of string theory, specifically the action for the bosonic string:

        \\[
        S = -\\frac{1}{4\\pi\\alpha'} \\int d\\tau \\, d\\sigma \\, \\sqrt{-h} \\left( h^{ab} \\partial_a X^\\mu \\partial_b X_\\mu + \\alpha' R^{(2)} \\Phi(X) \\right)
        \\]

        Where:
        - \\( S \\) is the action.
        - \\( \\alpha' \\) is the string tension parameter.
        - \\( \\tau \\) and \\( \\sigma \\) are the worldsheet coordinates.
        - \\( h \\) is the determinant of the worldsheet metric \\( h_{ab} \\).
        - \\( h^{ab} \\) is the inverse of the worldsheet metric.
        - \\( \\partial_a \\) denotes partial differentiation with respect to the worldsheet coordinates.
        - \\( X^\\mu \\) are the target space coordinates of the string.
        - \\( R^{(2)} \\) is the Ricci scalar of the worldsheet.
        - \\( \\Phi(X) \\) is the dilaton field.
        """

        let result = parser.parseMessageFromString(input: input)
        XCTAssertEqual(result.count, 3)
        
        switch result[0] {
        case .text(let text):
            XCTAssertEqual(text, """
            Sure, here’s a complex formula from the field of string theory, specifically the action for the bosonic string:

            """)
        default:
            XCTFail("Expected .text element")
        }
        
        switch result[1] {
        case .formula(let formula):
            XCTAssertEqual(formula, "S = -\\frac{1}{4\\pi\\alpha'} \\int d\\tau \\, d\\sigma \\, \\sqrt{-h} \\left( h^{ab} \\partial_a X^\\mu \\partial_b X_\\mu + \\alpha' R^{(2)} \\Phi(X) \\right)")
        default:
            XCTFail("Expected .formula element")
        }
        
        switch result[2] {
        case .text(let text):
            XCTAssertEqual(text, """
            Where:
            - \\( S \\) is the action.
            - \\( \\alpha' \\) is the string tension parameter.
            - \\( \\tau \\) and \\( \\sigma \\) are the worldsheet coordinates.
            - \\( h \\) is the determinant of the worldsheet metric \\( h_{ab} \\).
            - \\( h^{ab} \\) is the inverse of the worldsheet metric.
            - \\( \\partial_a \\) denotes partial differentiation with respect to the worldsheet coordinates.
            - \\( X^\\mu \\) are the target space coordinates of the string.
            - \\( R^{(2)} \\) is the Ricci scalar of the worldsheet.
            - \\( \\Phi(X) \\) is the dilaton field.
            """)
        default:
            XCTFail("Expected .text element")
        }
        
    }

    func testKeepsStructuralLookingLinesInsideCodeFenceAsCode() {
        let input = """
        ```swift
        | this is not a table |
        \\[
        <think> this is not reasoning
        ```
        """

        let result = parser.parseMessageFromString(input: input)

        XCTAssertEqual(result.count, 1)
        guard case .code(let code, let language, _) = result[0] else {
            return XCTFail("Expected one code element")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "| this is not a table |\n\\[\n<think> this is not reasoning")
    }

    func testPreservesHeaderOnlyTableRatherThanDroppingIt() {
        let input = """
        | First | Second |
        | --- | --- |
        """

        let result = parser.parseMessageFromString(input: input)

        XCTAssertEqual(result.count, 1)
        guard case .table(let header, let data) = result[0] else {
            return XCTFail("Expected a table element")
        }
        XCTAssertEqual(header, ["First", "Second"])
        XCTAssertEqual(data, [])
    }

    func testFallsBackToReadableTextForEmptyUnclosedCodeFence() {
        let input = "```swift"

        let result = parser.parseMessageFromString(input: input)

        XCTAssertEqual(result.count, 1)
        guard case .text(let text) = result[0] else {
            return XCTFail("Expected readable text fallback")
        }
        XCTAssertEqual(text, input)
    }

    func testPreservesSourceOrderForMarkdownTableMathAndReasoning() {
        let input = """
        # Heading
        | Name | Value |
        | --- | --- |
        | A | 1 |
        \\[
        x^2
        \\]
        <think>Because it is deterministic.</think>
        """

        let result = parser.parseMessageFromString(input: input)

        XCTAssertEqual(result.count, 4)
        guard case .text = result[0], case .table = result[1], case .formula = result[2], case .thinking = result[3] else {
            return XCTFail("Expected text, table, formula, and reasoning in source order")
        }
    }

    func testUnclosedFormulaAndReasoningRemainAvailable() {
        let input = """
        \\[
        x + y
        \\]
        <think>
        unfinished reasoning
        """

        let result = parser.parseMessageFromString(input: input)

        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains { element in
            if case .formula(let value) = element { return value.contains("x + y") }
            return false
        })
        XCTAssertTrue(result.contains { element in
            if case .thinking(let value, _) = element { return value.contains("unfinished reasoning") }
            return false
        })
    }

    func testLargePlainTextRetainsReadablePrefixAndAttachmentsAreExempt() {
        let source = String(repeating: "a", count: AppConstants.largeMessageSymbolsThreshold + 1)
        XCTAssertEqual(String(source.prefix(AppConstants.largeMessageSymbolsThreshold)).count, AppConstants.largeMessageSymbolsThreshold)
        XCTAssertFalse(source.containsAttachment)
        XCTAssertTrue("<image-uuid>00000000-0000-0000-0000-000000000000</image-uuid>".containsAttachment)
    }

    func testStaleParseSessionCannotReplaceNewerMessage() {
        XCTAssertTrue(MessageParseSession.isCurrent(expectedSource: "new", currentSource: "new"))
        XCTAssertFalse(MessageParseSession.isCurrent(expectedSource: "old", currentSource: "new"))
    }

    func testTableSerializationHandlesUnevenRowsAndEmptyCells() throws {
        let header = ["Name", "Value"]
        let rows = [["A"], ["", "2", "ignored"]]

        XCTAssertEqual(TableSerialization.tabSeparated(header: header, rows: rows), "Name\tValue\nA\n\t2\tignored")
        let data = try TableSerialization.jsonData(header: header, rows: rows)
        let objects = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: String]])
        XCTAssertEqual(objects, [["Name": "A", "Value": ""], ["Name": "", "Value": "2"]])
    }

    func testHTMLPreviewSecurityAlwaysInjectsRestrictivePolicyAndBlocksURLs() {
        let document = HTMLPreviewSecurity.securedHTMLDocument(
            "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src *\"><script>window.x = 1</script>"
        )

        XCTAssertTrue(document.contains(HTMLPreviewSecurity.contentSecurityPolicy))
        XCTAssertTrue(document.contains("script-src 'none'"))
        XCTAssertTrue(HTMLPreviewSecurity.allowsNavigation(url: nil, navigationType: .other))
        XCTAssertFalse(HTMLPreviewSecurity.allowsNavigation(url: URL(string: "https://example.com"), navigationType: .linkActivated))
        XCTAssertFalse(HTMLPreviewSecurity.allowsNavigation(url: URL(fileURLWithPath: "/private/secret"), navigationType: .other))
    }

    func testIncrementalParserFinalizesChunkedCodeWithoutInterpretingInteriorBlocks() {
        let incremental = IncrementalMessageParser(colorScheme: .light)
        incremental.appendChunk("```swift\n| not a table |\n")
        incremental.appendChunk("<think>not reasoning\n```")
        let result = incremental.finalize()

        XCTAssertEqual(result.count, 1)
        guard case .code(let code, let language, _) = result[0] else {
            return XCTFail("Expected a code block")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "| not a table |\n<think>not reasoning")
    }

    func testParsesVideoMarkerAndKeepsMalformedMarkerAsText() {
        let valid = "<video-url>file:///tmp/generated-video.mp4</video-url>"
        let validElements = parser.parseMessageFromString(input: valid)
        XCTAssertEqual(validElements.count, 1)
        guard case .videoURL(let url) = validElements[0] else {
            return XCTFail("Expected a video URL element")
        }
        XCTAssertEqual(url, "file:///tmp/generated-video.mp4")

        let malformed = "<video-url>file:///tmp/generated-video.mp4"
        let malformedElements = parser.parseMessageFromString(input: malformed)
        XCTAssertEqual(malformedElements.count, 1)
        guard case .text(let text) = malformedElements[0] else {
            return XCTFail("Expected malformed marker to remain readable text")
        }
        XCTAssertEqual(text, malformed)
    }

    func testIncrementalParserRecognizesVideoMarkerAcrossStreamingBoundary() {
        let incremental = IncrementalMessageParser(colorScheme: .light)
        incremental.appendChunk("Before\n<video-")
        incremental.appendChunk("url>file:///tmp/generated-video.mp4</video-url>")

        let result = incremental.finalize()
        XCTAssertEqual(result.count, 2)
        guard case .text(let text) = result[0] else {
            return XCTFail("Expected leading text")
        }
        XCTAssertEqual(text, "Before")
        guard case .videoURL(let url) = result[1] else {
            return XCTFail("Expected streamed video URL")
        }
        XCTAssertEqual(url, "file:///tmp/generated-video.mp4")
    }

    func testVideoAttachmentSupportRejectsRemoteMissingAndExistingDestinations() throws {
        XCTAssertFalse(VideoAttachmentSupport.isUsableLocalVideo(URL(string: "https://example.com/video.mp4")!))
        XCTAssertFalse(VideoAttachmentSupport.isUsableLocalVideo(URL(fileURLWithPath: "/tmp/warden-missing-video.mp4")))

        let source = FileManager.default.temporaryDirectory.appendingPathComponent("warden-video-\(UUID().uuidString).mp4")
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("warden-video-copy-\(UUID().uuidString).mp4")
        try Data([0x00]).write(to: source)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }

        XCTAssertTrue(VideoAttachmentSupport.isUsableLocalVideo(source))
        XCTAssertTrue(VideoAttachmentSupport.shouldDisplayPlayer(playerExists: true, videoURL: source))
        XCTAssertNil(VideoAttachmentSupport.exportError(source: source, destination: destination))
        XCTAssertNotNil(VideoAttachmentSupport.exportError(source: source, destination: source))

        try Data([0x01]).write(to: destination)
        XCTAssertNotNil(VideoAttachmentSupport.exportError(source: source, destination: destination))

        try FileManager.default.removeItem(at: source)
        XCTAssertFalse(VideoAttachmentSupport.shouldDisplayPlayer(playerExists: true, videoURL: source))
    }

    @MainActor
    func testAttachmentReadinessRequiresSuccessfulPreparation() {
        let image = ImageAttachment(image: NSImage(size: NSSize(width: 1, height: 1)))
        XCTAssertTrue(image.isReadyForSend)
        image.error = NSError(domain: "AttachmentTests", code: 1)
        XCTAssertFalse(image.isReadyForSend)

        let file = FileAttachment(
            id: UUID(),
            fileName: "notes.txt",
            fileSize: 1,
            fileTypeExtension: "txt",
            textContent: "x",
            imageData: nil,
            thumbnailData: nil
        )
        XCTAssertTrue(file.isReadyForSend)
        file.isLoading = true
        XCTAssertFalse(file.isReadyForSend)
    }

    @MainActor
    func testPersistedFileExportReconstructsStoredImageAndTextRepresentations() throws {
        let image = try XCTUnwrap(makeFixtureImage())
        let imageData = try XCTUnwrap(ImageExportFormat.png.data(for: image))
        let imageFile = FileAttachment(
            id: UUID(),
            fileName: "diagram.jpg",
            fileSize: Int64(imageData.count),
            fileTypeExtension: "jpg",
            textContent: "not used for images",
            imageData: imageData,
            thumbnailData: nil
        )
        let imageExport = try XCTUnwrap(imageFile.exportRepresentation)
        XCTAssertEqual(imageExport.data, imageData)
        XCTAssertEqual(imageExport.suggestedFileName, "diagram.png")
        XCTAssertEqual(imageExport.contentType, .png)

        let textFile = FileAttachment(
            id: UUID(),
            fileName: "",
            fileSize: 5,
            fileTypeExtension: "json",
            textContent: "{\"ok\":true}",
            imageData: nil,
            thumbnailData: nil
        )
        let textExport = try XCTUnwrap(textFile.exportRepresentation)
        XCTAssertEqual(String(data: textExport.data, encoding: .utf8), "{\"ok\":true}")
        XCTAssertEqual(textExport.suggestedFileName, "attachment.json")

        let unknownTextFile = FileAttachment(
            id: UUID(),
            fileName: "README.custom",
            fileSize: 5,
            fileTypeExtension: "custom",
            textContent: "plain text",
            imageData: nil,
            thumbnailData: nil
        )
        XCTAssertEqual(unknownTextFile.exportRepresentation?.suggestedFileName, "README.txt")

        let binaryPlaceholder = FileAttachment(
            id: UUID(),
            fileName: "archive.bin",
            fileSize: 5,
            fileTypeExtension: "bin",
            textContent: "[Binary file: archive.bin]",
            imageData: nil,
            thumbnailData: nil
        )
        XCTAssertNil(binaryPlaceholder.exportRepresentation)

        let pdfExtract = FileAttachment(
            id: UUID(),
            fileName: "report.pdf",
            fileSize: 1,
            fileTypeExtension: "pdf",
            textContent: "Extracted text",
            imageData: nil,
            thumbnailData: nil
        )
        XCTAssertEqual(pdfExtract.exportRepresentation?.suggestedFileName, "report.txt")
    }

    @MainActor
    func testPersistedCorruptImageIsUnavailableAndCannotExportAsGenericFile() {
        let corruptImage = FileAttachment(
            id: UUID(),
            fileName: "broken.png",
            fileSize: 2,
            fileTypeExtension: "png",
            textContent: "not a fallback",
            imageData: Data([0x00, 0x01]),
            thumbnailData: nil
        )

        XCTAssertTrue(corruptImage.hasUnavailablePersistedImage)
        XCTAssertNil(corruptImage.exportRepresentation)
        XCTAssertFalse(corruptImage.isReadyForSend)
    }

    @MainActor
    func testImageExportFormatFollowsDestinationExtension() throws {
        let image = try XCTUnwrap(makeFixtureImage())
        let pngData = try XCTUnwrap(ImageExportFormat.forDestination(URL(fileURLWithPath: "/tmp/image.png")).data(for: image))
        let jpegData = try XCTUnwrap(ImageExportFormat.forDestination(URL(fileURLWithPath: "/tmp/image.jpeg")).data(for: image))

        XCTAssertEqual(Array(pngData.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(Array(jpegData.prefix(3)), [255, 216, 255])
        XCTAssertEqual(ImageExportFormat.forDestination(URL(fileURLWithPath: "/tmp/image.jpg")), .jpeg)
        XCTAssertEqual(ImageExportFormat.forDestination(URL(fileURLWithPath: "/tmp/image.png")), .png)
    }

    @MainActor
    func testAttachmentResolverLoadsPersistedImageAndFileAndTreatsUnknownIDsAsUnavailable() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let imageID = UUID()
        let fileID = UUID()

        let imageAttachment = ImageAttachment(image: try XCTUnwrap(makeFixtureImage()), id: imageID)
        XCTAssertTrue(imageAttachment.saveToEntity(context: context))

        let fileAttachment = FileAttachment(
            id: fileID,
            fileName: "notes.txt",
            fileSize: 5,
            fileTypeExtension: "txt",
            textContent: "hello",
            imageData: nil,
            thumbnailData: nil
        )
        XCTAssertTrue(fileAttachment.saveToEntity(context: context))

        let resolver = AttachmentResolver(dataLoader: BackgroundDataLoader(persistenceController: persistence))
        let resolvedImage = await resolver.image(for: imageID)
        XCTAssertNotNil(resolvedImage)

        let resolvedFile = await resolver.fileAttachment(for: fileID)
        XCTAssertEqual(resolvedFile?.fileName, "notes.txt")
        XCTAssertEqual(resolvedFile?.textContent, "hello")
        let missingImage = await resolver.image(for: UUID())
        let missingFile = await resolver.fileAttachment(for: UUID())
        XCTAssertNil(missingImage)
        XCTAssertNil(missingFile)
    }

    @MainActor
    private func makeFixtureImage() -> NSImage? {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 2, height: 2)).fill()
        image.unlockFocus()
        return image
    }
}

@MainActor
final class PersonasModelSelectionRegressionTests: XCTestCase {
    func testModelIdentityRoundTripRetainsOpaqueProviderAndModelValues() throws {
        let identity = ModelSelectionIdentity(
            provider: "open:router",
            modelID: "vendor:model/with:separators"
        )

        let encoded = try JSONEncoder().encode([identity])
        let decoded = try JSONDecoder().decode([ModelSelectionIdentity].self, from: encoded)

        XCTAssertEqual(decoded, [identity])
    }

    func testLegacyFavoriteMigrationKeepsModelSeparators() throws {
        let legacy = try JSONEncoder().encode(["openrouter:vendor:model/with:separators"])

        XCTAssertEqual(
            FavoriteModelsManager.decodeFavorites(from: legacy),
            [ModelSelectionIdentity(provider: "openrouter", modelID: "vendor:model/with:separators")]
        )
    }

    func testSelectionPolicyRejectsUnconfiguredOrInvisibleModels() {
        let configured = ModelSelectionIdentity(provider: "chatgpt", modelID: "gpt-4o")
        let hidden = ModelSelectionIdentity(provider: "chatgpt", modelID: "gpt-4o-mini")

        XCTAssertTrue(
            ModelSelectionPolicy.isSelectable(
                configured,
                configuredProviders: ["chatgpt"],
                visibleModels: [configured]
            )
        )
        XCTAssertFalse(
            ModelSelectionPolicy.isSelectable(
                hidden,
                configuredProviders: ["chatgpt"],
                visibleModels: [configured]
            )
        )
        XCTAssertFalse(
            ModelSelectionPolicy.isSelectable(
                configured,
                configuredProviders: ["claude"],
                visibleModels: [configured]
            )
        )
    }
}

final class MessageParserSSEStreamParserTests: XCTestCase {
    func testParsesSingleSSEDataLineWithoutTrailingNewline() async throws {
        let input = "data: {\"a\":1}"
        let data = Data(input.utf8)

        var events: [String] = []
        try await SSEStreamParser.parse(data: data) { payload in
            events.append(payload)
        }

        XCTAssertEqual(events, ["{\"a\":1}"])
    }

    func testParsesDoneWithoutTrailingNewline() async throws {
        let input = "data: [DONE]"
        let data = Data(input.utf8)

        var events: [String] = []
        try await SSEStreamParser.parse(data: data) { payload in
            events.append(payload)
        }

        XCTAssertEqual(events, ["[DONE]"])
    }

    func testParsesLastEventWhenFinalNewlineMissing() async throws {
        let first = "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}"
        let second = "data: [DONE]"
        let input = "\(first)\n\n\(second)"
        let data = Data(input.utf8)

        var events: [String] = []
        try await SSEStreamParser.parse(data: data) { payload in
            events.append(payload)
        }

        XCTAssertEqual(events, ["{\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}", "[DONE]"])
    }
}
