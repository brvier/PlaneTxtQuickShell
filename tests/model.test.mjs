// Ports of Planova's test/markdown_parser_test.dart and
// test/daily_content_helper_test.dart - the compatibility contract with
// Planova's markdown files - plus cases for the functions this plugin adds
// (toggle, serializers, refill, indicators, keys).
//
// Run with: node --test tests/

import { test } from "node:test"
import assert from "node:assert/strict"
import { createRequire } from "node:module"

const require = createRequire(import.meta.url)
const M = require("../PlanovaModel.js")

const todoHeader = "^#{1,2}\\s+.*Tasks?"
const eventHeader = "^#{1,2}\\s+.*Events?"

// ---- MarkdownParser.parseTasks ----------------------------------------------

test("parseTasks: parses unchecked and checked todos", () => {
  const content = `
# Tasks
- [ ] buy milk
- [x] call mom
* [ ] star bullet
+ [x] plus bullet
`
  const tasks = M.parseTasks(content)
  assert.equal(tasks.length, 4)
  assert.equal(tasks[0].text, "buy milk")
  assert.equal(tasks[0].done, false)
  assert.equal(tasks[1].text, "call mom")
  assert.equal(tasks[1].done, true)
  assert.equal(tasks[2].done, false)
  assert.equal(tasks[3].done, true)
})

test("parseTasks: tolerates indentation and spaces inside brackets", () => {
  const tasks = M.parseTasks("  - [ x ] indented done\n\t- [  ] tab todo")
  assert.equal(tasks.length, 2)
  assert.equal(tasks[0].done, true)
  assert.equal(tasks[1].done, false)
})

test("parseTasks: ignores non-todo lines and empty checkboxes without text", () => {
  const content = `
just a note
- a bullet
- [ ]
# header
`
  assert.deepEqual(M.parseTasks(content), [])
})

test("parseTasks: returns empty list for empty content", () => {
  assert.deepEqual(M.parseTasks(""), [])
})

test("parseTasks: uppercase X is not done (Planova rule)", () => {
  // [X] doesn't match the todo shape at all in Planova's regexes.
  assert.deepEqual(M.parseTasks("- [X] shouty"), [])
})

test("parseTasks: reports the line index of each task", () => {
  const tasks = M.parseTasks("# Tasks\n- [ ] a\ntext\n- [x] b")
  assert.equal(tasks[0].lineIndex, 1)
  assert.equal(tasks[1].lineIndex, 3)
})

// ---- MarkdownParser.parseEvents ---------------------------------------------

test("parseEvents: parses event lines with @HH:MM", () => {
  const content = `
## Events
- @09:30 standup meeting
- @14:05 dentist
`
  const events = M.parseEvents("20260710", content)
  assert.equal(events.length, 2)
  assert.equal(events[0].title, "standup meeting")
  assert.equal(events[0].hour, 9)
  assert.equal(events[0].minute, 30)
  assert.equal(events[1].hour, 14)
  assert.equal(events[1].minute, 5)
})

test("parseEvents: accepts single-digit hour", () => {
  const events = M.parseEvents("20260710", "- @9:00 breakfast")
  assert.equal(events.length, 1)
  assert.equal(events[0].hour, 9)
})

test("parseEvents: ignores @time mentions without a bullet", () => {
  assert.deepEqual(M.parseEvents("20260710", "meet me at @9:00 tomorrow"), [])
})

test("parseEvents: collects following lines as description, stopping at blank/todo", () => {
  const content = `
- @10:00 review
  bring the notes
  room 4B

- @11:00 next
`
  const events = M.parseEvents("20260710", content)
  assert.equal(events.length, 2)
  assert.equal(events[0].description, "bring the notes\nroom 4B")
  assert.equal(events[1].description, "")
})

test("parseEvents: caps description at 4 lines", () => {
  const events = M.parseEvents("20260710", "- @10:00 x\na\nb\nc\nd\ne\nf")
  assert.equal(events[0].description, "a\nb\nc\nd")
})

test("parseEvents: returns empty list for an invalid date string", () => {
  assert.deepEqual(M.parseEvents("not-a-date", "- @10:00 x"), [])
})

// ---- MarkdownParser.parseNotes ------------------------------------------------

test("parseNotes: keeps free text and plain bullets, strips markers", () => {
  const content = `
# Header
- [ ] a todo
- @10:00 an event
- plain bullet note
free text line
`
  assert.deepEqual(M.parseNotes(content), ["plain bullet note", "free text line"])
})

// ---- Line classifiers ----------------------------------------------------------

test("isTodoLine", () => {
  assert.equal(M.isTodoLine("- [ ] x"), true)
  assert.equal(M.isTodoLine("- [x] x"), true)
  assert.equal(M.isTodoLine("- x"), false)
})

test("isEventLine", () => {
  assert.equal(M.isEventLine("- @10:00 x"), true)
  assert.equal(M.isEventLine("- 10:00 x"), false)
  assert.equal(M.isEventLine("@10:00 x"), false)
})

// ---- DailyContentHelper.insertAfterLastTodo -------------------------------------

test("insertAfterLastTodo: inserts after the last todo in the section", () => {
  const content = `## Tasks
- [ ] first
- [x] second

## Notes
something`
  const lines = M.insertAfterLastTodo(content, "- [ ] third", todoHeader).split("\n")
  const idx = lines.indexOf("- [ ] third")
  assert.ok(idx > lines.indexOf("- [x] second"))
  assert.ok(idx < lines.indexOf("## Notes"))
})

test("insertAfterLastTodo: inserts right after the header when the section is empty", () => {
  const content = `## Tasks

## Notes`
  const lines = M.insertAfterLastTodo(content, "- [ ] new", todoHeader).split("\n")
  assert.equal(lines[lines.indexOf("## Tasks") + 1], "- [ ] new")
})

test("insertAfterLastTodo: appends at end when no header matches", () => {
  const result = M.insertAfterLastTodo("just text", "- [ ] new", todoHeader)
  assert.ok(result.trim().endsWith("- [ ] new"))
})

test("insertAfterLastTodo: appends at end when regex is empty", () => {
  assert.ok(M.insertAfterLastTodo("text", "- [ ] new", "").includes("- [ ] new"))
})

test("insertAfterLastTodo: works against the real Planova template headers", () => {
  const result = M.insertAfterLastTodo(M.DEFAULT_TEMPLATE, "- [ ] new", M.DEFAULT_TODO_HEADER)
  const lines = result.split("\n")
  assert.equal(lines[lines.indexOf("# ✅ Todos") + 1], "- [ ] new")
  // Events and Logs sections untouched.
  assert.ok(result.includes("# 📅 Events\n\n"))
  assert.ok(result.includes("# 📝 Logs"))
})

// ---- DailyContentHelper.insertAfterLastEvent -------------------------------------

test("insertAfterLastEvent: inserts after the last event of the section", () => {
  const content = `## Events
- @09:00 standup

## Tasks`
  const lines = M.insertAfterLastEvent(content, "- @10:00 review", eventHeader).split("\n")
  assert.equal(lines.indexOf("- @10:00 review"), lines.indexOf("- @09:00 standup") + 1)
})

// ---- DailyContentHelper.insertEventsChronologically --------------------------------

test("insertEventsChronologically: merges sorted by time, skipping duplicates", () => {
  const content = `## Events
- @12:00 lunch
`
  const result = M.insertEventsChronologically(
    content,
    ["- @15:00 coffee", "- @08:00 gym", "- @12:00 lunch"],
    eventHeader
  )
  const lines = result.split("\n").filter(l => l.startsWith("- @"))
  assert.equal(lines.filter(l => l.includes("lunch")).length, 1)
  assert.ok(lines.findIndex(l => l.includes("gym")) < lines.findIndex(l => l.includes("coffee")))
})

test("insertEventsChronologically: appends a fresh block when no events section exists", () => {
  const result = M.insertEventsChronologically("notes only", ["- @08:00 gym"], eventHeader)
  assert.ok(result.includes("- @08:00 gym"))
})

// ---- DailyContentHelper.insertAtEndOfSection ----------------------------------------

test("insertAtEndOfSection: inserts before the next header", () => {
  const content = `## Log
first entry

## Notes
note`
  const lines = M.insertAtEndOfSection(content, "- 10:00 did things", "^#{1,2}\\s+.*Log").split("\n")
  assert.equal(lines.indexOf("- 10:00 did things"), lines.indexOf("first entry") + 1)
})

// ---- DailyContentHelper.insertAfterHeader --------------------------------------------

test("insertAfterHeader: inserts right after the matching header", () => {
  const content = `## Tasks
- [ ] existing`
  const lines = M.insertAfterHeader(content, "- [ ] new", todoHeader).split("\n")
  assert.equal(lines[lines.indexOf("## Tasks") + 1], "- [ ] new")
})

test("insertAfterHeader: falls back to append on invalid regex", () => {
  assert.ok(M.insertAfterHeader("text", "new", "([").includes("new"))
})

// ---- Mixed-generation headers (real files mix both) -------------------------------

test("section regexes match both header generations in one file", () => {
  const content = `# 📅 Events

- @10:00 emoji-header event

## Tasks
- [ ] old-style task
`
  const afterTodo = M.insertAfterLastTodo(content, "- [ ] added", M.DEFAULT_TODO_HEADER)
  const lines = afterTodo.split("\n")
  assert.equal(lines.indexOf("- [ ] added"), lines.indexOf("- [ ] old-style task") + 1)

  const afterEvent = M.insertAfterLastEvent(content, "- @11:00 added", M.DEFAULT_EVENT_HEADER)
  const eLines = afterEvent.split("\n")
  assert.equal(eLines.indexOf("- @11:00 added"), eLines.indexOf("- @10:00 emoji-header event") + 1)
})

// ---- toggleTaskAtLine -----------------------------------------------------------------

test("toggleTaskAtLine: flips [ ] to [x] and back, preserving prefix and text", () => {
  const content = "# Tasks\n  * [ ] keep my bullet"
  const once = M.toggleTaskAtLine(content, 1)
  assert.equal(once, "# Tasks\n  * [x] keep my bullet")
  const twice = M.toggleTaskAtLine(once, 1)
  assert.equal(twice, "# Tasks\n  * [ ] keep my bullet")
})

test("toggleTaskAtLine: normalizes odd bracket spacing to canonical form", () => {
  assert.equal(M.toggleTaskAtLine("- [ x ] spaced", 0), "- [ ] spaced")
})

test("toggleTaskAtLine: leaves non-todo lines untouched", () => {
  assert.equal(M.toggleTaskAtLine("plain text", 0), "plain text")
  assert.equal(M.toggleTaskAtLine("- [ ] x", 5), "- [ ] x")
})

// ---- Serializers -----------------------------------------------------------------------

test("serializers produce Planova's canonical lines", () => {
  assert.equal(M.todoLineFor("  task  "), "- [ ] task")
  assert.equal(M.eventLineFor(9, 5, "breakfast"), "- @09:05 breakfast")
  assert.equal(M.eventLineFor(14, 30, "dentist"), "- @14:30 dentist")
  assert.equal(M.logLineFor(8, 7, "note"), "- 08:07 note")
})

// ---- Refill ------------------------------------------------------------------------------

test("collectRefillTodos: undone todos from strictly earlier days, newest first", () => {
  const dailies = [
    { key: "20260810", content: "# Todos\n- [ ] old-a\n- [x] done" },
    { key: "20260812", content: "# Todos\n- [ ] newer-b" },
    { key: "20260815", content: "# Todos\n- [ ] same-day-excluded" },
    { key: "20260816", content: "# Todos\n- [ ] future-excluded" }
  ]
  const todos = M.collectRefillTodos(dailies, "20260815")
  assert.deepEqual(todos.map(t => t.content), ["- [ ] newer-b", "- [ ] old-a"])
  assert.deepEqual(todos.map(t => t.sourceKey), ["20260812", "20260810"])
})

test("removeTodoLines: removes by trim-equality only", () => {
  const content = "## Tasks\n- [ ] gone\n  - [ ] gone\n- [ ] stays\n* [ ] different bullet stays"
  const result = M.removeTodoLines(content, ["- [ ] gone"])
  assert.equal(result, "## Tasks\n- [ ] stays\n* [ ] different bullet stays")
})

test("refill round trip matches Planova's insert semantics", () => {
  const target = M.DEFAULT_TEMPLATE
  const inserted = M.insertAfterLastTodo(target, "- [ ] moved", M.DEFAULT_TODO_HEADER)
  assert.ok(inserted.split("\n").indexOf("- [ ] moved") ===
    inserted.split("\n").indexOf("# ✅ Todos") + 1)
})

// ---- Indicators ----------------------------------------------------------------------------

function summaryFor(content, key = "20260816") {
  return M.daySummary(key, content)
}

test("dayIndicator: all done → allDone", () => {
  assert.equal(M.dayIndicator(summaryFor("- [x] a\n- [x] b")).kind, "allDone")
})

test("dayIndicator: 1-3 undone → dots with count", () => {
  const one = M.dayIndicator(summaryFor("- [ ] a"))
  assert.deepEqual(one, { kind: "dots", count: 1 })
  const three = M.dayIndicator(summaryFor("- [ ] a\n- [ ] b\n- [ ] c\n- [x] d"))
  assert.deepEqual(three, { kind: "dots", count: 3 })
})

test("dayIndicator: more than 3 undone → count badge", () => {
  const four = M.dayIndicator(summaryFor("- [ ] a\n- [ ] b\n- [ ] c\n- [ ] d"))
  assert.deepEqual(four, { kind: "count", count: 4 })
})

test("dayIndicator: events only → eventDot; neither → fileDot; no file → none", () => {
  assert.equal(M.dayIndicator(summaryFor("- @10:00 meeting")).kind, "eventDot")
  assert.equal(M.dayIndicator(summaryFor("just a note")).kind, "fileDot")
  assert.equal(M.dayIndicator(null).kind, "none")
})

// ---- Keys and grid ----------------------------------------------------------------------------

test("keyFor and parseKey round-trip with zero padding", () => {
  assert.equal(M.keyFor(2026, 0, 5), "20260105")
  assert.deepEqual(M.parseKey("20260105"), { year: 2026, month: 0, day: 5 })
  assert.equal(M.parseKey("not-a-date"), null)
  assert.equal(M.parseKey("20261301"), null)
})

test("stepDay crosses month boundaries", () => {
  assert.equal(M.stepDay("20260131", 1), "20260201")
  assert.equal(M.stepDay("20260301", -1), "20260228")
  assert.equal(M.stepDay("20260101", -7), "20251225")
})

test("monthGrid: six Monday-first weeks with today and selected marked", () => {
  const weeks = M.monthGrid(2026, 7, "20260816", "20260803") // August 2026
  assert.equal(weeks.length, 6)
  // August 1, 2026 is a Saturday; Monday-first row starts July 27.
  assert.equal(weeks[0].days[0].key, "20260727")
  assert.equal(weeks[0].days[0].weekday, 1)
  const allDays = weeks.flatMap(w => w.days)
  assert.equal(allDays.find(d => d.key === "20260816").today, true)
  assert.equal(allDays.find(d => d.key === "20260803").selected, true)
  assert.equal(allDays.filter(d => d.inMonth).length, 31)
})

// ---- Prefs -----------------------------------------------------------------------------------

test("planovaPrefs: reads flutter.-prefixed keys, null when absent", () => {
  const prefs = M.planovaPrefs(JSON.stringify({
    "flutter.storage_path": "/home/user/Org",
    "flutter.todo_header_regex": "^#\\s+Custom"
  }))
  assert.equal(prefs.storagePath, "/home/user/Org")
  assert.equal(prefs.todoHeaderRegex, "^#\\s+Custom")
  assert.equal(prefs.dailyTemplate, null)
  assert.equal(M.planovaPrefs("garbage").storagePath, null)
})
