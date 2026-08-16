import QtQuick
import qs.Commons
import qs.Ui
import "../PlanovaModel.js" as Model

// The selected day, read the way Planova's day view reads it: Events, then
// Tasks, then Notes. Clicking a task (or Space on the keyboard cursor)
// flips its checkbox in the markdown.
Column {
  id: root

  required property var panel

  spacing: Style.space(6)

  readonly property var summary: panel.selectedSummary
  readonly property color fg: panel.contentForeground
  readonly property string fontFamily: panel.contentFontFamily

  readonly property bool hasAnything: summary
    && (summary.events.length > 0 || summary.tasks.length > 0 || summary.notes.length > 0)

  Text {
    visible: !root.hasAnything
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    text: root.summary ? "Nothing planned" : "No daily file yet - a to add one"
    color: Qt.darker(root.fg, 1.7)
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    topPadding: Style.space(6)
    bottomPadding: Style.space(6)
  }

  // ---- Events -------------------------------------------------------------
  PanelSectionHeader {
    visible: root.summary !== null && root.summary.events.length > 0
    text: "EVENTS"
    foreground: root.fg
    fontFamily: root.fontFamily
  }

  Repeater {
    model: root.summary ? root.summary.events : []

    Column {
      required property var modelData
      width: root.width
      spacing: Style.space(1)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: Model.pad2(modelData.hour) + ":" + Model.pad2(modelData.minute)
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          width: parent.width - x
          text: modelData.title
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }
      }

      Text {
        visible: modelData.description !== ""
        width: parent.width
        leftPadding: Style.space(46)
        text: modelData.description
        color: Qt.darker(root.fg, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
      }
    }
  }

  // ---- Tasks --------------------------------------------------------------
  PanelSectionHeader {
    visible: root.summary !== null && root.summary.tasks.length > 0
    text: "TASKS"
    foreground: root.fg
    fontFamily: root.fontFamily
  }

  Repeater {
    model: root.summary ? root.summary.tasks : []

    Rectangle {
      required property var modelData
      required property int index

      readonly property bool cursor: root.panel.detailFocus && root.panel.detailIndex === index

      width: root.width
      height: taskRow.implicitHeight + Style.space(4)
      radius: Style.cornerRadius
      color: cursor || taskMouse.containsMouse
        ? Style.hoverFillFor(root.fg, Color.accent)
        : "transparent"

      Row {
        id: taskRow
        anchors.verticalCenter: parent.verticalCenter
        x: Style.space(4)
        width: parent.width - Style.space(8)
        spacing: Style.space(8)

        Text {
          text: modelData.done ? "󰱒" : "󰄱"
          color: modelData.done ? Color.accent : root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width - x
          text: modelData.text
          color: modelData.done ? Qt.darker(root.fg, 1.6) : root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.strikeout: modelData.done
          wrapMode: Text.Wrap
        }
      }

      MouseArea {
        id: taskMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.panel.store.toggleTask(root.panel.selectedKey, modelData.lineIndex)
      }
    }
  }

  // ---- Notes --------------------------------------------------------------
  PanelSectionHeader {
    visible: root.summary !== null && root.summary.notes.length > 0
    text: "NOTES"
    foreground: root.fg
    fontFamily: root.fontFamily
  }

  Repeater {
    model: root.summary ? root.summary.notes : []

    Row {
      required property var modelData
      width: root.width
      spacing: Style.space(8)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(4)
        height: Style.space(4)
        radius: width / 2
        color: Qt.darker(root.fg, 1.6)
      }

      Text {
        width: parent.width - x
        text: modelData
        color: Qt.darker(root.fg, 1.25)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
      }
    }
  }
}
