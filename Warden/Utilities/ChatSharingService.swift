import AppKit
import Foundation
import os

enum ChatExportFormat: String, CaseIterable {
    case plainText = "Plain Text"
    case markdown = "Markdown"
    case json = "JSON"

    var fileExtension: String {
        switch self {
        case .plainText: "txt"
        case .markdown: "md"
        case .json: "json"
        }
    }
}

struct ChatExportRepresentation: Equatable {
    let content: String
    let suggestedFilename: String
}

enum ChatSharingError: LocalizedError {
    case temporaryFileCreationFailed

    var errorDescription: String? {
        switch self {
        case .temporaryFileCreationFailed:
            "Warden could not prepare the export for sharing. Please try again."
        }
    }
}

@MainActor
final class ChatSharingService: NSObject {
    static let shared = ChatSharingService()

    private static let sharePickerExpiry: TimeInterval = 5 * 60

    private var activeShareDelegates: [UUID: TemporaryShareDelegate] = [:]
    private var activeShareCleanup: [UUID: DispatchWorkItem] = [:]

    private override init() {}

    /// Share a chat using the native macOS sharing service.
    func shareChat(_ chat: ChatEntity, format: ChatExportFormat = .markdown) {
        let representation = exportRepresentation(for: chat, format: format)

        do {
            let temporaryURL = try createTemporaryFile(for: representation, format: format)
            let picker = NSSharingServicePicker(items: [temporaryURL])
            let token = UUID()
            let delegate = TemporaryShareDelegate(fileURL: temporaryURL) { [weak self] in
                self?.completeShare(token: token)
            }
            activeShareDelegates[token] = delegate
            picker.delegate = delegate

            guard let window = NSApp.keyWindow, let contentView = window.contentView else {
                completeShare(token: token)
                presentUserSafeError("Warden could not open the share menu. Please try again.")
                return
            }

            scheduleShareExpiry(token: token)
            let rect = NSRect(x: window.frame.midX - 100, y: window.frame.midY, width: 200, height: 50)
            picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
        } catch {
            logSharingFailure("temporary file creation")
            presentUserSafeError(ChatSharingError.temporaryFileCreationFailed.localizedDescription)
        }
    }

    private func scheduleShareExpiry(token: UUID) {
        let cleanup = DispatchWorkItem { [weak self] in
            self?.completeShare(token: token)
        }
        activeShareCleanup[token] = cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.sharePickerExpiry, execute: cleanup)
    }

    private func completeShare(token: UUID) {
        activeShareCleanup.removeValue(forKey: token)?.cancel()
        activeShareDelegates.removeValue(forKey: token)?.removeTemporaryFile()
    }

    /// Return the exact user-selected representation without invoking AppKit UI.
    func shareChatAsText(_ chat: ChatEntity, format: ChatExportFormat = .markdown) -> String {
        exportRepresentation(for: chat, format: format).content
    }

    /// Copy a chat only after an explicit UI action.
    func copyChatToClipboard(_ chat: ChatEntity, format: ChatExportFormat = .markdown) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(shareChatAsText(chat, format: format), forType: .string) else {
            logSharingFailure("clipboard write")
            presentUserSafeError("Warden could not copy the export. Please try again.")
            return
        }
    }

    /// Export a chat through the native save panel.
    func exportChatToFile(_ chat: ChatEntity, format: ChatExportFormat = .markdown) {
        let representation = exportRepresentation(for: chat, format: format)
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = representation.suggestedFilename
        savePanel.allowedContentTypes = [.plainText, .data]
        savePanel.title = "Export Chat"
        savePanel.message = "Choose where to save the chat export"

        savePanel.begin { result in
            guard result == .OK, let url = savePanel.url else { return }

            do {
                try self.write(representation.content, to: url)
            } catch {
                self.logSharingFailure("export write")
                self.presentUserSafeError("Warden could not save the export. Check the destination and try again.")
            }
        }
    }

    func exportRepresentation(for chat: ChatEntity, format: ChatExportFormat) -> ChatExportRepresentation {
        let document = ChatExportDocument(chat: chat)
        let content: String

        switch format {
        case .plainText:
            content = document.plainText
        case .markdown:
            content = document.markdown
        case .json:
            content = document.json
        }

        return ChatExportRepresentation(
            content: content,
            suggestedFilename: suggestedFilename(for: chat.name, format: format)
        )
    }

    func suggestedFilename(for title: String, format: ChatExportFormat) -> String {
        let permitted = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let normalized = title.precomposedStringWithCanonicalMapping.unicodeScalars.map { scalar in
            permitted.contains(scalar) ? String(scalar) : "-"
        }.joined()
        let collapsed = normalized.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))
        let baseName = String((trimmed.isEmpty ? "Chat" : trimmed).prefix(80))
        return "\(baseName).\(format.fileExtension)"
    }

    func createTemporaryFile(
        for representation: ChatExportRepresentation,
        format: ChatExportFormat,
        in directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let extensionURL = URL(fileURLWithPath: representation.suggestedFilename)
        let baseName = extensionURL.deletingPathExtension().lastPathComponent
        let temporaryURL = directory.appendingPathComponent("\(baseName)-\(UUID().uuidString).\(format.fileExtension)")

        do {
            try write(representation.content, to: temporaryURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
            return temporaryURL
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    func write(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func logSharingFailure(_ operation: String) {
        WardenLog.app.error("Chat sharing \(operation, privacy: .public) failed")
    }

    private func presentUserSafeError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Export Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private struct ChatExportDocument: Encodable {
    struct Metadata: Encodable {
        let id: UUID
        let title: String
        let createdAt: Date
        let updatedAt: Date
        let model: String
        let persona: String?
        let project: String?
        let service: String?
    }

    struct Message: Encodable {
        let id: Int64
        let role: String
        let name: String
        let timestamp: Date?
        let body: String
    }

    let metadata: Metadata
    let systemMessage: String?
    let messages: [Message]

    init(chat: ChatEntity) {
        metadata = Metadata(
            id: chat.id,
            title: chat.name,
            createdAt: chat.createdDate,
            updatedAt: chat.updatedDate,
            model: chat.gptModel,
            persona: chat.persona?.name,
            project: chat.project?.name,
            service: chat.apiService?.name
        )
        systemMessage = chat.systemMessage.isEmpty ? nil : chat.systemMessage
        messages = chat.messagesArray
            .sorted {
                let lhs = $0.timestamp ?? .distantPast
                let rhs = $1.timestamp ?? .distantPast
                return lhs == rhs ? $0.id < $1.id : lhs < rhs
            }
            .map {
                Message(
                    id: $0.id,
                    role: $0.own ? "user" : "assistant",
                    name: $0.name,
                    timestamp: $0.timestamp,
                    body: $0.body
                )
            }
    }

    var plainText: String {
        var lines = [
            "Chat: \(metadata.title)",
            "ID: \(metadata.id.uuidString)",
            "Created: \(Self.timestamp(metadata.createdAt))",
            "Updated: \(Self.timestamp(metadata.updatedAt))",
            "Model: \(metadata.model)"
        ]
        if let persona = metadata.persona { lines.append("Persona: \(persona)") }
        if let project = metadata.project { lines.append("Project: \(project)") }
        if let service = metadata.service { lines.append("Service: \(service)") }
        if let systemMessage {
            lines += ["", "System Message:", systemMessage]
        }
        for message in messages {
            lines += ["", "[\(Self.timestamp(message.timestamp))] \(message.role == "user" ? "You" : "Assistant"):", message.body]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    var markdown: String {
        var lines = [
            "# \(metadata.title)",
            "",
            "**ID:** \(metadata.id.uuidString)  ",
            "**Created:** \(Self.timestamp(metadata.createdAt))  ",
            "**Updated:** \(Self.timestamp(metadata.updatedAt))  ",
            "**Model:** \(metadata.model)"
        ]
        if let persona = metadata.persona { lines.append("**Persona:** \(persona)") }
        if let project = metadata.project { lines.append("**Project:** \(project)") }
        if let service = metadata.service { lines.append("**Service:** \(service)") }
        if let systemMessage {
            lines += ["", "## System Message", "", systemMessage]
        }
        for message in messages {
            lines += ["", "## \(message.role == "user" ? "You" : "Assistant") — \(Self.timestamp(message.timestamp))", "", message.body]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    var json: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self), let value = String(data: data, encoding: .utf8) else {
            return "{}\n"
        }
        return value + "\n"
    }

    private static func timestamp(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return ISO8601DateFormatter().string(from: date)
    }
}

final class TemporaryShareDelegate: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    private let fileURL: URL
    private let completion: () -> Void
    private var hasFinished = false

    init(fileURL: URL, completion: @escaping () -> Void) {
        self.fileURL = fileURL
        self.completion = completion
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        delegateFor sharingService: NSSharingService
    ) -> NSSharingServiceDelegate? {
        self
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
    ) {
        if service == nil {
            finish()
        }
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        finish()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        finish()
    }

    func removeTemporaryFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        removeTemporaryFile()
        completion()
    }
}
