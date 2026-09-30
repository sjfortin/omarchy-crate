# Omarchy plugin marketplace draft

Crate is awaiting hands-on testing. Use this copy once the repository is public
and the plugin is ready to submit.

## Listing

- **Name:** Crate
- **Repository URL:** Add the public GitHub URL before submitting.
- **Category:** Widgets
- **Tags:** Media, Bar, Quickshell
- **Short description:** A fast, minimal local music player for Omarchy. Dig through folders, search, and build a listening queue.

## Maintainer notes

Crate treats the filesystem as the music library. Users can browse their own
music folders, search filenames and paths, play a folder or a track's album in
order, queue a track or directory, and
control playback from a small themed bar widget and browser. No import,
account, or network service is required. It needs mpv and Python 3. The queue,
current track, playback position, and recent directory are stored locally under
`~/.local/state/omarchy/crate` by default. Crate does not modify music files.
The README covers setup, controls, dependencies, removal, and contributor
checks.

## Before submitting

- Test browsing, search, folder queuing, playback, and resume in a running
  Omarchy shell, including large folders, missing files, and light/dark themes.
- Publish a public GitHub repository with `manifest.json`, README, and LICENSE
  at the root; add its URL above.
- Submit via the [marketplace form](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml).

Marketplace verification applies to a specific commit after checks and
maintainer review. Crate does not currently claim verified status.
