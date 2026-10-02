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
        for name in ("next", "removeQueueAt", "moveQueue", "playTrack", "playNext", "clearQueue"):
            match = re.search(r"  function " + name + r"\([^\n]*\) \{.*?\n  \}", source, re.S)
            self.assertIsNotNone(match)
            functions.append(match.group(0))
        script = '''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const c = vm.createContext({queue: [], currentIndex: -1, trackTitle: '', artist: '', album: '',
  stop() { c.stopped = true }, saveState() {}, queueEditing() {}, notify() {},
  playAt(index) { c.currentIndex = index; c.played = c.queue[index] },
});
vm.runInContext(FUNCTIONS, c);
function reset(queue, index) { c.queue = queue; c.currentIndex = index; c.played = null; c.stopped = false }
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
assert.deepEqual(Array.from(c.queue), ['a', 'b', 'x', 'c']); assert.equal(c.played, 'x');
reset(['a', 'b', 'c'], 0); c.playNext('x');
assert.deepEqual(Array.from(c.queue), ['a', 'x', 'b', 'c']); assert.equal(c.played, null);
reset(['a', 'b', 'c'], 1); c.moveQueue(1, 1);
assert.deepEqual(Array.from(c.queue), ['a', 'c', 'b']); assert.equal(c.currentIndex, 2);
c.clearQueue(); assert.deepEqual(Array.from(c.queue), ['b']); assert.equal(c.currentIndex, 0);
'''.replace("FUNCTIONS", json.dumps("\n".join(functions)))
        result = subprocess.run(["node", "-e", script], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
