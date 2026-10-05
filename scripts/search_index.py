"""Incremental, local search index for Crate's music library."""

import os
from pathlib import Path
import sqlite3
import subprocess
import time

import json
from contextlib import closing


AUDIO_EXTENSIONS = {
    ".aac", ".aif", ".aiff", ".alac", ".ape", ".dsf", ".dff",
    ".flac", ".m4a", ".mp3", ".mpc", ".oga", ".ogg", ".opus",
    ".wav", ".wma", ".wv",
}
MAX_INDEX_ENTRIES = 100000


def connect(db_path):
    db = sqlite3.connect(db_path, timeout=2)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("CREATE TABLE IF NOT EXISTS library (root TEXT PRIMARY KEY, indexed_at INTEGER, scan_limited INTEGER)")
    db.execute("""CREATE TABLE IF NOT EXISTS entries (
        path TEXT PRIMARY KEY, relative TEXT NOT NULL, kind TEXT NOT NULL,
        mtime_ns INTEGER, size INTEGER, title TEXT, artist TEXT, album TEXT,
        seen INTEGER NOT NULL DEFAULT 0
    )""")
    return db


def tags_for(path):
    try:
        result = subprocess.run(
            ["ffprobe", "-v", "error", "-protocol_whitelist", "file",
             "-show_entries", "format_tags=title,artist,album", "-of", "json", path],
            capture_output=True, text=True, timeout=3,
        )
        if result.returncode:
            return {}, False
        tags = json.loads(result.stdout).get("format", {}).get("tags", {})
        return {k.lower(): str(v) for k, v in tags.items()
                if k.lower() in {"title", "artist", "album"}}, True
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return {}, False


def index_music(root_arg, db_path, progress=None):
    root = Path(os.path.expanduser(root_arg)).resolve()
    if not root.is_dir():
        return {"error": f"Music folder does not exist: {root}"}
    Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    root_text = str(root)
    stamp = time.time_ns()
    scanned = 0
    skipped = 0
    pending_tags = []
    processed_tags = 0
    with closing(connect(db_path)) as db:
        prior = db.execute("SELECT root FROM library LIMIT 1").fetchone()
        if prior and prior[0] != root_text:
            db.execute("DELETE FROM entries")
            db.execute("DELETE FROM library")
        # Keep the previous completed index available while the next scan runs.
        db.execute("INSERT OR IGNORE INTO library VALUES (?, 0, 0)", (root_text,))
        db.commit()
        prefix = root_text.rstrip(os.sep) + os.sep
        for folder, dirs, files in os.walk(root, followlinks=False):
            dirs[:] = [name for name in dirs if not name.startswith(".")
                       and not os.path.islink(os.path.join(folder, name))]
            names = [(name, "folder") for name in dirs]
            names += [(name, "track") for name in files
                      if not name.startswith(".") and Path(name).suffix.lower() in AUDIO_EXTENSIONS]
            for name, kind in names:
                path = os.path.join(folder, name)
                if os.path.islink(path):
                    continue
                try:
                    info = os.stat(path, follow_symlinks=False)
                except OSError:
                    continue
                relative = path[len(prefix):]
                old = db.execute("SELECT mtime_ns, size, title FROM entries WHERE path=?", (path,)).fetchone()
                if old and old[:2] == (info.st_mtime_ns, info.st_size):
                    db.execute("UPDATE entries SET seen=?, relative=? WHERE path=?", (stamp, relative, path))
                    if kind == "track" and old[2] is None:
                        pending_tags.append(path)
                else:
                    db.execute("""INSERT INTO entries (path, relative, kind, mtime_ns, size, title, artist, album, seen)
                                  VALUES (?, ?, ?, ?, ?, NULL, NULL, NULL, ?)
                                  ON CONFLICT(path) DO UPDATE SET relative=excluded.relative, kind=excluded.kind,
                                      mtime_ns=excluded.mtime_ns, size=excluded.size,
                                      title=NULL, artist=NULL, album=NULL, seen=excluded.seen""",
                               (path, relative, kind, info.st_mtime_ns, info.st_size, stamp))
                    if kind == "track":
                        pending_tags.append(path)
                scanned += 1
                if scanned % 300 == 0:
                    db.commit()
                if scanned >= MAX_INDEX_ENTRIES:
                    break
            if scanned >= MAX_INDEX_ENTRIES:
                break
        # A completed scan removes files that vanished since the prior run.
        db.execute("DELETE FROM entries WHERE seen != ?", (stamp,))
        db.execute("UPDATE library SET indexed_at=?, scan_limited=? WHERE root=?",
                   (stamp, int(scanned >= MAX_INDEX_ENTRIES), root_text))
        db.commit()
        if progress:
            progress(0, len(pending_tags))
        for path in pending_tags:
            if os.path.islink(path) or not Path(path).resolve().is_relative_to(root):
                continue
            tags, success = tags_for(path)
            processed_tags += 1
            if not success:
                skipped += 1
                if progress and processed_tags % 32 == 0:
                    progress(processed_tags, len(pending_tags))
                continue
            # A file may change while ffprobe is reading it; recheck next refresh.
            try:
                info = os.stat(path, follow_symlinks=False)
            except OSError:
                continue
            db.execute("""UPDATE entries SET title=?, artist=?, album=?
                          WHERE path=? AND mtime_ns=? AND size=? AND seen=?""",
                       (tags.get("title", ""), tags.get("artist", ""), tags.get("album", ""),
                        path, info.st_mtime_ns, info.st_size, stamp))
            if processed_tags % 32 == 0:
                db.commit()
                if progress:
                    progress(processed_tags, len(pending_tags))
        db.commit()
        if progress:
            progress(processed_tags, len(pending_tags))
    return {"error": "", "count": scanned, "tagsSkipped": skipped,
            "scanLimited": scanned >= MAX_INDEX_ENTRIES}


def indexed_entries(root_arg, db_path):
    """Return None until the first scan has committed its filenames."""
    if not db_path or not Path(db_path).is_file():
        return None
    root = str(Path(os.path.expanduser(root_arg)).resolve())
    try:
        with closing(sqlite3.connect(db_path, timeout=0.3)) as db:
            status = db.execute("SELECT indexed_at, scan_limited FROM library WHERE root=?", (root,)).fetchone()
            if not status or not status[0]:
                return None
            rows = db.execute("SELECT path, relative, kind, title, artist, album FROM entries").fetchall()
            return rows, bool(status[1])
    except (OSError, sqlite3.Error):
        return None


def cached_tags(root_arg, db_path, original):
    """Reuse tags only when the path remains inside the root and stat matches."""
    if not db_path or not Path(db_path).is_file():
        return None
    root = Path(os.path.expanduser(root_arg)).resolve()
    path = Path(original).resolve()
    if not path.is_relative_to(root):
        return None
    try:
        info = path.stat()
        with closing(sqlite3.connect(db_path, timeout=0.3)) as db:
            row = db.execute("""SELECT mtime_ns, size, title, artist, album
                                FROM entries WHERE path=?""", (str(path),)).fetchone()
        if row and row[0] == info.st_mtime_ns and row[1] == info.st_size and row[2] is not None:
            return {key: value for key, value in zip(("title", "artist", "album"), row[2:]) if value}
    except (OSError, sqlite3.Error):
        pass
    return None
