import QtQuick
import qs.Commons
import qs.Ui

// PlaneTxt's notes, newest first: every .md under notes/ (recursively),
// searchable by name, opened in the external editor. o creates, F2/r
// renames, x deletes (with confirmation).
Column {
  id: root

  required property var panel

  spacing: Style.space(8)

  property int cursorIndex: 0
  property string createFolder: ""
  property bool creating: false
  property string renamingPath: ""

  readonly property bool editing: visible && (searchField.activeFocus || nameField.activeFocus)

  readonly property color fg: panel.contentForeground
  readonly property string fontFamily: panel.contentFontFamily

  readonly property var filteredNotes: {
    if (!panel.store) return []
    panel.store.revision
    var all = panel.store.notes
    var needle = searchField.text.trim().toLowerCase()
    if (needle === "") return all
    return all.filter(function(note) {
      return note.relPath.toLowerCase().indexOf(needle) !== -1
    })
  }

  onFilteredNotesChanged: {
    if (cursorIndex >= filteredNotes.length) cursorIndex = Math.max(0, filteredNotes.length - 1)
  }

  function moveCursor(dy) {
    if (filteredNotes.length === 0) return
    cursorIndex = Math.max(0, Math.min(filteredNotes.length - 1, cursorIndex + dy))
  }

  function activate() {
    if (cursorIndex < 0 || cursorIndex >= filteredNotes.length) return
    panel.store.openNote(filteredNotes[cursorIndex].relPath)
    panel.close()
  }

  function focusSearch() {
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function startCreate() {
    creating = true
    renamingPath = ""
    nameField.text = ""
    Qt.callLater(function() { nameField.forceActiveFocus() })
  }

  function startRename() {
    if (cursorIndex < 0 || cursorIndex >= filteredNotes.length) return
    renamingPath = filteredNotes[cursorIndex].relPath
    creating = false
    nameField.text = filteredNotes[cursorIndex].name
    Qt.callLater(function() { nameField.forceActiveFocus() })
  }

  function commitName() {
    var name = nameField.text.trim()
    if (name === "") { cancelName(); return }
    if (renamingPath !== "") {
      panel.store.renameNote(renamingPath, name)
    } else {
      var relPath = panel.store.createNote("", name)
      if (relPath !== "") {
        panel.store.openNote(relPath)
        panel.close()
      }
    }
    cancelName()
  }

  function cancelName() {
    creating = false
    renamingPath = ""
    nameField.text = ""
    panel.refocus()
  }

  function requestDelete() {
    if (cursorIndex < 0 || cursorIndex >= filteredNotes.length) return
    var note = filteredNotes[cursorIndex]
    panel.askConfirm("Delete note \"" + note.displayName + "\"?", function() {
      panel.store.deleteNote(note.relPath)
    })
  }

  function relativeAge(mtime) {
    if (!mtime) return ""
    var seconds = Date.now() / 1000 - mtime
    if (seconds < 3600) return Math.max(1, Math.round(seconds / 60)) + "m"
    if (seconds < 86400) return Math.round(seconds / 3600) + "h"
    return Math.round(seconds / 86400) + "d"
  }

  Row {
    width: parent.width
    spacing: Style.space(8)

    TextField {
      id: searchField
      width: parent.width - newButton.width - parent.spacing
      placeholderText: "Search notes (/)"
      foreground: root.fg
      font.family: root.fontFamily
      onTextChanged: root.cursorIndex = 0
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (text !== "") text = ""
          else root.panel.refocus()
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.panel.refocus()
          root.activate()
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          root.panel.refocus()
          event.accepted = true
        }
      }
    }

    Button {
      id: newButton
      anchors.verticalCenter: parent.verticalCenter
      text: "New"
      iconText: "󰎜"
      tooltipText: "New note (o)"
      foreground: root.fg
      fontFamily: root.fontFamily
      onClicked: root.startCreate()
    }
  }

  // Inline name row for create/rename.
  Row {
    visible: root.creating || root.renamingPath !== ""
    width: parent.width
    spacing: Style.space(8)

    TextField {
      id: nameField
      width: parent.width
      placeholderText: root.renamingPath !== "" ? "New name" : "Note name"
      foreground: root.fg
      font.family: root.fontFamily
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.cancelName()
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.commitName()
          event.accepted = true
        }
      }
    }
  }

  Text {
    visible: root.filteredNotes.length === 0
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    text: searchField.text.trim() !== "" ? "No matches" : "No notes yet - o to create one"
    color: Qt.darker(root.fg, 1.7)
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    topPadding: Style.space(8)
    bottomPadding: Style.space(8)
  }

  Repeater {
    model: root.filteredNotes

    Rectangle {
      required property var modelData
      required property int index

      readonly property bool cursor: root.cursorIndex === index

      width: root.width
      height: noteRow.implicitHeight + Style.space(8)
      radius: Style.cornerRadius
      color: cursor || noteMouse.containsMouse
        ? Style.hoverFillFor(root.fg, Color.accent)
        : "transparent"

      Row {
        id: noteRow
        anchors.verticalCenter: parent.verticalCenter
        x: Style.space(6)
        width: parent.width - Style.space(12)
        spacing: Style.space(8)

        Text {
          text: "󰎞"
          color: Qt.darker(root.fg, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Column {
          width: parent.width - x - ageLabel.width - Style.space(8)

          Text {
            width: parent.width
            text: modelData.displayName
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            visible: modelData.folder !== ""
            width: parent.width
            text: modelData.folder
            color: Qt.darker(root.fg, 1.7)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Text {
          id: ageLabel
          anchors.verticalCenter: parent.verticalCenter
          text: root.relativeAge(modelData.mtime)
          color: Qt.darker(root.fg, 1.7)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      MouseArea {
        id: noteMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
          root.cursorIndex = index
          if (mouse.button === Qt.RightButton) root.startRename()
          else root.activate()
        }
      }
    }
  }

  Text {
    visible: root.filteredNotes.length > 0
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    text: "enter open · o new · r rename · x delete · / search"
    color: Qt.darker(root.fg, 1.9)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    topPadding: Style.space(4)
  }
}
