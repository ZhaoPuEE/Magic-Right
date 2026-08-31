import Foundation
import Testing
@testable import SuperRightCore

private struct StubApplicationLocator: ApplicationLocating {
    var installed: [String: LocatedApplication]
    var inspected: [URL: LocatedApplication] = [:]

    func locateApplication(bundleIdentifier: String) -> LocatedApplication? {
        installed[bundleIdentifier]
    }

    func inspectApplication(at applicationURL: URL) -> LocatedApplication? {
        inspected[applicationURL]
    }
}

private final class RecordingApplicationLocator: ApplicationLocating, @unchecked Sendable {
    private let lock = NSLock()
    private let installed: [String: LocatedApplication]
    private var requestedIdentifiers: [String] = []

    init(installed: [String: LocatedApplication]) {
        self.installed = installed
    }

    func locateApplication(bundleIdentifier: String) -> LocatedApplication? {
        lock.lock()
        requestedIdentifiers.append(bundleIdentifier)
        lock.unlock()
        return installed[bundleIdentifier]
    }

    func inspectApplication(at applicationURL: URL) -> LocatedApplication? {
        nil
    }

    func requests() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return requestedIdentifiers
    }
}

@Suite("Dynamic application registry")
struct ApplicationRegistryTests {
    private let zedBundleIdentifier = "dev.zed.Zed"

    @Test("Finder menu resolves only enabled applications")
    func visibleMenuSkipsDisabledApplicationLookups() throws {
        let catalog = KnownApplicationCatalog.standard
        let vscode = try #require(
            catalog.descriptor(forBundleIdentifier: "com.microsoft.VSCode")
        )
        var preferences = ApplicationPreferences()
        preferences.setEnabled(true, for: vscode, defaultOrder: 0)
        let locator = RecordingApplicationLocator(installed: [
            "com.microsoft.VSCode": LocatedApplication(
                bundleIdentifier: "com.microsoft.VSCode",
                applicationURL: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
                displayName: "Visual Studio Code"
            ),
            zedBundleIdentifier: LocatedApplication(
                bundleIdentifier: zedBundleIdentifier,
                applicationURL: URL(fileURLWithPath: "/Applications/Zed.app"),
                displayName: "Zed"
            )
        ])
        let registry = ApplicationRegistry(
            catalog: catalog,
            preferences: preferences,
            locator: locator
        )

        #expect(
            registry.visibleEnabledApplications().map(\.bundleIdentifier)
                == ["com.microsoft.VSCode"]
        )
        #expect(locator.requests() == ["com.microsoft.VSCode"])
    }

    @Test("A newly installed Zed is discovered but does not pollute the menu")
    func newlyInstalledZedIsAvailableButDisabled() {
        let zedURL = URL(fileURLWithPath: "/Applications/Zed.app")
        let locator = StubApplicationLocator(installed: [
            zedBundleIdentifier: LocatedApplication(
                bundleIdentifier: zedBundleIdentifier,
                applicationURL: zedURL,
                displayName: "Zed"
            )
        ])
        let registry = ApplicationRegistry(locator: locator)

        #expect(registry.detectedApplications().map(\.bundleIdentifier) == [zedBundleIdentifier])
        #expect(registry.visibleEnabledApplications().isEmpty)
    }

    @Test("First run enables promised terminals and editors but not Zed")
    func developerDefaults() {
        let preferences = ApplicationPreferences.developerDefaults

        #expect(preferences.isEnabled(bundleIdentifier: "com.apple.Terminal"))
        #expect(preferences.isEnabled(bundleIdentifier: "org.tabby"))
        #expect(preferences.isEnabled(bundleIdentifier: "com.mitchellh.ghostty"))
        #expect(preferences.isEnabled(bundleIdentifier: "com.microsoft.VSCode"))
        #expect(!preferences.isEnabled(bundleIdentifier: zedBundleIdentifier))
    }

    @Test("New developer defaults migrate without overriding explicit choices")
    func missingDeveloperDefaultsAreAddedWithoutOverridingChoices() throws {
        let terminal = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "com.apple.Terminal"
            )
        )
        var legacy = ApplicationPreferences()
        legacy.setEnabled(false, for: terminal, defaultOrder: 7)
        legacy.setCustomDisplayName("My Terminal", for: terminal, defaultOrder: 7)

        let migrated = legacy.addingMissingDeveloperDefaults()

        let terminalPreference = try #require(
            migrated.preference(forBundleIdentifier: "com.apple.Terminal")
        )
        #expect(!terminalPreference.isEnabled)
        #expect(terminalPreference.order == 7)
        #expect(terminalPreference.customDisplayName == "My Terminal")
        #expect(migrated.isEnabled(bundleIdentifier: "com.mitchellh.ghostty"))
        #expect(migrated.isEnabled(bundleIdentifier: "org.tabby"))
        #expect(migrated.isEnabled(bundleIdentifier: "com.microsoft.VSCode"))
    }

    @Test("An explicitly disabled Ghostty stays disabled during migration")
    func disabledGhosttyIsPreserved() throws {
        let ghostty = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: "com.mitchellh.ghostty"
            )
        )
        var legacy = ApplicationPreferences()
        legacy.setEnabled(false, for: ghostty, defaultOrder: 4)

        let migrated = legacy.addingMissingDeveloperDefaults()

        let preference = try #require(
            migrated.preference(forBundleIdentifier: "com.mitchellh.ghostty")
        )
        #expect(!preference.isEnabled)
        #expect(preference.order == 4)
    }

    @Test("An enabled app is hidden on uninstall and restored after reinstall")
    func reinstallRestoresConfigurationAndResolvesNewLocation() throws {
        let descriptor = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: zedBundleIdentifier
            )
        )
        var preferences = ApplicationPreferences()
        preferences.setEnabled(true, for: descriptor, defaultOrder: 3)
        preferences.setCustomDisplayName("My Zed", for: descriptor, defaultOrder: 3)

        let uninstalled = ApplicationRegistry(
            preferences: preferences,
            locator: StubApplicationLocator(installed: [:])
        )
        #expect(uninstalled.visibleEnabledApplications().isEmpty)
        #expect(uninstalled.preferences.isEnabled(bundleIdentifier: zedBundleIdentifier))

        let newURL = URL(fileURLWithPath: "/Volumes/Tools/Zed.app")
        let reinstalled = ApplicationRegistry(
            preferences: uninstalled.preferences,
            locator: StubApplicationLocator(installed: [
                zedBundleIdentifier: LocatedApplication(
                    bundleIdentifier: zedBundleIdentifier,
                    applicationURL: newURL,
                    displayName: "Zed"
                )
            ])
        )

        let visible = reinstalled.visibleEnabledApplications()
        #expect(visible.count == 1)
        #expect(visible.first?.currentApplicationURL == newURL)
        #expect(visible.first?.menuDisplayName == "My Zed")
    }

    @Test("An unknown application can be added without persisting its selected path")
    func manuallyAddsUnknownApplication() throws {
        let appURL = URL(fileURLWithPath: "/Applications/Nova Editor.app")
        let bundleIdentifier = "com.example.nova-editor"
        let located = LocatedApplication(
            bundleIdentifier: bundleIdentifier,
            applicationURL: appURL,
            displayName: "Nova Editor"
        )
        let locator = StubApplicationLocator(
            installed: [bundleIdentifier: located],
            inspected: [appURL: located]
        )
        var registry = ApplicationRegistry(locator: locator)

        let descriptor = try registry.addManualApplication(at: appURL)

        #expect(descriptor.bundleIdentifier == bundleIdentifier)
        #expect(descriptor.adapterKind == .genericURLs)
        #expect(descriptor.source == .manuallyAdded)
        #expect(registry.visibleEnabledApplications().map(\.bundleIdentifier) == [bundleIdentifier])

        let encoded = try JSONEncoder().encode(registry.preferences)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(!json.contains(appURL.path))
        #expect(json.contains(bundleIdentifier))
    }

    @Test("A known app selected manually keeps its known adapter")
    func manualKnownAppUsesCatalogAdapter() throws {
        let appURL = URL(fileURLWithPath: "/Applications/Tabby.app")
        let located = LocatedApplication(
            bundleIdentifier: "org.tabby",
            applicationURL: appURL,
            displayName: "Tabby"
        )
        let locator = StubApplicationLocator(
            installed: ["org.tabby": located],
            inspected: [appURL: located]
        )
        var registry = ApplicationRegistry(locator: locator)

        let descriptor = try registry.addManualApplication(at: appURL)

        #expect(descriptor.adapterKind == .tabby)
        #expect(descriptor.source == .knownCatalog)
    }

    @Test("Preferences survive Codable round-trip")
    func preferencesCodableRoundTrip() throws {
        let descriptor = try #require(
            KnownApplicationCatalog.standard.descriptor(
                forBundleIdentifier: zedBundleIdentifier
            )
        )
        var preferences = ApplicationPreferences()
        preferences.setEnabled(true, for: descriptor, defaultOrder: 2)
        preferences.setCustomDisplayName("Z", for: descriptor, defaultOrder: 2)

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(ApplicationPreferences.self, from: data)

        #expect(decoded == preferences)
    }
}
