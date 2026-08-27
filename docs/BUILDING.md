# Building and releasing

## Requirements

- macOS 15 or later for running Magic Right
- A current Xcode toolchain with Swift 6 and the macOS 15 SDK or later
- Xcode Command Line Tools (`xcode-select -p` should succeed)
- Git

The repository does not contain certificates, private keys, notarization credentials, provisioning profiles, built apps, or DMGs.

The shipped product name is **Magic Right**. The Xcode project, scheme, Swift module, and several source types intentionally retain the internal `SuperRight` technical name for source compatibility during the rename.

## Open the project

From the repository root:

```sh
open SuperRight.xcodeproj
```

Select the `SuperRight` scheme and the **My Mac** destination. The app and Finder extension must use compatible signing teams and the same App Group capability. Use a development team for which Xcode can create App Group provisioning for both targets. Do not assume a free Personal Team supports this capability; confirm the generated profiles in the current Xcode account. Public distribution requires Apple Developer Program membership and Developer ID credentials.

Do not commit changes under `xcuserdata` or any locally generated signing material.

## Verify from the command line

Run:

```sh
./scripts/verify-project.sh
```

The script performs these checks:

1. `swift test` for a package at the repository root and each direct child of `Packages`;
2. `xcodebuild -list` for the top-level workspace or project;
3. an unsigned Debug build of the `SuperRight` scheme for macOS, using a temporary Derived Data directory.

Override the scheme with either form:

```sh
./scripts/verify-project.sh AnotherScheme
SUPER_RIGHT_SCHEME=AnotherScheme ./scripts/verify-project.sh
```

The positional argument takes precedence. The unsigned build verifies compilation; it is not a substitute for launching a properly signed build and testing the Finder extension.

## Local Finder extension test

1. Configure the same development team and App Group for both targets.
2. Run the host app once from Xcode.
3. Follow the onboarding link to enable the Magic Right Finder extension in System Settings.
4. In Finder, right-click a disposable test folder and confirm the Magic Right menu appears.
5. Test opening a path that includes spaces and non-ASCII characters in each enabled app.
6. Confirm the extension remains responsive during hashing, archive, copy, and move operations performed by the host app.

Before calling a build stable, also test app uninstall/reinstall discovery, multi-selection, denied permissions, name collisions, move undo, malicious archive paths, disconnected volumes, and smart-folder pause/clear behavior.

Office templates must be opened in the installed Microsoft Word, Excel, and PowerPoint applications. A file existing with the correct suffix is not sufficient validation.

## Build a Release app

A local Release build can be produced in Xcode with **Product > Archive**, or from the command line. For an unsigned compile-only artifact:

```sh
xcodebuild \
  -project SuperRight.xcodeproj \
  -scheme SuperRight \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

An unsigned app is suitable only for build verification. Use Xcode's archive/export workflow or an explicit Developer ID pipeline for an app intended for other Macs.

## Create a local DMG

Given an already built `.app`:

```sh
./scripts/create-dmg.sh "/absolute/path/to/Magic Right.app" ./dist
```

The output is `dist/Magic Right.dmg`. The image contains the app and an `Applications` symlink. The script:

- validates the `.app` suffix and bundle structure;
- stages through a private temporary directory;
- refuses to overwrite an existing DMG;
- verifies the completed image;
- never reads or accepts signing credentials.

DMGs are ignored by Git and must not be committed.

## Public release boundary

A public GitHub Release requires more than a successful local DMG:

1. Run unit tests and `./scripts/verify-project.sh`.
2. Complete the real-app and Finder extension test matrix on supported macOS versions.
3. Archive and sign the app and embedded extension with the appropriate Developer ID identities and entitlements.
4. Verify the signatures and designated requirements.
5. Create and sign the DMG.
6. Submit the distributed artifact to Apple notarization and wait for acceptance.
7. Staple the notarization ticket and verify it under Gatekeeper.
8. Tag the exact Git commit with a semantic version, push `main` and the tag, then attach the verified DMG and checksums to a GitHub Release.

Signing and notarization should be a separate release step. Credentials belong in the developer keychain or protected CI secrets, never command-line arguments recorded in the repository. `scripts/create-dmg.sh` intentionally performs packaging only.

No README, tag, or release note should claim notarization or installed-user validation without evidence from the exact published artifact.
