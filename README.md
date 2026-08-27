# Super Right

[简体中文](README.zh-CN.md)

Super Right is a native, open-source macOS utility that turns the Finder context menu into a practical launchpad for developers and everyday file work. It combines a lightweight Finder Sync extension with a menu bar app for configuration, permissions, history, and longer-running operations.

> Super Right is under active development. The items below describe the V1 product scope; there is no stable public release yet.

## Why Super Right

- Open a selected file or folder in Terminal, Tabby, Visual Studio Code, Zed, and other installed apps.
- Discover newly installed apps dynamically instead of relying on hard-coded `/Applications` paths.
- Learn frequently visited folders locally and expose pinned, frequent, and recent destinations.
- Create real files from built-in or user-imported templates, including valid Office documents.
- Put useful path, Git, archive, move, copy, and inspection actions close to the selection.
- Keep risky work out of the Finder extension: file operations run in the host app, avoid silent overwrites, and retain a recoverable operation record.
- Stay free and open source under the MIT License, without a subscription tier.

## Planned V1

### Open with any app

Super Right stores applications by bundle identifier and resolves their current location with Launch Services when an action runs. A newly installed app such as Zed appears in Settings as available, but is not added to Finder until the user enables it. Uninstalled apps disappear from the menu; reinstalling the same bundle restores the previous preference.

Known apps can use purpose-built, structured launch arguments. Other apps use the standard macOS open mechanism or a user-selected `.app`. Super Right does not execute user-provided shell command strings.

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

Actions are organized into configurable groups: New File, Move To, Copy To, Folders, Archive, Open With, Git, and Tools. Groups can be reordered, renamed, kept inside one Super Right submenu, or promoted as selected high-frequency actions.

### Toolbox control center

The host app is also the control center for the Finder experience. Its sidebar contains **Overview**, **Open With**, **New File & Templates**, **Smart Folders**, **Paths & Git**, **File Tools**, **Archive**, and **Settings**. Each capability can be enabled, reordered, renamed, and independently included in or removed from the Finder menu.

Three starting presets make configuration quick without locking it down:

- **Developer** emphasizes editors, terminals, paths, and Git.
- **File** emphasizes creation, destinations, archives, and safe file operations.
- **All** enables the complete supported tool set.

Applying a preset updates the editable configuration; it is not a permanent mode. Super Right may study the interaction patterns of established context-menu utilities, but its code, interface copy, icon, templates, and other brand assets must be original and must not reproduce a competitor's protected assets.

## Platform and design

- macOS 15 or later
- Swift 6, SwiftUI, and AppKit
- A menu bar host app plus a Finder Sync extension
- Shared state through an App Group
- Local DMG distribution; Developer ID signing and notarization are required for public releases

The original visual direction is a macOS rounded-square icon with graphite translucent glass, an electric-cyan accent, and three context-menu rows whose highlighted middle row contains `>_`. The menu bar uses a simplified monochrome template icon. The identity deliberately avoids mouse imagery, lightning bolts, and `SR` initials, and must be checked at 16 through 1024 pixels in light, dark, and system-tinted appearances before release.

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
./scripts/create-dmg.sh "/path/to/Super Right.app" ./dist
```

The result contains the app and an `Applications` symlink for drag-and-drop installation. The script neither signs nor notarizes anything.

## Project principles

- Finder stays responsive; long work belongs to the host app.
- External apps are identities (bundle IDs), not fixed paths.
- Paths are passed as structured arguments, never interpolated into a shell command.
- User files are never silently overwritten.
- Directory-learning data stays local and never inspects directory contents.
- Build products, DMGs, certificates, credentials, and notarization profiles do not belong in Git.
- Competitor behavior may inform product research, but implementation, wording, icons, and bundled assets must remain original.

## Contributing

Use the `main` branch, keep changes small and reviewable, add tests for shared behavior, and run `./scripts/verify-project.sh` before proposing a change. Please do not commit signing material or generated release artifacts.

## License

Super Right is available under the [MIT License](LICENSE).
