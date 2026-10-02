import tempfile
import json
import shutil
import subprocess
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from browse import list_folder, search_music, tracks_in_folder, queue_metadata


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
