# Changelog

All notable changes to Magic Right are documented here. The project follows Semantic Versioning.

## [Unreleased]

### Fixed

- Opening a Finder directory in Ghostty now uses Ghostty's native macOS directory-open handler, preserving the selected working directory and the user's loaded appearance configuration instead of launching a separate application instance.

## [0.1.1] - 2026-09-01

### Fixed

- Tabby Codex Here now creates a window when the Tabby process has none, while still reusing the existing single instance.
- Interrupting or exiting Codex in a Tabby Codex Here tab now returns to an interactive local zsh in the same directory instead of closing the terminal session.

## [0.1.0] - 2026-09-01

### Added

- Native SwiftUI menu bar host and Finder Sync extension targeting macOS 15.
- Lightweight native action control center and original application/menu bar icons.
- Bundle-ID application registry with Launch Services resolution, manual `.app` registration, and safe structured opening.
- One default-enabled Codex Here Finder action with a Settings choice of System Terminal, Ghostty, or Tabby, positional path handling, and a runtime-loaded local Codex icon.
- Version and build information in Settings, with development-only explanatory copy removed from the product UI.
- Known discovery entries for Zed, Visual Studio Code, Tabby, Terminal, Cursor, VSCodium, iTerm2, Warp, Ghostty, Sublime Text, Nova, common JetBrains IDEs, and Git clients; Ghostty now has a directory-aware structured adapter and is enabled by the developer default migration.
- Seven collision-safe built-in New File presets.
- Local smart-directory history with pinned, frequent, recent, search, rename, exclusion, pause, deletion, and clear controls.
- First-level Finder action entries without an umbrella Magic Right submenu, grouped under a branded, enabled Magic Right settings row and without internal top-level separators.
- Shared pinned/frequent/recent destinations for Jump To, Move To, and Copy To.
- Collision-safe move/copy execution with captured Finder context and a local operation journal.
- Shared-storage resolution that prefers a valid App Group and, when it is unavailable to an ad-hoc/source build, falls back to the `dev.magicright.shared` defaults suite plus `~/Library/Application Support/Magic Right/Shared`.
- App Group eligibility checks and minimal ad-hoc signing entitlements that prevent preview builds without a Team ID from probing or declaring another app-data container and repeatedly triggering macOS permission prompts.
- A non-sandboxed host plus the sandboxed Finder extension required by macOS plug-in registration.
- Non-App-Store Finder-extension temporary exceptions for read/write access under `/Users/`, `/Volumes/`, and `/private/tmp/`, plus shared-preference access to `dev.magicright.shared`; security-scoped bookmark persistence is not implemented.
- Absolute-path and shell-safe-path copy actions.
- An opt-in launch-at-login setting implemented with `SMAppService.mainApp`.
- Finder Sync actions retain their concrete extension target while scalar menu tags resolve captured selection and destination context after Finder serializes the menu.
- Tabby's directory adapter now uses its public `tabby://open` URL so an existing window receives a new tab instead of a forced application instance.
- Finder actions are suppressed whenever the Magic Right menu bar host is not running, even though macOS keeps the Finder Sync process loaded independently.
- The menu bar no longer duplicates pinned/frequent/recent destinations; Finder owns the destination-jump interaction.
- Frequent-directory jumps navigate the current Finder window, request Finder Automation only through macOS, and pass destination paths as positional data rather than script source.
- Swift package tests, unsigned Xcode verification, and non-overwriting DMG packaging scripts.
- Standard macOS file-URL clipboard interoperability, including explicit cut finalization errors and preservation of journal/reveal results after partial or completed transfers.
- ZIP creation limits that monitor temporary output, cap generated data, preserve free space on both temporary and destination volumes, and fail closed before the startup disk can be exhausted.
- Symbolic-link aware Git discovery and file operations, including safe handling of broken links as real Finder items.
- A project-owner-selected anime-style Finder helper AppIcon with transparent outer corners, a branded About card, and release-focused English and Chinese READMEs.
- GitHub Actions verification for Core tests plus unsigned Debug and Release builds.

### Validation status

- 135 Shared Core tests and unsigned arm64 Debug/Release builds pass locally.
- A Magic Right branded, signed, and notarized DMG has not been produced yet.
- The latest Finder execution path, the validly signed App Group backend, protected-folder writes, and notarization still require signed end-to-end validation.
