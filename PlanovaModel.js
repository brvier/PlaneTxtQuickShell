// Pure parsing, insertion, and date math for the Planova bar widget and its
// panel. Everything here is Qt-free so it can be unit tested under node
// (tests/model.test.mjs); the QML owns file IO and month/weekday naming.
//
// The regexes and insertion algorithms are line-for-line ports of Planova's
// lib/utils/markdown_parser.dart and lib/utils/daily_content_helper.dart -
// they are the compatibility contract with Planova's markdown files. Do not
// "improve" them without changing Planova first.

// ---- Line regexes (MarkdownParser) ----------------------------------------

// Shape of a todo line, with or without text after the brackets. Done is a
// lowercase x only; anything whitespace is undone.
var TODO_LINE = /^\s*[-*+]\s*\[\s*[x\s]\s*\]/

// Todo with text: group 1 is the checkbox char, group 2 the task text.
var TODO_LINE_WITH_TEXT = /^\s*[-*+]\s*\[\s*([x\s])\s*\]\s+(.+)$/

// Event: bullet then @HH:MM. Hour may be 1-2 digits, minute exactly 2.
// A bare "@9:00" mention without a bullet is not an event.
var EVENT_LINE = /^\s*[-*+]\s*@(\d{1,2}):(\d{2})\b\s*(.*)$/

// Any header, level 1-6.
var HEADER_LINE = /^\s*#{1,6}\s+/

// Plain bullet (non-task), used by parseNotes to strip markers.
var BULLET_LINE = /^\s*[-*+]\s+/

// ---- Defaults (AppConstants / ThemeProvider) -------------------------------

var DEFAULT_TODO_HEADER = "^#{1,2}\\s+.*(Todos?|Tasks?)"
var DEFAULT_EVENT_HEADER = "^#{1,2}\\s+.*Events?"
var DEFAULT_LOG_HEADER = "^#{1,2}\\s+.*(Journal|Logs?)"

var DEFAULT_TEMPLATE = "# 📅 Events\n\n# ✅ Todos\n\n# 📝 Logs\n\n# 🗒️ Notes\n"

function isTodoLine(line) {
  return TODO_LINE.test(line)
}

function isEventLine(line) {
  return EVENT_LINE.test(line)
}

// ---- Parsing (MarkdownParser) ----------------------------------------------

// Tasks in the whole file, in file order. lineIndex is an extension over the
// Dart parser so a toggle can rewrite the exact line it came from.
function parseTasks(content) {
  var tasks = []
  var lines = String(content || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = TODO_LINE_WITH_TEXT.exec(lines[i])
    if (!m) continue
    tasks.push({ text: m[2].trim(), done: m[1] === "x", lineIndex: i })
  }
  return tasks
}

// Events in the whole file. dateKey is Planova's YYYYMMDD; an invalid key
// yields no events, matching the Dart parser.
function parseEvents(dateKey, content) {
  var events = []
  if (!parseKey(dateKey)) return events
  var lines = String(content || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = EVENT_LINE.exec(lines[i])
    if (!m) continue
    events.push({
      title: m[3].trim(),
      hour: parseInt(m[1], 10),
      minute: parseInt(m[2], 10),
      description: extractEventDescription(lines, i),
      lineIndex: i,
      dateKey: String(dateKey)
    })
  }
  return events
}

// Description lines following an event: up to 4 lines, stopping at a blank
// line, another event, or a todo.
function extractEventDescription(lines, eventIdx) {
  var out = []
  var maxLook = Math.min(eventIdx + 5, lines.length)
  for (var i = eventIdx + 1; i < maxLook; i++) {
    var line = lines[i].trim()
    if (line === "") break
    if (isEventLine(line) || isTodoLine(line)) break
    out.push(line)
  }
  return out.join("\n")
}

// Free text: everything that is not a task, an event, or a header, with
// bullet markers stripped.
function parseNotes(content) {
  var notes = []
  var lines = String(content || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var trimmed = lines[i].trim()
    if (trimmed === "") continue
    if (HEADER_LINE.test(trimmed)) continue
    if (isTodoLine(trimmed)) continue
    if (isEventLine(trimmed)) continue
    if (BULLET_LINE.test(trimmed)) {
      var clean = trimmed.replace(BULLET_LINE, "").trim()
      if (clean !== "") notes.push(clean)
      continue
    }
    notes.push(trimmed)
  }
  return notes
}

// ---- Insertion (DailyContentHelper) ----------------------------------------

function appendAtEnd(content, newContent) {
  if (content === "") return newContent
  return content.charAt(content.length - 1) === "\n"
    ? content + newContent
    : content + "\n\n" + newContent
}

// Bounds of the section whose header is the first line matching headerRegex.
// With a strictItemPredicate the section ends at the first non-empty,
// non-header line failing it (a stray note ends a tasks section); otherwise
// it runs to the next header or EOF. Blank lines never terminate.
function findSection(lines, headerRegex, strictItemPredicate) {
  var headerIndex = -1
  for (var i = 0; i < lines.length; i++) {
    if (headerRegex.test(lines[i])) { headerIndex = i; break }
  }
  if (headerIndex < 0) return { headerIndex: -1, endExclusive: -1, found: false }

  var end = headerIndex + 1
  while (end < lines.length) {
    var t = lines[end].trim()
    if (t === "") { end++; continue }
    if (t.charAt(0) === "#") break
    if (strictItemPredicate && !strictItemPredicate(t)) break
    end++
  }
  return { headerIndex: headerIndex, endExclusive: end, found: true }
}

// Insert newContent right after the first matching header (skipping blank
// lines); append at end when no header matches or the regex is invalid.
function insertAfterHeader(content, newContent, headerRegexStr) {
  content = String(content || "")
  if (!headerRegexStr) return appendAtEnd(content, newContent)
  try {
    var regex = new RegExp(headerRegexStr, "m")
    var lines = content.split("\n")

    var headerIndex = -1
    for (var i = 0; i < lines.length; i++) {
      if (regex.test(lines[i])) { headerIndex = i; break }
    }
    if (headerIndex < 0) return appendAtEnd(content, newContent)

    var insertIndex = headerIndex + 1
    while (insertIndex < lines.length && lines[insertIndex].trim() === "") insertIndex++

    var beforeInsert = lines.slice(0, insertIndex).join("\n")
    var afterInsert = lines.slice(insertIndex).join("\n")
    var nextLine = afterInsert.split("\n")[0]
    nextLine = nextLine === undefined ? "" : nextLine.trim()
    var nextIsHeader = nextLine.charAt(0) === "#"

    if (afterInsert !== "") {
      return nextIsHeader
        ? beforeInsert + "\n" + newContent + "\n\n" + afterInsert
        : beforeInsert + "\n" + newContent + "\n" + afterInsert
    }
    return beforeInsert + "\n" + newContent
  } catch (e) {
    return appendAtEnd(content, newContent)
  }
}

function sortEventLinesChronologically(eventLines) {
  var withTimes = []
  for (var i = 0; i < eventLines.length; i++) {
    var m = EVENT_LINE.exec(eventLines[i])
    var t = m ? parseInt(m[1], 10) * 100 + parseInt(m[2], 10) : 0
    withTimes.push({ t: t, i: i, line: eventLines[i] })
  }
  // Stable by construction: ties keep input order via the index.
  withTimes.sort(function(a, b) { return a.t - b.t || a.i - b.i })
  return withTimes.map(function(e) { return e.line })
}

// Two event lines are the same event if their text after the time matches.
function eventsAreSame(existing, newEvent) {
  var stripTime = /^\s*[-*+]\s*@\d{1,2}:\d{2}\s*/
  return existing.replace(stripTime, "").trim() === newEvent.replace(stripTime, "").trim()
}

// Merge eventLines into the events section in chronological order, keeping
// existing events and skipping duplicates. Used by ICS-style bulk inserts.
function insertEventsChronologically(content, eventLines, eventHeaderRegexStr) {
  content = String(content || "")
  try {
    var regex = new RegExp(String(eventHeaderRegexStr), "m")
    var lines = content.split("\n")
    var range = findSection(lines, regex, isEventLine)
    var sortedNew = sortEventLinesChronologically(eventLines)

    if (range.found) {
      var beforeEvents = lines.slice(0, range.headerIndex + 1)
      var eventsBlock = lines.slice(range.headerIndex + 1, range.endExclusive)
      var afterEventsSection = lines.slice(range.endExclusive)

      var existingEvents = eventsBlock.filter(function(l) { return isEventLine(l.trim()) })
      var newOnly = sortedNew.filter(function(newE) {
        return !existingEvents.some(function(e) { return eventsAreSame(e.trim(), newE) })
      })
      var merged = sortEventLinesChronologically(existingEvents.concat(newOnly))

      var out = beforeEvents
        .concat(eventsBlock.filter(function(l) { return !isEventLine(l.trim()) }))
        .concat(merged)
      if (afterEventsSection.length > 0) out = out.concat(afterEventsSection)
      return out.join("\n")
    }
    return appendAtEnd(content, sortedNew.join("\n"))
  } catch (e) {
    return appendAtEnd(content, eventLines.join("\n"))
  }
}

// Insert newItem after the last line in range matching itemMatcher; with no
// items yet, right after the header with a blank-line separator before any
// subsequent content.
function insertItem(lines, range, newItem, itemMatcher) {
  var lastItemIndex = range.headerIndex
  var hasItems = false
  for (var i = range.headerIndex + 1; i < range.endExclusive; i++) {
    if (itemMatcher(lines[i])) { lastItemIndex = i; hasItems = true }
  }

  if (hasItems) {
    var before = lines.slice(0, lastItemIndex + 1).join("\n")
    var after = lines.slice(lastItemIndex + 1).join("\n")
    return after !== "" ? before + "\n" + newItem + "\n" + after : before + "\n" + newItem
  }

  var beforeHeader = lines.slice(0, range.headerIndex + 1).join("\n")
  var afterHeader = lines.slice(range.headerIndex + 1).join("\n")
  return afterHeader !== ""
    ? beforeHeader + "\n" + newItem + "\n\n" + afterHeader
    : beforeHeader + "\n\n" + newItem
}

function insertAfterLastEvent(content, eventContent, eventHeaderRegexStr) {
  content = String(content || "")
  if (!eventHeaderRegexStr) return appendAtEnd(content, eventContent)
  try {
    var regex = new RegExp(eventHeaderRegexStr, "m")
    var lines = content.split("\n")
    var range = findSection(lines, regex, isEventLine)
    if (!range.found) return appendAtEnd(content, eventContent)
    return insertItem(lines, range, eventContent, isEventLine)
  } catch (e) {
    return appendAtEnd(content, eventContent)
  }
}

function insertAfterLastTodo(content, todoContent, todoHeaderRegexStr) {
  content = String(content || "")
  if (!todoHeaderRegexStr) return appendAtEnd(content, todoContent)
  try {
    var regex = new RegExp(todoHeaderRegexStr, "m")
    var lines = content.split("\n")
    var range = findSection(lines, regex, isTodoLine)
    if (!range.found) return appendAtEnd(content, todoContent)
    return insertItem(lines, range, todoContent, isTodoLine)
  } catch (e) {
    return appendAtEnd(content, todoContent)
  }
}

// Insert at the end of a section, just before the next header - the shape
// log entries take. No item predicate: any line belongs to the section.
function insertAtEndOfSection(content, newContent, sectionHeaderRegexStr) {
  content = String(content || "")
  if (!sectionHeaderRegexStr) return appendAtEnd(content, newContent)
  try {
    var regex = new RegExp(sectionHeaderRegexStr, "m")
    var lines = content.split("\n")
    var range = findSection(lines, regex, null)
    if (!range.found) return appendAtEnd(content, newContent)

    var lastContentIndex = range.endExclusive - 1
    while (lastContentIndex > range.headerIndex && lines[lastContentIndex].trim() === "") lastContentIndex--

    var insertIndex = lastContentIndex + 1
    var before = lines.slice(0, insertIndex).join("\n")
    var after = lines.slice(insertIndex).join("\n")
    return after !== "" ? before + "\n" + newContent + "\n" + after : before + "\n" + newContent
  } catch (e) {
    return appendAtEnd(content, newContent)
  }
}

// ---- Mutations and serializers ---------------------------------------------

// Rewrite only the checkbox on the given line, keeping indentation, bullet
// marker, and text. Matches Planova's editor toggle output: "[x]" / "[ ]"
// followed by a single space and the text.
function toggleTaskAtLine(content, lineIndex) {
  var lines = String(content || "").split("\n")
  if (lineIndex < 0 || lineIndex >= lines.length) return content
  var m = /^(\s*[-*+]\s*)\[\s*([x\s]?)\s*\]\s*(.*)$/.exec(lines[lineIndex])
  if (!m) return content
  var newBox = m[2] === "x" ? "[ ]" : "[x]"
  lines[lineIndex] = m[1] + newBox + (m[3] !== "" ? " " + m[3] : "")
  return lines.join("\n")
}

// Refill source cleanup: drop every line whose trimmed form equals one of
// the canonical todo lines. Trim-equality is what Planova uses, so a source
// line written with a different bullet marker survives there and here alike.
function removeTodoLines(content, todoLines) {
  var wanted = {}
  for (var i = 0; i < todoLines.length; i++) wanted[String(todoLines[i]).trim()] = true
  return String(content || "").split("\n")
    .filter(function(line) { return !wanted[line.trim()] })
    .join("\n")
}

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

function todoLineFor(text) {
  return "- [ ] " + String(text).trim()
}

function eventLineFor(hour, minute, title) {
  return "- @" + pad2(hour) + ":" + pad2(minute) + " " + String(title).trim()
}

function logLineFor(hour, minute, text) {
  return "- " + pad2(hour) + ":" + pad2(minute) + " " + String(text).trim()
}

// Undone todos from every daily strictly before targetKey, newest day first,
// as canonical refill entries. dailies: [{key, content}].
function collectRefillTodos(dailies, targetKey) {
  var target = String(targetKey)
  var earlier = dailies
    .filter(function(d) { return String(d.key) < target })
    .sort(function(a, b) { return String(a.key) < String(b.key) ? 1 : -1 })

  var out = []
  for (var i = 0; i < earlier.length; i++) {
    var tasks = parseTasks(earlier[i].content)
    for (var t = 0; t < tasks.length; t++) {
      if (tasks[t].done) continue
      out.push({
        content: "- [ ] " + tasks[t].text,
        text: tasks[t].text,
        sourceKey: String(earlier[i].key)
      })
    }
  }
  return out
}

// ---- Day summaries and grid indicators --------------------------------------

// Everything the calendar needs to mark one day, from raw file content.
function daySummary(key, content) {
  var tasks = parseTasks(content)
  var undone = 0
  for (var i = 0; i < tasks.length; i++) if (!tasks[i].done) undone++
  var events = parseEvents(key, content)
  return {
    key: String(key),
    hasFile: true,
    tasks: tasks,
    events: events,
    notes: parseNotes(content),
    undoneCount: undone
  }
}

// Indicator for a day cell, mirroring Planova's CalendarDayWidget rules:
// all todos done → filled check; 1-3 undone → that many dots; more → a count
// badge; events only → one accent dot; a file with neither → one quiet dot.
function dayIndicator(summary) {
  if (!summary || !summary.hasFile) return { kind: "none", count: 0 }
  if (summary.tasks.length > 0) {
    if (summary.undoneCount === 0) return { kind: "allDone", count: 0 }
    if (summary.undoneCount <= 3) return { kind: "dots", count: summary.undoneCount }
    return { kind: "count", count: summary.undoneCount }
  }
  if (summary.events.length > 0) return { kind: "eventDot", count: 0 }
  return { kind: "fileDot", count: 0 }
}

// ---- Dates and keys ----------------------------------------------------------

// Planova's day identity: zero-padded YYYYMMDD.
function keyFor(year, month, day) {
  return String(year) + pad2(Number(month) + 1) + pad2(day)
}

function keyForDate(date) {
  return keyFor(date.getFullYear(), date.getMonth(), date.getDate())
}

// {year, month (0-based), day} for a valid key, null otherwise.
function parseKey(key) {
  var m = /^(\d{4})(\d{2})(\d{2})$/.exec(String(key || "").trim())
  if (!m) return null
  var month = parseInt(m[2], 10)
  var day = parseInt(m[3], 10)
  if (month < 1 || month > 12 || day < 1 || day > 31) return null
  return { year: parseInt(m[1], 10), month: month - 1, day: day }
}

function dateForKey(key) {
  var parts = parseKey(key)
  return parts ? new Date(parts.year, parts.month, parts.day) : null
}

// Key of the day `delta` days away from key.
function stepDay(key, delta) {
  var parts = parseKey(key)
  if (!parts) return key
  var date = new Date(parts.year, parts.month, parts.day + Number(delta))
  return keyForDate(date)
}

function stepMonth(year, month, delta) {
  var target = new Date(year, Number(month) + Number(delta), 1)
  return { year: target.getFullYear(), month: target.getMonth() }
}

// ISO-8601 week number, for the bar label's 'ww' token (same as the clock).
var MS_PER_DAY = 86400000

function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

function isoWeekLiteral(year, month, day) {
  return pad2(isoWeek(year, month, day))
}

// Always six rows of seven days, Monday-first like Planova's calendar, so
// the popup is the same height in February as in August. todayKey and
// selectedKey are Planova YYYYMMDD keys.
function monthGrid(year, month, todayKey, selectedKey) {
  var leading = (new Date(year, month, 1).getDay() - 1 + 7) % 7
  var cursor = new Date(year, month, 1 - leading)
  var today = String(todayKey || "")
  var selected = String(selectedKey || "")
  var weeks = []

  for (var w = 0; w < 6; w++) {
    var days = []
    var thursday = null
    for (var d = 0; d < 7; d++) {
      var cellYear = cursor.getFullYear()
      var cellMonth = cursor.getMonth()
      var cellDay = cursor.getDate()
      var weekday = cursor.getDay()
      var key = keyFor(cellYear, cellMonth, cellDay)
      if (weekday === 4) thursday = { year: cellYear, month: cellMonth, day: cellDay }
      days.push({
        key: key,
        year: cellYear,
        month: cellMonth,
        day: cellDay,
        weekday: weekday,
        inMonth: cellMonth === month && cellYear === year,
        weekend: weekday === 0 || weekday === 6,
        today: key === today,
        selected: key === selected
      })
      cursor.setDate(cursor.getDate() + 1)
    }
    var anchor = thursday || days[0]
    weeks.push({ week: isoWeek(anchor.year, anchor.month, anchor.day), days: days })
  }
  return weeks
}

// ---- Bar label formats (copied from the clock's Model.js) -------------------

var CLOCK_FORMATS = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
]

var VERTICAL_CLOCK_FORMATS = [
  "HH\n\u2014\nmm",
  "h\n\u2014\nmm\nAP",
  "dd\nMMM\n'W'ww\n''yy",
  "HH\nmm"
]

function clockFormats(vertical) {
  return vertical ? VERTICAL_CLOCK_FORMATS.slice() : CLOCK_FORMATS.slice()
}

function clockFormatRing(configured, configuredAlt, presets) {
  var ring = []
  var candidates = (presets || []).concat([configuredAlt, configured])
  for (var i = 0; i < candidates.length; i++) {
    var format = String(candidates[i] === undefined || candidates[i] === null ? "" : candidates[i])
    if (format === "" || ring.indexOf(format) !== -1) continue
    ring.push(format)
  }
  return ring.length > 0 ? ring : ["HH:mm"]
}

function nextClockFormat(ring, current) {
  if (!ring || ring.length === 0) return ""
  var index = ring.indexOf(String(current === undefined || current === null ? "" : current))
  return ring[(index + 1) % ring.length]
}

// ---- Planova preferences -----------------------------------------------------

// Values a QuickShell panel needs from Planova's shared_preferences.json.
// Every key is prefixed "flutter." on disk (the plugin adds it here so QML
// hands in the raw parsed JSON object).
function planovaPrefs(json) {
  var prefs = {}
  try { prefs = JSON.parse(String(json || "{}")) || {} } catch (e) { prefs = {} }
  function pick(key) {
    var value = prefs["flutter." + key]
    return typeof value === "string" && value !== "" ? value : null
  }
  return {
    storagePath: pick("storage_path"),
    dailyTemplate: pick("daily_template"),
    todoHeaderRegex: pick("todo_header_regex"),
    eventHeaderRegex: pick("event_header_regex"),
    logHeaderRegex: pick("log_header_regex")
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    TODO_LINE: TODO_LINE,
    EVENT_LINE: EVENT_LINE,
    DEFAULT_TODO_HEADER: DEFAULT_TODO_HEADER,
    DEFAULT_EVENT_HEADER: DEFAULT_EVENT_HEADER,
    DEFAULT_LOG_HEADER: DEFAULT_LOG_HEADER,
    DEFAULT_TEMPLATE: DEFAULT_TEMPLATE,
    isTodoLine: isTodoLine,
    isEventLine: isEventLine,
    parseTasks: parseTasks,
    parseEvents: parseEvents,
    parseNotes: parseNotes,
    extractEventDescription: extractEventDescription,
    appendAtEnd: appendAtEnd,
    insertAfterHeader: insertAfterHeader,
    insertAfterLastTodo: insertAfterLastTodo,
    insertAfterLastEvent: insertAfterLastEvent,
    insertAtEndOfSection: insertAtEndOfSection,
    insertEventsChronologically: insertEventsChronologically,
    toggleTaskAtLine: toggleTaskAtLine,
    removeTodoLines: removeTodoLines,
    pad2: pad2,
    todoLineFor: todoLineFor,
    eventLineFor: eventLineFor,
    logLineFor: logLineFor,
    collectRefillTodos: collectRefillTodos,
    daySummary: daySummary,
    dayIndicator: dayIndicator,
    keyFor: keyFor,
    keyForDate: keyForDate,
    parseKey: parseKey,
    dateForKey: dateForKey,
    stepDay: stepDay,
    stepMonth: stepMonth,
    isoWeek: isoWeek,
    isoWeekLiteral: isoWeekLiteral,
    monthGrid: monthGrid,
    clockFormats: clockFormats,
    clockFormatRing: clockFormatRing,
    nextClockFormat: nextClockFormat,
    planovaPrefs: planovaPrefs
  }
}
