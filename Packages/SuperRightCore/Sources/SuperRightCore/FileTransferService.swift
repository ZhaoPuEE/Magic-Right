import Foundation

public enum FileTransferKind: String, Codable, Hashable, Sendable {
    case move
    case copy
}

public struct FileTransferRequest: Hashable, Sendable {
    public let kind: FileTransferKind
    public let sourceURL: URL
    public let destinationDirectory: URL

    public init(
        kind: FileTransferKind,
        sourceURL: URL,
        destinationDirectory: URL
    ) {
        self.kind = kind
        self.sourceURL = sourceURL
        self.destinationDirectory = destinationDirectory
    }
}

public struct FileTransferResult: Codable, Hashable, Sendable {
    public let kind: FileTransferKind
    public let sourceURL: URL
    public let destinationURL: URL

    public init(
        kind: FileTransferKind,
        sourceURL: URL,
        destinationURL: URL
    ) {
        self.kind = kind
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
    }
}

public enum FileTransferServiceError: Error, Equatable, Sendable {
    case sourceDoesNotExist(URL)
    case destinationDoesNotExist(URL)
    case destinationIsNotDirectory(URL)
    case moveDestinationIsCurrentParent(source: URL, destination: URL)
    case destinationIsInsideSource(source: URL, destination: URL)
    case noAvailableName(URL)
}

/// Moves or copies one Finder item without overwriting an existing item.
public struct FileTransferService: Sendable {
    private static let maximumNameAttempts = 10_000

    public init() {}

    public func transfer(_ request: FileTransferRequest) throws -> FileTransferResult {
        let fileManager = FileManager.default
        guard let sourceType = FileSystemItemInspector.type(
            at: request.sourceURL,
            fileManager: fileManager
        ) else {
            throw FileTransferServiceError.sourceDoesNotExist(request.sourceURL)
        }
        let sourceIsDirectory = sourceType == .typeDirectory

        var destinationIsDirectory = ObjCBool(false)
        guard fileManager.fileExists(
            atPath: request.destinationDirectory.path,
            isDirectory: &destinationIsDirectory
        ) else {
            throw FileTransferServiceError.destinationDoesNotExist(
                request.destinationDirectory
            )
        }
        guard destinationIsDirectory.boolValue else {
            throw FileTransferServiceError.destinationIsNotDirectory(
                request.destinationDirectory
            )
        }

        // Resolve symbolic links before checking ancestry. Otherwise a
        // destination such as `source/child-link -> source/child` could make a
        // recursive directory transfer bypass the lexical path check.
        let normalizedSource = request.sourceURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let normalizedDestination = request.destinationDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let normalizedSourceParent = request.sourceURL
            .deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        if request.kind == .move,
           normalizedDestination == normalizedSourceParent {
            throw FileTransferServiceError.moveDestinationIsCurrentParent(
                source: request.sourceURL,
                destination: request.destinationDirectory
            )
        }
        if sourceIsDirectory,
           Self.isEqualOrDescendant(
            normalizedDestination,
            of: normalizedSource
           ) {
            throw FileTransferServiceError.destinationIsInsideSource(
                source: request.sourceURL,
                destination: request.destinationDirectory
            )
        }

        for attempt in 1...Self.maximumNameAttempts {
            let destinationURL = Self.candidateURL(
                for: request.sourceURL,
                in: request.destinationDirectory,
                isDirectory: sourceIsDirectory,
                attempt: attempt
            )
            guard !fileManager.fileExists(atPath: destinationURL.path) else {
                continue
            }

            do {
                switch request.kind {
                case .move:
                    try fileManager.moveItem(
                        at: request.sourceURL,
                        to: destinationURL
                    )
                case .copy:
                    try fileManager.copyItem(
                        at: request.sourceURL,
                        to: destinationURL
                    )
                }
                return FileTransferResult(
                    kind: request.kind,
                    sourceURL: request.sourceURL,
                    destinationURL: destinationURL
                )
            } catch {
                // Another process may have claimed the candidate after the
                // existence check. Retry only that collision; preserve every
                // other failure for the caller to report.
                if Self.isFileExistsError(error) {
                    continue
                }
                throw error
            }
        }

        throw FileTransferServiceError.noAvailableName(
            request.destinationDirectory
        )
    }

    private static func candidateURL(
        for sourceURL: URL,
        in destinationDirectory: URL,
        isDirectory: Bool,
        attempt: Int
    ) -> URL {
        precondition(attempt > 0)
        let originalName = sourceURL.lastPathComponent
        guard attempt > 1 else {
            return destinationDirectory.appendingPathComponent(
                originalName,
                isDirectory: isDirectory
            )
        }

        let suffix = " \(attempt)"
        let name: String
        if isDirectory {
            name = originalName + suffix
        } else {
            let pathExtension = sourceURL.pathExtension
            let isSingleDotFile = originalName.hasPrefix(".")
                && !originalName.dropFirst().contains(".")
            if pathExtension.isEmpty || isSingleDotFile {
                name = originalName + suffix
            } else {
                name = sourceURL.deletingPathExtension().lastPathComponent
                    + suffix
                    + "."
                    + pathExtension
            }
        }
        return destinationDirectory.appendingPathComponent(
            name,
            isDirectory: isDirectory
        )
    }

    private static func isEqualOrDescendant(_ url: URL, of ancestor: URL) -> Bool {
        let components = url.pathComponents
        let ancestorComponents = ancestor.pathComponents
        guard components.count >= ancestorComponents.count else { return false }
        return components.prefix(ancestorComponents.count)
            .elementsEqual(ancestorComponents)
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

public struct FileOperationRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let result: FileTransferResult
    public let completedAt: Date

    public init(
        id: UUID = UUID(),
        result: FileTransferResult,
        completedAt: Date = Date()
    ) {
        self.id = id
        self.result = result
        self.completedAt = completedAt
    }
}

public struct FileOperationJournal: Codable, Hashable, Sendable {
    public private(set) var records: [FileOperationRecord]

    public init(records: [FileOperationRecord] = []) {
        self.records = records
    }

    public mutating func append(
        _ record: FileOperationRecord,
        maximumRecordCount: Int = 100
    ) {
        records.append(record)
        let maximum = max(1, maximumRecordCount)
        if records.count > maximum {
            records.removeFirst(records.count - maximum)
        }
    }
}
