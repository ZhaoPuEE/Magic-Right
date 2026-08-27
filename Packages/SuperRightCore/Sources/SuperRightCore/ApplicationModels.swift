import Foundation

/// How Super Right should translate an open intent for an application.
///
/// Application identity is always the bundle identifier. The adapter only
/// describes launch behavior and never contains a persisted application path.
public enum ApplicationAdapterKind: String, Codable, CaseIterable, Hashable, Sendable {
    case genericURLs
    case zed
    case visualStudioCode
    case tabby
    case terminal
}

public enum ApplicationDescriptorSource: String, Codable, Hashable, Sendable {
    case knownCatalog
    case manuallyAdded
}

/// Persistable metadata for an application Super Right knows how to offer.
///
/// Do not add an application URL to this type. Applications can be moved or
/// reinstalled, so their current URL must be resolved through Launch Services.
public struct ApplicationDescriptor: Codable, Hashable, Identifiable, Sendable {
    public var id: String { bundleIdentifier }

    public let bundleIdentifier: String
    public var displayName: String
    public var adapterKind: ApplicationAdapterKind
    public var source: ApplicationDescriptorSource

    public init(
        bundleIdentifier: String,
        displayName: String,
        adapterKind: ApplicationAdapterKind,
        source: ApplicationDescriptorSource
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.adapterKind = adapterKind
        self.source = source
    }
}

/// Concise API spelling for clients that model descriptors as menu items.
public typealias AppDescriptor = ApplicationDescriptor

/// Ephemeral information returned by an application locator.
public struct LocatedApplication: Hashable, Sendable {
    public let bundleIdentifier: String
    public let applicationURL: URL
    public let displayName: String

    public init(bundleIdentifier: String, applicationURL: URL, displayName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationURL = applicationURL
        self.displayName = displayName
    }
}

/// An installed application combined with Super Right's launch metadata.
///
/// `currentApplicationURL` is intentionally ephemeral and must not be used as
/// persisted application identity.
public struct DetectedApplication: Hashable, Identifiable, Sendable {
    public var id: String { descriptor.bundleIdentifier }

    public let descriptor: ApplicationDescriptor
    public let currentApplicationURL: URL
    public let currentDisplayName: String

    public init(
        descriptor: ApplicationDescriptor,
        currentApplicationURL: URL,
        currentDisplayName: String
    ) {
        self.descriptor = descriptor
        self.currentApplicationURL = currentApplicationURL
        self.currentDisplayName = currentDisplayName
    }

    public var bundleIdentifier: String { descriptor.bundleIdentifier }

    public var menuDisplayName: String {
        currentDisplayName.isEmpty ? descriptor.displayName : currentDisplayName
    }
}
