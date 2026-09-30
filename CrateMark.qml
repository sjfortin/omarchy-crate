import QtQuick

// The app icon's record mark, drawn with the current Omarchy colors.
Item {
  id: mark
  property color ink: "white"
  property color paper: "black"
  readonly property real size: Math.min(width, height)
  implicitWidth: 20
  implicitHeight: 20

  Rectangle {
    anchors.centerIn: parent
    width: mark.size
    height: width
    radius: width / 2
    color: "transparent"
    border.width: Math.max(1, mark.size * 0.065)
    border.color: mark.ink
  }
  Rectangle {
    anchors.centerIn: parent
    width: mark.size * 0.74
    height: width
    radius: width / 2
    color: "transparent"
    border.width: Math.max(1, mark.size * 0.035)
    border.color: mark.ink
    opacity: 0.5
  }
  Rectangle {
    anchors.centerIn: parent
    width: mark.size * 0.43
    height: width
    radius: width / 2
    color: mark.ink
  }
  Rectangle {
    anchors.centerIn: parent
    width: Math.max(2, mark.size * 0.11)
    height: width
    radius: width / 2
    color: mark.paper
  }
}
