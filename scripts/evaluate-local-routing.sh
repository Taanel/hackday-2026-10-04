#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
swift build --package-path "$repo_root/apps/macos" --configuration debug
binary_directory="$(swift build --package-path "$repo_root/apps/macos" --configuration debug --show-bin-path)"
probe_directory="$(mktemp -d "${TMPDIR:-/tmp}/friday-routing.XXXXXX")"
trap 'rm -rf "$probe_directory"' EXIT
swiftc -parse-as-library -I "$binary_directory/Modules" "$repo_root/scripts/evaluate-local-routing.swift" \
    "$binary_directory"/FridayAdapters.build/*.o "$binary_directory"/FridayCore.build/*.o \
    -o "$probe_directory/evaluate"
"$probe_directory/evaluate" "$repo_root" "$repo_root/services/local-runtime/evals/friday-routing.jsonl"
