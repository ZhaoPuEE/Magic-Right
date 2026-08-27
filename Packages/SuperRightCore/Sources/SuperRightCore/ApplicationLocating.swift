import Foundation

/// Resolves the current installation location for an application identity.
/// Tests and previews can inject a deterministic implementation.
public protocol ApplicationLocating: Sendable {
    func locateApplication(bundleIdentifier: String) -> LocatedApplication?
    func inspectApplication(at applicationURL: URL) -> LocatedApplication?
}

#if canImport(AppKit)
import AppKit

/// Production Launch Services-backed locator for macOS.
///
/// `NSWorkspace` is shared AppKit state. This value is safe to pass between
/// clients because it stores no mutable AppKit objects of its own.
public struct NSWorkspaceApplicationLocator: ApplicationLocating, @unchecked Sendable {
    public init() {}

    public func locateApplication(bundleIdentifier: String) -> LocatedApplication? {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            return nil
        }

        return inspectApplication(at: applicationURL)
            ?? LocatedApplication(
                bundleIdentifier: bundleIdentifier,
                applicationURL: applicationURL,
                displayName: applicationURL.deletingPathExtension().lastPathComponent
            )
    }

    public func inspectApplication(at applicationURL: URL) -> LocatedApplication? {
        guard let bundle = Bundle(url: applicationURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return nil
        }

        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? applicationURL.deletingPathExtension().lastPathComponent

        return LocatedApplication(
            bundleIdentifier: bundleIdentifier,
            applicationURL: applicationURL,
            displayName: displayName
        )
    }
}
#endif
