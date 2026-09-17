import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "PlaneTxtModel.js" as Model
import "components"

// The PlaneTxt popup: a month calendar whose days carry todo/event
// indicators, a detail view of the selected day (events, tasks, notes),
// quick add, refill, and a notes browser - all reading and writing
// PlaneTxt's markdown files through the Store.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against plus the shared Store.
Panel {
  id: root
  moduleName: "fr.rvier.planetxt"
  ipcTarget: "fr.rvier.planetxt"
  manageIpc: false

  property var anchorItem: null
  property var store: null

  // The bar tracks the widget mounted in its slot - BarWidget.qml - not this
  // nested panel, so everything the bar identifies a panel by must be that
  // widget.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- View state.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  property string selectedKey: todayKey
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  // tab: which surface is up. mode: what the calendar tab is showing.
  property string tab: "calendar"        // "calendar" | "notes"
  property string mode: "main"           // "main" | "quickadd" | "refill"

  // Keyboard focus inside the day detail list (j/k over tasks).
  property bool detailFocus: false
  property int detailIndex: 0

  readonly property var selectedSummary: {
    if (!store) return null
    store.revision
    return store.summaryFor(selectedKey)
  }
  readonly property var selectedTasks: selectedSummary ? selectedSummary.tasks : []

  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, todayKey, selectedKey)
  readonly property var selectedDate: Model.dateForKey(selectedKey) || today
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Guarded so the widget renders before the bar is injected.
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    refresh()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.mode = "main"
    root.detailFocus = false
    confirm.opened = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Omarchy 4.0.3 hands plugins a PluginBarApi facade where the flag is
  // read-only behind a setter; older bars expose the property directly.
  function setCenterHoverRevealSuppressed(value) {
    if (!root.bar) return
    if (typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if ("centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    goToToday()
    if (store) store.rescan()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
    root.selectedKey = todayKey
    root.detailFocus = false
  }

  function selectKey(key) {
    root.selectedKey = String(key)
    var parts = Model.parseKey(key)
    if (parts) {
      root.viewYear = parts.year
      root.viewMonth = parts.month
    }
    root.detailFocus = false
  }

  function moveSelection(deltaDays) {
    selectKey(Model.stepDay(selectedKey, deltaDays))
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
    // Keep the selection inside the visible month so keyboard nav never
    // strands the cursor off-screen.
    var parts = Model.parseKey(selectedKey)
    if (!parts || parts.year !== next.year || parts.month !== next.month) {
      var day = parts ? Math.min(parts.day, 28) : 1
      root.selectedKey = Model.keyFor(next.year, next.month, day)
    }
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  function refocus() {
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // A focused text field that gets hidden (switching tab from the header
  // while quick add or the notes search is up, dropping the time row by
  // switching the entry type from the hour field) loses focus without
  // handing it to anyone, and the key catcher stops hearing Escape. Whenever
  // the fields stop editing while the panel is up, take the keys back.
  readonly property bool fieldEditing: quickAdd.editing || notesTab.editing
  onFieldEditingChanged: if (!fieldEditing && root.opened) refocus()

  function startQuickAdd(type) {
    root.mode = "quickadd"
    quickAdd.begin(type || "todo")
  }

  function startRefill() {
    if (!store) return
    refillView.begin(store.collectRefill(selectedKey))
    root.mode = "refill"
  }

  function leaveMode() {
    root.mode = "main"
    refocus()
  }

  function editSelectedDay() {
    if (!store) return
    store.openDaily(selectedKey)
    root.close()
  }

  function toggleTaskAtCursor() {
    if (!store) return
    var tasks = selectedTasks
    if (detailIndex < 0 || detailIndex >= tasks.length) return
    store.toggleTask(selectedKey, tasks[detailIndex].lineIndex)
  }

  // ---- Keyboard routing. One place decides what every semantic key means
  //      for the surface currently up; text fields block the catcher and
  //      handle Esc/Enter themselves.

  function handleMove(dx, dy) {
    if (confirm.opened) {
      if (dx !== 0) confirm.selectedIndex = confirm.selectedIndex === 0 ? 1 : 0
      return
    }
    if (tab === "notes") { notesTab.moveCursor(dy); return }
    if (mode === "refill") { refillView.moveCursor(dy); return }
    if (mode !== "main") return
    if (detailFocus) {
      if (dy !== 0) {
        var count = selectedTasks.length
        if (count > 0) detailIndex = Math.max(0, Math.min(count - 1, detailIndex + dy))
      }
      return
    }
    if (dx !== 0) moveSelection(dx)
    if (dy !== 0) moveSelection(dy * 7)
  }

  // Return commits the refill; Space toggles rows. PanelKeyCatcher fires
  // both returnRequested and activateRequested on Enter, so the return
  // handler eats the paired activate.
  property bool _skipActivate: false

  function handleReturn() {
    if (confirm.opened) return
    if (mode === "refill") {
      refillView.commit()
      _skipActivate = true
    }
  }

  function handleActivate() {
    if (_skipActivate) { _skipActivate = false; return }
    if (confirm.opened) {
      if (confirm.selectedIndex === 0) confirm.canceled()
      else confirm.confirmed()
      return
    }
    if (tab === "notes") { notesTab.activate(); return }
    if (mode === "refill") { refillView.toggleAtCursor(); return }
    if (mode !== "main") return
    if (detailFocus) { toggleTaskAtCursor(); return }
    if (selectedTasks.length > 0) {
      root.detailIndex = 0
      root.detailFocus = true
    }
  }

  function handleClose() {
    if (confirm.opened) { confirm.canceled(); return }
    if (mode !== "main") { leaveMode(); return }
    if (detailFocus) { root.detailFocus = false; return }
    root.close()
  }

  function handleDelete() {
    if (tab === "notes") { notesTab.requestDelete(); return }
    if (tab === "calendar" && mode === "main" && detailFocus) toggleTaskAtCursor()
  }

  function handleTextKey(t) {
    if (confirm.opened) return
    if (t === "n") { root.tab = "notes"; return }
    if (t === "c") { root.tab = "calendar"; return }
    if (tab === "notes") {
      if (t === "o") notesTab.startCreate()
      else if (t === "/") notesTab.focusSearch()
      else if (t === "e") notesTab.activate()
      else if (t === "r" || t === "R") notesTab.startRename()
      return
    }
    if (mode !== "main") return
    if (t === "[") moveMonth(-1)
    else if (t === "]") moveMonth(1)
    else if (t === "{") moveYear(-1)
    else if (t === "}") moveYear(1)
    else if (t === "t" || t === "T") goToToday()
    else if (t === "a") startQuickAdd("todo")
    else if (t === "e" || t === "E") startQuickAdd("event")
    else if (t === "g" || t === "G" || t === "L") startQuickAdd("log")
    else if (t === "r") startRefill()
    else if (t === "o" || t === "O") editSelectedDay()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.selectedKey === root.todayKey
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(820))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: quickAdd.editing || notesTab.editing
      onMoveRequested: function(dx, dy) { root.handleMove(dx, dy) }
      onReturnRequested: root.handleReturn()
      onActivateRequested: root.handleActivate()
      onCloseRequested: root.handleClose()
      onDeleteRequested: root.handleDelete()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { root.handleTextKey(t) }

      Flickable {
        id: panelScroll
        anchors.fill: parent
        contentWidth: contentColumn.width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: panelScroll.width
          spacing: Style.space(10)

          // ---- Header: the selected day as the hero, tab switch on the
          //      right. Clicking the hero goes home to today.
          Item {
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(16)

              Text {
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 34
              }

              Text {
                id: heroDate
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(root.selectedDate, "dddd, MMMM d")
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 30
                font.bold: true
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: root.selectedKey !== root.todayKey
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }

            PanelActionButton {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.tab === "calendar" ? "󰎞" : "󰃭"
              tooltipText: root.tab === "calendar" ? "Notes (n)" : "Calendar (c)"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.tab = root.tab === "calendar" ? "notes" : "calendar"
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.contentForeground
          }

          CalendarTab {
            id: calendarTab
            visible: root.tab === "calendar" && root.mode === "main"
            width: parent.width
            panel: root
          }

          QuickAddForm {
            id: quickAdd
            visible: root.tab === "calendar" && root.mode === "quickadd"
            width: parent.width
            panel: root
          }

          RefillView {
            id: refillView
            visible: root.tab === "calendar" && root.mode === "refill"
            width: parent.width
            panel: root
          }

          NotesTab {
            id: notesTab
            visible: root.tab === "notes"
            width: parent.width
            panel: root
          }
        }
      }

      ConfirmDialog {
        id: confirm
        anchors.fill: parent
        fontFamily: root.contentFontFamily

        property var onConfirm: null

        function ask(message, action) {
          confirm.message = message
          confirm.onConfirm = action
          confirm.selectedIndex = 1
          confirm.opened = true
        }

        onCanceled: {
          confirm.opened = false
          root.refocus()
        }
        onConfirmed: {
          confirm.opened = false
          if (confirm.onConfirm) confirm.onConfirm()
          confirm.onConfirm = null
          root.refocus()
        }
      }
    }
  }

  // Exposed so components can raise confirmations without reaching into the
  // key catcher's children.
  function askConfirm(message, action) {
    confirm.ask(message, action)
  }
}
