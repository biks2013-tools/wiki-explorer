<structure-and-conventions>
## Structure & Conventions — Documentation Map

<!-- Maintained automatically. The master copy lives at
     ~/.claude/structure-and-conventions.md (claude-workdocs repo) and the SessionStart
     hook ~/.claude/scripts/sync-claude-md.sh keeps this copy of the block up to date —
     edit the master, never this block. The block is committed with the repository on
     purpose: it tells anyone (human or agent) working with this repo where the
     project's documentation lives and how to read and maintain it. -->

### Where the documentation lives

- `docs/plans/` — every plan, one file per plan, named `plan-NNN-<indicative-description>.md`.
- `docs/design/` — all other planning and design documents:
  - `project-design.md` — the complete, always-current project design; update it with every new design or design change.
  - `project-functions.md` — the registry of all functional requirements and feature descriptions.
  - `configuration-guide.md` — the project's configuration guide, when one exists (structure below).
- `docs/reference/` — all reference material collected for the project.
- `docs/refined_requests/` — every refined request specification (create the folder if missing), one file per request named `refined-request-NNN-<slug>.md`. `NNN` is a zero-padded three-digit sequential number: the next number is the highest `NNN` already present in the folder plus one, starting at `001` — and when the category has an archive history branch, the archive's numbering counts too (see "Archiving historical documents" below). `<slug>` is the request slug reused by all downstream artifacts of the same request.
- `docs/prompts/` — every prompt created while working on the project (create the folder if missing), one file per prompt named `NNN-<indicative-description>.md`. `NNN` is a zero-padded three-digit sequential number: the next number is the highest `NNN` already present in the folder plus one, starting at `001` — and when the category has an archive history branch, the archive's numbering counts too (see "Archiving historical documents" below). The description states the prompt's use and purpose.
- `docs/tools/<tool-name>.md` — one dedicated documentation file per project tool.
- `test_scripts/` — every test script goes here; create the folder if it doesn't exist.
- `Issues - Pending Items.md` (project root) — the register of every issue, pending item, inconsistency, or discrepancy detected while working on the project. Pending items come first (most critical and important on top), completed items after. Whenever a defect or issue is fixed, check this file for an item to remove.

### How to use the documentation

- Every time an issue is solved, it must be resolved AND both the issue and the solution must be thoroughly documented.
- This file's "Tools" section (when present) lists each project tool with a one-or-two-sentence description of what it is capable of and the relative path to its dedicated documentation file under `docs/tools/` — retrieve the full documentation from there whenever it is needed. Full tool documentation must never be inlined into this file.
- Before writing any code script, consult the "Tools" section and the documentation under `docs/tools/` to check whether the planned code fits the scope of an existing tool. If so, implement it as an extension of that tool; otherwise build a generic, abstract version of the code as a new tool in the project's toolset, document it under `docs/tools/`, and reference it in the "Tools" section. The goal is to progressively grow the tools needed to test, evaluate, generate data, collect information, etc., and reuse them consistently.

### Archiving historical documents (history branches)

- A project MAY move accumulated historical, write-once process artifacts — deployment reports, codebase scans, refined requests, plans, session handoffs, and similar — off the default branch to keep its documentation lean. Living, authoritative documents (`project-design.md`, `project-functions.md`, the guides, tool docs, the issue register) are never archived.
- Each archived category gets a dedicated **orphan, docs-only branch** named `<category>-history`, whose tree contains ONLY that category's files at their original repository paths — so retrieval paths never change: `git show <category>-history:<original-path>`, no branch switching required. A pointer note/README stays in the category's folder on the default branch stating the branch name, the retrieval command, and (for numbered categories) the next number. Archive branches are append-only: never rebase, rewrite, delete, or merge them.
- **Numbering across the archive**: for every `NNN`-numbered folder, the next number is `max(highest NNN in the folder, highest NNN on the category's archive branch) + 1`. Before creating the FIRST document of a numbered category, check whether an archive branch exists for it (the folder's README/pointer note, or `git branch --list --all '*-history'`) and continue from the archive's highest number — never restart at `001`, never reuse an archived number. The archive branch is authoritative over the pointer note's recorded "next number" if they disagree.
- **Migration** runs in a temporary linked worktree so the main checkout — and any uncommitted changes in it — is never disturbed: `git worktree add <tmp> <category>-history` (first-time archiving: `git worktree add --detach <tmp> <default-branch>`, then inside it `git switch --orphan <category>-history` and `git checkout <default-branch> -- <category-paths>`); bring the new artifacts over at their original paths and commit ONLY the category's files; then on the default branch `git rm` the migrated files, update the pointer note, and commit referencing the archive commit. Verify with `git ls-tree -r <category>-history --name-only` and a `git show` spot-check.
- The project's concrete category → branch registry (which categories are archived, under which branch names) is project-specific and lives OUTSIDE this synced block — typically a "Document Archiving Strategy" section in the project's CLAUDE.md.

<configuration-guide>
- A configuration guide, when requested, is created at `docs/design/configuration-guide.md` and explains:
  - When multiple configuration options exist (config file, env variables, CLI params, etc.), what the options are and the priority of each one.
  - The purpose and use of each configuration variable.
  - How the user can obtain such a configuration variable.
  - The recommended approach for storing or managing the variable.
  - Which options exist for the variable and what each option means for the project.
  - Any default value the parameter has.
  - For configuration parameters that expire (e.g., PAT keys, tokens), propose adding a parameter that captures the expiration date, so the app or service can proactively warn users to renew.
</configuration-guide>

</structure-and-conventions>

# wiki-explorer — Wiki Explorer

Native macOS (SwiftUI) app to explore and grow the user's llm-wiki wikis: list the registered wikis, browse
their pages with links and backlinks, search one or all wikis, ask questions whose answers link to the cited
pages, add files or web pages (URLs), and create new wikis. It is a front end only: every operation runs the
`llm-wiki` CLI from the sibling project `../wiki-v2` through its `--json` output.

## Project layout

- `Package.swift` — SwiftPM, macOS 14+, Swift 5 language mode.
- `Sources/WikiExplorerCore/` — no UI: `LLMWikiCLI` (runs `llm-wiki`, streams stderr, decodes JSON, maps exit
  codes to `CLIError`), `Models.swift` (the JSON shapes of `wikis list`, `pages`, `show`, `search`, `query`,
  `ingest`), `LinkTarget` (the `llmwiki://open?wiki=&page=|raw=` scheme), `ShellEnvironment` (reads the login
  shell's environment so a Finder-launched app finds `llm-wiki`, `node` and the API keys).
- `Sources/WikiExplorer/` — the app: `AppModel` (state, navigation history, actions), `MainView` (three-column
  split view + Ask inspector), `WikiSidebar`, `PageListColumn` (pages by type, search), `PageDetailView`
  (`HTMLView` WebKit page + links/backlinks/sources), `AskPanel`, `IngestSheet`, `NewWikiSheet`, `SettingsView`, `GuidedTour` (tour overlay
  panel, `.tourAnchor`), `ShortcutsWindow` (Keyboard Shortcuts window, `AppShortcut` → `KeyboardShortcut`),
  `SettingsView` (llm-wiki tab = editor of `~/.tool-agents/llm-wiki/.env`; Wiki Explorer tab).
- `Sources/WikiExplorerCore/DotenvFile.swift` / `SettingsCatalog.swift` — line-preserving reader/writer of the
  CLI's settings file (same parsing rules as wiki-v2 `parseDotenv`) and the list of settings shown. When llm-wiki
  gains a setting, add it to the catalogue. Never log or print values from that file.
- `Sources/WikiExplorerCore/Graph.swift` — `WikiGraph` (`llm-wiki graph --json`), `GraphModel.build` (what the graph
  view shows: kinds, source files, neighbourhood) and `ForceSimulation` (deterministic force layout). The app side is
  `GraphScene.swift` (camera, pointer, Canvas drawing with blur + alpha-threshold "liquid" pools) and `GraphView.swift`
  (the view, controls, info card, legend, scroll-wheel catcher). Keep the timeline paused when nothing moves.
- `Sources/WikiExplorerCore/Shortcuts.swift` / `Tour.swift` — the shortcut catalogue (`AppShortcuts`, the only
  place keys are defined) and the tour steps. Add a menu command's key there, and update the tour text when a
  step's area or shortcut changes (tests check both).
- `Tests/WikiExplorerCoreTests/` — XCTest: links, shell-environment parsing, the CLI runner against a fake
  script, JSON decoding, and an integration test against the installed `llm-wiki` in a throwaway HOME.
- `scripts/build-app.sh` — universal release build → `build/WikiExplorer.app` (Info.plist, icon), signed with
  the Developer ID in `WIKI_EXPLORER_SIGN_IDENTITY` (hardened runtime, timestamp) or `--adhoc`; `--install`
  copies it to `/Applications/Wiki Explorer.app`. `scripts/package.sh` (needs `NOTARY_PROFILE` too) runs the
  tests, verifies the signature, notarizes + staples the app and a disk image (`packaging/macos/INSTALL.txt`)
  into `dist/`. `scripts/make-icon.swift` draws the icon.
- `Sources/WikiExplorer/SourcesSheet.swift` — `sources check` / `sources update` (outside-source change detection).

## Commands

```
swift build                 # debug build
swift test                  # core tests (the integration test needs llm-wiki on PATH)
scripts/build-app.sh --adhoc [--install]                               # local build
WIKI_EXPLORER_SIGN_IDENTITY=<sha1> NOTARY_PROFILE=<profile> scripts/package.sh   # distributable, notarized
WIKI_EXPLORER_INHERIT_ENV=1 build/WikiExplorer.app/Contents/MacOS/WikiExplorer   # run with the terminal's env
```

## Rules specific to this project

- All wiki logic lives in llm-wiki. If the app needs data the CLI does not expose, add it to the CLI (with
  `--json`, tests and guide updates in wiki-v2) instead of reading or writing wiki files from Swift.
- Keep `Models.swift` in step with `llm-wiki guide output`; the CLI JSON shapes are the contract.
- No configuration fallbacks: the `llm-wiki` path is either set in Settings or found on the login shell's PATH,
  otherwise the app shows a setup error. The page format of a new wiki has no preselected value.
- Rendered HTML comes from `show --json` / `query --json` (sanitised); `HTMLView` keeps JavaScript disabled and
  routes every link click through `AppModel.follow`.
- Never log or display the captured shell environment (it holds API keys).

## Tools

- **llm-wiki** (`../wiki-v2`) — the CLI this app drives; see `../wiki-v2/docs/tools/llm-wiki.md` and `llm-wiki guide`.
