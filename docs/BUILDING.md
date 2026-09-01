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

Select the `SuperRight` scheme and the **My Mac** destination. For a formally signed build, the app and Finder extension must use compatible signing teams and the same `group.dev.magicright.app` App Group capability. Use a development team for which Xcode can create compatible provisioning for both targets. Do not assume a free Personal Team supports this capability; confirm the generated profiles in the current Xcode account. Public distribution requires Apple Developer Program membership and Developer ID credentials.

The host target sets `ENABLE_APP_SANDBOX = NO`. The Finder extension target must set `ENABLE_APP_SANDBOX = YES`; macOS `pkd` rejects an unsandboxed Finder plug-in with `plug-ins must be sandboxed`.

For the current open-source, non-App-Store GitHub/Developer ID distribution path, the extension entitlements include:

- `com.apple.security.temporary-exception.files.absolute-path.read-write` for `/Users/`, `/Volumes/`, and `/private/tmp/`;
- `com.apple.security.temporary-exception.shared-preference.read-write` for `dev.magicright.shared`.

Those exceptions are not Full Disk Access and remain subject to TCC and normal filesystem enforcement. They are not an App Store entitlement strategy. Security-scoped bookmark persistence is not implemented; an App Store build would need a separate access design and is outside the current release scope.

When valid signing makes the App Group container available, it is always preferred. Ad-hoc/source builds without a usable App Group fall back automatically to:

- `dev.magicright.shared` as the shared `UserDefaults` suite;
- `~/Library/Application Support/Magic Right/Shared` for cross-process locks and coordination files.

The fallback is for local development and preview testing. The Finder extension's shared-preference entitlement permits access to that suite, and its `/Users/` exception covers the coordination directory. The fallback must not be used as evidence that a formally signed release selected or correctly shared the App Group backend.

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

1. For the production-equivalent path, configure the same development team and App Group for both targets. For an ad-hoc/source preview, record that the fallback backend is being tested instead.
2. Run the host app once from Xcode.
3. Follow the onboarding link to enable the Magic Right Finder extension in System Settings.
4. Inspect the built extension's effective entitlements and confirm App Sandbox is enabled. For a non-App-Store build, also confirm the three absolute-path exceptions and `dev.magicright.shared` shared-preference exception are present.
5. Register the extension and confirm `pkd`/`pluginkit` does not report `plug-ins must be sandboxed`.
6. In Finder, right-click disposable test items separately under `/Users/`, `/Volumes/` when available, and `/private/tmp/`; confirm the Magic Right menu and expected read/write actions work.
7. Confirm a path outside the declared roots fails closed rather than being described as supported.
8. Test opening a path that includes spaces and non-ASCII characters in each enabled app.
9. Confirm the extension remains responsive while copy and move operations execute away from Finder's main thread.
10. Use **Jump To** once, allow Finder Automation when macOS asks, and confirm later jumps reuse the current Finder window without another prompt. Replacing an ad-hoc build can reset this local consent because its code identity is not stable.

Before calling the current build stable, also test app uninstall/reinstall discovery, multi-selection, denied permissions, name collisions, disconnected volumes, and smart-folder pause/clear behavior. Move undo, archives, and their security tests become release gates only when those planned features are implemented.

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
- requires the production host and Finder-extension bundle identifiers;
- rejects invalid or revoked signatures before and after staging;
- stages through a private temporary directory;
- refuses to overwrite an existing DMG;
- verifies the completed image;
- never reads or accepts signing credentials.

Run `scripts/verify-release-app.sh` directly when validating an app without
creating a DMG. It rejects the retired `dev.superright.app` development bundle
and requires `dev.magicright.app` with the matching
`dev.magicright.app.finder-extension` embedded extension. This check prevents a
locally cached development build from being mistaken for a release artifact;
it does not replace Developer ID signing, notarization, or clean-machine
Gatekeeper testing.

DMGs are ignored by Git and must not be committed.

An ad-hoc build may be attached to a GitHub **pre-release** only when the title
and release notes clearly identify the supported architecture and state that
the artifact is unsigned by Developer ID and not notarized.

After an unsigned Release build, sign preview artifacts with the repository's
minimal ad-hoc entitlements before packaging:

```bash
./scripts/sign-ad-hoc-app.sh "/path/to/Magic Right.app"
./scripts/create-dmg.sh "/path/to/Magic Right.app" "/path/to/output"
```

The ad-hoc signing script signs the embedded Finder extension before the host,
rejects any ad-hoc entitlement file that declares an App Group, and runs the
release bundle verifier. Formally signed builds use the target entitlements
instead; they must not use the ad-hoc entitlement files.

## Signed stable release boundary

A signed, notarized stable GitHub Release requires more than a successful local DMG:

1. Run unit tests and `./scripts/verify-project.sh`.
2. Complete the real-app and Finder extension test matrix on supported macOS versions.
3. Archive and sign the app and embedded extension with the appropriate Developer ID identities, matching App Group entitlements, a non-sandboxed host, and a sandboxed Finder extension.
4. Verify the signatures, designated requirements, extension sandbox, exact temporary exceptions, and App Group entitlements; then confirm both processes selected the App Group backend rather than the development fallback.
5. Create and sign the DMG.
6. Submit the distributed artifact to Apple notarization and wait for acceptance.
7. Staple the notarization ticket and verify it under Gatekeeper.
8. Tag the exact Git commit with a semantic version, push `main` and the tag, then attach the verified DMG and checksums to a GitHub Release.

Signing and notarization should be a separate release step. Credentials belong in the developer keychain or protected CI secrets, never command-line arguments recorded in the repository. `scripts/create-dmg.sh` intentionally performs packaging only.

No README, tag, or release note should claim notarization or installed-user validation without evidence from the exact published artifact.
