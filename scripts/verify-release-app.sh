#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s /path/to/Magic Right.app\n' "${0##*/}" >&2
}

fail() {
  printf 'verify-release-app: %s\n' "$1" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
  exit 64
fi

app_input=$1

[[ "$app_input" == *.app ]] || fail "input must have a .app suffix: $app_input"
[[ -d "$app_input" ]] || fail "application does not exist or is not a directory: $app_input"

app_parent=$(cd "$(dirname "$app_input")" && pwd -P)
app_name=$(basename "$app_input")
app_path="$app_parent/$app_name"
info_plist="$app_path/Contents/Info.plist"
extension_path="$app_path/Contents/PlugIns/SuperRightFinderExtension.appex"
extension_info_plist="$extension_path/Contents/Info.plist"

[[ -f "$info_plist" ]] || fail "application is missing Contents/Info.plist: $app_path"
[[ -d "$extension_path" ]] || fail "application is missing the Finder extension: $extension_path"
[[ -f "$extension_info_plist" ]] || fail "Finder extension is missing Contents/Info.plist: $extension_path"

for required_command in codesign /usr/libexec/PlistBuddy; do
  [[ -x "$(command -v "$required_command" 2>/dev/null || true)" ]] || fail "required command is unavailable: $required_command"
done

package_type=$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$info_plist" 2>/dev/null || true)
host_bundle_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || true)
extension_bundle_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$extension_info_plist" 2>/dev/null || true)

[[ "$package_type" == "APPL" ]] || fail "Info.plist does not identify an application bundle (CFBundlePackageType=APPL)"
[[ "$host_bundle_identifier" == "dev.magicright.app" ]] || fail "unexpected host bundle identifier: ${host_bundle_identifier:-missing}"
[[ "$extension_bundle_identifier" == "dev.magicright.app.finder-extension" ]] || fail "unexpected Finder extension bundle identifier: ${extension_bundle_identifier:-missing}"

if ! codesign --verify --deep --strict --verbose=2 "$app_path" >/dev/null 2>&1; then
  fail "application or an embedded component has an invalid or revoked code signature"
fi

printf 'Verified release app: %s\n' "$app_path"
printf '  Host bundle identifier: %s\n' "$host_bundle_identifier"
printf '  Finder extension bundle identifier: %s\n' "$extension_bundle_identifier"
