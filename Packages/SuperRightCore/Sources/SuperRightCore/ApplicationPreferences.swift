import Foundation

public struct ApplicationMenuPreference: Codable, Hashable, Identifiable, Sendable {
    public var id: String { descriptor.bundleIdentifier }

    public var descriptor: ApplicationDescriptor
    public var isEnabled: Bool
    public var order: Int
    public var customDisplayName: String?

    public init(
        descriptor: ApplicationDescriptor,
        isEnabled: Bool,
        order: Int,
        customDisplayName: String? = nil
    ) {
        self.descriptor = descriptor
        self.isEnabled = isEnabled
        self.order = order
        self.customDisplayName = customDisplayName
    }
}

/// Codable menu state keyed semantically by application bundle identifier.
///
/// Entries are retained while an application is uninstalled. A registry only
/// hides unavailable entries, so reinstalling the same bundle identifier
/// restores the previous enabled state and ordering.
public struct ApplicationPreferences: Codable, Hashable, Sendable {
    public private(set) var applications: [ApplicationMenuPreference]

    public init(applications: [ApplicationMenuPreference] = []) {
        self.applications = Self.deduplicated(applications)
    }

    public func preference(forBundleIdentifier bundleIdentifier: String) -> ApplicationMenuPreference? {
        applications.first { $0.descriptor.bundleIdentifier == bundleIdentifier }
    }

    public func isEnabled(bundleIdentifier: String) -> Bool {
        preference(forBundleIdentifier: bundleIdentifier)?.isEnabled ?? false
    }

    public mutating func setEnabled(
        _ isEnabled: Bool,
        for descriptor: ApplicationDescriptor,
        defaultOrder: Int
    ) {
        upsert(descriptor: descriptor, defaultOrder: defaultOrder) { preference in
            preference.isEnabled = isEnabled
        }
    }

    public mutating func setOrder(
        _ order: Int,
        for descriptor: ApplicationDescriptor
    ) {
        upsert(descriptor: descriptor, defaultOrder: order) { preference in
            preference.order = order
        }
    }

    public mutating func setCustomDisplayName(
        _ customDisplayName: String?,
        for descriptor: ApplicationDescriptor,
        defaultOrder: Int
    ) {
        upsert(descriptor: descriptor, defaultOrder: defaultOrder) { preference in
            preference.customDisplayName = customDisplayName
        }
    }

    public mutating func register(
        descriptor: ApplicationDescriptor,
        isEnabled: Bool,
        order: Int
    ) {
        if let index = index(forBundleIdentifier: descriptor.bundleIdentifier) {
            // Prefer a known adapter over generic manually-added metadata while
            // retaining the user's menu choices.
            applications[index].descriptor = descriptor
            applications[index].isEnabled = isEnabled
            applications[index].order = order
        } else {
            applications.append(
                ApplicationMenuPreference(
                    descriptor: descriptor,
                    isEnabled: isEnabled,
                    order: order
                )
            )
        }
    }

    private mutating func upsert(
        descriptor: ApplicationDescriptor,
        defaultOrder: Int,
        update: (inout ApplicationMenuPreference) -> Void
    ) {
        if let index = index(forBundleIdentifier: descriptor.bundleIdentifier) {
            applications[index].descriptor = descriptor
            update(&applications[index])
        } else {
            var preference = ApplicationMenuPreference(
                descriptor: descriptor,
                isEnabled: false,
                order: defaultOrder
            )
            update(&preference)
            applications.append(preference)
        }
    }

    private func index(forBundleIdentifier bundleIdentifier: String) -> Int? {
        applications.firstIndex { $0.descriptor.bundleIdentifier == bundleIdentifier }
    }

    private static func deduplicated(
        _ applications: [ApplicationMenuPreference]
    ) -> [ApplicationMenuPreference] {
        var seen = Set<String>()
        return applications.filter {
            seen.insert($0.descriptor.bundleIdentifier).inserted
        }
    }
}
