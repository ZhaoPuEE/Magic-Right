#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s /path/to/Magic Right.app\n' "${0##*/}" >&2
}

fail() {
  printf 'sign-ad-hoc-app: %s\n' "$1" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
  exit 64
fi

app_input=$1
[[ "$app_input" == *.app ]] || fail "input must have a .app suffix: $app_input"
[[ -d "$app_input" ]] || fail "application does not exist: $app_input"

app_parent=$(cd "$(dirname "$app_input")" && pwd -P)
app_name=$(basename "$app_input")
app_path="$app_parent/$app_name"
info_plist="$app_path/Contents/Info.plist"
extension_path="$app_path/Contents/PlugIns/SuperRightFinderExtension.appex"
extension_info_plist="$extension_path/Contents/Info.plist"
[[ -f "$info_plist" ]] || fail "application Info.plist is missing: $info_plist"
[[ -d "$extension_path" ]] || fail "Finder extension is missing: $extension_path"
[[ -f "$extension_info_plist" ]] || fail "Finder extension Info.plist is missing: $extension_info_plist"

host_bundle_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || true)
extension_bundle_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$extension_info_plist" 2>/dev/null || true)
[[ "$host_bundle_identifier" == "dev.magicright.app" ]] || fail "unexpected host bundle identifier: ${host_bundle_identifier:-missing}"
[[ "$extension_bundle_identifier" == "dev.magicright.app.finder-extension" ]] || fail "unexpected Finder extension bundle identifier: ${extension_bundle_identifier:-missing}"

script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_root=$(cd "$script_dir/.." && pwd -P)
host_entitlements="$repo_root/Signing/AdHoc/SuperRightApp.entitlements"
extension_entitlements="$repo_root/Signing/AdHoc/SuperRightFinderExtension.entitlements"

for entitlements in "$host_entitlements" "$extension_entitlements"; do
  [[ -f "$entitlements" ]] || fail "entitlements file is missing: $entitlements"
  if /usr/libexec/PlistBuddy \
    -c 'Print :com.apple.security.application-groups' \
    "$entitlements" >/dev/null 2>&1; then
    fail "ad-hoc entitlements must not declare an App Group: $entitlements"
  fi
done

codesign \
  --force \
  --sign - \
  --timestamp=none \
  --generate-entitlement-der \
  --entitlements "$extension_entitlements" \
  "$extension_path"

codesign \
  --force \
  --sign - \
  --timestamp=none \
  --generate-entitlement-der \
  --entitlements "$host_entitlements" \
  "$app_path"

for signed_bundle in "$app_path" "$extension_path"; do
  if codesign -d --entitlements :- "$signed_bundle" 2>/dev/null |
    grep -q '<key>com.apple.security.application-groups</key>'; then
    fail "signed ad-hoc bundle unexpectedly declares an App Group: $signed_bundle"
  fi
done

"$script_dir/verify-release-app.sh" "$app_path"
printf 'Ad-hoc signed without App Group access: %s\n' "$app_path"
