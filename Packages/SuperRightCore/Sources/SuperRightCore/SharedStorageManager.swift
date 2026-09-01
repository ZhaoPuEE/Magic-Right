import Foundation
import Security

/// A resolved cross-process storage backend.
///
/// The location stores only immutable, `Sendable` metadata. `UserDefaults` is
/// intentionally created on demand by ``SharedStorageManager/defaults`` so UI
/// clients do not need to keep a process-global `UserDefaults` instance.
public struct SharedStorageLocation: Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case appGroup
        case applicationSupportFallback
    }

    public let kind: Kind
    public let suiteName: String
    public let containerURL: URL

    public init(kind: Kind, suiteName: String, containerURL: URL) {
        self.kind = kind
        self.suiteName = suiteName
        self.containerURL = containerURL
    }

    /// Pure backend selection used by the live manager and deterministic tests.
    public static func preferred(
        appGroupSuiteName: String,
        appGroupContainerURL: URL?,
        isAppGroupSuiteAvailable: Bool,
        fallbackSuiteName: String,
        fallbackContainerURL: URL?,
        isFallbackSuiteAvailable: Bool
    ) -> SharedStorageLocation? {
        if let appGroupContainerURL, isAppGroupSuiteAvailable {
            return SharedStorageLocation(
                kind: .appGroup,
                suiteName: appGroupSuiteName,
                containerURL: appGroupContainerURL
            )
        }
        if let fallbackContainerURL, isFallbackSuiteAvailable {
            return SharedStorageLocation(
                kind: .applicationSupportFallback,
                suiteName: fallbackSuiteName,
                containerURL: fallbackContainerURL
            )
        }
        return nil
    }
}

/// Resolves storage shared by the host app and Finder extension.
///
/// A valid App Group container and defaults suite always win. Ad-hoc builds
/// without a Team ID fall back to a normal defaults suite plus
/// `~/Library/Application Support/Magic Right/Shared` for cross-process locks.
public struct SharedStorageManager: Sendable {
    public static let defaultAppGroupSuiteName = "group.dev.magicright.app"
    public static let defaultFallbackSuiteName = "dev.magicright.shared"

    public let location: SharedStorageLocation?

    public var defaults: UserDefaults? {
        guard let suiteName = location?.suiteName else { return nil }
        return UserDefaults(suiteName: suiteName)
    }

    public var containerURL: URL? {
        location?.containerURL
    }

    public var isAppGroupAvailable: Bool {
        location?.kind == .appGroup
    }

    public var isAvailable: Bool {
        location != nil
    }

    public init(
        appGroupSuiteName: String = Self.defaultAppGroupSuiteName,
        fallbackSuiteName: String = Self.defaultFallbackSuiteName,
        applicationSupportURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true),
        appGroupEligibilityProvider: ((String) -> Bool)? = nil,
        appGroupContainerProvider: (String) -> URL? = {
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: $0
            )
        },
        defaultsProvider: (String) -> UserDefaults? = {
            UserDefaults(suiteName: $0)
        },
        directoryCreator: (URL) throws -> Void = {
            try FileManager.default.createDirectory(
                at: $0,
                withIntermediateDirectories: true
            )
        }
    ) {
        let canUseAppGroup = appGroupEligibilityProvider?(appGroupSuiteName)
            ?? Self.currentProcessCanUseAppGroup(appGroupSuiteName)
        if canUseAppGroup {
            let appGroupContainerURL = appGroupContainerProvider(appGroupSuiteName)
            let isAppGroupSuiteAvailable = defaultsProvider(appGroupSuiteName) != nil
            if let appGroupLocation = SharedStorageLocation.preferred(
                appGroupSuiteName: appGroupSuiteName,
                appGroupContainerURL: appGroupContainerURL,
                isAppGroupSuiteAvailable: isAppGroupSuiteAvailable,
                fallbackSuiteName: fallbackSuiteName,
                fallbackContainerURL: nil,
                isFallbackSuiteAvailable: false
            ) {
                location = appGroupLocation
                return
            }
        }

        let fallbackContainerURL = applicationSupportURL
            .appendingPathComponent("Magic Right", isDirectory: true)
            .appendingPathComponent("Shared", isDirectory: true)
        do {
            try directoryCreator(fallbackContainerURL)
        } catch {
            location = nil
            return
        }

        location = SharedStorageLocation.preferred(
            appGroupSuiteName: appGroupSuiteName,
            appGroupContainerURL: nil,
            isAppGroupSuiteAvailable: false,
            fallbackSuiteName: fallbackSuiteName,
            fallbackContainerURL: fallbackContainerURL,
            isFallbackSuiteAvailable: defaultsProvider(fallbackSuiteName) != nil
        )
    }

    /// App Group APIs are only safe to query when the running code has both a
    /// real team identity and the requested entitlement. Xcode ad-hoc builds
    /// can retain the entitlement in their signature but have no Team ID, so
    /// probing the container would ask macOS for access to other apps' data.
    private static func currentProcessCanUseAppGroup(_ suiteName: String) -> Bool {
        var dynamicCode: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &dynamicCode) == errSecSuccess,
              let dynamicCode
        else {
            return false
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(dynamicCode, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else {
            return false
        }

        var rawInformation: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &rawInformation) == errSecSuccess,
              let information = rawInformation as NSDictionary?,
              let teamIdentifier = information[kSecCodeInfoTeamIdentifier] as? String,
              !teamIdentifier.isEmpty,
              let entitlements = information[kSecCodeInfoEntitlementsDict] as? NSDictionary,
              let appGroups = entitlements["com.apple.security.application-groups"] as? [String]
        else {
            return false
        }

        return appGroups.contains(suiteName)
    }
}
