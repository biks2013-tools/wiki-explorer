<img src="docs/design/app-icon.png" alt="Wiki Explorer icon" width="128" align="right">

# Wiki Explorer

A native macOS app for the wikis built with [llm-wiki](https://github.com/biks2013-tools/llm-wiki) — Andrej Karpathy's *LLM Wiki* pattern: an
LLM compiles your documents into an interlinked wiki that keeps getting richer.

- **Explore the wikis** — every registered wiki with its description, format (markdown or HTML), page count
  and pending sources; the current wiki is starred.
- **Navigate the pages** — pages grouped by type (entities, concepts, syntheses, sources, …), rendered with
  their links; follow links, go back and forward (⌘[ / ⌘]), see what links to a page and which source files it
  comes from, open a source or reveal the page file.
- **Graph** (⌘G, or the Page / Graph switch in the toolbar) — the wiki as a living map: every page is a
  bubble sized by its links, every link a thread, and pages of the same kind (entities, concepts, sources, …)
  melt together into soft coloured pools. The layout settles like a liquid and moves again when you drag a
  bubble — its neighbours follow. Hover to light up a page's links (drops flow along them), click to select
  it, double-click or ↩ to open it. Drag the background to move, pinch or ⌘-scroll to zoom, ⌘0 fits.
  "Neighbourhood" shows only the pages 1–4 links away from the selected one (⇧⌘G from a page shows its
  neighbourhood); "Source files" adds the original documents; the legend hides or shows each kind; "Highlight
  pages" rings the pages whose title matches.
- **Search** — instant full-text search of one wiki or of all wikis.
- **Ask** (⌘K) — ask a question of one wiki, several, or all; the answer cites its pages and every citation is a
  link. Optionally save the answer as a page of the wiki.
- **Add sources** (⌘I) — drop or choose files (markdown, text, PDF, Word, PowerPoint, Excel, images) or paste
  URLs of web pages and online documents; preview what the LLM would write, or add them straight away.
- **Keep sources current** (⌘U) — downloaded web pages and files added from outside the wiki are compared
  with the copy the wiki was built from (SHA-256; web pages by their text, after an ETag/Last-Modified check);
  changed ones are re-ingested as new copies with one click.
- **Pages built by JavaScript** — detected when added and saved as PDF through a headless browser (set
  `LLM_WIKI_BROWSER` to Chrome/Chromium/Edge/Brave); "Save every page as PDF" forces it.
- **Images** — pictures in pages (for example from `raw/assets/`) are displayed.
- **Create wikis** (⇧⌘N) — name, description, page format and folder; registered automatically.
- **Open outside the app** — "Open in Browser" (⇧⌘O) opens a page of an HTML wiki in your default web browser,
  where its links keep working; "Show in Finder" (⌥⌘R) selects any page file (markdown pages also open in
  your editor); ⌥⇧⌘R selects the page's source documents. The same actions are on the right-click menu of
  pages, search results, sources and wikis.
- **Guided tour** (the toolbar's ⋯ menu or Help › Take the Tour, ⇧⌘T) — runs on first launch: each step dims the window except the
  part it explains (wiki list, pages, search, page, open-outside buttons, links and sources, the graph, Ask, Add Sources,
  Check Sources). Clicks inside the highlighted area reach the app, so you can try each part as you go;
  → / ↩ next, ← back, Esc ends.
- **Settings** (⌘, or the toolbar's ⋯ menu) — the *llm-wiki* tab edits the command line's own settings file,
  `~/.tool-agents/llm-wiki/.env`, so the app and `llm-wiki` in a terminal always share one configuration:
  chat model, document parser, embeddings, wiki selection, headless browser and every provider's credentials.
  Comments and other lines of the file are kept; an empty field removes the setting (no defaults); keys are
  hidden unless you reveal them; settings that come from your shell are marked (their values are not shown);
  saving refuses to overwrite changes made to the file elsewhere meanwhile. The *Wiki Explorer* tab chooses
  which `llm-wiki` runs and shows what it resolves (`llm-wiki config`, secrets masked).
- **Keyboard shortcuts** (the toolbar's ⋯ menu or Help › Keyboard Shortcuts, ⌘/) — every key of the app in one window, grouped and
  filterable. ⌘F jumps to the search field.

## Requirements

- macOS 14 or later, Swift 5.10+ toolchain (Xcode or Command Line Tools) to build.
- The `llm-wiki` command ([biks2013-tools/llm-wiki](https://github.com/biks2013-tools/llm-wiki): `pnpm install && pnpm link:global`) with its settings in
  `~/.tool-agents/llm-wiki/.env` (chat model, parser model for documents and images; see `llm-wiki guide config`).

## Install

Download `WikiExplorer-<version>.dmg` (or the zip) and drag the app to Applications. It is a universal app
(Apple silicon and Intel), signed with a Developer ID certificate and notarized by Apple, so it opens on any
Mac with macOS 14+ without Gatekeeper warnings. `llm-wiki` must be installed on that Mac (see `INSTALL.txt`).

## Build and run

```bash
scripts/build-app.sh --adhoc --install                       # local build for this Mac
WIKI_EXPLORER_SIGN_IDENTITY=<sha1> scripts/build-app.sh      # Developer ID signed (hardened runtime)
WIKI_EXPLORER_SIGN_IDENTITY=<sha1> NOTARY_PROFILE=<profile> scripts/package.sh
                                                             # test, sign, notarize, staple → dist/*.zip, *.dmg
swift test                                                   # core tests
```

## How it works

Wiki Explorer contains no wiki logic of its own. It runs `llm-wiki` with `--json` and renders what it returns:

| In the app | CLI |
|---|---|
| wiki list | `llm-wiki wikis list --json` |
| page list | `llm-wiki --wiki <w> pages --json` |
| page view, links, backlinks | `llm-wiki --wiki <w> show <page> --json` (HTML with `llmwiki://` links) |
| search | `llm-wiki [--wiki <w>] search "<q>" --json [--all-wikis]` |
| ask | `llm-wiki --wiki <w> query "<q>" --json [--file]` or `query "<q>" --json --wikis a,b` |
| add sources | `llm-wiki --wiki <w> ingest <files and URLs> --json [--dry-run]` |
| new wiki | `llm-wiki init <dir> --format markdown\|html --name <n> [--description d] [--use]` |
| check / update sources | `llm-wiki --wiki <w> sources check --json` / `sources update --json` |

An app started from the Finder does not inherit your shell's PATH or exported API keys, so Wiki Explorer asks
your login shell for its environment once at start-up and runs `llm-wiki` with it (the values are never shown or
logged). **Settings** (⌘,) shows which `llm-wiki` is used, lets you set its path explicitly, and shows the
resolved configuration (`llm-wiki config`, keys masked).

LLM operations (ask, add sources) take from a few seconds to a minute per source; their progress is streamed
from the CLI into the panel.
