import Foundation
import SwiftUI

struct MessageParser {
    let colorScheme: ColorScheme

    enum BlockType {
        case text
        case table
        case codeBlock
        case formulaBlock
        case formulaLine
        case thinking
        case imageUUID
        case imageURL
        case fileUUID
        case videoURL
    }

    func detectBlockType(line: String) -> BlockType {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        if trimmedLine.hasPrefix("<think>") {
            return .thinking
        }
        else if trimmedLine.hasPrefix("```") {
            return .codeBlock
        }
        else if trimmedLine.first == "|" {
            return .table
        }
        else if trimmedLine.hasPrefix("\\[") {
            return trimmedLine.replacingOccurrences(of: " ", with: "") == "\\[" ? .formulaBlock : .formulaLine
        }
        else if trimmedLine.hasPrefix("\\]") {
            return .formulaLine
        }
        else if trimmedLine.hasPrefix("<image-uuid>") {
            return .imageUUID
        }
        else if trimmedLine.hasPrefix("<image-url>") {
            return .imageURL
        }
        else if trimmedLine.hasPrefix("<video-url>") {
            return .videoURL
        }
        else if trimmedLine.hasPrefix("<file-uuid>") {
            return .fileUUID
        }
        else {
            return .text
        }
    }

    func parseMessageFromString(input: String) -> [MessageElements] {

        let lines = input.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        var elements: [MessageElements] = []
        var currentHeader: [String] = []
        var currentTableData: [[String]] = []
        var textLines: [String] = []
        var codeLines: [String] = []
        var formulaLines: [String] = []
        var firstTableRowProcessed = false
        var isCodeBlockOpened = false
        var isFormulaBlockOpened = false
        var codeBlockLanguage = ""
        var codeOpeningLine = ""
        var leadingSpaces = 0

        func toggleCodeBlock(line: String) {
            if isCodeBlockOpened {
                appendCodeBlockIfNeeded()
                isCodeBlockOpened = false
                codeBlockLanguage = ""
                codeOpeningLine = ""
                leadingSpaces = 0
            }
            else {
                codeOpeningLine = line
                codeBlockLanguage = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "```", with: "")
                isCodeBlockOpened = true
            }
        }

        func openFormulaBlock() {
            isFormulaBlockOpened = true
        }

        func closeFormulaBlock() {
            isFormulaBlockOpened = false
        }

        func handleFormulaLine(line: String) {
            let formulaString = line.replacingOccurrences(of: "\\[", with: "").replacingOccurrences(of: "\\]", with: "")
            formulaLines.append(formulaString)
        }

        func appendFormulaLines() {
            guard !formulaLines.isEmpty else { return }
            let combinedLines = formulaLines.joined(separator: "\n")
            elements.append(.formula(combinedLines))
            formulaLines = []
        }

        func handleTableLine(line: String) {

            combineTextLinesIfNeeded()

            let rowData = parseRowData(line: line)

            if rowDataIsTableDelimiter(rowData: rowData) {
                return
            }

            if !firstTableRowProcessed {
                handleFirstRowData(rowData: rowData)
            }
            else {
                handleSubsequentRowData(rowData: rowData)
            }
        }

        func rowDataIsTableDelimiter(rowData: [String]) -> Bool {
            !rowData.isEmpty && rowData.allSatisfy { cell in
                !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" }
            }
        }

        func parseRowData(line: String) -> [String] {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            var cells = trimmedLine.split(separator: "|", omittingEmptySubsequences: false)
            if trimmedLine.hasPrefix("|") { cells.removeFirst() }
            if trimmedLine.hasSuffix("|") { cells.removeLast() }
            return cells.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        func handleFirstRowData(rowData: [String]) {
            currentHeader = rowData
            firstTableRowProcessed = true
        }

        func handleSubsequentRowData(rowData: [String]) {
            currentTableData.append(rowData)
        }

        func combineTextLinesIfNeeded() {
            if !textLines.isEmpty {
                let combinedText = textLines.reduce("") { (result, line) -> String in
                    if result.isEmpty {
                        return line
                    }
                    else {
                        return result + "\n" + line
                    }
                }
                elements.append(.text(combinedText))
                textLines = []
            }
        }

        func appendTableIfNeeded() {
            if !currentHeader.isEmpty {
                appendTable()
            }
        }

        func appendTable() {
            elements.append(.table(header: currentHeader, data: currentTableData))
            currentHeader = []
            currentTableData = []
            firstTableRowProcessed = false
        }

        func appendCodeBlockIfNeeded(unclosed: Bool = false) {
            if !codeLines.isEmpty {
                let combinedCode = codeLines.joined(separator: "\n")
                elements.append(.code(code: combinedCode, lang: codeBlockLanguage, indent: leadingSpaces))
                codeLines = []
            } else if unclosed, !codeOpeningLine.isEmpty {
                elements.append(.text(codeOpeningLine))
            }
        }

        func extractImageUUID(_ line: String) -> UUID? {
            let pattern = "<image-uuid>(.*?)</image-uuid>"
            if let range = line.range(of: pattern, options: .regularExpression) {
                let uuidString = String(line[range])
                    .replacingOccurrences(of: "<image-uuid>", with: "")
                    .replacingOccurrences(of: "</image-uuid>", with: "")
                return UUID(uuidString: uuidString)
            }
            return nil
        }

        func extractImageURL(_ line: String) -> String? {
            let pattern = "<image-url>(.*?)</image-url>"
            if let range = line.range(of: pattern, options: .regularExpression) {
                let urlString = String(line[range])
                    .replacingOccurrences(of: "<image-url>", with: "")
                    .replacingOccurrences(of: "</image-url>", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return urlString.isEmpty ? nil : urlString
            }
            return nil
        }

        func extractFileUUID(_ line: String) -> UUID? {
            let pattern = "<file-uuid>(.*?)</file-uuid>"
            if let range = line.range(of: pattern, options: .regularExpression) {
                let uuidString = String(line[range])
                    .replacingOccurrences(of: "<file-uuid>", with: "")
                    .replacingOccurrences(of: "</file-uuid>", with: "")
                return UUID(uuidString: uuidString)
            }
            return nil
        }

        func extractVideoURL(_ line: String) -> String? {
            let pattern = "<video-url>(.*?)</video-url>"
            if let range = line.range(of: pattern, options: .regularExpression) {
                let urlString = String(line[range])
                    .replacingOccurrences(of: "<video-url>", with: "")
                    .replacingOccurrences(of: "</video-url>", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return urlString.isEmpty ? nil : urlString
            }
            return nil
        }

        var thinkingLines: [String] = []
        var isThinkingBlockOpened = false

        func appendThinkingBlockIfNeeded() {
            if !thinkingLines.isEmpty {
                let combinedThinking = thinkingLines.joined(separator: "\n")
                    .replacingOccurrences(of: "<think>", with: "")
                    .replacingOccurrences(of: "</think>", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                elements.append(.thinking(combinedThinking, isExpanded: false))
                thinkingLines = []
            }
        }

        func finalizeParsing() {
            combineTextLinesIfNeeded()
            appendCodeBlockIfNeeded(unclosed: isCodeBlockOpened)
            appendTableIfNeeded()
            appendThinkingBlockIfNeeded()
        }

        for line in lines {
            // Once a fenced block has started, every line except its closing fence
            // is source code. Do this before general block detection so table,
            // math, attachment, and reasoning-looking lines cannot escape it.
            if isCodeBlockOpened && line.trimmingCharacters(in: .whitespaces).hasPrefix("```") == false {
                if leadingSpaces > 0 {
                    codeLines.append(String(line.dropFirst(min(leadingSpaces, line.count))))
                } else {
                    codeLines.append(line)
                }
                continue
            }

            // Display math and reasoning also own their interior lines while
            // streaming. This prevents delimiter-like text from reordering
            // elements or being lost before a closing delimiter arrives.
            if isFormulaBlockOpened {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("\\]") {
                    closeFormulaBlock()
                    appendFormulaLines()
                } else {
                    handleFormulaLine(line: line)
                }
                continue
            }

            if isThinkingBlockOpened {
                if line.contains("</think>") {
                    let lastLine = line.replacingOccurrences(of: "</think>", with: "")
                    if !lastLine.isEmpty {
                        thinkingLines.append(lastLine)
                    }
                    isThinkingBlockOpened = false
                    appendThinkingBlockIfNeeded()
                } else {
                    thinkingLines.append(line)
                }
                continue
            }

            let blockType = detectBlockType(line: line)

            switch blockType {

            case .codeBlock:
                leadingSpaces = line.count - line.trimmingCharacters(in: .whitespaces).count
                combineTextLinesIfNeeded()
                appendTableIfNeeded()
                toggleCodeBlock(line: line)

            case .table:
                handleTableLine(line: line)

            case .formulaBlock:
                combineTextLinesIfNeeded()
                appendTableIfNeeded()
                openFormulaBlock()

            case .formulaLine:
                combineTextLinesIfNeeded()
                appendTableIfNeeded()
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("\\]") {
                    closeFormulaBlock()
                    appendFormulaLines()
                }
                else {
                    handleFormulaLine(line: line)
                    if !isFormulaBlockOpened {
                        appendFormulaLines()
                    }
                }

            case .thinking:
                if line.contains("</think>") {
                    let thinking =
                        line
                        .replacingOccurrences(of: "<think>", with: "")
                        .replacingOccurrences(of: "</think>", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    elements.append(.thinking(thinking, isExpanded: false))
                }
                else if line.contains("<think>") {
                    combineTextLinesIfNeeded()
                    appendTableIfNeeded()
                    isThinkingBlockOpened = true
                    let firstLine = line.replacingOccurrences(of: "<think>", with: "")
                    if !firstLine.isEmpty {
                        thinkingLines.append(firstLine)
                    }
                }

            case .imageUUID:
                if let uuid = extractImageUUID(line) {
                    combineTextLinesIfNeeded()
                    elements.append(.image(uuid))
                }
                else {
                    textLines.append(line)
                }

            case .imageURL:
                if let url = extractImageURL(line) {
                    combineTextLinesIfNeeded()
                    elements.append(.imageURL(url))
                } else {
                    textLines.append(line)
                }

            case .fileUUID:
                if let uuid = extractFileUUID(line) {
                    combineTextLinesIfNeeded()
                    elements.append(.file(uuid))
                }
                else {
                    textLines.append(line)
                }

            case .videoURL:
                if let url = extractVideoURL(line) {
                    combineTextLinesIfNeeded()
                    elements.append(.videoURL(url))
                } else {
                    textLines.append(line)
                }

            case .text:
                if isThinkingBlockOpened {
                    if line.contains("</think>") {
                        let lastLine = line.replacingOccurrences(of: "</think>", with: "")
                        if !lastLine.isEmpty {
                            thinkingLines.append(lastLine)
                        }
                        isThinkingBlockOpened = false
                        appendThinkingBlockIfNeeded()
                    }
                    else {
                        thinkingLines.append(line)
                    }
                }
                else if isCodeBlockOpened {
                    if leadingSpaces > 0 {
                        codeLines.append(String(line.dropFirst(leadingSpaces)))
                    }
                    else {
                        codeLines.append(line)
                    }
                }
                else if isFormulaBlockOpened {
                    handleFormulaLine(line: line)
                }
                else {
                    if !currentTableData.isEmpty {
                        appendTable()
                    }
                    textLines.append(line)
                }
            }
        }

        finalizeParsing()
        return elements
    }
}
