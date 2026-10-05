import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

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
  readonly property string searchIndexPath: stateDir + "/search-index.sqlite"
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
  property string searchKind: "all"
  property bool indexing: false
  property bool searchIndexed: false
  property bool indexPending: false
  property string indexAttemptedRoot: ""
  property string indexRoot: ""
  property string indexBody: ""
  property int indexDone: 0
  property int indexTotal: -1
  property var searchResults: []
  property bool searchLoading: false
  property bool searchTruncated: false
  property string searchError: ""
  property string searchBody: ""
  property string pendingSearch: ""
  property string folderQueueBody: ""
  property string selectionPayload: ""
  property var folderRequests: []
  property bool folderRequestActive: false
  readonly property bool addingFolders: folderRequestActive || folderRequests.length > 0
  property bool folderQueueNext: false
  property bool searchActive: false
  property bool searchScanLimited: false
  property string operationError: ""
  property string operationWarning: ""
  property string userMusicRoot: ""
  property var recentFolders: []
  property var pinnedFolders: []
  property var mixtapes: []
  property var history: []
  property var undoStack: []
  property var visibleMetadataPaths: []
  readonly property int upcomingCount: Math.max(0, queue.length - (currentIndex >= 0 ? currentIndex + 1 : 0))
  readonly property bool canUndo: undoStack.length > 0
  property real previousPressedAt: 0
  property string albumBody: ""
  property string pendingAlbum: ""
  property string pendingAlbumTrack: ""
  property string albumStartTrack: ""

  signal queueEditing()
  property var queue: []
  // Per-entry provenance: duplicate paths can have different priorities.
  property var queueKinds: []
  property int currentIndex: -1
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
  readonly property var outputSink: Pipewire.defaultAudioSink
  readonly property int volume: outputSink && outputSink.audio
    ? Math.round(outputSink.audio.volume * 100) : 0
  readonly property bool muted: outputSink && outputSink.audio ? outputSink.audio.muted : false
  PwObjectTracker { objects: root.outputSink ? [root.outputSink] : [] }

  property var trackInfo: ({})
  property bool metadataIgnore: false
  property string notice: ""
  function notify(text) { notice = text; noticeTimer.restart() }
  Timer { id: noticeTimer; interval: 2500; onTriggered: root.notice = "" }
  onQueueChanged: metadataDelay.restart()
  onVisibleMetadataPathsChanged: metadataDelay.restart()
  onCurrentPathChanged: metadataDelay.restart()
  Timer { id: metadataDelay; interval: 100; onTriggered: root.loadQueueMetadata() }
  function loadQueueMetadata() {
    if (metadataProcess.running) return
    var candidates = (currentPath ? [currentPath] : []).concat(visibleMetadataPaths, queue)
    var seen = {}
    var missing = candidates.filter(function(path) { if (seen[path] || trackInfo[path]) return false; seen[path] = true; return true })
    if (!missing.length) return
    metadataProcess.command = ["python3", pluginDir + "/scripts/browse.py", "metadata-stream", musicRoot, JSON.stringify(missing.slice(0, 8)), searchIndexPath]
    metadataProcess.running = true
  }
  function queueTitle(path) {
    var info = trackInfo[path] || {}
    var base = rootDirectory || String(musicRoot).replace(/^~/, String(Quickshell.env("HOME")))
    var relative = String(path).indexOf(base.replace(/\/$/, "") + "/") === 0
      ? String(path).slice(base.replace(/\/$/, "").length + 1) : ""
    var parts = relative.split("/")
    var who = info.artist || (parts.length >= 3 ? parts[0] : "")
    return (info.title || titleFor(path)) + (who ? "  ·  " + who : "")
  }
  Process {
    id: metadataProcess
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        if (root.metadataIgnore) return
        try {
          var result = JSON.parse(String(line))
          root.trackInfo = Object.assign({}, root.trackInfo, result.metadata || {})
        } catch (e) {}
      }
    }
    onExited: function(code) {
      if (root.metadataIgnore) {
        root.metadataIgnore = false
        metadataDelay.restart()
        return
      }
      root.saveState()
      if (code === 0) metadataDelay.restart()
    }
  }

  property string playbackError: ""
  property bool switching: false
  property bool stopRequested: false
  property bool ipcReady: false
  property int ipcAttempts: 0
  property real localPlaybackStartedAt: 0
  property real queuedClaimAt: 0
  property real sentClaimAt: 0

  // Keep local audio exclusive with NTS Radio. Its endpoint ignores cast output.
  onPlayingChanged: {
    if (!playing) return
    localPlaybackStartedAt = Date.now()
    queuedClaimAt = localPlaybackStartedAt
    sendAudioClaim()
  }

  function sendAudioClaim() {
    if (pauseNts.running || queuedClaimAt <= sentClaimAt) return
    sentClaimAt = queuedClaimAt
    pauseNts.command = ["omarchy-shell", "-q", "nts-radio", "pauseLocalBefore", String(sentClaimAt)]
    pauseNts.running = true
  }

  Process {
    id: pauseNts
    running: false
    onExited: root.sendAudioClaim()
  }

  function titleFor(path) {
    if (!path) return "Nothing playing"
    var name = String(path).split("/").pop()
    return name.replace(/\.[^.]+$/, "")
  }

  function setMusicRoot(path) {
    var wanted = userMusicRoot || String(path || "~/Music").trim() || "~/Music"
    if (wanted === musicRoot) return
    search("")
    indexAttemptedRoot = ""
    indexPending = false
    indexRestart.stop()
    if (indexProcess.running) indexProcess.running = false
    if (metadataProcess.running) {
      metadataIgnore = true
      metadataProcess.running = false
    }
    trackInfo = ({})
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

  function refresh() {
    browse(directory || musicRoot)
    trackInfo = ({})
    metadataDelay.restart()
    startIndex(true)
  }

  function setSearchKind(kind) {
    if (["all", "track", "folder"].indexOf(kind) < 0 || kind === searchKind) return
    searchKind = kind
    if (searchQuery) search(searchQuery)
  }

  function startIndex(force) {
    if (!force && indexAttemptedRoot === musicRoot) return
    if (stateDirInit.running) { indexPending = true; return }
    if (indexProcess.running) {
      indexPending = true
      indexProcess.running = false
      indexRestart.restart()
      return
    }
    indexPending = false
    indexAttemptedRoot = musicRoot
    indexRoot = musicRoot
    indexBody = ""
    indexDone = 0
    indexTotal = -1
    indexing = true
    indexProcess.command = ["python3", pluginDir + "/scripts/browse.py", "index", musicRoot, searchIndexPath]
    indexProcess.running = true
  }

  function search(query) {
    searchQuery = String(query || "").trim()
    searchResults = []
    searchError = ""; searchTruncated = false; searchScanLimited = false
    searchLoading = !!searchQuery
    if (searchActive) {
      pendingSearch = searchQuery || " "
      searchProcess.running = false
      return
    }
    if (!searchQuery) return
    startIndex(false)
    searchBody = ""
    searchActive = true
    searchProcess.command = ["python3", pluginDir + "/scripts/browse.py", "search-index", musicRoot,
      JSON.stringify({query: searchQuery, kind: searchKind, cache: searchIndexPath})]
    searchProcess.running = true
  }

  function queueFolder(path, next) {
    if (!path) return
    folderRequests = folderRequests.concat([{path: String(path), next: next === true}])
    notify("Adding folder…")
    runFolderRequest()
  }

  function queueSelection(items, next) {
    if (!items.length) return
    folderRequests = folderRequests.concat([{items: items, next: next === true}])
    notify("Adding selection…")
    runFolderRequest()
  }

  function runFolderRequest() {
    if (folderRequestActive || !folderRequests.length) return
    var request = folderRequests[0]
    folderRequests = folderRequests.slice(1)
    folderRequestActive = true
    folderQueueNext = request.next
    folderQueueBody = ""
    selectionPayload = request.items ? JSON.stringify(request.items) : ""
    folderQueueProcess.command = ["python3", pluginDir + "/scripts/browse.py", request.items ? "collect-stdin" : "tracks", musicRoot, request.items ? "-" : request.path]
    folderQueueProcess.running = true
  }

  function chooseMusicRoot(path) {
    if (!String(path).trim()) return
    userMusicRoot = String(path).trim()
    setMusicRoot(userMusicRoot)
    saveState()
  }

  function togglePin(path) {
    if (!path) return
    pinnedFolders = pinnedFolders.indexOf(path) >= 0
      ? pinnedFolders.filter(function(p) { return p !== path }) : pinnedFolders.concat([path])
    saveState()
  }

  function saveMixtape(name) {
    name = String(name).trim()
    if (!name || !queue.length) return false
    if (mixtapes.some(function(t) { return t.name === name })) {
      operationError = "A mixtape with that name already exists. Choose another name."
      return false
    }
    mixtapes = mixtapes.concat([{name: name, paths: queue.slice(), created: Date.now()}])
    saveState(); notify("Mixtape saved")
    return true
  }

  function removeMixtape(index) {
    mixtapes = mixtapes.filter(function(t, i) { return i !== index })
    saveState()
  }

  function loadMixtape(index, start) {
    var tape = mixtapes[index]
    if (!tape || !tape.paths.length) return
    if (start) playAlbum(tape.paths, 0)
    else enqueueMany(tape.paths)
  }

  function checkpoint(label) {
    undoStack = undoStack.slice(-19).concat([{
      label: label, queue: queue.slice(), kinds: queueKinds.slice(), index: currentIndex,
      position: positionSec, history: history.slice()
    }])
  }

  function undoQueue() {
    if (!undoStack.length) return
    var snapshot = undoStack[undoStack.length - 1]
    undoStack = undoStack.slice(0, -1)
    var sameTrack = currentIndex >= 0 && snapshot.index >= 0 && queue[currentIndex] === snapshot.queue[snapshot.index]
    if (!sameTrack) stop()
    queueEditing()
    queueKinds = snapshot.kinds
    queue = snapshot.queue
    currentIndex = snapshot.index
    history = snapshot.history
    if (!sameTrack) {
      positionSec = snapshot.position
      durationSec = 0; trackTitle = ""; artist = ""; album = ""
      paused = true; resumePending = currentIndex >= 0
    }
    saveState(); notify("Undid " + snapshot.label)
  }

  function toggleMute() {
    if (outputSink && outputSink.audio) outputSink.audio.muted = !outputSink.audio.muted
  }

  function retryPlayback() {
    playbackError = ""
    if (currentIndex >= 0) { paused = false; startTrack() }
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

  function queuedMetadata() {
    var result = {}
    for (var i = 0; i < queue.length; i++) {
      var path = queue[i]
      if (trackInfo[path]) result[path] = trackInfo[path]
    }
    return result
  }

  function saveState() {
    if (!stateLoaded) return
    stateFile.setText(JSON.stringify({
      version: 3,
      userMusicRoot: userMusicRoot,
      recentFolders: recentFolders,
      pinnedFolders: pinnedFolders,
      mixtapes: mixtapes,
      history: history,
      queue: queue,
      queueKinds: queueKinds,
      currentIndex: currentIndex,
      positionSec: positionSec,
      directory: directory,
      trackInfo: queuedMetadata()
    }, null, 2) + "\n")
  }

  function queueKind(index) {
    return queueKinds[index] === "album" ? "album" : "queued"
  }

  function explicitInsertIndex() {
    var index = currentIndex >= 0 ? currentIndex + 1 : 0
    while (index < queue.length && queueKind(index) !== "album") index++
    return index
  }

  function insertQueued(paths, index) {
    paths = paths.filter(function(path) { return !!path }).map(String)
    if (!paths.length) return
    checkpoint("add tracks")
    var kinds = queue.map(function(path, i) { return queueKind(i) })
    queueEditing()
    queueKinds = kinds.slice(0, index).concat(paths.map(function() { return "queued" }), kinds.slice(index))
    queue = queue.slice(0, index).concat(paths, queue.slice(index))
    saveState()
  }

  function enqueue(path) {
    if (!path) return
    insertQueued([path], explicitInsertIndex())
    notify("Added to queue")
  }

  function playNext(path) {
    if (!path) return
    insertQueued([path], currentIndex >= 0 ? currentIndex + 1 : 0)
    notify("Playing next")
  }

  function playNextMany(paths) {
    if (!paths.length) return
    insertQueued(paths, currentIndex >= 0 ? currentIndex + 1 : 0)
    notify(paths.length + " tracks playing next")
  }

  function shuffleQueue() {
    if (upcomingCount < 2) return
    checkpoint("shuffle")
    var start = currentIndex >= 0 ? currentIndex + 1 : 0
    var next = queue.slice()
    // Shuffle each priority independently, keeping explicit songs first.
    var boundary = explicitInsertIndex()
    var ends = [boundary, next.length]
    for (var group = 0; group < ends.length; group++) {
      for (var i = ends[group] - 1; i > start; i--) {
        var j = start + Math.floor(Math.random() * (i - start + 1))
        var item = next[i]; next[i] = next[j]; next[j] = item
      }
      start = boundary
    }
    queueEditing()
    queue = next
    saveState()
  }

  function enqueueMany(paths) {
    if (!paths.length) return
    insertQueued(paths, explicitInsertIndex())
    notify(paths.length + " tracks added to queue")
  }

  function playTrack(path) {
    if (!path) return
    playFolder(String(path).slice(0, String(path).lastIndexOf("/")), String(path))
  }

  function playAlbum(paths, index) {
    if (currentPath) history = history.concat([currentPath]).slice(-100)
    undoStack = []
    // A new playback context replaces automatic continuation, not user requests.
    var explicit = []
    for (var i = currentIndex >= 0 ? currentIndex + 1 : 0; i < queue.length; i++) {
      if (queueKind(i) !== "album") explicit.push(queue[i])
    }
    var following = paths.slice(index + 1)
    queueEditing()
    queueKinds = ["album"].concat(explicit.map(function() { return "queued" }),
      following.map(function() { return "album" }))
    queue = [paths[index]].concat(explicit, following)
    currentIndex = -1
    playAt(0)
  }

  function playAt(index, remember) {
    if (index < 0 || index >= queue.length) return
    if (remember !== false && currentPath && index !== currentIndex) history = history.concat([currentPath]).slice(-100)
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
      "--access-references=no", "--autoload-files=no",
      "--audio-client-name=Crate", "--volume=100",
      "--input-ipc-server=" + socketPath,
      "--start=" + (resumePending ? Math.max(0, positionSec) : 0),
      "--", currentPath
    ]
    resumePending = false
    player.running = true
  }

  function play() {
    if (startAfterStop.running) return
    if (!player.running) {
      if (currentIndex >= 0) {
        paused = false
        launchTrack()
        saveState()
      } else if (queue.length) playAt(0)
    } else if (paused) {
      paused = false
      send(["set_property", "pause", false])
      saveState()
    }
  }

  function pause() {
    if (startAfterStop.running) {
      startAfterStop.stop()
      switching = false
      stopRequested = true
      paused = true
      resumePending = true
      saveState()
      return
    }
    if (!player.running || paused) return
    paused = true
    if (ipcReady) send(["set_property", "pause", true])
    else {
      // Before mpv's socket opens, stop and resume from saved position later.
      stopRequested = true
      closeIpc()
      player.running = false
      resumePending = true
    }
    saveState()
  }

  function togglePlayback() {
    if (playing) pause()
    else play()
  }

  function stop() {
    startAfterStop.stop()
    stopRequested = true
    switching = false
    paused = false
    positionSec = 0
    closeIpc()
    player.running = false
    saveState()
  }

  function next(manual) {
    if (currentIndex < 0) { if (queue.length) playAt(0); return }
    // A finished or skipped track is consumed, including the final track.
    var index = currentIndex
    history = history.concat([queue[index]]).slice(-100)
    undoStack = []
    stop()
    var remaining = queue.slice()
    var kinds = queue.map(function(path, i) { return queueKind(i) })
    kinds.splice(index, 1)
    remaining.splice(index, 1)
    queueKinds = kinds
    currentIndex = -1
    queueEditing()
    queue = remaining
    trackTitle = ""; artist = ""; album = ""
    if (index < queue.length) playAt(index)
    else { saveState() }
  }

  function previous() {
    var now = Date.now()
    if (currentPath && positionSec > 3 && now - previousPressedAt > 1500) {
      previousPressedAt = now
      seek(0)
      return
    }
    previousPressedAt = now
    if (history.length) {
      var path = history[history.length - 1]
      history = history.slice(0, -1)
      var index = Math.max(0, currentIndex)
      queueEditing()
      queueKinds = queueKinds.slice(0, index).concat(["queued"], queueKinds.slice(index))
      queue = queue.slice(0, index).concat([path], queue.slice(index))
      playAt(index, false)
    } else if (currentIndex > 0) playAt(currentIndex - 1)
    else seek(0)
  }

  function removeQueueAt(index) {
    if (index < 0 || index >= queue.length) return
    checkpoint("remove track")
    var wasCurrent = index === currentIndex
    var next = queue.slice()
    var kinds = queue.map(function(path, i) { return queueKind(i) })
    kinds.splice(index, 1)
    next.splice(index, 1)
    queueKinds = kinds
    queueEditing()
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
    checkpoint("reorder")
    var next = queue.slice()
    var item = next.splice(index, 1)[0]
    next.splice(target, 0, item)
    var kinds = queue.map(function(path, i) { return queueKind(i) })
    var kind = kinds.splice(index, 1)[0]
    kinds.splice(target, 0, kind)
    var playingIndex = currentIndex
    if (playingIndex === index) playingIndex = target
    else if (index < playingIndex && target >= playingIndex) playingIndex--
    else if (index > playingIndex && target <= playingIndex) playingIndex++
    // Manual ordering makes the chosen prefix explicit, preserving that order.
    if (index !== currentIndex) kinds[target] = "queued"
    var lastExplicit = -1
    for (var i = playingIndex + 1; i < kinds.length; i++) {
      if (kinds[i] !== "album") lastExplicit = i
    }
    for (var j = playingIndex + 1; j <= lastExplicit; j++) kinds[j] = "queued"
    queueKinds = kinds
    queueEditing()
    queue = next
    currentIndex = playingIndex
    saveState()
  }

  function clearQueue() {
    if (!queue.length) return
    checkpoint("clear queue")
    if (currentIndex >= 0 && currentIndex < queue.length) {
      queueEditing()
      queueKinds = [queueKind(currentIndex)]
      queue = [queue[currentIndex]]
      currentIndex = 0
    } else {
      queueEditing()
      queueKinds = []
      queue = []
      currentIndex = -1
    }
    saveState()
  }

  function seek(seconds) {
    if (!ipcReady) return
    var wanted = Math.max(0, Math.min(Number(seconds) || 0, durationSec || Infinity))
    positionSec = wanted
    send(["seek", wanted, "absolute"])
  }

  function setVolume(value) {
    if (!outputSink || !outputSink.audio) return
    var wanted = Math.max(0, Math.min(100, Math.round(Number(value) || 0)))
    outputSink.audio.volume = wanted / 100
    if (wanted > 0) outputSink.audio.muted = false
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
    onExited: {
      stateFile.reload()
      if (root.indexPending) root.startIndex(true)
    }
  }

  Process {
    id: indexProcess
    running: false
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        try {
          var message = JSON.parse(String(line))
          if (message.progress) {
            root.indexDone = Number(message.progress.done) || 0
            root.indexTotal = Number(message.progress.total) || 0
          } else root.indexBody = String(line)
        } catch (e) {}
      }
    }
    onExited: function(code) {
      if (root.indexPending) {
        Qt.callLater(function() { root.startIndex(true) })
        return
      }
      root.indexing = false
      try {
        var result = JSON.parse(root.indexBody)
        if (result.error) root.operationWarning = String(result.error)
        else if (result.scanLimited) root.operationWarning = "Only the first 100,000 library entries were indexed."
      } catch (e) { if (code !== 0) root.operationWarning = "Could not refresh the search index" }
      if (code === 0) {
        if (metadataProcess.running) {
          root.metadataIgnore = true
          metadataProcess.running = false
        }
        root.trackInfo = ({})
        metadataDelay.restart()
      }
      if (root.searchQuery) root.search(root.searchQuery)
    }
  }
  Timer {
    id: indexRestart
    interval: 150
    onTriggered: if (root.indexPending && !indexProcess.running) root.startIndex(true)
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
        root.userMusicRoot = typeof saved.userMusicRoot === "string" ? saved.userMusicRoot : ""
        if (root.userMusicRoot) root.setMusicRoot(root.userMusicRoot)
        root.recentFolders = Array.isArray(saved.recentFolders) ? saved.recentFolders.filter(function(p) { return typeof p === "string" }).slice(0, 8) : []
        root.pinnedFolders = Array.isArray(saved.pinnedFolders) ? saved.pinnedFolders.filter(function(p) { return typeof p === "string" }) : []
        root.history = Array.isArray(saved.history) ? saved.history.filter(function(p) { return typeof p === "string" }).slice(-100) : []
        root.mixtapes = Array.isArray(saved.mixtapes) ? saved.mixtapes.filter(function(t) {
          return t && typeof t.name === "string" && Array.isArray(t.paths) && t.paths.every(function(p) { return typeof p === "string" })
        }) : []
        root.queueEditing()
        root.queue = Array.isArray(saved.queue) ? saved.queue.filter(function(p) { return typeof p === "string" }) : []
        root.queueKinds = root.queue.map(function(path, i) {
          return Array.isArray(saved.queueKinds) && saved.queueKinds[i] === "album" ? "album" : "queued"
        })
        root.currentIndex = Number.isInteger(saved.currentIndex) && saved.currentIndex >= 0
          && saved.currentIndex < root.queue.length ? saved.currentIndex : -1
        root.positionSec = Math.max(0, Number(saved.positionSec) || 0)
        root.resumePending = root.currentIndex >= 0 && root.positionSec > 0
        root.trackInfo = saved.trackInfo && typeof saved.trackInfo === "object" ? saved.trackInfo : ({})
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
          root.recentFolders = [root.directory].concat(root.recentFolders.filter(function(p) { return p !== root.directory })).slice(0, 8)
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
      root.searchActive = false
      if (root.pendingSearch) {
        root.pendingSearch = ""
        Qt.callLater(function() { if (!root.searchActive) root.search(root.searchQuery) })
        return
      }
      root.searchLoading = false
      try {
        var result = JSON.parse(root.searchBody)
        root.searchResults = Array.isArray(result.entries) ? result.entries : []
        root.searchTruncated = result.truncated === true
        root.searchScanLimited = result.scanLimited === true
        root.searchIndexed = result.indexed === true
        root.searchError = String(result.error || "")
      } catch (e) { root.searchResults = []; root.searchError = "Search failed" }
    }
  }

  Process {
    id: folderQueueProcess
    running: false
    stdinEnabled: true
    onStarted: if (root.selectionPayload) write(root.selectionPayload + "\n")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.folderQueueBody = String(text || "")
    }
    onExited: {
      try {
        var result = JSON.parse(root.folderQueueBody)
        if (result.error) root.operationError = String(result.error)
        else {
          var paths = result.entries.map(function(entry) { return entry.path })
          if (root.folderQueueNext) root.playNextMany(paths)
          else root.enqueueMany(paths)
          if (!paths.length) root.operationError = "No playable tracks in this folder"
          if (result.truncated) root.operationWarning = "Only the first 5,000 tracks were added. Add smaller subfolders to include the rest."
        }
      } catch (e) { root.operationError = "Could not queue this folder" }
      root.folderRequestActive = false
      Qt.callLater(root.runFolderRequest)
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
          if (result.error) root.operationError = String(result.error)
          else {
            var paths = result.entries.map(function(entry) { return entry.path })
            if (!paths.length) root.operationError = "No playable tracks in this folder"
            else {
              var index = root.albumStartTrack ? paths.indexOf(root.albumStartTrack) : 0
              if (index < 0) root.operationError = "Selected track is no longer in this folder"
              else {
                root.playAlbum(paths, index)
                if (result.truncated) root.operationWarning = "Album continuation includes only the first 5,000 tracks. Open a smaller subfolder for the rest."
              }
            }
          }
        } catch (e) { root.operationError = "Could not play this folder" }
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
    function play(): void { root.play() }
    function pause(): void { root.pause() }
    function pauseBefore(stamp: string): void {
      // A same-millisecond tie goes to Crate.
      if (Number(stamp) > root.localPlaybackStartedAt) root.pause()
    }
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
