#!/usr/bin/env bash
# Cihaz/Java gerektirmeyen kendi kendine test: manifest yaması ve prefs düzenleyici
# mantığını sahte dosyalar üzerinde doğrular. Katkı yaparken bunu çalıştır.

source "$(dirname "$0")/lib.sh"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

PASS=0; FAIL=0
check() { # check <açıklama> <beklenen> <gerçek>
  if [ "$2" = "$3" ]; then
    PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"
  else
    FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n      beklenen: %s\n      gerçek  : %s\n' "$1" "$2" "$3"
  fi
}

# --- 1. sözdizimi ----------------------------------------------------------
info "sözdizimi"
for f in "$ROOT_DIR"/tools/*.sh; do
  if bash -n "$f" 2>/dev/null; then
    check "$(basename "$f")" "ok" "ok"
  else
    check "$(basename "$f")" "ok" "sözdizimi hatası"
  fi
done
if awk -f "$ROOT_DIR/tools/prefs_edit.awk" /dev/null >/dev/null 2>&1; then
  check "prefs_edit.awk" "ok" "ok"
else
  check "prefs_edit.awk" "ok" "sözdizimi hatası"
fi

# --- 2. manifest yaması ----------------------------------------------------
echo; info "patch_manifest"

M="$TMPD/a.xml"
cat > "$M" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.skgames.trafficracer">
    <application android:allowBackup="false" android:extractNativeLibs="false" android:label="Traffic Racer" android:icon="@mipmap/app_icon">
        <activity android:name="com.unity3d.player.UnityPlayerActivity" android:exported="true"/>
    </application>
</manifest>
XML
patch_manifest "$M" >/dev/null
check "debuggable eklendi"                1 "$(grep -c 'android:debuggable="true"' "$M")"
check "allowBackup false -> true"         1 "$(grep -c 'android:allowBackup="true"' "$M")"
check "allowBackup=\"false\" kalmadı"     0 "$(grep -c 'android:allowBackup="false"' "$M")"
check "extractNativeLibs false kalmadı"   0 "$(grep -c 'android:extractNativeLibs="false"' "$M")"
check "extractNativeLibs true"            1 "$(grep -c 'android:extractNativeLibs="true"' "$M")"
check "</application> bozulmadı"          1 "$(grep -c '</application>' "$M")"
check "activity satırı değişmedi"         1 "$(grep -c 'UnityPlayerActivity' "$M")"

# idempotent olmalı: ikinci kez çalıştırınca hiçbir şey artmamalı
patch_manifest "$M" >/dev/null
check "tekrar çalıştırma güvenli"         1 "$(grep -c 'android:debuggable="true"' "$M")"

M2="$TMPD/b.xml"
cat > "$M2" <<'XML'
<manifest package="x">
    <application android:label="X">
    </application>
</manifest>
XML
patch_manifest "$M2" >/dev/null
check "allowBackup yoksa eklenir"         1 "$(grep -c 'android:allowBackup="true"' "$M2")"
check "extractNativeLibs yoksa eklenir"   1 "$(grep -c 'android:extractNativeLibs="true"' "$M2")"
check "debuggable yoksa eklenir"          1 "$(grep -c 'android:debuggable="true"' "$M2")"

# --- 2b. first_match: pipefail altında sessiz ölmemeli ----------------------
echo; info "first_match (pipefail tuzağı)"
mkdir -p "$TMPD/out"
: > "$TMPD/out/app-menu.apk"
: > "$TMPD/out/app-debuggable.apk"
check "eşleşme bulur"              "$TMPD/out/app-menu.apk" "$(first_match "$TMPD/out" '*-menu.apk')"
# Asıl regresyon: eşleşme YOKKEN script ölmemeli, boş dönmeli.
rc=0; miss="$(first_match "$TMPD/out" '*-yok.apk')" || rc=$?
check "eşleşme yokken hata vermez" "0" "$rc"
check "eşleşme yokken boş döner"   ""  "$miss"
check "olmayan dizinde de ölmez"   ""  "$(first_match "$TMPD/hicyok" '*.apk')"

# --- 3. prefs düzenleyici --------------------------------------------------
echo; info "prefs_edit.awk"
P="$TMPD/prefs.xml"
fixture() {
  cat > "$P" <<'XML'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <int name="cash" value="1500" />
    <int name="bestScore" value="42" />
    <float name="sfxVolume" value="0.8" />
    <boolean name="car_3_owned" value="false" />
    <string name="playerName">emre</string>
</map>
XML
}

# awk_get <anahtar> ; awk_set <anahtar> <deger> ; awk_count
awk_get()   { prefs_awk get "$1" '' "$P"; }
awk_set()   { prefs_awk set "$1" "$2" "$P" > "$P.new" && mv "$P.new" "$P"; }
awk_count() { prefs_awk list '' '' "$P" | wc -l | tr -d ' '; }

fixture
check "list 5 anahtar bulur"       "5"     "$(awk_count)"
check "get int"                    "1500"  "$(awk_get cash)"
check "get string"                 "emre"  "$(awk_get playerName)"
check "get boolean"                "false" "$(awk_get car_3_owned)"
check "get float"                  "0.8"   "$(awk_get sfxVolume)"

rc=0; awk_get yokBoyleAnahtar >/dev/null 2>&1 || rc=$?
check "olmayan anahtar -> 3"       "3" "$rc"

fixture
awk_set cash 999999
check "set int"                    "999999" "$(awk_get cash)"
check "komşu anahtar bozulmadı"    "42"     "$(awk_get bestScore)"
check "anahtar sayısı sabit"       "5"      "$(awk_count)"

awk_set car_3_owned true
check "set boolean"                "true"   "$(awk_get car_3_owned)"

awk_set playerName "hız kralı"
check "set string (utf-8, boşluk)" "hız kralı" "$(awk_get playerName)"

# awk -v kaçışları yorumlar, ENVIRON yorumlamaz — literal kalmalı
awk_set playerName 'a\1b\g<0>c&d'
check "değer literal yazılır"      'a\1b\g<0>c&d' "$(awk_get playerName)"

# XML'de anlamlı karakterler değeri bozmamalı
awk_set playerName 'x"y>z'
check "tırnak/köşeli değer"        'x"y>z' "$(awk_get playerName)"

# "cash" ile "cas" karışmamalı (tam ad eşleşmesi)
fixture
rc=0; awk_set cas 1 >/dev/null 2>&1 || rc=$?
check "kısmi ad eşleşmez -> 3"     "3" "$rc"
check "başarısız set dosyayı bozmadı" "1500" "$(awk_get cash)"

check "XML kökü korundu"           "1" "$(grep -c '</map>' "$P")"

# aynı değeri iki kez yazmak tek satırı değiştirmeli
fixture
awk_set bestScore 7
awk_set bestScore 7
check "tekrar set güvenli"         "1" "$(grep -c 'name="bestScore"' "$P")"

# satıra sığmayan string değerinde bozmak yerine durmalı (çıkış 4)
printf '<map>\n  <string name="uzun">bir\nikinci</string>\n</map>\n' > "$P"
rc=0; prefs_awk set uzun yeni "$P" > /dev/null 2>&1 || rc=$?
check "çok satırlı değerde durur -> 4" "4" "$rc"

# --- özet ------------------------------------------------------------------
echo
if [ "$FAIL" -eq 0 ]; then
  ok "$PASS test geçti"
else
  printf '\033[31m%d başarısız\033[0m, %d geçti\n' "$FAIL" "$PASS"
  exit 1
fi
