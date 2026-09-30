#!/usr/bin/env bash

# Add Crate to app launchers that read XDG desktop entries.
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
apps_dir="$data_home/applications"
icons_dir="$data_home/icons/hicolor/scalable/apps"
entry="$apps_dir/crate.desktop"
icon="$icons_dir/crate.svg"

refresh() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -qtf "$data_home/icons/hicolor" >/dev/null 2>&1 || true
  fi
}

if [[ ${1:-} == "--remove" ]]; then
  rm -f -- "$entry" "$icon"
  refresh
  echo "Removed the Crate app entry."
  exit 0
fi

mkdir -p -- "$apps_dir" "$icons_dir"
install -m 644 -- "$here/crate.desktop" "$entry"
install -m 644 -- "$here/../assets/crate.svg" "$icon"
refresh
echo "Installed $entry and $icon"
