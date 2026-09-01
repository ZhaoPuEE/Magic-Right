# Product model

Magic Right treats the Finder context menu as a configurable inventory of actions, not as a dashboard of loosely related modules.

## Primary mental model

The host app answers one user question: **what should appear when I right-click in Finder?**

- The sidebar selects a Finder action group; it does not add another level to the Finder menu.
- The detail pane lists the real actions in that group.
- Each row has a stable action identity, an enable state, an icon, a display name, an availability state, an order, and optional settings.
- A container visibility switch, when a group needs one, is presented separately from its real action rows and never counted as an action.
- Changing a row updates the shared Finder-menu snapshot. The Finder extension never invents a second configuration model.

The sidebar and Finder menu use the same groups:

1. Open With
2. New File
3. Directories
4. Paths & Git
5. File Tools
6. Archive
7. General Settings

Overview is a summary of these groups, not an additional place to configure different values.

Enabled entries appear directly at the first level of Finder's context menu. Magic Right does not add an umbrella submenu. An entry opens a submenu only when the action itself requires another choice, such as a new-file type or destination.

Finder places one enabled, branded Magic Right settings row immediately above the extension's contiguous action block. The row uses the app icon and opens settings instead of presenting as unavailable text. Internal action groups do not add separator rows. Destination actions expose the bounded pinned, frequent, and recent catalog in their own submenu. The menu bar does not duplicate those directory destinations; it retains only lightweight learning, settings, and lifecycle controls.

## Distinctive product model

The action list is only the control surface. The product's differentiating engine is:

- local folder-frequency memory with pinned, frequent, and recent destinations;
- one shared destination catalog reused by Jump To, Move To, and Copy To;
- dynamic application discovery by bundle identifier, including apps installed later;
- context-aware visibility, so irrelevant Git or selection-specific actions stay out of Finder;
- structured, fail-closed execution and collision-safe file operations;
- an open action registry that can grow without hard-coded application paths.

Codex Here is a built-in workflow action rather than another discovered application row. Finder always exposes one Codex Here entry; Settings chooses System Terminal, Ghostty, or Tabby as its execution terminal. The action is visible when Codex and the selected terminal are available and uses the selected item’s directory context. Terminal-specific adapters pass the directory and resolved Codex executable as positional data without synthetic input or path interpolation into executable script source.

The interface expresses these capabilities through Magic Right's own layout, copy, icons, ordering, and visual language.

## Three separate states

Every action must distinguish:

1. **Available**: the implementation exists and any required external app is installed.
2. **Enabled**: the user wants the action in Finder.
3. **Visible in this context**: the current selection makes the action relevant.

For example, an enabled Git action is still hidden outside a repository. An enabled Zed row becomes unavailable when Zed is uninstalled but retains its preference for a future reinstall. Move To and Copy To are available actions; a planned action such as move undo is shown as “In development” and cannot be enabled.

This separation prevents disabled, unavailable, and contextually irrelevant actions from looking like the same state.

## Configuration interaction

- A group header shows `enabled / available` and offers “Enable all available” and “Disable all”.
- A large row toggle is the primary control. The whole row has a clear label and status; the toggle is not an unlabeled checkbox.
- Reordering and advanced options are secondary controls and never obscure enablement.
- Applying Developer, File, or All changes ordinary editable rows; it does not enter a separate product mode.
- Generic presets only change built-in actions. Discovered external applications remain explicit user choices.
- Destructive resets require confirmation and describe exactly which preferences will change.

## Smart directories

“Show Directories in Finder” and “Learn directory visits” are different controls:

- The Finder action toggle controls menu visibility.
- The learning toggle controls local observation and scoring.
- History management remains available while Finder visibility or learning is paused.

This lets a user pause data collection without losing pinned destinations or hide the Jump To entry without destroying history.

## Shared destinations

Pinned, frequent, and recent are views over one local directory history, not three unrelated configuration lists. The Finder extension derives one deduplicated, menu-ready destination catalog from those views and reuses it for:

- **Jump To**: change the current Finder window to the selected destination;
- **Move To**: move the current selection without silently overwriting an existing item;
- **Copy To**: copy the current selection without silently overwriting an existing item.

A custom display name changes menu presentation only; the canonical directory URL remains the operation target. A missing or excluded directory is omitted from active menus without silently deleting its history record.

## Finder boundary

The host app and Finder extension resolve one compact, versioned shared-storage backend. A valid App Group from a formally signed build is always preferred. An ad-hoc or source build without a usable App Group falls back to the `dev.magicright.shared` defaults suite and uses `~/Library/Application Support/Magic Right/Shared` for cross-process coordination files. The extension reads the resolved backend and renders only actions that are implemented, enabled, and relevant to the current selection. It captures the selection and target directory while building the menu so clicking a first-level action does not depend on Finder still exposing transient selection state after the menu closes. A missing first-run configuration uses a small product default; a present but corrupt configuration fails closed with all optional actions disabled.

The host app is non-sandboxed, while macOS plug-in registration requires the Finder extension to be sandboxed. For the current GitHub distribution architecture, that extension receives temporary read/write exceptions for `/Users/`, `/Volumes/`, and `/private/tmp/`, plus shared-preference access to `dev.magicright.shared`. These roots remain subject to TCC and ordinary filesystem permissions. An App Store build would use a separate security-scoped access and migration design.

## Visual and accessibility principles

- Use the existing graphite surface and electric-cyan accent, but reserve cyan for selection and enabled state.
- Keep action rows at least 44 points high with a clear label, description, and text status in addition to color.
- Use native controls, keyboard focus, VoiceOver labels, and visible disabled states.
- Avoid dense spreadsheet presentation, tiny checkbox-only targets, low-contrast text, and icons as the only explanation.
- Keep layout, wording, icons, ordering, and brand assets original and internally consistent.
