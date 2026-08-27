#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s /path/to/Application.app /path/to/output-directory\n' "${0##*/}" >&2
}

fail() {
  printf 'create-dmg: %s\n' "$1" >&2
  exit 1
}

if [[ $# -ne 2 ]]; then
  usage
  exit 64
fi

app_input=$1
output_input=$2

[[ "$app_input" == *.app ]] || fail "input must have a .app suffix: $app_input"
[[ -d "$app_input" ]] || fail "application does not exist or is not a directory: $app_input"
[[ -f "$app_input/Contents/Info.plist" ]] || fail "application is missing Contents/Info.plist: $app_input"

for required_command in ditto hdiutil ln mktemp mv; do
  command -v "$required_command" >/dev/null 2>&1 || fail "required command is unavailable: $required_command"
done

app_parent=$(cd "$(dirname "$app_input")" && pwd -P)
app_name=$(basename "$app_input")
app_path="$app_parent/$app_name"
product_name=${app_name%.app}

[[ -n "$product_name" ]] || fail "application name cannot be empty"

if [[ -e "$output_input" && ! -d "$output_input" ]]; then
  fail "output path exists and is not a directory: $output_input"
fi

mkdir -p "$output_input"
output_dir=$(cd "$output_input" && pwd -P)
output_path="$output_dir/$product_name.dmg"

[[ ! -e "$output_path" ]] || fail "refusing to overwrite existing output: $output_path"

package_type=$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$app_path/Contents/Info.plist" 2>/dev/null || true)
[[ "$package_type" == "APPL" ]] || fail "Info.plist does not identify an application bundle (CFBundlePackageType=APPL)"

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/super-right-dmg.XXXXXX")
stage_dir="$work_dir/stage"
temporary_dmg="$work_dir/$product_name.dmg"

cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT INT TERM

mkdir "$stage_dir"
ditto "$app_path" "$stage_dir/$app_name"
ln -s /Applications "$stage_dir/Applications"

printf 'Creating %s\n' "$output_path"
hdiutil create \
  -quiet \
  -volname "$product_name" \
  -srcfolder "$stage_dir" \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$temporary_dmg"

hdiutil verify -quiet "$temporary_dmg"

if [[ -e "$output_path" ]]; then
  fail "output appeared during packaging; refusing to overwrite: $output_path"
fi

mv -n "$temporary_dmg" "$output_path"

if [[ -e "$temporary_dmg" || ! -f "$output_path" ]]; then
  fail "could not install DMG without overwriting an existing file"
fi

printf 'Created %s\n' "$output_path"
