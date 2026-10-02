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
  that track while preserving queued songs. Folder Play still replaces the
  queue; Queue and Next append or insert the entire folder.
- Confirm Queue/Next actions in the player footer without moving the user.
- Preserve queue scroll position across model replacements. Mouse removal sets
  selection to the deleted row; keyboard removal retains the nearby selection.
- Read title/artist tags for queued tracks asynchronously. Fall back to artist
  folders for Artist/Album/Track layouts, and filenames for untagged flat files.
- Consume completed/skipped queue entries, including the last track. Remove
  repeat controls to match the requirement to add tracks again to replay.
- Make volume a system-output control, with global mute and device changes
  reflected in Crate. mpv runs at unity gain.

## Recommended next work, in priority order

1. **Index tags for search.** Search still matches filenames and folder paths,
   not tags. A background cache keyed by path and modification time would make
   artist/title/album searches work even for badly named files, and avoid full
   filesystem scans per query. Refresh changed files and exclude deleted files.
   Queue tags are cached separately; changed tags currently need cache refresh.
2. **Cancel superseded searches.** The current worker finishes its scan before
   starting the latest pending query. Results stay consistent, but large libraries
   can feel slow. A persistent indexed worker would address both latency issues.
3. **Make album replacement explicit.** Folder Play still replaces the queue.
   Label it “Play folder” and explain replacement inline, or add an undo action.
   Avoid a confirmation dialog for routine track Queue/Next actions.
4. **Offer track/folder filters and batch selection** once library sizes justify
   them. Do not add filtering controls before observing real result clutter.
5. **Improve fuzzy matching after measuring examples.** The present subsequence
   matcher handles omitted letters but misses transpositions. Use exact title,
   artist and album matches before fuzzy fallbacks, and test actual failed queries.
6. **Add queue undo.** A brief Undo action for deletion/clear would reduce the
   cost of mistakes while preserving the consuming-queue model.

## Validation

Existing browse and playback tests, added queue logic cases, real FFmpeg tag
fixtures, accent-insensitive search tests, plugin validation and QML lint.
An isolated offscreen Quickshell harness also verifies final-track consumption
and both mouse-action and keyboard-removal paths at a scrolled queue position.
This checks handlers and layout behavior; physical key/mouse events and listening
on the live desktop still warrant a hands-on check.
