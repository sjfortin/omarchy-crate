"""Exercise the actual QML queue functions with player and persistence stubs."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import unittest


@unittest.skipUnless(shutil.which("node"), "Node is required for queue logic tests")
class QueueTests(unittest.TestCase):
    def test_consumption_insertion_and_index_adjustments(self):
        source = (Path(__file__).resolve().parents[1] / "Service.qml").read_text()
        functions = []
        for name in ("next", "removeQueueAt", "moveQueue", "playTrack", "playNext", "clearQueue", "queueKind", "explicitInsertIndex", "insertQueued", "enqueue", "enqueueMany", "playNextMany", "playAlbum", "shuffleQueue", "checkpoint", "undoQueue", "previous", "queueFolder", "queueSelection", "runFolderRequest", "saveMixtape", "loadMixtape", "removeMixtape"):
            match = re.search(r"  function " + name + r"\([^\n]*\) \{.*?\n  \}", source, re.S)
            self.assertIsNotNone(match)
            functions.append(match.group(0))
        script = '''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const c = vm.createContext({queue: [], queueKinds: [], currentIndex: -1, trackTitle: '', artist: '', album: '', history: [], undoStack: [], positionSec: 0, durationSec: 0, paused: false, resumePending: false, previousPressedAt: 0, mixtapes: [], operationError: '', folderRequests: [], folderRequestActive: false, folderQueueNext: false, folderQueueBody: '', selectionPayload: '', pluginDir: '/plugin', musicRoot: '/music', folderQueueProcess: {},
  get currentPath() { return c.queue[c.currentIndex] || '' },
  get upcomingCount() { return Math.max(0, c.queue.length - (c.currentIndex >= 0 ? c.currentIndex + 1 : 0)) },
  seek(n) { c.positionSec = n },
  stop() { c.stopped = true }, saveState() {}, queueEditing() {}, notify() {},
  playFolder(folder, track) { c.folder = folder; c.startTrack = track },
  playAt(index) { c.currentIndex = index; c.played = c.queue[index] },
});
vm.runInContext(FUNCTIONS, c);
function reset(queue, index) { c.queue = queue; c.queueKinds = queue.map(() => "queued"); c.currentIndex = index; c.played = null; c.stopped = false; c.history = []; c.undoStack = []; c.positionSec = 0 }
reset(['a', 'b', 'c'], 0); c.next(false);
assert.deepEqual(Array.from(c.queue), ['b', 'c']); assert.equal(c.played, 'b'); assert.equal(c.currentIndex, 0);
reset(['a'], 0); c.next(false);
assert.equal(c.queue.length, 0); assert.equal(c.currentIndex, -1); assert.equal(c.played, null);
reset(['a', 'b', 'c'], 1); c.next(true);
assert.deepEqual(Array.from(c.queue), ['a', 'c']); assert.equal(c.played, 'c');
reset(['a', 'b', 'c'], 1); c.removeQueueAt(0);
assert.deepEqual(Array.from(c.queue), ['b', 'c']); assert.equal(c.currentIndex, 0); assert.equal(c.stopped, false);
reset(['a', 'b', 'c'], 1); c.removeQueueAt(1);
assert.deepEqual(Array.from(c.queue), ['a', 'c']); assert.equal(c.played, 'c');
reset(['a', 'b'], 1); c.removeQueueAt(1); assert.equal(c.currentIndex, -1);
reset(['a', 'b', 'c'], 1); c.playTrack('x');
assert.equal(c.startTrack, 'x');
reset(['a', 'b', 'c'], 0); c.playNext('x');
assert.deepEqual(Array.from(c.queue), ['a', 'x', 'b', 'c']); assert.equal(c.played, null);
reset(['a', 'b', 'c'], 1); c.moveQueue(1, 1);
assert.deepEqual(Array.from(c.queue), ['a', 'c', 'b']); assert.equal(c.currentIndex, 2);
c.clearQueue(); assert.deepEqual(Array.from(c.queue), ['b']); assert.equal(c.currentIndex, 0);

reset(['old', 'request', 'old-album'], 0); c.queueKinds = ['album', 'queued', 'album'];
c.playAlbum(['first', 'clicked', 'following', 'last'], 1);
assert.deepEqual(Array.from(c.queue), ['clicked', 'request', 'following', 'last']);
assert.equal(c.played, 'clicked');
c.enqueue('second'); c.enqueueMany(['third', 'fourth']);
assert.deepEqual(Array.from(c.queue), ['clicked', 'request', 'second', 'third', 'fourth', 'following', 'last']);
c.playNext('urgent'); c.enqueue('fifth');
assert.deepEqual(Array.from(c.queue), ['clicked', 'urgent', 'request', 'second', 'third', 'fourth', 'fifth', 'following', 'last']);
c.next(false); assert.equal(c.played, 'urgent');
assert.equal(c.queueKinds.length, c.queue.length);
c.removeQueueAt(6); assert.equal(c.queueKind(6), 'album');
c.playAlbum(['new', 'tail'], 0);
assert.deepEqual(Array.from(c.queue), ['new', 'request', 'second', 'third', 'fourth', 'fifth', 'tail']);
c.shuffleQueue(); assert.equal(c.queue[0], 'new'); assert.equal(c.queue.at(-1), 'tail');
reset(['current', 'request', 'auto1', 'auto2'], 0); c.queueKinds = ['album', 'queued', 'album', 'album'];
c.moveQueue(3, -1); c.enqueue('later');
assert.deepEqual(Array.from(c.queue), ['current', 'request', 'auto2', 'later', 'auto1']);
assert.equal(c.queueKind(2), 'queued');
c.clearQueue(); assert.equal(c.queueKinds.length, 1);
reset([], -1); c.playAlbum(['a', 'b', 'c'], 1); c.enqueue('x'); c.playNextMany(['y', 'z']);
assert.deepEqual(Array.from(c.queue), ['b', 'y', 'z', 'x', 'c']);
reset(['same', 'same'], -1); c.queueKinds = ['queued', 'album']; c.enqueue('new');
assert.deepEqual(Array.from(c.queue), ['same', 'new', 'same']);
assert.deepEqual(Array.from(c.queueKinds), ['queued', 'queued', 'album']);

// History remains available after a track is consumed, including the final song.
reset(['a', 'b'], 0); c.next(false); c.previous();
assert.deepEqual(Array.from(c.queue), ['a', 'b']); assert.equal(c.played, 'a');
reset(['last'], 0); c.next(false); c.previous(); assert.equal(c.played, 'last');
c.positionSec = 30; c.previousPressedAt = 0; c.previous(); assert.equal(c.positionSec, 0);
// Undo preserves active playback for non-current edits, and restores removed current tracks paused.
reset(['a', 'b', 'c'], 0); c.positionSec = 24; c.removeQueueAt(1); c.undoQueue();
assert.deepEqual(Array.from(c.queue), ['a', 'b', 'c']); assert.equal(c.positionSec, 24); assert.equal(c.stopped, false);
c.removeQueueAt(0); c.undoQueue(); assert.equal(c.currentIndex, 0); assert.equal(c.paused, true); assert.equal(c.resumePending, true);
reset(['a', 'b', 'c'], 0); c.clearQueue(); c.undoQueue(); assert.deepEqual(Array.from(c.queue), ['a', 'b', 'c']);
c.shuffleQueue(); c.undoQueue(); assert.deepEqual(Array.from(c.queue), ['a', 'b', 'c']);
// Every rapid folder request survives, in click order.
c.queueFolder('/one'); c.queueFolder('/two'); c.queueFolder('/three');
assert.equal(c.folderQueueProcess.command.at(-1), '/one');
assert.deepEqual(Array.from(c.folderRequests, r => r.path), ['/two', '/three']);
c.folderRequestActive = false; c.runFolderRequest(); assert.equal(c.folderQueueProcess.command.at(-1), '/two');
c.folderRequestActive = false; c.runFolderRequest(); assert.equal(c.folderQueueProcess.command.at(-1), '/three');
c.folderRequestActive = false; c.queueSelection([{path:'/music/one.mp3',kind:'track'}], false);
assert.equal(c.folderQueueProcess.command[2], 'collect-stdin');
assert.equal(JSON.parse(c.selectionPayload)[0].path, '/music/one.mp3');
// Named snapshots are independent of subsequent queue changes and cannot overwrite silently.
reset(['a', 'b'], 0); assert.equal(c.saveMixtape(' Road '), true); c.queue.push('c');
assert.deepEqual(Array.from(c.mixtapes[0].paths), ['a', 'b']); assert.equal(c.saveMixtape('Road'), false);
reset([], -1); c.loadMixtape(0, false); assert.deepEqual(Array.from(c.queue), ['a', 'b']);
c.removeMixtape(0); assert.equal(c.mixtapes.length, 0);
'''.replace("FUNCTIONS", json.dumps("\n".join(functions)))
        result = subprocess.run(["node", "-e", script], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
