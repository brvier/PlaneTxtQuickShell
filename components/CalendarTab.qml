import QtQuick
import qs.Commons
import qs.Ui

// Month grid over the selected day's detail: the panel's main surface.
// The grid is a picker - arrows and clicks move the selected day - with
// Planova's per-day indicators drawn under each day number.
Column {
  id: root

  required property var panel

  spacing: Style.space(8)

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(38)
  readonly property int cellSpacing: Style.space(2)

  // Monday-first weekday header, matching Model.monthGrid.
  function weekdayLabel(offset) {
    var weekday = (1 + offset) % 7
    return String(Qt.locale().dayName(weekday, Locale.ShortFormat)).replace(/\.$/, "").toUpperCase()
  }

  Item {
    width: parent.width
    height: gridColumn.height

    WheelHandler {
      onWheel: function(event) {
        if (event.angleDelta.y === 0) return
        root.panel.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
      }
    }

    Column {
      id: gridColumn
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(3)

      Row {
        spacing: root.cellSpacing

        Repeater {
          model: 7

          Text {
            required property int index
            width: root.cellWidth
            height: Style.space(16)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: root.weekdayLabel(index)
            color: Qt.darker(root.panel.contentForeground, 1.5)
            font.family: root.panel.contentFontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            font.bold: true
          }
        }
      }

      Repeater {
        model: root.panel.weeks

        Row {
          required property var modelData
          spacing: root.cellSpacing

          Repeater {
            model: modelData.days

            DayCell {
              required property var modelData
              panel: root.panel
              cell: modelData
              width: root.cellWidth
              height: root.cellHeight
            }
          }
        }
      }
    }
  }

  // ---- Month stepping rail under the grid.
  Item {
    width: parent.width
    height: monthNav.height

    Item {
      id: monthNav
      anchors.horizontalCenter: parent.horizontalCenter
      width: gridColumn.width
      height: monthLabel.implicitHeight + Style.space(8)

      Text {
        id: monthLabel
        anchors.centerIn: parent
        width: Style.space(140)
        horizontalAlignment: Text.AlignHCenter
        text: Qt.formatDate(new Date(root.panel.viewYear, root.panel.viewMonth, 1), "MMMM yyyy").toUpperCase()
        color: Qt.darker(root.panel.contentForeground, 1.4)
        font.family: root.panel.contentFontFamily
        font.pixelSize: Style.font.body
        font.letterSpacing: 1
      }

      PanelActionButton {
        anchors.left: parent.left
        anchors.leftMargin: -Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰅁"
        tooltipText: "Previous month"
        foreground: root.panel.contentForeground
        fontFamily: root.panel.contentFontFamily
        onClicked: root.panel.moveMonth(-1)
      }

      PanelActionButton {
        anchors.right: parent.right
        anchors.rightMargin: -Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰅂"
        tooltipText: "Next month"
        foreground: root.panel.contentForeground
        fontFamily: root.panel.contentFontFamily
        onClicked: root.panel.moveMonth(1)
      }
    }
  }

  PanelSeparator {
    width: parent.width
    foreground: root.panel.contentForeground
  }

  DayDetail {
    width: parent.width
    panel: root.panel
  }

  // ---- Action rail: the write operations, mirrored by their hotkeys.
  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.space(6)

    Button {
      text: "Add"
      iconText: "󰐕"
      tooltipText: "Quick add - event, todo, or log (a)"
      foreground: root.panel.contentForeground
      fontFamily: root.panel.contentFontFamily
      onClicked: root.panel.startQuickAdd()
    }

    Button {
      text: "Refill"
      iconText: "󰑏"
      tooltipText: "Move undone todos from earlier days here (r)"
      foreground: root.panel.contentForeground
      fontFamily: root.panel.contentFontFamily
      onClicked: root.panel.startRefill()
    }

    Button {
      text: "Edit"
      iconText: "󰤌"
      tooltipText: "Open this day in your editor (e)"
      foreground: root.panel.contentForeground
      fontFamily: root.panel.contentFontFamily
      onClicked: root.panel.editSelectedDay()
    }
  }
}
