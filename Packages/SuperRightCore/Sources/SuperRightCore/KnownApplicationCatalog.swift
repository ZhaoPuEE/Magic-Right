import Foundation

public struct KnownApplicationCatalog: Hashable, Sendable {
    public let descriptors: [ApplicationDescriptor]

    public init(descriptors: [ApplicationDescriptor]) {
        var seen = Set<String>()
        self.descriptors = descriptors.filter { seen.insert($0.bundleIdentifier).inserted }
    }

    public func descriptor(forBundleIdentifier bundleIdentifier: String) -> ApplicationDescriptor? {
        descriptors.first { $0.bundleIdentifier == bundleIdentifier }
    }

    public static let standard = KnownApplicationCatalog(descriptors: [
        descriptor(
            bundleIdentifier: "dev.zed.Zed",
            displayName: "Zed",
            adapterKind: .zed
        ),
        descriptor(
            bundleIdentifier: "com.microsoft.VSCode",
            displayName: "Visual Studio Code",
            adapterKind: .visualStudioCode
        ),
        descriptor(
            bundleIdentifier: "org.tabby",
            displayName: "Tabby",
            adapterKind: .tabby
        ),
        descriptor(
            bundleIdentifier: "com.apple.Terminal",
            displayName: "Terminal",
            adapterKind: .terminal
        ),

        // Editors and developer terminals. Generic URL delivery is the safe
        // default until an application has a separately tested adapter.
        descriptor(bundleIdentifier: "com.todesktop.230313mzl4w4u92", displayName: "Cursor"),
        descriptor(bundleIdentifier: "com.vscodium", displayName: "VSCodium"),
        descriptor(bundleIdentifier: "com.googlecode.iterm2", displayName: "iTerm2"),
        descriptor(bundleIdentifier: "dev.warp.Warp-Stable", displayName: "Warp"),
        descriptor(
            bundleIdentifier: "com.mitchellh.ghostty",
            displayName: "Ghostty",
            adapterKind: .ghostty
        ),
        descriptor(bundleIdentifier: "com.sublimetext.4", displayName: "Sublime Text"),
        descriptor(bundleIdentifier: "com.panic.Nova", displayName: "Nova"),

        // Common JetBrains IDEs. Edition-specific bundle identifiers are kept
        // separate so Launch Services can discover either installed edition.
        descriptor(bundleIdentifier: "com.jetbrains.intellij", displayName: "IntelliJ IDEA"),
        descriptor(bundleIdentifier: "com.jetbrains.intellij.ce", displayName: "IntelliJ IDEA Community Edition"),
        descriptor(bundleIdentifier: "com.jetbrains.pycharm", displayName: "PyCharm"),
        descriptor(bundleIdentifier: "com.jetbrains.pycharm.ce", displayName: "PyCharm Community Edition"),
        descriptor(bundleIdentifier: "com.jetbrains.WebStorm", displayName: "WebStorm"),
        descriptor(bundleIdentifier: "com.jetbrains.CLion", displayName: "CLion"),
        descriptor(bundleIdentifier: "com.jetbrains.goland", displayName: "GoLand"),
        descriptor(bundleIdentifier: "com.jetbrains.rider", displayName: "Rider"),
        descriptor(bundleIdentifier: "com.jetbrains.datagrip", displayName: "DataGrip"),
        descriptor(bundleIdentifier: "com.jetbrains.PhpStorm", displayName: "PhpStorm"),
        descriptor(bundleIdentifier: "com.jetbrains.rubymine", displayName: "RubyMine"),

        // Git clients. SourceTree has distinct direct-download and Mac App
        // Store bundle identifiers, both representing the same product.
        descriptor(bundleIdentifier: "com.DanPristupov.Fork", displayName: "Fork"),
        descriptor(bundleIdentifier: "com.torusknot.SourceTreeNotMAS", displayName: "Sourcetree"),
        descriptor(bundleIdentifier: "com.torusknot.SourceTree", displayName: "Sourcetree"),
        descriptor(bundleIdentifier: "com.github.GitHubClient", displayName: "GitHub Desktop")
    ])

    private static func descriptor(
        bundleIdentifier: String,
        displayName: String,
        adapterKind: ApplicationAdapterKind = .genericURLs
    ) -> ApplicationDescriptor {
        ApplicationDescriptor(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            adapterKind: adapterKind,
            source: .knownCatalog
        )
    }
}
