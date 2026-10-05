import tempfile
import json
import shutil
import subprocess
import unittest
import io
from contextlib import redirect_stdout
from unittest.mock import patch
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from browse import list_folder, search_music, tracks_in_folder, queue_metadata, collect_selection
from search_index import index_music


class BrowseTests(unittest.TestCase):
    def test_folders_first_and_supported_audio_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Zulu.mp3").touch()
            (root / "alpha.FLAC").touch()
            (root / "cover.jpg").touch()
            (root / ".hidden.mp3").touch()
            (root / "Albums").mkdir()
            result = list_folder(directory, directory)
            self.assertEqual(
                [(entry["name"], entry["kind"]) for entry in result["entries"]],
                [("Albums", "folder"), ("alpha.FLAC", "track"), ("Zulu.mp3", "track")],
            )

    def test_cannot_browse_or_follow_symlinks_outside_root(self):
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as outside:
            root = Path(directory)
            (root / "outside").symlink_to(outside, target_is_directory=True)
            (Path(outside) / "private.mp3").touch()
            self.assertEqual(list_folder(directory, outside)["error"], "Folder is outside the music library")
            self.assertEqual(list_folder(directory, directory)["entries"], [])

    def test_search_finds_folder_paths_and_fuzzy_names(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            album = root / "Boards of Canada" / "Music Has the Right to Children"
            album.mkdir(parents=True)
            (album / "Roygbiv.mp3").touch()
            (root / "unrelated.wav").touch()
            paths = [entry["relative"] for entry in search_music(directory, "bord canada")["entries"]]
            self.assertIn("Boards of Canada/Music Has the Right to Children/Roygbiv.mp3", paths)
            self.assertIn("Boards of Canada", paths)
            self.assertEqual(search_music(directory, "roygbiv")["entries"][0]["name"], "Roygbiv.mp3")

    def test_artist_search_puts_openable_directory_first(self):
        with tempfile.TemporaryDirectory() as directory:
            artist = Path(directory) / "Radiohead"
            album = artist / "In Rainbows"
            album.mkdir(parents=True)
            (album / "01 15 Step.mp3").touch()
            result = search_music(directory, "radiohead")
            self.assertEqual(result["entries"][0]["kind"], "folder")
            self.assertEqual(result["entries"][0]["path"], str(artist))
            self.assertEqual([entry["name"] for entry in list_folder(directory, str(artist))["entries"]],
                             ["In Rainbows"])

    def test_folder_queue_is_recursive_and_stays_in_root(self):
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as outside:
            root = Path(directory)
            album = root / "Artist" / "Album"
            album.mkdir(parents=True)
            (album / "01.mp3").touch()
            (root / "Artist" / "02.flac").touch()
            (album / "cover.jpg").touch()
            (root / "Artist" / "outside").symlink_to(outside, target_is_directory=True)
            (Path(outside) / "private.mp3").touch()
            result = tracks_in_folder(directory, str(root / "Artist"))
            self.assertEqual({entry["name"] for entry in result["entries"]}, {"01.mp3", "02.flac"})
            self.assertEqual(tracks_in_folder(directory, outside)["error"], "Folder is outside the music library")

    def test_accent_insensitive_search(self):
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "Björk - Jóga.flac").touch()
            result = search_music(directory, "bjork joga")
            self.assertEqual(result["entries"][0]["name"], "Björk - Jóga.flac")

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "FFmpeg required")
    def test_queue_metadata_reads_tags_and_rejects_outside_library(self):
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as outside:
            track = Path(directory) / "song.wav"
            subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "anullsrc",
                            "-t", "0.05", "-metadata", "title=Tagged title",
                            "-metadata", "artist=Tagged artist", str(track)], check=True)
            external = Path(outside) / "other.wav"
            shutil.copyfile(track, external)
            result = queue_metadata(directory, json.dumps([str(track), str(external)]))
            self.assertEqual(result["metadata"][str(track)]["title"], "Tagged title")
            self.assertEqual(result["metadata"][str(track)]["artist"], "Tagged artist")
            self.assertEqual(result["metadata"][str(external)], {})

    def test_search_reports_result_limit_separately_from_scan_limit(self):
        with tempfile.TemporaryDirectory() as directory:
            for name in ("one.mp3", "two.mp3", "three.mp3"):
                (Path(directory) / name).touch()
            with patch("browse.MAX_RESULTS", 1):
                result = search_music(directory, "mp3")
                self.assertTrue(result["truncated"])
                self.assertFalse(result["scanLimited"])
            with patch("browse.MAX_SEARCH_FILES", 1):
                result = search_music(directory, "absent")
                self.assertTrue(result["scanLimited"])
                self.assertFalse(result["truncated"])

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "FFmpeg required")
    def test_index_finds_tags_refreshes_changed_files_and_removes_deleted_files(self):
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as state:
            root = Path(directory)
            cache = str(Path(state) / "search.sqlite")
            track = root / "untitled.wav"

            def make_track(title):
                subprocess.run([
                    "ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "anullsrc",
                    "-t", "0.05", "-metadata", f"title={title}",
                    "-metadata", "artist=Rare Artist", str(track),
                ], check=True)

            make_track("Secret Nocturne")
            self.assertEqual(search_music(directory, "nocturne", cache_path=cache)["entries"], [])
            self.assertEqual(index_music(directory, cache)["error"], "")
            with patch("browse.os.walk", side_effect=AssertionError("indexed search walked the filesystem")):
                result = search_music(directory, "nocturne", cache_path=cache)
            self.assertTrue(result["indexed"])
            self.assertEqual(result["entries"][0]["title"], "Secret Nocturne")
            self.assertEqual(search_music(directory, "rare artist", cache_path=cache)["entries"][0]["path"], str(track))
            self.assertEqual(search_music(directory, "rare artist", kind="folder", cache_path=cache)["entries"], [])
            self.assertEqual(search_music(directory, "rare artist", kind="track", cache_path=cache)["entries"][0]["path"], str(track))
            self.assertEqual(queue_metadata(directory, json.dumps([str(track)]), cache_path=cache)["metadata"][str(track)]["title"], "Secret Nocturne")
            make_track("Hidden Aurora")
            self.assertEqual(index_music(directory, cache)["error"], "")
            self.assertEqual(search_music(directory, "nocturne", cache_path=cache)["entries"], [])
            self.assertEqual(search_music(directory, "aurora", cache_path=cache)["entries"][0]["path"], str(track))
            track.unlink()
            self.assertEqual(search_music(directory, "aurora", cache_path=cache)["entries"], [])
            self.assertEqual(index_music(directory, cache)["error"], "")
            self.assertEqual(search_music(directory, "aurora", cache_path=cache)["entries"], [])

    def test_adjacent_letter_swap_matches_but_ranks_below_exact(self):
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "Brainstorm.mp3").touch()
            (Path(directory) / "Brainstrom.mp3").touch()
            result = search_music(directory, "brainstrom")
            self.assertEqual(result["entries"][0]["name"], "Brainstrom.mp3")
            self.assertIn("Brainstorm.mp3", [entry["name"] for entry in result["entries"]])

    def test_index_does_not_follow_folder_replaced_with_external_symlink(self):
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as outside, tempfile.TemporaryDirectory() as state:
            root = Path(directory)
            album = root / "Album"
            album.mkdir()
            (album / "Secret.mp3").touch()
            cache = str(Path(state) / "search.sqlite")
            index_music(directory, cache)
            album.rename(root / "Moved")
            (Path(outside) / "Secret.mp3").touch()
            album.symlink_to(outside, target_is_directory=True)
            self.assertEqual(search_music(directory, "secret", cache_path=cache)["entries"], [])

    def test_index_rebuilds_when_music_root_changes(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second, tempfile.TemporaryDirectory() as state:
            (Path(first) / "First.mp3").touch()
            (Path(second) / "Second.mp3").touch()
            cache = str(Path(state) / "search.sqlite")
            index_music(first, cache)
            self.assertTrue(search_music(first, "first", cache_path=cache)["indexed"])
            index_music(second, cache)
            self.assertTrue(search_music(second, "second", cache_path=cache)["indexed"])
            self.assertEqual(search_music(second, "first", cache_path=cache)["entries"], [])
            self.assertFalse(search_music(first, "first", cache_path=cache)["indexed"])

    def test_collection_preserves_selection_order_and_reports_partial_results(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root / "Album"
            folder.mkdir()
            (folder / "01.mp3").touch()
            (folder / "02.mp3").touch()
            (root / "first.mp3").touch()
            selection = json.dumps([{"path": str(root / "first.mp3"), "kind": "track"}, {"path": str(folder), "kind": "folder"}])
            result = collect_selection(directory, selection)
            self.assertEqual([t["name"] for t in result["entries"]], ["first.mp3", "01.mp3", "02.mp3"])
            with patch("browse.MAX_ENTRIES", 2):
                result = collect_selection(directory, selection)
                self.assertEqual(len(result["entries"]), 2)
                self.assertTrue(result["truncated"])
            invalid = collect_selection(directory, json.dumps([{"path": "/outside.mp3", "kind": "track"}]))
            self.assertTrue(invalid["error"])

    def test_metadata_stream_reports_each_missing_track(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [str(Path(directory) / "one.mp3"), str(Path(directory) / "two.mp3")]
            output = io.StringIO()
            with redirect_stdout(output):
                queue_metadata(directory, json.dumps(paths), stream=True)
            lines = [json.loads(line) for line in output.getvalue().splitlines()]
            self.assertEqual([list(line["metadata"])[0] for line in lines], paths)

    def test_album_tracks_follow_natural_order(self):
        with tempfile.TemporaryDirectory() as directory:
            album = Path(directory) / "Artist" / "Album"
            album.mkdir(parents=True)
            for name in ("10 Ending.mp3", "2 Middle.mp3", "1 Opening.mp3"):
                (album / name).touch()
            tracks = tracks_in_folder(directory, str(album))["entries"]
            self.assertEqual([entry["name"] for entry in tracks],
                             ["1 Opening.mp3", "2 Middle.mp3", "10 Ending.mp3"])


if __name__ == "__main__":
    unittest.main()
