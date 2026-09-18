#!/usr/bin/env bash
# يشغّل اللعبة في Xvfb (رندر برمجي) مع تدفق اختبار آلي ويأخذ لقطات شاشة.
# الاستخدام: tools/run_test.sh <flow> [res WxH] [timeout_s]
#   flow مثال: menu,garage,settings,drive,pause,results  أو drive_long
set -u
FLOW="${1:-menu,garage,drive}"
RES="${2:-720x1280}"
TO="${3:-300}"
GODOT="${GODOT:-/home/user/godot/Godot_v4.7.2-stable_linux.x86_64}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-/tmp/shots}"
mkdir -p "$OUT"
rm -f "$OUT"/*.png
W="${RES%x*}"; H="${RES#*x}"
timeout "$TO" xvfb-run -a -s "-screen 0 $((W+40))x$((H+40))x24" \
  "$GODOT" --path "$PROJ" --rendering-driver opengl3 --audio-driver Dummy \
  --resolution "$RES" -- --test --shots="$OUT" --flow="$FLOW" > "$OUT/run.log" 2>&1
echo "EXIT=$?" >> "$OUT/run.log"
