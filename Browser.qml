import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
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
  property string pendingFolderSelection: ""
  property bool helpOpen: false
  readonly property bool dialogOpen: helpOpen || folderSettings.visible || saveTapeDialog.visible || placesDialog.visible || deleteTapeDialog.visible
  property var pagePositions: ({})
  property var selectedPaths: []
  property int selectionAnchor: 0
  function rememberPosition() {
    var positions = Object.assign({}, pagePositions)
    positions[page] = {cursor: cursor, offset: page === "files" ? fileList.contentY : queueList.contentY}
    pagePositions = positions
  }
  function restorePosition() {
    var saved = pagePositions[page] || {cursor: 0, offset: 0}
    cursor = saved.cursor
    Qt.callLater(function() {
      var list = page === "files" ? fileList : queueList
      list.contentY = Math.max(list.originY, Math.min(saved.offset, list.originY + Math.max(0, list.contentHeight - list.height)))
    })
  }
  function toggleSelection(index, range) {
    if (range) {
      var paths = selectedPaths.slice()
      for (var i = Math.min(index, selectionAnchor); i <= Math.max(index, selectionAnchor); i++) {
        if (visibleEntries[i] && paths.indexOf(visibleEntries[i].path) < 0) paths.push(visibleEntries[i].path)
      }
      selectedPaths = paths
    } else {
      var path = visibleEntries[index].path
      selectedPaths = selectedPaths.indexOf(path) >= 0 ? selectedPaths.filter(function(p) { return p !== path }) : selectedPaths.concat([path])
      selectionAnchor = index
    }
    cursor = index
  }
  function queueSelection(next) {
    if (!service) return
    var selected = visibleEntries.filter(function(e) { return selectedPaths.indexOf(e.path) >= 0 })
    if (selected.length) { service.queueSelection(selected, next); selectedPaths = [] }
    else queueSelected(next)
  }
  function metadataViewport() {
    if (!service || page !== "queue" || !opened) return
    var first = Math.max(0, queueList.indexAt(1, queueList.contentY))
    service.visibleMetadataPaths = service.queue.slice(first, first + Math.ceil(queueList.height / 46) + 1)
  }
  readonly property bool searching: searchInput.text.trim() !== ""
  readonly property var visibleEntries: service
    ? (searching ? (service.searchQuery === searchInput.text.trim() ? service.searchResults : []) : (service.directoryLoading ? [] : service.entries)) : []
  readonly property var breadcrumbs: buildBreadcrumbs()

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "sjfortin.crate"
  readonly property color ink: Color.foreground
  readonly property color paper: Color.background
  readonly property color dimInk: Util.alpha(ink, 0.58)
  readonly property color ruleColor: Util.alpha(ink, 0.2)

  function formatTime(seconds) {
    var total = Math.max(0, Math.floor(Number(seconds) || 0))
    var minutes = Math.floor(total / 60)
    var paddedSeconds = ("0" + (total % 60)).slice(-2)
    if (minutes >= 60)
      return Math.floor(minutes / 60) + ":" + ("0" + (minutes % 60)).slice(-2) + ":" + paddedSeconds
    return minutes + ":" + paddedSeconds
  }

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
    if (!opened || !window.visible || dialogOpen) return
    if (typeof window.requestActivate === "function") window.requestActivate()
    keyCatcher.forceActiveFocus()
  }

  function openDirectory(path) {
    if (!service) return
    pendingFolderSelection = ""
    selectedPaths = []
    searchDelay.stop()
    searchInput.text = ""
    service.search("")
    service.browse(path)
    cursor = 0
    Qt.callLater(root.restoreKeyboardFocus)
  }

  function goParent() {
    if (!service || page !== "files") return false
    if (searching) {
      searchDelay.stop()
      searchInput.text = ""
      service.search("")
      cursor = 0
      return true
    }
    if (!service.parentDirectory) return false
    var child = service.directory
    openDirectory(service.parentDirectory)
    pendingFolderSelection = child
    return true
  }

  function openSelectedFolder() {
    if (!service || page !== "files") return false
    var entry = visibleEntries[cursor]
    if (!entry || entry.kind !== "folder") return false
    openDirectory(entry.path)
    return true
  }

  function open(payloadJson) {
    closingFromHost = false
    opened = true
    helpOpen = false
    restorePosition()
    window.visible = true
    if (payloadJson) {
      try {
        var payload = JSON.parse(String(payloadJson))
        if (["files", "queue", "mixtapes"].indexOf(payload.page) !== -1)
          navigate(payload.page)
      } catch (e) {}
    }
    if (service && !service.directory && !service.directoryLoading) service.browse("")
    focusTimer.restart()
  }

  function close() {
    rememberPosition()
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
    rememberPosition()
    page = target
    restorePosition()
    keyCatcher.forceActiveFocus()
    metadataViewport()
  }

  function selectionLength() {
    if (!service) return 0
    if (page === "files") return visibleEntries.length
    return page === "queue" ? service.queue.length : 0
  }

  function selectedPath() {
    if (!service || cursor < 0) return ""
    if (page === "files") {
      var entry = visibleEntries[cursor]
      return entry && entry.kind === "track" ? entry.path : ""
    }
    return page === "queue" ? service.queue[cursor] || "" : ""
  }

  function activateCursor() {
    if (!service) return
    if (page === "files") {
      var entry = visibleEntries[cursor]
      if (!entry) return
      if (entry.kind === "folder") openDirectory(entry.path)
      else service.playTrack(entry.path)
    } else if (page === "queue") service.playAt(cursor)
  }

  function moveCursor(delta) {
    cursor = Math.max(0, Math.min(selectionLength() - 1, cursor + delta))
    if (page === "files" && fileList.count) fileList.positionViewAtIndex(cursor, ListView.Contain)
    if (page === "queue" && queueList.count) queueList.positionViewAtIndex(cursor, ListView.Contain)
  }

  function entryInitial(index) {
    var entry = visibleEntries[index]
    var name = entry ? String(entry.name || "").trim() : ""
    return name ? name.charAt(0).toUpperCase() : "#"
  }

  function jumpLetter(delta) {
    if (page !== "files" || !visibleEntries.length) return
    var selected = Math.max(0, Math.min(cursor, visibleEntries.length - 1))
    var initial = entryInitial(selected)
    var target = selected
    if (delta > 0) {
      for (var next = selected + 1; next < visibleEntries.length; next++) {
        if (entryInitial(next) !== initial) { target = next; break }
      }
    } else {
      while (target > 0 && entryInitial(target - 1) === initial) target--
      if (target === selected && target > 0) {
        initial = entryInitial(target - 1)
        target--
        while (target > 0 && entryInitial(target - 1) === initial) target--
      }
    }
    cursor = target
    if (fileList.count) fileList.positionViewAtIndex(cursor, ListView.Contain)
  }

  function moveQueueSelection(delta) {
    if (!service || page !== "queue" || cursor < 0) return
    var target = cursor + delta
    if (target < 0 || target >= service.queue.length) return
    service.moveQueue(cursor, delta)
    cursor = target
    if (queueList.count) queueList.positionViewAtIndex(cursor, ListView.Contain)
  }

  function removeQueueSelection(index) {
    if (!service || page !== "queue") return
    if (index !== undefined) cursor = index
    if (cursor < 0 || cursor >= service.queue.length) return
    service.removeQueueAt(cursor)
    cursor = Math.max(0, Math.min(cursor, service.queue.length - 1))
  }

  function queueSelected(next) {
    if (!service || cursor < 0) return
    if (page === "files") {
      var entry = visibleEntries[cursor]
      if (!entry) return
      if (entry.kind === "folder") service.queueFolder(entry.path, next)
      else if (next) service.playNext(entry.path)
      else service.enqueue(entry.path)
    } else if (page === "queue" && selectedPath()) {
      if (next) service.playNext(selectedPath())
      else service.enqueue(selectedPath())
    }
  }

  Timer {
    id: focusTimer
    interval: 80
    onTriggered: root.restoreKeyboardFocus()
  }

  onHelpOpenChanged: if (helpOpen) helpDialog.open(); else helpDialog.close()

  Connections {
    target: root.service
    function onQueueEditing() { queueList.savedOffset = queueList.contentY }
    function onQueueChanged() {
      var offset = queueList.savedOffset
      if (root.page === "queue") root.cursor = Math.max(0, Math.min(root.cursor, root.service.queue.length - 1))
      Qt.callLater(function() {
        queueList.contentY = Math.max(queueList.originY,
          Math.min(offset, queueList.originY + Math.max(0, queueList.contentHeight - queueList.height)))
        queueList.savedOffset = queueList.contentY
      })
    }
    function onEntriesChanged() {
      if (!root.pendingFolderSelection || !root.service) return
      var wanted = root.pendingFolderSelection
      root.pendingFolderSelection = ""
      for (var i = 0; i < root.service.entries.length; i++) {
        if (root.service.entries[i].path === wanted) {
          root.cursor = i
          Qt.callLater(function() {
            if (fileList.count > i) fileList.positionViewAtIndex(i, ListView.Contain)
          })
          break
        }
      }
    }
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
      if (visible) { if (root.opened) focusTimer.restart(); return }
      if (!root.closingFromHost && root.opened) root.requestClose()
    }

    FocusScope {
      id: keyScope
      anchors.fill: parent
      focus: true
      Item {
        id: keyCatcher
        objectName: "crateKeys"
        focus: true
        Keys.onPressed: function(event) {
          if (root.dialogOpen) return
          if (event.key === Qt.Key_Escape) {
            if (root.selectedPaths.length) root.selectedPaths = []
            else if (!root.goParent()) root.requestClose()
          } else if (event.key === Qt.Key_Z && event.modifiers & Qt.ControlModifier) {
            if (root.service) root.service.undoQueue()
          } else if (event.key === Qt.Key_A && event.modifiers & Qt.ControlModifier && root.page === "files") {
            root.selectedPaths = root.visibleEntries.map(function(e) { return e.path })
          } else if (event.text === "?" || event.key === Qt.Key_Question) root.helpOpen = true
          else if (root.page === "queue" && ((event.key === Qt.Key_J && event.modifiers & Qt.ShiftModifier) || (event.key === Qt.Key_Down && event.modifiers & Qt.ControlModifier))) root.moveQueueSelection(1)
          else if (root.page === "queue" && ((event.key === Qt.Key_K && event.modifiers & Qt.ShiftModifier) || (event.key === Qt.Key_Up && event.modifiers & Qt.ControlModifier))) root.moveQueueSelection(-1)
          else if (root.page === "files" && event.key === Qt.Key_J && event.modifiers & Qt.ShiftModifier) root.jumpLetter(1)
          else if (root.page === "files" && event.key === Qt.Key_K && event.modifiers & Qt.ShiftModifier) root.jumpLetter(-1)
          else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) root.moveCursor(1)
          else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) root.moveCursor(-1)
          else if ((event.key === Qt.Key_Left || event.key === Qt.Key_H || event.key === Qt.Key_Backspace) && root.page === "files") root.goParent()
          else if ((event.key === Qt.Key_Right || event.key === Qt.Key_L) && root.page === "files") root.openSelectedFolder()
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.activateCursor()
          else if (event.key === Qt.Key_Space && root.service) root.service.togglePlayback()
          else if (event.key === Qt.Key_Q) root.queueSelection((event.modifiers & Qt.ShiftModifier) !== 0)
          else if (event.key === Qt.Key_Slash) { root.navigate("files"); searchInput.forceActiveFocus() }
          else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && root.page === "queue") root.removeQueueSelection()
          else if (event.key === Qt.Key_1) root.navigate("files")
          else if (event.key === Qt.Key_2) root.navigate("queue")
          else if (event.key === Qt.Key_3) root.navigate("mixtapes")
          else return
          event.accepted = true
        }
      }
      Shortcut { sequence: "Ctrl+Z"; enabled: !root.dialogOpen && root.opened; onActivated: if (root.service) root.service.undoQueue() }
      ColumnLayout {
        anchors.fill: parent
        spacing: 0
        RowLayout {
          Layout.fillWidth: true
          Layout.margins: 14
          spacing: 10
          CrateMark { Layout.preferredWidth: 22; Layout.preferredHeight: 22; ink: root.ink; paper: root.paper }
          Label { text: "CRATE"; color: root.ink; font.bold: true; font.pixelSize: Style.font.subtitle }
          Item { Layout.fillWidth: true }
          Action { label: "FOLDERS"; hint: "Recent and pinned folders"; onActivated: placesDialog.open() }
          Action { label: "SETTINGS"; onActivated: { folderPath.text = root.service ? root.service.musicRoot : "~/Music"; folderSettings.open() } }
          Action { label: "?"; hint: "Keyboard shortcuts"; onActivated: root.helpOpen = true }
          Action { label: "CLOSE"; onActivated: root.requestClose() }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: root.ruleColor }
        RowLayout {
          Layout.fillWidth: true
          Layout.margins: 12
          spacing: 8
          Repeater {
            model: [{key:"files", label:"1  DIG"}, {key:"queue", label:"2  QUEUE"}, {key:"mixtapes", label:"3  MIXTAPES"}]
            Action { required property var modelData; label: modelData.label; strong: root.page === modelData.key; onActivated: root.navigate(modelData.key) }
          }
          Item { Layout.fillWidth: true }
          Label { text: root.service ? root.service.upcomingCount + " UP NEXT" : ""; color: root.dimInk; font.pixelSize: Style.font.caption }
          Action { label: "UNDO"; enabled: !!root.service && root.service.canUndo; hint: "Undo queue edit · Ctrl+Z"; onActivated: root.service.undoQueue() }
        }
        // Persistent errors stay separate from short confirmations.
        Rectangle {
          Layout.fillWidth: true
          Layout.leftMargin: 14; Layout.rightMargin: 14
          implicitHeight: errorRow.implicitHeight + 16
          visible: !!root.service && !!(root.service.playbackError || root.service.operationError || root.service.operationWarning)
          color: Util.alpha(root.ink, 0.09)
          RowLayout {
            id: errorRow
            anchors.fill: parent; anchors.margins: 8
            Label { Layout.fillWidth: true; text: root.service ? (root.service.playbackError || root.service.operationError || root.service.operationWarning) : ""; color: root.ink; wrapMode: Text.Wrap; textFormat: Text.PlainText }
            Action { label: "RETRY"; visible: !!root.service && !!root.service.playbackError && !!root.service.currentPath; onActivated: root.service.retryPlayback() }
            Action { label: "SKIP"; visible: !!root.service && !!root.service.playbackError && !!root.service.currentPath; onActivated: { root.service.playbackError = ""; root.service.next(true) } }
            Action { label: "×"; hint: "Dismiss message"; onActivated: { root.service.playbackError = ""; root.service.operationError = ""; root.service.operationWarning = "" } }
          }
        }
        StackLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.margins: 14
          currentIndex: root.page === "files" ? 0 : root.page === "queue" ? 1 : 2
          ColumnLayout {
            spacing: 10
            RowLayout {
              Layout.fillWidth: true
              Action { label: "↑"; hint: "Parent folder"; enabled: !!root.service && (!!root.service.parentDirectory || root.searching); onActivated: root.goParent() }
              Flickable {
                Layout.fillWidth: true; Layout.preferredHeight: 32
                contentWidth: crumbs.width; clip: true; flickableDirection: Flickable.HorizontalFlick
                Row {
                  id: crumbs; spacing: 2
                  Repeater {
                    model: root.breadcrumbs
                    Action { required property var modelData; label: modelData.label + " /"; hint: modelData.path; onActivated: root.openDirectory(modelData.path) }
                  }
                }
              }
              Action { label: root.service && root.service.pinnedFolders.indexOf(root.service.directory) >= 0 ? "UNPIN" : "PIN"; enabled: !!root.service && !!root.service.directory; hint: "Pin this folder"; onActivated: root.service.togglePin(root.service.directory) }
              Action { label: "REFRESH"; onActivated: if (root.service) { if (root.searching) { root.service.startIndex(true); root.service.search(searchInput.text) } else root.service.refresh() } }
            }
            RowLayout {
              Layout.fillWidth: true
              TextField {
                id: searchInput
                objectName: "crateSearch"
                Layout.fillWidth: true
                placeholderText: "Search titles, artists, albums, and folders  /"
                color: root.ink; placeholderTextColor: root.dimInk
                selectByMouse: true
                background: Rectangle { color: Util.alpha(root.ink, 0.04); border.color: searchInput.activeFocus ? root.ink : root.ruleColor }
                onTextChanged: { root.cursor = 0; root.selectedPaths = []; searchDelay.restart() }
                Keys.onEscapePressed: { text = ""; searchDelay.stop(); if (root.service) root.service.search(""); root.restoreKeyboardFocus() }
                Keys.onDownPressed: { root.cursor = 0; root.restoreKeyboardFocus() }
                onAccepted: { if (!searchDelay.running && root.service && !root.service.searchLoading) root.activateCursor(); root.restoreKeyboardFocus() }
                Keys.onTabPressed: root.restoreKeyboardFocus()
              }
              Action { label: "×"; visible: root.searching; hint: "Clear search"; onActivated: { searchInput.text = ""; root.restoreKeyboardFocus() } }
            }
            Timer { id: searchDelay; interval: 200; onTriggered: if (root.service) root.service.search(searchInput.text) }
            RowLayout {
              Layout.fillWidth: true
              visible: root.searching
              spacing: 6
              Action { label: "ALL"; strong: !!root.service && root.service.searchKind === "all"; onActivated: root.service.setSearchKind("all") }
              Action { label: "TRACKS"; strong: !!root.service && root.service.searchKind === "track"; onActivated: root.service.setSearchKind("track") }
              Action { label: "FOLDERS"; strong: !!root.service && root.service.searchKind === "folder"; onActivated: root.service.setSearchKind("folder") }
              Item { Layout.fillWidth: true }
              Label { text: root.service && root.service.indexing ? (root.service.indexTotal >= 0 ? "Indexing tags " + root.service.indexDone + "/" + root.service.indexTotal : "Scanning library…") : ""; color: root.dimInk; font.pixelSize: Style.font.caption }
            }
            Label {
              Layout.fillWidth: true
              visible: !!text
              wrapMode: Text.Wrap
              text: !root.service ? "" : root.searching
                ? (root.service.searchError || ((searchDelay.running || root.service.searchLoading) ? "Searching…" : root.service.searchScanLimited ? "Search stopped at 100,000 entries; some folders were not searched." : root.service.searchTruncated ? "Showing the best 100 matches. Refine your search." : root.visibleEntries.length + (root.visibleEntries.length === 1 ? " match" : " matches")))
                : (root.service.directoryError || (root.service.directoryLoading ? "Opening folder…" : root.service.truncated ? "Showing the first 5,000 items. Open a smaller folder." : ""))
              color: root.dimInk; font.pixelSize: Style.font.bodySmall; textFormat: Text.PlainText
            }
            ListView {
              id: fileList
              objectName: "crateFiles"
              Layout.fillWidth: true; Layout.fillHeight: true
              clip: true; spacing: 2
              model: root.visibleEntries
              ScrollBar.vertical: ScrollBar {}
              delegate: Rectangle {
                id: fileRow
                required property var modelData
                required property int index
                width: fileList.width; height: root.searching ? 62 : 46
                color: root.selectedPaths.indexOf(modelData.path) >= 0 ? Util.alpha(root.ink, 0.16) : root.cursor === index ? Util.alpha(root.ink, 0.09) : "transparent"
                RowLayout {
                  anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 12
                  spacing: 6
                  Action {
                    label: root.selectedPaths.indexOf(fileRow.modelData.path) >= 0 ? "✓" : "□"
                    hint: "Select " + fileRow.modelData.name
                    onActivated: root.toggleSelection(fileRow.index, false)
                  }
                  Item {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Column {
                      anchors.verticalCenter: parent.verticalCenter; width: parent.width
                      Label { width: parent.width; text: (fileRow.modelData.kind === "folder" ? "▸  " : "") + (fileRow.modelData.title || fileRow.modelData.name); color: root.ink; elide: Text.ElideRight; textFormat: Text.PlainText; font.pixelSize: Style.font.body }
                      Label { visible: root.searching; width: parent.width; text: (fileRow.modelData.artist ? fileRow.modelData.artist + "  ·  " : "") + (fileRow.modelData.album ? fileRow.modelData.album + "  ·  " : "") + (fileRow.modelData.relative || ""); color: root.dimInk; elide: Text.ElideMiddle; textFormat: Text.PlainText; font.pixelSize: Style.font.caption }
                    }
                    MouseArea {
                      id: rowMouse
                      anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                      onClicked: function(mouse) {
                        if (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) root.toggleSelection(fileRow.index, !!(mouse.modifiers & Qt.ShiftModifier))
                        else {
                          root.cursor = fileRow.index
                          if (fileRow.modelData.kind === "folder") root.openDirectory(fileRow.modelData.path)
                          else root.service.playTrack(fileRow.modelData.path)
                        }
                        root.restoreKeyboardFocus()
                      }
                    }
                    ToolTip.visible: rowMouse.containsMouse
                    ToolTip.delay: 700
                    ToolTip.text: fileRow.modelData.name + "\n" + fileRow.modelData.path
                  }
                  Action {
                    label: "+ QUEUE"
                    onActivated: { if (fileRow.modelData.kind === "folder") root.service.queueFolder(fileRow.modelData.path); else root.service.enqueue(fileRow.modelData.path) }
                  }
                  Action { label: "⋯"; hint: "More actions for " + fileRow.modelData.name; onActivated: fileMenu.popup() }
                }
                Menu {
                  popupType: Popup.Item
                  id: fileMenu
                  MenuItem { text: "Play next"; onTriggered: { if (fileRow.modelData.kind === "folder") root.service.queueFolder(fileRow.modelData.path, true); else root.service.playNext(fileRow.modelData.path) } }
                  MenuItem { text: fileRow.modelData.kind === "folder" ? "Play folder · replace album continuation" : "Play now"; onTriggered: { if (fileRow.modelData.kind === "folder") root.service.playFolder(fileRow.modelData.path); else root.service.playTrack(fileRow.modelData.path) } }
                  MenuItem { text: "Open folder"; visible: fileRow.modelData.kind === "folder"; height: visible ? implicitHeight : 0; onTriggered: root.openDirectory(fileRow.modelData.path) }
                  MenuItem { text: "Select"; onTriggered: root.toggleSelection(fileRow.index, false) }
                }
              }
              Column {
                anchors.centerIn: parent; width: Math.min(parent.width, 430); spacing: 14
                visible: fileList.count === 0 && !!root.service && !root.service.directoryLoading && !root.service.searchLoading && !searchDelay.running
                Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; color: root.ink; text: root.searching ? "No matches. Try a filename, artist folder, or album folder." : root.service && root.service.directoryError ? "Choose a music folder to start digging." : "No audio files here. Try another folder." }
                Action { anchors.horizontalCenter: parent.horizontalCenter; label: root.searching ? "CLEAR SEARCH" : "CHOOSE MUSIC FOLDER"; onActivated: { if (root.searching) searchInput.text = ""; else { folderPath.text = root.service.musicRoot; folderSettings.open() } } }
              }
            }
            RowLayout {
              Layout.fillWidth: true
              Label { text: root.selectedPaths.length ? root.selectedPaths.length + " SELECTED" : root.visibleEntries.length + (root.visibleEntries.length === 1 ? " ITEM" : " ITEMS"); color: root.dimInk; font.pixelSize: Style.font.caption }
              Item { Layout.fillWidth: true }
              Label { visible: !!root.service && root.service.addingFolders; text: "Adding…"; color: root.dimInk }
              Action { label: "CLEAR SELECTION"; visible: root.selectedPaths.length > 0; onActivated: root.selectedPaths = [] }
              Action { label: root.selectedPaths.length ? "QUEUE SELECTED" : "QUEUE FOLDER"; visible: root.selectedPaths.length > 0 || !root.searching; enabled: !!root.service && !root.service.directoryLoading; onActivated: { if (root.selectedPaths.length) root.queueSelection(false); else root.service.queueFolder(root.service.directory || root.service.musicRoot) } }
              Action { label: "NEXT"; visible: root.selectedPaths.length > 0; onActivated: root.queueSelection(true) }
            }
          }
          ColumnLayout {
            RowLayout {
              Layout.fillWidth: true
              Label { Layout.fillWidth: true; text: root.service ? root.service.upcomingCount + " UP NEXT" : ""; color: root.ink; font.bold: true }
              Action { label: "SAVE MIXTAPE"; enabled: !!root.service && root.service.queue.length > 0; onActivated: { tapeName.text = ""; saveTapeDialog.open() } }
              Action { label: "SHUFFLE"; enabled: !!root.service && root.service.upcomingCount > 1; onActivated: root.service.shuffleQueue() }
              Action { label: "CLEAR OTHERS"; enabled: !!root.service && root.service.queue.length > (root.service.currentIndex >= 0 ? 1 : 0); onActivated: root.service.clearQueue() }
            }
            ListView {
              id: queueList
              objectName: "crateQueue"
              property real savedOffset: 0
              Layout.fillWidth: true; Layout.fillHeight: true
              clip: true; spacing: 1
              model: root.service ? root.service.queue : []
              onContentYChanged: root.metadataViewport()
              onCountChanged: root.metadataViewport()
              ScrollBar.vertical: ScrollBar {}
              delegate: Rectangle {
                id: queueRow
                required property string modelData
                required property int index
                width: queueList.width; height: 46
                color: root.service && root.service.currentIndex === index ? Util.alpha(root.ink, 0.14) : root.cursor === index ? Util.alpha(root.ink, 0.07) : "transparent"
                RowLayout {
                  anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 12; spacing: 4
                  Item {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Column {
                      anchors.verticalCenter: parent.verticalCenter; width: parent.width
                      Label { width: parent.width; color: root.ink; font.pixelSize: Style.font.bodySmall; textFormat: Text.PlainText; elide: Text.ElideRight; text: root.service ? root.service.queueTitle(queueRow.modelData) : "" }
                      Label { color: root.dimInk; font.pixelSize: Style.font.caption; text: root.service && root.service.currentIndex === queueRow.index ? (root.service.playing ? "NOW PLAYING" : "PAUSED") : root.service && queueRow.index < root.service.currentIndex ? "EARLIER IN QUEUE" : root.service && root.service.queueKind(queueRow.index) === "album" ? "ALBUM CONTINUATION" : "QUEUED" }
                    }
                    MouseArea { id: queueMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.cursor = queueRow.index; root.service.playAt(queueRow.index); root.restoreKeyboardFocus() } }
                    ToolTip.visible: queueMouse.containsMouse; ToolTip.delay: 700; ToolTip.text: root.service ? root.service.queueTitle(queueRow.modelData) + "\n" + queueRow.modelData : ""
                  }
                  Action { label: "↑"; hint: "Move track up"; enabled: queueRow.index > 0; onActivated: root.service.moveQueue(queueRow.index, -1) }
                  Action { label: "↓"; hint: "Move track down"; enabled: !!root.service && queueRow.index < root.service.queue.length - 1; onActivated: root.service.moveQueue(queueRow.index, 1) }
                  Action { objectName: "removeQueue" + queueRow.index; label: "×"; hint: "Remove track"; onActivated: root.removeQueueSelection(queueRow.index) }
                }
              }
              Column {
                anchors.centerIn: parent; spacing: 14; visible: queueList.count === 0
                Label { text: "Your queue is empty."; color: root.ink }
                Action { label: "BROWSE MUSIC"; onActivated: root.navigate("files") }
              }
            }
          }
          ColumnLayout {
            Label { text: "MIXTAPES"; color: root.ink; font.bold: true }
            Label { Layout.fillWidth: true; text: "Save a queue to listen again. Mixtapes reference your original music files."; color: root.dimInk; wrapMode: Text.Wrap }
            ListView {
              Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 8
              model: root.service ? root.service.mixtapes : []
              ScrollBar.vertical: ScrollBar {}
              delegate: RowLayout {
                required property var modelData
                required property int index
                width: ListView.view.width - 12
                Label { Layout.fillWidth: true; text: modelData.name + " · " + modelData.paths.length + " tracks"; color: root.ink; textFormat: Text.PlainText; elide: Text.ElideRight }
                Action { label: "+ QUEUE"; onActivated: root.service.loadMixtape(index, false) }
                Action { label: "PLAY"; onActivated: root.service.loadMixtape(index, true) }
                Action { label: "DELETE"; onActivated: { deleteTapeDialog.tapeIndex = index; deleteTapeDialog.open() } }
              }
              Label { anchors.centerIn: parent; visible: !root.service || !root.service.mixtapes.length; text: "Build a queue, then choose Save Mixtape."; color: root.dimInk }
            }
          }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: root.ruleColor }
        ColumnLayout {
          Layout.fillWidth: true; Layout.margins: 12; spacing: 3
          Label { Layout.fillWidth: true; text: root.service ? root.service.displayTitle : "Nothing playing"; textFormat: Text.PlainText; elide: Text.ElideRight; color: root.ink; font.bold: true; font.pixelSize: Style.font.bodySmall }
          RowLayout {
            Layout.fillWidth: true; spacing: 6
            Action { label: "|◀"; hint: "Previous track / restart"; enabled: !!root.service && (!!root.service.currentPath || root.service.history.length > 0); onActivated: root.service.previous() }
            Action { label: root.service && root.service.playing ? "PAUSE" : "PLAY"; strong: true; enabled: !!root.service && root.service.queue.length > 0; onActivated: root.service.togglePlayback() }
            Action { label: "▶|"; hint: "Next track"; enabled: !!root.service && root.service.queue.length > 0; onActivated: root.service.next(true) }
            Item { Layout.fillWidth: true }
            Label { text: "System volume"; color: root.dimInk; font.pixelSize: Style.font.caption }
            Action { label: root.service && root.service.muted ? "UNMUTE" : "MUTE"; hint: "Affects all apps on the default output"; onActivated: if (root.service) root.service.toggleMute() }
            Action { label: "−"; hint: "Lower system volume"; onActivated: if (root.service) root.service.setVolume(root.service.volume - 5) }
            Label { text: root.service ? root.service.volume + "%" : ""; color: root.ink; font.pixelSize: Style.font.caption }
            Action { label: "+"; hint: "Raise system volume"; onActivated: if (root.service) root.service.setVolume(root.service.volume + 5) }
          }
          Slider {
            id: seekSlider
            objectName: "crateSeek"
            Layout.fillWidth: true; Layout.preferredHeight: 24
            from: 0; to: root.service && root.service.durationSec > 0 ? root.service.durationSec : 1
            value: root.service ? root.service.positionSec : 0
            enabled: !!root.service && root.service.durationSec > 0
            Accessible.name: "Playback position"
            stepSize: 1
            onMoved: if (root.service) root.service.seek(value)
            background: Rectangle { x: seekSlider.leftPadding; y: (seekSlider.height - height) / 2; width: seekSlider.availableWidth; height: 3; color: root.ruleColor; Rectangle { width: parent.width * seekSlider.visualPosition; height: parent.height; color: root.ink } }
            handle: Rectangle { x: seekSlider.leftPadding + seekSlider.visualPosition * (seekSlider.availableWidth - width); y: (seekSlider.height - height) / 2; width: 10; height: 10; radius: 5; color: root.ink; visible: seekSlider.hovered || seekSlider.pressed || seekSlider.activeFocus }
            HoverHandler { id: seekHover }
            ToolTip.visible: seekHover.hovered && seekSlider.enabled
            ToolTip.text: root.formatTime(Math.max(0, Math.min(1, (seekHover.point.position.x - seekSlider.leftPadding) / seekSlider.availableWidth)) * seekSlider.to)
          }
          RowLayout {
            Layout.fillWidth: true
            Label { Layout.fillWidth: true; text: root.service && root.service.notice ? root.service.notice : "SPACE Play/pause · / Search · Q Queue · ? Help"; color: root.dimInk; elide: Text.ElideRight; font.pixelSize: Style.font.caption; Accessible.role: Accessible.StaticText }
            Label { text: root.service && root.service.currentPath ? root.formatTime(root.service.positionSec) + " / " + (root.service.durationSec > 0 ? root.formatTime(root.service.durationSec) : "--:--") : ""; color: root.ink; font.pixelSize: Style.font.caption }
          }
        }
      }
      Dialog {
        popupType: Popup.Item
        id: folderSettings
        objectName: "crateFolderSettings"
        title: "Music folder"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 540)
        modal: true; standardButtons: Dialog.Save | Dialog.Cancel
        onOpened: folderPath.forceActiveFocus()
        onAccepted: { if (root.service) { root.service.chooseMusicRoot(folderPath.text); searchInput.text = ""; root.selectedPaths = [] } root.restoreKeyboardFocus() }
        onRejected: root.restoreKeyboardFocus()
        ColumnLayout {
          anchors.fill: parent
          Label { Layout.fillWidth: true; text: "Choose the top folder containing your music."; wrapMode: Text.Wrap }
          TextField { id: folderPath; Layout.fillWidth: true; selectByMouse: true; Accessible.name: "Music folder path"; onAccepted: folderSettings.accept() }
          Action { label: "BROWSE…"; onActivated: folderPicker.open() }
        }
      }
      FolderDialog { id: folderPicker; title: "Choose music folder"; onAccepted: folderPath.text = decodeURIComponent(String(selectedFolder).replace(/^file:\/\//, "")) }
      Dialog {
        popupType: Popup.Item
        id: saveTapeDialog
        title: "Save queue as mixtape"
        anchors.centerIn: parent; width: Math.min(parent.width - 40, 440)
        modal: true
        onOpened: tapeName.forceActiveFocus()
        onClosed: root.restoreKeyboardFocus()
        ColumnLayout {
          anchors.fill: parent
          TextField { id: tapeName; Layout.fillWidth: true; placeholderText: "Mixtape name"; Accessible.name: "Mixtape name"; maximumLength: 100; onAccepted: saveTapeButton.activated() }
          Label { Layout.fillWidth: true; visible: !!root.service && root.service.mixtapes.some(function(t) { return t.name === tapeName.text.trim() }); text: "That name already exists. Choose another name."; wrapMode: Text.Wrap }
          RowLayout {
            Action { id: saveTapeButton; label: "SAVE"; enabled: !!tapeName.text.trim() && !!root.service && !root.service.mixtapes.some(function(t) { return t.name === tapeName.text.trim() }); onActivated: if (enabled && root.service.saveMixtape(tapeName.text)) saveTapeDialog.close() }
            Action { label: "CANCEL"; onActivated: saveTapeDialog.close() }
          }
        }
      }
      Dialog {
        popupType: Popup.Item
        id: deleteTapeDialog
        property int tapeIndex: -1
        title: "Delete mixtape?"
        anchors.centerIn: parent; modal: true; standardButtons: Dialog.Yes | Dialog.No
        Label { text: "Only the saved list will be removed." }
        onAccepted: root.service.removeMixtape(tapeIndex)
        onClosed: root.restoreKeyboardFocus()
      }
      Dialog {
        popupType: Popup.Item
        id: placesDialog
        objectName: "cratePlaces"
        title: "Folders"
        anchors.centerIn: parent; width: Math.min(parent.width - 40, 620); height: Math.min(parent.height - 40, 500)
        modal: true; standardButtons: Dialog.Close
        onClosed: root.restoreKeyboardFocus()
        ScrollView {
          anchors.fill: parent; contentWidth: availableWidth
          ColumnLayout {
            width: parent.width
            Label { text: "PINNED"; font.bold: true }
            Label { visible: !root.service || !root.service.pinnedFolders.length; text: "Use Pin while browsing to keep a folder here." }
            Repeater {
              model: root.service ? root.service.pinnedFolders : []
              Action { required property string modelData; Layout.fillWidth: true; label: modelData; hint: modelData; onActivated: { placesDialog.close(); root.navigate("files"); root.openDirectory(modelData) } }
            }
            Label { text: "RECENT"; font.bold: true }
            Repeater {
              model: root.service ? root.service.recentFolders : []
              Action { required property string modelData; Layout.fillWidth: true; label: modelData; hint: modelData; onActivated: { placesDialog.close(); root.navigate("files"); root.openDirectory(modelData) } }
            }
          }
        }
      }
      Dialog {
        popupType: Popup.Item
        id: helpDialog
        objectName: "crateHelp"
        title: "Keyboard shortcuts"
        anchors.centerIn: parent; width: Math.min(parent.width - 40, 540); height: Math.min(parent.height - 40, 520)
        modal: true; standardButtons: Dialog.Close
        onClosed: { root.helpOpen = false; root.restoreKeyboardFocus() }
        ScrollView {
          anchors.fill: parent
          Label { text: "↑ / ↓ or J / K   Move selection\nShift+J / K   Jump letter in Dig\n← / H   Parent folder\n→ / L   Open folder\nEnter   Open folder / play track\nEsc   Clear selection / search / parent / close\n/   Search filenames and folders\nQ / Shift+Q   Queue / play next\nCtrl+click   Select multiple items\nShift+click   Select a range\nCtrl+A   Select all visible results\n1 / 2 / 3   Dig / Queue / Mixtapes\nSpace   Play / pause\nShift+J/K or Ctrl+↓/↑   Reorder queue\nDelete / Backspace   Remove queue item\nCtrl+Z   Undo queue edit\nTab / Shift+Tab   Focus controls\nArrow keys on seek slider   Seek"; lineHeight: 1.5 }
        }
      }
    }
  }
  component Action: Button {
    id: action
    property string label: ""
    property string hint: ""
    property bool strong: false
    signal activated()
    text: label
    implicitWidth: Math.max(30, caption.implicitWidth + 18)
    implicitHeight: 32
    focusPolicy: Qt.StrongFocus
    Accessible.name: hint || label
    Keys.priority: Keys.AfterItem
    Keys.forwardTo: [keyCatcher]
    onClicked: activated()
    ToolTip.visible: hovered && hint !== ""
    ToolTip.delay: 600
    ToolTip.text: hint
    contentItem: Text { id: caption; text: action.label; textFormat: Text.PlainText; color: action.strong ? root.paper : root.ink; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideMiddle; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }
    background: Rectangle { color: action.strong ? root.ink : action.hovered ? Util.alpha(root.ink, 0.1) : "transparent"; border.width: action.activeFocus ? 2 : 1; border.color: action.activeFocus ? root.ink : root.ruleColor; opacity: action.enabled ? 1 : 0.4 }
    opacity: enabled ? 1 : 0.45
  }
}
