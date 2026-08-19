import QtQuick
import qs.Commons
import qs.Ui

// Planova's quick add: one line into the right section of the selected
// day's file: an event (- @HH:MM title), a todo (- [ ] title), or a log
// (- HH:MM title, stamped with "now"). Enter commits, Escape backs out.
Column {
  id: root

  required property var panel

  spacing: Style.space(10)

  property string addType: "todo"   // "event" | "todo" | "log"

  // While any field has focus the panel's key catcher is blocked, so the
  // fields own Escape and Enter themselves.
  readonly property bool editing: visible && (titleField.activeFocus || hourField.activeFocus || minuteField.activeFocus)

  readonly property color fg: panel.contentForeground
  readonly property string fontFamily: panel.contentFontFamily

  function begin(type) {
    addType = type === "event" || type === "log" ? type : "todo"
    titleField.text = ""
    var next = new Date()
    hourField.text = String((next.getHours() + 1) % 24)
    minuteField.text = "00"
    Qt.callLater(function() { titleField.forceActiveFocus() })
  }

  function commit() {
    var title = titleField.text.trim()
    if (title === "") return
    var store = panel.store
    if (!store) return
    if (addType === "event") {
      var hour = parseInt(hourField.text, 10)
      var minute = parseInt(minuteField.text, 10)
      if (!isFinite(hour) || hour < 0 || hour > 23) hour = 9
      if (!isFinite(minute) || minute < 0 || minute > 59) minute = 0
      store.quickAddEvent(panel.selectedKey, hour, minute, title)
    } else if (addType === "log") {
      store.quickAddLog(panel.selectedKey, title)
    } else {
      store.quickAddTodo(panel.selectedKey, title)
    }
    panel.leaveMode()
  }

  function handleFieldKey(event) {
    if (event.key === Qt.Key_Escape) {
      panel.leaveMode()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      commit()
      event.accepted = true
    } else if (event.modifiers & Qt.ControlModifier) {
      // Switch the entry type without leaving the title field.
      if (event.key === Qt.Key_E) { root.addType = "event"; event.accepted = true }
      else if (event.key === Qt.Key_T) { root.addType = "todo"; event.accepted = true }
      else if (event.key === Qt.Key_L) { root.addType = "log"; event.accepted = true }
    }
  }

  PanelSectionHeader {
    text: "QUICK ADD: " + Qt.formatDate(root.panel.selectedDate, "dddd, MMMM d").toUpperCase()
    foreground: root.fg
    fontFamily: root.fontFamily
  }

  Row {
    spacing: Style.space(6)

    Repeater {
      model: [
        { key: "event", label: "Event", icon: "󰃰", hint: "Ctrl+E" },
        { key: "todo", label: "Todo", icon: "󰄱", hint: "Ctrl+T" },
        { key: "log", label: "Log", icon: "󰦨", hint: "Ctrl+L" }
      ]

      Button {
        required property var modelData
        text: modelData.label
        iconText: modelData.icon
        tooltipText: modelData.hint
        selected: root.addType === modelData.key
        bordered: true
        foreground: root.fg
        fontFamily: root.fontFamily
        onClicked: root.addType = modelData.key
      }
    }
  }

  Row {
    width: parent.width
    spacing: Style.space(8)

    TextField {
      id: titleField
      width: parent.width - (timeRow.visible ? timeRow.width + parent.spacing : 0)
      placeholderText: root.addType === "event" ? "Event title"
        : root.addType === "log" ? "What happened?"
        : "Task"
      foreground: root.fg
      font.family: root.fontFamily
      Keys.onPressed: function(event) { root.handleFieldKey(event) }
    }

    Row {
      id: timeRow
      visible: root.addType === "event"
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      TextField {
        id: hourField
        width: Style.space(46)
        horizontalAlignment: TextInput.AlignHCenter
        placeholderText: "HH"
        inputMethodHints: Qt.ImhDigitsOnly
        maximumLength: 2
        foreground: root.fg
        font.family: root.fontFamily
        Keys.onPressed: function(event) { root.handleFieldKey(event) }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: ":"
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      TextField {
        id: minuteField
        width: Style.space(46)
        horizontalAlignment: TextInput.AlignHCenter
        placeholderText: "MM"
        inputMethodHints: Qt.ImhDigitsOnly
        maximumLength: 2
        foreground: root.fg
        font.family: root.fontFamily
        Keys.onPressed: function(event) { root.handleFieldKey(event) }
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
      text: "Add"
      iconText: "󰐕"
      bordered: true
      foreground: root.fg
      fontFamily: root.fontFamily
      onClicked: root.commit()
    }
  }
}
