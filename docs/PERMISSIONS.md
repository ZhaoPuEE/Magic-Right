# Permissions

Super Right follows progressive permission requests: explain the feature first, request only what that feature needs, and provide diagnostics when macOS denies access.

## Finder extension

The Finder Sync extension supplies the context menu and directory observations. During onboarding, Super Right checks whether the extension is enabled and directs the user to the relevant macOS extension settings when needed.

The extension should be useful without Accessibility permission and must not simulate clicks or keystrokes in Finder.

## Files and folders

Normal user-selected files and destinations use macOS sandbox access and security-scoped bookmarks where persistent access is necessary. Selecting a custom template, application, or destination is an explicit grant for that item; it is not permission to scan adjacent directories.

Some protected locations can still be denied by macOS. Super Right should first report the exact failed action and offer a targeted retry or selection flow.

## Full Disk Access

Full Disk Access is not an onboarding requirement. It should be suggested only after an operation against a protected location fails and the user asks to work there. The permission diagnostics page must explain:

- which selected path triggered the denial;
- which action needs access;
- that enabling Full Disk Access broadens access beyond that path;
- that the user can continue using other locations without granting it.

Super Right must not claim to detect Full Disk Access perfectly: macOS does not expose a general authoritative status API. A targeted read/write probe for the requested operation is better evidence.

## Application launching

Opening a target in another app normally uses Launch Services/`NSWorkspace` and does not require Apple Events automation. Known integrations use structured arguments, not UI automation. Super Right should avoid Apple Events; adding an Apple Events integration later requires a feature-specific explanation and permission review.

Terminal and editor actions pass the selected paths to the target app. They do not grant Super Right access that macOS has not already provided.

## Launch at login

Onboarding may recommend launch at login, but the user must confirm it. The setting should use the supported macOS service-management API and remain reversible in both Super Right and System Settings. It does not require administrator privileges.

## Notifications

Do not request notification permission merely to report a foreground action. If background completion notifications are added, request permission only when the user enables that behavior and keep in-app status available as a fallback.

## Permissions not required by V1

- Accessibility
- Screen Recording
- Contacts, Calendars, Photos, Camera, or Microphone
- Location
- Apple Events automation under the standard open strategies

Any implementation that introduces one of these requirements must update this document and onboarding before release.

## Development signing

The host app and Finder extension require compatible signing and the same App Group entitlement. Local development can use an Xcode Personal Team. A public DMG requires a paid Apple Developer account, Developer ID signing, notarization, and stapling; see [Building and releasing](BUILDING.md).
