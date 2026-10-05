# Search and queue experience audit

Reviewed the search field, debounce and subprocess lifecycle, matching/ranking,
result presentation, mouse and keyboard actions, folder playback, queue updates,
and player controls in version 0.1.12.

## Changes made

- Keep digits and punctuation available while typing; `1`, `2`, and `?` no
  longer hijack the search field. Down selects the first result. Tab returns
  focus to result navigation; Q and Shift+Q then queue or play next.
- Hide results belonging to an older query during debounce. Clear obsolete
  errors and truncation flags, and keep loading state while searches are pending.
- Show track/folder names on the first line and library paths on a second line.
  Artist and album context stays visible without crowding out the title.
- Match accented names without requiring accents. Preserve the existing folder
  ranking and fuzzy partial-name matching.
- Display result counts, no-match guidance, and a prompt to refine truncated
  searches. Hide “Queue this folder” during search because it referred to the
  underlying browsed folder, not the search results.
- Give every track an explicit Play action. Track playback inserts and plays
  that track while preserving queued songs. Folder Play replaces automatic
  album continuation while keeping manually queued requests; Queue and Next
  append or insert the entire folder.
- Confirm Queue/Next actions in the player footer without moving the user.
- Preserve queue scroll position across model replacements. Mouse removal sets
  selection to the deleted row; keyboard removal retains the nearby selection.
- Read title/artist tags for queued tracks asynchronously. Fall back to artist
  folders for Artist/Album/Track layouts, and filenames for untagged flat files.
- Consume completed/skipped queue entries, including the last track. Remove
  repeat controls to match the requirement to add tracks again to replay.
- Make volume a system-output control, with global mute and device changes
  reflected in Crate. mpv runs at unity gain.

## Follow-up progress

1. **Tag search and indexing — done.** The first search starts a background
   SQLite index of filenames, folders, title, artist, and album tags. Searches
   use the index after its first scan. Refresh checks file modification time
   and size, updates changed tags, and removes deleted entries. The queue tag
   reader reuses valid indexed tags.
2. **Cancel superseded searches — done.** A newer query stops the old worker;
   only results for the latest query are displayed.
3. **Explain album replacement — done.** The folder menu labels playback as
   replacing automatic album continuation. Explicit queue requests remain in
   place. Undo covers queue edits.
4. **Track/folder filters and batch selection — done.** The library has over
   14,000 files, so mixed search results warrant All/Tracks/Folders filters.
   Dig also supports checkbox, Ctrl-click, Shift-click, and Ctrl+A selection.
5. **Fuzzy matching — improved.** Exact title, artist, and album matches rank
   before fuzzy fallbacks; one adjacent letter swap now matches. Examples from
   daily use would help refine ranking further.
6. **Queue undo — done.** Undo reverses additions, removals, reordering,
   shuffling, and clearing during the current session.

## Validation

Browse and playback tests cover real FFmpeg tags, index refresh, deleted files,
filters, accent-insensitive search, and transposition matching. Queue tests
cover undo and folder request ordering. Plugin validation and an isolated
offscreen Quickshell harness check the UI, search worker, and saved state.
Physical key/mouse events and listening on the live desktop still warrant a
hands-on check.
