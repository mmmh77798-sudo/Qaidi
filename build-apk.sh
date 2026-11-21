#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
: "${SDK:?Set ANDROID_SDK_ROOT to an Android SDK with android-35 and 35.0.0 build-tools}"
JAR="$SDK/platforms/android-35/android.jar"
TOOLS="$SDK/build-tools/35.0.0"
[[ -f "$JAR" && -x "$TOOLS/aapt2" ]] || { echo 'Missing Android SDK Platform 35 or build-tools 35.0.0' >&2; exit 1; }
if [[ -n "${JAVA_HOME:-}" ]]; then export PATH="$JAVA_HOME/bin:$PATH"; fi
OUT="${1:-$ROOT/Qayd-3.7.apk}"
mkdir -p "$(dirname -- "$OUT")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/assets" "$WORK/classes" "$WORK/dex"
cp -R "$ROOT/app" "$WORK/assets/app"
python3 "$ROOT/tools/stage-shared-desk.py" "$WORK/assets/shared-desk"
python3 "$ROOT/tools/stage-device-profile.py" "$WORK/assets/device-profile"
"$TOOLS/aapt2" compile --dir "$ROOT/android/res" -o "$WORK/resources.zip"
"$TOOLS/aapt2" link --manifest "$ROOT/android/AndroidManifest.xml" -I "$JAR" -A "$WORK/assets" --java "$WORK/generated" -o "$WORK/raw.apk" "$WORK/resources.zip"
find "$ROOT/android/src" "$WORK/generated" -name '*.java' -print0 | xargs -0 javac -encoding UTF-8 -source 8 -target 8 -Xlint:-options -classpath "$JAR" -d "$WORK/classes"
jar cf "$WORK/classes.jar" -C "$WORK/classes" .
"$TOOLS/d8" --release --min-api 24 --lib "$JAR" --output "$WORK/dex" "$WORK/classes.jar"
zip -q -j "$WORK/raw.apk" "$WORK/dex/classes.dex"
"$TOOLS/zipalign" -f 4 "$WORK/raw.apk" "$WORK/aligned.apk"
if [[ -n "${QAYD_KEYSTORE:-}" ]]; then
  KEY="$QAYD_KEYSTORE"; ALIAS="${QAYD_KEY_ALIAS:-qayd}"
  : "${QAYD_STORE_PASS:?Set QAYD_STORE_PASS}"
  export QAYD_KEY_PASS="${QAYD_KEY_PASS:-$QAYD_STORE_PASS}"
  export QAYD_STORE_PASS
else
  KEY="${XDG_DATA_HOME:-$HOME/.local/share}/qayd/test-signing.p12"; ALIAS=qaydtest
  export QAYD_STORE_PASS=localtestonly QAYD_KEY_PASS=localtestonly
  if [[ ! -f "$KEY" ]]; then
    mkdir -p "$(dirname -- "$KEY")"
    keytool -genkeypair -keystore "$KEY" -storetype PKCS12 -storepass:env QAYD_STORE_PASS -alias "$ALIAS" -keyalg RSA -keysize 2048 -validity 3650 -dname 'CN=Qayd Test Build, O=Qayd' >/dev/null
    chmod 600 "$KEY"
  fi
fi
"$TOOLS/apksigner" sign --ks "$KEY" --ks-key-alias "$ALIAS" --ks-pass env:QAYD_STORE_PASS --key-pass env:QAYD_KEY_PASS --v4-signing-enabled false --out "$OUT" "$WORK/aligned.apk"
"$TOOLS/apksigner" verify -v "$OUT"
echo "APK: $OUT"
