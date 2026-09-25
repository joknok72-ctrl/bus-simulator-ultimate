#!/bin/sh
# Validate City Bus Driver with the exact official Godot 4.7.2-stable editor (headless).
#   GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 sh tools/validate.sh
# Runs on a scratch copy so the import cache never pollutes the source tree.
# 1) import (twice on a clean tree)  2) tests/smoke_test.gd  3) boot the main scene headless for ~3 s
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
GODOT=${GODOT:-/tmp/godot/Godot_v4.7.2-stable_linux.x86_64}
LOGS=${LOGS:-$HERE/build/logs}
SCRATCH=${SCRATCH:-/tmp/citybus_validate}
mkdir -p "$LOGS"

[ -x "$GODOT" ] || { echo "Godot binary not found: $GODOT (set GODOT=...)"; exit 1; }
VERSION=$("$GODOT" --version 2>/dev/null | tail -1)
case "$VERSION" in 4.7.2.stable*) echo "Engine: $VERSION" ;; *) echo "Expected 4.7.2.stable, got $VERSION"; exit 1 ;; esac

rm -rf "$SCRATCH" && mkdir -p "$SCRATCH" && cp -r "$HERE"/. "$SCRATCH"/ && rm -rf "$SCRATCH/.godot" "$SCRATCH/build"
cd "$SCRATCH" || exit 1

echo "--- import"
"$GODOT" --headless --path "$SCRATCH" --import > "$LOGS/validate_import1.log" 2>&1
"$GODOT" --headless --path "$SCRATCH" --import > "$LOGS/validate_import2.log" 2>&1
echo "import exit=$?  errors(second pass)=$(grep -cE 'SCRIPT ERROR|^ERROR' "$LOGS/validate_import2.log")"

echo "--- smoke test"
"$GODOT" --headless --path "$SCRATCH" -s res://tests/smoke_test.gd > "$LOGS/validate_smoke.log" 2>&1
SMOKE=$?
grep -E "^\s*\[(PASS|FAIL)\]|checks|SMOKE TEST|SCRIPT ERROR|^ERROR" "$LOGS/validate_smoke.log" | sed 's/\x1b\[[0-9;]*m//g'
echo "smoke exit=$SMOKE"

echo "--- boot main scene (180 frames)"
"$GODOT" --headless --path "$SCRATCH" --quit-after 180 > "$LOGS/validate_boot.log" 2>&1
BOOT=$?
echo "boot exit=$BOOT  errors=$(grep -cE 'SCRIPT ERROR|^ERROR|USER ERROR' "$LOGS/validate_boot.log")"

[ "$SMOKE" -eq 0 ] && [ "$BOOT" -eq 0 ] && echo "VALIDATION OK" || { echo "VALIDATION FAILED"; exit 1; }
