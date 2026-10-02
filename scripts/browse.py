#!/usr/bin/env python3
"""List one music folder for the Quickshell UI. Never traverse outside the root."""

import json
import os
from pathlib import Path
import sys
import re
import subprocess
import unicodedata


AUDIO_EXTENSIONS = {
    ".aac", ".aif", ".aiff", ".alac", ".ape", ".dsf", ".dff",
    ".flac", ".m4a", ".mp3", ".mpc", ".oga", ".ogg", ".opus",
    ".wav", ".wma", ".wv",
}
MAX_ENTRIES = 5000
MAX_SEARCH_FILES = 100000
MAX_RESULTS = 100


def natural_key(name: str) -> list:
    return [int(part) if part.isdecimal() else part.casefold()
            for part in re.split(r"(\d+)", name)]


def list_folder(root_arg: str, folder_arg: str) -> dict:
    root = Path(os.path.expanduser(root_arg)).resolve()
    folder = Path(os.path.expanduser(folder_arg)).resolve() if folder_arg else root
    if not root.is_dir():
        return {"error": f"Music folder does not exist: {root}", "entries": []}
    if not folder.is_relative_to(root) or not folder.is_dir():
        return {"error": "Folder is outside the music library", "entries": []}

    entries = []
    try:
        for child in folder.iterdir():
            if child.name.startswith("."):
                continue
            try:
                resolved = child.resolve()
                if not resolved.is_relative_to(root):
                    continue
                if child.is_dir():
                    kind = "folder"
                elif child.is_file() and child.suffix.lower() in AUDIO_EXTENSIONS:
                    kind = "track"
                else:
                    continue
                entries.append({"name": child.name, "path": str(resolved), "kind": kind})
            except (OSError, RuntimeError):
                continue
    except OSError as error:
        return {"error": str(error), "entries": []}

    entries.sort(key=lambda entry: (entry["kind"] != "folder", natural_key(entry["name"])))
    return {
        "root": str(root),
        "path": str(folder),
        "parent": str(folder.parent) if folder != root else "",
        "entries": entries[:MAX_ENTRIES],
        "truncated": len(entries) > MAX_ENTRIES,
        "error": "",
    }


def normalize(text: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFKD", text.casefold())
                   if not unicodedata.combining(c))


def score_match(query: str, relative: str) -> float:
    text = normalize(relative)
    name = normalize(os.path.basename(relative))
    parts = normalize(query).split()
    if not parts:
        return 0
    score = 0.0
    for part in parts:
        if part in name:
            score += 100 - name.index(part) * 0.1
        elif part in text:
            score += 55 - text.index(part) * 0.05
        else:
            if part[0] not in text:
                return 0
            # A subsequence catches small omissions without a costly edit-distance scan.
            best = 0.0
            for word in re.split(r"[^\w]+", text):
                if (len(part) < 3 or not len(part) <= len(word) <= len(part) + 3
                        or word[0] != part[0]):
                    continue
                letters = iter(word)
                if all(letter in letters for letter in part):
                    best = max(best, len(part) / len(word))
            if not best:
                return 0
            score += best * 35
    return score


def search_music(root_arg: str, query: str) -> dict:
    root = Path(os.path.expanduser(root_arg)).resolve()
    if not root.is_dir():
        return {"error": f"Music folder does not exist: {root}", "entries": []}
    query = query.strip()
    if not query:
        return {"error": "", "entries": [], "truncated": False}
    matches = []
    scanned = 0
    root_path = str(root)
    root_prefix = root_path.rstrip(os.sep) + os.sep
    for folder, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = [name for name in dirs if not name.startswith(".")
                   and not os.path.islink(os.path.join(folder, name))]
        for name, kind in [(name, "folder") for name in dirs] + [(name, "track") for name in files]:
            if name.startswith("."):
                continue
            path = os.path.join(folder, name)
            if kind == "track" and os.path.splitext(name)[1].lower() not in AUDIO_EXTENSIONS:
                continue
            if os.path.islink(path):
                continue
            scanned += 1
            relative = path[len(root_prefix):]
            score = score_match(query, relative)
            if score:
                matches.append((score, relative.casefold(), {
                    "name": name, "path": path, "kind": kind,
                    "relative": relative,
                }))
            if scanned >= MAX_SEARCH_FILES:
                break
        if scanned >= MAX_SEARCH_FILES:
            break
    matches.sort(key=lambda item: (-item[0], item[1]))
    return {"error": "", "entries": [item[2] for item in matches[:MAX_RESULTS]],
            "truncated": scanned >= MAX_SEARCH_FILES or len(matches) > MAX_RESULTS}


def tracks_in_folder(root_arg: str, folder_arg: str) -> dict:
    result = list_folder(root_arg, folder_arg)
    if result.get("error"):
        return result
    root = Path(result["root"])
    folder = Path(result["path"])
    tracks = []
    for current, dirs, files in os.walk(folder, followlinks=False):
        dirs[:] = sorted((name for name in dirs if not name.startswith(".")
                          and not (Path(current) / name).is_symlink()), key=natural_key)
        for name in sorted(files, key=natural_key):
            path = Path(current) / name
            if name.startswith(".") or path.is_symlink() or path.suffix.lower() not in AUDIO_EXTENSIONS:
                continue
            if not path.resolve().is_relative_to(root):
                continue
            tracks.append({"name": name, "path": str(path), "kind": "track"})
            if len(tracks) >= MAX_ENTRIES:
                result["truncated"] = True
                break
        if len(tracks) >= MAX_ENTRIES:
            break
    result["entries"] = tracks
    return result


def queue_metadata(root_arg: str, paths_arg: str) -> dict:
    """Read tags off the UI thread; restrict probes to local library audio."""
    root = Path(os.path.expanduser(root_arg)).resolve()
    metadata = {}
    try:
        paths = json.loads(paths_arg)
        if not isinstance(paths, list):
            raise ValueError("Expected track paths")
        for original in paths[:100]:
            if not isinstance(original, str):
                continue
            metadata[original] = {}
            path = Path(original).resolve()
            if not path.is_relative_to(root) or path.suffix.lower() not in AUDIO_EXTENSIONS or not path.is_file():
                continue
            try:
                result = subprocess.run(
                    ["ffprobe", "-v", "error", "-protocol_whitelist", "file",
                     "-show_entries", "format_tags=title,artist,album", "-of", "json", str(path)],
                    capture_output=True, text=True, timeout=3,
                )
                tags = json.loads(result.stdout).get("format", {}).get("tags", {})
                metadata[original] = {k.lower(): str(v) for k, v in tags.items()
                                      if k.lower() in {"title", "artist", "album"}}
            except (OSError, ValueError, subprocess.TimeoutExpired):
                pass
        return {"error": "", "metadata": metadata}
    except (OSError, ValueError, RuntimeError) as error:
        return {"error": str(error), "metadata": metadata}


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in {"list", "search", "tracks", "metadata"}:
        print(json.dumps({"error": "usage: browse.py {list|search|tracks|metadata} ROOT ARG", "entries": []}))
        sys.exit(2)
    result = {"list": list_folder, "search": search_music,
              "tracks": tracks_in_folder, "metadata": queue_metadata}[sys.argv[1]](sys.argv[2], sys.argv[3])
    print(json.dumps(result, ensure_ascii=False))
    sys.exit(1 if result["error"] else 0)
