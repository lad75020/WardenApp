import CoreData
import Combine
import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import os

enum FileAttachmentType {
    case image
    case text
    case csv
    case pdf
    case json
    case xml
    case markdown
    case rtf
    case other(String)
}

/// A safe representation reconstructed from the data Warden stores for a file attachment.
/// It is intentionally not presented as the original file when that original is unavailable.
struct FileAttachmentExportRepresentation {
    let data: Data
    let suggestedFileName: String
    let contentType: UTType
    let description: String
}

@MainActor
final class FileAttachment: Identifiable, ObservableObject {
    var id: UUID = UUID()
    var url: URL?
    @Published var fileName: String = ""
    @Published var fileSize: Int64 = 0
    @Published var fileType: FileAttachmentType = .other("")
    @Published var textContent: String = ""
    @Published var isLoading: Bool = false
    @Published var error: Error?
    @Published var thumbnail: NSImage?
    
    @Published var image: NSImage?

    /// True only for a persisted attachment declared as an image whose stored payload cannot be decoded.
    /// Such an attachment cannot safely fall back to its text preview.
    private(set) var hasUnavailablePersistedImage = false

    /// File preparation is complete once its type-specific content is available without an error.
    var isReadyForSend: Bool {
        guard !isLoading, error == nil else { return false }
        if case .image = fileType {
            return image != nil
        }
        return true
    }
    
    private var managedObjectContext: NSManagedObjectContext?
    private var fileEntityID: NSManagedObjectID?
    private var loadTask: Task<Void, Never>?
    private var persistedImageData: Data?
    private(set) var originalUTType: UTType
    
    init(url: URL, context: NSManagedObjectContext? = nil) {
        self.url = url
        self.fileName = url.lastPathComponent
        self.originalUTType = url.getUTType() ?? .data
        self.managedObjectContext = context
        self.fileType = self.determineFileType(from: url.pathExtension)
        startLoadingFromURL()
    }
    
    init(fileEntity: FileEntity) {
        self.fileEntityID = fileEntity.objectID
        self.id = fileEntity.id ?? UUID()
        self.fileName = fileEntity.fileName ?? "Unknown"
        self.fileSize = fileEntity.fileSize
        self.textContent = fileEntity.textContent ?? ""
        self.managedObjectContext = fileEntity.managedObjectContext
        
        if let typeString = fileEntity.fileType {
            self.originalUTType = UTType(filenameExtension: typeString) ?? .data
            self.fileType = self.determineFileType(from: typeString)
        } else {
            self.originalUTType = .data
            self.fileType = .other("")
        }
        
        startLoadingFromEntity()
    }

    init(
        id: UUID,
        fileName: String,
        fileSize: Int64,
        fileTypeExtension: String,
        textContent: String,
        imageData: Data?,
        thumbnailData: Data?
    ) {
        self.id = id
        self.url = nil
        self.fileName = fileName
        self.fileSize = fileSize
        self.textContent = textContent
        self.originalUTType = UTType(filenameExtension: fileTypeExtension) ?? .data
        self.fileType = self.determineFileType(from: fileTypeExtension)

        if case .image = self.fileType {
            if let imageData, let image = NSImage(data: imageData) {
                self.image = image
                self.persistedImageData = imageData
            } else {
                self.hasUnavailablePersistedImage = true
            }
        }
        if let thumbnailData, let thumbnail = NSImage(data: thumbnailData) {
            self.thumbnail = thumbnail
        }

        self.isLoading = false
    }

    /// Returns the faithful stored image payload when available, or a UTF-8 text reconstruction for
    /// formats whose persisted value is text. This never claims to restore bytes Warden did not retain.
    var exportRepresentation: FileAttachmentExportRepresentation? {
        switch fileType {
        case .image:
            guard let imageData = persistedImageData,
                  NSImage(data: imageData) != nil,
                  let imageType = Self.imageType(for: imageData) else {
                return nil
            }
            return FileAttachmentExportRepresentation(
                data: imageData,
                suggestedFileName: Self.exportFileName(fileName, extension: imageType.preferredFilenameExtension ?? "jpg"),
                contentType: imageType,
                description: "stored image representation"
            )

        case .text, .csv, .json, .xml, .markdown:
            let fileExtension = Self.textExtension(for: fileType)
            return FileAttachmentExportRepresentation(
                data: Data(textContent.utf8),
                suggestedFileName: Self.exportFileName(fileName, extension: fileExtension),
                contentType: UTType(filenameExtension: fileExtension) ?? .plainText,
                description: "stored text representation"
            )

        case .pdf, .rtf:
            return FileAttachmentExportRepresentation(
                data: Data(textContent.utf8),
                suggestedFileName: Self.exportFileName(fileName, extension: "txt"),
                contentType: .plainText,
                description: "stored text extraction"
            )

        case .other:
            guard !textContent.isEmpty, textContent != "[Binary file: \(fileName)]" else {
                return nil
            }
            return FileAttachmentExportRepresentation(
                data: Data(textContent.utf8),
                suggestedFileName: Self.exportFileName(fileName, extension: "txt"),
                contentType: .plainText,
                description: "stored text representation"
            )
        }
    }
    
    deinit {
        loadTask?.cancel()
    }

    private func determineFileType(from `extension`: String) -> FileAttachmentType {
        let ext = `extension`.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "heif", "webp": return .image
        case "txt", "log": return .text
        case "csv": return .csv
        case "pdf": return .pdf
        case "json": return .json
        case "xml", "html", "htm": return .xml
        case "md", "markdown": return .markdown
        case "rtf": return .rtf
        default: return .other(ext)
        }
    }
    
    private func startLoadingFromURL() {
        loadTask?.cancel()
        isLoading = true
        error = nil
        
        let url = url
        let fileType = fileType
        let fileName = fileName

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                guard let url else {
                    throw NSError(
                        domain: "FileAttachment",
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Missing file URL"]
                    )
                }

                let size = try await Task.detached(priority: .userInitiated) {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    return attributes[.size] as? Int64 ?? 0
                }.value

                try Task.checkCancellation()
                self.fileSize = size

                switch fileType {
                case .image:
                    try await loadImageFile(from: url)
                case .text, .csv, .json, .xml, .markdown:
                    try await loadTextFile(from: url)
                case .pdf:
                    try await loadPDFFile(from: url)
                case .rtf:
                    try await loadRTFFile(from: url)
                case .other:
                    await loadGenericFile(from: url, fileName: fileName)
                }
            } catch {
                if Task.isCancelled { return }
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    private func loadImageFile(from url: URL) async throws {
        let image = try await Task.detached(priority: .userInitiated) {
            guard let image = NSImage(contentsOf: url) else {
                throw NSError(
                    domain: "FileAttachment",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load image"]
                )
            }
            return image
        }.value

        try Task.checkCancellation()
        createThumbnail(from: image)
        self.image = image
        self.isLoading = false
        saveToEntity()
    }
    
    private func loadTextFile(from url: URL) async throws {
        let content = try await Task.detached(priority: .userInitiated) {
            try String(contentsOf: url, encoding: .utf8)
        }.value

        try Task.checkCancellation()
        self.textContent = content
        self.isLoading = false
        saveToEntity()
    }
    
    private func loadPDFFile(from url: URL) async throws {
        let result = try await Task.detached(priority: .userInitiated) {
            guard let pdfDocument = PDFDocument(url: url) else {
                throw NSError(
                    domain: "FileAttachment",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load PDF"]
                )
            }

            var fullText = ""
            fullText.reserveCapacity(8_000)

            for pageIndex in 0..<pdfDocument.pageCount {
                try Task.checkCancellation()
                if let page = pdfDocument.page(at: pageIndex) {
                    fullText += page.string ?? ""
                    fullText += "\n\n"
                }
            }

            let firstPage = pdfDocument.page(at: 0)
            return (fullText, firstPage)
        }.value

        try Task.checkCancellation()

        if let firstPage = result.1 {
            createPDFThumbnail(from: firstPage)
        }

        self.textContent = result.0
        self.isLoading = false
        saveToEntity()
    }
    
    private func loadRTFFile(from url: URL) async throws {
        let content = try await Task.detached(priority: .userInitiated) {
            let rtfData = try Data(contentsOf: url)
            guard let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) else {
                throw NSError(
                    domain: "FileAttachment",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to parse RTF"]
                )
            }
            return attributedString.string
        }.value

        try Task.checkCancellation()
        self.textContent = content
        self.isLoading = false
        saveToEntity()
    }
    
    private func loadGenericFile(from url: URL, fileName: String) async {
        let content = await Task.detached(priority: .userInitiated) {
            (try? String(contentsOf: url, encoding: .utf8)) ?? "[Binary file: \(fileName)]"
        }.value

        self.textContent = content
        self.isLoading = false
        saveToEntity()
    }
    
    private func createThumbnail(from image: NSImage) {
        let thumbnailSize: CGFloat = 100
        let size = image.size
        let aspectRatio = size.width / size.height
        
        let (newWidth, newHeight) = size.width > size.height
            ? (thumbnailSize, thumbnailSize / aspectRatio)
            : (thumbnailSize * aspectRatio, thumbnailSize)
        
        let thumbnailImage = NSImage(size: NSSize(width: newWidth, height: newHeight))
        
        thumbnailImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: newWidth, height: newHeight),
            from: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            operation: .copy,
            fraction: 1.0
        )
        thumbnailImage.unlockFocus()
        
        DispatchQueue.main.async {
            self.thumbnail = thumbnailImage
        }
    }
    
    private func createPDFThumbnail(from page: PDFPage) {
        let pageRect = page.bounds(for: .mediaBox)
        let thumbnailSize = CGSize(width: 100, height: 100)
        let thumbnail = NSImage(size: thumbnailSize)
        
        thumbnail.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: thumbnailSize))
            
            let scale = min(thumbnailSize.width / pageRect.width, thumbnailSize.height / pageRect.height)
            context.scaleBy(x: scale, y: scale)
            
            page.draw(with: .mediaBox, to: context)
        }
        thumbnail.unlockFocus()
        
        self.thumbnail = thumbnail
    }
    
    private func startLoadingFromEntity() {
        loadTask?.cancel()
        isLoading = true
        error = nil
        
        guard let context = managedObjectContext, let fileEntityID else {
            error = NSError(
                domain: "FileAttachment",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing file database reference"]
            )
            isLoading = false
            return
        }

        loadTask = Task { [weak self] in
            guard let self else { return }

            let values: (Data?, Data?, String?, Int64, String?) = await context.performAsync {
                guard let object = try? context.existingObject(with: fileEntityID) as? FileEntity else {
                    return (nil, nil, nil, 0, nil)
                }
                return (object.imageData, object.thumbnailData, object.textContent, object.fileSize, object.fileType)
            }

            if Task.isCancelled { return }

            if let text = values.2 {
                self.textContent = text
            }
            if values.3 > 0 {
                self.fileSize = values.3
            }
            if let typeString = values.4 {
                self.fileType = self.determineFileType(from: typeString)
            }

            if case .image = self.fileType {
                if let imageData = values.0, let decodedImage = NSImage(data: imageData) {
                    self.image = decodedImage
                    self.persistedImageData = imageData
                } else {
                    self.hasUnavailablePersistedImage = true
                }
            }
            if let thumbnailData = values.1, let decodedThumbnail = NSImage(data: thumbnailData) {
                self.thumbnail = decodedThumbnail
            }

            self.isLoading = false
        }
    }
    
    @discardableResult
    func saveToEntity(context: NSManagedObjectContext? = nil) -> Bool {
        let contextToUse = context ?? managedObjectContext
        guard let contextToUse = contextToUse else { return false }
        
        if context != nil {
            self.managedObjectContext = context
        }

        let id = id
        let fileName = fileName
        let fileSize = fileSize
        let textContent = textContent
        let fileTypeString = originalUTType.preferredFilenameExtension
        let imageData = image.flatMap { Self.convertImageToData($0, compression: 0.9) }
        let thumbnailData = thumbnail.flatMap { Self.convertImageToData($0, compression: 0.7) }
        let fileEntityID = fileEntityID

        var didSave = false
        contextToUse.performAndWait { [weak self] in
            let entity: FileEntity
            if let fileEntityID, let existing = try? contextToUse.existingObject(with: fileEntityID) as? FileEntity {
                entity = existing
            } else {
                let newEntity = FileEntity(context: contextToUse)
                newEntity.id = id
                entity = newEntity

                let objectID = newEntity.objectID
                Task { @MainActor [weak self] in
                    self?.fileEntityID = objectID
                }
            }

            entity.fileName = fileName
            entity.fileSize = fileSize
            entity.textContent = textContent
            entity.fileType = fileTypeString
            entity.imageData = imageData
            entity.thumbnailData = thumbnailData

            do {
                try contextToUse.save()
                didSave = true
            } catch {
                WardenLog.coreData.error("Error saving file to Core Data: \(error.localizedDescription, privacy: .public)")
            }
        }
        if let imageData {
            persistedImageData = imageData
        }
        return didSave
    }

    private static func imageType(for data: Data) -> UTType? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) else {
            return nil
        }
        return UTType(identifier as String)
    }

    private static func exportFileName(_ fileName: String, extension fileExtension: String) -> String {
        guard !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "attachment.\(fileExtension.lowercased())"
        }
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let safeStem = stem.isEmpty ? "attachment" : stem
        return "\(safeStem).\(fileExtension.lowercased())"
    }

    private static func textExtension(for fileType: FileAttachmentType) -> String {
        switch fileType {
        case .text: return "txt"
        case .csv: return "csv"
        case .json: return "json"
        case .xml: return "xml"
        case .markdown: return "md"
        default: return "txt"
        }
    }
    
    private static func convertImageToData(_ image: NSImage, compression: Double = 0.8) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: compression])
    }
    
    func toAPIContent() -> [String: Any] {
        switch fileType {
        case .image:
            if let image = self.image, let data = Self.convertImageToData(image, compression: 0.8) {
                return [
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())"]
                ]
            }
            return ["type": "text", "text": "[Failed to encode image]"]
            
        case .text, .csv, .json, .xml, .markdown, .rtf, .other:
            let fileTypeDescription = getFileTypeDescription()
            let content = """
            File: \(fileName) (\(fileTypeDescription))
            Size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
            
            Content:
            \(textContent)
            """
            return ["type": "text", "text": content]
            
        case .pdf:
            let content = """
            PDF File: \(fileName)
            Size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
            
            Extracted Text:
            \(textContent)
            """
            return ["type": "text", "text": content]
        }
    }
    
    private func getFileTypeDescription() -> String {
        switch fileType {
        case .text: return "Text File"
        case .csv: return "CSV File"
        case .json: return "JSON File"
        case .xml: return "XML File"
        case .markdown: return "Markdown File"
        case .rtf: return "Rich Text File"
        case .pdf: return "PDF Document"
        case .image: return "Image File"
        case .other(let ext): return "\(ext.uppercased()) File"
        }
    }
}
