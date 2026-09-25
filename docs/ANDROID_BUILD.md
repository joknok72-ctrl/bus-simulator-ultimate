# بناء نسخة أندرويد (APK) — Android build guide

هذا الدليل يشرح بالضبط ما تحتاجه لتصدير **City Bus Driver** إلى APK باستخدام
**Godot 4.7.2-stable** (تصدير مباشر بلا Gradle). كل الأوامر مجرّبة على Linux x86_64.
This guide lists exactly what is needed to export **City Bus Driver** to an APK with **Godot 4.7.2-stable**
(direct export, no Gradle). All commands were exercised on Linux x86_64.

## 1) المتطلبات | Prerequisites

| المكوّن | Component | ملاحظات | Notes |
|---|---|---|---|
| Godot 4.7.2-stable editor | `Godot_v4.7.2-stable_linux.x86_64` | من `https://godotengine.org/download` (أو أرشيف الإصدارات الرسمي) | official download only |
| قوالب التصدير | `Godot_v4.7.2-stable_export_templates.tpz` (≈1.28 GB) | نحتاج فقط `android_debug.apk`, `android_release.apk`, `version.txt` منه — السكربت `tools/fetch_android_templates.py` يحمّل هذه الملفات وحدها (≈230 MB) عبر HTTP Range | only the Android entries are needed |
| JDK 17 | `openjdk-17-jdk-headless` | `sudo apt install openjdk-17-jdk-headless` | required for `apksigner` and the debug keystore |
| Android SDK | `platform-tools` + `build-tools;35.0.0` | عبر `sdkmanager` من command-line tools الرسمية (`dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip`) | Gradle/NDK/platforms are **not** required for non-Gradle export |

تُثبَّت القوالب في المسار الذي يتوقعه Godot على Linux:
Templates must live where Godot expects them on Linux:

```
~/.local/share/godot/export_templates/4.7.2.stable/android_debug.apk
~/.local/share/godot/export_templates/4.7.2.stable/android_release.apk
~/.local/share/godot/export_templates/4.7.2.stable/version.txt      # يحتوي: 4.7.2.stable
```

## 2) تجهيز Android SDK | Android SDK setup

```sh
export ANDROID_HOME=/opt/android-sdk
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
mkdir -p $ANDROID_HOME/cmdline-tools
curl -L -o /tmp/cmdline-tools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip -q /tmp/cmdline-tools.zip -d /tmp/ct && mv /tmp/ct/cmdline-tools $ANDROID_HOME/cmdline-tools/latest
yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --sdk_root=$ANDROID_HOME --licenses
$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --sdk_root=$ANDROID_HOME "platform-tools" "build-tools;35.0.0"
```

## 3) إعدادات المحرّر | Editor settings

يجب أن يعرف Godot مسار JDK وSDK. في المحرّر: **Editor → Editor Settings → Export → Android**
(`Java SDK Path`, `Android SDK Path`). أو بلا واجهة، عدّل `~/.config/godot/editor_settings-4.7.tres`:

```
export/android/java_sdk_path = "/usr/lib/jvm/java-17-openjdk-amd64"
export/android/android_sdk_path = "/opt/android-sdk"
```

مفتاح التصحيح (debug keystore): يُنشئ `tools/build_android.sh` مفتاحاً مؤقّتاً في `~/debug.keystore` إن لم يوجد (غيّر المسار عبر
`DEBUG_KEYSTORE=...`) ويضبط `export/android/debug_keystore*` في إعدادات المحرّر — وهو ما يفعله GitHub Actions أيضاً.
كل مفتاح مؤقّت مختلف عن سابقه، لذا احذف النسخة القديمة من الهاتف قبل تثبيت APK من بناء آخر.
Debug keystore: `tools/build_android.sh` creates a throw-away key at `~/debug.keystore` if none exists (override with
`DEBUG_KEYSTORE=...`) and writes `export/android/debug_keystore*` into the editor settings — the same thing the GitHub
Actions workflow does. Every throw-away key differs from the previous one, so uninstall the old copy from the phone
before installing an APK from another build.

## 4) التصدير | Export

```sh
GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64
cd /path/to/CityBusDriver
$GODOT --headless --path . --import                       # مرّتين في أول مرة لمستودع نظيف / twice on a clean checkout
$GODOT --headless --path . --export-debug "Android" build/CityBusDriver-debug.apk
```

الإعداد `Android` معرّف في `export_presets.cfg`:
arm64-v8a فقط، الحزمة `com.khaled.citybusdriver`، الإصدار `1.1.0` (code 2)، وضع ملء الشاشة، صلاحية `VIBRATE`،
أيقونات adaptive من `android/icons/`. minSdk = 24 (Android 7.0) وtargetSdk = 36 (افتراضيات Godot 4.7).

### نسخة release موقّعة | Signed release

```sh
keytool -genkeypair -v -keystore my-release.keystore -alias upload -keyalg RSA -keysize 2048 -validity 10000
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/secure/my-release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=upload
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD='***'
$GODOT --headless --path . --export-release "Android" build/CityBusDriver-release.apk
```

احتفظ بملف keystore خارج المستودع (مضاف إلى `.gitignore`). لمتجر Google Play فعّل `gradle_build/export_format = 1` (AAB)
مع `use_gradle_build = true` (يتطلب حينها `android_source.zip` من نفس أرشيف القوالب وGradle/NDK).
Keep the keystore out of the repository. For Google Play switch the preset to AAB (`gradle_build/export_format = 1`,
`use_gradle_build = true`; that additionally requires `android_source.zip` from the same template archive and Gradle).

## 5) التثبيت على الهاتف | Install on a phone

```sh
$ANDROID_HOME/platform-tools/adb install -r build/CityBusDriver-debug.apk
```

أو انقل الملف إلى الهاتف وافتحه (فعّل "تثبيت من مصادر غير معروفة"). الجهاز يجب أن يكون **arm64** (كل هواتف أندرويد الحديثة).
Or copy the APK to the phone and open it (allow "unknown sources"). The device must be **arm64** (all modern phones).

## 6) السكربت الجاهز | One-shot script

```sh
GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 JAVA_HOME=... ANDROID_HOME=... sh tools/build_android.sh
```

يفحص إصدار المحرّك (يرفض أي إصدار غير 4.7.2.stable)، يحمّل قوالب أندرويد إن لم تكن موجودة، يضبط مسارات SDK في
إعدادات المحرّر، يستورد المشروع، يصدّر APK التصحيح، يتحقق منه بـ `apksigner verify`، ويكتب `build/BUILD_INFO.txt`.
