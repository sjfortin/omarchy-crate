# Crate

A fast, minimal local music player for Omarchy. Your filesystem is your music
library: open Crate, dig through your folders, build a queue, and get back to
work. No import or account is needed.

## Dig → Queue → Play

- **Dig:** Browse `~/Music` by folder or press `/` to search names and paths
  across your collection. Search matches tracks and folders, including artist
  and album names when they appear in the path. Fuzzy matches help with partial
  names. Change the root in the bar widget's **Music folder** setting.
- **Queue:** Add a track or a whole folder (including its subfolders), play it
  next, reorder or remove items, clear the queue, or shuffle what comes next.
- **Play:** Use previous, play/pause, next, seek, volume, and repeat off/all/one.
  Crate shows track title, artist, and album when mpv provides that metadata;
  filenames work when tags are missing.

Click a track to play its containing folder in order, starting at that track.
On a folder row, click **PLAY** to play the whole folder; click its name to
open it and keep digging. Playing a folder replaces the current queue. Use
**+ QUEUE** or **NEXT** when you want to keep what is already queued.

The queue, current track, playback position, and last browsed directory are
saved under `~/.local/state/omarchy/crate/state.json` (or
`$XDG_STATE_HOME/omarchy/crate/state.json`). Press play after restarting the
shell to resume the saved track and position. Closing the browser leaves music
playing.

## Requirements and local setup

- Omarchy with the Quickshell plugin system
- `mpv` for playback
- Python 3 for folder browsing and search

Place this folder at `~/.config/omarchy/plugins/sjfortin.crate`. With
`omarchy-shell` running, use:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/sjfortin.crate
omarchy plugin enable sjfortin.crate
omarchy-shell crate open
```

Click **CRATE** in the bar to open it; middle-click to play or pause, and scroll
to change volume. Once published as a Git repository, it can be installed with
`omarchy plugin add <git-url> --enable`.

## Keyboard

| Key | Action |
| --- | --- |
| `1` / `2` | Dig / Queue |
| `↑` / `↓` or `j` / `k` | Move selection |
| `Enter` | Open folder or play the selected track's folder |
| `Backspace` / `Esc` | Parent folder / clear search / close |
| `/` | Search the collection |
| `q` / `Shift+q` | Queue selection / play it next |
| `Space` | Play or pause |
| `Delete` | Remove selected queue item |
| `?` | Shortcut help |

Use **QUEUE THIS FOLDER** to add the current folder and its subfolders. Search
runs only when requested; Crate does not build a separate music database.
Search currently uses filenames and folder paths, so metadata that appears
only inside file tags is not indexed. Large collections may take longer on the
first search.

Crate reads local music and makes no network requests. It plays MP3, FLAC,
Ogg, Opus, AAC/M4A, WAV, and other formats supported by mpv. It does not
change your music files.

Crate is intentionally queue first. Accounts, streaming, recommendations,
ratings, and large library-management screens are outside its scope. A future
**Save Queue → Mixtape** feature may add simple persistent collections after
the browsing and listening flow is solid.

To turn it off, run `omarchy plugin disable sjfortin.crate`. For a Git-installed
plugin, `omarchy plugin remove sjfortin.crate` removes plugin files. Saved queue
data remains in the state directory for you to keep or delete.

## Contribute

`Service.qml` owns playback, queue, search, and saved state. `Browser.qml` is
the Dig and Queue window; `BarWidget.qml` provides bar controls.
`scripts/browse.py` reads folders, searches paths, and collects folder tracks
without leaving the configured music root.

Run these checks after changes:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/sjfortin.crate
python3 -m unittest discover -s tests -v
```

Please also test in a running Omarchy shell. This is an early version awaiting
hands-on testing before store submission.
