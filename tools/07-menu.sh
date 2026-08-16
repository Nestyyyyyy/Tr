#!/usr/bin/env bash
# Oyun içi mod menüsünü APK'ya enjekte eder.
#
# Yapılanlar:
#   1. frida-gadget (arm64) lib/arm64-v8a/ altına konur
#   2. gadget yapılandırması: ajanı /data/data/<paket>/files/agent.js'ten okur,
#      dosya değişince kendini yeniden yükler (on_change: reload)
#   3. Açılış Activity'sine System.loadLibrary("frida-gadget") eklenir
#   4. manifest'e debuggable + allowBackup
#   5. yeniden paketle, zipalign, imzala
#
# Bu işlem BİR KEZ yapılır. Sonrasında menüyü değiştirmek için sadece
# ./tr.sh agent  yeterli — APK'ya bir daha dokunulmaz.

source "$(dirname "$0")/lib.sh"

need_java
need_jar "$APKTOOL_JAR"
need_jar "$SIGNER_JAR"

SRC="$WORK_DIR/original.apk"
DEC="$WORK_DIR/menu-decoded"
UNSIGNED="$WORK_DIR/menu-unsigned.apk"
GADGET_ZIP="$ROOT_DIR/menu/vendor/libfrida-gadget.zip"

[ -f "$SRC" ] || die "work/original.apk yok. Önce: ./tr.sh pull"
[ -f "$GADGET_ZIP" ] || die "frida-gadget paketi yok: $GADGET_ZIP"

mkdir -p "$OUT_DIR" "$WORK_DIR"
rm -rf "$DEC"; rm -f "$UNSIGNED"

# --- 1. APK'yı aç (sadece classes.dex; digerleri ham kopyalanir) --------------
info "APK açılıyor (yalnızca classes.dex çözülüyor, birkaç dakika sürebilir)..."
DECODE_FLAGS="--only-main-classes"
if [ "${FULL_DECODE:-0}" = "1" ]; then
  warn "FULL_DECODE=1 — tüm dex dosyaları çözülecek, bu çok daha yavaş."
  DECODE_FLAGS=""
fi
# shellcheck disable=SC2086
java -jar "$APKTOOL_JAR" d $DECODE_FLAGS -f -o "$DEC" "$SRC" >/dev/null \
  || die "apktool decode başarısız."

MANIFEST="$DEC/AndroidManifest.xml"
[ -f "$MANIFEST" ] || die "AndroidManifest.xml çıkmadı."
APK_PKG="$(sed -n 's/.*package="\([^"]*\)".*/\1/p' "$MANIFEST" | head -1)"
[ -n "$APK_PKG" ] || die "Paket adı okunamadı."
info "Paket: $APK_PKG"

# --- 2. Açılış Activity'sini bul ---------------------------------------------
info "Açılış Activity'si aranıyor..."
LAUNCHER="$(awk '
  /<activity/            { cur = $0; inact = 1 }
  inact && /android:name=/ && cur !~ /android:name=/ { cur = cur " " $0 }
  /android.intent.category.LAUNCHER/ { found = 1 }
  /<\/activity>/ {
    if (found) {
      # cur icindeki ilk android:name degerini al
      if (match(cur, /android:name="[^"]*"/)) {
        s = substr(cur, RSTART + 14, RLENGTH - 15)
        print s; exit
      }
    }
    inact = 0; found = 0; cur = ""
  }
' "$MANIFEST")"

[ -n "$LAUNCHER" ] || die "Açılış Activity'si bulunamadı (manifest'i elle incele: $MANIFEST)"
case "$LAUNCHER" in
  .*) LAUNCHER="${APK_PKG}${LAUNCHER}" ;;   # ".MainActivity" -> tam ad
esac
ok "Açılış Activity'si: $LAUNCHER"

SMALI_REL="$(printf '%s' "$LAUNCHER" | tr '.' '/').smali"
SMALI_FILE=""
for d in "$DEC"/smali "$DEC"/smali_classes*; do
  [ -d "$d" ] || continue
  if [ -f "$d/$SMALI_REL" ]; then SMALI_FILE="$d/$SMALI_REL"; break; fi
done

if [ -z "$SMALI_FILE" ]; then
  die "Activity'nin smali dosyası bulunamadı: $SMALI_REL
     Sınıf classes.dex dışında bir dex'te olabilir. Şunu dene:
       FULL_DECODE=1 ./tr.sh menu"
fi
ok "smali: ${SMALI_FILE#$DEC/}"

# --- 3. System.loadLibrary("frida-gadget") enjekte et ------------------------
if grep -q 'frida-gadget' "$SMALI_FILE"; then
  ok "gadget yükleme kodu zaten var"
else
  info "loadLibrary çağrısı ekleniyor..."
  awk '
    BEGIN { done = 0; inclinit = 0 }
    # Mevcut bir <clinit> varsa oraya yaz
    /^\.method static constructor <clinit>\(\)V/ { inclinit = 1; print; next }
    inclinit && /^[ \t]*\.locals[ \t]+[0-9]+/ {
      n = $2 + 0
      if (n < 1) n = 1
      print "    .locals " n
      print "    const-string v0, \"frida-gadget\""
      print "    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V"
      inclinit = 0; done = 1; next
    }
    inclinit && /^[ \t]*\.registers[ \t]+[0-9]+/ {
      n = $2 + 0
      if (n < 1) n = 1
      print "    .registers " n
      print "    const-string v0, \"frida-gadget\""
      print "    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V"
      inclinit = 0; done = 1; next
    }
    { print }
    END {
      if (!done) {
        # <clinit> yoktu: yenisini ekle
        print ""
        print ".method static constructor <clinit>()V"
        print "    .locals 1"
        print "    const-string v0, \"frida-gadget\""
        print "    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V"
        print "    return-void"
        print ".end method"
      }
    }
  ' "$SMALI_FILE" > "$SMALI_FILE.new" && mv "$SMALI_FILE.new" "$SMALI_FILE"

  grep -q 'frida-gadget' "$SMALI_FILE" || die "Enjeksiyon başarısız."
  ok "loadLibrary eklendi"
fi

# --- 4. gadget kütüphanesi + yapılandırma ------------------------------------
LIBDIR="$DEC/lib/arm64-v8a"
[ -d "$LIBDIR" ] || die "lib/arm64-v8a yok — APK arm64 içermiyor olabilir."

info "frida-gadget yerleştiriliyor..."
( cd "$LIBDIR" && jar xf "$GADGET_ZIP" ) || die "gadget açılamadı."
[ -f "$LIBDIR/libfrida-gadget.so" ] || die "libfrida-gadget.so çıkmadı."
ok "libfrida-gadget.so ($(du -h "$LIBDIR/libfrida-gadget.so" | cut -f1))"

# Gadget, kendi adının yanındaki .config.so dosyasını okur.
cat > "$LIBDIR/libfrida-gadget.config.so" <<EOF
{
  "interaction": {
    "type": "script",
    "path": "/data/data/$APK_PKG/files/agent.js",
    "on_change": "reload"
  }
}
EOF
ok "gadget yapılandırması yazıldı (ajan: files/agent.js, değişince yeniden yüklenir)"

# --- 5. manifest + paketle + imzala ------------------------------------------
info "Manifest yamalanıyor..."
patch_manifest "$MANIFEST"

info "Yeniden paketleniyor (uzun sürebilir)..."
java -jar "$APKTOOL_JAR" b "$DEC" -o "$UNSIGNED" >/dev/null \
  || die "apktool build başarısız. Log: $DEC"

info "Zipalign + imzalama..."
rm -f "$OUT_DIR"/menu-unsigned-aligned*.apk "$OUT_DIR"/menu-unsigned-aligned*.idsig
java -jar "$SIGNER_JAR" -a "$UNSIGNED" -o "$OUT_DIR" --allowResign >/dev/null \
  || die "İmzalama başarısız."

SIGNED="$(ls -1 "$OUT_DIR"/menu-unsigned-aligned*Signed.apk 2>/dev/null | head -1)"
[ -n "$SIGNED" ] || die "İmzalı APK üretilemedi."
FINAL="$OUT_DIR/${APK_PKG}-menu.apk"
mv "$SIGNED" "$FINAL"
rm -f "$OUT_DIR"/menu-unsigned-aligned*.idsig

echo
ok "Hazır: $FINAL  ($(du -h "$FINAL" | cut -f1))"
echo
info "Sıradaki adımlar:"
info "  1. ./tr.sh install $FINAL     (orijinali kaldırıp bunu kurar)"
info "  2. ./tr.sh agent               (menü ajanını telefona gönderir)"
info "  3. Oyunu aç — sol üstte kırmızı 'MOD' düğmesi görünecek"
warn "Ajanı göndermeden oyunu açma: gadget dosyayı bulamazsa oyun açılmayabilir."
