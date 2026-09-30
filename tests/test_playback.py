import http.server
import io
import re
import shutil
import subprocess
import tempfile
import threading
import unittest
import wave
from pathlib import Path


@unittest.skipUnless(shutil.which("mpv"), "mpv is required for playback tests")
class PlaybackTests(unittest.TestCase):
    def test_disguised_playlists_cannot_fetch_references(self):
        # Exercise the actual fixed launch options, using a silent audio output.
        service = (Path(__file__).resolve().parents[1] / "Service.qml").read_text()
        command = service.split("player.command = [", 1)[1].split("]", 1)[0]
        options = [option for option in re.findall(r'"(--[^"]*)"\s*,', command)
                   if option != "--"]
        options += ["--ao=null", "--length=0.05"]
        audio = io.BytesIO()
        with wave.open(audio, "wb") as track:
            track.setparams((1, 2, 8000, 0, "NONE", "not compressed"))
            track.writeframes(b"\x00\x00" * 800)
        requests = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                self.send_response(200)
                self.send_header("Content-Type", "audio/wav")
                self.send_header("Content-Length", str(len(audio.getvalue())))
                self.end_headers()
                self.wfile.write(audio.getvalue())

            def log_message(self, *_args):
                pass

        with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            try:
                with tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    url = f"http://127.0.0.1:{server.server_port}/track.wav"
                    disguised = root / "playlist.mp3"
                    disguised.write_text(f"#EXTM3U\n{url}\n")

                    def play(path, flags):
                        return subprocess.run(
                            ["mpv", *flags, "--", str(path)],
                            capture_output=True, timeout=10,
                        )

                    # Confirm the fixture exposes the original bug on this mpv.
                    unsafe = [flag for flag in options if flag != "--access-references=no"]
                    play(disguised, unsafe)
                    self.assertTrue(requests, "Control playlist did not reach the HTTP server")
                    requests.clear()

                    for content in (f"#EXTM3U\n{url}\n",
                                    f"[playlist]\nNumberOfEntries=1\nFile1={url}\nVersion=2\n"):
                        with self.subTest(playlist=content.splitlines()[0]):
                            disguised.write_text(content)
                            play(disguised, options)
                            self.assertEqual(requests, [])

                    local = root / "local.wav"
                    local.write_bytes(audio.getvalue())
                    result = play(local, options)
                    self.assertEqual(result.returncode, 0, result.stderr.decode())
            finally:
                server.shutdown()
                worker.join()
