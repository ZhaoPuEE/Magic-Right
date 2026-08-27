# Product model

Magic Right treats the Finder context menu as a configurable inventory of actions, not as a dashboard of loosely related modules.

## Primary mental model

The host app answers one user question: **what should appear when I right-click in Finder?**

- The sidebar selects a Finder action group.
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

## Distinctive product model

The action list is only the control surface. The product's differentiating engine is:

- local folder-frequency memory with pinned, frequent, and recent destinations;
- dynamic application discovery by bundle identifier, including apps installed later;
- context-aware visibility, so irrelevant Git or selection-specific actions stay out of Finder;
- structured, fail-closed execution and collision-safe file operations;
- an open action registry that can grow without hard-coded application paths.

The interface should express these capabilities in Magic Right's own visual language. It must not imitate another product's layout, copy, icons, ordering, or branded assets.

## Three separate states

Every action must distinguish:

1. **Available**: the implementation exists and any required external app is installed.
2. **Enabled**: the user wants the action in Finder.
3. **Visible in this context**: the current selection makes the action relevant.

For example, an enabled Git action is still hidden outside a repository. An enabled Zed row becomes unavailable when Zed is uninstalled but retains its preference for a future reinstall. A planned action is shown as “In development” and cannot be enabled.

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

This lets a user pause data collection without losing pinned destinations or hide the submenu without destroying history.

## Finder boundary

The host app writes a compact, versioned App Group snapshot. The Finder extension reads it and renders only actions that are implemented, enabled, and relevant to the current selection. A missing first-run configuration uses a small product default; a present but corrupt configuration fails closed with all optional actions disabled.

## Visual and accessibility principles

- Use the existing graphite surface and electric-cyan accent, but reserve cyan for selection and enabled state.
- Keep action rows at least 44 points high with a clear label, description, and text status in addition to color.
- Use native controls, keyboard focus, VoiceOver labels, and visible disabled states.
- Avoid dense spreadsheet presentation, tiny checkbox-only targets, low-contrast text, and icons as the only explanation.
- Keep layout, wording, icons, ordering, and brand assets original and internally consistent.
