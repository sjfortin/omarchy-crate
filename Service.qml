import QtQuick
import Quickshell
import Quickshell.Io

// One service owns the player, queue, search, and current folder. The bar
// and browser are views of this state; closing either never stops playback.
Item {
  id: root
  visible: false
  width: 0
  height: 0

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "sjfortin.crate"
  readonly property string pluginDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : String(Quickshell.env("HOME")) + "/.config/omarchy/plugins/sjfortin.crate"
  readonly property string stateDir: {
    var xdg = String(Quickshell.env("XDG_STATE_HOME") || "")
    return (xdg || String(Quickshell.env("HOME")) + "/.local/state") + "/omarchy/crate"
  }
  readonly property string statePath: stateDir + "/state.json"
  readonly property string socketPath: {
    var runtime = String(Quickshell.env("XDG_RUNTIME_DIR") || "")
    return (runtime || stateDir) + "/omarchy-crate.mpv.sock"
  }

  property string musicRoot: "~/Music"
  property string rootDirectory: ""
  property string directory: ""
  property string parentDirectory: ""
  property var entries: []
  property bool directoryLoading: false
  property string directoryError: ""
  property bool truncated: false
  property string pendingDirectory: ""
  property string scanBody: ""
  property string searchQuery: ""
  property var searchResults: []
  property bool searchLoading: false
  property bool searchTruncated: false
  property string searchError: ""
  property string searchBody: ""
  property string pendingSearch: ""
  property string folderQueueBody: ""
  property string pendingFolder: ""
  property bool folderQueueNext: false
  property bool pendingFolderNext: false
  property string albumBody: ""
  property string pendingAlbum: ""
  property string pendingAlbumTrack: ""
  property string albumStartTrack: ""

  property var queue: []
  property int currentIndex: -1
  property string repeatMode: "off"
  property bool resumePending: false
  property bool stateLoaded: false
  readonly property string currentPath: currentIndex >= 0 && currentIndex < queue.length
    ? String(queue[currentIndex]) : ""
  readonly property string currentTitle: titleFor(currentPath)
  property string trackTitle: ""
  property string artist: ""
  property string album: ""
  readonly property string displayTitle: (trackTitle || currentTitle)
    + (artist ? "  ·  " + artist : "") + (album ? "  /  " + album : "")
  readonly property bool playing: player.running && !paused
  property bool paused: false
  property real positionSec: 0
  property real durationSec: 0
  property int volume: 70
  property string playbackError: ""
  property bool switching: false
  property bool stopRequested: false
  property bool ipcReady: false
  property int ipcAttempts: 0

  function titleFor(path) {
    if (!path) return "Nothing playing"
    var name = String(path).split("/").pop()
    return name.replace(/\.[^.]+$/, "")
  }

  function setMusicRoot(path) {
    var wanted = String(path || "~/Music").trim() || "~/Music"
    if (wanted === musicRoot) return
    musicRoot = wanted
    rootDirectory = ""
    directory = ""
    parentDirectory = ""
    browse("")
  }

  function browse(path) {
    var wanted = String(path || "")
    if (scan.running) {
      pendingDirectory = wanted || musicRoot
      return
    }
    directoryLoading = true
    directoryError = ""
    scanBody = ""
    scan.command = ["python3", pluginDir + "/scripts/browse.py", "list", musicRoot, wanted]
    scan.running = true
  }

  function refresh() { browse(directory || musicRoot) }

  function search(query) {
    searchQuery = String(query || "").trim()
    searchResults = []
    if (!searchQuery) {
      searchResults = []; searchLoading = false
      if (searchProcess.running) pendingSearch = " "
      return
    }
    if (searchProcess.running) { pendingSearch = searchQuery; return }
    searchLoading = true
    searchBody = ""
    searchProcess.command = ["python3", pluginDir + "/scripts/browse.py", "search", musicRoot, searchQuery]
    searchProcess.running = true
  }

  function queueFolder(path, next) {
    if (!path) return
    if (folderQueueProcess.running) {
      pendingFolder = String(path); pendingFolderNext = next === true; return
    }
    folderQueueNext = next === true
    folderQueueBody = ""
    folderQueueProcess.command = ["python3", pluginDir + "/scripts/browse.py", "tracks", musicRoot, String(path)]
    folderQueueProcess.running = true
  }

  function playFolder(path, startTrack) {
    if (!path) return
    if (albumProcess.running) {
      pendingAlbum = String(path)
      pendingAlbumTrack = String(startTrack || "")
      return
    }
    albumStartTrack = String(startTrack || "")
    albumBody = ""
    albumProcess.command = ["python3", pluginDir + "/scripts/browse.py", "tracks", musicRoot, String(path)]
    albumProcess.running = true
  }

  function saveState() {
    if (!stateLoaded) return
    stateFile.setText(JSON.stringify({
      version: 1,
      queue: queue,
      currentIndex: currentIndex,
      positionSec: positionSec,
      directory: directory,
      repeatMode: repeatMode
    }, null, 2) + "\n")
  }

  function enqueue(path) {
    if (!path) return
    var next = queue.slice()
    next.push(String(path))
    queue = next
    saveState()
  }

  function playNext(path) {
    if (!path) return
    var next = queue.slice()
    var index = currentIndex >= 0 ? currentIndex + 1 : 0
    next.splice(index, 0, String(path))
    queue = next
    saveState()
  }

  function playNextMany(paths) {
    if (!paths.length) return
    var index = currentIndex >= 0 ? currentIndex + 1 : 0
    queue = queue.slice(0, index).concat(paths, queue.slice(index))
    saveState()
  }

  function shuffleQueue() {
    var start = currentIndex >= 0 ? currentIndex + 1 : 0
    var next = queue.slice()
    for (var i = next.length - 1; i > start; i--) {
      var j = start + Math.floor(Math.random() * (i - start + 1))
      var item = next[i]; next[i] = next[j]; next[j] = item
    }
    queue = next
    saveState()
  }

  function cycleRepeat() {
    repeatMode = repeatMode === "off" ? "all" : (repeatMode === "all" ? "one" : "off")
    saveState()
  }

  function enqueueMany(paths) {
    var next = queue.slice()
    for (var i = 0; i < paths.length; i++) if (paths[i]) next.push(String(paths[i]))
    if (next.length === queue.length) return
    queue = next
    saveState()
  }

  function playAt(index) {
    if (index < 0 || index >= queue.length) return
    currentIndex = index
    paused = false
    positionSec = 0
    durationSec = 0
    playbackError = ""
    trackTitle = ""
    artist = ""
    album = ""
    resumePending = false
    saveState()
    startTrack()
  }

  function startTrack() {
    if (!currentPath) return
    if (player.running) {
      switching = true
      closeIpc()
      player.running = false
      startAfterStop.restart()
    } else {
      launchTrack()
    }
  }

  function launchTrack() {
    if (!currentPath) return
    switching = false
    stopRequested = false
    ipcAttempts = 0
    player.command = [
      "mpv", "--no-config", "--no-video", "--audio-display=no",
      "--terminal=no", "--idle=no", "--keep-open=no", "--ytdl=no",
      "--audio-client-name=Crate", "--volume=" + volume,
      "--input-ipc-server=" + socketPath,
      "--start=" + (resumePending ? Math.max(0, positionSec) : 0),
      "--", currentPath
    ]
    resumePending = false
    player.running = true
  }

  function togglePlayback() {
    if (!player.running) {
      if (currentIndex >= 0) launchTrack()
      else if (queue.length) playAt(0)
    } else {
      paused = !paused
      send(["set_property", "pause", paused])
      saveState()
    }
  }

  function stop() {
    stopRequested = true
    switching = false
    paused = false
    positionSec = 0
    closeIpc()
    player.running = false
    saveState()
  }

  function next(manual) {
    if (manual !== true && repeatMode === "one" && currentIndex >= 0) { playAt(currentIndex); return }
    if (currentIndex + 1 < queue.length) playAt(currentIndex + 1)
    else if (repeatMode === "all" && queue.length) playAt(0)
    else stop()
  }

  function previous() {
    if (positionSec > 3) seek(0)
    else if (currentIndex > 0) playAt(currentIndex - 1)
    else seek(0)
  }

  function removeQueueAt(index) {
    if (index < 0 || index >= queue.length) return
    var wasCurrent = index === currentIndex
    var next = queue.slice()
    next.splice(index, 1)
    queue = next
    if (wasCurrent) {
      stop()
      currentIndex = -1
      if (index < next.length) playAt(index)
      else saveState()
    } else {
      if (index < currentIndex) currentIndex--
      saveState()
    }
  }

  function moveQueue(index, delta) {
    var target = index + delta
    if (index < 0 || target < 0 || target >= queue.length) return
    var next = queue.slice()
    var item = next.splice(index, 1)[0]
    next.splice(target, 0, item)
    queue = next
    if (currentIndex === index) currentIndex = target
    else if (index < currentIndex && target >= currentIndex) currentIndex--
    else if (index > currentIndex && target <= currentIndex) currentIndex++
    saveState()
  }

  function clearQueue() {
    stop()
    queue = []
    currentIndex = -1
    saveState()
  }

  function seek(seconds) {
    if (!ipcReady) return
    var wanted = Math.max(0, Math.min(Number(seconds) || 0, durationSec || Infinity))
    positionSec = wanted
    send(["seek", wanted, "absolute"])
  }

  function setVolume(value) {
    volume = Math.max(0, Math.min(100, Math.round(Number(value) || 0)))
    send(["set_property", "volume", volume])
  }

  function send(command, requestId) {
    if (!ipcReady || !ipcLoader.item) return
    ipcLoader.item.write(JSON.stringify({ command: command, request_id: requestId || 1 }) + "\n")
    ipcLoader.item.flush()
  }

  function closeIpc() {
    ipcConnect.stop()
    ipcReady = false
    ipcLoader.active = false
  }

  function onIpcReady() {
    if (!ipcLoader.item || !ipcLoader.item.connected || ipcReady) return
    ipcReady = true
    ipcConnect.stop()
    send(["observe_property", 1, "pause"])
    send(["get_property", "duration"], 900002)
    send(["get_property", "metadata"], 900003)
  }

  function handleIpc(line) {
    var message
    try { message = JSON.parse(String(line)) } catch (e) { return }
    if (message.event === "property-change" && message.name === "pause")
      paused = message.data === true
    if (message.request_id === 900001 && message.error === "success")
      positionSec = Math.max(0, Number(message.data) || 0)
    if (message.request_id === 900002 && message.error === "success")
      durationSec = Math.max(0, Number(message.data) || 0)
    if (message.request_id === 900003 && message.error === "success" && message.data) {
      var tags = message.data
      trackTitle = String(tags.title || tags.TITLE || "")
      artist = String(tags.artist || tags.ARTIST || "")
      album = String(tags.album || tags.ALBUM || "")
    }
    if (message.event === "file-loaded") {
      send(["get_property", "duration"], 900002)
      send(["get_property", "metadata"], 900003)
    }
  }

  function openBrowser(page) {
    if (!shell || typeof shell.summon !== "function") return false
    return shell.summon(pluginId, JSON.stringify({ page: page || "files" })) === true
  }

  Process {
    id: stateDirInit
    running: true
    command: ["mkdir", "-p", root.stateDir]
    onExited: stateFile.reload()
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var saved = JSON.parse(text())
        root.queue = Array.isArray(saved.queue) ? saved.queue.filter(function(p) { return typeof p === "string" }) : []
        root.currentIndex = Number.isInteger(saved.currentIndex) && saved.currentIndex >= 0
          && saved.currentIndex < root.queue.length ? saved.currentIndex : -1
        root.positionSec = Math.max(0, Number(saved.positionSec) || 0)
        root.resumePending = root.currentIndex >= 0 && root.positionSec > 0
        root.repeatMode = ["off", "all", "one"].indexOf(saved.repeatMode) !== -1 ? saved.repeatMode : "off"
        if (typeof saved.directory === "string" && saved.directory) root.browse(saved.directory)
      } catch (e) { /* leave the in-memory library empty */ }
      root.stateLoaded = true
    }
    onLoadFailed: function(error) { root.stateLoaded = true }
  }

  Process {
    id: scan
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.scanBody = String(text || "")
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      if (root.pendingDirectory) {
        var wanted = root.pendingDirectory
        root.pendingDirectory = ""
        Qt.callLater(function() { root.browse(wanted) })
        return
      }
      root.directoryLoading = false
      try {
        var result = JSON.parse(root.scanBody)
        root.directoryError = String(result.error || "")
        root.entries = Array.isArray(result.entries) ? result.entries : []
        root.truncated = result.truncated === true
        if (!root.directoryError) {
          root.rootDirectory = String(result.root || "")
          root.directory = String(result.path || "")
          root.parentDirectory = String(result.parent || "")
          root.saveState()
        }
      } catch (e) {
        root.directoryError = "Could not read this folder"
        root.entries = []
      }
    }
  }

  Process {
    id: searchProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.searchBody = String(text || "")
    }
    onExited: {
      if (root.pendingSearch) {
        var wanted = root.pendingSearch
        root.pendingSearch = ""
        Qt.callLater(function() { root.search(wanted) })
        return
      }
      root.searchLoading = false
      try {
        var result = JSON.parse(root.searchBody)
        root.searchResults = Array.isArray(result.entries) ? result.entries : []
        root.searchTruncated = result.truncated === true
        root.searchError = String(result.error || "")
      } catch (e) { root.searchResults = []; root.searchError = "Search failed" }
    }
  }

  Process {
    id: folderQueueProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.folderQueueBody = String(text || "")
    }
    onExited: {
      try {
        var result = JSON.parse(root.folderQueueBody)
        if (result.error) root.directoryError = String(result.error)
        else {
          var paths = result.entries.map(function(entry) { return entry.path })
          if (root.folderQueueNext) root.playNextMany(paths)
          else root.enqueueMany(paths)
        }
      } catch (e) { root.directoryError = "Could not queue this folder" }
      if (root.pendingFolder) {
        var wanted = root.pendingFolder
        var next = root.pendingFolderNext
        root.pendingFolder = ""
        Qt.callLater(function() { root.queueFolder(wanted, next) })
      }
    }
  }

  Process {
    id: albumProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.albumBody = String(text || "")
    }
    onExited: {
      if (!root.pendingAlbum) {
        try {
          var result = JSON.parse(root.albumBody)
          if (result.error) root.playbackError = String(result.error)
          else {
            var paths = result.entries.map(function(entry) { return entry.path })
            if (!paths.length) root.playbackError = "No playable tracks in this folder"
            else {
              var index = root.albumStartTrack ? paths.indexOf(root.albumStartTrack) : 0
              if (index < 0) root.playbackError = "Selected track is no longer in this folder"
              else {
                root.queue = paths
                root.playAt(index)
              }
            }
          }
        } catch (e) { root.playbackError = "Could not play this folder" }
      }
      if (root.pendingAlbum) {
        var wanted = root.pendingAlbum
        var track = root.pendingAlbumTrack
        root.pendingAlbum = ""
        root.pendingAlbumTrack = ""
        Qt.callLater(function() { root.playFolder(wanted, track) })
      }
    }
  }

  Process {
    id: player
    running: false
    onStarted: ipcConnect.restart()
    onExited: function(exitCode, exitStatus) {
      root.closeIpc()
      if (root.switching) return
      if (root.stopRequested) return
      if (exitCode === 0) root.next(false)
      else root.playbackError = "Could not play this file"
    }
  }

  Timer {
    id: startAfterStop
    interval: 350
    onTriggered: root.launchTrack()
  }

  Timer {
    id: ipcConnect
    interval: 200
    repeat: true
    onTriggered: {
      if (!player.running || root.ipcReady) { stop(); return }
      root.ipcAttempts++
      if (root.ipcAttempts > 30) { stop(); return }
      ipcLoader.active = false
      ipcLoader.active = true
    }
  }

  Loader {
    id: ipcLoader
    active: false
    onLoaded: if (item && item.connected) Qt.callLater(root.onIpcReady)
    sourceComponent: Socket {
      path: root.socketPath
      connected: true
      parser: SplitParser {
        splitMarker: "\n"
        onRead: function(data) { root.handleIpc(data) }
      }
      onConnectionStateChanged: if (connected) Qt.callLater(root.onIpcReady)
      onError: function(error) {}
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.playing && root.ipcReady
    onTriggered: {
      root.send(["get_property", "time-pos"], 900001)
      if (root.durationSec <= 0) root.send(["get_property", "duration"], 900002)
    }
  }

  Timer {
    interval: 5000
    repeat: true
    running: root.playing
    onTriggered: root.saveState()
  }

  IpcHandler {
    target: "crate"
    function open(): string { return root.openBrowser("files") ? "ok" : "unavailable" }
    function toggle(): void { root.togglePlayback() }
    function next(): void { root.next(true) }
    function previous(): void { root.previous() }
    function status(): string { return (root.playing ? "playing " : "paused ") + root.currentTitle }
  }

  Component.onCompleted: browse("")
  Component.onDestruction: {
    closeIpc()
    player.running = false
  }
}
