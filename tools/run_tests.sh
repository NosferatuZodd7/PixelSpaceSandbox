#!/usr/bin/env bash
# Runs the headless checks and fails if anything is wrong:
#   1. imports the project (fonts, textures, translations) — twice, because on a
#      fresh checkout the first pass reports the not-yet-imported translations
#      the project settings point to; only the second pass is checked, and an
#      asset that really fails to import fails again there;
#   2. runs every test (tests/run_tests.gd);
#   3. runs the game itself for a few hundred frames;
#   4. fails if Godot printed any error or warning in any step.
#
# Usage:
#   tools/run_tests.sh [--filter=<text>]
#   GODOT=/path/to/godot tools/run_tests.sh
set -uo pipefail

GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOGS="$ROOT/tests/output"
mkdir -p "$LOGS"
failed=0

step() {
  local name="$1"
  shift
  echo "== $name"
  "$@" >"$LOGS/$name.log" 2>&1
  local status=$?
  if [ $status -ne 0 ]; then
    echo "   exit code $status"
    failed=1
  fi
}

step import-first-pass "$GODOT" --headless --path "$ROOT" --import
step import "$GODOT" --headless --path "$ROOT" --import
step tests "$GODOT" --headless --path "$ROOT" --script res://tests/run_tests.gd -- "$@"
grep -E '^(PASS|FAIL|        )|passed,' "$LOGS/tests.log"
step game "$GODOT" --headless --path "$ROOT" --quit-after 300

problems="$(grep -nE '(^|[^A-Z_])(ERROR|WARNING):|SCRIPT ERROR|USER ERROR|USER WARNING' "$LOGS"/{import,tests,game}.log)"
if [ -n "$problems" ]; then
  echo "== Godot reported errors or warnings:"
  echo "$problems"
  failed=1
fi

if [ $failed -ne 0 ]; then
  echo "== FAILED (logs in tests/output/)"
  exit 1
fi
echo "== All checks passed"
