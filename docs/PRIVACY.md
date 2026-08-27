# Privacy

Super Right is designed as a local utility. Its V1 product contract does not require an account, analytics, advertising, telemetry, or a remote service.

## Data kept on the Mac

Depending on enabled features, Super Right stores:

- menu layout, feature toggles, and launch-at-login preference;
- enabled and discovered applications by bundle identifier, plus cached display metadata;
- imported template metadata and security-scoped bookmarks chosen by the user;
- pinned, frequent, and recent directory records, including paths and visit timestamps;
- exclusions, custom directory names, and the paused/active learning state;
- a compact record of Super Right file operations needed to show outcomes and support the promised undo behavior.

Folder paths can reveal private project names or account names and should be treated as personal data even though they stay local.

## Smart folder learning

When the user enables learning, Super Right records eligible directory visits reported by Finder and directories opened through Super Right. The user has chosen the inclusive mode: system, hidden, and temporary directories may be recorded unless explicitly excluded.

Learning does **not**:

- enumerate or index files inside a directory;
- read document contents to rank a folder;
- upload history;
- infer a category from filenames or contents.

The full history is retained until the user removes records or clears it. Missing paths are hidden from active menus but remain in history so that a temporarily disconnected volume does not lose its ranking. Controls must allow the user to pause learning, exclude paths, inspect and search records, delete individual entries, and clear all history.

## Application discovery

Super Right asks macOS Launch Services which applications can handle relevant files or folders, and reads application metadata such as bundle ID, display name, and icon. It does not launch a newly discovered app or place it in the Finder menu without the user's choice.

## Network behavior

Core features are local. Opening a Git remote page hands the URL to the user's chosen browser; network access then belongs to the browser and remote site. Super Right must not contact a Git host merely to construct or display that action.

If update checks or other network features are proposed later, they require separate documentation and a visible user control before release. They are not part of this V1 contract.

## User control and deletion

Settings must provide controls to:

- pause or resume directory learning;
- exclude directories;
- remove one directory record or clear all directory history;
- disable discovered applications and remove manually added applications;
- remove imported templates and destinations;
- clear recoverable operation history.

Removing the app does not automatically guarantee removal of its App Group container. Complete-uninstall instructions must identify the exact container only after the production App Group identifier is finalized; documentation must never recommend deleting a broad Library directory.

## Future contributions

Contributions must not add telemetry, remote storage, directory-content scanning, or a new data recipient without an explicit product decision, updated privacy documentation, and an appropriate consent flow.
