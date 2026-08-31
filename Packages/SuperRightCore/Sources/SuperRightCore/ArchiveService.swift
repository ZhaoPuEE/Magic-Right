import Foundation

public enum ArchiveFormat: String, Codable, Hashable, Sendable {
    case zip
    case tar
    case tarGzip

    fileprivate static func detect(from url: URL) -> ArchiveFormat? {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") {
            return .tarGzip
        }
        if name.hasSuffix(".tar") {
            return .tar
        }
        if name.hasSuffix(".zip") {
            return .zip
        }
        return nil
    }
}

public struct ArchiveCreationResult: Equatable, Sendable {
    public let sourceURLs: [URL]
    public let archiveURL: URL

    public init(sourceURLs: [URL], archiveURL: URL) {
        self.sourceURLs = sourceURLs
        self.archiveURL = archiveURL
    }
}

public struct ArchiveExtractionResult: Equatable, Sendable {
    public let archiveURL: URL
    public let destinationDirectoryURL: URL

    public init(archiveURL: URL, destinationDirectoryURL: URL) {
        self.archiveURL = archiveURL
        self.destinationDirectoryURL = destinationDirectoryURL
    }
}

public enum ArchiveCommand: String, Codable, Hashable, Sendable {
    case createZIP
    case listEntries
    case extract
}

public enum ArchiveServiceError: Error, Equatable, Sendable {
    case noSources
    case sourceDoesNotExist(URL)
    case sourcesHaveDifferentParents
    case destinationDoesNotExist(URL)
    case destinationIsNotDirectory(URL)
    case archiveDoesNotExist(URL)
    case archiveIsNotAFile(URL)
    case unsupportedArchive(URL)
    case invalidArchiveListing
    case archiveEntryLimitExceeded(maximum: Int)
    case unsafeArchiveEntry(String)
    case unsafeExtractedItem(URL)
    case commandCouldNotRun(ArchiveCommand)
    case commandFailed(command: ArchiveCommand, status: Int32)
    case commandTimedOut(ArchiveCommand)
    case commandOutputLimitExceeded(ArchiveCommand)
    case archiveDataLimitExceeded(maximumBytes: UInt64)
    case expandedDataLimitExceeded(maximumBytes: UInt64)
    case insufficientAvailableCapacity(URL)
    case capacityCheckFailed(URL)
    case noAvailableName(URL)
}

extension ArchiveServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noSources:
            "没有可压缩的项目。"
        case let .sourceDoesNotExist(url):
            "源项目不存在：\(url.path)"
        case .sourcesHaveDifferentParents:
            "一次只能压缩位于同一目录中的项目。"
        case let .destinationDoesNotExist(url):
            "目标目录不存在：\(url.path)"
        case let .destinationIsNotDirectory(url):
            "目标不是目录：\(url.path)"
        case let .archiveDoesNotExist(url):
            "压缩包不存在：\(url.path)"
        case let .archiveIsNotAFile(url):
            "所选压缩包不是文件：\(url.path)"
        case let .unsupportedArchive(url):
            "不支持该压缩格式：\(url.lastPathComponent)"
        case .invalidArchiveListing:
            "无法读取压缩包目录。"
        case let .archiveEntryLimitExceeded(maximum):
            "压缩包项目数超过安全上限（\(maximum) 项）。"
        case let .unsafeArchiveEntry(entry):
            "压缩包包含不安全路径：\(entry)"
        case let .unsafeExtractedItem(url):
            "解压结果包含不安全项目：\(url.lastPathComponent)"
        case let .commandCouldNotRun(command):
            "无法启动归档工具（\(command.rawValue)）。"
        case let .commandFailed(command, status):
            "归档工具执行失败（\(command.rawValue)，状态 \(status)）。"
        case let .commandTimedOut(command):
            "归档操作超时（\(command.rawValue)）。"
        case let .commandOutputLimitExceeded(command):
            "归档工具输出超过安全上限（\(command.rawValue)）。"
        case let .archiveDataLimitExceeded(maximumBytes):
            "生成的 ZIP 超过大小上限（\(Self.byteCount(maximumBytes))）。"
        case let .expandedDataLimitExceeded(maximumBytes):
            "解压数据超过安全上限（\(Self.byteCount(maximumBytes))）。"
        case let .insufficientAvailableCapacity(url):
            "磁盘空间不足：\(url.path)"
        case let .capacityCheckFailed(url):
            "无法检查可用磁盘空间：\(url.path)"
        case let .noAvailableName(url):
            "无法在目标目录生成不冲突的名称：\(url.path)"
        }
    }

    private static func byteCount(_ value: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(clamping: value),
            countStyle: .file
        )
    }
}

struct ArchiveSafetyLimits: Equatable, Sendable {
    let maximumListingBytes: UInt64
    let maximumEntryCount: Int
    let maximumArchiveBytes: UInt64
    let maximumExpandedBytes: UInt64
    let minimumFreeSpaceReserveBytes: UInt64
    let listingTimeout: TimeInterval
    let operationTimeout: TimeInterval

    init(
        maximumListingBytes: UInt64,
        maximumEntryCount: Int,
        maximumArchiveBytes: UInt64,
        maximumExpandedBytes: UInt64,
        minimumFreeSpaceReserveBytes: UInt64,
        listingTimeout: TimeInterval,
        operationTimeout: TimeInterval
    ) {
        precondition(maximumListingBytes > 0)
        precondition(maximumEntryCount > 0)
        precondition(maximumArchiveBytes > 0)
        precondition(maximumExpandedBytes > 0)
        precondition(listingTimeout > 0)
        precondition(operationTimeout > 0)
        self.maximumListingBytes = maximumListingBytes
        self.maximumEntryCount = maximumEntryCount
        self.maximumArchiveBytes = maximumArchiveBytes
        self.maximumExpandedBytes = maximumExpandedBytes
        self.minimumFreeSpaceReserveBytes = minimumFreeSpaceReserveBytes
        self.listingTimeout = listingTimeout
        self.operationTimeout = operationTimeout
    }

    static let standard = ArchiveSafetyLimits(
        maximumListingBytes: 8 * 1_024 * 1_024,
        maximumEntryCount: 50_000,
        maximumArchiveBytes: 32 * 1_024 * 1_024 * 1_024,
        maximumExpandedBytes: 32 * 1_024 * 1_024 * 1_024,
        minimumFreeSpaceReserveBytes: 512 * 1_024 * 1_024,
        listingTimeout: 120,
        operationTimeout: 30 * 60
    )
}

struct ArchiveFileSystemMetrics: Sendable {
    let availableCapacity: @Sendable (URL) throws -> UInt64
    let fileTreeUsage: @Sendable (URL) throws -> FileTreeUsage
    let isSameVolume: @Sendable (URL, URL) throws -> Bool

    static let local = ArchiveFileSystemMetrics(
        availableCapacity: { url in
            try LocalStructuredCommandRunner.availableCapacity(at: url)
        },
        fileTreeUsage: { url in
            try LocalStructuredCommandRunner.fileTreeUsage(at: url)
        },
        isSameVolume: { firstURL, secondURL in
            let firstIdentifier = try firstURL.resourceValues(
                forKeys: [.volumeIdentifierKey]
            ).volumeIdentifier
            let secondIdentifier = try secondURL.resourceValues(
                forKeys: [.volumeIdentifierKey]
            ).volumeIdentifier
            guard let firstIdentifier, let secondIdentifier else {
                throw StructuredCommandRunnerError.resourceMonitoringFailed
            }
            return firstIdentifier.isEqual(secondIdentifier)
        }
    )
}

/// Creates ZIP archives and extracts common macOS archives without invoking a
/// shell. Extraction is staged, audited, and then placed in a collision-safe
/// wrapper directory, so existing user files are never overwritten.
public struct ArchiveService: Sendable {
    private static let zipExecutableURL = URL(fileURLWithPath: "/usr/bin/zip")
    private static let tarExecutableURL = URL(fileURLWithPath: "/usr/bin/tar")
    private static let maximumNameAttempts = 10_000

    private let commandRunner: any StructuredCommandRunning
    private let safetyLimits: ArchiveSafetyLimits
    private let fileSystemMetrics: ArchiveFileSystemMetrics

    public init() {
        commandRunner = LocalStructuredCommandRunner()
        safetyLimits = .standard
        fileSystemMetrics = .local
    }

    init(commandRunner: any StructuredCommandRunning) {
        self.init(commandRunner: commandRunner, safetyLimits: .standard)
    }

    init(
        commandRunner: any StructuredCommandRunning,
        safetyLimits: ArchiveSafetyLimits,
        fileSystemMetrics: ArchiveFileSystemMetrics = .local
    ) {
        self.commandRunner = commandRunner
        self.safetyLimits = safetyLimits
        self.fileSystemMetrics = fileSystemMetrics
    }

    public func canExtract(_ url: URL) -> Bool {
        ArchiveFormat.detect(from: url) != nil
    }

    @discardableResult
    public func archive(
        urls sourceURLs: [URL],
        destinationDirectory: URL
    ) throws -> ArchiveCreationResult {
        guard !sourceURLs.isEmpty else {
            throw ArchiveServiceError.noSources
        }
        try validateDestination(destinationDirectory)

        let fileManager = FileManager.default
        let normalizedSources = sourceURLs.map(\.standardizedFileURL)
        var seenPaths = Set<String>()
        var uniqueSources: [URL] = []
        for sourceURL in normalizedSources {
            guard FileSystemItemInspector.exists(
                at: sourceURL,
                fileManager: fileManager
            ) else {
                throw ArchiveServiceError.sourceDoesNotExist(sourceURL)
            }
            if seenPaths.insert(sourceURL.path).inserted {
                uniqueSources.append(sourceURL)
            }
        }
        guard let sharedParent = uniqueSources.first?
            .deletingLastPathComponent()
            .standardizedFileURL,
              uniqueSources.allSatisfy({
                  $0.deletingLastPathComponent().standardizedFileURL == sharedParent
              }) else {
            throw ArchiveServiceError.sourcesHaveDifferentParents
        }

        // Keep the growing ZIP in its own tree so the command runner can
        // measure only this operation, stop it at a deterministic byte budget,
        // and preserve free space on the temporary volume.
        let temporaryVolumeURL = fileManager.temporaryDirectory
        let isolatedStagingURL = temporaryVolumeURL
            .appendingPathComponent(
                "MagicRightArchive-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: isolatedStagingURL,
            withIntermediateDirectories: false
        )
        defer { try? fileManager.removeItem(at: isolatedStagingURL) }

        let archiveBudget = try makeArchiveBudget(
            stagingVolumeURL: temporaryVolumeURL,
            destinationDirectory: destinationDirectory
        )
        let temporaryArchiveURL = isolatedStagingURL.appendingPathComponent(
            "archive.zip",
            isDirectory: false
        )

        let arguments = [
            "-r",
            "-q",
            "-y",
            temporaryArchiveURL.path,
            "--"
        ] + uniqueSources.map(\.lastPathComponent)
        let commandResult = try runCommand(
            .createZIP,
            executableURL: Self.zipExecutableURL,
            arguments: arguments,
            currentDirectoryURL: sharedParent,
            limits: StructuredCommandLimits(
                timeout: safetyLimits.operationTimeout,
                maximumCapturedOutputBytes: safetyLimits.maximumListingBytes,
                monitoredDirectoryURL: isolatedStagingURL,
                maximumMaterializedBytes: archiveBudget,
                monitoredVolumeURL: temporaryVolumeURL,
                minimumAvailableCapacityBytes: safetyLimits
                    .minimumFreeSpaceReserveBytes
            )
        )
        guard commandResult.terminationStatus == 0,
              fileManager.fileExists(atPath: temporaryArchiveURL.path) else {
            throw ArchiveServiceError.commandFailed(
                command: .createZIP,
                status: commandResult.terminationStatus
            )
        }
        let archiveUsage = try measuredFileTreeUsage(at: isolatedStagingURL)
        guard archiveUsage.materializedBytes <= archiveBudget else {
            throw ArchiveServiceError.archiveDataLimitExceeded(
                maximumBytes: archiveBudget
            )
        }

        let destinationSharesStagingVolume = try sameVolume(
            temporaryVolumeURL,
            destinationDirectory
        )
        if !destinationSharesStagingVolume {
            try requireCapacityToCopy(
                archiveUsage.materializedBytes,
                to: destinationDirectory
            )
        }

        let preferredName = uniqueSources.count == 1
            ? uniqueSources[0].lastPathComponent + ".zip"
            : "Archive.zip"
        let finalURL = try moveItemWithoutOverwrite(
            at: temporaryArchiveURL,
            toDirectory: destinationDirectory,
            preferredName: preferredName,
            itemIsDirectory: false
        )
        return ArchiveCreationResult(
            sourceURLs: uniqueSources,
            archiveURL: finalURL
        )
    }

    @discardableResult
    public func extract(
        url archiveURL: URL,
        destinationDirectory: URL
    ) throws -> ArchiveExtractionResult {
        let fileManager = FileManager.default
        var archiveIsDirectory = ObjCBool(false)
        guard fileManager.fileExists(
            atPath: archiveURL.path,
            isDirectory: &archiveIsDirectory
        ) else {
            throw ArchiveServiceError.archiveDoesNotExist(archiveURL)
        }
        guard !archiveIsDirectory.boolValue else {
            throw ArchiveServiceError.archiveIsNotAFile(archiveURL)
        }
        guard ArchiveFormat.detect(from: archiveURL) != nil else {
            throw ArchiveServiceError.unsupportedArchive(archiveURL)
        }
        try validateDestination(destinationDirectory)
        try validateEntryListing(of: archiveURL)

        let extractionBudget = try makeExtractionBudget(
            stagingParentURL: fileManager.temporaryDirectory,
            destinationDirectory: destinationDirectory
        )

        let isolatedStagingURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                "MagicRightExtraction-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: isolatedStagingURL,
            withIntermediateDirectories: false
        )
        defer { try? fileManager.removeItem(at: isolatedStagingURL) }

        let extractResult = try runCommand(
            .extract,
            executableURL: Self.tarExecutableURL,
            arguments: [
                "-xf",
                archiveURL.standardizedFileURL.path,
                "-C",
                isolatedStagingURL.path
            ],
            currentDirectoryURL: nil,
            limits: StructuredCommandLimits(
                timeout: safetyLimits.operationTimeout,
                maximumCapturedOutputBytes: safetyLimits.maximumListingBytes,
                monitoredDirectoryURL: isolatedStagingURL,
                maximumMaterializedBytes: extractionBudget,
                maximumMaterializedItemCount: safetyLimits.maximumEntryCount,
                monitoredVolumeURL: isolatedStagingURL,
                minimumAvailableCapacityBytes: safetyLimits
                    .minimumFreeSpaceReserveBytes
            )
        )
        guard extractResult.terminationStatus == 0 else {
            throw ArchiveServiceError.commandFailed(
                command: .extract,
                status: extractResult.terminationStatus
            )
        }
        try auditExtractedTree(at: isolatedStagingURL)
        let extractedUsage: FileTreeUsage
        do {
            extractedUsage = try LocalStructuredCommandRunner.fileTreeUsage(
                at: isolatedStagingURL
            )
        } catch {
            throw ArchiveServiceError.unsafeExtractedItem(isolatedStagingURL)
        }
        guard extractedUsage.itemCount <= safetyLimits.maximumEntryCount else {
            throw ArchiveServiceError.archiveEntryLimitExceeded(
                maximum: safetyLimits.maximumEntryCount
            )
        }
        guard extractedUsage.materializedBytes <= extractionBudget else {
            throw ArchiveServiceError.expandedDataLimitExceeded(
                maximumBytes: extractionBudget
            )
        }
        try requireCapacityToCopy(
            extractedUsage.materializedBytes,
            to: destinationDirectory
        )

        // Copy the audited tree to a hidden directory on the destination
        // volume, then rename it. This keeps the visible result atomic even
        // when /tmp and the destination are on different volumes.
        let destinationStagingURL = destinationDirectory.appendingPathComponent(
            ".magic-right-extraction-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: destinationStagingURL) }
        try fileManager.copyItem(at: isolatedStagingURL, to: destinationStagingURL)

        let finalURL = try moveItemWithoutOverwrite(
            at: destinationStagingURL,
            toDirectory: destinationDirectory,
            preferredName: extractionDirectoryName(for: archiveURL),
            itemIsDirectory: true
        )
        return ArchiveExtractionResult(
            archiveURL: archiveURL,
            destinationDirectoryURL: finalURL
        )
    }

    private func validateDestination(_ destinationURL: URL) throws {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(
            atPath: destinationURL.path,
            isDirectory: &isDirectory
        ) else {
            throw ArchiveServiceError.destinationDoesNotExist(destinationURL)
        }
        guard isDirectory.boolValue else {
            throw ArchiveServiceError.destinationIsNotDirectory(destinationURL)
        }
    }

    private func validateEntryListing(of archiveURL: URL) throws {
        let result = try runCommand(
            .listEntries,
            executableURL: Self.tarExecutableURL,
            arguments: ["-tf", archiveURL.standardizedFileURL.path],
            currentDirectoryURL: nil,
            limits: StructuredCommandLimits(
                timeout: safetyLimits.listingTimeout,
                maximumCapturedOutputBytes: safetyLimits.maximumListingBytes
            )
        )
        guard result.terminationStatus == 0 else {
            throw ArchiveServiceError.commandFailed(
                command: .listEntries,
                status: result.terminationStatus
            )
        }
        guard let output = String(data: result.standardOutput, encoding: .utf8) else {
            throw ArchiveServiceError.invalidArchiveListing
        }
        var entries = output.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        if entries.last == "" {
            entries.removeLast()
        }
        guard entries.count <= safetyLimits.maximumEntryCount else {
            throw ArchiveServiceError.archiveEntryLimitExceeded(
                maximum: safetyLimits.maximumEntryCount
            )
        }
        for entry in entries where !Self.isSafeArchiveEntry(entry) {
            throw ArchiveServiceError.unsafeArchiveEntry(entry)
        }
    }

    static func isSafeArchiveEntry(_ entry: String) -> Bool {
        guard !entry.isEmpty,
              !entry.hasPrefix("/"),
              !entry.hasPrefix("\\"),
              !entry.contains("\\"),
              !entry.contains("\0") else {
            return false
        }
        let components = entry.split(separator: "/", omittingEmptySubsequences: false)
        if let first = components.first,
           first.count >= 2,
           first[first.index(after: first.startIndex)] == ":",
           first.first?.isASCII == true,
           first.first?.isLetter == true {
            return false
        }
        for (index, component) in components.enumerated() {
            if component == ".." {
                return false
            }
            // Empty components are permitted only for a trailing directory
            // slash. `.` is common in archives produced as `./file`.
            if component.isEmpty, index != components.index(before: components.endIndex) {
                return false
            }
        }
        return true
    }

    private func auditExtractedTree(at rootURL: URL) throws {
        let fileManager = FileManager.default
        var enumerationFailureURL: URL?
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { url, _ in
                enumerationFailureURL = url
                return false
            }
        ) else {
            throw ArchiveServiceError.unsafeExtractedItem(rootURL)
        }
        while let itemURL = enumerator.nextObject() as? URL {
            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try fileManager.attributesOfItem(atPath: itemURL.path)
            } catch {
                throw ArchiveServiceError.unsafeExtractedItem(itemURL)
            }
            guard let type = attributes[.type] as? FileAttributeType,
                  type == .typeDirectory
                    || type == .typeRegular
                    || type == .typeSymbolicLink else {
                throw ArchiveServiceError.unsafeExtractedItem(itemURL)
            }
            if type == .typeSymbolicLink {
                let target: String
                do {
                    target = try fileManager.destinationOfSymbolicLink(
                        atPath: itemURL.path
                    )
                } catch {
                    throw ArchiveServiceError.unsafeExtractedItem(itemURL)
                }
                let targetURL = target.hasPrefix("/")
                    ? URL(fileURLWithPath: target)
                    : itemURL.deletingLastPathComponent()
                        .appendingPathComponent(target)
                guard Self.isEqualOrDescendant(
                    targetURL.standardizedFileURL,
                    of: rootURL.standardizedFileURL
                ), Self.isEqualOrDescendant(
                    targetURL.standardizedFileURL.resolvingSymlinksInPath(),
                    of: rootURL.standardizedFileURL.resolvingSymlinksInPath()
                ) else {
                    throw ArchiveServiceError.unsafeExtractedItem(itemURL)
                }
            }
        }
        if let enumerationFailureURL {
            throw ArchiveServiceError.unsafeExtractedItem(enumerationFailureURL)
        }
    }

    private func runCommand(
        _ command: ArchiveCommand,
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        limits: StructuredCommandLimits
    ) throws -> StructuredCommandResult {
        do {
            return try commandRunner.run(
                executableURL: executableURL,
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL,
                limits: limits
            )
        } catch let error as StructuredCommandRunnerError {
            switch error {
            case .timedOut:
                throw ArchiveServiceError.commandTimedOut(command)
            case .capturedOutputLimitExceeded:
                throw ArchiveServiceError.commandOutputLimitExceeded(command)
            case .materializedDataLimitExceeded:
                let maximumBytes = limits.maximumMaterializedBytes
                    ?? safetyLimits.maximumExpandedBytes
                if command == .createZIP {
                    throw ArchiveServiceError.archiveDataLimitExceeded(
                        maximumBytes: maximumBytes
                    )
                }
                throw ArchiveServiceError.expandedDataLimitExceeded(
                    maximumBytes: maximumBytes
                )
            case .materializedItemLimitExceeded:
                throw ArchiveServiceError.archiveEntryLimitExceeded(
                    maximum: limits.maximumMaterializedItemCount
                        ?? safetyLimits.maximumEntryCount
                )
            case .availableCapacityLimitReached:
                throw ArchiveServiceError.insufficientAvailableCapacity(
                    limits.monitoredVolumeURL ?? FileManager.default.temporaryDirectory
                )
            case .resourceMonitoringFailed:
                throw ArchiveServiceError.capacityCheckFailed(
                    limits.monitoredVolumeURL ?? FileManager.default.temporaryDirectory
                )
            }
        } catch {
            throw ArchiveServiceError.commandCouldNotRun(command)
        }
    }

    private func makeArchiveBudget(
        stagingVolumeURL: URL,
        destinationDirectory: URL
    ) throws -> UInt64 {
        let stagingCapacity = try availableCapacity(at: stagingVolumeURL)
        let destinationCapacity = try availableCapacity(at: destinationDirectory)
        let reserve = safetyLimits.minimumFreeSpaceReserveBytes
        guard stagingCapacity > reserve else {
            throw ArchiveServiceError.insufficientAvailableCapacity(
                stagingVolumeURL
            )
        }
        guard destinationCapacity > reserve else {
            throw ArchiveServiceError.insufficientAvailableCapacity(
                destinationDirectory
            )
        }

        let capacityBudget = min(
            stagingCapacity - reserve,
            destinationCapacity - reserve
        )
        let budget = min(safetyLimits.maximumArchiveBytes, capacityBudget)
        guard budget > 0 else {
            throw ArchiveServiceError.insufficientAvailableCapacity(
                destinationDirectory
            )
        }
        return budget
    }

    private func makeExtractionBudget(
        stagingParentURL: URL,
        destinationDirectory: URL
    ) throws -> UInt64 {
        let stagingCapacity = try availableCapacity(at: stagingParentURL)
        let destinationCapacity = try availableCapacity(at: destinationDirectory)
        let reserve = safetyLimits.minimumFreeSpaceReserveBytes
        guard stagingCapacity > reserve else {
            throw ArchiveServiceError.insufficientAvailableCapacity(stagingParentURL)
        }
        guard destinationCapacity > reserve else {
            throw ArchiveServiceError.insufficientAvailableCapacity(destinationDirectory)
        }

        let sameVolume = try sameVolume(
            stagingParentURL,
            destinationDirectory
        )

        let stagingBudget = stagingCapacity - reserve
        let destinationBudget = destinationCapacity - reserve
        let capacityBudget = sameVolume
            ? min(stagingBudget, destinationBudget) / 2
            : min(stagingBudget, destinationBudget)
        let budget = min(safetyLimits.maximumExpandedBytes, capacityBudget)
        guard budget > 0 else {
            throw ArchiveServiceError.insufficientAvailableCapacity(destinationDirectory)
        }
        return budget
    }

    private func requireCapacityToCopy(
        _ materializedBytes: UInt64,
        to destinationDirectory: URL
    ) throws {
        let (requiredCapacity, overflow) = materializedBytes.addingReportingOverflow(
            safetyLimits.minimumFreeSpaceReserveBytes
        )
        guard !overflow,
              try availableCapacity(at: destinationDirectory) >= requiredCapacity else {
            throw ArchiveServiceError.insufficientAvailableCapacity(destinationDirectory)
        }
    }

    private func availableCapacity(at url: URL) throws -> UInt64 {
        do {
            return try fileSystemMetrics.availableCapacity(url)
        } catch {
            throw ArchiveServiceError.capacityCheckFailed(url)
        }
    }

    private func measuredFileTreeUsage(at url: URL) throws -> FileTreeUsage {
        do {
            return try fileSystemMetrics.fileTreeUsage(url)
        } catch {
            throw ArchiveServiceError.capacityCheckFailed(url)
        }
    }

    private func sameVolume(_ firstURL: URL, _ secondURL: URL) throws -> Bool {
        do {
            return try fileSystemMetrics.isSameVolume(firstURL, secondURL)
        } catch {
            throw ArchiveServiceError.capacityCheckFailed(secondURL)
        }
    }

    private func moveItemWithoutOverwrite(
        at sourceURL: URL,
        toDirectory destinationDirectory: URL,
        preferredName: String,
        itemIsDirectory: Bool
    ) throws -> URL {
        let fileManager = FileManager.default
        for attempt in 1...Self.maximumNameAttempts {
            let candidateName = Self.candidateName(
                preferredName,
                itemIsDirectory: itemIsDirectory,
                attempt: attempt
            )
            let candidateURL = destinationDirectory.appendingPathComponent(
                candidateName,
                isDirectory: itemIsDirectory
            )
            guard !fileManager.fileExists(atPath: candidateURL.path) else {
                continue
            }
            do {
                try fileManager.moveItem(at: sourceURL, to: candidateURL)
                return candidateURL
            } catch where Self.isFileExistsError(error) {
                continue
            }
        }
        throw ArchiveServiceError.noAvailableName(destinationDirectory)
    }

    private static func candidateName(
        _ preferredName: String,
        itemIsDirectory: Bool,
        attempt: Int
    ) -> String {
        guard attempt > 1 else { return preferredName }
        if itemIsDirectory {
            return preferredName + " \(attempt)"
        }
        let url = URL(fileURLWithPath: preferredName)
        let pathExtension = url.pathExtension
        guard !pathExtension.isEmpty else {
            return preferredName + " \(attempt)"
        }
        return url.deletingPathExtension().lastPathComponent
            + " \(attempt)."
            + pathExtension
    }

    private func extractionDirectoryName(for archiveURL: URL) -> String {
        var result = archiveURL.lastPathComponent
        let lowercased = result.lowercased()
        if lowercased.hasSuffix(".tar.gz") {
            result.removeLast(7)
        } else if lowercased.hasSuffix(".tgz") {
            result.removeLast(4)
        } else if lowercased.hasSuffix(".tar") || lowercased.hasSuffix(".zip") {
            result.removeLast(4)
        }
        return result.isEmpty ? "Extracted Archive" : result
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
