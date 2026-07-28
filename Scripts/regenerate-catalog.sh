#!/bin/zsh
# Regenerates catalog.json when apps in /Applications change, using the
# `claude` CLI to research/describe any new apps. Then installs the catalog
# to ~/Library/Application Support/FindApp/catalog.json where FindApp reads it.
#
# Usage:
#   ./regenerate-catalog.sh            # update catalog (add new, remove gone) + install
#   ./regenerate-catalog.sh --install  # just install the existing catalog.json

set -euo pipefail
cd "$(dirname "$0")/.."

DEST="$HOME/Library/Application Support/FindApp/catalog.json"

install_catalog() {
  mkdir -p "$(dirname "$DEST")"
  cp Resources/catalog.json "$DEST"
  echo "Installed catalog to $DEST"
}

if [[ "${1:-}" == "--install" ]]; then
  install_catalog
  exit 0
fi

if ! command -v claude >/dev/null; then
  echo "error: the 'claude' CLI is required to regenerate descriptions." >&2
  exit 1
fi

# Snapshot current apps with bundle ids as grounding data for the model.
# Covers /Applications and ~/Applications (each one level deep) plus Apple's
# system app folders. Keys match the catalog 'file' field.
APPS_FILE=$(mktemp)
for app in /Applications/*.app(N) /Applications/*/*.app(N) \
           $HOME/Applications/*.app(N) $HOME/Applications/*/*.app(N) \
           /System/Applications/*.app(N) /System/Applications/Utilities/*.app(N); do
  case "$app" in
    /System/*) key="$app";;
    $HOME/Applications/*) key="~/Applications/${app#$HOME/Applications/}";;
    *) key="${app#/Applications/}";;
  esac
  bid=$(defaults read "$app/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "?")
  echo "$key | $bid" >> "$APPS_FILE"
done

claude -p --permission-mode acceptEdits "You are updating Resources/catalog.json in the current directory, which is a search index of macOS apps for a Spotlight-like app finder. The file '$APPS_FILE' lists every installed app as 'file-key | bundle-id', where file-key is a path relative to /Applications (e.g. 'Thaw.app', 'ISTP/ISTP.app'), a '~/Applications/...' path for user-installed apps, or an absolute path for Apple system apps (e.g. '/System/Applications/Notes.app').

Update Resources/catalog.json so it exactly covers that list:
1. REMOVE entries whose 'file' is no longer in the list.
2. ADD an entry for each app in the list that's missing from catalog.json. For each new app, research what it does (use your knowledge and web search for unfamiliar ones; the bundle id is a strong hint). Write a 1-2 sentence 'description' and 8-14 lowercase 'keywords' covering its category, purpose and common synonyms (e.g. a menu bar utility should include 'menubar', 'menu bar app', 'utility'). Follow the existing JSON structure exactly ('file', 'name', 'bundleId', 'description', 'keywords').
3. Leave existing entries untouched. Update the top-level 'generated' date to today.
4. Validate that the final file is valid JSON."

rm -f "$APPS_FILE"

python3 -c "import json; json.load(open('Resources/catalog.json'))" || {
  echo "error: Resources/catalog.json is not valid JSON after regeneration" >&2
  exit 1
}

install_catalog
