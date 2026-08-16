#!/usr/bin/env bash
# Oyunun kayıt dosyasını (Unity PlayerPrefs = Android SharedPreferences XML)
# root OLMADAN, run-as üzerinden okur/yazar.
#
# Kullanım:
#   ./tools/04-prefs.sh list            # tüm anahtarları ve değerleri göster
#   ./tools/04-prefs.sh guess           # para/altın olabilecek anahtarları tahmin et
#   ./tools/04-prefs.sh get <anahtar>
#   ./tools/04-prefs.sh set <anahtar> <değer>
#   ./tools/04-prefs.sh add <anahtar> <miktar>   # sayısal değere ekler (eksi de olur)
#   ./tools/04-prefs.sh backup          # kayıt dosyasını out/ altına yedekle
#   ./tools/04-prefs.sh pull [dosya]    # cihazdan çek
#   ./tools/04-prefs.sh push [dosya]    # elle düzenlediğin dosyayı geri yaz

source "$(dirname "$0")/lib.sh"

CMD="${1:-list}"; shift || true
LOCAL="$WORK_DIR/prefs.xml"

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

  # doğrula: cihazdaki dosyayı geri okuyup karşılaştır
  local verify="$WORK_DIR/.verify.xml"
  adb exec-out run-as "$PKG" cat "shared_prefs/$REMOTE" > "$verify" 2>/dev/null \
    || die "Doğrulama için geri okunamadı."
  if [ "$(file_sum "$verify")" != "$(file_sum "$src")" ]; then
    rm -f "$verify"
    die "Doğrulama başarısız: cihazdaki dosya yazdığımızdan farklı."
  fi
  rm -f "$verify"
  ok "Yazıldı ve doğrulandı: shared_prefs/$REMOTE"
}

case "$CMD" in
  list)
    pull_prefs
    info "Dosya: shared_prefs/$REMOTE"
    echo
    TSV="$(prefs_awk list '' '' "$LOCAL")"
    if [ -z "$TSV" ]; then
      warn "Tanınan anahtar yok. Ham dosya: $LOCAL"
      cat "$LOCAL"
    else
      W="$(printf '%s\n' "$TSV" | awk -F'\t' '{ if (length($1) > m) m = length($1) } END { print m + 0 }')"
      printf '%s\n' "$TSV" | sort | awk -F'\t' -v w="$W" '
        BEGIN { fmt = "  %-" w "s  %-8s %s\n" }
        { v = $3; if (length(v) > 60) v = substr(v, 1, 57) "..."; printf fmt, $1, $2, v }'
      printf '\n  toplam %s anahtar\n' "$(printf '%s\n' "$TSV" | wc -l | tr -d ' ')"
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
    pull_prefs
    prefs_awk get "$KEY" '' "$LOCAL" || die "'$KEY' bulunamadı. Önce: $0 list"
    ;;

  set)
    KEY="${1:-}"; VAL="${2:-}"
    [ -n "$KEY" ] && [ -n "$VAL" ] || die "Kullanım: $0 set <anahtar> <değer>"

    adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
    pull_prefs

    mkdir -p "$OUT_DIR"
    BK="$OUT_DIR/prefs-backup-$(date +%Y%m%d-%H%M%S).xml"
    cp "$LOCAL" "$BK"; ok "Yedek alındı: $BK"

    OLD="$(prefs_awk get "$KEY" '' "$LOCAL")" \
      || die "'$KEY' kayıt dosyasında yok. Önce: $0 list"

    # Önce geçici dosyaya yaz: awk hata verirse kaynak dosya bozulmasın.
    prefs_awk set "$KEY" "$VAL" "$LOCAL" > "$LOCAL.new" \
      || { rm -f "$LOCAL.new"; die "Değiştirilemedi: $KEY"; }
    mv "$LOCAL.new" "$LOCAL"
    ok "$KEY: $OLD -> $VAL"

    push_prefs "$LOCAL"
    ok "Oyunu şimdi aç ve kontrol et."
    ;;

  add)
    KEY="${1:-}"; DELTA="${2:-}"
    [ -n "$KEY" ] && [ -n "$DELTA" ] || die "Kullanım: $0 add <anahtar> <miktar>"
    case "$DELTA" in ''|*[!0-9-]*|-*-*) die "Miktar tam sayı olmalı: $DELTA" ;; esac

    adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
    pull_prefs

    CUR="$(prefs_awk get "$KEY" '' "$LOCAL")" || die "'$KEY' bulunamadı. Önce: $0 list"
    case "$CUR" in ''|*[!0-9-]*|-*-*) die "'$KEY' sayısal değil ($CUR) — 'add' kullanılamaz." ;; esac

    # Bash aritmetiği 64-bit; gizlenmiş değerler zaten int64 sınırında, taşmayı kontrol et.
    NEW=$(( CUR + DELTA ))
    if { [ "$DELTA" -gt 0 ] && [ "$NEW" -lt "$CUR" ]; } || { [ "$DELTA" -lt 0 ] && [ "$NEW" -gt "$CUR" ]; }; then
      die "64-bit taşma olurdu ($CUR + $DELTA). Daha küçük bir miktar dene."
    fi

    mkdir -p "$OUT_DIR"
    BK="$OUT_DIR/prefs-backup-$(date +%Y%m%d-%H%M%S).xml"
    cp "$LOCAL" "$BK"; ok "Yedek alındı: $BK"

    prefs_awk set "$KEY" "$NEW" "$LOCAL" > "$LOCAL.new" \
      || { rm -f "$LOCAL.new"; die "Değiştirilemedi: $KEY"; }
    mv "$LOCAL.new" "$LOCAL"
    ok "$KEY: $CUR -> $NEW  (fark: $DELTA)"

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
    die "Bilinmeyen komut: $CMD  (list | guess | get | set | add | pull | push | backup)"
    ;;
esac
