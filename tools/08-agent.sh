#!/usr/bin/env bash
# Menü ajanını telefona gönderir ve çıktılarını geri alır.
#
#   ./tr.sh agent          ajanı gönder (gadget dosyayı görünce kendini yeniler)
#   ./tr.sh agent status   teşhis: gadget açılmış mı, ajan yerinde mi, logcat
#   ./tr.sh agent log      telefondaki mod.log'u göster
#   ./tr.sh agent classes  oyunun sınıf listesini çek -> work/classes.txt
#   ./tr.sh agent dump     tam dökümü çek -> work/dump.cs
#
# APK'ya bir daha dokunulmuyor: gadget "on_change: reload" ile çalışıyor, yani
# ajanı gönderip oyunu yeniden açman yeterli.

source "$(dirname "$0")/lib.sh"

CMD="${1:-push}"

need_device
pkg_installed || die "'$PKG' kurulu değil."
adb shell run-as "$PKG" ls >/dev/null 2>&1 \
  || die "run-as çalışmıyor — menülü sürüm kurulu mu? (./tr.sh install)"

AGENT="$ROOT_DIR/menu/dist/agent.js"
mkdir -p "$WORK_DIR"

case "$CMD" in
  push)
    [ -f "$AGENT" ] || die "Ajan yok: $AGENT"
    adb shell "run-as $PKG mkdir -p files" >/dev/null 2>&1 || true
    info "Ajan gönderiliyor ($(du -h "$AGENT" | cut -f1))..."
    push_app_file "$AGENT" "files/agent.js"
    ok "Gönderildi ve doğrulandı: files/agent.js"
    echo
    info "Oyunu (yeniden) aç — sol üstte kırmızı 'MOD' düğmesi çıkacak."
    info "Sorun olursa:  ./tr.sh agent log"
    ;;

  status)
    info "Paket: $PKG"
    ok "run-as çalışıyor"

    # 1. Gadget diske açılmış mı? (extractNativeLibs kapalıysa açılmaz ve
    #    gadget ayar dosyasını bulamayıp 'listen' moduna düşer -> oyun kilitlenir)
    NLD="$(adb shell dumpsys package "$PKG" 2>/dev/null | tr -d '\r' \
           | sed -n 's/.*nativeLibraryPath=\([^ ]*\).*/\1/p;s/.*legacyNativeLibraryDir=\([^ ]*\).*/\1/p' \
           | head -1 || true)"
    echo
    if [ -n "$NLD" ]; then
      info "Native kütüphane klasörü: $NLD"
      LIBS="$(adb shell ls "$NLD"/arm64 "$NLD" 2>/dev/null | tr -d '\r' | grep -i frida || true)"
      if [ -n "$LIBS" ]; then
        ok "gadget diske açılmış:"
        printf '%s\n' "$LIBS" | sed 's/^/    /'
        printf '%s\n' "$LIBS" | grep -q 'config' \
          && ok "ayar dosyası da var (script modu çalışır)" \
          || warn "AYAR DOSYASI YOK -> gadget 'listen' moduna düşer ve oyunu kilitler."
      else
        warn "gadget diske AÇILMAMIŞ -> extractNativeLibs kapalı demektir."
        warn "Çözüm: ./tr.sh menu (düzeltilmiş sürüm) + ./tr.sh install"
      fi
    else
      warn "Native kütüphane klasörü okunamadı."
    fi

    # 2. Ajan dosyası
    echo
    AG="$(adb shell "run-as $PKG ls -la files/agent.js" 2>/dev/null | tr -d '\r' || true)"
    if [ -n "$AG" ] && ! printf '%s' "$AG" | grep -qi 'no such'; then
      ok "ajan yerinde: $AG"
    else
      warn "files/agent.js YOK -> önce: ./tr.sh agent"
    fi

    # 3. Gadget'ın kendi günlüğü
    echo
    info "logcat'te frida/gadget izleri (son 20 satır):"
    adb logcat -d 2>/dev/null | grep -iE 'frida|gadget' | tail -20 | sed 's/^/    /' \
      || warn "iz yok"
    echo
    info "Oyun çökmüşse:"
    adb logcat -d 2>/dev/null | grep -iE 'FATAL|AndroidRuntime|trafficracer' | tail -15 | sed 's/^/    /' \
      || warn "çökme kaydı yok"
    ;;

  log)
    if pull_app_file "files/mod.log" "$WORK_DIR/mod.log"; then
      info "files/mod.log:"
      sed 's/^/    /' "$WORK_DIR/mod.log"
    else
      warn "mod.log yok. Ajan hiç çalışmamış olabilir."
      info "Gadget'ın kendi günlüğü için:  adb logcat -d | grep -i frida"
    fi
    ;;

  classes)
    if pull_app_file "files/classes.txt" "$WORK_DIR/classes.txt"; then
      ok "Çekildi -> work/classes.txt ($(du -h "$WORK_DIR/classes.txt" | cut -f1))"
      echo
      info "Para / trafik / hız ile ilgili sınıflar:"
      grep -inE '^[A-Za-z].*(money|cash|coin|traffic|spawn|speed|player|car|game|score|nitro|boost)' \
        "$WORK_DIR/classes.txt" | head -40 | sed 's/^/    /' \
        || warn "Doğrudan eşleşme yok — dosyayı elle incele."
    else
      die "classes.txt yok. Menüden 'Sınıf listesi çıkar'a bas, sonra tekrar dene."
    fi
    ;;

  dump)
    if pull_app_file "files/dump.cs" "$WORK_DIR/dump.cs"; then
      ok "Çekildi -> work/dump.cs ($(du -h "$WORK_DIR/dump.cs" | cut -f1))"
    else
      die "dump.cs yok. Menüden 'Tam döküm'e bas (uzun sürer), sonra tekrar dene."
    fi
    ;;

  *)
    die "Bilinmeyen komut: $CMD  (push | status | log | classes | dump)"
    ;;
esac
