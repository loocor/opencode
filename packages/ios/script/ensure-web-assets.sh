#!/usr/bin/env bash
set -euo pipefail
# Repo: packages/ios. Symlink OpenCode/OpenCode/WebAssets -> ../../WebAssets
root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -f "$root/WebAssets/index.html" ]]; then
  echo "error: $root/WebAssets is missing (Vite output). The Xcode group links to this folder." >&2
  echo "From the repository root run:" >&2
  echo "  bun run --cwd packages/ios build" >&2
  exit 1
fi
