import Foundation
import Darwin

struct StructuredCommandResult: Equatable, Sendable {
    let terminationStatus: Int32
    let standardOutput: Data
    let standardError: Data
}

protocol StructuredCommandRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?
    ) throws -> StructuredCommandResult
}

struct StructuredCommandLimits: Equatable, Sendable {
    let timeout: TimeInterval
    let maximumCapturedOutputBytes: UInt64
    let monitoredDirectoryURL: URL?
    let maximumMaterializedBytes: UInt64?
    let maximumMaterializedItemCount: Int?
    let monitoredVolumeURL: URL?
    let minimumAvailableCapacityBytes: UInt64?

    init(
        timeout: TimeInterval,
        maximumCapturedOutputBytes: UInt64,
        monitoredDirectoryURL: URL? = nil,
        maximumMaterializedBytes: UInt64? = nil,
        maximumMaterializedItemCount: Int? = nil,
        monitoredVolumeURL: URL? = nil,
        minimumAvailableCapacityBytes: UInt64? = nil
    ) {
        precondition(timeout > 0)
        precondition(maximumCapturedOutputBytes > 0)
        precondition(maximumMaterializedBytes == nil || monitoredDirectoryURL != nil)
        precondition(maximumMaterializedItemCount == nil || monitoredDirectoryURL != nil)
        precondition(minimumAvailableCapacityBytes == nil || monitoredVolumeURL != nil)
        self.timeout = timeout
        self.maximumCapturedOutputBytes = maximumCapturedOutputBytes
        self.monitoredDirectoryURL = monitoredDirectoryURL
        self.maximumMaterializedBytes = maximumMaterializedBytes
        self.maximumMaterializedItemCount = maximumMaterializedItemCount
        self.monitoredVolumeURL = monitoredVolumeURL
        self.minimumAvailableCapacityBytes = minimumAvailableCapacityBytes
    }

    static let standard = StructuredCommandLimits(
        timeout: 120,
        maximumCapturedOutputBytes: 16 * 1_024 * 1_024
    )
}

enum StructuredCommandRunnerError: Error, Equatable, Sendable {
    case timedOut
    case capturedOutputLimitExceeded
    case materializedDataLimitExceeded
    case materializedItemLimitExceeded
    case availableCapacityLimitReached
    case resourceMonitoringFailed
}

struct FileTreeUsage: Equatable, Sendable {
    let itemCount: Int
    let materializedBytes: UInt64
}

protocol LimitedStructuredCommandRunning: StructuredCommandRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        limits: StructuredCommandLimits
    ) throws -> StructuredCommandResult
}

extension StructuredCommandRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        limits: StructuredCommandLimits
    ) throws -> StructuredCommandResult {
        guard let limitedRunner = self as? any LimitedStructuredCommandRunning else {
            return try run(
                executableURL: executableURL,
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL
            )
        }
        return try limitedRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            limits: limits
        )
    }
}

/// Runs a fixed executable with an argument vector. No argument is interpreted
/// by a shell. Output is redirected to private files so a verbose subprocess
/// cannot deadlock while the parent waits for it to finish.
struct LocalStructuredCommandRunner: LimitedStructuredCommandRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil
    ) throws -> StructuredCommandResult {
        try run(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            limits: .standard
        )
    }

    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        limits: StructuredCommandLimits
    ) throws -> StructuredCommandResult {
        let fileManager = FileManager.default
        let captureDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(
                "MagicRightCommand-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: captureDirectory,
            withIntermediateDirectories: false
        )
        defer { try? fileManager.removeItem(at: captureDirectory) }

        let standardOutputURL = captureDirectory.appendingPathComponent("stdout")
        let standardErrorURL = captureDirectory.appendingPathComponent("stderr")
        guard fileManager.createFile(atPath: standardOutputURL.path, contents: nil),
              fileManager.createFile(atPath: standardErrorURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let standardOutputHandle = try FileHandle(forWritingTo: standardOutputURL)
        let standardErrorHandle = try FileHandle(forWritingTo: standardErrorURL)
        defer {
            try? standardOutputHandle.close()
            try? standardErrorHandle.close()
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = standardOutputHandle
        process.standardError = standardErrorHandle
        try process.run()
        let startedAt = Date()
        var nextResourceCheck = startedAt
        while process.isRunning {
            do {
                try Self.checkCapturedOutput(
                    standardOutputURL: standardOutputURL,
                    standardErrorURL: standardErrorURL,
                    limit: limits.maximumCapturedOutputBytes
                )
                if Date().timeIntervalSince(startedAt) > limits.timeout {
                    throw StructuredCommandRunnerError.timedOut
                }
                if Date() >= nextResourceCheck {
                    try Self.checkMonitoredResources(limits)
                    nextResourceCheck = Date().addingTimeInterval(0.25)
                }
            } catch {
                Self.stop(process)
                throw error
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        process.waitUntilExit()
        try standardOutputHandle.synchronize()
        try standardErrorHandle.synchronize()
        try Self.checkCapturedOutput(
            standardOutputURL: standardOutputURL,
            standardErrorURL: standardErrorURL,
            limit: limits.maximumCapturedOutputBytes
        )
        try Self.checkMonitoredResources(limits)

        return StructuredCommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: try Data(contentsOf: standardOutputURL),
            standardError: try Data(contentsOf: standardErrorURL)
        )
    }

    static func fileTreeUsage(at rootURL: URL) throws -> FileTreeUsage {
        let fileManager = FileManager.default
        var itemCount = 0
        var materializedBytes: UInt64 = 0
        var enumerationFailed = false
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, _ in
                enumerationFailed = true
                return false
            }
        ) else {
            throw StructuredCommandRunnerError.resourceMonitoringFailed
        }
        while let itemURL = enumerator.nextObject() as? URL {
            itemCount += 1
            var itemStatus = stat()
            guard lstat(itemURL.path, &itemStatus) == 0 else {
                throw StructuredCommandRunnerError.resourceMonitoringFailed
            }
            let logicalBytes = itemStatus.st_size > 0
                ? UInt64(itemStatus.st_size)
                : 0
            let allocatedBytes = itemStatus.st_blocks > 0
                ? UInt64(itemStatus.st_blocks) * 512
                : 0
            let itemBytes = max(logicalBytes, allocatedBytes)
            let (updatedBytes, overflow) = materializedBytes.addingReportingOverflow(
                itemBytes
            )
            guard !overflow else {
                throw StructuredCommandRunnerError.materializedDataLimitExceeded
            }
            materializedBytes = updatedBytes
        }
        guard !enumerationFailed else {
            throw StructuredCommandRunnerError.resourceMonitoringFailed
        }
        return FileTreeUsage(
            itemCount: itemCount,
            materializedBytes: materializedBytes
        )
    }

    static func availableCapacity(at url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfFileSystem(
            forPath: url.path
        )
        guard let freeSize = attributes[.systemFreeSize] as? NSNumber,
              freeSize.int64Value >= 0 else {
            throw StructuredCommandRunnerError.resourceMonitoringFailed
        }
        return freeSize.uint64Value
    }

    private static func checkCapturedOutput(
        standardOutputURL: URL,
        standardErrorURL: URL,
        limit: UInt64
    ) throws {
        let fileManager = FileManager.default
        let outputSize = try fileSize(at: standardOutputURL, fileManager: fileManager)
        let errorSize = try fileSize(at: standardErrorURL, fileManager: fileManager)
        let (combinedSize, overflow) = outputSize.addingReportingOverflow(errorSize)
        guard !overflow, combinedSize <= limit else {
            throw StructuredCommandRunnerError.capturedOutputLimitExceeded
        }
    }

    private static func fileSize(
        at url: URL,
        fileManager: FileManager
    ) throws -> UInt64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber,
              size.int64Value >= 0 else {
            throw StructuredCommandRunnerError.resourceMonitoringFailed
        }
        return size.uint64Value
    }

    private static func checkMonitoredResources(
        _ limits: StructuredCommandLimits
    ) throws {
        if let rootURL = limits.monitoredDirectoryURL {
            let usage = try fileTreeUsage(at: rootURL)
            if let byteLimit = limits.maximumMaterializedBytes,
               usage.materializedBytes > byteLimit {
                throw StructuredCommandRunnerError.materializedDataLimitExceeded
            }
            if let itemLimit = limits.maximumMaterializedItemCount,
               usage.itemCount > itemLimit {
                throw StructuredCommandRunnerError.materializedItemLimitExceeded
            }
        }
        if let volumeURL = limits.monitoredVolumeURL,
           let minimumCapacity = limits.minimumAvailableCapacityBytes,
           try availableCapacity(at: volumeURL) < minimumCapacity {
            throw StructuredCommandRunnerError.availableCapacityLimitReached
        }
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else {
            process.waitUntilExit()
            return
        }
        process.terminate()
        let gracefulDeadline = Date().addingTimeInterval(0.5)
        while process.isRunning, Date() < gracefulDeadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }
}
