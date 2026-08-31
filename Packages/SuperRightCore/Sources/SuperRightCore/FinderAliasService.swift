import Foundation

public struct FinderAliasCreationResult: Codable, Hashable, Sendable {
    public let targetURL: URL
    public let aliasURL: URL

    public init(targetURL: URL, aliasURL: URL) {
        self.targetURL = targetURL
        self.aliasURL = aliasURL
    }
}

public enum FinderAliasServiceError: Error, Equatable, Sendable {
    case targetDoesNotExist(URL)
    case destinationDoesNotExist(URL)
    case destinationIsNotDirectory(URL)
    case invalidAliasLabel
    case noAvailableName(URL)
}

/// Creates a real macOS bookmark alias file that Finder can resolve.
public struct FinderAliasService: Sendable {
    private static let maximumNameAttempts = 10_000

    public init() {}

    public func createAlias(
        to targetURL: URL,
        in destinationDirectory: URL,
        aliasLabel: String = "替身"
    ) throws -> FinderAliasCreationResult {
        let label = aliasLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, !label.contains("/") else {
            throw FinderAliasServiceError.invalidAliasLabel
        }

        let fileManager = FileManager.default
        guard let targetType = FileSystemItemInspector.type(
            at: targetURL,
            fileManager: fileManager
        ) else {
            throw FinderAliasServiceError.targetDoesNotExist(targetURL)
        }
        let targetIsDirectory = targetType == .typeDirectory
        var destinationIsDirectory = ObjCBool(false)
        guard fileManager.fileExists(
            atPath: destinationDirectory.path,
            isDirectory: &destinationIsDirectory
        ) else {
            throw FinderAliasServiceError.destinationDoesNotExist(
                destinationDirectory
            )
        }
        guard destinationIsDirectory.boolValue else {
            throw FinderAliasServiceError.destinationIsNotDirectory(
                destinationDirectory
            )
        }

        let normalizedTarget = targetURL.standardizedFileURL
        let bookmarkData = try normalizedTarget.bookmarkData(
            options: .suitableForBookmarkFile,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        for attempt in 1...Self.maximumNameAttempts {
            let candidate = Self.candidateURL(
                for: normalizedTarget,
                in: destinationDirectory,
                targetIsDirectory: targetIsDirectory,
                aliasLabel: label,
                attempt: attempt
            )
            guard !fileManager.fileExists(atPath: candidate.path) else {
                continue
            }

            let temporaryURL = destinationDirectory.appendingPathComponent(
                ".magic-right-alias-\(UUID().uuidString)",
                isDirectory: false
            )
            defer { try? fileManager.removeItem(at: temporaryURL) }
            try URL.writeBookmarkData(bookmarkData, to: temporaryURL)
            do {
                // Moving the completed alias into place makes the final name
                // collision-safe even if another process creates it between
                // our existence check and this operation.
                try fileManager.moveItem(at: temporaryURL, to: candidate)
                return FinderAliasCreationResult(
                    targetURL: normalizedTarget,
                    aliasURL: candidate
                )
            } catch {
                if Self.isFileExistsError(error) {
                    continue
                }
                throw error
            }
        }

        throw FinderAliasServiceError.noAvailableName(destinationDirectory)
    }

    private static func candidateURL(
        for targetURL: URL,
        in destinationDirectory: URL,
        targetIsDirectory: Bool,
        aliasLabel: String,
        attempt: Int
    ) -> URL {
        precondition(attempt > 0)
        let numberedLabel = attempt == 1
            ? aliasLabel
            : "\(aliasLabel) \(attempt)"
        let originalName = targetURL.lastPathComponent
        let name: String
        let pathExtension = targetURL.pathExtension
        let isSingleDotFile = originalName.hasPrefix(".")
            && !originalName.dropFirst().contains(".")
        if targetIsDirectory || pathExtension.isEmpty || isSingleDotFile {
            name = "\(originalName) \(numberedLabel)"
        } else {
            let stem = targetURL.deletingPathExtension().lastPathComponent
            name = "\(stem) \(numberedLabel).\(pathExtension)"
        }
        return destinationDirectory.appendingPathComponent(
            name,
            isDirectory: false
        )
    }

    private static func isFileExistsError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.Code.fileWriteFileExists.rawValue {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == POSIXErrorCode.EEXIST.rawValue {
            return true
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isFileExistsError(underlyingError)
        }
        return false
    }
}
