import CoreServices
import Foundation
import PDFKit

public struct FileMetadata: Sendable {
    public let url: URL
    public let path: String
    public let name: String
    public let ext: String
    public let size: UInt64
    public let creationDate: Date?
    public let modificationDate: Date?
    public let isDirectory: Bool
    public let tags: [String]
    public let downloadURL: String?
    public let quarantineAgentName: String?
    public let isQuarantined: Bool
    public let uti: String?

    public var ageDays: Double {
        guard let date = creationDate else { return 0 }
        return Date().timeIntervalSince(date) / 86400
    }

    public var ageHours: Double {
        guard let date = creationDate else { return 0 }
        return Date().timeIntervalSince(date) / 3600
    }

    public var ageModifiedDays: Double {
        guard let date = modificationDate else { return 0 }
        return Date().timeIntervalSince(date) / 86400
    }

    public var sizeHuman: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

public struct FileIntrospector: Sendable {
    public init() {}

    public func inspect(url: URL) throws -> FileMetadata {
        let resourceValues = try url.resourceValues(forKeys: [
            .fileSizeKey, .creationDateKey, .contentModificationDateKey,
            .isDirectoryKey, .tagNamesKey, .typeIdentifierKey,
        ])

        let downloadURL = readDownloadURL(for: url)
        let quarantineInfo = readQuarantineInfo(for: url)

        return FileMetadata(
            url: url,
            path: url.path,
            name: url.lastPathComponent,
            ext: url.pathExtension,
            size: UInt64(resourceValues.fileSize ?? 0),
            creationDate: resourceValues.creationDate,
            modificationDate: resourceValues.contentModificationDate,
            isDirectory: resourceValues.isDirectory ?? false,
            tags: resourceValues.tagNames ?? [],
            downloadURL: downloadURL,
            quarantineAgentName: quarantineInfo?.agentName,
            isQuarantined: quarantineInfo != nil,
            uti: resourceValues.typeIdentifier,
        )
    }

    // MARK: - Download source URL from com.apple.metadata:kMDItemWhereFroms

    private func readDownloadURL(for url: URL) -> String? {
        let attrName = "com.apple.metadata:kMDItemWhereFroms"
        let length = getxattr(url.path, attrName, nil, 0, 0, 0)
        guard length > 0 else { return nil }

        var data = Data(count: length)
        let result = data.withUnsafeMutableBytes { ptr -> Int in
            getxattr(url.path, attrName, ptr.baseAddress, length, 0, 0)
        }
        guard result > 0 else { return nil }

        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String] {
            return plist.first
        }
        return nil
    }

    // MARK: - Quarantine info from com.apple.quarantine

    private struct QuarantineInfo {
        let agentName: String?
        let timestamp: Date?
    }

    private func readQuarantineInfo(for url: URL) -> QuarantineInfo? {
        let attrName = "com.apple.quarantine"
        let length = getxattr(url.path, attrName, nil, 0, 0, 0)
        guard length > 0 else { return nil }

        var data = Data(count: length)
        let result = data.withUnsafeMutableBytes { ptr -> Int in
            getxattr(url.path, attrName, ptr.baseAddress, length, 0, 0)
        }
        guard result > 0 else { return nil }

        // Quarantine xattr format: "flag;timestamp;agentName;uuid"
        if let str = String(data: data, encoding: .utf8) {
            let parts = str.components(separatedBy: ";")
            let agentName = parts.count > 2 ? parts[2] : nil
            return QuarantineInfo(agentName: agentName, timestamp: nil)
        }
        return nil
    }

    // MARK: - Content matching

    public func contentMatches(url: URL, pattern: String, maxSize: UInt64) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? UInt64,
              fileSize <= maxSize
        else { return false }

        guard let content = extractText(from: url) else { return false }

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(content.startIndex..., in: content)
        return regex.firstMatch(in: content, range: range) != nil
    }

    private func extractText(from url: URL) -> String? {
        // PDF: use PDFKit
        if url.pathExtension.lowercased() == "pdf" {
            return extractTextFromPDF(url: url)
        }

        // Plain text: try UTF-8
        if let data = FileManager.default.contents(atPath: url.path),
           let text = String(data: data, encoding: .utf8)
        {
            return text
        }

        // Other rich documents (docx, pages, rtf, etc.): Spotlight metadata
        return extractTextViaSpotlight(url: url)
    }

    private func extractTextFromPDF(url: URL) -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        return doc.string
    }

    private func extractTextViaSpotlight(url: URL) -> String? {
        guard let mdItem = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(mdItem, kMDItemTextContent) as? String
    }
}
