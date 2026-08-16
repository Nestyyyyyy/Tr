#!/usr/bin/env bash
# Orijinali kaldırır, yamalı APK'yı kurar ve run-as erişimini doğrular.
# DİKKAT: kaldırma işlemi mevcut oyun ilerlemesini siler (imza değiştiği için kaçınılmaz).

source "$(dirname "$0")/lib.sh"

need_device

APK="${1:-}"

if [ -n "$APK" ] && [ ! -f "$APK" ]; then
  warn "Böyle bir dosya yok: $APK"
  if ls -1 "$OUT_DIR"/*.apk >/dev/null 2>&1; then
    info "out/ içinde bulunanlar:"
    ls -1 "$OUT_DIR"/*.apk | sed 's|.*/|    |'
  else
    warn "out/ klasöründe hiç APK yok — üretim adımı tamamlanmamış."
  fi
  die "Menülü sürüm için önce:  ./tr.sh menu
     Sade (menüsüz) sürüm için: ./tr.sh patch"
fi

if [ -z "$APK" ]; then
  # Argüman verilmediyse: önce menülü sürüm, yoksa sade sürüm.
  APK="$(first_match "$OUT_DIR" '*-menu.apk')"
  [ -n "$APK" ] || APK="$(first_match "$OUT_DIR" '*-debuggable.apk')"
fi

[ -n "$APK" ] && [ -f "$APK" ] || die "Kurulacak APK yok.
     Menülü sürüm için:  ./tr.sh menu
     Sade sürüm için:    ./tr.sh patch"

info "Kurulacak: $APK"

# Kurulumu yalnızca cihazdaki APK ile YERELDEKİ AYNI dosya ise atla.
# Eskiden "kurulu + run-as çalışıyor" yetiyordu; bu yüzden menülü sürümü kurmak
# istediğinde eski (menüsüz) sürüm kurulu diye kurulum sessizce atlanıyordu.
installed_apk_size() {
  local path
  path="$(adb shell pm path "$PKG" 2>/dev/null | tr -d '\r' | sed -n 's/^package://p' | head -1 || true)"
  [ -n "$path" ] || return 1
  adb shell "stat -c %s '$path'" 2>/dev/null | tr -d '\r'
}

if pkg_installed; then
  LOCAL_SIZE="$(wc -c < "$APK" | tr -d ' ')"
  DEVICE_SIZE="$(installed_apk_size || true)"
  if [ -n "$DEVICE_SIZE" ] && [ "$DEVICE_SIZE" = "$LOCAL_SIZE" ] \
     && adb shell run-as "$PKG" ls >/dev/null 2>&1; then
    ok "Bu APK zaten kurulu (aynı boyut: $LOCAL_SIZE) — kurulum atlandı."
    echo
    info "Farklı bir sürüm kurmak istiyorsan dosya yolunu ver:  ./tr.sh install <apk>"
    exit 0
  fi
  [ -n "$DEVICE_SIZE" ] && info "Cihazdaki sürüm farklı ($DEVICE_SIZE bayt), yenisi kurulacak."
fi

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
# Göreli yol: Git Bash'in yol dönüşümüne takılmasın.
# Çıktıyı dosyaya alıyoruz: "adb install" hata kodunu metinde veriyor, çıkış kodunda değil.
INSTALL_LOG="$WORK_DIR/install.log"
mkdir -p "$WORK_DIR"
( cd "$(dirname "$APK")" && adb install -r "$(basename "$APK")" ) > "$INSTALL_LOG" 2>&1 || true
sed 's/^/    /' "$INSTALL_LOG"

if grep -q 'Success' "$INSTALL_LOG"; then
  ok "Kuruldu."
else
  echo
  if grep -q 'INSTALL_FAILED_USER_RESTRICTED' "$INSTALL_LOG"; then
    warn "Telefon USB üzerinden kurulumu engelliyor (INSTALL_FAILED_USER_RESTRICTED)."
    warn "Xiaomi/Redmi/POCO'da yaygın. Geliştirici seçeneklerinde şunları aç:"
    warn "  • USB üzerinden yükleme (Install via USB)"
    warn "  • USB hata ayıklama (Güvenlik ayarları)"
    warn "  • MIUI optimizasyonu -> KAPAT   (ilerideki run-as için de gerekli)"
  else
    warn "Kurulum adb ile yapılamadı. Ayrıntı: $INSTALL_LOG"
  fi

  # Kaçış yolu: APK'yı telefona kopyala, kullanıcı dosya yöneticisinden kursun.
  # "USB üzerinden yükleme" kapalıyken bile bu yol çalışır.
  echo
  info "Alternatif yol deneniyor: APK telefona kopyalanıyor..."
  if ( cd "$(dirname "$APK")" && MSYS_NO_PATHCONV=1 adb push "$(basename "$APK")" /sdcard/Download/trafficracer-mod.apk >/dev/null ); then
    ok "Kopyalandı -> telefonda: İndirilenler / Download / trafficracer-mod.apk"
    echo
    info "Şimdi TELEFONDAN kur:"
    info "  1. Dosyalar (Dosya Yöneticisi) uygulamasını aç"
    info "  2. İndirilenler klasörü -> trafficracer-mod.apk -> dokun"
    info "  3. 'Bilinmeyen kaynaklara izin ver' çıkarsa onayla, sonra Yükle"
    info "  4. Kurulum bitince burada çalıştır:  ./tr.sh install"
    echo
    die "Kurulumu telefondan tamamla, sonra bu komutu tekrar çalıştır."
  else
    die "APK telefona kopyalanamadı da. Yukarıdaki izinleri açıp tekrar dene."
  fi
fi

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
