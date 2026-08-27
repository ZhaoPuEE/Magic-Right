# Architecture

This document defines the intended V1 boundaries. It is a contract for implementation and review, not a claim that every component is already complete.

## System shape

Magic Right uses a native macOS container app with a Finder Sync extension and a shared core:

```text
Finder selection / observed directory
                |
                v
      Finder Sync extension
       (menu + context only)
                |
       App Group shared state
                |
                v
      Menu bar host application
  (settings, permissions, long work)
                |
                v
 Launch Services / file system / Git
```

The targets are expected to remain separable:

- **Magic Right host app**: SwiftUI settings and onboarding, menu bar UI, app discovery, permissions diagnostics, directory history, operation dispatch, and long-running work.
- **Finder Sync extension**: selection resolution, context-aware menu generation, observation events, and lightweight requests to the host app.
- **Shared Core**: data models, scoring, menu configuration, path and Git logic, application adapters, archive validation, collision naming, and persistence contracts.
- **Tests**: deterministic tests for Shared Core behavior. File-system tests use isolated temporary directories.

The extension must not compress archives, hash large files, enumerate directory trees, or perform multi-file moves. It obtains the selected URLs, builds a menu from already shared configuration, and sends a structured request to the host app.

## Toolbox control center

The host app presents one coherent configuration surface rather than a collection of unrelated preference panels. Its primary sections are:

1. **Overview**: extension status, permission diagnostics, current preset, learning state, and recent operation result.
2. **Open With**: discovered applications, known adapters, enable/order/name controls, manual `.app` selection, and Finder visibility.
3. **New File & Templates**: built-in types, imported templates, collision naming, icons, ordering, and Finder visibility.
4. **Smart Folders**: pinned/frequent/recent lists, search, exclusions, pause, deletion, and ranking settings exposed by the product.
5. **Paths & Git**: path representations and context-sensitive repository actions.
6. **File Tools**: information, hashes, aliases, safe move/copy destinations, and recoverable operation history.
7. **Archive**: supported create/extract formats and extraction safety outcomes.
8. **Settings**: menu composition, login item, appearance, permissions, privacy controls, diagnostics, and product information.

Every action definition has stable identity plus user-editable enable state, order, display name, and Finder-menu visibility. Display-name changes do not alter the action identity. A user may keep actions in the Magic Right submenu or promote selected high-frequency actions, subject to bounded menu-size rules.

The built-in **Developer**, **File**, and **All** presets are seeds for this same configuration model, not separate execution paths. Applying a preset produces ordinary editable settings so later app discovery and user customization behave consistently.

The detailed interaction contract is defined in [Product model](PRODUCT_MODEL.md). In particular, availability, user enablement, and context-sensitive Finder visibility are separate states and must not be collapsed into one toggle.

All shipped implementation and assets must be original or carry a compatible, documented license. External source code, interface text, icons, templates, and brand assets are not part of this architecture.

## Shared state and requests

An App Group is the common boundary between the app and extension. Shared data should be versioned and small enough to read without blocking Finder:

- enabled action groups, order, names, and promoted actions;
- enabled applications identified by bundle ID;
- menu-ready pinned, frequent, and recent directory summaries;
- imported template metadata and security-scoped bookmarks;
- pending structured action requests and compact operation results.

Large or mutable histories belong to the host app's store. The host publishes a menu-ready snapshot rather than making the extension compute scores or migrate storage. Schema changes require an explicit version and a backward-compatible read path during upgrades.

Requests use typed payloads such as `open(appID, urls)`, `openGitRoot(appID, url)`, or `move(urls, destinationBookmarkID)`. A request never contains a command line to evaluate.

## Dynamic application registry

The application registry exists so future tools do not require hard-coded installation paths.

### Identity and discovery

- Persist the application's bundle identifier as its identity.
- Resolve the current application URL through `NSWorkspace`/Launch Services when an action executes.
- Discover known integrations and applications registered to open files or folders when the app launches, Settings opens, or the user requests a rescan.
- Allow the user to select any `.app`; read its bundle identifier and metadata before registration.
- Cache display name and icon only for presentation. A cached `.app` URL is not authoritative.

A discovered app enters the available list but is not automatically inserted into Finder. If an app can no longer be resolved, hide its actions while retaining the user's enable/order preference. Reinstalling the same bundle ID restores that preference.

### Open strategies

The registry chooses the narrowest safe strategy:

1. **Known adapter**: an integration such as Tabby, VS Code, or Zed can provide structured arguments for folders, files, multiple URLs, or a Git root.
2. **Launch Services fallback**: ask `NSWorkspace` to open the selected URLs with the resolved application.
3. **Validated custom template**: support only recognized tokens such as `{path}`, `{paths}`, and `{gitRoot}`, expanded into a process argument array.

No strategy invokes `/bin/sh`, interpolates paths into a command string, or accepts arbitrary scripts. A failure reports the app and target clearly and does not silently switch to a different application.

## Smart directory learning

`DirectoryLearningService` accepts observations from Finder directory callbacks and Magic Right open/navigation actions. It stores the directory URL and event time; it does not list, index, or read files in that directory.

V1 behavior:

- a Finder visit is eligible after the directory remains active for more than two seconds;
- repeat observations of the same path within 30 minutes do not increase its frequency;
- frequent ranking combines visit frequency with recency using an approximately 30-day half-life;
- the Finder menu shows the top eight frequent entries by default;
- complete history is retained until the user deletes it;
- missing paths are hidden from menus but their records remain;
- when learning is enabled, system, hidden, and temporary directories are eligible unless the user excludes them.

Pinned, frequent, and recent are separate views over the history store. User-supplied display names never replace the canonical URL. Any persisted external destination that needs sandbox access uses a security-scoped bookmark, with stale bookmark renewal handled by the host app.

## File operations

All mutations follow the same safety contract:

- standardize and validate source and destination URLs;
- resolve access through user intent and security-scoped bookmarks;
- choose a numbered collision-safe name instead of overwriting;
- stage work when partial results would be unsafe;
- record enough metadata to explain the result and support the promised undo operation;
- surface partial failure per item for multi-selection actions.

The V1 undo contract covers the most recent move initiated by Magic Right. Undo must refuse to overwrite a file created at the original path after the move.

New Office documents must come from valid minimal package templates and be verified by opening them in Microsoft Word, Excel, and PowerPoint during release testing. Appending an Office extension to an empty file is invalid.

## Archive boundary

V1 uses system-supported ZIP, tar, and tar.gz formats and does not bundle 7z/RAR binaries. Extraction first targets a private temporary directory. Before results move to the final destination, validate every archive entry against:

- absolute paths;
- `..` traversal outside the extraction root;
- symlink or hard-link escape;
- destination name collisions.

A validation failure leaves the destination unchanged and removes only the private staging directory.

## Git actions

Git detection walks parent directories from the selected URL without scanning unrelated trees. Git-only actions are omitted when no repository root exists. Remote parsing must support common HTTPS and SSH forms before constructing a browser URL; an unrecognized remote may be copied but must not be transformed into a guessed web URL.

## Concurrency and responsiveness

- Finder callbacks do constant or bounded work and read a precomputed menu snapshot.
- File coordination, hashing, archives, Git processes, and directory-store writes run outside Finder's main thread.
- Cancellation and per-item progress are host-app concerns.
- App Group writes use an atomic replace or a transactional store; readers must never observe partial JSON or plist data.

## Security invariants

- No user-provided shell or AppleScript execution.
- No silent overwrite or permanent-delete action.
- No accessibility permission dependency.
- No directory-content collection for smart folders.
- No signing credential, certificate, notarization profile, or built artifact in the repository.
- No copied third-party code, interface text, icon, template, or brand asset without a compatible documented license.

See [Privacy](PRIVACY.md) and [Permissions](PERMISSIONS.md) for the user-facing consequences of these invariants.
