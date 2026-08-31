# Magic Right

<p align="center">
  <img src="Design/AppIcon-master.png" width="144" alt="Magic Right icon">
</p>

<h3 align="center">A lightweight, open-source Finder context-menu toolkit for macOS</h3>

<p align="center">
  Open the current path in any app, learn useful destinations, and work with the system file clipboard—<br>
  all within one right-click.
</p>

<p align="center">
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-111111?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="MIT License" src="https://img.shields.io/badge/License-MIT-2563EB">
</p>

<p align="center"><a href="README.zh-CN.md">简体中文</a></p>

> **0.1.0 open-source preview:** Core tests and Debug/Release compilation pass locally on Apple silicon. A public DMG still requires a valid Developer ID signature, Apple notarization, and clean-machine installation validation; build from source for now. Intel Macs have not been validated yet.

## One right-click, connected to your workflow

| Capability | How Magic Right handles it |
| --- | --- |
| **Open in apps** | Detect common editors, terminals, IDEs, and Git clients, or manually choose any valid `.app`. Magic Right stores only its bundle identifier, so Launch Services can find it after it moves or is reinstalled. |
| **Smart destinations** | Learn folders you actually visit in Finder and share Pinned / Frequent / Recent destinations across Jump To, Move To, and Copy To. Folder contents are never scanned and history never leaves the Mac. |
| **System file clipboard** | Cut and copy use `NSPasteboard.general` and standard `public.file-url` items, so Finder, Deck, and other compatible macOS apps can read them. It is not a Magic Right-only clipboard. |
| **Codex Here!** | Keep one Finder action and choose System Terminal, Ghostty, or Tabby in Settings to start local Codex in the current directory. |
| **File toolbox** | Create seven development file types safely, copy paths and Git context, inspect files and SHA-256, create ZIP archives, validate extraction, and move or copy without silent overwrites. |

Enabled actions sit directly at the first level of Finder's context menu. Only actions that need another choice—such as a file type or destination—open their own focused submenu.

## Interface

Magic Right is both a menu bar app and the control center for its Finder actions. The sidebar separates Application Actions, Create Files, Smart Directories, Paths & Repositories, File Operations, and Archives; every capability can independently enter or leave Finder.

<!-- A real-device screenshot will be added at docs/images/control-center.png after current-version validation. -->

## Start in three minutes

### 1. Run from source

You need **macOS 15 or later** and Xcode with the macOS 15 SDK. Current validation runs on Apple silicon.

```sh
git clone https://github.com/ZhaoPuEE/Magic-Right.git
cd Magic-Right
open SuperRight.xcodeproj
```

Select the `SuperRight` scheme and **My Mac**, then run the host app once.

### 2. Enable the Finder extension

Open Magic Right → **Preferences** → **Open Extension Settings**, then enable the Magic Right Finder extension in macOS System Settings. Finder shows Magic Right actions only while the menu bar host is running; quitting the host removes them automatically.

### 3. Choose your actions

- Enable discovered apps under **Application Actions**, or manually register any valid `.app`.
- Choose System Terminal, Ghostty, or Tabby for **Codex Here!**.
- Pin, rename, exclude, or clear destinations under **Smart Directories**.
- Start with the Developer, File, or All Built-ins preset, then tune individual actions.
- Optionally enable Launch at Login; it is off by default.

## Core capabilities

### Open the current path in any app

Built-in integrations are discovered by bundle identifier. Manual registration accepts a valid `.app` with readable bundle metadata, stores its bundle identifier, and resolves its current location through Launch Services each time it is used.

Terminal, Tabby, and Ghostty have directory-aware behavior. Other manually registered apps use standard macOS URL opening by default. Magic Right neither stores a fixed `/Applications/...` path nor executes user-provided shell strings.

### Codex Here!

Finder keeps a single `Codex Here!` action while Settings chooses the terminal:

- **System Terminal** creates a local tab in the existing window. macOS asks for Automation permission on first use.
- **Ghostty** receives the working directory and directly runs the resolved Codex executable.
- **Tabby** reuses its existing instance and opens a local interactive zsh tab in the current directory.

No keyboard input is simulated, and Finder paths are never interpolated into executable script source. The Finder action appears only when both the chosen terminal and local Codex executable can be resolved.

### Destinations that learn

Magic Right records Finder visits observed under supported local roots and folders opened through Magic Right. It stores normalized paths, counts, and timestamps only:

- a visit counts after a two-second dwell;
- repeated observations within 30 minutes are deduplicated;
- frequent ranking uses a 30-day half-life;
- missing, excluded, or unavailable-volume paths stay out of the menu.

Pinned / Frequent / Recent destinations are shared by Jump To, Move To, and Copy To. Jump To switches the current Finder window and creates a window only when none exists.

### The real macOS clipboard

Cut writes standard `public.file-url` items to the macOS system clipboard, so Finder, Deck, and other compatible apps can read them. Magic Right adds private cut metadata only for its own Paste action:

- items cut by Magic Right are moved;
- standard file URLs from other apps are copied;
- private cut protocols from other apps are not guessed;
- an existing destination name is never silently overwritten.

### Practical file and repository actions

- Create Markdown, TXT, RTF, XML, JSON, YAML, and `.gitignore` files with collision-safe naming.
- Copy absolute, shell-safe, and Git-root-relative paths.
- Open the Git root, an editor, or the remote repository page, and copy the origin URL.
- Inspect file size, type, timestamps, and on-demand SHA-256.
- Create ZIP archives; safely extract ZIP, tar, tar.gz, and tgz.
- Create Finder aliases; move, copy, cut, and paste without silent overwrites.

Copy Shell-safe Path only encodes each selected path as a paste-ready argument for zsh, bash, or sh. It never executes a command and cannot make an arbitrary surrounding command inherently safe.

## Privacy and security

- Directory learning stays local, never reads folder contents, and sends no telemetry.
- External apps are represented by bundle identifier, and paths travel as structured arguments.
- User file operations reject silent overwrites and retain local outcomes.
- Host/extension permissions, shared storage, and non-App-Store distribution boundaries are documented in [Privacy](docs/PRIVACY.md), [Permissions](docs/PERMISSIONS.md), and [Architecture](docs/ARCHITECTURE.md).

Magic Right is distributed through GitHub rather than the Mac App Store. Its current supported file roots are `/Users/`, `/Volumes/`, and `/private/tmp/`, still subject to macOS TCC and ordinary file permissions.

## Development and validation

```sh
./scripts/verify-project.sh
```

The verification script runs Swift Package tests, lists Xcode schemes, and performs an unsigned Debug build. See [Building and releasing](docs/BUILDING.md) for Release builds, Finder extension validation, Developer ID signing, notarization, and DMG packaging.

The project follows a few simple rules: keep Finder's main thread light, never interpolate user paths into shell commands, never silently overwrite files, and ship only original or compatibly licensed assets.

Issues and pull requests are welcome. Read [Architecture](docs/ARCHITECTURE.md) and the [Changelog](CHANGELOG.md) before contributing.

## License

Magic Right is available under the [MIT License](LICENSE).

`Codex` is a trademark of OpenAI. Magic Right is not affiliated with, sponsored by, or endorsed by OpenAI. The Codex icon is loaded at runtime from a locally installed app and is not redistributed in this repository or its installation media.
