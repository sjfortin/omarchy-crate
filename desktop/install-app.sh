#!/usr/bin/env bash

# Add Crate to app launchers that read XDG desktop entries.
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
apps_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
entry="$apps_dir/crate.desktop"

if [[ ${1:-} == "--remove" ]]; then
  rm -f -- "$entry"
  echo "Removed the Crate app entry."
  exit 0
fi

mkdir -p -- "$apps_dir"
install -m 644 -- "$here/crate.desktop" "$entry"
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
fi
echo "Installed $entry"
