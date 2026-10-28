#!/usr/bin/env bash
# Publish one analysed session as the live sample report on GitHub Pages.
#   tools/publish_pages.sh sessions/synthetic/planted-voice
# Exports the static viewer and force-pushes it as the only commit on the gh-pages branch,
# so the video never enters main's history and old videos don't pile up.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
session="$(cd "$1" && pwd)"
remote="$(git -C "$root" remote get-url origin)"
site="$(mktemp -d)"
trap 'rm -rf "$site"' EXIT

(cd "$root/analyst" && bun src/cli.ts export "$session" "$site")
touch "$site/.nojekyll"   # serve the files as they are, no Jekyll build
git -C "$site" init -q -b gh-pages
git -C "$site" add -A
git -C "$site" -c user.name="$(git -C "$root" config user.name)" -c user.email="$(git -C "$root" config user.email)" \
	commit -q -m "Sample report: $(basename "$session")"
git -C "$site" push -q --force "$remote" gh-pages
echo "Pushed. Live in a minute or two at the repo's GitHub Pages URL."
