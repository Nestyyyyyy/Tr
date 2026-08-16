#!/usr/bin/env python3
"""Android SharedPreferences / Unity PlayerPrefs XML okuyucu-düzenleyici.

  python3 prefs_edit.py list <dosya>
  python3 prefs_edit.py get  <dosya> <anahtar>
  python3 prefs_edit.py set  <dosya> <anahtar> <deger>

Çıkış kodları: 0 tamam, 2 kullanım hatası, 3 anahtar yok.

Not: dosya metin olarak, regex ile düzenleniyor. Bilinçli bir tercih — XML
parser'dan geçirmek öznitelik sırasını ve biçimlendirmeyi değiştirir, Android'in
kendi yazdığı dosyadan uzaklaşmak istemiyoruz.
"""

import re
import sys

TYPED = r'<(?:int|long|float|boolean)\s+name="{k}"\s+value="([^"]*)"'
STRING = r'<string\s+name="{k}"\s*>(.*?)</string>'


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def entries(text):
    """[(anahtar, tip, deger)] — dosyadaki sırayı değil, alfabetik sırayı döner."""
    rows = [
        (m.group(2), m.group(1), m.group(3))
        for m in re.finditer(
            r'<(int|long|float|boolean)\s+name="([^"]*)"\s+value="([^"]*)"', text
        )
    ]
    rows += [
        (m.group(1), "string", m.group(2))
        for m in re.finditer(r'<string\s+name="([^"]*)"\s*>(.*?)</string>', text, re.S)
    ]
    return sorted(rows)


def find(text, key):
    """(tip, deger) döner, yoksa None."""
    k = re.escape(key)
    m = re.search(TYPED.format(k=k), text)
    if m:
        return ("typed", m.group(1))
    m = re.search(STRING.format(k=k), text, re.S)
    if m:
        return ("string", m.group(1))
    return None


def replace(text, key, value):
    """Değeri değiştirilmiş metni ve eski değeri döner; anahtar yoksa (None, None)."""
    k = re.escape(key)
    hit = find(text, key)
    if hit is None:
        return None, None
    kind, old = hit
    # Yerine koyarken value'yu literal ele al: \g<0> gibi kaçışlar yorumlanmasın.
    if kind == "typed":
        new = re.sub(
            TYPED.format(k=k),
            lambda m: m.group(0)[: m.start(1) - m.start(0)]
            + value
            + m.group(0)[m.end(1) - m.start(0) :],
            text,
            count=1,
        )
    else:
        new = re.sub(
            STRING.format(k=k),
            lambda m: m.group(0)[: m.start(1) - m.start(0)]
            + value
            + m.group(0)[m.end(1) - m.start(0) :],
            text,
            count=1,
            flags=re.S,
        )
    return new, old


def cmd_list(path):
    rows = entries(read(path))
    if not rows:
        print("  (tanınan anahtar yok — dosyayı ham haliyle incele)")
        return 0
    width = max(len(r[0]) for r in rows)
    for key, kind, val in rows:
        shown = val if len(val) <= 60 else val[:57] + "..."
        print("  %s  %-8s %s" % (key.ljust(width), kind, shown))
    print("\n  toplam %d anahtar" % len(rows))
    return 0


def cmd_get(path, key):
    hit = find(read(path), key)
    if hit is None:
        sys.stderr.write("anahtar yok: %s\n" % key)
        return 3
    print(hit[1])
    return 0


def cmd_set(path, key, value):
    new, old = replace(read(path), key, value)
    if new is None:
        sys.stderr.write("anahtar yok: %s\n" % key)
        return 3
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(new)
    print("%s: %s -> %s" % (key, old, value))
    return 0


def main(argv):
    if len(argv) < 3:
        sys.stderr.write(__doc__)
        return 2
    cmd, path = argv[1], argv[2]
    if cmd == "list" and len(argv) == 3:
        return cmd_list(path)
    if cmd == "get" and len(argv) == 4:
        return cmd_get(path, argv[3])
    if cmd == "set" and len(argv) == 5:
        return cmd_set(path, argv[3], argv[4])
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
