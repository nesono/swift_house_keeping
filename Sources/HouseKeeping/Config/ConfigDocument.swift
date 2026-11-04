import Foundation

/// A text-preserving configuration edit, including the disk snapshot it was based on.
public struct ConfigDocument: Codable, Sendable {
    public let url: URL
    public var text: String
    private var originalData: Data?

    public static let starter = """
    version: 1

    global:
      log_level: info
      log_file: ~/Library/Logs/house_keeping/house_keeping.log
      state_file: ~/.local/share/house_keeping/state.db

    # Add your rules here. Use the example in the editor to get started.
    rules: []

    """

    public init(path: String = ConfigLoader.defaultConfigPath) throws {
        url = URL(fileURLWithPath: Config.expandPath(path)).resolvingSymlinksInPath()
        originalData = try Self.readIfPresent(url)
        if let originalData {
            guard let text = String(data: originalData, encoding: .utf8) else {
                throw DocumentError.invalidEncoding
            }
            self.text = text
        } else {
            text = Self.starter
        }
    }

    public var isDirty: Bool {
        Data(text.utf8) != originalData
    }

    @discardableResult
    public func validate() throws -> Config {
        let loader = ConfigLoader()
        let config = try loader.parse(text)
        let errors = loader.validate(config)
        guard errors.isEmpty else { throw ConfigError.validationError(errors) }
        return config
    }

    public mutating func save() throws {
        try validate()
        guard try Self.readIfPresent(url) == originalData else {
            throw DocumentError.changedOnDisk
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(text.utf8)
        try data.write(to: url, options: .atomic)
        originalData = data
    }

    private static func readIfPresent(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }
}

public enum DocumentError: Error, LocalizedError {
    case invalidEncoding
    case changedOnDisk

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            "The configuration is not UTF-8 text."
        case .changedOnDisk:
            "The configuration changed on disk. Copy your edits, then reload the file before saving."
        }
    }
}
