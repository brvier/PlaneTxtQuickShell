import QtQuick
import qs.Commons
import "../PlanovaModel.js" as Model

// One day in the month grid: the number with Planova's indicator beneath -
// a filled check when every todo is done, one dot per undone todo up to
// three, a count badge past that, a quiet dot for event-only or file-only
// days. Selection is an accent border; today is bold.
Rectangle {
  id: root

  property var panel: null
  property var cell: ({})

  readonly property var indicator: {
    if (!panel || !panel.store) return { kind: "none", count: 0 }
    panel.store.revision
    return panel.store.indicatorFor(cell.key)
  }

  readonly property color fg: panel ? panel.contentForeground : Color.foreground
  readonly property string fontFamily: panel ? panel.contentFontFamily : Style.font.family

  radius: Style.cornerRadius
  color: cellMouse.containsMouse ? Style.hoverFillFor(fg, Color.accent) : "transparent"
  border.width: cell.selected || cell.today ? Style.spacing.hairline : 0
  border.color: cell.selected
    ? Color.accent
    : Style.normalBorderFor(fg, Color.accent)

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: Style.space(3)
    text: cell.day
    color: cell.inMonth
      ? (cell.weekend ? Qt.darker(root.fg, 1.45) : root.fg)
      : Qt.darker(root.fg, 2.2)
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.bold: cell.today === true
  }

  // ---- Indicator strip along the bottom of the cell.
  Item {
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(3)
    anchors.horizontalCenter: parent.horizontalCenter
    width: parent.width
    height: Style.space(10)

    // All todos done: filled accent circle with a check.
    Rectangle {
      visible: root.indicator.kind === "allDone"
      anchors.centerIn: parent
      width: Style.space(10)
      height: Style.space(10)
      radius: width / 2
      color: Color.accent

      Text {
        anchors.centerIn: parent
        text: "󰄬"
        color: Color.background
        font.pixelSize: Style.space(7)
      }
    }

    // 1-3 undone todos: that many urgent dots.
    Row {
      visible: root.indicator.kind === "dots"
      anchors.centerIn: parent
      spacing: Style.space(2)

      Repeater {
        model: root.indicator.kind === "dots" ? root.indicator.count : 0

        Rectangle {
          width: Style.space(5)
          height: Style.space(5)
          radius: width / 2
          color: Color.urgent
        }
      }
    }

    // More than 3: the number itself.
    Rectangle {
      visible: root.indicator.kind === "count"
      anchors.centerIn: parent
      width: Math.max(height, countLabel.implicitWidth + Style.space(4))
      height: Style.space(10)
      radius: height / 2
      color: Color.urgent

      Text {
        id: countLabel
        anchors.centerIn: parent
        text: root.indicator.count
        color: Color.background
        font.family: root.fontFamily
        font.pixelSize: Style.space(7)
        font.bold: true
      }
    }

    // Events only: one accent dot. A file with neither: one faint dot.
    Rectangle {
      visible: root.indicator.kind === "eventDot" || root.indicator.kind === "fileDot"
      anchors.centerIn: parent
      width: Style.space(5)
      height: Style.space(5)
      radius: width / 2
      color: root.indicator.kind === "eventDot" ? Color.accent : Qt.darker(root.fg, 1.8)
    }
  }

  MouseArea {
    id: cellMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: if (root.panel) root.panel.selectKey(root.cell.key)
    onDoubleClicked: if (root.panel) root.panel.editSelectedDay()
  }
}
