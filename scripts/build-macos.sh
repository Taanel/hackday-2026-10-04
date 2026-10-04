#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
package_path="$repo_root/apps/macos"
app_path="${FRIDAY_APP_PATH:-$repo_root/dist/Friday.app}"

swift build --package-path "$package_path" --configuration release
binary_directory="$(swift build --package-path "$package_path" --configuration release --show-bin-path)"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_directory/Friday" "$app_path/Contents/MacOS/Friday"
cp "$package_path/packaging/Info.plist" "$app_path/Contents/Info.plist"
for resource_bundle in "$binary_directory"/*.bundle; do
    [ -d "$resource_bundle" ] || continue
    cp -R "$resource_bundle" "$app_path/Contents/Resources/"
done
if [ -d "$repo_root/services/local-runtime/src/friday_runtime" ]; then
    mkdir -p "$app_path/Contents/Resources/LocalRuntime"
    cp -R "$repo_root/services/local-runtime/src/friday_runtime" "$app_path/Contents/Resources/LocalRuntime/"
    # Python workers run with -B. Generated caches must not mutate signed resources.
    rm -rf "$app_path/Contents/Resources/LocalRuntime/friday_runtime/__pycache__"
fi
plutil -lint "$app_path/Contents/Info.plist"
# Finder metadata on copied resources can invalidate a macOS code signature.
xattr -cr "$app_path"
# A stable Apple signing identity preserves Keychain trust across updates.
# Keep local identity selection outside the repository; ad-hoc is the portable fallback.
signing_identity="${FRIDAY_SIGNING_IDENTITY:-}"
identity_file="$HOME/Library/Application Support/Friday/signing-identity"
if [ -z "$signing_identity" ] && [ -f "$identity_file" ]; then
    signing_identity="$(cat "$identity_file")"
fi
codesign --force --deep --sign "${signing_identity:--}" "$app_path"
codesign --verify --deep --strict "$app_path"
printf 'Built %s\n' "$app_path"
