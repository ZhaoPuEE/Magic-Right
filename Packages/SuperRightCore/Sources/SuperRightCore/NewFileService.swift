import Foundation

/// Built-in file templates that can be created without launching another app.
public enum NewFilePreset: String, Codable, CaseIterable, Hashable, Sendable {
    case markdown
    case plainText
    case richText
    case xml
    case json
    case yaml
    case gitignore

    /// The first filename attempted when creating this preset.
    public var defaultFileName: String {
        switch self {
        case .markdown: "未命名.md"
        case .plainText: "未命名.txt"
        case .richText: "未命名.rtf"
        case .xml: "未命名.xml"
        case .json: "未命名.json"
        case .yaml: "未命名.yaml"
        case .gitignore: ".gitignore"
        }
    }

    /// A small, valid document for formats whose syntax requires structure.
    /// Empty text, Markdown, and gitignore documents are valid as-is.
    public var initialContents: Data {
        switch self {
        case .markdown, .plainText, .gitignore:
            Data()
        case .richText:
            Data("{\\rtf1\\ansi\n}\n".utf8)
        case .xml:
            Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root />\n".utf8)
        case .json:
            Data("{}\n".utf8)
        case .yaml:
            Data("---\n{}\n".utf8)
        }
    }

    /// Returns a conflict-safe filename for the one-based creation attempt.
    /// Hidden `.gitignore` files deliberately have no conventional basename or
    /// extension, so their numeric suffix is appended to the complete name.
    public func fileName(attempt: Int) -> String {
        precondition(attempt > 0, "A new-file attempt must be positive")
        guard attempt > 1 else { return defaultFileName }

        switch self {
        case .gitignore:
            return ".gitignore \(attempt)"
        case .markdown:
            return "未命名 \(attempt).md"
        case .plainText:
            return "未命名 \(attempt).txt"
        case .richText:
            return "未命名 \(attempt).rtf"
        case .xml:
            return "未命名 \(attempt).xml"
        case .json:
            return "未命名 \(attempt).json"
        case .yaml:
            return "未命名 \(attempt).yaml"
        }
    }
}

/// A structured request passed by the host app or Finder extension.
public struct NewFileRequest: Codable, Hashable, Sendable {
    public let preset: NewFilePreset
    public let destinationDirectory: URL

    public init(preset: NewFilePreset, destinationDirectory: URL) {
        self.preset = preset
        self.destinationDirectory = destinationDirectory
    }
}

public enum NewFileItemKind: Equatable, Sendable {
    case directory
    case other
}

/// Minimal file-system surface needed by `NewFileService`.
///
/// Implementations must make `createFileExclusively` atomic with respect to an
/// existing destination: returning `false` means the item already existed and
/// its contents were left untouched.
public protocol NewFileFileSystem: Sendable {
    func itemKind(at url: URL) throws -> NewFileItemKind?
    func createFileExclusively(at url: URL, contents: Data) throws -> Bool
}

/// Local disk implementation used by the app.
public struct LocalNewFileFileSystem: NewFileFileSystem {
    public init() {}

    public func itemKind(at url: URL) throws -> NewFileItemKind? {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) else {
            return nil
        }
        return isDirectory.boolValue ? .directory : .other
    }

    public func createFileExclusively(at url: URL, contents: Data) throws -> Bool {
        do {
            try contents.write(to: url, options: .withoutOverwriting)
            return true
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            return false
        }
    }
}

public enum NewFileServiceError: Error, Equatable, Sendable {
    case destinationDoesNotExist(URL)
    case destinationIsNotDirectory(URL)
    case noAvailableFileName(URL)
}

/// Creates built-in documents without overwriting any existing item.
public struct NewFileService: Sendable {
    private static let maximumNameAttempts = 10_000

    private let fileSystem: any NewFileFileSystem

    public init(fileSystem: any NewFileFileSystem = LocalNewFileFileSystem()) {
        self.fileSystem = fileSystem
    }

    /// Creates the requested preset and returns the URL that was actually used.
    /// If another process claims a candidate between attempts, the next numeric
    /// suffix is tried instead of overwriting the competing item.
    @discardableResult
    public func createFile(for request: NewFileRequest) throws -> URL {
        switch try fileSystem.itemKind(at: request.destinationDirectory) {
        case nil:
            throw NewFileServiceError.destinationDoesNotExist(
                request.destinationDirectory
            )
        case .other:
            throw NewFileServiceError.destinationIsNotDirectory(
                request.destinationDirectory
            )
        case .directory:
            break
        }

        for attempt in 1...Self.maximumNameAttempts {
            let candidate = request.destinationDirectory.appendingPathComponent(
                request.preset.fileName(attempt: attempt),
                isDirectory: false
            )
            if try fileSystem.createFileExclusively(
                at: candidate,
                contents: request.preset.initialContents
            ) {
                return candidate
            }
        }

        throw NewFileServiceError.noAvailableFileName(
            request.destinationDirectory
        )
    }
}
