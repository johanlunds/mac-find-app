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
```

- The search field is focused automatically when the app opens/activates.
- **↑/↓** select, **Enter** launches, **Esc** hides, **⌘Q** quits.
- Reopening the app (Dock/Spotlight/Raycast) brings the panel back.

Test matching from the terminal:

```sh
swift run FindApp --search "mac menubar app"
```

## Regenerating the catalog

When apps are added or removed:

```sh
Scripts/regenerate-catalog.sh
```

This uses the `claude` CLI to research new apps (bundle id + web search), prune
removed ones, and installs the updated catalog to
`~/Library/Application Support/FindApp/catalog.json`.

Catalog search order: `$FINDAPP_CATALOG` → `~/Library/Application
Support/FindApp/catalog.json` → next to the executable / bundle resources →
`Resources/catalog.json` in the current directory.

The icon is generated from [Icon/make-icon.swift](Icon/make-icon.swift);
`build-app.sh` re-renders it automatically when that file changes.
