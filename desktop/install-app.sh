#!/usr/bin/env bash

# Add Crate to app launchers that read XDG desktop entries.
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
apps_dir="$data_home/applications"
icons_dir="$data_home/icons/hicolor/scalable/apps"
entry="$apps_dir/crate.desktop"
icon="$icons_dir/crate.svg"
entry_source="$here/crate.desktop"
icon_source="$here/../assets/crate.svg"

# Only replace or remove files that still match the ones shipped with Crate.
# In particular, never follow a same-named symlink into another app's files.
is_ours() {
  [[ -f $2 && ! -L $2 ]] && cmp -s -- "$1" "$2"
}

check_destination() {
  if [[ -e $2 || -L $2 ]] && ! is_ours "$1" "$2"; then
    printf 'Refusing to overwrite %s: it does not match Crate\x27s file.\n' "$2" >&2
    exit 1
  fi
}

refresh() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -qtf "$data_home/icons/hicolor" >/dev/null 2>&1 || true
  fi
}

if [[ ${1:-} == "--remove" ]]; then
  if is_ours "$entry_source" "$entry"; then
    rm -- "$entry"
  fi
  if is_ours "$icon_source" "$icon"; then
    rm -- "$icon"
  fi
  refresh
  echo "Removed matching Crate launcher files; left any other files in place."
  exit 0
fi

check_destination "$entry_source" "$entry"
check_destination "$icon_source" "$icon"
mkdir -p -- "$apps_dir" "$icons_dir"
install -m 644 -- "$entry_source" "$entry"
install -m 644 -- "$icon_source" "$icon"
refresh
echo "Installed $entry and $icon"
