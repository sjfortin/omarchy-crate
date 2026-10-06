import QtQuick
import Quickshell
import "Crate" as Crate
ShellRoot {
  Crate.Service { id: realService }
  QtObject {
    id: mock
    signal queueEditing()
    property var history: []
    property var mixtapes: []
    property var recentFolders: []
    property var pinnedFolders: []
    property var visibleMetadataPaths: []
    property bool canUndo: false
    property bool addingFolders: false
    property bool searchScanLimited: false
    property bool indexing: false
    property int indexDone: 0
    property int indexTotal: -1
    property bool searchIndexed: false
    property string searchKind: "all"
    property string operationError: ""
    property string operationWarning: ""
    readonly property int upcomingCount: Math.max(0, queue.length - (currentIndex >= 0 ? currentIndex + 1 : 0))
    property var queue: []
    property int currentIndex: -1
    property bool playing: false
    property var entries: []
    property bool directoryLoading: false
    property string directory: ""
    property string rootDirectory: ""
    property string musicRoot: "~/Music"
    property string parentDirectory: ""
    property string searchQuery: ""
    property var searchResults: []
    property bool searchLoading: false
    property bool searchTruncated: false
    property string searchError: ""
    property bool truncated: false
    property string directoryError: ""
    property string displayTitle: "Test"
    property bool muted: false
    property int volume: 50
    property real positionSec: 0
    property real durationSec: 0
    property string currentPath: ""
    property string notice: ""
    property string playbackError: ""
    property string queueTitleOverride: ""
    function browse(path) {}
    function search(query) { searchQuery = query }
    function setSearchKind(kind) { searchKind = kind }
    function startIndex(force) {}
    function queueKind(index) { return "queued" }
    function queueTitle(path) { return queueTitleOverride || path + " · Artist" }
    function removeQueueAt(index) { queueEditing(); var next = queue.slice(); next.splice(index, 1); queue = next }
  }
  Crate.Browser { id: browser; service: mock }
  Timer {
    interval: 500; running: true
    onTriggered: {
      if (!realService.stateLoaded) throw new Error("State not loaded")
      realService.queue = ["/missing.mp3"]
      realService.currentIndex = 0
      realService.next(false)
      if (realService.queue.length !== 0 || realService.currentIndex !== -1) throw new Error("Final track not consumed")
      console.log("PASS final track consumption; system volume=" + realService.volume)
      var tracks = []
      for (var i = 0; i < 100; i++) tracks.push("Track " + i)
      mock.queueTitleOverride = '<img src="https://attacker.example/pixel">'
      mock.queue = tracks
      browser.open('{"page":"queue"}')
      phase2.start()
    }
  }
  property var list: null
  function find(item, name) {
    if (item.objectName === name) return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) { var match = find(children[i], name); if (match) return match }
    var data = item.data || []
    for (var j = 0; j < data.length; j++) { if (data[j] && data[j].objectName === name) return data[j]; if (data[j] && data[j].contentItem) { var result = find(data[j].contentItem, name); if (result) return result } }
    return null
  }
  Timer {
    id: phase2; interval: 200
    onTriggered: {
      list = find(browser, "crateQueue")
      if (!list) throw new Error("Queue list missing")
      var tip = find(list, "crateQueueTip0")
      if (!tip || tip.contentItem.textFormat !== Text.PlainText || tip.contentItem.text.indexOf("<img") !== 0)
        throw new Error("Queue tooltip must render untrusted tags as plain text")
      console.log("PASS queue tooltip renders metadata as plain text")
      list.contentY = 1500
      phase3.start()
    }
  }
  Timer {
    id: phase3; interval: 200
    onTriggered: {
      var action = find(list, "removeQueue40")
      if (!action) throw new Error("Mouse removal action missing")
      action.activated()
      phase4.start()
    }
  }
  Timer {
    id: phase4; interval: 200
    onTriggered: {
      if (mock.queue.length !== 99 || list.contentY !== 1500 || browser.cursor !== 40) throw new Error("Mouse viewport reset: " + list.contentY)
      browser.cursor = 41
      browser.removeQueueSelection()
      phase5.start()
    }
  }
  Timer {
    id: phase5; interval: 200
    onTriggered: {
      if (mock.queue.length !== 98 || list.contentY !== 1500 || browser.cursor !== 41) throw new Error("Keyboard viewport reset: " + list.contentY)
      console.log("PASS mouse action and keyboard removal preserve viewport and selection")
      browser.helpOpen = true
      var help = find(browser, "crateHelp")
      if (!help || !help.visible || help.height > 710) throw new Error("Shortcut dialog failed")
      browser.helpOpen = false
      browser.navigate("files")
      browser.cursor = 8
      mock.queue = mock.queue.slice(0, 2)
      if (browser.cursor !== 8) throw new Error("Queue edit changed Dig selection")
      mock.entries = [{name:"one", path:"/one", kind:"track"}, {name:"two",path:"/two",kind:"track"}, {name:"three",path:"/three",kind:"track"}]
      browser.toggleSelection(0, false)
      browser.toggleSelection(2, true)
      if (browser.selectedPaths.length !== 3) throw new Error("Range selection failed")
      browser.cursor = 2
      browser.navigate("queue")
      browser.navigate("files")
      if (browser.cursor !== 2) throw new Error("Page selection lost")
      browser.close()
      realService.chooseMusicRoot(String(Quickshell.env("CRATE_TEST_MUSIC")))
      realService.queueFolder(realService.musicRoot + "/one")
      realService.queueFolder(realService.musicRoot + "/two")
      realService.queueFolder(realService.musicRoot + "/three")
      realService.search("one")
      realService.search("two")
      realService.search("three")
      phase6.start()
    }
  }
  Timer {
    id: phase6; interval: 100; repeat: true
    property int attempts: 0
    onTriggered: {
      if (++attempts > 80) throw new Error("Async pipeline timed out")
      if (realService.addingFolders || realService.searchLoading || realService.directoryLoading || realService.indexing || !realService.searchIndexed) return
      if (realService.queue.length !== 3 || !realService.queue[0].endsWith("one.mp3") || !realService.queue[1].endsWith("two.mp3") || !realService.queue[2].endsWith("three.mp3")) throw new Error("Folder request lost or reordered")
      if (realService.searchQuery !== "three" || !realService.searchResults.some(function(e) { return e.name === "three.mp3" })) throw new Error("Stale search results")
      realService.togglePin(realService.musicRoot)
      if (!realService.saveMixtape("Test tape") || realService.mixtapes[0].paths.length !== 3) throw new Error("Mixtape failed")
      realService.clearQueue()
      realService.undoQueue()
      if (realService.queue.length !== 3) throw new Error("Undo failed")
      console.log("PASS folder pipeline, latest search, and persistence")
      Qt.quit()
    }
  }
}
