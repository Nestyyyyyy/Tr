#!/usr/bin/env bash
# Orijinali kaldırır, yamalı APK'yı kurar ve run-as erişimini doğrular.
# DİKKAT: kaldırma işlemi mevcut oyun ilerlemesini siler (imza değiştiği için kaçınılmaz).

source "$(dirname "$0")/lib.sh"

need_device

APK="${1:-}"
if [ -z "$APK" ]; then
  APK="$(ls -1 "$OUT_DIR"/*-debuggable.apk 2>/dev/null | head -1)"
fi
[ -n "$APK" ] && [ -f "$APK" ] || die "Kurulacak APK yok. Önce: ./tools/02-patch.sh"

info "Kurulacak: $APK"

if pkg_installed; then
  warn "'$PKG' kurulu. İmza farklı olduğu için kaldırılması şart."
  warn "Bu işlem mevcut para/skor/araç ilerlemeni SİLER."
  if [ "${YES:-0}" != "1" ]; then
    printf 'Devam edilsin mi? (evet yaz): '
    read -r answer
    [ "$answer" = "evet" ] || die "İptal edildi."
  fi
  info "Kaldırılıyor..."
  adb uninstall "$PKG" >/dev/null || die "Kaldırılamadı."
  ok "Kaldırıldı."
fi

info "Kuruluyor..."
adb install -r "$APK" || die "Kurulum başarısız. (Telefonda 'USB ile kurulum' iznini onaylaman gerekebilir.)"

pkg_installed || die "Kurulum sonrası paket görünmüyor."
ok "Kuruldu."

info "run-as erişimi kontrol ediliyor..."
if adb shell run-as "$PKG" ls >/dev/null 2>&1; then
  ok "run-as çalışıyor — kayıt dosyasını root'suz düzenleyebilirsin."
else
  warn "run-as reddedildi. Bazı üretici ROM'ları (özellikle Xiaomi/MIUI) bunu kısıtlar."
  warn "Çare: geliştirici seçeneklerinde 'MIUI optimizasyonu'nu kapat, ya da bir emülatör kullan."
fi

echo
info "Şimdi oyunu bir kez aç, birkaç saniye oyna ve ana menüye dön (kayıt dosyası böylece oluşur)."
info "Sonra: ./tools/04-prefs.sh list"
