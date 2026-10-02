import QtQuick
import Quickshell
import "Crate" as Crate
ShellRoot {
  Crate.Service { id: realService }
  QtObject {
    id: mock
    signal queueEditing()
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
    function browse(path) {}
    function search(query) { searchQuery = query }
    function queueTitle(path) { return path + " · Artist" }
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
      browser.close()
      Qt.quit()
    }
  }
}
