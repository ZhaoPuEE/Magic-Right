import Foundation
import Testing
@testable import SuperRightCore

@Suite("Safe archive operations")
struct ArchiveServiceTests {
    @Test("Only supported archive extensions are offered")
    func supportedFormats() {
        let service = ArchiveService()
        #expect(service.canExtract(URL(fileURLWithPath: "/tmp/a.zip")))
        #expect(service.canExtract(URL(fileURLWithPath: "/tmp/a.TAR")))
        #expect(service.canExtract(URL(fileURLWithPath: "/tmp/a.tar.gz")))
        #expect(service.canExtract(URL(fileURLWithPath: "/tmp/a.tgz")))
        #expect(!service.canExtract(URL(fileURLWithPath: "/tmp/a.gz")))
        #expect(!service.canExtract(URL(fileURLWithPath: "/tmp/a.dmg")))
    }

    @Test("Traversal and absolute archive entries are rejected")
    func rejectsUnsafeEntryNames() {
        let unsafe = [
            "../escape",
            "folder/../../escape",
            "/absolute/path",
            "\\windows\\path",
            "C:/windows/path",
            "folder//file",
            "folder//"
        ]
        for entry in unsafe {
            #expect(!ArchiveService.isSafeArchiveEntry(entry))
        }
        let safe = ["file", "folder/file", "./folder/file", "folder/"]
        for entry in safe {
            #expect(ArchiveService.isSafeArchiveEntry(entry))
        }
    }

    @Test("ZIP creation preserves sources and never overwrites")
    func createsCollisionSafeZIP() throws {
        try withArchiveDirectories { source, destination in
            let item = source.appendingPathComponent("report.txt")
            try Data("payload".utf8).write(to: item)
            let existing = destination.appendingPathComponent("report.txt.zip")
            try Data("keep".utf8).write(to: existing)

            let result = try ArchiveService().archive(
                urls: [item, item],
                destinationDirectory: destination
            )

            #expect(result.sourceURLs == [item])
            #expect(result.archiveURL.lastPathComponent == "report.txt 2.zip")
            #expect(try Data(contentsOf: existing) == Data("keep".utf8))
            #expect(try Data(contentsOf: item) == Data("payload".utf8))
            #expect(FileManager.default.fileExists(atPath: result.archiveURL.path))
        }
    }

    @Test("Shell-looking filenames remain inert structured arguments")
    func shellLookingNamesAreInert() throws {
        try withArchiveDirectories { source, destination in
            let item = source.appendingPathComponent("--evil; $(touch pwned)")
            try Data("safe".utf8).write(to: item)

            let result = try ArchiveService().archive(
                urls: [item],
                destinationDirectory: destination
            )

            #expect(FileManager.default.fileExists(atPath: result.archiveURL.path))
            #expect(!FileManager.default.fileExists(atPath: source.appendingPathComponent("pwned").path))
        }
    }

    @Test("ZIP creation preserves a broken symbolic link as an item")
    func archivesBrokenSymbolicLink() throws {
        try withArchiveDirectories { source, destination in
            let missingTarget = source.appendingPathComponent("missing")
            let brokenLink = source.appendingPathComponent("broken-link")
            try FileManager.default.createSymbolicLink(
                at: brokenLink,
                withDestinationURL: missingTarget
            )

            let result = try ArchiveService().archive(
                urls: [brokenLink],
                destinationDirectory: destination
            )

            #expect(FileManager.default.fileExists(atPath: result.archiveURL.path))
            #expect(
                (try? FileManager.default.attributesOfItem(
                    atPath: brokenLink.path
                ))?[.type] as? FileAttributeType == .typeSymbolicLink
            )
        }
    }

    @Test("ZIP creation stops at its configured materialized-size budget")
    func zipCreationSizeBudget() throws {
        try withArchiveDirectories { source, destination in
            let item = source.appendingPathComponent("incompressible.bin")
            try Data((0..<4_096).map { UInt8(truncatingIfNeeded: $0) }).write(
                to: item
            )
            let service = ArchiveService(
                commandRunner: LocalStructuredCommandRunner(),
                safetyLimits: testArchiveLimits(
                    maximumArchiveBytes: 1,
                    minimumFreeSpaceReserveBytes: 0
                )
            )

            #expect(
                throws: ArchiveServiceError.archiveDataLimitExceeded(
                    maximumBytes: 1
                )
            ) {
                try service.archive(
                    urls: [item],
                    destinationDirectory: destination
                )
            }
            #expect(FileManager.default.fileExists(atPath: item.path))
            #expect(
                !FileManager.default.fileExists(
                    atPath: destination.appendingPathComponent(
                        "incompressible.bin.zip"
                    ).path
                )
            )
        }
    }

    @Test("ZIP creation fails before launch when either volume lacks its reserve")
    func zipCreationReservePreflight() throws {
        try withArchiveDirectories { source, destination in
            let item = source.appendingPathComponent("payload")
            try Data("value".utf8).write(to: item)
            let runner = ArchiveRecordingRunner(results: [])
            let cases: [(temporary: UInt64, destination: UInt64, errorURL: URL)] = [
                (512, 4_096, FileManager.default.temporaryDirectory),
                (4_096, 512, destination)
            ]
            for testCase in cases {
                let metrics = ArchiveFileSystemMetrics(
                    availableCapacity: { url in
                        url.standardizedFileURL == destination.standardizedFileURL
                            ? testCase.destination
                            : testCase.temporary
                    },
                    fileTreeUsage: { _ in
                        FileTreeUsage(itemCount: 1, materializedBytes: 1)
                    },
                    isSameVolume: { _, _ in true }
                )
                let service = ArchiveService(
                    commandRunner: runner,
                    safetyLimits: testArchiveLimits(
                        minimumFreeSpaceReserveBytes: 512
                    ),
                    fileSystemMetrics: metrics
                )

                #expect(
                    throws: ArchiveServiceError.insufficientAvailableCapacity(
                        testCase.errorURL
                    )
                ) {
                    try service.archive(
                        urls: [item],
                        destinationDirectory: destination
                    )
                }
            }
            #expect(runner.invocations.isEmpty)
            #expect(FileManager.default.fileExists(atPath: item.path))
        }
    }

    @Test("ZIP creation forwards byte and free-space limits to the process runner")
    func zipCreationForwardsResourceLimits() throws {
        try withArchiveDirectories { source, destination in
            let item = source.appendingPathComponent("payload")
            try Data("value".utf8).write(to: item)
            let runner = ArchiveLimitRecordingRunner()
            let service = ArchiveService(
                commandRunner: runner,
                safetyLimits: testArchiveLimits(
                    maximumArchiveBytes: 4_096,
                    minimumFreeSpaceReserveBytes: 512
                ),
                fileSystemMetrics: ArchiveFileSystemMetrics(
                    availableCapacity: { _ in 16_384 },
                    fileTreeUsage: { _ in
                        FileTreeUsage(itemCount: 1, materializedBytes: 3)
                    },
                    isSameVolume: { _, _ in true }
                )
            )

            let result = try service.archive(
                urls: [item],
                destinationDirectory: destination
            )

            #expect(FileManager.default.fileExists(atPath: result.archiveURL.path))
            let invocation = try #require(runner.invocations.first)
            #expect(invocation.limits.maximumMaterializedBytes == 4_096)
            #expect(invocation.limits.maximumMaterializedItemCount == nil)
            #expect(
                invocation.limits.minimumAvailableCapacityBytes == 512
            )
            #expect(
                invocation.limits.monitoredDirectoryURL?
                    .deletingLastPathComponent().standardizedFileURL
                    == invocation.limits.monitoredVolumeURL?.standardizedFileURL
            )
            let archiveArgument = try #require(
                invocation.arguments.dropFirst(3).first
            )
            #expect(
                archiveArgument == invocation.limits.monitoredDirectoryURL?
                    .appendingPathComponent("archive.zip").path
            )
        }
    }

    @Test("ZIP, TAR, and TAR.GZ extract into isolated wrapper directories")
    func extractsCommonFormats() throws {
        try withArchiveDirectories { source, destination in
            let payload = source.appendingPathComponent("payload", isDirectory: true)
            try FileManager.default.createDirectory(
                at: payload,
                withIntermediateDirectories: false
            )
            try Data("hello".utf8).write(
                to: payload.appendingPathComponent("hello.txt")
            )

            let zip = try ArchiveService().archive(
                urls: [payload],
                destinationDirectory: source
            ).archiveURL
            let tar = source.appendingPathComponent("sample.tar")
            let tarGzip = source.appendingPathComponent("sample.tar.gz")
            try runTestCommand(
                executable: "/usr/bin/tar",
                arguments: ["-cf", tar.path, "-C", source.path, "payload"]
            )
            try runTestCommand(
                executable: "/usr/bin/tar",
                arguments: ["-czf", tarGzip.path, "-C", source.path, "payload"]
            )

            for archiveURL in [zip, tar, tarGzip] {
                let result = try ArchiveService().extract(
                    url: archiveURL,
                    destinationDirectory: destination
                )
                let extractedFile = result.destinationDirectoryURL
                    .appendingPathComponent("payload/hello.txt")
                #expect(
                    try String(contentsOf: extractedFile, encoding: .utf8)
                        == "hello"
                )
            }
        }
    }

    @Test("Extraction collision allocates a new wrapper and preserves old data")
    func extractionDoesNotOverwrite() throws {
        try withArchiveDirectories { source, destination in
            let item = source.appendingPathComponent("Project", isDirectory: true)
            try FileManager.default.createDirectory(
                at: item,
                withIntermediateDirectories: false
            )
            try Data("new".utf8).write(to: item.appendingPathComponent("data"))
            let archiveURL = try ArchiveService().archive(
                urls: [item],
                destinationDirectory: source
            ).archiveURL
            let existing = destination.appendingPathComponent("Project", isDirectory: true)
            try FileManager.default.createDirectory(
                at: existing,
                withIntermediateDirectories: false
            )
            try Data("old".utf8).write(to: existing.appendingPathComponent("data"))

            let result = try ArchiveService().extract(
                url: archiveURL,
                destinationDirectory: destination
            )

            #expect(result.destinationDirectoryURL.lastPathComponent == "Project 2")
            #expect(
                try String(
                    contentsOf: existing.appendingPathComponent("data"),
                    encoding: .utf8
                ) == "old"
            )
        }
    }

    @Test("Unsafe listing stops before extraction")
    func unsafeListingStopsEarly() throws {
        try withArchiveDirectories { source, destination in
            let archiveURL = source.appendingPathComponent("hostile.zip")
            try Data("placeholder".utf8).write(to: archiveURL)
            let runner = ArchiveRecordingRunner(results: [
                StructuredCommandResult(
                    terminationStatus: 0,
                    standardOutput: Data("../escape\n".utf8),
                    standardError: Data()
                )
            ])
            let service = ArchiveService(commandRunner: runner)

            #expect(throws: ArchiveServiceError.unsafeArchiveEntry("../escape")) {
                try service.extract(
                    url: archiveURL,
                    destinationDirectory: destination
                )
            }
            #expect(runner.invocations.count == 1)
        }
    }

    @Test("Entry count is bounded before extraction")
    func entryCountLimit() throws {
        try withArchiveDirectories { source, destination in
            let archiveURL = source.appendingPathComponent("many.zip")
            try Data("placeholder".utf8).write(to: archiveURL)
            let runner = ArchiveRecordingRunner(results: [
                StructuredCommandResult(
                    terminationStatus: 0,
                    standardOutput: Data("one\ntwo\nthree\n".utf8),
                    standardError: Data()
                )
            ])
            let service = ArchiveService(
                commandRunner: runner,
                safetyLimits: testArchiveLimits(maximumEntryCount: 2)
            )

            #expect(throws: ArchiveServiceError.archiveEntryLimitExceeded(maximum: 2)) {
                try service.extract(
                    url: archiveURL,
                    destinationDirectory: destination
                )
            }
            #expect(runner.invocations.count == 1)
        }
    }

    @Test("Listing output is bounded by the real process runner")
    func listingOutputLimit() throws {
        try withArchiveDirectories { source, destination in
            let payload = source.appendingPathComponent("payload")
            try Data("value".utf8).write(to: payload)
            let archiveURL = source.appendingPathComponent("payload.tar")
            try runTestCommand(
                executable: "/usr/bin/tar",
                arguments: ["-cf", archiveURL.path, "-C", source.path, "payload"]
            )
            let service = ArchiveService(
                commandRunner: LocalStructuredCommandRunner(),
                safetyLimits: testArchiveLimits(maximumListingBytes: 2)
            )

            #expect(
                throws: ArchiveServiceError.commandOutputLimitExceeded(.listEntries)
            ) {
                try service.extract(
                    url: archiveURL,
                    destinationDirectory: destination
                )
            }
        }
    }

    @Test("Expanded data is cancelled at the configured budget")
    func expandedDataBudget() throws {
        try withArchiveDirectories { source, destination in
            let payload = source.appendingPathComponent("payload")
            try Data(repeating: 0x41, count: 4_096).write(to: payload)
            let archiveURL = source.appendingPathComponent("payload.tar")
            try runTestCommand(
                executable: "/usr/bin/tar",
                arguments: ["-cf", archiveURL.path, "-C", source.path, "payload"]
            )
            let service = ArchiveService(
                commandRunner: LocalStructuredCommandRunner(),
                safetyLimits: testArchiveLimits(
                    maximumExpandedBytes: 1,
                    minimumFreeSpaceReserveBytes: 0
                )
            )

            #expect(
                throws: ArchiveServiceError.expandedDataLimitExceeded(maximumBytes: 1)
            ) {
                try service.extract(
                    url: archiveURL,
                    destinationDirectory: destination
                )
            }
            #expect(
                !FileManager.default.fileExists(
                    atPath: destination.appendingPathComponent("payload").path
                )
            )
        }
    }

    @Test("Insufficient free-space reserve fails before extraction")
    func freeSpaceReserve() throws {
        try withArchiveDirectories { source, destination in
            let payload = source.appendingPathComponent("payload")
            try Data("value".utf8).write(to: payload)
            let archiveURL = source.appendingPathComponent("payload.tar")
            try runTestCommand(
                executable: "/usr/bin/tar",
                arguments: ["-cf", archiveURL.path, "-C", source.path, "payload"]
            )
            let service = ArchiveService(
                commandRunner: LocalStructuredCommandRunner(),
                safetyLimits: testArchiveLimits(
                    minimumFreeSpaceReserveBytes: UInt64.max
                )
            )

            #expect(
                throws: ArchiveServiceError.insufficientAvailableCapacity(
                    FileManager.default.temporaryDirectory
                )
            ) {
                try service.extract(
                    url: archiveURL,
                    destinationDirectory: destination
                )
            }
        }
    }

    @Test("Structured commands terminate on timeout and output overflow")
    func commandRunnerLimits() throws {
        let runner = LocalStructuredCommandRunner()
        #expect(throws: StructuredCommandRunnerError.timedOut) {
            try runner.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["2"],
                currentDirectoryURL: nil,
                limits: StructuredCommandLimits(
                    timeout: 0.05,
                    maximumCapturedOutputBytes: 1_024
                )
            )
        }
        #expect(throws: StructuredCommandRunnerError.capturedOutputLimitExceeded) {
            try runner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/yes"),
                arguments: ["bounded"],
                currentDirectoryURL: nil,
                limits: StructuredCommandLimits(
                    timeout: 2,
                    maximumCapturedOutputBytes: 1_024
                )
            )
        }
    }

    @Test("Command-runner resource enumeration fails closed")
    func resourceEnumerationFailsClosed() throws {
        try withArchiveDirectories { source, _ in
            let blocked = source.appendingPathComponent("blocked", isDirectory: true)
            try FileManager.default.createDirectory(
                at: blocked,
                withIntermediateDirectories: false
            )
            try Data("hidden".utf8).write(to: blocked.appendingPathComponent("item"))
            try FileManager.default.setAttributes(
                [.posixPermissions: 0],
                ofItemAtPath: blocked.path
            )
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o700],
                    ofItemAtPath: blocked.path
                )
            }

            #expect(throws: StructuredCommandRunnerError.resourceMonitoringFailed) {
                try LocalStructuredCommandRunner.fileTreeUsage(at: source)
            }
        }
    }

    @Test("An extracted symlink may not escape the staging tree")
    func rejectsEscapingSymlink() throws {
        try withArchiveDirectories { source, destination in
            let payload = source.appendingPathComponent("payload", isDirectory: true)
            try FileManager.default.createDirectory(
                at: payload,
                withIntermediateDirectories: false
            )
            try FileManager.default.createSymbolicLink(
                at: payload.appendingPathComponent("escape"),
                withDestinationURL: URL(fileURLWithPath: "../../outside")
            )
            let archiveURL = source.appendingPathComponent("links.tar")
            try runTestCommand(
                executable: "/usr/bin/tar",
                arguments: ["-cf", archiveURL.path, "-C", source.path, "payload"]
            )

            #expect(throws: (any Error).self) {
                try ArchiveService().extract(
                    url: archiveURL,
                    destinationDirectory: destination
                )
            }
            #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("links").path))
        }
    }

    @Test("Invalid endpoints fail before any mutation")
    func validatesEndpoints() throws {
        try withArchiveDirectories { source, destination in
            let first = source.appendingPathComponent("one")
            try Data().write(to: first)
            let otherParent = destination.appendingPathComponent("two")
            try Data().write(to: otherParent)

            #expect(throws: ArchiveServiceError.noSources) {
                try ArchiveService().archive(
                    urls: [],
                    destinationDirectory: destination
                )
            }
            #expect(throws: ArchiveServiceError.sourcesHaveDifferentParents) {
                try ArchiveService().archive(
                    urls: [first, otherParent],
                    destinationDirectory: destination
                )
            }
            let unsupported = source.appendingPathComponent("file.rar")
            try Data().write(to: unsupported)
            #expect(throws: ArchiveServiceError.unsupportedArchive(unsupported)) {
                try ArchiveService().extract(
                    url: unsupported,
                    destinationDirectory: destination
                )
            }
        }
    }
}

private final class ArchiveLimitRecordingRunner: LimitedStructuredCommandRunning,
    @unchecked Sendable {
    struct Invocation: Equatable {
        let executableURL: URL
        let arguments: [String]
        let currentDirectoryURL: URL?
        let limits: StructuredCommandLimits
    }

    private let lock = NSLock()
    private var recordedInvocations: [Invocation] = []

    var invocations: [Invocation] {
        lock.withLock { recordedInvocations }
    }

    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?
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
        guard let archivePath = arguments.dropFirst(3).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        try Data("zip".utf8).write(to: URL(fileURLWithPath: archivePath))
        lock.withLock {
            recordedInvocations.append(
                Invocation(
                    executableURL: executableURL,
                    arguments: arguments,
                    currentDirectoryURL: currentDirectoryURL,
                    limits: limits
                )
            )
        }
        return StructuredCommandResult(
            terminationStatus: 0,
            standardOutput: Data(),
            standardError: Data()
        )
    }
}

private final class ArchiveRecordingRunner: StructuredCommandRunning, @unchecked Sendable {
    struct Invocation: Equatable {
        let executableURL: URL
        let arguments: [String]
        let currentDirectoryURL: URL?
    }

    private let lock = NSLock()
    private var results: [StructuredCommandResult]
    private var recordedInvocations: [Invocation] = []

    var invocations: [Invocation] {
        lock.withLock { recordedInvocations }
    }

    init(results: [StructuredCommandResult]) {
        self.results = results
    }

    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?
    ) throws -> StructuredCommandResult {
        lock.withLock {
            recordedInvocations.append(
                Invocation(
                    executableURL: executableURL,
                    arguments: arguments,
                    currentDirectoryURL: currentDirectoryURL
                )
            )
            return results.removeFirst()
        }
    }
}

private func withArchiveDirectories(
    _ body: (URL, URL) throws -> Void
) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let source = root.appendingPathComponent("source", isDirectory: true)
    let destination = root.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(source, destination)
}

private func runTestCommand(executable: String, arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CocoaError(.executableLoad)
    }
}

private func testArchiveLimits(
    maximumListingBytes: UInt64 = 1_024 * 1_024,
    maximumEntryCount: Int = 1_000,
    maximumArchiveBytes: UInt64 = 1_024 * 1_024,
    maximumExpandedBytes: UInt64 = 1_024 * 1_024,
    minimumFreeSpaceReserveBytes: UInt64 = 1_024,
    listingTimeout: TimeInterval = 5,
    operationTimeout: TimeInterval = 5
) -> ArchiveSafetyLimits {
    ArchiveSafetyLimits(
        maximumListingBytes: maximumListingBytes,
        maximumEntryCount: maximumEntryCount,
        maximumArchiveBytes: maximumArchiveBytes,
        maximumExpandedBytes: maximumExpandedBytes,
        minimumFreeSpaceReserveBytes: minimumFreeSpaceReserveBytes,
        listingTimeout: listingTimeout,
        operationTimeout: operationTimeout
    )
}
