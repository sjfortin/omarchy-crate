import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "sjfortin.crate"

  property var service: null
  readonly property color ink: bar ? bar.barForeground : Color.foreground
  readonly property color paper: bar ? bar.background : Color.background

  function resolveService() {
    if (service || !bar || !bar.shell) return
    var found = null
    if (typeof bar.shell.serviceFor === "function") found = bar.shell.serviceFor(moduleName)
    if (!found && typeof bar.shell.ensureService === "function") found = bar.shell.ensureService(moduleName)
    if (found) {
      service = found
      syncSettings()
    }
  }

  function syncSettings() {
    if (service) service.setMusicRoot(root.setting("musicDirectory", "~/Music"))
  }

  onBarChanged: resolveService()
  onSettingsChanged: syncSettings()
  Component.onCompleted: resolveService()

  Timer {
    interval: 500
    repeat: true
    running: root.service === null
    onTriggered: root.resolveService()
  }

  implicitWidth: vertical ? barSize : content.implicitWidth + Style.space(16)
  implicitHeight: vertical ? verticalContent.implicitHeight + Style.space(12) : barSize

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    onClicked: function(mouse) {
      if (!root.service) return
      if (mouse.button === Qt.MiddleButton) root.service.togglePlayback()
      else root.service.openBrowser("files")
    }
    onWheel: function(wheel) {
      if (root.service) root.service.setVolume(root.service.volume + (wheel.angleDelta.y > 0 ? 5 : -5))
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.service
      ? root.service.displayTitle + "\nClick to browse · middle-click to play/pause"
      : "Crate")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  Row {
    id: content
    visible: !root.vertical
    anchors.centerIn: parent
    spacing: Style.space(6)

    CrateMark {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(18)
      height: width
      ink: root.ink
      paper: root.paper
      opacity: root.service && root.service.playing ? 1 : 0.72
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "CRATE"
      color: root.ink
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.service && root.service.currentPath !== ""
      width: Math.min(160, implicitWidth)
      text: root.service ? (root.service.trackTitle || root.service.currentTitle) : ""
      textFormat: Text.PlainText
      color: Util.alpha(root.ink, 0.7)
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      TransportButton {
        icon: "󰒮"
        hint: "Previous track"
        available: root.service && root.service.currentIndex >= 0
        onActivated: root.service.previous()
      }
      TransportButton {
        icon: root.service && root.service.playing ? "󰏤" : "󰐊"
        hint: root.service && root.service.playing ? "Pause" : "Play"
        available: root.service && root.service.queue.length > 0
        onActivated: root.service.togglePlayback()
      }
      TransportButton {
        icon: "󰒭"
        hint: "Next track"
        available: root.service &&
          (root.service.currentIndex + 1 < root.service.queue.length ||
           (root.service.repeatMode === "all" && root.service.queue.length > 0))
        onActivated: root.service.next(true)
      }
    }
  }

  Column {
    id: verticalContent
    visible: root.vertical
    anchors.centerIn: parent
    spacing: Style.space(2)
    CrateMark {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Style.space(18)
      height: width
      ink: root.ink
      paper: root.paper
      opacity: root.service && root.service.playing ? 1 : 0.72
    }
    TransportButton {
      icon: "󰒮"
      hint: "Previous track"
      available: root.service && root.service.currentIndex >= 0
      onActivated: root.service.previous()
    }
    TransportButton {
      icon: root.service && root.service.playing ? "󰏤" : "󰐊"
      hint: root.service && root.service.playing ? "Pause" : "Play"
      available: root.service && root.service.queue.length > 0
      onActivated: root.service.togglePlayback()
    }
    TransportButton {
      icon: "󰒭"
      hint: "Next track"
      available: root.service &&
        (root.service.currentIndex + 1 < root.service.queue.length ||
         (root.service.repeatMode === "all" && root.service.queue.length > 0))
      onActivated: root.service.next(true)
    }
  }

  component TransportButton: Item {
    id: control
    property string icon: ""
    property string hint: ""
    property bool available: false
    signal activated()
    width: Style.space(22)
    height: Style.space(22)
    opacity: available ? 1 : 0.4
    Text {
      anchors.centerIn: parent
      text: control.icon
      color: root.ink
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
    }
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: control.available ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (control.available) control.activated()
      onWheel: function(wheel) {
        if (root.service) root.service.setVolume(root.service.volume + (wheel.angleDelta.y > 0 ? 5 : -5))
      }
      onEntered: if (root.bar && control.available) root.bar.showTooltip(control, control.hint)
      onExited: if (root.bar) root.bar.hideTooltip(control)
    }
  }
}
