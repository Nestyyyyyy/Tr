/*
 * Bağımlılıksız teşhis sondası.
 *
 * Menü ajanı hiç çalışmadığında suçlu kim belli olsun diye var: gadget script'i
 * gerçekten çalıştırıyor mu, hangi Frida sürümü, Java köprüsü global mi (16.x)
 * yoksa modül mü (17.x), il2cpp o an yüklü mü.
 *
 * Hiçbir şey import etmiyor — sadece Frida'nın kendi API'leri. Böylece
 * "import patladı" ihtimali tamamen elenir.
 *
 * Kullanım:  ./tr.sh agent probe   -> bunu agent.js yerine koyar
 *            oyunu aç, sonra:  ./tr.sh agent log
 */
"use strict";

(function () {
    var PKG = "com.skgames.trafficracer";
    var out = [];

    function add(k, v) {
        out.push(k + ": " + v);
    }

    function tryGet(fn, fallback) {
        try {
            return fn();
        } catch (e) {
            return fallback + " (" + e + ")";
        }
    }

    add("sonda", "CALISTI");
    add("frida", tryGet(function () { return Frida.version; }, "?"));
    add("mimari", tryGet(function () { return Process.arch + " / " + Process.platform; }, "?"));
    add("pid", tryGet(function () { return Process.id; }, "?"));

    // Frida 17'de Java global'i kaldirildi. Hangisi oldugunu bilmek onemli.
    add("Java global", typeof Java);
    add("ObjC global", typeof ObjC);
    add("File API", typeof File);

    // il2cpp bu anda yuklu mu? Gadget Activity <clinit>'te yukleniyor, oyun
    // kutuphaneleri daha sonra gelebilir.
    add("moduller", tryGet(function () {
        var names = [];
        Process.enumerateModules().forEach(function (m) {
            if (/il2cpp|unity|frida|main/i.test(m.name)) names.push(m.name);
        });
        return names.length ? names.join(", ") : "(eslesme yok)";
    }, "okunamadi"));

    add("toplam modul", tryGet(function () { return Process.enumerateModules().length; }, "?"));

    var text = out.join("\n") + "\n";

    // Hem dosyaya hem logcat'e yaz; biri tutmazsa digeri kalir.
    try {
        var f = new File("/data/data/" + PKG + "/files/probe.txt", "w");
        f.write(text);
        f.flush();
        f.close();
    } catch (e) {
        text += "dosyaya yazilamadi: " + e + "\n";
    }

    console.log("[probe]\n" + text);
})();
