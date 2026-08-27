# Magic Right development rules

- Keep all source, tests, packaging scripts, and documentation in this repository.
- The default branch is `main`; make small, reviewable commits and never commit credentials, signing certificates, notarization profiles, build products, or DMGs.
- The product is a native macOS app built with Swift 6, SwiftUI, AppKit, and a Finder Sync extension. The deployment target is macOS 15.
- Keep Finder extension work lightweight. Long-running or destructive file operations belong in the host app.
- Identify external apps by bundle identifier, and resolve their current URL through Launch Services at execution time. Do not persist absolute `.app` paths as identity.
- Do not execute user-provided shell strings. Structured arguments such as path, paths, and Git root must be passed as process arguments or through `NSWorkspace`.
- Never silently overwrite user files. File-moving features require collision-safe names and a recoverable operation log.
- Directory-learning data stays local and must never inspect directory contents or leave the device.
- Add tests for shared Core behavior and run both `swift test` and the Xcode build checks before release packaging.

