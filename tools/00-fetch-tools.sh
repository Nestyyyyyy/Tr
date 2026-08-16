#!/usr/bin/env bash
# Gerekli jar'ları bin/ altına indirir. Bir kere çalıştırman yeterli.

source "$(dirname "$0")/lib.sh"

APKTOOL_VER="2.11.1"
SIGNER_VER="1.3.0"
APKEDITOR_VER="1.4.1"

APKTOOL_URL="https://github.com/iBotPeaches/Apktool/releases/download/v${APKTOOL_VER}/apktool_${APKTOOL_VER}.jar"
SIGNER_URL="https://github.com/patrickfav/uber-apk-signer/releases/download/v${SIGNER_VER}/uber-apk-signer-${SIGNER_VER}.jar"
APKEDITOR_URL="https://github.com/REAndroid/APKEditor/releases/download/V${APKEDITOR_VER}/APKEditor-${APKEDITOR_VER}.jar"

need_cmd curl "curl kur (sudo apt install curl)"
need_java

mkdir -p "$BIN_DIR"

fetch() {
  local url="$1" dest="$2" name="$3"
  if [ -s "$dest" ]; then
    ok "$name zaten var ($dest)"
    return
  fi
  info "$name indiriliyor..."
  curl -fL --retry 4 --retry-delay 2 --progress-bar -o "$dest.part" "$url" \
    || die "$name indirilemedi: $url"
  mv "$dest.part" "$dest"
  ok "$name -> $dest"
}

fetch "$APKTOOL_URL"   "$APKTOOL_JAR"   "apktool $APKTOOL_VER"
fetch "$SIGNER_URL"    "$SIGNER_JAR"    "uber-apk-signer $SIGNER_VER"
fetch "$APKEDITOR_URL" "$APKEDITOR_JAR" "APKEditor $APKEDITOR_VER (split APK birleştirme)"

echo
info "Java sürümü:"
java -version 2>&1 | sed 's/^/    /'
echo
ok "Araçlar hazır. Sıradaki adım: ./tools/01-pull.sh"
