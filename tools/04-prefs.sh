#!/usr/bin/env bash
# Oyunun kayıt dosyasını (Unity PlayerPrefs = Android SharedPreferences XML)
# root OLMADAN, run-as üzerinden okur/yazar.
#
# Kullanım:
#   ./tools/04-prefs.sh list            # tüm anahtarları ve değerleri göster
#   ./tools/04-prefs.sh guess           # para/altın olabilecek anahtarları tahmin et
#   ./tools/04-prefs.sh get <anahtar>
#   ./tools/04-prefs.sh set <anahtar> <değer>
#   ./tools/04-prefs.sh backup          # kayıt dosyasını out/ altına yedekle
#   ./tools/04-prefs.sh pull [dosya]    # cihazdan çek
#   ./tools/04-prefs.sh push [dosya]    # elle düzenlediğin dosyayı geri yaz

source "$(dirname "$0")/lib.sh"

CMD="${1:-list}"; shift || true
LOCAL="$WORK_DIR/prefs.xml"
EDITOR_PY="$ROOT_DIR/tools/prefs_edit.py"

need_device
pkg_installed || die "'$PKG' kurulu değil."

if ! adb shell run-as "$PKG" ls >/dev/null 2>&1; then
  die "run-as reddedildi. Yamalı (debuggable) sürüm kurulu değil ya da ROM izin vermiyor.
     Kontrol:  ./tools/03-install.sh"
fi

# --- kayıt dosyasını seç ---------------------------------------------------
pick_prefs_file() {
  if [ -n "${PREFS_FILE:-}" ]; then echo "$PREFS_FILE"; return; fi
  local files
  files="$(adb shell run-as "$PKG" ls shared_prefs 2>/dev/null | tr -d '\r' | grep '\.xml$' || true)"
  [ -n "$files" ] || die "shared_prefs boş. Oyunu bir kez açıp birkaç saniye oynadıktan sonra tekrar dene."
  # Unity 2019.3+ -> <paket>.v2.playerprefs.xml ; öncesi -> <paket>.xml
  echo "$files" | grep -i 'playerprefs' | head -1 && return 0
  echo "$files" | grep -Fx "$PKG.xml" | head -1 && return 0
  echo "$files" | head -1
}

REMOTE="$(pick_prefs_file | head -1)"
[ -n "$REMOTE" ] || die "Kayıt dosyası bulunamadı."

pull_prefs() {
  mkdir -p "$WORK_DIR"
  adb exec-out run-as "$PKG" cat "shared_prefs/$REMOTE" > "$LOCAL" 2>/dev/null \
    || die "Okunamadı: shared_prefs/$REMOTE"
  [ -s "$LOCAL" ] || die "Kayıt dosyası boş geldi."
}

push_prefs() {
  local src="$1"
  [ -s "$src" ] || die "Yazılacak dosya boş: $src"
  grep -q '</map>' "$src" || die "Bu geçerli bir prefs XML'i değil (</map> yok): $src"

  info "Oyun kapatılıyor (açıkken yazarsan üzerine yazar)..."
  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true

  local b64 len=0 i=0 chunk
  b64="$(b64_oneline "$src")"
  len=${#b64}

  adb shell "run-as $PKG sh -c 'rm -f .prefs.b64'" >/dev/null 2>&1 || true
  info "Yazılıyor (${len} bayt base64)..."
  while [ "$i" -lt "$len" ]; do
    chunk="${b64:$i:1500}"
    adb shell "run-as $PKG sh -c 'printf %s $chunk >> .prefs.b64'" >/dev/null \
      || die "Aktarım başarısız."
    i=$((i + 1500))
  done

  adb shell "run-as $PKG sh -c 'base64 -d < .prefs.b64 > shared_prefs/$REMOTE && chmod 660 shared_prefs/$REMOTE && rm -f .prefs.b64'" >/dev/null \
    || die "Cihazda dosya yazılamadı (base64 aracı yok olabilir)."

  # doğrula
  local remote_sum local_sum
  remote_sum="$(adb exec-out run-as "$PKG" cat "shared_prefs/$REMOTE" | cksum | awk '{print $1"-"$2}')"
  local_sum="$(cksum < "$src" | awk '{print $1"-"$2}')"
  [ "$remote_sum" = "$local_sum" ] || die "Doğrulama başarısız: cihazdaki dosya farklı."
  ok "Yazıldı ve doğrulandı: shared_prefs/$REMOTE"
}

case "$CMD" in
  list)
    pull_prefs
    info "Dosya: shared_prefs/$REMOTE"
    echo
    if command -v python3 >/dev/null 2>&1; then
      python3 "$EDITOR_PY" list "$LOCAL"
    else
      cat "$LOCAL"
    fi
    echo
    info "Değiştirmek için:  ./tools/04-prefs.sh set <anahtar> <değer>"
    ;;

  guess)
    pull_prefs
    info "Para/ilerleme adayı anahtarlar:"
    grep -oE 'name="[^"]*"' "$LOCAL" | sed 's/name="//; s/"$//' \
      | grep -iE 'cash|coin|money|gold|gem|credit|score|best|dist|car|level|unlock|owned|buy|purchas' \
      | sort -u | sed 's/^/    /' || warn "Eşleşme yok — 'list' ile tüm anahtarlara bak."
    echo
    warn "Değerler anlamsız/karışık görünüyorsa oyun kaydı şifreliyordur; o durumda README'deki 'Plan B' bölümüne bak."
    ;;

  get)
    KEY="${1:-}"; [ -n "$KEY" ] || die "Kullanım: $0 get <anahtar>"
    command -v python3 >/dev/null 2>&1 || die "'get' için python3 gerekli."
    pull_prefs
    python3 "$EDITOR_PY" get "$LOCAL" "$KEY" || die "'$KEY' bulunamadı. Önce: $0 list"
    ;;

  set)
    KEY="${1:-}"; VAL="${2:-}"
    [ -n "$KEY" ] && [ -n "$VAL" ] || die "Kullanım: $0 set <anahtar> <değer>"
    command -v python3 >/dev/null 2>&1 || die "'set' için python3 gerekli. Alternatif: pull -> elle düzenle -> push"

    adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
    pull_prefs

    mkdir -p "$OUT_DIR"
    BK="$OUT_DIR/prefs-backup-$(date +%Y%m%d-%H%M%S).xml"
    cp "$LOCAL" "$BK"; ok "Yedek alındı: $BK"

    python3 "$EDITOR_PY" set "$LOCAL" "$KEY" "$VAL" \
      || die "'$KEY' kayıt dosyasında yok. Önce: $0 list"

    push_prefs "$LOCAL"
    ok "Oyunu şimdi aç ve kontrol et."
    ;;

  pull)
    pull_prefs
    ok "Çekildi -> $LOCAL  (elle düzenleyip '$0 push' ile geri yaz)"
    ;;

  push)
    push_prefs "${1:-$LOCAL}"
    ;;

  backup)
    pull_prefs
    mkdir -p "$OUT_DIR"
    BK="$OUT_DIR/prefs-backup-$(date +%Y%m%d-%H%M%S).xml"
    cp "$LOCAL" "$BK"
    ok "Yedek: $BK"
    ;;

  *)
    die "Bilinmeyen komut: $CMD  (list | guess | get | set | pull | push | backup)"
    ;;
esac
