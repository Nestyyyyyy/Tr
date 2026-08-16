#!/usr/bin/env bash
# Plan B keşfi: APK Mono mu IL2CPP mi? Kayıt dosyası düzenlemek yetmezse
# hangi dosyaya bakman gerektiğini söyler. Hiçbir şeyi değiştirmez.

source "$(dirname "$0")/lib.sh"

need_cmd unzip "sudo apt install unzip"

SRC="${1:-$WORK_DIR/original.apk}"
[ -f "$SRC" ] || die "APK yok: $SRC  (önce ./tools/01-pull.sh)"

LIST="$WORK_DIR/apk-listing.txt"
mkdir -p "$WORK_DIR"
unzip -l "$SRC" > "$LIST" || die "APK okunamadı."

info "APK: $SRC"
echo

if grep -q 'assets/bin/Data/Managed/Assembly-CSharp.dll' "$LIST"; then
  ok "Motor: Unity + MONO  (kolay taraf)"
  echo "    Oyun mantığı doğrudan C# olarak duruyor:"
  echo "      assets/bin/Data/Managed/Assembly-CSharp.dll"
  echo "    Yapılacak: dosyayı çıkar, dnSpyEx ile aç, ilgili metodu düzenle, APK'ya geri koy,"
  echo "    ./tools/02-patch.sh mantığıyla yeniden imzala."
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
grep -oE 'lib/[a-z0-9_-]+/' "$LIST" | sort -u | sed 's|lib/||; s|/||; s/^/    /' || echo "    (native kütüphane yok)"

if grep -q 'assets/bin/Data/globalgamemanagers' "$LIST"; then
  UV="$(unzip -p "$SRC" assets/bin/Data/globalgamemanagers 2>/dev/null \
        | strings 2>/dev/null | grep -m1 -E '^20[0-9]{2}\.[0-9]+\.[0-9]+' || true)"
  [ -n "$UV" ] && info "Unity sürümü: $UV"
fi

echo
info "Boyutça en büyük 10 dosya:"
sort -k1 -n -r "$LIST" | grep -E '^\s*[0-9]+' \
  | awk '$4 != "" && $4 != "files" {printf "    %10s  %s\n", $1, $4}' | head -10
