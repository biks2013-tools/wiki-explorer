# Issues - Pending Items

## Pending items

- A running ask or ingest cannot be cancelled from the UI; the CLI process runs to completion.
- The app does not watch the registry or the wiki folders: changes made elsewhere (CLI, agents) appear after
  ⌘R / the reload button, or after the next action that refreshes.
- Distribution is a notarized zip/dmg; there is no auto-update and no Homebrew cask yet.
- The sheets' controls are not exposed to the accessibility tree in the automation used for testing (SwiftUI
  sheets); keyboard shortcuts (⌘↩, Esc) work. Revisit if VoiceOver users report problems.
- Answers are shown when complete (no token streaming); the CLI's progress lines are shown meanwhile.

## Completed items

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

