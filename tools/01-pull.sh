#!/usr/bin/env bash
# Oyunun APK'sını KENDİ telefonundan çeker. Split (App Bundle) ise tek APK'ya birleştirir.
# Sonuç: work/original.apk

source "$(dirname "$0")/lib.sh"

need_device
need_java

if ! pkg_installed; then
  die "'$PKG' bu cihazda kurulu değil. Önce Play Store'dan kur, bir kez aç, sonra tekrar dene.
     (Farklı bir paket için:  PKG=com.ornek.oyun ./tools/01-pull.sh )"
fi

mkdir -p "$WORK_DIR/splits"
rm -f "$WORK_DIR/splits/"*.apk "$WORK_DIR/original.apk"

info "'$PKG' için APK yolları okunuyor..."
mapfile -t PATHS < <(adb shell pm path "$PKG" | tr -d '\r' | sed -n 's/^package://p')
[ "${#PATHS[@]}" -gt 0 ] || die "APK yolu bulunamadı."

info "${#PATHS[@]} adet APK parçası bulundu, çekiliyor..."
for p in "${PATHS[@]}"; do
  name="$(basename "$p")"
  adb pull "$p" "$WORK_DIR/splits/$name" >/dev/null || die "Çekilemedi: $p"
  printf '    %s (%s)\n' "$name" "$(du -h "$WORK_DIR/splits/$name" | cut -f1)"
done

if [ "${#PATHS[@]}" -eq 1 ]; then
  cp "$WORK_DIR/splits/$(basename "${PATHS[0]}")" "$WORK_DIR/original.apk"
  ok "Tek APK. -> work/original.apk"
else
  need_jar "$APKEDITOR_JAR"
  info "Split APK tespit edildi, APKEditor ile birleştiriliyor..."
  java -jar "$APKEDITOR_JAR" m -i "$WORK_DIR/splits" -o "$WORK_DIR/original.apk" -f \
    || die "Birleştirme başarısız."
  ok "Birleştirildi. -> work/original.apk"
fi

VER="$(adb shell dumpsys package "$PKG" | tr -d '\r' | sed -n 's/.*versionName=\(.*\)/\1/p' | head -1)"
echo
ok "Sürüm: ${VER:-bilinmiyor} | Boyut: $(du -h "$WORK_DIR/original.apk" | cut -f1)"
warn "Bu APK senin cihazından geldi; asla yeniden dağıtma."
info "Sıradaki adım: ./tools/02-patch.sh"
