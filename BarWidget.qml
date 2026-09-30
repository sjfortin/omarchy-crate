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
  implicitHeight: vertical ? content.implicitHeight + Style.space(12) : barSize

  Row {
    id: content
    visible: !root.vertical
    anchors.centerIn: parent
    spacing: Style.space(6)

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(8)
      height: width
      color: root.service && root.service.playing ? root.ink : "transparent"
      border.width: 1
      border.color: root.ink
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
  }

  Text {
    visible: root.vertical
    anchors.centerIn: parent
    text: "CR"
    color: root.ink
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
  }

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
}
