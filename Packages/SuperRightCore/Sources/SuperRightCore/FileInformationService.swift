import CryptoKit
import Foundation
import UniformTypeIdentifiers

public enum FileItemKind: String, Codable, Hashable, Sendable {
    case regularFile
    case directory
    case symbolicLink
    case alias
    case other
}

public struct FileInformationOptions: Hashable, Sendable {
    public var calculateDirectorySize: Bool
    public var calculateSHA256: Bool

    public init(
        calculateDirectorySize: Bool = false,
        calculateSHA256: Bool = false
    ) {
        self.calculateDirectorySize = calculateDirectorySize
        self.calculateSHA256 = calculateSHA256
    }
}

public struct FileItemInformation: Codable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public let kind: FileItemKind
    public let localizedTypeDescription: String?
    public let contentTypeIdentifier: String?
    public let logicalSizeInBytes: Int64?
    public let allocatedSizeInBytes: Int64?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let addedToDirectoryDate: Date?
    public let lastAccessDate: Date?
    public let isHidden: Bool
    public let isReadable: Bool
    public let isWritable: Bool
    public let posixPermissions: UInt16?
    public let sha256: String?

    public init(
        url: URL,
        name: String,
        kind: FileItemKind,
        localizedTypeDescription: String?,
        contentTypeIdentifier: String?,
        logicalSizeInBytes: Int64?,
        allocatedSizeInBytes: Int64?,
        creationDate: Date?,
        modificationDate: Date?,
        addedToDirectoryDate: Date?,
        lastAccessDate: Date?,
        isHidden: Bool,
        isReadable: Bool,
        isWritable: Bool,
        posixPermissions: UInt16?,
        sha256: String?
    ) {
        self.url = url
        self.name = name
        self.kind = kind
        self.localizedTypeDescription = localizedTypeDescription
        self.contentTypeIdentifier = contentTypeIdentifier
        self.logicalSizeInBytes = logicalSizeInBytes
        self.allocatedSizeInBytes = allocatedSizeInBytes
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.addedToDirectoryDate = addedToDirectoryDate
        self.lastAccessDate = lastAccessDate
        self.isHidden = isHidden
        self.isReadable = isReadable
        self.isWritable = isWritable
        self.posixPermissions = posixPermissions
        self.sha256 = sha256
    }
}

public enum FileInformationServiceError: Error, Equatable, Sendable {
    case itemDoesNotExist(URL)
    case sha256RequiresRegularFile(URL)
}

public struct FileInformationService: Sendable {
    public init() {}

    public func information(
        for itemURL: URL,
        options: FileInformationOptions = .init()
    ) throws -> FileItemInformation {
        let url = itemURL.standardizedFileURL
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(
            atPath: url.path
        ), let fileType = attributes[.type] as? FileAttributeType else {
            throw FileInformationServiceError.itemDoesNotExist(itemURL)
        }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
            .localizedTypeDescriptionKey,
            .contentTypeKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .addedToDirectoryDateKey,
            .contentAccessDateKey,
            .isHiddenKey,
            .isReadableKey,
            .isWritableKey
        ]
        let values = try? url.resourceValues(forKeys: keys)
        let kind = fileType == .typeSymbolicLink
            ? FileItemKind.symbolicLink
            : values.map(Self.kind(from:)) ?? .other

        let sizes: (logical: Int64?, allocated: Int64?)
        if kind == .directory, options.calculateDirectorySize {
            sizes = try Self.recursiveDirectorySizes(at: url)
        } else if kind == .directory {
            sizes = (nil, nil)
        } else {
            sizes = (
                values?.fileSize.map(Int64.init)
                    ?? (attributes[.size] as? NSNumber)?.int64Value,
                values?.totalFileAllocatedSize.map(Int64.init)
            )
        }

        let digest: String?
        if options.calculateSHA256 {
            guard kind == .regularFile else {
                throw FileInformationServiceError.sha256RequiresRegularFile(url)
            }
            digest = try Self.sha256(of: url)
        } else {
            digest = nil
        }

        let permissions = (attributes[.posixPermissions] as? NSNumber)
            .map { UInt16(truncating: $0) }

        return FileItemInformation(
            url: url,
            name: url.lastPathComponent,
            kind: kind,
            localizedTypeDescription: values?.localizedTypeDescription,
            contentTypeIdentifier: values?.contentType?.identifier,
            logicalSizeInBytes: sizes.logical,
            allocatedSizeInBytes: sizes.allocated,
            creationDate: values?.creationDate
                ?? attributes[.creationDate] as? Date,
            modificationDate: values?.contentModificationDate
                ?? attributes[.modificationDate] as? Date,
            addedToDirectoryDate: values?.addedToDirectoryDate,
            lastAccessDate: values?.contentAccessDate,
            isHidden: values?.isHidden ?? url.lastPathComponent.hasPrefix("."),
            isReadable: values?.isReadable
                ?? fileManager.isReadableFile(atPath: url.path),
            isWritable: values?.isWritable
                ?? fileManager.isWritableFile(atPath: url.path),
            posixPermissions: permissions,
            sha256: digest
        )
    }

    private static func kind(from values: URLResourceValues) -> FileItemKind {
        if values.isAliasFile == true { return .alias }
        if values.isSymbolicLink == true { return .symbolicLink }
        if values.isDirectory == true { return .directory }
        if values.isRegularFile == true { return .regularFile }
        return .other
    }

    private static func recursiveDirectorySizes(
        at directoryURL: URL
    ) throws -> (logical: Int64, allocated: Int64) {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return (0, 0)
        }

        var logical: Int64 = 0
        var allocated: Int64 = 0
        for case let childURL as URL in enumerator {
            let values = try childURL.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            logical += Int64(values.fileSize ?? 0)
            allocated += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return (logical, allocated)
    }

    private static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
