import Foundation
import Testing
@testable import SuperRightCore

@Suite("Git repository context")
struct GitRepositoryServiceTests {
    @Test("Finder repository marker lookup terminates at the filesystem root")
    func boundedFinderMarkerLookup() {
        var probes: [String] = []
        let nested = URL(
            fileURLWithPath: "/Users/example/project/Sources",
            isDirectory: true
        )

        let found = GitRepositoryService.containsGitMetadata(
            atOrAbove: nested
        ) { path in
            probes.append(path)
            return path == "/Users/example/project/.git"
        }

        #expect(found)
        #expect(probes == [
            "/Users/example/project/Sources/.git",
            "/Users/example/project/.git"
        ])

        var rootProbeCount = 0
        let missing = GitRepositoryService.containsGitMetadata(
            atOrAbove: URL(fileURLWithPath: "/", isDirectory: true)
        ) { _ in
            rootProbeCount += 1
            return false
        }
        #expect(!missing)
        #expect(rootProbeCount == 1)
        #expect(
            !GitRepositoryService.containsGitMetadata(
                atOrAbove: URL(string: "https://example.com/repository")!
            )
        )
    }

    @Test("Common remote forms normalize to credential-free browser URLs")
    func normalizesRemoteURLs() {
        let cases: [(String, String)] = [
            ("git@github.com:openai/codex.git", "https://github.com/openai/codex"),
            ("ssh://git@gitlab.com/group/project.git", "https://gitlab.com/group/project"),
            ("git@server:group/project.git", "https://server/group/project"),
            ("git://github.com/openai/codex.git/", "https://github.com/openai/codex"),
            (
                "git@ssh.dev.azure.com:v3/company/product/repository.git",
                "https://dev.azure.com/company/product/_git/repository"
            ),
            (
                "https://token@example.com/team/repo.git?private=1#readme",
                "https://example.com/team/repo"
            ),
            ("http://git.example.test:8080/team/repo.git", "http://git.example.test:8080/team/repo")
        ]

        for (remote, expected) in cases {
            #expect(
                GitRepositoryService.normalizedOpenableOriginURL(for: remote)?.absoluteString
                    == expected
            )
        }
    }

    @Test("Local paths and unsupported schemes do not become browser URLs")
    func rejectsUnsupportedRemotes() {
        #expect(GitRepositoryService.normalizedOpenableOriginURL(for: "/tmp/repo.git") == nil)
        #expect(GitRepositoryService.normalizedOpenableOriginURL(for: "file:///tmp/repo") == nil)
        #expect(GitRepositoryService.normalizedOpenableOriginURL(for: "ftp://host/repo") == nil)
        #expect(GitRepositoryService.normalizedOpenableOriginURL(for: "") == nil)
    }

    @Test("Relative paths are component-aware")
    func relativePaths() throws {
        let service = GitRepositoryService()
        let root = URL(fileURLWithPath: "/tmp/example/repo", isDirectory: true)

        #expect(try service.relativePath(of: root, in: root) == ".")
        #expect(
            try service.relativePath(
                of: root.appendingPathComponent("Sources/App.swift"),
                in: root
            ) == "Sources/App.swift"
        )
        let sibling = URL(fileURLWithPath: "/tmp/example/repository/file")
        #expect(throws: GitRepositoryServiceError.selectedItemOutsideRepository(
            item: sibling,
            repositoryRoot: root
        )) {
            try service.relativePath(of: sibling, in: root)
        }
    }

    @Test("Symlinked repository subdirectories retain Git context")
    func symlinkedRepositorySubdirectory() throws {
        try withGitTemporaryDirectory { parent in
            let repository = parent.appendingPathComponent(
                "Repository",
                isDirectory: true
            )
            let sources = repository.appendingPathComponent(
                "Sources",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: sources,
                withIntermediateDirectories: true
            )
            try runGitTestCommand(arguments: ["-C", repository.path, "init", "-q"])

            let selected = sources.appendingPathComponent("App.swift")
            try Data().write(to: selected)
            let linkedSources = parent.appendingPathComponent(
                "Linked Sources",
                isDirectory: true
            )
            try FileManager.default.createSymbolicLink(
                at: linkedSources,
                withDestinationURL: sources
            )
            let linkedSelection = linkedSources.appendingPathComponent("App.swift")

            #expect(GitRepositoryService.containsGitMetadata(atOrAbove: linkedSources))

            let service = GitRepositoryService()
            let discoveredRoot = try service.repositoryRoot(containing: linkedSelection)
            #expect(discoveredRoot == repository.resolvingSymlinksInPath())
            #expect(
                try service.relativePath(
                    of: linkedSelection,
                    in: discoveredRoot
                ) == "Sources/App.swift"
            )
        }
    }

    @Test("Repository lookup passes unusual Finder paths as one argument")
    func repositoryLookupUsesStructuredArguments() throws {
        try withGitTemporaryDirectory { parent in
            let directory = parent.appendingPathComponent(
                "repo; $(touch should-not-exist)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false
            )
            let expectedRoot = directory.appendingPathComponent("root", isDirectory: true)
            let runner = GitStubCommandRunner { executable, arguments, currentDirectory in
                #expect(executable.path == "/usr/bin/git")
                #expect(arguments == [
                    "-C",
                    directory.path,
                    "rev-parse",
                    "--show-toplevel"
                ])
                #expect(currentDirectory == nil)
                return StructuredCommandResult(
                    terminationStatus: 0,
                    standardOutput: Data((expectedRoot.path + "\n").utf8),
                    standardError: Data()
                )
            }

            let result = try GitRepositoryService(commandRunner: runner)
                .repositoryRoot(containing: directory)

            #expect(result.path == expectedRoot.path)
            #expect(
                !FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent("should-not-exist").path
                )
            )
        }
    }

    @Test("Repository description combines root, relative path, and origin")
    func repositoryDescription() throws {
        try withGitTemporaryDirectory { root in
            let selected = root.appendingPathComponent("Sources/App.swift")
            try FileManager.default.createDirectory(
                at: selected.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: selected)
            let runner = GitStubCommandRunner { _, arguments, _ in
                if arguments.suffix(2) == ["rev-parse", "--show-toplevel"] {
                    return StructuredCommandResult(
                        terminationStatus: 0,
                        standardOutput: Data((root.path + "\n").utf8),
                        standardError: Data()
                    )
                }
                #expect(arguments.suffix(3) == ["config", "--get", "remote.origin.url"])
                return StructuredCommandResult(
                    terminationStatus: 0,
                    standardOutput: Data("git@github.com:owner/project.git\n".utf8),
                    standardError: Data()
                )
            }

            let description = try GitRepositoryService(commandRunner: runner)
                .repository(for: selected)

            #expect(description.rootURL == root)
            #expect(description.relativePath == "Sources/App.swift")
            #expect(description.originRemote == "git@github.com:owner/project.git")
            #expect(
                description.normalizedRemoteWebURL.absoluteString
                    == "https://github.com/owner/project"
            )
        }
    }

    @Test("Local runner discovers a real repository and reads origin")
    func realRepositoryRoundTrip() throws {
        try withGitTemporaryDirectory { root in
            try runGitTestCommand(arguments: ["-C", root.path, "init", "-q"])
            try runGitTestCommand(arguments: [
                "-C",
                root.path,
                "config",
                "remote.origin.url",
                "git@github.com:owner/project.git"
            ])
            let selected = root.appendingPathComponent("Sources/App.swift")
            try FileManager.default.createDirectory(
                at: selected.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: selected)

            let repository = try GitRepositoryService().repository(for: selected)

            #expect(repository.rootURL.path == root.path)
            #expect(repository.relativePath == "Sources/App.swift")
            #expect(repository.originRemote == "git@github.com:owner/project.git")
        }
    }

    @Test("Missing repositories and origins have stable errors")
    func stableErrors() throws {
        try withGitTemporaryDirectory { directory in
            let missingRepositoryRunner = GitStubCommandRunner { _, _, _ in
                StructuredCommandResult(
                    terminationStatus: 128,
                    standardOutput: Data(),
                    standardError: Data("not a repository".utf8)
                )
            }
            #expect(throws: GitRepositoryServiceError.repositoryNotFound(directory)) {
                try GitRepositoryService(commandRunner: missingRepositoryRunner)
                    .repositoryRoot(containing: directory)
            }

            let missingOriginRunner = GitStubCommandRunner { _, _, _ in
                StructuredCommandResult(
                    terminationStatus: 1,
                    standardOutput: Data(),
                    standardError: Data()
                )
            }
            #expect(throws: GitRepositoryServiceError.originNotConfigured(directory)) {
                try GitRepositoryService(commandRunner: missingOriginRunner)
                    .origin(forRepositoryAt: directory)
            }
        }
    }
}

private struct GitStubCommandRunner: StructuredCommandRunning {
    let body: @Sendable (URL, [String], URL?) throws -> StructuredCommandResult

    init(
        body: @escaping @Sendable (URL, [String], URL?) throws -> StructuredCommandResult
    ) {
        self.body = body
    }

    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?
    ) throws -> StructuredCommandResult {
        try body(executableURL, arguments, currentDirectoryURL)
    }
}

private func withGitTemporaryDirectory(
    _ body: (URL) throws -> Void
) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

private func runGitTestCommand(arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CocoaError(.executableLoad)
    }
}
