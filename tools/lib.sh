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

# Git Bash / MSYS mi? (Windows)
is_msys() {
  case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; *) return 1 ;; esac
}

# python3 / python / py — Windows'ta üçü de olabilir. Boş kalabilir (opsiyonel bağımlılık).
PYTHON=""
for _c in python3 python py; do
  if command -v "$_c" >/dev/null 2>&1 \
     && "$_c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
    PYTHON="$_c"; break
  fi
done
unset _c

# Dosya özeti — cksum her yerde yok (Git Bash), sırayla dene.
file_sum() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum < "$1" | awk '{print $1}'
  elif command -v cksum >/dev/null 2>&1; then
    cksum < "$1" | awk '{print $1"-"$2}'
  else
    wc -c < "$1" | tr -d ' '
  fi
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

# 'jar' PATH'te olmayabilir (Windows'ta java kurulu ama JDK/bin PATH'te değil).
# java'nın yanında ve JAVA_HOME altında ara.
find_jar_bin() {
  local j d c
  if command -v jar >/dev/null 2>&1; then command -v jar; return 0; fi
  j="$(command -v java 2>/dev/null || true)"
  if [ -n "$j" ]; then
    d="$(dirname "$j")"
    for c in "$d/jar" "$d/jar.exe"; do
      [ -x "$c" ] && { echo "$c"; return 0; }
    done
  fi
  if [ -n "${JAVA_HOME:-}" ]; then
    for c in "$JAVA_HOME/bin/jar" "$JAVA_HOME/bin/jar.exe"; do
      [ -x "$c" ] && { echo "$c"; return 0; }
    done
  fi
  echo ""
}

# Zip açar. Sırayla: unzip -> python -> jar -> PowerShell (Windows'ta hep var).
extract_zip() {  # extract_zip <zip> <hedef-dizin>
  local zip="$1" dest="$2" jarbin
  [ -f "$zip" ] || die "Zip yok: $zip"
  mkdir -p "$dest"

  if command -v unzip >/dev/null 2>&1; then
    unzip -o -q "$zip" -d "$dest" && return 0
  fi
  if [ -n "$PYTHON" ]; then
    "$PYTHON" -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
      "$zip" "$dest" && return 0
  fi
  jarbin="$(find_jar_bin)"
  if [ -n "$jarbin" ]; then
    ( cd "$dest" && "$jarbin" xf "$zip" ) && return 0
  fi
  if is_msys && command -v powershell >/dev/null 2>&1; then
    powershell -NoProfile -Command \
      "Expand-Archive -LiteralPath '$(cygpath -w "$zip")' -DestinationPath '$(cygpath -w "$dest")' -Force" \
      && return 0
  fi
  die "Zip açacak araç bulunamadı (unzip / python / jar / powershell)."
}

# Uygulamanın özel veri klasörüne dosya yazar (root'suz, run-as üzerinden).
# Önce hızlı yol: adb push -> uygulamanın kendi harici klasörü -> run-as cp.
# Olmazsa yavaş ama her yerde çalışan base64 parçalı aktarım.
#   push_app_file <yerel-dosya> <veri-dizinine-göreli-hedef>
push_app_file() {
  local src="$1" rel="$2"
  [ -s "$src" ] || die "Gönderilecek dosya boş: $src"

  local dir; dir="$(dirname "$rel")"
  [ "$dir" = "." ] || adb shell "run-as $PKG mkdir -p '$dir'" >/dev/null 2>&1 || true

  local ext="/sdcard/Android/data/$PKG/files"
  adb shell "mkdir -p '$ext'" >/dev/null 2>&1 || true
  if ( cd "$(dirname "$src")" && MSYS_NO_PATHCONV=1 adb push "$(basename "$src")" "$ext/.push.tmp" ) >/dev/null 2>&1 \
     && adb shell "run-as $PKG cp '$ext/.push.tmp' '$rel'" >/dev/null 2>&1; then
    adb shell "rm -f '$ext/.push.tmp'" >/dev/null 2>&1 || true
  else
    warn "Hızlı aktarım olmadı, parçalı yola geçiliyor (daha yavaş)..."
    local b64 len i=0 chunk
    b64="$(b64_oneline "$src")"; len=${#b64}
    adb shell "run-as $PKG sh -c 'rm -f .push.b64'" >/dev/null 2>&1 || true
    while [ "$i" -lt "$len" ]; do
      chunk="${b64:$i:1500}"
      adb shell "run-as $PKG sh -c 'printf %s $chunk >> .push.b64'" >/dev/null \
        || die "Aktarım başarısız."
      i=$((i + 1500))
    done
    adb shell "run-as $PKG sh -c 'base64 -d < .push.b64 > \"$rel\" && rm -f .push.b64'" >/dev/null \
      || die "Cihazda yazılamadı: $rel"
  fi

  # doğrula
  local verify="$WORK_DIR/.pushverify"
  mkdir -p "$WORK_DIR"
  adb exec-out run-as "$PKG" cat "$rel" > "$verify" 2>/dev/null || die "Geri okunamadı: $rel"
  if [ "$(file_sum "$verify")" != "$(file_sum "$src")" ]; then
    rm -f "$verify"; die "Doğrulama başarısız: cihazdaki $rel farklı."
  fi
  rm -f "$verify"
}

# Uygulamanın veri klasöründen dosya çeker.
pull_app_file() {  # pull_app_file <veri-dizinine-göreli-kaynak> <yerel-hedef>
  adb exec-out run-as "$PKG" cat "$1" > "$2" 2>/dev/null || return 1
  [ -s "$2" ] || return 1
}

# prefs_awk <mode> <anahtar> <deger> <dosya>   (mode: list | get | set)
# Anahtar/değer ENVIRON ile geçilir: "awk -v" kaçış dizilerini yorumlar, ENVIRON yorumlamaz —
# yani "\1" gibi değerler birebir literal yazılır.
prefs_awk() {
  PREFS_MODE="$1" PREFS_KEY="$2" PREFS_VAL="$3" awk -f "$ROOT_DIR/tools/prefs_edit.awk" "$4"
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
