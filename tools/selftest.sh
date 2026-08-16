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
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import ast,sys; ast.parse(open('$ROOT_DIR/tools/prefs_edit.py').read())"; then
    check "prefs_edit.py" "ok" "ok"
  else
    check "prefs_edit.py" "ok" "sözdizimi hatası"
  fi
fi

# --- 2. manifest yaması ----------------------------------------------------
echo; info "patch_manifest"

M="$TMPD/a.xml"
cat > "$M" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.skgames.trafficracer">
    <application android:allowBackup="false" android:label="Traffic Racer" android:icon="@mipmap/app_icon">
        <activity android:name="com.unity3d.player.UnityPlayerActivity" android:exported="true"/>
    </application>
</manifest>
XML
patch_manifest "$M" >/dev/null
check "debuggable eklendi"                1 "$(grep -c 'android:debuggable="true"' "$M")"
check "allowBackup false -> true"         1 "$(grep -c 'android:allowBackup="true"' "$M")"
check "allowBackup=\"false\" kalmadı"     0 "$(grep -c 'android:allowBackup="false"' "$M")"
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
check "debuggable yoksa eklenir"          1 "$(grep -c 'android:debuggable="true"' "$M2")"

# --- 3. prefs düzenleyici --------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
  warn "python3 yok, prefs testleri atlandı"
else
  echo; info "prefs_edit.py"
  PY="$ROOT_DIR/tools/prefs_edit.py"
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

  fixture
  check "list 5 anahtar bulur"  "5" "$(python3 "$PY" list "$P" | sed -n 's/.*toplam \([0-9]*\) anahtar/\1/p')"
  check "get int"               "1500"  "$(python3 "$PY" get "$P" cash)"
  check "get string"            "emre"  "$(python3 "$PY" get "$P" playerName)"
  check "get boolean"           "false" "$(python3 "$PY" get "$P" car_3_owned)"

  rc=0; python3 "$PY" get "$P" yokBoyleAnahtar >/dev/null 2>&1 || rc=$?
  check "olmayan anahtar -> 3" "3" "$rc"

  fixture
  python3 "$PY" set "$P" cash 999999 >/dev/null
  check "set int"                    "999999" "$(python3 "$PY" get "$P" cash)"
  check "komşu anahtar bozulmadı"    "42"     "$(python3 "$PY" get "$P" bestScore)"
  check "anahtar sayısı sabit"       "5"      "$(python3 "$PY" list "$P" | sed -n 's/.*toplam \([0-9]*\) anahtar/\1/p')"

  python3 "$PY" set "$P" car_3_owned true >/dev/null
  check "set boolean"                "true"   "$(python3 "$PY" get "$P" car_3_owned)"

  python3 "$PY" set "$P" playerName "hız kralı" >/dev/null
  check "set string (utf-8, boşluk)" "hız kralı" "$(python3 "$PY" get "$P" playerName)"

  # regex kaçışlarının literal işlendiğini doğrula
  python3 "$PY" set "$P" playerName 'a\1b\g<0>c' >/dev/null
  check "değer literal yazılır"      'a\1b\g<0>c' "$(python3 "$PY" get "$P" playerName)"

  # "cash" ile "cashX" karışmamalı (tam ad eşleşmesi)
  fixture
  rc=0; python3 "$PY" set "$P" cas 1 >/dev/null 2>&1 || rc=$?
  check "kısmi ad eşleşmez -> 3"     "3" "$rc"

  check "XML kökü korundu"           "1" "$(grep -c '</map>' "$P")"
fi

# --- özet ------------------------------------------------------------------
echo
if [ "$FAIL" -eq 0 ]; then
  ok "$PASS test geçti"
else
  printf '\033[31m%d başarısız\033[0m, %d geçti\n' "$FAIL" "$PASS"
  exit 1
fi
