# Find App

A Spotlight-style app finder for macOS with semantic search. Type what an app
*does* ("mac menubar utility", "hide menu bar icons", "postgres gui") and find
it even if you don't remember its name.

## How it works

- **Catalog**: [Resources/catalog.json](Resources/catalog.json) holds an
  AI-generated description + keyword set for every installed app, grounded in
  each app's bundle id and web research.
- **Matching**: combines classic name/keyword/prefix scoring with on-device
  semantic matching using Apple's `NaturalLanguage` word- and sentence
  embeddings (no network calls at search time).
- **Scope**: `/Applications` and `~/Applications` (each scanned one folder deep,
  so `ISTP/ISTP.app` and `Chrome Apps.localized/YouTube.app` are included),
  plus Apple's built-ins in `/System/Applications` and
  `/System/Applications/Utilities`.
- **Freshness**: those locations are rescanned on every keystroke, so removed
  apps never appear and newly added apps still match by name (add descriptions
  by regenerating the catalog).

Catalog `file` keys follow the scan roots: bare or relative under
`/Applications` (`Thaw.app`, `ISTP/ISTP.app`), `~/Applications/…` for user apps,
and absolute paths for system apps (`/System/Applications/Notes.app`).

## Layout

```
Sources/FindApp/   app code (search engine, panel UI, app lifecycle)
Resources/         catalog.json — the app descriptions/keywords index
Icon/              make-icon.swift — the app icon, drawn in code
Scripts/           build-app.sh, make-icon.sh, regenerate-catalog.sh
build/             generated: "Find App.app", AppIcon.icns (gitignored)
```

## Usage

```sh
swift run                 # run directly
Scripts/build-app.sh      # build "build/Find App.app" (also installs the catalog)
cp -R "build/Find App.app" /Applications/
open -a "Find App.app"
```

- The search field is focused automatically when the app opens/activates.
- **↑/↓** select, **Enter** launches, **Esc** hides, **⌘Q** quits.
- Reopening the app (Dock/Spotlight/Raycast) brings the panel back.

Developer flags:

```sh
swift run FindApp --search "mac menubar app"       # test matching quality
swift run FindApp --render-preview out.png "query" # offscreen panel screenshot
swift run FindApp --render-settings out.png        # offscreen settings screenshot ("welcome" for first-run state)
swift run FindApp --selftest-keys                  # key-handling self-test
swift run FindApp --selftest-generate [fileKey]    # run real AI generation for missing apps (or one app)
```

## Settings & regenerating the catalog

Open **Settings** (⌘, — or the gear in the search panel's footer) to browse
every installed app with its description and keyword chips, filter them, and
regenerate entries:

- **Generate Missing (n)** — describe apps that have no entry yet.
- **Regenerate All** — rebuild every entry.
- Right-click a row — **Regenerate This App** / **Show in Finder**.

Generation spawns your local `claude` CLI (research only — the CLI returns
JSON, the app merges and saves it). Results are merged and saved once, after
all batches finished regularly — a cancelled or failed run discards them. Each
save keeps the previous catalog as a timestamped backup
(`catalog.yyyyMMdd-HHmmss-SSS.backup.json`, newest 5 kept).

On **first launch** (no catalog in Application Support yet) the app opens a
welcome pane offering **Analyze My Apps** / **Skip for Now** — name-based
search works fine until the analysis runs.

The older script route still works too:

```sh
Scripts/regenerate-catalog.sh
```

Both write the catalog to `~/Library/Application Support/FindApp/catalog.json`.

Catalog search order: `$FINDAPP_CATALOG` → `~/Library/Application
Support/FindApp/catalog.json` → next to the executable / bundle resources →
`Resources/catalog.json` in the current directory.

To test the first-run flow, clear the app's user defaults (and move the
Application Support catalog aside):

```sh
defaults delete com.johanlunds.FindApp
```

The icon is generated from [Icon/make-icon.swift](Icon/make-icon.swift);
`build-app.sh` re-renders it automatically when that file changes.
