import Testing
@testable import SuperRightCore

@Suite("Known application catalog")
struct KnownApplicationCatalogTests {
    @Test("Standard catalog has no duplicate bundle identifiers")
    func uniqueBundleIdentifiers() {
        let descriptors = KnownApplicationCatalog.standard.descriptors
        #expect(Set(descriptors.map(\.bundleIdentifier)).count == descriptors.count)
    }

    @Test("Key editors terminals IDEs and Git clients are discoverable")
    func keyApplicationsExist() {
        let expectedBundleIdentifiers = [
            "dev.zed.Zed",
            "com.microsoft.VSCode",
            "org.tabby",
            "com.apple.Terminal",
            "com.todesktop.230313mzl4w4u92",
            "com.vscodium",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "com.mitchellh.ghostty",
            "com.sublimetext.4",
            "com.panic.Nova",
            "com.jetbrains.intellij",
            "com.jetbrains.pycharm",
            "com.jetbrains.WebStorm",
            "com.DanPristupov.Fork",
            "com.torusknot.SourceTreeNotMAS",
            "com.github.GitHubClient"
        ]

        for bundleIdentifier in expectedBundleIdentifiers {
            #expect(
                KnownApplicationCatalog.standard.descriptor(
                    forBundleIdentifier: bundleIdentifier
                ) != nil,
                "Missing catalog entry for \(bundleIdentifier)"
            )
        }
    }

    @Test("Only tested built-ins use specialized adapters")
    func safeAdapters() {
        let specializedAdapters: [String: ApplicationAdapterKind] = [
            "dev.zed.Zed": .zed,
            "com.microsoft.VSCode": .visualStudioCode,
            "org.tabby": .tabby,
            "com.apple.Terminal": .terminal
        ]

        for descriptor in KnownApplicationCatalog.standard.descriptors {
            let expected = specializedAdapters[descriptor.bundleIdentifier] ?? .genericURLs
            #expect(
                descriptor.adapterKind == expected,
                "Unexpected adapter for \(descriptor.bundleIdentifier)"
            )
            #expect(descriptor.source == .knownCatalog)
        }
    }
}
