#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
fixture_build=$(mktemp -d "${TMPDIR:-/tmp}/screenscribe-fixtures.XXXXXX")
trap 'rm -rf "$fixture_build"' EXIT
export TEXMFVAR="$fixture_build/texmf-var"
export TEXMFCACHE="$fixture_build/texmf-cache"
mkdir -p "$TEXMFVAR" "$TEXMFCACHE"
for fixture in Tests/Fixtures/*.tex; do
  name=${fixture:t:r}
  lualatex -no-shell-escape -interaction=nonstopmode -halt-on-error -output-directory="$fixture_build" "$fixture" > "$fixture_build/$name-output.txt" 2>&1 || { tail -30 "$fixture_build/$name-output.txt"; exit 1; }
  pdftoppm -png -scale-to 2000 -singlefile "$fixture_build/$name.pdf" "Tests/Fixtures/$name" >/dev/null 2>&1
  echo "$name: LuaLaTeX compiled; PNG rendered"
done
