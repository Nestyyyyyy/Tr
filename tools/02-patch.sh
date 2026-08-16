#!/usr/bin/env bash
# work/original.apk -> manifest'e android:debuggable="true" + allowBackup="true" ekler,
# yeniden paketler ve imzalar.  Oyun koduna/dex'e HİÇ dokunulmaz (en düşük riskli yöntem).
# Sonuç: out/<paket>-debuggable.apk

source "$(dirname "$0")/lib.sh"

need_java
need_jar "$APKTOOL_JAR"
need_jar "$SIGNER_JAR"

SRC="$WORK_DIR/original.apk"
DEC="$WORK_DIR/decoded"
UNSIGNED="$WORK_DIR/unsigned.apk"

[ -f "$SRC" ] || die "work/original.apk yok. Önce: ./tools/01-pull.sh"

mkdir -p "$OUT_DIR"
rm -rf "$DEC"; rm -f "$UNSIGNED"

# -s = dex'i smali'ye çevirme. Sadece manifest lazım; hem 10 kat hızlı hem de
# smali yeniden derleme hatalarını tamamen ortadan kaldırır.
info "APK açılıyor (kaynaklar + manifest, dex dokunulmadan)..."
java -jar "$APKTOOL_JAR" d -s -f -o "$DEC" "$SRC" >/dev/null || die "apktool decode başarısız."

MANIFEST="$DEC/AndroidManifest.xml"
[ -f "$MANIFEST" ] || die "AndroidManifest.xml çıkmadı."

APK_PKG="$(sed -n 's/.*package="\([^"]*\)".*/\1/p' "$MANIFEST" | head -1)"
info "Paket: ${APK_PKG:-?}"

info "Manifest yamalanıyor..."
patch_manifest "$MANIFEST"

info "Yeniden paketleniyor..."
java -jar "$APKTOOL_JAR" b "$DEC" -o "$UNSIGNED" >/dev/null \
  || die "apktool build başarısız. (Nadir; olursa work/decoded/ altındaki apktool loglarına bak.)"

info "Zipalign + imzalama (uber-apk-signer'ın debug anahtarı)..."
FINAL="$OUT_DIR/${APK_PKG:-app}-debuggable.apk"
sign_apk "$UNSIGNED" "$FINAL"

echo
ok "Hazır: $FINAL  ($(du -h "$FINAL" | cut -f1))"
warn "İmza değişti: orijinal uygulamanın ÜZERİNE kurulmaz, önce kaldırılması gerekir (mevcut ilerleme silinir)."
info "Sıradaki adım: ./tools/03-install.sh"
