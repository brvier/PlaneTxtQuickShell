# Changelog

## [0.1.2] - 2026-09-11

### Fixed
- Panel could not be closed on Omarchy 4.0.3: the bar handed to plugins is now a PluginBarApi facade whose `centerHoverRevealSuppressed` is read-only, so `close()` threw before hiding. Use the facade's setter, with the direct property as fallback for older shells.
- Escape went dead after a focused text field was hidden (switching tab from the header during quick add or a notes search, switching the entry type from the hour field). The key catcher now takes focus back whenever the fields stop editing, and Ctrl+E/T/L return the cursor to the title field.

## [0.1.1] - 2026-09-10

### Added
- Screenshots in the README and a root `preview.png` for the marketplace card.

### Fixed
- README: real install URL, working `omarchy-shell <target> <method>` IPC examples, and new Uninstall, Dependencies and License sections for the Omarchy plugin marketplace listing.

## [0.1.0] - 2026-08-19

### Added
- Planova panel plugin for Omarchy 4 quickshell: replaces the omarchy.clock bar widget with the same date/time label plus an undone-todo badge, and a popup providing a month calendar with per-day indicators, day view of events/tasks/notes, quick add, todo toggle, refill, and a notes browser. Reads and writes Planova's markdown files with the exact parsing and insertion rules ported from Planova, atomic writes, and an inotify watcher for live bidirectional sync.
- Keyboard shortcuts for every add and edit action: per-type quick add from the calendar, Ctrl+E/Ctrl+T/Ctrl+L to switch entry type inside the form, r to rename a note.

### Changed
- Shift-free shortcuts: e adds an event, g adds a log, o opens the day file in the editor (Shift variants kept as aliases).
