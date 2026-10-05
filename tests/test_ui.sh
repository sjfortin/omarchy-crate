#!/usr/bin/env bash
# Isolated handler/layout check; never uses the user's saved playback state.
set -euo pipefail
plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf -- "$fixture_dir"' EXIT
ln -s "$plugin_dir" "$fixture_dir/Crate"
ln -s /usr/share/omarchy/shell/Commons "$fixture_dir/Commons"
cp "$plugin_dir/tests/ui.qml" "$fixture_dir/shell.qml"
mkdir -p "$fixture_dir/music/one" "$fixture_dir/music/two" "$fixture_dir/music/three"
touch "$fixture_dir/music/one/one.mp3" "$fixture_dir/music/two/two.mp3" "$fixture_dir/music/three/three.mp3"
CRATE_TEST_MUSIC="$fixture_dir/music" QT_QPA_PLATFORM=offscreen XDG_STATE_HOME="$fixture_dir/state" timeout 15s quickshell -p "$fixture_dir" --no-color > "$fixture_dir/output" 2>&1
cat "$fixture_dir/output"
rg -q 'PASS final track consumption' "$fixture_dir/output"
rg -q 'PASS mouse action and keyboard removal preserve viewport and selection' "$fixture_dir/output"
rg -q 'PASS folder pipeline, latest search, and persistence' "$fixture_dir/output"
if rg -q 'TypeError|ReferenceError|Error:|TEST FAILED' "$fixture_dir/output"; then exit 1; fi

python3 - "$fixture_dir/state/omarchy/crate/state.json" <<'PYTEST'
import json
import sys
from pathlib import Path
state = json.loads(Path(sys.argv[1]).read_text())
assert state["version"] == 3
assert len(state["queue"]) == 3
assert state["mixtapes"][0]["name"] == "Test tape"
assert len(state["mixtapes"][0]["paths"]) == 3
assert state["pinnedFolders"] == [state["userMusicRoot"]]
print("PASS persisted mixtape, folder preference, and restored queue")
PYTEST
