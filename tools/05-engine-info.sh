#!/usr/bin/env bash
# Plan B keşfi: APK Mono mu IL2CPP mi? Kayıt dosyası düzenlemek yetmezse
# hangi dosyaya bakman gerektiğini söyler. Hiçbir şeyi değiştirmez.

source "$(dirname "$0")/lib.sh"

SRC="${1:-$WORK_DIR/original.apk}"
[ -f "$SRC" ] || die "APK yok: $SRC  (önce ./tools/01-pull.sh)"

# unzip Git Bash'te yok; python varsa onunla aynı işi yaparız.
HAVE_UNZIP=0
command -v unzip >/dev/null 2>&1 && HAVE_UNZIP=1
if [ "$HAVE_UNZIP" = "0" ] && [ -z "$PYTHON" ]; then
  die "unzip da python3 de yok. Birini kur (Windows: python.org, 'Add to PATH' işaretli)."
fi

# "boyut tarih saat ad" biçiminde liste (unzip -l ile aynı sütun düzeni)
list_apk() {
  if [ "$HAVE_UNZIP" = "1" ]; then
    unzip -l "$1"
  else
    "$PYTHON" -c '
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    for i in z.infolist():
        print("%9d %s %s %s" % (i.file_size, "0000-00-00", "00:00", i.filename))
' "$1"
  fi
}

# Unity sürümünü globalgamemanagers içinden çıkar (bulamazsa sessizce boş döner)
unity_version() {
  local member="assets/bin/Data/globalgamemanagers"
  if [ -n "$PYTHON" ]; then
    "$PYTHON" -c '
import re, sys, zipfile
try:
    with zipfile.ZipFile(sys.argv[1]) as z:
        data = z.read(sys.argv[2])
except Exception:
    sys.exit(0)
m = re.search(rb"20[0-9]{2}\.[0-9]+\.[0-9]+[a-z0-9]*", data)
if m:
    print(m.group(0).decode("ascii", "replace"))
' "$1" "$member"
  elif command -v strings >/dev/null 2>&1; then
    unzip -p "$1" "$member" 2>/dev/null | strings | grep -m1 -E '^20[0-9]{2}\.[0-9]+\.[0-9]+' || true
  fi
}

LIST="$WORK_DIR/apk-listing.txt"
mkdir -p "$WORK_DIR"
list_apk "$SRC" > "$LIST" || die "APK okunamadı."

info "APK: $SRC"
echo

if grep -q 'assets/bin/Data/Managed/Assembly-CSharp.dll' "$LIST"; then
  ok "Motor: Unity + MONO  (kolay taraf)"
  echo "    Oyun mantığı doğrudan C# olarak duruyor:"
  echo "      assets/bin/Data/Managed/Assembly-CSharp.dll"
  echo "    Yapılacak: dosyayı çıkar, dnSpyEx ile aç, ilgili metodu düzenle, APK'ya geri koy,"
  echo "    02-patch.sh mantığıyla yeniden imzala."
elif grep -q 'libil2cpp.so' "$LIST"; then
  ok "Motor: Unity + IL2CPP  (zor taraf)"
  echo "    Kod native'e derlenmiş. İlgili dosyalar:"
  grep -E 'libil2cpp\.so|global-metadata\.dat' "$LIST" | sed 's/^/      /'
  echo
  echo "    Yol: Il2CppDumper ile global-metadata.dat + libil2cpp.so'dan sembolleri çıkar,"
  echo "    Ghidra/IDA'da hedef fonksiyonu bul, ARM64 talimatını yamala."
  echo "    Daha hızlı alternatif: APK'ya frida-gadget enjekte edip runtime'da hook'la."
else
  warn "Unity izi bulunamadı; farklı bir motor olabilir."
fi

echo
info "Mimariler:"
grep -oE 'lib/[a-z0-9_-]+/' "$LIST" | sort -u | sed 's|lib/||; s|/||; s/^/    /' \
  || echo "    (native kütüphane yok)"

UV="$(unity_version "$SRC" || true)"
[ -n "$UV" ] && info "Unity sürümü: $UV"

echo
info "Boyutça en büyük 10 dosya:"
sort -k1 -n -r "$LIST" | grep -E '^\s*[0-9]+' \
  | awk '$4 != "" && $4 != "files" {printf "    %10s  %s\n", $1, $4}' | head -10
