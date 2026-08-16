#!/usr/bin/env bash
# Menü ajanını telefona gönderir ve çıktılarını geri alır.
#
#   ./tr.sh agent          ajanı gönder (gadget dosyayı görünce kendini yeniler)
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
    die "Bilinmeyen komut: $CMD  (push | log | classes | dump)"
    ;;
esac
