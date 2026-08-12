

import XCTest
import WebKit
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
