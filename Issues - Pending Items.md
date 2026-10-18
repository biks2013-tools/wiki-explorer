# Issues - Pending Items

## Pending items

- A running ask or ingest cannot be cancelled from the UI; the CLI process runs to completion.
- The app does not watch the registry or the wiki folders: changes made elsewhere (CLI, agents) appear after
  ⌘R / the reload button, or after the next action that refreshes.
- Distribution is a notarized zip/dmg; there is no auto-update and no Homebrew cask yet.
- The sheets' controls are not exposed to the accessibility tree in the automation used for testing (SwiftUI
  sheets); keyboard shortcuts (⌘↩, Esc) work. Revisit if VoiceOver users report problems.
- Answers are shown when complete (no token streaming); the CLI's progress lines are shown meanwhile.

- Tour: while a text field has focus, → and ← move the cursor instead of the tour (use the card's buttons or
  Esc). The tour's card buttons render grey rather than blue because the overlay panel never becomes key (by
  design, so the main window keeps the keyboard).

- Settings: a `./.env` in a working directory and CLI flags still override the file for terminal use; the app
  runs llm-wiki from `/`, so only the shell environment and this file apply to it.

## Completed items

- 2026-10-18 — 0.4.0: liquid graph view (⌘G) on the new `llm-wiki graph --json`. Fixed during UI testing: wheel
  zoom ran the wrong way and too fast; a click on a bubble moved the camera so a double-click missed (the camera now
  stays put for clicks made in the graph; double-click is a `SpatialTapGesture`); with a page selected every other
  label was hidden (now only hovering fades the rest); the ambient motion kept ~26 % CPU at rest (now 15 fps when
  only drifting and paused 10 s after the last interaction: 0 %). Note: synthetic double-clicks without a click
  count (some automation tools) only select — real double-clicks open.
- 2026-10-17 — First version (0.1.0): wikis, pages, links/backlinks/sources, search (one/all wikis), Ask with
  linked citations (one/several/all wikis, optional filing), Add Sources (files + URLs, preview), New Wiki,
  Settings. Fixed during UI testing: window opened at minimum size (now sized on first launch), the Ask
  inspector squeezed the page column (page column minimum width), inspector content was vertically centred,
  the search field was not shown (moved to the toolbar), Return could not submit the URL sheet (⌘↩), bare page
  ids shown as link text (titles shown instead, in llm-wiki `show`/`query`).
- 2026-10-17 — 0.2.0: local images in pages render (document loaded from a temporary file with read access, as
  WebKit blocks local images in string-loaded pages); Check Sources sheet (⌘U) for SHA-256 change detection of
  outside sources with one-click update; "Save every page as PDF" in Add Sources; universal build signed with
  Developer ID (hardened runtime) and notarized by `scripts/package.sh`.
- 2026-10-17 — 0.2.1: new app icon (dark ink tile, paper pages with a copper graph of linked nodes, copper
  magnifying glass enlarging one node; vector-drawn by `scripts/make-icon.swift`, simplified at 64 px and
  below); links updated after llm-wiki moved to biks2013-tools/llm-wiki.
- 2026-10-17 — 0.3.0: guided tour (first launch, Help › Take the Tour ⇧⌘T) with click-through highlights;
  "Open in Browser" (default browser, HTML pages) and "Show in Finder" (any page, its sources, search hits,
  wikis) in the page header, context menus and a new Page menu; Keyboard Shortcuts window (⌘/) built from one
  shortcut catalogue; ⌘F focuses the search field. Tour, shortcuts and Settings are also in a ⋯ (More) menu in the toolbar. Settings edits the CLI's own `~/.tool-agents/llm-wiki/.env` (line-preserving, 0600, conflict check), so app and terminal share one configuration; tested live by setting LLM_WIKI_BROWSER (then restored). Fixed during testing: the overlay panel was moved by macOS's
  frame constraining (overridden), the search field was not an NSSearchToolbarItem (found in the view tree), the
  page header truncated its buttons (path label gives way).
