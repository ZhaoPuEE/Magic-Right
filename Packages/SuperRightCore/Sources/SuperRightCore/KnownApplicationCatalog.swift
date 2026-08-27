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
        ApplicationDescriptor(
            bundleIdentifier: "dev.zed.Zed",
            displayName: "Zed",
            adapterKind: .zed,
            source: .knownCatalog
        ),
        ApplicationDescriptor(
            bundleIdentifier: "com.microsoft.VSCode",
            displayName: "Visual Studio Code",
            adapterKind: .visualStudioCode,
            source: .knownCatalog
        ),
        ApplicationDescriptor(
            bundleIdentifier: "org.tabby",
            displayName: "Tabby",
            adapterKind: .tabby,
            source: .knownCatalog
        ),
        ApplicationDescriptor(
            bundleIdentifier: "com.apple.Terminal",
            displayName: "Terminal",
            adapterKind: .terminal,
            source: .knownCatalog
        )
    ])
}
