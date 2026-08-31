import AppKit
import Foundation

public enum FileClipboardOperation: String, Codable, Hashable, Sendable {
    case copy
    case cut
}

public struct FileClipboardContents: Hashable, Sendable {
    public let operation: FileClipboardOperation
    public let fileURLs: [URL]
    public let pasteboardChangeCount: Int

    public init(
        operation: FileClipboardOperation,
        fileURLs: [URL],
        pasteboardChangeCount: Int
    ) {
        self.operation = operation
        self.fileURLs = fileURLs
        self.pasteboardChangeCount = pasteboardChangeCount
    }
}

public struct FileClipboardPartialTransferError: Error, Sendable {
    public let failedSourceURL: URL
    public let completedResults: [FileTransferResult]
    public let underlyingErrorDescription: String
    public let cutClipboardFinalizationErrorDescription: String?

    public init(
        failedSourceURL: URL,
        completedResults: [FileTransferResult],
        underlyingErrorDescription: String,
        cutClipboardFinalizationErrorDescription: String? = nil
    ) {
        self.failedSourceURL = failedSourceURL
        self.completedResults = completedResults
        self.underlyingErrorDescription = underlyingErrorDescription
        self.cutClipboardFinalizationErrorDescription =
            cutClipboardFinalizationErrorDescription
    }
}

public struct FileClipboardPasteFinalizationError: Error, Sendable {
    public let completedResults: [FileTransferResult]
    public let underlyingErrorDescription: String

    public init(
        completedResults: [FileTransferResult],
        underlyingErrorDescription: String
    ) {
        self.completedResults = completedResults
        self.underlyingErrorDescription = underlyingErrorDescription
    }
}

public struct FileClipboardPastePlan: Hashable, Sendable {
    public let clipboardContents: FileClipboardContents
    public let destinationDirectory: URL
    public let transferKind: FileTransferKind

    public init(
        clipboardContents: FileClipboardContents,
        destinationDirectory: URL,
        transferKind: FileTransferKind
    ) {
        self.clipboardContents = clipboardContents
        self.destinationDirectory = destinationDirectory
        self.transferKind = transferKind
    }
}

public enum SystemFileClipboardError: Error, Equatable, Sendable {
    case noFileURLs
    case sourceIsNotAFileURL(URL)
    case sourceDoesNotExist(URL)
    case pasteboardChanged
    case unableToClearPasteboard
    case unableToWritePasteboard
}

/// Reads and writes Finder-compatible file URLs on a macOS pasteboard.
///
/// The default initializer always uses `NSPasteboard.general`. Magic Right's
/// cut intent is supplementary metadata on the same pasteboard items; the
/// actual selection remains standard `public.file-url` data that Finder and
/// other applications can consume without understanding Magic Right.
@MainActor
public final class SystemFileClipboardService {
    public static let cutMarkerPasteboardType = NSPasteboard.PasteboardType(
        "dev.magicright.file-cut-marker.v1"
    )
    public static let legacyFilenamesPasteboardType = NSPasteboard.PasteboardType(
        "NSFilenamesPboardType"
    )

    private let pasteboard: NSPasteboard
    private let transferOperation: @Sendable (FileTransferRequest) throws -> FileTransferResult
    private let pasteboardContentsClearer: (NSPasteboard) -> Int
    private let pasteboardItemWriter: (NSPasteboard, [NSPasteboardItem]) -> Bool

    public convenience init(transferService: FileTransferService = .init()) {
        self.init(pasteboard: .general, transferService: transferService)
    }

    /// Allows tests to use a private named pasteboard without touching the
    /// user's system clipboard. Production code should use the convenience
    /// initializer above.
    public init(
        pasteboard: NSPasteboard,
        transferService: FileTransferService = .init()
    ) {
        self.pasteboard = pasteboard
        transferOperation = { request in
            try transferService.transfer(request)
        }
        pasteboardContentsClearer = { pasteboard in
            pasteboard.clearContents()
        }
        pasteboardItemWriter = { pasteboard, items in
            pasteboard.writeObjects(items)
        }
    }

    init(
        pasteboard: NSPasteboard,
        transferOperation: @escaping @Sendable (
            FileTransferRequest
        ) throws -> FileTransferResult,
        pasteboardContentsClearer: @escaping (NSPasteboard) -> Int = { pasteboard in
            pasteboard.clearContents()
        },
        pasteboardItemWriter: @escaping (
            NSPasteboard,
            [NSPasteboardItem]
        ) -> Bool
    ) {
        self.pasteboard = pasteboard
        self.transferOperation = transferOperation
        self.pasteboardContentsClearer = pasteboardContentsClearer
        self.pasteboardItemWriter = pasteboardItemWriter
    }

    @discardableResult
    public func write(
        fileURLs: [URL],
        operation: FileClipboardOperation
    ) throws -> FileClipboardContents {
        try write(
            fileURLs: fileURLs,
            operation: operation,
            verifyFinalizationClear: false
        )
    }

    private func write(
        fileURLs: [URL],
        operation: FileClipboardOperation,
        verifyFinalizationClear: Bool
    ) throws -> FileClipboardContents {
        let normalizedURLs = try Self.validatedUniqueFileURLs(fileURLs)
        guard !normalizedURLs.isEmpty else {
            throw SystemFileClipboardError.noFileURLs
        }

        let items = normalizedURLs.map { url -> NSPasteboardItem in
            let item = NSPasteboardItem()
            // `public.file-url` is the interoperable representation used by
            // NSURL, Finder and third-party file clipboard consumers.
            item.setString(url.absoluteString, forType: .fileURL)
            return item
        }
        if operation == .cut {
            let marker = CutMarker(fileURLs: normalizedURLs)
            items[0].setData(
                try JSONEncoder().encode(marker),
                forType: Self.cutMarkerPasteboardType
            )
        }

        if verifyFinalizationClear {
            try clearPasteboardForFinalization()
        } else {
            pasteboard.clearContents()
        }
        guard pasteboardItemWriter(pasteboard, items) else {
            throw SystemFileClipboardError.unableToWritePasteboard
        }
        return FileClipboardContents(
            operation: operation,
            fileURLs: normalizedURLs,
            pasteboardChangeCount: pasteboard.changeCount
        )
    }

    public func read() -> FileClipboardContents? {
        let fileURLs = readStandardFileURLs()
        guard !fileURLs.isEmpty else { return nil }

        let operation: FileClipboardOperation
        if let markerData = pasteboard.pasteboardItems?
            .compactMap({ $0.data(forType: Self.cutMarkerPasteboardType) })
            .first,
           let marker = try? JSONDecoder().decode(CutMarker.self, from: markerData),
           marker.matches(fileURLs) {
            operation = .cut
        } else {
            operation = .copy
        }

        return FileClipboardContents(
            operation: operation,
            fileURLs: fileURLs,
            pasteboardChangeCount: pasteboard.changeCount
        )
    }

    /// Copies or moves every standard file URL currently on the pasteboard.
    /// FileTransferService supplies collision-safe destination naming. A cut
    /// clipboard is cleared only after every move succeeds and only if another
    /// app has not replaced the clipboard in the meantime.
    public func preparePaste(
        into destinationDirectory: URL
    ) throws -> FileClipboardPastePlan {
        guard let contents = read() else {
            throw SystemFileClipboardError.noFileURLs
        }
        try preflight(contents: contents, destinationDirectory: destinationDirectory)
        guard pasteboard.changeCount == contents.pasteboardChangeCount else {
            throw SystemFileClipboardError.pasteboardChanged
        }
        let kind: FileTransferKind = contents.operation == .cut ? .move : .copy
        return FileClipboardPastePlan(
            clipboardContents: contents,
            destinationDirectory: destinationDirectory,
            transferKind: kind
        )
    }

    /// The potentially slow filesystem work runs outside the main actor. Only
    /// the pasteboard snapshot and conditional finalization touch AppKit.
    @discardableResult
    public func paste(
        into destinationDirectory: URL
    ) async throws -> [FileTransferResult] {
        let plan = try preparePaste(into: destinationDirectory)
        let transfer = transferOperation
        do {
            let completedResults = try await Task.detached(priority: .userInitiated) {
                var results: [FileTransferResult] = []
                for sourceURL in plan.clipboardContents.fileURLs {
                    do {
                        results.append(
                            try transfer(
                                FileTransferRequest(
                                    kind: plan.transferKind,
                                    sourceURL: sourceURL,
                                    destinationDirectory: plan.destinationDirectory
                                )
                            )
                        )
                    } catch {
                        throw FileClipboardPartialTransferError(
                            failedSourceURL: sourceURL,
                            completedResults: results,
                            underlyingErrorDescription: String(describing: error)
                        )
                    }
                }
                return results
            }.value
            do {
                try finalizeCutPaste(
                    original: plan.clipboardContents,
                    completedResults: completedResults
                )
            } catch {
                throw FileClipboardPasteFinalizationError(
                    completedResults: completedResults,
                    underlyingErrorDescription: String(describing: error)
                )
            }
            return completedResults
        } catch let partialError as FileClipboardPartialTransferError {
            do {
                try finalizeCutPaste(
                    original: plan.clipboardContents,
                    completedResults: partialError.completedResults
                )
            } catch let finalizationError {
                throw FileClipboardPartialTransferError(
                    failedSourceURL: partialError.failedSourceURL,
                    completedResults: partialError.completedResults,
                    underlyingErrorDescription: partialError.underlyingErrorDescription,
                    cutClipboardFinalizationErrorDescription: String(
                        describing: finalizationError
                    )
                )
            }
            throw partialError
        }
    }

    private func readStandardFileURLs() -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [NSURL]
        return Self.uniqueURLs(
            (objects ?? []).map { $0 as URL }.filter(\.isFileURL)
        )
    }

    private func preflight(
        contents: FileClipboardContents,
        destinationDirectory: URL
    ) throws {
        let fileManager = FileManager.default
        var destinationIsDirectory = ObjCBool(false)
        guard fileManager.fileExists(
            atPath: destinationDirectory.path,
            isDirectory: &destinationIsDirectory
        ) else {
            throw FileTransferServiceError.destinationDoesNotExist(
                destinationDirectory
            )
        }
        guard destinationIsDirectory.boolValue else {
            throw FileTransferServiceError.destinationIsNotDirectory(
                destinationDirectory
            )
        }

        let normalizedDestination = destinationDirectory.standardizedFileURL
            .resolvingSymlinksInPath()
        for sourceURL in contents.fileURLs {
            guard let sourceType = FileSystemItemInspector.type(
                at: sourceURL,
                fileManager: fileManager
            ) else {
                throw SystemFileClipboardError.sourceDoesNotExist(sourceURL)
            }
            let sourceIsDirectory = sourceType == .typeDirectory
            let normalizedSource = sourceURL.standardizedFileURL
                .resolvingSymlinksInPath()
            let normalizedParent = sourceURL.deletingLastPathComponent()
                .standardizedFileURL
                .resolvingSymlinksInPath()
            if contents.operation == .cut,
               normalizedDestination == normalizedParent {
                throw FileTransferServiceError.moveDestinationIsCurrentParent(
                    source: sourceURL,
                    destination: destinationDirectory
                )
            }
            if sourceIsDirectory,
               Self.isEqualOrDescendant(
                normalizedDestination,
                of: normalizedSource
               ) {
                throw FileTransferServiceError.destinationIsInsideSource(
                    source: sourceURL,
                    destination: destinationDirectory
                )
            }
        }
    }

    /// Clears a fully consumed Magic Right cut clipboard, or rewrites a
    /// partially completed cut with only the not-yet-moved sources. The update
    /// is ignored if any app has replaced the pasteboard since `read()`.
    public func finalizeCutPaste(
        original: FileClipboardContents,
        completedResults: [FileTransferResult]
    ) throws {
        guard original.operation == .cut,
              pasteboard.changeCount == original.pasteboardChangeCount else {
            return
        }
        let completedSources = Set(completedResults.map(\.sourceURL))
        let remaining = original.fileURLs.filter {
            !completedSources.contains($0)
        }
        guard remaining.count < original.fileURLs.count else { return }
        if remaining.isEmpty {
            try clearPasteboardForFinalization()
        } else {
            _ = try write(
                fileURLs: remaining,
                operation: .cut,
                verifyFinalizationClear: true
            )
        }
    }

    private func clearPasteboardForFinalization() throws {
        let previousChangeCount = pasteboard.changeCount
        let resultingChangeCount = pasteboardContentsClearer(pasteboard)
        guard resultingChangeCount != previousChangeCount,
              pasteboard.changeCount == resultingChangeCount,
              readStandardFileURLs().isEmpty,
              pasteboard.availableType(from: [Self.cutMarkerPasteboardType]) == nil else {
            throw SystemFileClipboardError.unableToClearPasteboard
        }
    }

    private static func validatedUniqueFileURLs(_ urls: [URL]) throws -> [URL] {
        for url in urls where !url.isFileURL {
            throw SystemFileClipboardError.sourceIsNotAFileURL(url)
        }
        let normalized = uniqueURLs(urls.map(\.standardizedFileURL))
        for url in normalized where !FileSystemItemInspector.exists(at: url) {
            throw SystemFileClipboardError.sourceDoesNotExist(url)
        }
        return normalized
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { seen.insert($0.standardizedFileURL).inserted }
    }

    private static func isEqualOrDescendant(_ url: URL, of ancestor: URL) -> Bool {
        let components = url.pathComponents
        let ancestorComponents = ancestor.pathComponents
        guard components.count >= ancestorComponents.count else { return false }
        return components.prefix(ancestorComponents.count)
            .elementsEqual(ancestorComponents)
    }
}

private struct CutMarker: Codable {
    let schemaVersion: Int
    let fileURLStrings: [String]

    init(fileURLs: [URL]) {
        schemaVersion = 1
        fileURLStrings = fileURLs.map { $0.standardizedFileURL.absoluteString }
    }

    func matches(_ fileURLs: [URL]) -> Bool {
        schemaVersion == 1
            && fileURLStrings == fileURLs.map {
                $0.standardizedFileURL.absoluteString
            }
    }
}
