#!/usr/bin/env bash
# IL2CPP dökümü: libil2cpp.so + global-metadata.dat -> dump.cs + script.json
#
# Mod menüsü yazabilmek için oyunun sınıf/metot isimlerine ve adreslerine ihtiyaç var.
# Bu script Il2CppDumper'ı indirir, APK'dan gerekli iki dosyayı çıkarır ve dökümü alır.
# Sonuç: work/dump/dump.cs  (dev bir metin dosyası; içinde aradığımız fonksiyonlar var)

source "$(dirname "$0")/lib.sh"

IL2CPP_VER="6.7.46"
IL2CPP_URL="https://github.com/Perfare/Il2CppDumper/releases/download/v${IL2CPP_VER}/Il2CppDumper-win-v${IL2CPP_VER}.zip"

SRC="${1:-$WORK_DIR/original.apk}"
[ -f "$SRC" ] || die "APK yok: $SRC  (önce ./tr.sh pull)"

need_java   # jar, zip açmak için (unzip Git Bash'te yok)
need_cmd curl "curl kur"

DUMP_DIR="$WORK_DIR/dump"
EXTRACT="$WORK_DIR/il2cpp-input"
TOOL_DIR="$BIN_DIR/Il2CppDumper"

# --- zip açma: unzip -> python -> jar -----------------------------------------
unzip_into() {  # unzip_into <zip> <hedef-dizin> [icerideki-yol...]
  local zip="$1" dest="$2"; shift 2
  mkdir -p "$dest"
  if command -v unzip >/dev/null 2>&1; then
    if [ "$#" -gt 0 ]; then unzip -o -q "$zip" "$@" -d "$dest"; else unzip -o -q "$zip" -d "$dest"; fi
  elif [ -n "$PYTHON" ]; then
    "$PYTHON" -c '
import sys, zipfile, os
zf, dest, names = sys.argv[1], sys.argv[2], sys.argv[3:]
with zipfile.ZipFile(zf) as z:
    z.extractall(dest, members=names or None)
' "$zip" "$dest" "$@"
  else
    local jarbin; jarbin="$(find_jar_bin)"
    if [ -n "$jarbin" ]; then
      ( cd "$dest" && "$jarbin" xf "$zip" "$@" )
    else
      extract_zip "$zip" "$dest"
    fi
  fi
}

# --- APK'dan gerekli dosyalar -------------------------------------------------
info "APK'dan libil2cpp.so ve global-metadata.dat çıkarılıyor..."
rm -rf "$EXTRACT"; mkdir -p "$EXTRACT"

SO_CANDIDATES="lib/arm64-v8a/libil2cpp.so lib/armeabi-v7a/libil2cpp.so"
META="assets/bin/Data/Managed/Metadata/global-metadata.dat"

SO_PATH=""
for c in $SO_CANDIDATES; do
  if unzip_into "$SRC" "$EXTRACT" "$c" >/dev/null 2>&1 && [ -f "$EXTRACT/$c" ]; then
    SO_PATH="$EXTRACT/$c"; break
  fi
done
[ -n "$SO_PATH" ] || die "libil2cpp.so bulunamadı. Oyun IL2CPP değil olabilir — önce: ./tr.sh info"

unzip_into "$SRC" "$EXTRACT" "$META" >/dev/null 2>&1 || true
[ -f "$EXTRACT/$META" ] || die "global-metadata.dat bulunamadı."

ok "libil2cpp.so  ($(du -h "$SO_PATH" | cut -f1))"
ok "global-metadata.dat  ($(du -h "$EXTRACT/$META" | cut -f1))"

# --- Il2CppDumper -------------------------------------------------------------
if [ ! -f "$TOOL_DIR/Il2CppDumper.exe" ]; then
  info "Il2CppDumper $IL2CPP_VER indiriliyor..."
  mkdir -p "$BIN_DIR"
  curl -fL --retry 4 --retry-delay 2 --progress-bar -o "$BIN_DIR/il2cppdumper.zip" "$IL2CPP_URL" \
    || die "Il2CppDumper indirilemedi."
  rm -rf "$TOOL_DIR"
  extract_zip "$BIN_DIR/il2cppdumper.zip" "$TOOL_DIR"
  rm -f "$BIN_DIR/il2cppdumper.zip"
  ok "Il2CppDumper -> $TOOL_DIR"
fi

rm -rf "$DUMP_DIR"; mkdir -p "$DUMP_DIR"

info "Döküm alınıyor (birkaç dakika sürebilir)..."
if is_msys && [ -f "$TOOL_DIR/Il2CppDumper.exe" ]; then
  # Windows: .NET Framework derlemesi, ek runtime gerekmez.
  ( cd "$TOOL_DIR" && ./Il2CppDumper.exe "$(cygpath -w "$SO_PATH")" \
      "$(cygpath -w "$EXTRACT/$META")" "$(cygpath -w "$DUMP_DIR")" ) \
    || die "Il2CppDumper hata verdi."
elif command -v dotnet >/dev/null 2>&1; then
  ( cd "$TOOL_DIR" && dotnet Il2CppDumper.dll "$SO_PATH" "$EXTRACT/$META" "$DUMP_DIR" ) \
    || die "Il2CppDumper hata verdi."
else
  die "Bu platformda Il2CppDumper çalıştırılamıyor.
     Windows'ta doğrudan çalışır; Linux/macOS'ta 'dotnet' kur ya da net8 sürümünü kullan."
fi

[ -f "$DUMP_DIR/dump.cs" ] || die "dump.cs üretilmedi."
ok "Döküm hazır: $DUMP_DIR/dump.cs  ($(du -h "$DUMP_DIR/dump.cs" | cut -f1))"

echo
info "İlgi çekici sınıflar (para / trafik / hız):"
grep -inE 'class .*(money|cash|coin|player|traffic|spawn|speed|car|game ?manager)' "$DUMP_DIR/dump.cs" \
  | head -40 | sed 's/^/    /' || warn "Doğrudan eşleşme yok — dump.cs'i elle incele."

echo
info "Bu çıktıyı paylaş; hangi fonksiyonların hook'lanacağını birlikte seçelim."
