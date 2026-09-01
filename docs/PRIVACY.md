# Privacy

Magic Right is designed as a local utility. Its V1 product contract does not require an account, analytics, advertising, telemetry, or a remote service.

## Data kept on the Mac

Depending on enabled features, Magic Right stores:

- menu layout and feature toggles; launch-at-login state is managed by macOS;
- enabled and discovered applications by bundle identifier, plus cached display metadata;
- pinned, frequent, and recent directory records, including paths and visit timestamps;
- exclusions, custom directory names, and the paused/active learning state;
- a compact record of Magic Right file operations needed to show outcomes and support the promised undo behavior.

Folder paths can reveal private project names or account names and should be treated as personal data even though they stay local.

The host app is non-sandboxed. The Finder extension is sandboxed and, for the current non-App-Store GitHub/Developer ID architecture, declares temporary read/write exceptions for `/Users/`, `/Volumes/`, and `/private/tmp/` plus shared-preference access to `dev.magicright.shared`. It does not create or persist security-scoped bookmarks. Imported templates are also not part of the current implementation; their future storage and access contract must be documented before that feature ships.

## Smart folder learning

When the user enables learning, Magic Right records eligible directory visits reported by Finder and directories opened through Magic Right. Eligible paths are constrained to `/Users/`, `/Volumes/`, and `/private/tmp/` and remain subject to macOS privacy and filesystem permissions. Hidden paths within those roots may be recorded unless explicitly excluded.

Learning does **not**:

- enumerate or index files inside a directory;
- read document contents to rank a folder;
- upload history;
- infer a category from filenames or contents.

The full history is retained until the user removes records or clears it. Missing paths are hidden from active menus but remain in history so that a temporarily disconnected volume does not lose its ranking. Controls must allow the user to pause learning, exclude paths, inspect and search records, delete individual entries, and clear all history.

## Application discovery

Magic Right asks macOS Launch Services which applications can handle relevant files or folders, and reads application metadata such as bundle ID, display name, and icon. It does not launch a newly discovered app or place it in the Finder menu without the user's choice.

## Network behavior

Core features are local. Opening a Git remote page hands the URL to the user's chosen browser; network access then belongs to the browser and remote site. Magic Right must not contact a Git host merely to construct or display that action.

If update checks or other network features are proposed later, they require separate documentation and a visible user control before release. They are not part of this V1 contract.

## User control and deletion

Settings must provide controls to:

- pause or resume directory learning;
- exclude directories;
- remove one directory record or clear all directory history;
- disable discovered applications and remove manually added applications;
- remove imported templates and destinations;
- clear recoverable operation history.

Removing the app does not automatically remove shared data. Signed builds prefer the App Group container; local and community builds use the `dev.magicright.shared` defaults suite and `~/Library/Application Support/Magic Right/Shared`. Complete-uninstall instructions should identify the backend used by the installed build.

## Future contributions

Contributions must not add telemetry, remote storage, directory-content scanning, or a new data recipient without an explicit product decision, updated privacy documentation, and an appropriate consent flow.
