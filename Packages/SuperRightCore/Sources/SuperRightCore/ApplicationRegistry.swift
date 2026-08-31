import Foundation

public enum ApplicationRegistryError: Error, Equatable, Sendable {
    case invalidApplication(URL)
}

/// Pure registry logic with an injected installation locator.
public struct ApplicationRegistry<Locator: ApplicationLocating>: Sendable {
    public let catalog: KnownApplicationCatalog
    public private(set) var preferences: ApplicationPreferences
    public let locator: Locator

    public init(
        catalog: KnownApplicationCatalog = .standard,
        preferences: ApplicationPreferences = .init(),
        locator: Locator
    ) {
        self.catalog = catalog
        self.preferences = preferences
        self.locator = locator
    }

    /// All currently installed known or manually registered applications.
    /// Newly installed catalog applications appear here without being enabled.
    public func detectedApplications() -> [DetectedApplication] {
        sortDetectedApplications(allDescriptors().compactMap(detect))
    }

    /// Installed and explicitly enabled applications suitable for a Finder menu.
    /// Uninstalled entries remain in preferences but are omitted from this view.
    public func visibleEnabledApplications() -> [DetectedApplication] {
        sortDetectedApplications(
            allDescriptors()
                .filter {
                    preferences.isEnabled(bundleIdentifier: $0.bundleIdentifier)
                }
                .compactMap(detect)
        )
    }

    public mutating func setEnabled(_ isEnabled: Bool, bundleIdentifier: String) {
        guard let descriptor = descriptor(forBundleIdentifier: bundleIdentifier) else { return }
        preferences.setEnabled(
            isEnabled,
            for: descriptor,
            defaultOrder: nextOrder
        )
    }

    public mutating func setOrder(_ order: Int, bundleIdentifier: String) {
        guard let descriptor = descriptor(forBundleIdentifier: bundleIdentifier) else { return }
        preferences.setOrder(order, for: descriptor)
    }

    public mutating func setCustomDisplayName(
        _ displayName: String?,
        bundleIdentifier: String
    ) {
        guard let descriptor = descriptor(forBundleIdentifier: bundleIdentifier) else { return }
        preferences.setCustomDisplayName(
            displayName,
            for: descriptor,
            defaultOrder: nextOrder
        )
    }

    /// Registers an arbitrary `.app` using bundle metadata. Only its bundle ID
    /// and launch metadata are persisted; its selected URL is not.
    @discardableResult
    public mutating func addManualApplication(
        at applicationURL: URL,
        enabled: Bool = true
    ) throws -> ApplicationDescriptor {
        guard let located = locator.inspectApplication(at: applicationURL) else {
            throw ApplicationRegistryError.invalidApplication(applicationURL)
        }

        let descriptor = catalog.descriptor(forBundleIdentifier: located.bundleIdentifier)
            ?? ApplicationDescriptor(
                bundleIdentifier: located.bundleIdentifier,
                displayName: located.displayName,
                adapterKind: .genericURLs,
                source: .manuallyAdded
            )

        if let existing = preferences.preference(
            forBundleIdentifier: descriptor.bundleIdentifier
        ) {
            preferences.register(
                descriptor: descriptor,
                isEnabled: enabled,
                order: existing.order
            )
        } else {
            preferences.register(
                descriptor: descriptor,
                isEnabled: enabled,
                order: nextOrder
            )
        }
        return descriptor
    }

    public func descriptor(forBundleIdentifier bundleIdentifier: String) -> ApplicationDescriptor? {
        catalog.descriptor(forBundleIdentifier: bundleIdentifier)
            ?? preferences.preference(forBundleIdentifier: bundleIdentifier)?.descriptor
    }

    private var nextOrder: Int {
        (preferences.applications.map(\.order).max() ?? -1) + 1
    }

    private func allDescriptors() -> [ApplicationDescriptor] {
        var descriptors = catalog.descriptors
        var knownIdentifiers = Set(descriptors.map(\.bundleIdentifier))

        for preference in preferences.applications
            where knownIdentifiers.insert(preference.descriptor.bundleIdentifier).inserted {
            descriptors.append(preference.descriptor)
        }
        return descriptors
    }

    private func detect(_ descriptor: ApplicationDescriptor) -> DetectedApplication? {
        guard let located = locator.locateApplication(
            bundleIdentifier: descriptor.bundleIdentifier
        ) else {
            return nil
        }

        let displayName = preferences.preference(
            forBundleIdentifier: descriptor.bundleIdentifier
        )?.customDisplayName ?? located.displayName

        return DetectedApplication(
            descriptor: descriptor,
            currentApplicationURL: located.applicationURL,
            currentDisplayName: displayName
        )
    }

    private func sortDetectedApplications(
        _ applications: [DetectedApplication]
    ) -> [DetectedApplication] {
        applications.sorted { lhs, rhs in
            let lhsOrder = preferences.preference(
                forBundleIdentifier: lhs.bundleIdentifier
            )?.order ?? Int.max
            let rhsOrder = preferences.preference(
                forBundleIdentifier: rhs.bundleIdentifier
            )?.order ?? Int.max

            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.menuDisplayName.localizedStandardCompare(
                rhs.menuDisplayName
            ) == .orderedAscending
        }
    }
}
