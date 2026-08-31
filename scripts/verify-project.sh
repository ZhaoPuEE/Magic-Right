#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s [scheme]\n' "${0##*/}" >&2
}

fail() {
  printf 'verify-project: %s\n' "$1" >&2
  exit 1
}

if [[ $# -gt 1 ]]; then
  usage
  exit 64
fi

script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_root=$(cd "$script_dir/.." && pwd -P)
scheme=${1:-${SUPER_RIGHT_SCHEME:-SuperRight}}

[[ -n "$scheme" ]] || fail "scheme cannot be empty"
command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild is unavailable; install Xcode Command Line Tools"

cd "$repo_root"

verification_dir=$(mktemp -d "${TMPDIR:-/tmp}/super-right-verify.XXXXXX")
cleanup() {
  rm -rf "$verification_dir"
}
trap cleanup EXIT INT TERM

module_cache="$verification_dir/ModuleCache"
verification_user_home="$verification_dir/UserHome"
mkdir -p "$verification_user_home"
export CLANG_MODULE_CACHE_PATH="$module_cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$module_cache"
export CFFIXED_USER_HOME="$verification_user_home"

shopt -s nullglob
package_manifests=()
if [[ -f "$repo_root/Package.swift" ]]; then
  package_manifests+=("$repo_root/Package.swift")
fi
package_manifests+=("$repo_root"/Packages/*/Package.swift)
shopt -u nullglob

if [[ ${#package_manifests[@]} -gt 0 ]]; then
  command -v swift >/dev/null 2>&1 || fail "Package.swift exists but swift is unavailable"
  package_index=0
  for package_manifest in "${package_manifests[@]}"; do
    package_dir=$(dirname "$package_manifest")
    package_index=$((package_index + 1))
    printf '==> Running Swift package tests in %s\n' "$package_dir"
    swift test \
      --disable-sandbox \
      --package-path "$package_dir" \
      --scratch-path "$verification_dir/SwiftPM-$package_index" \
      --cache-path "$verification_dir/SwiftPMCache"
  done
else
  printf '==> No Package.swift found at the root or under Packages/*; skipping swift test\n'
fi

shopt -s nullglob
workspaces=("$repo_root"/*.xcworkspace)
projects=("$repo_root"/*.xcodeproj)
shopt -u nullglob

container_args=()
if [[ ${#workspaces[@]} -eq 1 ]]; then
  container_args=(-workspace "${workspaces[0]}")
elif [[ ${#workspaces[@]} -gt 1 ]]; then
  fail "multiple top-level .xcworkspace files found; keep one or run xcodebuild directly"
elif [[ ${#projects[@]} -eq 1 ]]; then
  container_args=(-project "${projects[0]}")
elif [[ ${#projects[@]} -gt 1 ]]; then
  fail "multiple top-level .xcodeproj files found; keep one or run xcodebuild directly"
else
  fail "no top-level .xcworkspace or .xcodeproj found"
fi

printf '==> Listing Xcode schemes\n'
derived_data="$verification_dir/DerivedData"
source_packages="$verification_dir/SourcePackages"
package_cache="$verification_dir/XcodePackageCache"
xcodebuild \
  "${container_args[@]}" \
  -scheme "$scheme" \
  -list \
  -derivedDataPath "$derived_data" \
  -clonedSourcePackagesDirPath "$source_packages" \
  -packageCachePath "$package_cache" \
  -disablePackageRepositoryCache

printf '==> Building scheme %s (Debug, unsigned)\n' "$scheme"
xcodebuild \
  -quiet \
  "${container_args[@]}" \
  -scheme "$scheme" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  -clonedSourcePackagesDirPath "$source_packages" \
  -packageCachePath "$package_cache" \
  -disablePackageRepositoryCache \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  REGISTER_WITH_LAUNCH_SERVICES=NO \
  build

printf '==> Verification completed successfully\n'
