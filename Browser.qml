import QtQuick
import Quickshell
import qs.Commons

// Dig through folders or search, build a queue, then return to work.
Item {
  id: root
  property var shell: null
  property var service: null
  property var manifest: null
  property bool opened: false
  property bool closingFromHost: false
  property string page: "files"
  property int cursor: 0
  property bool helpOpen: false
  readonly property bool searching: searchInput.text.trim() !== ""
  readonly property var visibleEntries: service
    ? (searching ? service.searchResults : (service.directoryLoading ? [] : service.entries)) : []
  readonly property var breadcrumbs: buildBreadcrumbs()

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "sjfortin.crate"
  readonly property color ink: Color.foreground
  readonly property color paper: Color.background
  readonly property color dimInk: Util.alpha(ink, 0.58)
  readonly property color ruleColor: Util.alpha(ink, 0.2)

  function buildBreadcrumbs() {
    if (!service) return []
    var base = String(service.rootDirectory || "")
    var current = String(service.directory || "")
    var configured = String(service.musicRoot || "~/Music").split("/").filter(function(part) { return part !== "" })
    var label = configured.length ? configured[configured.length - 1] : "/"
    var items = [{ label: label, path: base }]
    if (!base || !current || (current !== base && current.indexOf(base.replace(/\/$/, "") + "/") !== 0))
      return items
    var relative = current.slice(base.length).replace(/^\/+/, "")
    if (!relative) return items
    var path = base.replace(/\/$/, "")
    var parts = relative.split("/")
    for (var i = 0; i < parts.length; i++) {
      path += "/" + parts[i]
      items.push({ label: parts[i], path: path })
    }
    return items
  }

  function restoreKeyboardFocus() {
    if (!opened || !window.visible) return
    if (typeof window.requestActivate === "function") window.requestActivate()
    keyCatcher.forceActiveFocus()
  }

  function openDirectory(path) {
    if (!service) return
    searchDelay.stop()
    searchInput.text = ""
    service.search("")
    service.browse(path)
    cursor = 0
    Qt.callLater(root.restoreKeyboardFocus)
  }

  function open(payloadJson) {
    closingFromHost = false
    opened = true
    helpOpen = false
    cursor = 0
    searchDelay.stop()
    searchInput.text = ""
    if (service) service.search("")
    window.visible = true
    if (payloadJson) {
      try {
        var payload = JSON.parse(String(payloadJson))
        if (["files", "queue"].indexOf(payload.page) !== -1)
          page = payload.page
      } catch (e) {}
    }
    if (service && !service.directory && !service.directoryLoading) service.browse("")
    focusTimer.restart()
  }

  function close() {
    closingFromHost = true
    opened = false
    window.visible = false
    focusTimer.stop()
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function navigate(target) {
    page = target
    cursor = 0
    keyCatcher.forceActiveFocus()
  }

  function selectionLength() {
    if (!service) return 0
    if (page === "files") return visibleEntries.length
    return service.queue.length
  }

  function selectedPath() {
    if (!service || cursor < 0) return ""
    if (page === "files") {
      var entry = visibleEntries[cursor]
      return entry && entry.kind === "track" ? entry.path : ""
    }
    return service.queue[cursor] || ""
  }

  function activateCursor() {
    if (!service) return
    if (page === "files") {
      var entry = visibleEntries[cursor]
      if (!entry) return
      if (entry.kind === "folder") openDirectory(entry.path)
      else playTrackAlbum(entry.path)
    } else service.playAt(cursor)
  }

  function playTrackAlbum(path) {
    if (!service || !path) return
    var folder = String(path).slice(0, String(path).lastIndexOf("/"))
    service.playFolder(folder, path)
  }

  function moveCursor(delta) {
    cursor = Math.max(0, Math.min(selectionLength() - 1, cursor + delta))
    if (page === "files" && fileList.count) fileList.positionViewAtIndex(cursor, ListView.Contain)
    if (page === "queue" && queueList.count) queueList.positionViewAtIndex(cursor, ListView.Contain)
  }

  function queueSelected(next) {
    if (!service || cursor < 0) return
    if (page === "files") {
      var entry = visibleEntries[cursor]
      if (!entry) return
      if (entry.kind === "folder") service.queueFolder(entry.path, next)
      else if (next) service.playNext(entry.path)
      else service.enqueue(entry.path)
    } else if (selectedPath()) {
      if (next) service.playNext(selectedPath())
      else service.enqueue(selectedPath())
    }
  }

  Timer {
    id: focusTimer
    interval: 80
    onTriggered: root.restoreKeyboardFocus()
  }

  FloatingWindow {
    id: window
    title: "Crate"
    visible: false
    color: root.paper
    implicitWidth: 1040
    implicitHeight: 710
    minimumSize: Qt.size(680, 480)

    onVisibleChanged: {
      if (visible) {
        if (root.opened) focusTimer.restart()
        return
      }
      if (root.closingFromHost) return
      root.opened = false
      if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    }

    FocusScope {
      id: keyScope
      anchors.fill: parent
      focus: true

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
        if (root.helpOpen) {
          root.helpOpen = false
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Escape) {
          if (root.page === "files" && root.searching) {
            searchInput.text = ""
            if (root.service) root.service.search("")
          }
          else if (root.page === "files" && root.service && root.service.parentDirectory)
            root.openDirectory(root.service.parentDirectory)
          else root.requestClose()
          root.cursor = 0
          event.accepted = true
          return
        }
        if (event.text === "?" || event.key === Qt.Key_Question
            || (event.key === Qt.Key_Slash && event.modifiers & Qt.ShiftModifier)) {
          root.helpOpen = true
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Down || event.key === Qt.Key_J) root.moveCursor(1)
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) root.moveCursor(-1)
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.activateCursor()
        else if (event.key === Qt.Key_Backspace && root.page === "files" && root.service)
          { root.openDirectory(root.service.parentDirectory) }
        else if (event.key === Qt.Key_Space && root.service) root.service.togglePlayback()
        else if (event.key === Qt.Key_Q) root.queueSelected((event.modifiers & Qt.ShiftModifier) !== 0)
        else if (event.key === Qt.Key_Slash && !(event.modifiers & Qt.ShiftModifier))
          { root.navigate("files"); searchInput.forceActiveFocus() }
        else if (event.key === Qt.Key_Delete && root.page === "queue" && root.service)
          root.service.removeQueueAt(root.cursor)
        else if (event.key === Qt.Key_1) root.navigate("files")
        else if (event.key === Qt.Key_2) root.navigate("queue")
        else return
        event.accepted = true
        }
      }

      Column {
        anchors.fill: parent
        spacing: 0

        Item {
          width: parent.width
          height: Style.space(58)

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(20)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(12)

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(10)
              height: width
              color: root.service && root.service.playing ? root.ink : "transparent"
              border.width: 1
              border.color: root.ink
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "CRATE"
              color: root.ink
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
              font.letterSpacing: 1.2
            }
          }

          Action {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            label: "CLOSE"
            onActivated: root.requestClose()
          }
        }

        Rectangle { width: parent.width; height: 1; color: root.ruleColor }

        Row {
          width: parent.width
          height: parent.height - Style.space(58) - Style.space(92) - 2
          spacing: 0

          Item {
            width: Style.space(180)
            height: parent.height

            Rectangle { anchors.fill: parent; color: Util.alpha(root.ink, 0.035) }

            Column {
              anchors.fill: parent
              anchors.margins: Style.space(14)
              spacing: Style.space(5)

              Repeater {
                model: [
                  { key: "files", label: "01  DIG" },
                  { key: "queue", label: "02  QUEUE" }
                ]
                delegate: Rectangle {
                  required property var modelData
                  width: parent.width
                  height: Style.space(37)
                  color: root.page === modelData.key ? Util.alpha(root.ink, 0.12)
                    : (navHover.hovered ? Util.alpha(root.ink, 0.06) : "transparent")
                  Rectangle {
                    width: 3
                    height: parent.height
                    color: root.page === modelData.key ? root.ink : "transparent"
                  }
                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(11)
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData.label
                    color: root.ink
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: root.page === parent.modelData.key
                  }
                  HoverHandler { id: navHover }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.navigate(parent.modelData.key)
                  }
                }
              }

              Item { width: 1; height: Style.space(18) }
              Text {
                width: parent.width
                text: root.service ? root.service.queue.length + " IN QUEUE" : ""
                color: root.dimInk
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(14)
              text: "LOCAL FILES ONLY\n?  KEYBOARD"
              color: root.dimInk
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              lineHeight: 1.6
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.helpOpen = true
              }
            }
          }

          Rectangle { width: 1; height: parent.height; color: root.ruleColor }

          Item {
            id: content
            width: parent.width - Style.space(181)
            height: parent.height

            Column {
              anchors.fill: parent
              anchors.margins: Style.space(20)
              spacing: Style.space(12)
              visible: root.page === "files"

              Row {
                width: parent.width
                height: Style.space(30)
                spacing: Style.space(8)
                Action {
                  label: "← UP"
                  enabled: root.service && root.service.parentDirectory !== ""
                  onActivated: root.openDirectory(root.service.parentDirectory)
                }
                Flickable {
                  id: breadcrumbStrip
                  width: Math.max(100, parent.width - Style.space(250))
                  height: parent.height
                  contentWidth: breadcrumbTrail.implicitWidth
                  contentHeight: height
                  flickableDirection: Flickable.HorizontalFlick
                  boundsBehavior: Flickable.StopAtBounds
                  clip: true
                  onContentWidthChanged: Qt.callLater(function() {
                    breadcrumbStrip.contentX = Math.max(0, breadcrumbStrip.contentWidth - breadcrumbStrip.width)
                  })

                  Row {
                    id: breadcrumbTrail
                    height: breadcrumbStrip.height
                    spacing: Style.space(5)
                    Repeater {
                      model: root.breadcrumbs
                      delegate: Row {
                        id: crumb
                        required property var modelData
                        required property int index
                        height: breadcrumbTrail.height
                        spacing: Style.space(5)
                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: crumb.modelData.label
                          textFormat: Text.PlainText
                          color: crumbHover.hovered ? root.ink : root.dimInk
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.bold: crumb.index === root.breadcrumbs.length - 1
                          HoverHandler { id: crumbHover }
                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openDirectory(crumb.modelData.path)
                          }
                        }
                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          visible: crumb.index < root.breadcrumbs.length - 1
                          text: "/"
                          color: root.dimInk
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                        }
                      }
                    }
                  }
                }
                Action { label: "REFRESH"; onActivated: if (root.service) root.service.refresh() }
              }

              Rectangle { width: parent.width; height: 1; color: root.ruleColor }

              Rectangle {
                width: parent.width
                height: Style.space(34)
                color: Util.alpha(root.ink, 0.05)
                border.width: 1
                border.color: root.ruleColor
                TextInput {
                  id: searchInput
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  verticalAlignment: TextInput.AlignVCenter
                  color: root.ink
                  selectionColor: root.ink
                  selectedTextColor: root.paper
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  clip: true
                  Text {
                    visible: !searchInput.text
                    text: "Search your collection  /"
                    color: root.dimInk
                    font: searchInput.font
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  onTextChanged: { root.cursor = 0; searchDelay.restart() }
                  Keys.priority: Keys.BeforeItem
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                      text = ""; if (root.service) root.service.search("")
                      root.restoreKeyboardFocus(); event.accepted = true
                    } else if (event.text === "?" || event.key === Qt.Key_Question
                               || (event.key === Qt.Key_Slash && event.modifiers & Qt.ShiftModifier)) {
                      root.helpOpen = true; root.restoreKeyboardFocus(); event.accepted = true
                    } else if (event.key === Qt.Key_1 || event.key === Qt.Key_2) {
                      root.navigate(event.key === Qt.Key_1 ? "files" : "queue")
                      event.accepted = true
                    } else if (event.key === Qt.Key_Down) {
                      root.restoreKeyboardFocus(); root.moveCursor(1); event.accepted = true
                    } else if (event.key === Qt.Key_Up) {
                      root.restoreKeyboardFocus(); root.moveCursor(-1); event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                      root.activateCursor(); root.restoreKeyboardFocus(); event.accepted = true
                    } else if (event.key === Qt.Key_Tab) {
                      root.restoreKeyboardFocus(); event.accepted = true
                    }
                  }
                }
                Timer {
                  id: searchDelay
                  interval: 200
                  onTriggered: if (root.service) root.service.search(searchInput.text)
                }
              }

              Text {
                visible: root.service && (root.searching
                  ? (root.service.searchLoading || root.service.searchError || root.service.searchTruncated)
                  : (root.service.directoryLoading || root.service.directoryError || root.service.truncated))
                width: parent.width
                text: root.service ? (root.searching
                  ? (root.service.searchError || (root.service.searchLoading ? "Searching…"
                    : "Showing first 100 matches"))
                  : (root.service.directoryError || (root.service.directoryLoading ? "Opening folder…"
                    : "Showing first 5,000 items"))) : ""
                color: root.dimInk
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              ListView {
                id: fileList
                width: parent.width
                height: parent.height - Style.space(145)
                clip: true
                spacing: 1
                model: root.visibleEntries
                delegate: Rectangle {
                  id: fileRow
                  required property var modelData
                  required property int index
                  width: fileList.width
                  height: Style.space(42)
                  color: root.cursor === index ? Util.alpha(root.ink, 0.1)
                    : (fileHover.hovered ? Util.alpha(root.ink, 0.055) : "transparent")

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(12)
                    anchors.right: fileActions.left
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: (fileRow.modelData.kind === "folder" ? "▸  " : "   ")
                      + (root.searching ? fileRow.modelData.relative : fileRow.modelData.name)
                    textFormat: Text.PlainText
                    color: root.ink
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Row {
                    id: fileActions
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(5)
                    Action {
                      label: "+ QUEUE"
                      onActivated: {
                        if (fileRow.modelData.kind === "folder") root.service.queueFolder(fileRow.modelData.path)
                        else root.service.enqueue(fileRow.modelData.path)
                      }
                    }
                    Action {
                      label: "NEXT"
                      onActivated: {
                        if (fileRow.modelData.kind === "folder") root.service.queueFolder(fileRow.modelData.path, true)
                        else root.service.playNext(fileRow.modelData.path)
                      }
                    }
                    Action {
                      label: "PLAY"
                      visible: fileRow.modelData.kind === "folder"
                      onActivated: root.service.playFolder(fileRow.modelData.path)
                    }
                    Action {
                      label: "OPEN"
                      visible: fileRow.modelData.kind === "folder"
                      onActivated: root.openDirectory(fileRow.modelData.path)
                    }
                  }

                  HoverHandler { id: fileHover }
                  MouseArea {
                    anchors.left: parent.left
                    anchors.right: fileActions.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.cursor = fileRow.index
                      if (fileRow.modelData.kind === "folder") {
                        root.openDirectory(fileRow.modelData.path)
                      } else root.playTrackAlbum(fileRow.modelData.path)
                      root.restoreKeyboardFocus()
                    }
                  }
                }
              }

              Row {
                spacing: Style.space(10)
                Text {
                  text: root.service ? root.visibleEntries.length + " ITEMS" : ""
                  color: root.dimInk
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
                Action {
                  label: "QUEUE THIS FOLDER"
                  onActivated: {
                    if (!root.service) return
                    root.service.queueFolder(root.service.directory || root.service.musicRoot)
                  }
                }
              }
            }

            Column {
              anchors.fill: parent
              anchors.margins: Style.space(20)
              spacing: Style.space(12)
              visible: root.page === "queue"

              Row {
                width: parent.width
                height: Style.space(30)
                spacing: Style.space(6)
                Text {
                  width: Math.max(80, parent.width - Style.space(270))
                  anchors.verticalCenter: parent.verticalCenter
                  text: "UP NEXT  /  " + (root.service ? root.service.queue.length : 0)
                  color: root.ink
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Action { label: "SHUFFLE"; onActivated: if (root.service) root.service.shuffleQueue() }
                Action {
                  label: root.service ? "REPEAT " + root.service.repeatMode.toUpperCase() : "REPEAT OFF"
                  onActivated: if (root.service) root.service.cycleRepeat()
                }
                Action { label: "CLEAR"; onActivated: if (root.service) root.service.clearQueue() }
              }
              Rectangle { width: parent.width; height: 1; color: root.ruleColor }
              ListView {
                id: queueList
                width: parent.width
                height: parent.height - Style.space(50)
                clip: true
                model: root.service ? root.service.queue : []
                delegate: Rectangle {
                  id: queueRow
                  required property string modelData
                  required property int index
                  width: queueList.width
                  height: Style.space(42)
                  color: root.service && root.service.currentIndex === index ? Util.alpha(root.ink, 0.14)
                    : (root.cursor === index ? Util.alpha(root.ink, 0.07) : "transparent")
                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(8)
                    anchors.right: queueActions.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: (queueRow.index + 1) + "   " + (root.service ? root.service.titleFor(queueRow.modelData) : "")
                    textFormat: Text.PlainText
                    color: root.ink
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }
                  Row {
                    id: queueActions
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(3)
                    Action { label: "↑"; onActivated: root.service.moveQueue(queueRow.index, -1) }
                    Action { label: "↓"; onActivated: root.service.moveQueue(queueRow.index, 1) }
                    Action { label: "×"; onActivated: root.service.removeQueueAt(queueRow.index) }
                  }
                  MouseArea {
                    anchors.left: parent.left
                    anchors.right: queueActions.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.cursor = queueRow.index; root.service.playAt(queueRow.index) }
                  }
                }
              }
            }
          }
        }

        Rectangle { width: parent.width; height: 1; color: root.ruleColor }

        Item {
          width: parent.width
          height: Style.space(92)

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(18)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(18)
            anchors.top: parent.top
            anchors.topMargin: Style.space(12)
            height: Style.space(32)
            spacing: Style.space(8)

            Action { label: "←"; onActivated: if (root.service) root.service.previous() }
            Action {
              label: root.service && root.service.playing ? "PAUSE" : "PLAY"
              strong: true
              onActivated: if (root.service) root.service.togglePlayback()
            }
            Action { label: "→"; onActivated: if (root.service) root.service.next(true) }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(120, parent.width - Style.space(340))
              text: root.service ? root.service.displayTitle : ""
              textFormat: Text.PlainText
              color: root.ink
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              elide: Text.ElideRight
            }
            Action { label: "−"; onActivated: if (root.service) root.service.setVolume(root.service.volume - 5) }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.service ? root.service.volume + "%" : ""
              color: root.dimInk
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            Action { label: "+"; onActivated: if (root.service) root.service.setVolume(root.service.volume + 5) }
          }

          Rectangle {
            id: progress
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(18)
            anchors.rightMargin: Style.space(18)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(23)
            height: Style.space(3)
            color: Util.alpha(root.ink, 0.18)
            Rectangle {
              height: parent.height
              width: root.service && root.service.durationSec > 0
                ? parent.width * Math.min(1, root.service.positionSec / root.service.durationSec) : 0
              color: root.ink
            }
            MouseArea {
              anchors.fill: parent
              enabled: root.service && root.service.durationSec > 0
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) { root.service.seek(mouse.x / width * root.service.durationSec) }
            }
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(18)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(5)
            text: root.service && root.service.playbackError ? root.service.playbackError
              : "SPACE PLAY/PAUSE  ·  / SEARCH  ·  Q QUEUE  ·  SHIFT+Q NEXT  ·  ? HELP"
            color: root.dimInk
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      Rectangle {
        anchors.fill: parent
        visible: root.helpOpen
        color: Util.alpha(root.paper, 0.9)
        MouseArea { anchors.fill: parent; onClicked: root.helpOpen = false }
        Rectangle {
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(60), Style.space(440))
          height: Style.space(260)
          color: root.paper
          border.width: 1
          border.color: root.ink
          Text {
            anchors.fill: parent
            anchors.margins: Style.space(20)
            text: "KEYBOARD\n\n↑ / ↓ or J / K   Move\nENTER   Open or play\nBACKSPACE / ESC   Parent / close\n/   Search\nQ   Queue track or folder\nSHIFT+Q   Play track next\n1 / 2   Dig / Queue\nSPACE   Play or pause\nDELETE   Remove queue item"
            color: root.ink
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            lineHeight: 1.35
          }
        }
      }
    }
  }

  component Action: Rectangle {
    id: action
    property string label: ""
    property bool strong: false
    signal activated()
    implicitWidth: caption.implicitWidth + Style.space(18)
    implicitHeight: Style.space(28)
    color: !enabled ? Util.alpha(root.ink, 0.02)
      : (strong ? root.ink : (hover.hovered ? Util.alpha(root.ink, 0.11) : "transparent"))
    border.width: strong ? 0 : 1
    border.color: Util.alpha(root.ink, enabled ? 0.3 : 0.12)
    opacity: enabled ? 1 : 0.45
    Text {
      id: caption
      anchors.centerIn: parent
      text: action.label
      color: action.strong ? root.paper : root.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    HoverHandler { id: hover }
    MouseArea {
      anchors.fill: parent
      enabled: action.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: { action.activated(); Qt.callLater(root.restoreKeyboardFocus) }
    }
  }
}
