import QtQuick
import Quickshell
import Quickshell.Io
import "PlanovaModel.js" as Model

// All file IO for the Planova widget: locating the Org root from Planova's
// own preferences, scanning and parsing the daily files, watching for
// external edits (Planova, an editor, Syncthing), and writing changes back
// through the same insertion algorithms Planova uses.
//
// Writes are atomic (FileView atomicWrites: temp file + rename), the same
// guarantee Planova gives, so a crash mid-write can never truncate a daily
// file - and Planova's own watcher picks our writes up within ~2s.
Item {
  id: root

  property QtObject bar: null
  property var settings: ({})

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // ---- Configuration: inline shell.json setting → Planova prefs → default.

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string prefsPath: home + "/.local/share/fr.rvier.planova/shared_preferences.json"

  property var planovaPrefs: ({ storagePath: null, dailyTemplate: null, todoHeaderRegex: null, eventHeaderRegex: null, logHeaderRegex: null })

  readonly property string storagePath: setting("storagePath", planovaPrefs.storagePath || (home + "/Org"))
  readonly property string dailiesDir: storagePath + "/dailies"
  readonly property string notesDir: storagePath + "/notes"

  readonly property string dailyTemplate: setting("dailyTemplate", planovaPrefs.dailyTemplate || Model.DEFAULT_TEMPLATE)
  readonly property string todoHeaderRegex: setting("todoHeaderRegex", planovaPrefs.todoHeaderRegex || Model.DEFAULT_TODO_HEADER)
  readonly property string eventHeaderRegex: setting("eventHeaderRegex", planovaPrefs.eventHeaderRegex || Model.DEFAULT_EVENT_HEADER)
  readonly property string logHeaderRegex: setting("logHeaderRegex", planovaPrefs.logHeaderRegex || Model.DEFAULT_LOG_HEADER)

  FileView {
    id: prefsFile
    path: root.prefsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.planovaPrefs = Model.planovaPrefs(text())
    onFileChanged: reload()
  }

  onStoragePathChanged: rescan()

  // ---- Daily files: key → content, parsed summaries derived once per scan.

  property string todayKey: Model.keyForDate(new Date())
  property var dailies: ({})     // key -> raw file content
  property var summaries: ({})   // key -> Model.daySummary

  // Bumped on every data change; bindings that read through the maps above
  // should also read this so they re-evaluate.
  property int revision: 0

  readonly property int todayUndoneCount: {
    revision
    var s = summaries[todayKey]
    return s ? s.undoneCount : 0
  }

  function summaryFor(key) {
    return summaries[String(key)] || null
  }

  function indicatorFor(key) {
    return Model.dayIndicator(summaries[String(key)] || null)
  }

  function contentFor(key) {
    var content = dailies[String(key)]
    return content === undefined ? "" : content
  }

  function dailyPathFor(key) {
    return dailiesDir + "/" + String(key) + ".md"
  }

  function rescan() {
    dailyScan.running = false
    dailyScan.running = true
    notesScan.running = false
    notesScan.running = true
  }

  function applyScan(text) {
    var dailiesOut = {}
    var summariesOut = {}
    var records = text.split(String.fromCharCode(30))
    for (var i = 0; i < records.length; i++) {
      if (records[i] === "") continue
      var nl = records[i].indexOf("\n")
      if (nl < 0) continue
      var name = records[i].substring(0, nl)
      var m = /(\d{8})\.md$/.exec(name)
      if (!m) continue
      var content = records[i].substring(nl + 1)
      dailiesOut[m[1]] = content
      summariesOut[m[1]] = Model.daySummary(m[1], content)
    }
    dailies = dailiesOut
    summaries = summariesOut
    revision++
  }

  Process {
    id: dailyScan
    // Each record is \x1e + filename + \n + file content. cat of all ~250
    // daily files is instant; a full scan also keeps refill and the badge
    // honest without a second pass.
    command: ["bash", "-c",
      'cd "$1" 2>/dev/null || exit 0; shopt -s nullglob; for f in *.md; do printf "\\x1e%s\\n" "$f"; cat -- "$f"; done',
      "--", root.dailiesDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyScan(text)
    }
  }

  // ---- Local mutation: update state in place, then persist. The watcher's
  //      rescan will land on identical content.

  function setDaily(key, content) {
    key = String(key)
    var dailiesOut = {}
    for (var k in dailies) dailiesOut[k] = dailies[k]
    dailiesOut[key] = content
    var summariesOut = {}
    for (var s in summaries) summariesOut[s] = summaries[s]
    summariesOut[key] = Model.daySummary(key, content)
    dailies = dailiesOut
    summaries = summariesOut
    revision++
    enqueueWrite(dailyPathFor(key), content)
  }

  // A day that has no file yet starts from the user's template, exactly like
  // Planova's quick-add does.
  function baseContentFor(key) {
    var existing = dailies[String(key)]
    return existing === undefined ? dailyTemplate : existing
  }

  function toggleTask(key, lineIndex) {
    var content = dailies[String(key)]
    if (content === undefined) return
    var next = Model.toggleTaskAtLine(content, lineIndex)
    if (next !== content) setDaily(key, next)
  }

  function quickAddEvent(key, hour, minute, title) {
    var line = Model.eventLineFor(hour, minute, title)
    setDaily(key, Model.insertAfterLastEvent(baseContentFor(key), line, eventHeaderRegex))
  }

  function quickAddTodo(key, text) {
    var line = Model.todoLineFor(text)
    setDaily(key, Model.insertAfterLastTodo(baseContentFor(key), line, todoHeaderRegex))
  }

  function quickAddLog(key, text) {
    var now = new Date()
    var line = Model.logLineFor(now.getHours(), now.getMinutes(), text)
    setDaily(key, Model.insertAtEndOfSection(baseContentFor(key), line, logHeaderRegex))
  }

  // ---- Refill: move undone todos from earlier days into targetKey.
  //      selected: [{content, sourceKey}] from Model.collectRefillTodos.

  function collectRefill(targetKey) {
    var list = []
    for (var key in dailies) list.push({ key: key, content: dailies[key] })
    return Model.collectRefillTodos(list, targetKey)
  }

  function performRefill(selected, targetKey) {
    if (!selected || selected.length === 0) return

    var bySource = {}
    for (var i = 0; i < selected.length; i++) {
      var sourceKey = String(selected[i].sourceKey)
      if (!bySource[sourceKey]) bySource[sourceKey] = []
      bySource[sourceKey].push(selected[i].content)
    }

    for (var source in bySource) {
      var content = dailies[source]
      if (content === undefined) continue
      setDaily(source, Model.removeTodoLines(content, bySource[source]))
    }

    var target = baseContentFor(targetKey)
    for (var t = 0; t < selected.length; t++)
      target = Model.insertAfterLastTodo(target, selected[t].content, todoHeaderRegex)
    setDaily(targetKey, target)
  }

  // ---- Atomic writes, serialized. One FileView is reused for every write;
  //      the queue rebinds its path only after the previous save reports
  //      back, so refill's multi-file burst can never interleave.

  property var writeQueue: []
  property bool writeBusy: false

  function enqueueWrite(path, content) {
    var queue = writeQueue.slice()
    queue.push({ path: path, content: content })
    writeQueue = queue
    pumpWrites()
  }

  function pumpWrites() {
    if (writeBusy || writeQueue.length === 0) return
    var job = writeQueue[0]
    writeQueue = writeQueue.slice(1)
    writeBusy = true
    writer.path = job.path
    writer.setText(job.content)
  }

  function writeDone() {
    writeBusy = false
    pumpWrites()
  }

  FileView {
    id: writer
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onSaved: root.writeDone()
    onSaveFailed: function(error) {
      console.warn("planova: write failed:", writer.path)
      root.writeDone()
    }
  }

  // ---- Watcher: external edits land within the same ~2s window Planova
  //      itself uses. Our own writes also come back through here, converging
  //      the in-memory state with whatever actually hit the disk.

  Process {
    id: watcher
    running: true
    command: ["bash", "-c",
      'dirs=(); for d in "$@"; do [ -d "$d" ] && dirs+=("$d"); done; [ ${#dirs[@]} -gt 0 ] || exit 0; exec inotifywait -m -q -e close_write,create,delete,move --format "%w%f" "${dirs[@]}" 2>/dev/null',
      "--", root.dailiesDir, root.notesDir]
    stdout: SplitParser {
      onRead: function(line) {
        if (line.indexOf(".tmp") !== -1 || line.indexOf("._daily_cache") !== -1 || line.indexOf("._note_cache") !== -1) return
        rescanDebounce.restart()
      }
    }
    onExited: watcherRestart.restart()
  }

  onDailiesDirChanged: {
    watcher.running = false
    watcher.running = true
  }

  Timer {
    id: watcherRestart
    interval: 5000
    onTriggered: watcher.running = true
  }

  Timer {
    id: rescanDebounce
    interval: 2000
    onTriggered: root.rescan()
  }

  // ---- Notes: recursive listing of notes/**/*.md, newest first.

  property var notes: []   // [{relPath, name, folder, displayName, mtime}]

  function applyNotes(text) {
    var out = []
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var tab = lines[i].indexOf("\t")
      if (tab < 0) continue
      var mtime = parseFloat(lines[i].substring(0, tab))
      var relPath = lines[i].substring(tab + 1)
      if (relPath === "" || !/\.md$/.test(relPath)) continue
      var slash = relPath.lastIndexOf("/")
      var fileName = relPath.substring(slash + 1).replace(/\.md$/, "")
      out.push({
        relPath: relPath,
        name: fileName,
        displayName: fileName.replace(/[_-]/g, " "),
        folder: slash > 0 ? relPath.substring(0, slash) : "",
        mtime: isFinite(mtime) ? mtime : 0
      })
    }
    out.sort(function(a, b) { return b.mtime - a.mtime })
    notes = out
    revision++
  }

  Process {
    id: notesScan
    command: ["bash", "-c",
      '[ -d "$1" ] && exec find "$1" -type f -name "*.md" -printf "%T@\\t%P\\n" || exit 0',
      "--", root.notesDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyNotes(text)
    }
  }

  function notePathFor(relPath) {
    return notesDir + "/" + String(relPath)
  }

  // Planova's note-name sanitization: strip slashes, keep word chars,
  // whitespace and dashes, collapse whitespace to underscores.
  function sanitizeNoteName(name) {
    var clean = String(name).replace(/[\/\\]/g, "")
      .replace(/[^\w\s-]/g, "").trim().replace(/\s+/g, "_")
    return clean
  }

  function createNote(folder, name) {
    var clean = sanitizeNoteName(name)
    if (clean === "") return ""
    var relPath = (folder ? String(folder).replace(/\/+$/, "") + "/" : "") + clean
    if (!/\.md$/.test(relPath)) relPath += ".md"
    Quickshell.execDetached(["bash", "-c",
      'mkdir -p "$(dirname "$1")" && [ -e "$1" ] || : > "$1"', "--", notePathFor(relPath)])
    rescanDebounce.restart()
    return relPath
  }

  function renameNote(relPath, newName) {
    var clean = sanitizeNoteName(newName)
    if (clean === "") return
    var slash = String(relPath).lastIndexOf("/")
    var folder = slash > 0 ? String(relPath).substring(0, slash + 1) : ""
    Quickshell.execDetached(["mv", "--", notePathFor(relPath), notePathFor(folder + clean + ".md")])
    rescanDebounce.restart()
  }

  function deleteNote(relPath) {
    // rm only ever runs on a path inside notesDir, built here.
    var rel = String(relPath)
    if (rel === "" || rel.indexOf("..") !== -1) return
    Quickshell.execDetached(["rm", "-f", "--", notePathFor(rel)])
    rescanDebounce.restart()
  }

  // ---- External editor -------------------------------------------------------

  function openExternally(path) {
    Quickshell.execDetached(["omarchy-launch-editor", path])
  }

  function openDaily(key) {
    // Seed a missing day from the template first so the editor doesn't open
    // on a blank buffer, matching what Planova's editor shows.
    if (dailies[String(key)] === undefined) setDaily(key, dailyTemplate)
    openExternally(dailyPathFor(key))
  }

  function openNote(relPath) {
    openExternally(notePathFor(relPath))
  }

  Component.onCompleted: rescan()
}
