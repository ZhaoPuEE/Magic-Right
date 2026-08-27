import Foundation
import Testing
@testable import SuperRightCore

@Suite("Structured application open requests")
struct ApplicationOpenRequestTests {
    @Test("Zed receives every selected URL in order")
    func zedMultiSelection() throws {
        let zed = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "dev.zed.Zed"
            )
        )
        let urls = [
            URL(fileURLWithPath: "/tmp/first file.swift"),
            URL(fileURLWithPath: "/tmp/second.swift")
        ]

        let request = try ApplicationOpenRequestBuilder.makeRequest(
            for: zed,
            intent: .selection(urls)
        )

        #expect(request == .openURLs(
            OpenURLsRequest(
                applicationBundleIdentifier: "dev.zed.Zed",
                urls: urls
            )
        ))
    }

    @Test("Git root is an explicit URL request")
    func gitRootRequest() throws {
        let vscode = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "com.microsoft.VSCode"
            )
        )
        let root = URL(fileURLWithPath: "/Users/test/repository")

        let request = try ApplicationOpenRequestBuilder.makeRequest(
            for: vscode,
            intent: .gitRoot(root)
        )

        #expect(request == .openURLs(
            OpenURLsRequest(
                applicationBundleIdentifier: "com.microsoft.VSCode",
                urls: [root]
            )
        ))
    }

    @Test("Tabby uses a structured argument array without shell interpolation")
    func tabbyStructuredArguments() throws {
        let tabby = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "org.tabby"
            )
        )
        let directory = URL(fileURLWithPath: "/tmp/a folder; touch danger")

        let request = try ApplicationOpenRequestBuilder.makeRequest(
            for: tabby,
            intent: .currentDirectory(directory)
        )

        let expected = StructuredLaunchRequest(
            applicationBundleIdentifier: "org.tabby",
            arguments: [.flag("--directory"), .path(directory)]
        )
        #expect(request == .structuredLaunch(expected))
        #expect(expected.argumentValues == ["--directory", directory.path])
    }

    @Test("Tabby converts a selected file to its parent directory")
    func tabbySelectedFileUsesParentDirectory() throws {
        let tabby = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "org.tabby"
            )
        )
        let file = URL(fileURLWithPath: "/tmp/Magic Right/project/main.swift")
        let parent = file.deletingLastPathComponent()

        let request = try ApplicationOpenRequestBuilder.makeRequest(
            for: tabby,
            intent: .selection([file])
        )

        #expect(request == .structuredLaunch(
            StructuredLaunchRequest(
                applicationBundleIdentifier: "org.tabby",
                arguments: [.flag("--directory"), .path(parent)]
            )
        ))
    }

    @Test("Tabby preserves a selected directory")
    func tabbySelectedDirectoryIsPreserved() throws {
        let tabby = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "org.tabby"
            )
        )
        let directory = URL(
            fileURLWithPath: "/tmp/Magic Right/project",
            isDirectory: true
        )

        let request = try ApplicationOpenRequestBuilder.makeRequest(
            for: tabby,
            intent: .selection([directory])
        )

        #expect(request == .structuredLaunch(
            StructuredLaunchRequest(
                applicationBundleIdentifier: "org.tabby",
                arguments: [.flag("--directory"), .path(directory)]
            )
        ))
    }

    @Test("Terminal converts a selected file to its parent directory")
    func terminalSelectedFileUsesParentDirectory() throws {
        let terminal = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "com.apple.Terminal"
            )
        )
        let file = URL(fileURLWithPath: "/tmp/Magic Right/project/main.swift")
        let parent = file.deletingLastPathComponent()

        let request = try ApplicationOpenRequestBuilder.makeRequest(
            for: terminal,
            intent: .selection([file])
        )

        #expect(request == .openURLs(
            OpenURLsRequest(
                applicationBundleIdentifier: "com.apple.Terminal",
                urls: [parent]
            )
        ))
    }

    @Test("Empty selection is rejected")
    func rejectsEmptySelection() throws {
        let terminal = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "com.apple.Terminal"
            )
        )

        #expect(throws: ApplicationOpenRequestError.emptySelection) {
            try ApplicationOpenRequestBuilder.makeRequest(
                for: terminal,
                intent: .selection([])
            )
        }
    }

    @Test("Open requests are Codable")
    func requestsCodableRoundTrip() throws {
        let request = ApplicationOpenRequest.structuredLaunch(
            StructuredLaunchRequest(
                applicationBundleIdentifier: "org.tabby",
                arguments: [
                    .flag("--directory"),
                    .path(URL(fileURLWithPath: "/tmp/project"))
                ]
            )
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ApplicationOpenRequest.self, from: data)

        #expect(decoded == request)
    }
}
