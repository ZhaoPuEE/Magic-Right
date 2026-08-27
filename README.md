# Magic Right

[简体中文](README.zh-CN.md)

<p align="center"><img src="Design/AppIcon-master.png" width="160" alt="Magic Right icon"></p>

Magic Right is an independent, native, open-source macOS utility that extends the Finder context menu for development and everyday file work. It combines a lightweight Finder Sync extension with a menu bar app for configuration, permissions, history, and longer-running operations.

> Magic Right is under active development. The items below describe the V1 product scope; there is no stable public release yet.

## Current prototype (0.1.0)

Implemented and source-verified today:

- Native menu bar app, toolbox settings UI, and Finder Sync extension project.
- Bundle-ID discovery for common editors, terminals, IDEs, and Git clients, plus manual registration of any `.app`.
- Structured Finder opening for Terminal, Tabby, Visual Studio Code, Zed, and compatible applications.
- Seven collision-safe New File presets: Markdown, TXT, RTF, XML, JSON, YAML, and `.gitignore`.
- Local smart folders with a two-second dwell threshold, 30-minute deduplication, 30-day scoring half-life, pinned/frequent/recent views, search, rename, exclusion, and clearing.
- Absolute, `file://`, and shell-safe path copying.
- Original AppIcon and menu bar template icon, source verification, and DMG packaging scripts.

Office/custom templates, Git actions, move/copy/undo, archives, and file inspection remain later V1 work. No Magic Right DMG is currently release-ready. Real Finder-extension installation, cross-process App Group sharing, and write access in arbitrary Finder locations still require a user-visible test with a valid development team and App Group provisioning in Xcode.

## Why Magic Right

- Open a selected file or folder in Terminal, Tabby, Visual Studio Code, Zed, and other installed apps.
- Discover newly installed apps dynamically instead of relying on hard-coded `/Applications` paths.
- Learn frequently visited folders locally and expose pinned, frequent, and recent destinations.
- Create real files from built-in or user-imported templates, including valid Office documents.
- Put useful path, Git, archive, move, copy, and inspection actions close to the selection.
- Keep risky work out of the Finder extension: file operations run in the host app, avoid silent overwrites, and retain a recoverable operation record.
- Stay free and open source under the MIT License, without a subscription tier.

The project is built around capabilities that remain useful beyond a static menu: local folder-frequency memory, context-aware action visibility, bundle-ID based discovery of newly installed apps, structured launches without shell-string evaluation, and recoverable file-operation contracts. Its source and local data model are designed to stay inspectable and extensible.

## Planned V1

### Open with any app

Magic Right stores applications by bundle identifier and resolves their current location with Launch Services when an action runs. A newly installed app such as Zed appears in Settings as available, but is not added to Finder until the user enables it. Uninstalled apps disappear from the menu; reinstalling the same bundle restores the previous preference.

Known apps can use purpose-built, structured launch arguments. Other apps use the standard macOS open mechanism or a user-selected `.app`. Magic Right does not execute user-provided shell command strings.

### Smart folders

The menu bar app and Finder menu provide three local lists:

- **Pinned**: destinations chosen explicitly by the user.
- **Frequent**: folders ranked by frequency and recency.
- **Recent**: the latest observed destinations.

Learning records folder paths and timestamps only. It does not enumerate folder contents or send history off the Mac. Users can pause learning, exclude paths, rename or pin entries, remove individual records, or clear the complete history.

### Finder actions

- New Markdown, text, RTF, XML, JSON, YAML, `.gitignore`, DOCX, XLSX, and PPTX files, plus custom templates.
- Absolute, shell-safe, `file://`, and Git-relative path copying.
- Git repository root and remote actions, shown only when applicable.
- Collision-safe move/copy destinations and undo for the most recent move.
- ZIP, tar, and tar.gz creation; guarded extraction through a validated temporary location.
- File information and on-demand hashes.

Actions are organized into configurable groups: New File, Move To, Copy To, Folders, Archive, Open With, Git, and Tools. Groups can be reordered, renamed, kept inside one Magic Right submenu, or promoted as selected high-frequency actions.

### Toolbox control center

The host app is also the control center for the Finder experience. Its sidebar contains **Overview**, **Open With**, **New File & Templates**, **Smart Folders**, **Paths & Git**, **File Tools**, **Archive**, and **Settings**. Each capability can be enabled, reordered, renamed, and independently included in or removed from the Finder menu.

Three starting presets make configuration quick without locking it down:

- **Developer** enables the application-action entry point, paths, and Git tools.
- **File** emphasizes creation, destinations, archives, and safe file operations.
- **All** enables every supported built-in action.

Applying a preset updates the editable built-in configuration; it is not a permanent mode. Discovered external applications remain opt-in so installing a new editor never changes the Finder menu by itself. The shipped code, interface copy, icon, templates, and bundled assets are original or use a documented compatible license.

## Platform and design

- macOS 15 or later
- Swift 6, SwiftUI, and AppKit
- A menu bar host app plus a Finder Sync extension
- Shared state through an App Group
- Source and DMG distribution through GitHub Releases, not the Mac App Store
- Developer ID signing and notarization are required before a public DMG is described as ready for ordinary users

The app icon uses an original graphite-and-cyan context-menu composition. The menu bar icon is a separate monochrome template: a transparent mouse outline with the right button emphasized. Both assets must be checked at 16 through 1024 pixels, as applicable, in light, dark, and system-tinted appearances before release. Source notes live in [Design/ASSET_NOTES.md](Design/ASSET_NOTES.md).

See [Architecture](docs/ARCHITECTURE.md), [Privacy](docs/PRIVACY.md), and [Permissions](docs/PERMISSIONS.md) for the product contracts behind these choices.

## Build from source

Open `SuperRight.xcodeproj` in Xcode and select the `SuperRight` scheme, or run:

```sh
./scripts/verify-project.sh
```

The verification script runs Swift package tests when a `Package.swift` exists at the root or one level below `Packages`, lists Xcode schemes, and performs an unsigned Debug build with temporary SwiftPM caches and Derived Data. A different scheme can be passed as the first argument or through `SUPER_RIGHT_SCHEME`.

For detailed development signing, Finder extension setup, Release builds, DMG packaging, and the notarized release boundary, read [Building and releasing](docs/BUILDING.md).

To package an already built app without overwriting an existing image:

```sh
./scripts/create-dmg.sh "/path/to/Magic Right.app" ./dist
```

The result contains the app and an `Applications` symlink for drag-and-drop installation. The script neither signs nor notarizes anything.

## Project principles

- Finder stays responsive; long work belongs to the host app.
- External apps are identities (bundle IDs), not fixed paths.
- Paths are passed as structured arguments, never interpolated into a shell command.
- User files are never silently overwritten.
- Directory-learning data stays local and never inspects directory contents.
- Build products, DMGs, certificates, credentials, and notarization profiles do not belong in Git.
- Shipped implementation, wording, icons, templates, and bundled assets must be original or carry a documented compatible license.

## Contributing

Use the `main` branch, keep changes small and reviewable, add tests for shared behavior, and run `./scripts/verify-project.sh` before proposing a change. Please do not commit signing material or generated release artifacts.

See the [CHANGELOG](CHANGELOG.md) for version progress.

## License

Magic Right is available under the [MIT License](LICENSE).
