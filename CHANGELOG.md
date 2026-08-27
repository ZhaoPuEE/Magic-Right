# Changelog

All notable changes to Super Right are documented here. The project follows Semantic Versioning.

## [0.1.0] - Unreleased

### Added

- Native SwiftUI menu bar host and Finder Sync extension targeting macOS 15.
- Graphite-and-cyan toolbox control center and original application/menu bar icons.
- Bundle-ID application registry with Launch Services resolution, manual `.app` registration, and safe structured opening.
- Known discovery entries for Zed, Visual Studio Code, Tabby, Terminal, Cursor, VSCodium, iTerm2, Warp, Ghostty, Sublime Text, Nova, common JetBrains IDEs, and Git clients.
- Seven collision-safe built-in New File presets.
- Local smart-directory history with pinned, frequent, recent, search, rename, exclusion, pause, deletion, and clear controls.
- Absolute path, `file://` URL, and shell-safe path copy actions.
- Swift package tests, unsigned Xcode verification, and non-overwriting DMG packaging scripts.

### Validation status

- Shared Core tests and unsigned arm64 Debug/Release builds pass locally.
- The test DMG layout and checksum are verified locally.
- Signed installation, Finder context-menu visibility, App Group behavior, arbitrary-folder writes, and notarization remain pending.
