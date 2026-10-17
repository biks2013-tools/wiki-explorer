<img src="docs/design/app-icon.png" alt="Wiki Explorer icon" width="128" align="right">

# Wiki Explorer

A native macOS app for the wikis built with [llm-wiki](https://github.com/biks2013-tools/llm-wiki) — Andrej Karpathy's *LLM Wiki* pattern: an
LLM compiles your documents into an interlinked wiki that keeps getting richer.

- **Explore the wikis** — every registered wiki with its description, format (markdown or HTML), page count
  and pending sources; the current wiki is starred.
- **Navigate the pages** — pages grouped by type (entities, concepts, syntheses, sources, …), rendered with
  their links; follow links, go back and forward (⌘[ / ⌘]), see what links to a page and which source files it
  comes from, open a source or reveal the page file.
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
