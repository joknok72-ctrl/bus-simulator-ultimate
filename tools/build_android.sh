#!/bin/sh
# Export City Bus Driver to an Android APK with the exact official Godot 4.7.2-stable editor.
#
#   GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 \
#   JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 ANDROID_HOME=/opt/android-sdk \
#   sh tools/build_android.sh
#
# Optional release signing:
#   RELEASE_KEYSTORE=/secure/my.keystore RELEASE_KEY_ALIAS=upload RELEASE_KEY_PASS=... sh tools/build_android.sh
#
# Steps: check engine version -> fetch Android templates if missing -> create a throw-away debug
#        keystore if missing (DEBUG_KEYSTORE, default ~/debug.keystore) -> configure editor SDK/keystore
#        paths -> import -> export debug APK (and release APK if a keystore is given) -> verify -> BUILD_INFO.txt
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
GODOT=${GODOT:-/tmp/godot/Godot_v4.7.2-stable_linux.x86_64}
JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}
ANDROID_HOME=${ANDROID_HOME:-/opt/android-sdk}
export JAVA_HOME ANDROID_HOME
OUT="$HERE/build"
LOGS="$OUT/logs"
mkdir -p "$LOGS"

fail() { echo "ERROR: $*" >&2; exit 1; }

[ -x "$GODOT" ] || fail "Godot binary not found/executable: $GODOT (set GODOT=...)"
VERSION=$("$GODOT" --version 2>/dev/null | tail -1)
case "$VERSION" in
  4.7.2.stable*) echo "Engine: $VERSION" ;;
  *) fail "Expected Godot 4.7.2.stable, got '$VERSION'. Do not build with another version." ;;
esac

[ -x "$JAVA_HOME/bin/java" ] || fail "JDK not found at $JAVA_HOME (install openjdk-17-jdk-headless)"
[ -x "$ANDROID_HOME/platform-tools/adb" ] || fail "Android platform-tools missing in $ANDROID_HOME"
APKSIGNER=$(ls "$ANDROID_HOME"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)
[ -n "$APKSIGNER" ] || fail "Android build-tools (apksigner) missing in $ANDROID_HOME"

# --- official Android export templates -------------------------------------------------
TPL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.7.2.stable"
if [ ! -f "$TPL_DIR/android_debug.apk" ] || [ ! -f "$TPL_DIR/android_release.apk" ]; then
  echo "Fetching official Android export templates into $TPL_DIR ..."
  python3 "$HERE/tools/fetch_android_templates.py" "$TPL_DIR" || fail "template download failed"
fi
grep -q "4.7.2.stable" "$TPL_DIR/version.txt" || fail "template version.txt mismatch"

# --- debug keystore (throw-away key for debug builds; created if missing) ----------------
DEBUG_KEYSTORE=${DEBUG_KEYSTORE:-$HOME/debug.keystore}
DEBUG_KEYSTORE_USER=${DEBUG_KEYSTORE_USER:-androiddebugkey}
DEBUG_KEYSTORE_PASS=${DEBUG_KEYSTORE_PASS:-android}
if [ ! -f "$DEBUG_KEYSTORE" ]; then
  echo "Creating throw-away debug keystore $DEBUG_KEYSTORE ..."
  "$JAVA_HOME/bin/keytool" -keyalg RSA -genkeypair -alias "$DEBUG_KEYSTORE_USER" -keypass "$DEBUG_KEYSTORE_PASS" \
    -keystore "$DEBUG_KEYSTORE" -storepass "$DEBUG_KEYSTORE_PASS" \
    -dname "CN=Android Debug,O=Android,C=US" -validity 9999 > "$LOGS/keytool.log" 2>&1 || fail "keytool could not create $DEBUG_KEYSTORE"
fi

# --- editor settings: SDK paths and debug keystore --------------------------------------
SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/godot/editor_settings-4.7.tres"
if [ ! -f "$SETTINGS" ]; then
  # First editor start creates the file (headless import is enough).
  "$GODOT" --headless --path "$HERE" --import > "$LOGS/import0.log" 2>&1
fi
[ -f "$SETTINGS" ] || fail "editor settings file was not created at $SETTINGS"
python3 - "$SETTINGS" "$JAVA_HOME" "$ANDROID_HOME" "$DEBUG_KEYSTORE" "$DEBUG_KEYSTORE_USER" "$DEBUG_KEYSTORE_PASS" <<'EOF'
import re, sys
path, java, sdk, keystore, ks_user, ks_pass = sys.argv[1:7]
s = open(path, encoding="utf-8").read()
def put(key, value):
    global s
    line = '%s = "%s"' % (key, value)
    if re.search(r'^%s = .*$' % re.escape(key), s, re.M):
        s = re.sub(r'^%s = .*$' % re.escape(key), line, s, flags=re.M)
    else:
        s = s.rstrip("\n") + "\n" + line + "\n"
put("export/android/java_sdk_path", java)
put("export/android/android_sdk_path", sdk)
put("export/android/debug_keystore", keystore)
put("export/android/debug_keystore_user", ks_user)
put("export/android/debug_keystore_pass", ks_pass)
open(path, "w", encoding="utf-8").write(s)
print("editor settings updated:", path)
EOF

# --- import (twice on a clean checkout so generated .translation/font resources exist) ---
cd "$HERE" || exit 1
"$GODOT" --headless --path "$HERE" --import > "$LOGS/import1.log" 2>&1
"$GODOT" --headless --path "$HERE" --import > "$LOGS/import2.log" 2>&1
IMPORT_ERRORS=$(grep -cE "SCRIPT ERROR|^ERROR" "$LOGS/import2.log")
echo "import errors (second pass): $IMPORT_ERRORS"
[ "$IMPORT_ERRORS" -eq 0 ] || { grep -E "SCRIPT ERROR|^ERROR" "$LOGS/import2.log" | head -20; fail "import reported errors"; }

# --- debug export -----------------------------------------------------------------------
DEBUG_APK="$OUT/CityBusDriver-debug.apk"
rm -f "$DEBUG_APK" "$DEBUG_APK.idsig"
"$GODOT" --headless --path "$HERE" --export-debug "Android" "$DEBUG_APK" > "$LOGS/export_debug.log" 2>&1
EXPORT_RC=$?
[ "$EXPORT_RC" -eq 0 ] && [ -s "$DEBUG_APK" ] || { sed 's/\x1b\[[0-9;]*m//g' "$LOGS/export_debug.log" | grep -vE "^ADDING|^\[" | tail -30; fail "debug export failed (exit $EXPORT_RC)"; }
"$APKSIGNER" verify "$DEBUG_APK" || fail "apksigner verify failed for $DEBUG_APK"
echo "Debug APK: $DEBUG_APK ($(wc -c < "$DEBUG_APK") bytes, signature verified)"

# --- optional release export ------------------------------------------------------------
RELEASE_APK=""
if [ -n "${RELEASE_KEYSTORE:-}" ]; then
  [ -f "$RELEASE_KEYSTORE" ] || fail "RELEASE_KEYSTORE not found: $RELEASE_KEYSTORE"
  export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$RELEASE_KEYSTORE"
  export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${RELEASE_KEY_ALIAS:-upload}"
  export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${RELEASE_KEY_PASS:-}"
  RELEASE_APK="$OUT/CityBusDriver-release.apk"
  rm -f "$RELEASE_APK" "$RELEASE_APK.idsig"
  "$GODOT" --headless --path "$HERE" --export-release "Android" "$RELEASE_APK" > "$LOGS/export_release.log" 2>&1
  [ -s "$RELEASE_APK" ] || { tail -30 "$LOGS/export_release.log"; fail "release export failed"; }
  "$APKSIGNER" verify "$RELEASE_APK" || fail "apksigner verify failed for $RELEASE_APK"
  echo "Release APK: $RELEASE_APK ($(wc -c < "$RELEASE_APK") bytes, signature verified)"
fi

# --- build info -------------------------------------------------------------------------
{
  echo "City Bus Driver - Android build"
  echo "date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "engine: $VERSION"
  echo "templates: $TPL_DIR ($(cat "$TPL_DIR/version.txt"))"
  echo "preset: Android (export_presets.cfg) - arm64-v8a, non-gradle"
  echo "debug apk: $(basename "$DEBUG_APK") $(wc -c < "$DEBUG_APK") bytes sha256=$(sha256sum "$DEBUG_APK" | cut -d' ' -f1)"
  [ -n "$RELEASE_APK" ] && echo "release apk: $(basename "$RELEASE_APK") $(wc -c < "$RELEASE_APK") bytes sha256=$(sha256sum "$RELEASE_APK" | cut -d' ' -f1)"
  echo "import errors (second pass): $IMPORT_ERRORS"
} > "$OUT/BUILD_INFO.txt"
cat "$OUT/BUILD_INFO.txt"
