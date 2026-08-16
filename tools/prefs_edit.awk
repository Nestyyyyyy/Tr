# Android SharedPreferences / Unity PlayerPrefs XML okuyucu-düzenleyici.
#
# awk ile yazıldı çünkü awk her yerde var (Git Bash dahil); Python opsiyonel
# kalsın istiyoruz. Değerler regex ile değil, index() ile konum bulunarak
# değiştiriliyor — yani hem "&" gibi karakterler hem "\1" gibi kaçışlar
# birebir literal yazılıyor, biçim hiç bozulmuyor.
#
# Girdi ortam değişkenleriyle verilir (awk -v kaçış dizilerini yorumlar,
# ENVIRON yorumlamaz — literal kalması için şart):
#   PREFS_MODE = list | get | set
#   PREFS_KEY  = anahtar adı
#   PREFS_VAL  = set için yeni değer
#
# Çıkış kodları: 0 tamam, 3 anahtar yok, 4 desteklenmeyen biçim.

function tag_of(s,   p, r, c, i) {
  p = index(s, "<")
  if (p == 0) return ""
  r = ""
  for (i = p + 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c ~ /[A-Za-z]/) r = r c; else break
  }
  return r
}

function key_of(s,   p, rest, q) {
  p = index(s, "name=\"")
  if (p == 0) return ""
  rest = substr(s, p + 6)
  q = index(rest, "\"")
  if (q == 0) return ""
  return substr(rest, 1, q - 1)
}

BEGIN {
  mode  = ENVIRON["PREFS_MODE"]
  key   = ENVIRON["PREFS_KEY"]
  newval = ENVIRON["PREFS_VAL"]
  found = 0
  count = 0
  badfmt = 0
}

{
  line = $0
  k = key_of(line)

  if (k == "") {                      # <map>, xml bildirimi vb.
    if (mode == "set") print line
    next
  }

  t = tag_of(line)
  vs = 0; ve = 0

  p = index(line, "value=\"")
  if (p > 0) {                        # <int name="x" value="1" />
    vs = p + 7
    rest = substr(line, vs)
    q = index(rest, "\"")
    if (q == 0) { badfmt = 1; if (mode == "set") print line; next }
    ve = vs + q - 1
  } else if (t == "string") {         # <string name="x">deger</string>
    p = index(line, ">")
    e = index(line, "</string>")
    if (p == 0 || e == 0) {
      # Değer satıra sığmamış (içinde satır sonu var). Bozmaktansa dur.
      if (k == key) { badfmt = 1 }
      if (mode == "set") print line
      next
    }
    vs = p + 1
    ve = e
  } else {
    if (mode == "set") print line
    next
  }

  val = substr(line, vs, ve - vs)

  if (mode == "list") {
    count++
    printf "%s\t%s\t%s\n", k, t, val
  } else if (mode == "get") {
    if (k == key) { print val; found = 1 }
  } else if (mode == "set") {
    if (k == key && !found) {
      print substr(line, 1, vs - 1) newval substr(line, ve)
      found = 1
    } else {
      print line
    }
  }
}

END {
  if (badfmt && (mode != "list")) {
    print "desteklenmeyen bicim: deger satira sigmiyor (elle duzenle)" > "/dev/stderr"
    exit 4
  }
  if ((mode == "get" || mode == "set") && !found) {
    print "anahtar yok: " key > "/dev/stderr"
    exit 3
  }
}
