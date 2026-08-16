# Ortak yardımcılar. Doğrudan çalıştırılmaz, diğer scriptler "source" eder.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
WORK_DIR="$ROOT_DIR/work"
OUT_DIR="$ROOT_DIR/out"

# Traffic Racer (SK Games). Başka bir oyun için: PKG=... ./tools/01-pull.sh
PKG="${PKG:-com.skgames.trafficracer}"

APKTOOL_JAR="$BIN_DIR/apktool.jar"
SIGNER_JAR="$BIN_DIR/uber-apk-signer.jar"
APKEDITOR_JAR="$BIN_DIR/apkeditor.jar"

if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_BLU=$'\033[34m'; C_OFF=$'\033[0m'
else
  C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_OFF=''
fi

info() { printf '%s==>%s %s\n' "$C_BLU" "$C_OFF" "$*"; }
ok()   { printf '%s ok %s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '%s dikkat%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
die()  { printf '%shata%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' bulunamadı. $2"
}

need_java() {
  need_cmd java "JDK 17 kur: https://adoptium.net (veya: sudo apt install openjdk-17-jdk)"
}

need_adb() {
  need_cmd adb "Android platform-tools kur: https://developer.android.com/tools/releases/platform-tools"
}

need_jar() {
  [ -f "$1" ] || die "$(basename "$1") yok. Önce: ./tools/00-fetch-tools.sh"
}

# Tek bir cihaz bağlı mı?
need_device() {
  need_adb
  adb start-server >/dev/null 2>&1 || true
  local n
  n="$(adb devices | awk 'NR>1 && $2=="device"' | wc -l | tr -d ' ')"
  [ "$n" != "0" ] || die "Cihaz görünmüyor. USB hata ayıklamayı aç ve telefondaki izin penceresini onayla ('adb devices' ile doğrula)."
  [ "$n" = "1" ] || die "$n cihaz bağlı. Fazlalıkları çıkar ya da ANDROID_SERIAL=<seri> ver."
}

# Paket cihazda kurulu mu?
pkg_installed() {
  adb shell pm list packages 2>/dev/null | tr -d '\r' | grep -qx "package:$PKG"
}

# base64'ü platform bağımsız, tek satır üret (Linux -w0, macOS satır sarmaz)
b64_oneline() {
  base64 < "$1" | tr -d '\n'
}

# AndroidManifest.xml'e debuggable + allowBackup ekler. Yerinde düzenler.
# "<application" yalnızca açılış etiketinde geçer; "</application>" eşleşmez.
patch_manifest() {
  local m="$1" tmp="$1.tmp"
  [ -f "$m" ] || die "Manifest yok: $m"

  if grep -q 'android:debuggable="true"' "$m"; then
    ok "debuggable zaten açık"
  else
    sed 's|<application|<application android:debuggable="true"|' "$m" > "$tmp" && mv "$tmp" "$m"
    grep -q 'android:debuggable="true"' "$m" || die "debuggable eklenemedi."
    ok 'android:debuggable="true" eklendi'
  fi

  if grep -q 'android:allowBackup="true"' "$m"; then
    ok "allowBackup zaten true"
  elif grep -q 'android:allowBackup=' "$m"; then
    sed 's|android:allowBackup="false"|android:allowBackup="true"|' "$m" > "$tmp" && mv "$tmp" "$m"
    ok "allowBackup true yapıldı"
  else
    sed 's|<application|<application android:allowBackup="true"|' "$m" > "$tmp" && mv "$tmp" "$m"
    ok 'allowBackup="true" eklendi'
  fi
}
