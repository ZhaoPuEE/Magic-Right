# Permissions

Magic Right follows progressive permission requests: explain the feature first, request only what that feature needs, and provide diagnostics when macOS denies access.

## Finder extension

The Finder Sync extension supplies the context menu and directory observations. During onboarding, Magic Right checks whether the extension is enabled and directs the user to the relevant macOS extension settings when needed.

The extension should be useful without Accessibility permission and must not simulate clicks or keystrokes in Finder.

## Files and folders

The host app sets `ENABLE_APP_SANDBOX = NO`. The Finder extension sets `ENABLE_APP_SANDBOX = YES` because macOS plug-in registration rejects unsandboxed Finder extensions.

For the current open-source, non-App-Store GitHub/Developer ID build, the extension has the `com.apple.security.temporary-exception.files.absolute-path.read-write` entitlement only for `/Users/`, `/Volumes/`, and `/private/tmp/`. It also has `com.apple.security.temporary-exception.shared-preference.read-write` for the fallback `dev.magicright.shared` suite. A valid App Group is still preferred when signing makes it available.

The extension can operate inside those roots subject to TCC, ACLs, ownership, and read-only volume rules. Paths outside them are outside its read/write scope. An App Store build would use a separate security-scoped access model.

Some protected locations can still be denied by macOS. Magic Right should first report the exact failed action and offer a targeted retry or selection flow.

## Full Disk Access

Full Disk Access is not an onboarding requirement, and granting it does not expand the extension entitlement beyond the declared sandbox roots. It should be suggested only after an operation within an entitled root fails against a protected location and the user asks to work there. The permission diagnostics page must explain:

- which selected path triggered the denial;
- which action needs access;
- that enabling Full Disk Access broadens access beyond that path;
- that the user can continue using other locations without granting it.

macOS does not expose a general Full Disk Access status API, so diagnostics use a targeted read/write probe for the requested operation.

## Application launching

Opening a target in another app normally uses Launch Services/`NSWorkspace` and does not require Apple Events automation. Known integrations use structured arguments, not UI automation.

The frequent-directory **Jump To** action is the exception: it asks the Magic Right host to change the target of Finder's current front window instead of opening another window. macOS requests Finder Automation consent on first use and retains that choice for the same stably signed app identity. The directory path is passed to `/usr/bin/osascript` as a positional argument and is never interpolated into AppleScript source. If there is no Finder window, the action creates one and then sets its target. Accessibility permission and simulated input are not used.

macOS associates Automation consent with the app's code identity. Replacing a local ad-hoc build can trigger the system prompt again, while a consistently Developer ID signed build keeps the same identity across updates. Magic Right does not add a per-action confirmation dialog.

Terminal and editor actions pass the selected paths to the target app. They do not grant Magic Right access that macOS has not already provided.

Codex Here keeps one Finder entry and lets the user choose System Terminal, Ghostty, or Tabby in Settings. Ghostty receives a working-directory option plus the resolved Codex executable as separate arguments. Tabby receives a constant local-zsh program whose directory and Codex executable are positional parameters; its single-instance handoff creates a window when needed, and Codex runs as a foreground child so the tab returns to zsh afterward. System Terminal uses AppleScript `quoted form` on positional arguments and may request Terminal Automation consent on first use. Finder-controlled values are not evaluated as shell source, and Magic Right does not paste text or simulate input. The Codex menu image is read at runtime from the locally installed `com.openai.codex` application and is not bundled or redistributed by Magic Right.

Copy Shell-safe Path only transforms selected paths into POSIX shell words and writes the result to the clipboard. It single-quotes each path, escapes embedded single quotes, and separates multiple arguments with spaces. It does not invoke a shell or validate any surrounding command assembled by the user.

## Launch at login

Launch at login is off until the user enables it. Magic Right uses `SMAppService.mainApp`, shows whether macOS still requires approval, and keeps the choice reversible in both Magic Right and System Settings. It does not require administrator privileges.

## Notifications

Do not request notification permission merely to report a foreground action. If background completion notifications are added, request permission only when the user enables that behavior and keep in-app status available as a fallback.

## Permissions not required by V1

- Accessibility
- Screen Recording
- Contacts, Calendars, Photos, Camera, or Microphone
- Location
- Apple Events automation beyond current-window Finder navigation and the optional System Terminal Codex Here adapter

Any implementation that introduces one of these requirements must update this document and onboarding before release.

## Development signing

The preferred backend requires compatible signing for the host app and Finder extension plus the same `group.dev.magicright.app` App Group entitlement. Magic Right selects it only when the running code has a non-empty Team ID and the exact entitlement. Local source and community builds use the `dev.magicright.shared` preference suite plus `~/Library/Application Support/Magic Right/Shared`; the minimal files under `Signing/AdHoc` intentionally omit App Group entitlements. See [Building and releasing](BUILDING.md) for both community and notarized release workflows.
