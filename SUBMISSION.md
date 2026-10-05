# Omarchy plugin marketplace submission

Submit this issue to `omacom/omarchy-plugin-marketplace` after the owner reviews
and confirms the checklist. The marketplace validates the repository and its
exact commit before a maintainer decides whether to list it.

## Issue title

`[Plugin]: Crate`

## Issue body

### Repository URL

https://github.com/sjfortin/omarchy-crate

### Category

Widgets

### Tags

media, bar, quickshell

### Suggest a missing tag

_No response_

### Maintainer notes

Crate is a fast local music player for Omarchy. It uses the filesystem as the
library and provides folder browsing, local title/artist/album tag search, album
playback, a persistent queue, keyboard navigation, and bar playback controls.
It requires mpv and Python 3; FFmpeg provides tag search. It reads local music
and writes playback state and a search index
under the user's XDG state directory; the optional Apps launcher is installed
only when the user runs its script. Crate can pause local NTS Radio when
music starts; the reciprocal NTS Radio update is in PR #3. Casting is unaffected.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
