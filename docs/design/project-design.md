# Wiki Explorer — project design

## Purpose

A desktop front end for llm-wiki that lets a person (not an agent) explore their wikis, read pages with their
links, ask questions with linked sources, add content from files or URLs, and create wikis.

## Architecture

```
SwiftUI views ──▶ AppModel (@Observable, @MainActor) ──▶ LLMWikiCLI (WikiExplorerCore) ──▶ llm-wiki --json
                        ▲                                          │
                        └──────── decoded models (Models.swift) ◀──┘
```

- **Single source of truth: the CLI.** The app never reads or writes wiki files (except opening them in Finder /
  the default app on request). New needs are met by extending the CLI (`pages`, `show`, `answerHtml`,
  `citations` and URL ingest were added to llm-wiki 0.5 for this app; `graph --json` in 0.6 for the graph view).
- **Process runner.** `LLMWikiCLI.run` starts `llm-wiki` with an explicit environment, reads stdout fully and
  stderr line by line (progress lines are forwarded to the UI), and turns a non-zero exit into `CLIError`
  (exit 2 = configuration, 3 = LLM provider) carrying the CLI's `error:` line.
- **Environment.** `ShellEnvironment.capture` runs the login shell (`-l -i -c`) and parses `env -0` between
  markers, ignoring anything profiles print. `WIKI_EXPLORER_INHERIT_ENV=1` uses the process environment instead
  (development, tests). The executable is the Settings path if set, else `llm-wiki` on the captured PATH; neither
  → a setup screen, no guessed fallback.
- **Rendering.** Page bodies and answers arrive as sanitised HTML. `HTMLView` (WKWebView, JavaScript off, CSP
  `default-src 'none'`) wraps them in the app's reading style and cancels every navigation, handing the URL to
  `AppModel.follow`: `llmwiki://open?wiki=&page=` opens a page (switching wiki if needed),
  `llmwiki://open?wiki=&raw=` opens the source file, http(s)/mailto go to the default browser.
- **Navigation.** `AppModel` keeps back/forward stacks of `PageLocation(wiki, id)`; a pending location prevents
  the wiki switch from auto-opening that wiki's first page.

- **Images.** `show --json` rewrites a page's relative image paths to absolute `file://` URLs. `HTMLView`
  writes the document to a private temporary file and loads it with `loadFileURL(_:allowingReadAccessTo: /)`,
  because WebKit refuses local subresources for pages loaded from a string.
- **Distribution.** Universal binary, Developer ID signature with the hardened runtime and a secure timestamp,
  notarized and stapled (app and disk image) by `scripts/package.sh`. No entitlements are needed: the app only
  spawns `llm-wiki` (whose `node` is signed on its own) and reads files.

## UI

- Window: `NavigationSplitView` — wikis | pages (or search results) | page; the Ask panel is an inspector on the
  right. First launch opens at up to 1480×920; later launches keep the user's size.
- Sheets: Add Sources (files by drop or panel, URLs one per line, preview toggle, streamed log, result list with
  links to the written pages; ⌘↩ submits), New Wiki (name validated like the registry, no preselected format).
- Sheets (cont.): Check Sources (`sources check` on open, status per URL/file, "Update N Changed" runs
  `sources update` with a streamed log). Add Sources has "Save every page as PDF" (`ingest --render`).
- Commands: ⇧⌘N new wiki, ⌘I add sources, ⌘U check sources, ⌘K ask, ⌘R reload, ⌘F search, ⌘[ / ⌘] back/forward,
  ⇧⌘O open page in browser, ⌥⌘R show page in Finder, ⌥⇧⌘R show its sources in Finder, ⌘G graph, ⇧⌘G show page
  in graph, ⌘0 / ⌘= / ⌘- fit and zoom the graph, ⇧⌘T tour, ⌘/ shortcuts.
  The keys are defined once, in `AppShortcuts` (WikiExplorerCore); the menu commands and the Keyboard Shortcuts
  window both read them, and a test keeps menu shortcuts unique and off the system ones.
- **Open outside the app.** `PageActions` in the page header: an HTML page → "Open in Browser"
  (`AppModel.openInBrowser` opens the file with the app registered for `https:`, so a `.html` file never lands in
  an editor that claims the extension), a markdown page → "Open in Editor"; every page → "Show in Finder"
  (`activateFileViewerSelecting`). Same actions in the context menus of pages, search hits, sources and wikis,
  and in the Page menu.
- **Guided tour** (`GuidedTour.swift`, steps in `Tour.swift` of the core). `TourController` puts a borderless,
  non-activating `NSPanel` as a child window exactly over the main window (frame constraining disabled, kept in
  step on resize/move). The overlay dims with an even-odd path whose hole is fully transparent, so the window
  server passes clicks in the hole to the main window — the user can try the highlighted part during the tour.
  Targets report their window frame through `.tourAnchor(_:)` (an `NSViewRepresentable` background, robust
  across the split view's hosting views); toolbar targets are found as toolbar item views by label, the search
  field as the `NSSearchField` in the window's view tree (also used by ⌘F). A local key monitor handles → ↩ ←
  Esc unless a text field has focus. The Ask step opens the Ask panel and the tour restores it afterwards. The
  tour runs once on first launch (`didShowGuidedTour`) and from Help.
- **⋯ toolbar menu** ("More", after Ask): Take the Tour, Keyboard Shortcuts, Settings….
- **Settings = the CLI's settings file.** The *llm-wiki* tab (`LLMWikiSettingsView`) edits
  `~/.tool-agents/llm-wiki/.env`, the file llm-wiki itself reads (tier 2 of its four tiers), so there is one
  configuration for the app and the terminal and the app keeps no copy. `DotenvFile` (core) reads it with the
  CLI's parsing rules and edits it line-preserving: changed keys are rewritten in place (earlier duplicates
  dropped, `export` kept), new keys appended, emptied keys removed (no empty values: the CLI has no defaults);
  values are quoted so the CLI's parser reads them back unchanged. Saving is atomic, mode 0600 (folder 0700 when
  created), and compares the file with the text loaded first — a change made elsewhere meanwhile asks Reload /
  Overwrite. Fields come from `SettingsCatalog` (the settings of `llm-wiki guide config`: providers as pickers,
  secrets as secure fields with reveal, the browser as an executable with detected Chrome/Chromium/Edge/Brave,
  the wiki root as a folder); credential groups of the providers in use come first, the rest under "Other
  providers"; unknown keys in the file are listed and kept. Keys present in the captured shell environment are
  marked ("set by your shell" / "this file's value wins") without showing shell values. The *Wiki Explorer* tab
  has the llm-wiki path and the masked `llm-wiki config` report.
- **Graph view** (`GraphView.swift`, `GraphScene.swift`; data and physics in the core's `Graph.swift`). The
  detail column switches between the page and the graph (`AppModel.detailMode`, toolbar segmented control, ⌘G).
  `llm-wiki graph --json` is loaded once per wiki (again after changes). `GraphModel.build` turns it into what is
  shown: pages (and optionally cited source files as `raw:` items), one undirected edge per linked pair (marked
  mutual), filtered by hidden kinds and, in Neighbourhood mode, by a breadth-first search of 1–4 steps from the
  selected page. `ForceSimulation` is a deterministic d3-force-style layout: many-body repulsion, edge springs
  (d3 strength/bias), pairwise overlap push, a pull towards each kind's centre (the pools) and weak gravity,
  with alpha cooling until it rests; fixed items for dragging; previous positions are kept by id when the shown
  graph changes, and new items start beside a placed neighbour. `GraphScene` (main actor) owns the simulation,
  an eased camera (auto-fit while the layout first unfolds), hover/selection and pointer handling, and draws with
  a SwiftUI `Canvas` in a `TimelineView`: per kind, the bubbles are drawn into a layer with blur + alpha
  threshold (metaball "liquid" pools); curved threads; flowing drops on the hovered/selected page's links;
  radial-gradient bubbles; greedy non-overlapping labels by importance. Ambient drift (off with Reduce Motion)
  and the flow rest 10 s after the last interaction; the timeline pauses when nothing moves or the window is
  inactive and drops to 15 fps when only drifting (0 % CPU at rest). Mouse wheel / ⌘-scroll zooms around the
  pointer and trackpad scrolling pans (a scroll-wheel monitor behind the canvas); pinch zooms; double-click is a
  `SpatialTapGesture(count: 2)`. Clicking a page selects it everywhere (page list, history); the camera glides to
  pages selected elsewhere. Overlays: controls bar, info card (Open Page, Neighbourhood), legend with counts.
- **Keyboard Shortcuts window** — a `Window` scene listing `AppShortcuts.all` by section as key caps, with a filter.

## Testing

- Unit: link parsing, environment parsing, executable lookup, JSON decoding of every model.
- Runner: a fake `llm-wiki` shell script exercises stdout/stderr streaming and error mapping.
- Integration: the installed `llm-wiki` in a throwaway HOME (`init`, `wikis list`, `pages`, `show` error, `search`).
- Unit (0.3): shortcut display order (⌃⌥⇧⌘), unique menu shortcuts that avoid the system's, filter/grouping; tour
  steps complete and distinct, every shortcut the tour text cites is a real one.
- UI pass 0.3 (2026-10-17): tour auto-start, every step's highlight (columns, toolbar buttons, search field, Ask
  panel), typing into the search field through the highlight, ⌘F, ⌘/ window, Page menu ⇧⌘O (default browser)
  and ⌥⌘R (Finder selection).
- Unit (0.4): graph building (merged directions, source files, neighbourhood depth, hidden kinds cutting paths),
  the simulation resting with linked items closer on average and no overlaps, fixed items, kept positions.
- UI pass 0.4 (2026-10-18, ai-committee, 374 pages / 82 sources): ⌘G, unfolding and auto-fit, hover and selection
  highlighting, wheel zoom around the pointer, double-click opening a page, Show in Graph → neighbourhood of 2,
  Source files, the two tour steps, idle CPU 0 % after the rest delay.
- Manual/automated UI pass (2026-10-17, accessibility automation): wiki list, page navigation via list and in-page
  links, back, Ask with a live Gemini answer and citation navigation, URL ingest from the sheet, search, New Wiki
  form, markdown and HTML wikis.
