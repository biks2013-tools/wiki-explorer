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
  `citations` and URL ingest were added to llm-wiki 0.5 for this app).
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
- Commands: ⇧⌘N new wiki, ⌘I add sources, ⌘U check sources, ⌘K ask, ⌘R reload, ⌘[ / ⌘] back/forward.

## Testing

- Unit: link parsing, environment parsing, executable lookup, JSON decoding of every model.
- Runner: a fake `llm-wiki` shell script exercises stdout/stderr streaming and error mapping.
- Integration: the installed `llm-wiki` in a throwaway HOME (`init`, `wikis list`, `pages`, `show` error, `search`).
- Manual/automated UI pass (2026-10-17, accessibility automation): wiki list, page navigation via list and in-page
  links, back, Ask with a live Gemini answer and citation navigation, URL ingest from the sheet, search, New Wiki
  form, markdown and HTML wikis.
