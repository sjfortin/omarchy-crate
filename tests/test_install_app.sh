#!/usr/bin/env bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
installer="$root/desktop/install-app.sh"
test_home=$(mktemp -d)
trap 'rm -rf -- "$test_home"' EXIT
export XDG_DATA_HOME="$test_home/data"
entry="$XDG_DATA_HOME/applications/crate.desktop"
icon="$XDG_DATA_HOME/icons/hicolor/scalable/apps/crate.svg"

mkdir -p -- "$(dirname -- "$entry")" "$(dirname -- "$icon")"
printf 'Another application\n' > "$entry"
if "$installer" > /dev/null 2>&1; then
  echo 'Installer overwrote a foreign launcher' >&2
  exit 1
fi
[[ $(cat -- "$entry") == 'Another application' && ! -e $icon ]]

rm -- "$entry"
printf 'Another icon\n' > "$icon"
if "$installer" > /dev/null 2>&1; then
  echo 'Installer overwrote a foreign icon' >&2
  exit 1
fi
[[ $(cat -- "$icon") == 'Another icon' && ! -e $entry ]]

"$installer" --remove > /dev/null
[[ $(cat -- "$icon") == 'Another icon' ]]
rm -- "$icon"

"$installer" > /dev/null
cmp -- "$root/desktop/crate.desktop" "$entry"
cmp -- "$root/assets/crate.svg" "$icon"

printf 'User edit\n' > "$icon"
"$installer" --remove > /dev/null
[[ ! -e $entry && $(cat -- "$icon") == 'User edit' ]]
rm -- "$icon"

ln -s -- "$root/desktop/crate.desktop" "$entry"
if "$installer" > /dev/null 2>&1; then
  echo 'Installer accepted a same-named symlink' >&2
  exit 1
fi
"$installer" --remove > /dev/null
[[ -L $entry ]]

echo 'Launcher ownership checks passed.'
