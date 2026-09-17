import QtQuick
import qs.Commons
import qs.Ui
import "../PlaneTxtModel.js" as Model

// PlaneTxt's refill: every undone todo from days before the selected one,
// newest first. Checked entries are moved - removed from their source file
// and inserted after the last todo of the selected day. Space toggles the
// row under the cursor, Enter moves the selection.
Column {
  id: root

  required property var panel

  spacing: Style.space(8)

  property var items: []       // [{content, text, sourceKey}]
  property var checked: ({})   // index -> true
  property int cursorIndex: 0

  readonly property color fg: panel.contentForeground
  readonly property string fontFamily: panel.contentFontFamily

  readonly property int checkedCount: {
    var n = 0
    for (var key in checked) if (checked[key]) n++
    return n
  }

  function begin(collected) {
    items = collected || []
    var all = {}
    for (var i = 0; i < items.length; i++) all[i] = true
    checked = all
    cursorIndex = 0
  }

  function moveCursor(dy) {
    if (items.length === 0) return
    cursorIndex = Math.max(0, Math.min(items.length - 1, cursorIndex + dy))
  }

  function toggleAt(index) {
    var next = {}
    for (var key in checked) next[key] = checked[key]
    next[index] = !next[index]
    checked = next
  }

  function toggleAtCursor() {
    if (items.length > 0) toggleAt(cursorIndex)
  }

  function displayDate(key) {
    var parts = Model.parseKey(key)
    if (!parts) return key
    return parts.day + "/" + (parts.month + 1) + "/" + parts.year
  }

  function commit() {
    var selected = []
    for (var i = 0; i < items.length; i++) if (checked[i]) selected.push(items[i])
    if (selected.length > 0 && panel.store) panel.store.performRefill(selected, panel.selectedKey)
    panel.leaveMode()
  }

  PanelSectionHeader {
    text: "REFILL INTO " + Qt.formatDate(root.panel.selectedDate, "dddd, MMMM d").toUpperCase()
    foreground: root.fg
    fontFamily: root.fontFamily
  }

  Text {
    visible: root.items.length === 0
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    text: "No undone todos in previous days"
    color: Qt.darker(root.fg, 1.7)
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    topPadding: Style.space(6)
    bottomPadding: Style.space(6)
  }

  Repeater {
    model: root.items

    Rectangle {
      required property var modelData
      required property int index

      readonly property bool isChecked: root.checked[index] === true
      readonly property bool cursor: root.cursorIndex === index

      width: root.width
      height: refillRow.implicitHeight + Style.space(6)
      radius: Style.cornerRadius
      color: cursor || rowMouse.containsMouse
        ? Style.hoverFillFor(root.fg, Color.accent)
        : "transparent"

      Row {
        id: refillRow
        anchors.verticalCenter: parent.verticalCenter
        x: Style.space(4)
        width: parent.width - Style.space(8)
        spacing: Style.space(8)

        Text {
          text: parent.parent.isChecked ? "󰱒" : "󰄱"
          color: parent.parent.isChecked ? Color.accent : root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width - x - sourceLabel.width - Style.space(8)
          text: modelData.text
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }

        Text {
          id: sourceLabel
          text: root.displayDate(modelData.sourceKey)
          color: Qt.darker(root.fg, 1.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.cursorIndex = index
          root.toggleAt(index)
        }
      }
    }
  }

  Row {
    anchors.right: parent.right
    spacing: Style.space(6)

    Button {
      text: "Cancel"
      foreground: root.fg
      fontFamily: root.fontFamily
      onClicked: root.panel.leaveMode()
    }

    Button {
      text: "Refill " + root.checkedCount + (root.checkedCount === 1 ? " todo" : " todos")
      iconText: "󰑏"
      bordered: true
      enabled: root.checkedCount > 0
      foreground: root.fg
      fontFamily: root.fontFamily
      onClicked: root.commit()
    }
  }
}
