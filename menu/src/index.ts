/*
 * Traffic Racer — oyun içi mod menüsü (Frida gadget ajanı)
 *
 * Bu dosya telefonda /data/data/<paket>/files/agent.js olarak duruyor ve
 * gadget "on_change: reload" ile çalıştığı için dosyayı push etmek yeterli:
 * APK'yı yeniden paketlemeye gerek yok.
 *
 * Menü, oyunun Activity'sine eklenen normal bir Android View. SYSTEM_ALERT_WINDOW
 * izni istemiyoruz — panel oyunun kendi penceresinin içine ekleniyor.
 */

import "frida-il2cpp-bridge";
// Frida 17'de "Java" global'i kaldirildi; kopru ayri modul olarak geliyor.
// Bu import 16.x'te de sorunsuz calisiyor.
import JavaBridge from "frida-java-bridge";

const Java: any = JavaBridge;

const PKG = "com.skgames.trafficracer";
const LOG_PATH = `/data/data/${PKG}/files/mod.log`;

// ---------------------------------------------------------------- log --------
function log(msg: string): void {
    const line = `[mod] ${msg}`;
    console.log(line);
    try {
        const f = new File(LOG_PATH, "a");
        f.write(line + "\n");
        f.flush();
        f.close();
    } catch (e) {
        /* dosyaya yazamazsak sorun değil */
    }
}

// ------------------------------------------------------------- il2cpp -------
/** Sınıfı tüm assembly'lerde arar; Unity sürümüne göre farklı yerlerde olabiliyor. */
function findClass(fullName: string): Il2Cpp.Class | null {
    for (const asm of Il2Cpp.domain.assemblies) {
        try {
            const klass = asm.image.tryClass(fullName);
            if (klass != null) return klass;
        } catch (e) {
            /* bu assembly'de yok */
        }
    }
    return null;
}

function setTimeScale(value: number): void {
    Il2Cpp.perform(() => {
        const time = findClass("UnityEngine.Time");
        if (time == null) {
            log("UnityEngine.Time bulunamadı");
            return;
        }
        time.method<void>("set_timeScale").invoke(value);
        log(`timeScale = ${value}`);
    });
}

function dumpClasses(): void {
    Il2Cpp.perform(() => {
        log("döküm başlıyor, bu biraz sürebilir...");
        Il2Cpp.dump("dump.cs", `/data/data/${PKG}/files`);
        log(`döküm hazır: /data/data/${PKG}/files/dump.cs`);
    });
}

/** Assembly-CSharp içindeki sınıf isimlerini kısa bir dosyaya yazar (hızlı ön bakış). */
function dumpClassNames(): void {
    Il2Cpp.perform(() => {
        const out: string[] = [];
        for (const asm of Il2Cpp.domain.assemblies) {
            if (!asm.name.startsWith("Assembly-CSharp")) continue;
            for (const klass of asm.image.classes) {
                const methods = klass.methods.map(m => m.name).join(", ");
                out.push(`${klass.type.name}\n    ${methods}`);
            }
        }
        const f = new File(`/data/data/${PKG}/files/classes.txt`, "w");
        f.write(out.join("\n"));
        f.flush();
        f.close();
        log(`${out.length} sınıf yazıldı: files/classes.txt`);
    });
}

// ------------------------------------------------------------- menü ---------
interface MenuItem {
    label: string;
    run: () => void;
}

const ITEMS: MenuItem[] = [
    { label: "Oyun hızı  1x", run: () => setTimeScale(1.0) },
    { label: "Oyun hızı  2x", run: () => setTimeScale(2.0) },
    { label: "Oyun hızı  4x", run: () => setTimeScale(4.0) },
    { label: "Yavaş çekim 0.5x", run: () => setTimeScale(0.5) },
    { label: "Sınıf listesi çıkar", run: () => dumpClassNames() },
    { label: "Tam döküm (yavaş)", run: () => dumpClasses() },
];

let menuBuilt = false;

// Frida 17'nin Java koprusu, JS degerini hangi asiri yuklemeye gonderecegini
// secemiyor (setText/setTextSize/Color.argb hepsinde birden fazla imza var).
// Bu yuzden imzayi elle sabitliyoruz.
function jstr(s: string): any {
    return Java.use("java.lang.String").$new(s);
}

function setText(view: any, s: string): void {
    view.setText.overload("java.lang.CharSequence").call(view, jstr(s));
}

function setTextSize(view: any, size: number): void {
    view.setTextSize.overload("float").call(view, size);
}

/** Java'nin int renk formati. Color.argb da asiri yuklu, o yuzden elle hesapliyoruz. */
function argb(a: number, r: number, g: number, b: number): number {
    return ((a << 24) | (r << 16) | (g << 8) | b) | 0;
}

function buildMenu(activity: any): void {
    const LinearLayout = Java.use("android.widget.LinearLayout");
    const Button = Java.use("android.widget.Button");
    const TextView = Java.use("android.widget.TextView");
    const FrameLayoutParams = Java.use("android.widget.FrameLayout$LayoutParams");
    const LinearParams = Java.use("android.widget.LinearLayout$LayoutParams");
    const Gravity = Java.use("android.view.Gravity");

    const WRAP = -2;
    const MATCH = -1;

    // panel aşağıda kuruluyor; dinleyici kapanış üzerinden erişiyor
    let panel: any;

    // Tıklama dinleyicisi: her düğmeye bir indeks bağlıyoruz.
    const Click = Java.registerClass({
        name: "tr.mod.Click",
        implements: [Java.use("android.view.View$OnClickListener")],
        fields: { idx: "int" },
        methods: {
            onClick(this: any, _view: any) {
                const i = this.idx.value;
                try {
                    if (i === -1) {
                        // panel aç/kapa
                        const vis = panel.getVisibility();
                        panel.setVisibility(vis === 0 ? 8 : 0);
                    } else {
                        ITEMS[i].run();
                    }
                } catch (e: any) {
                    log(`tıklama hatası (${i}): ${e.message ?? e}`);
                }
            },
        },
    });

    const mkClick = (i: number) => {
        const c = Click.$new();
        c.idx.value = i;
        return c;
    };

    // --- panel ---------------------------------------------------------------
    panel = LinearLayout.$new(activity);
    panel.setOrientation(1); // VERTICAL
    panel.setBackgroundColor(argb(220, 15, 15, 20));
    panel.setPadding(16, 16, 16, 16);
    panel.setVisibility(8); // GONE — başta kapalı

    const title = TextView.$new(activity);
    setText(title, "TRAFFIC RACER - MOD");
    title.setTextColor(argb(255, 120, 220, 255));
    setTextSize(title, 14);
    title.setPadding(0, 0, 0, 12);
    panel.addView(title);

    ITEMS.forEach((item, i) => {
      try {
        const b = Button.$new(activity);
        setText(b, item.label);
        b.setAllCaps(false);
        setTextSize(b, 13);
        b.setTextColor(argb(255, 235, 235, 235));
        b.setBackgroundColor(argb(255, 45, 45, 55));
        b.setOnClickListener(mkClick(i));
        const lp = LinearParams.$new(MATCH, WRAP);
        lp.setMargins(0, 4, 0, 4);
        b.setLayoutParams(lp);
        panel.addView(b);
      } catch (e: any) {
        log(`düğme eklenemedi (${item.label}): ${e.message ?? e}`);
      }
    });

    // --- açma düğmesi --------------------------------------------------------
    const toggle = Button.$new(activity);
    setText(toggle, "MOD");
    toggle.setAllCaps(false);
    setTextSize(toggle, 12);
    toggle.setTextColor(argb(255, 255, 255, 255));
    toggle.setBackgroundColor(argb(200, 200, 40, 60));
    toggle.setOnClickListener(mkClick(-1));

    // --- ekrana ekle ---------------------------------------------------------
    const wrapper = LinearLayout.$new(activity);
    wrapper.setOrientation(1);
    wrapper.addView(toggle);
    wrapper.addView(panel);

    const params = FrameLayoutParams.$new(WRAP, WRAP);
    params.gravity.value = Gravity.TOP.value | Gravity.LEFT.value;
    params.leftMargin.value = 24;
    params.topMargin.value = 120;

    activity.addContentView(wrapper, params);
    log("menü eklendi");
}

// ------------------------------------------------------------- giriş --------
function main(): void {
    log("ajan yüklendi");

    Java.perform(() => {
        const Activity = Java.use("android.app.Activity");
        Activity.onResume.implementation = function (this: any) {
            this.onResume();
            if (menuBuilt) return;
            menuBuilt = true;
            const act = Java.retain(this);
            Java.scheduleOnMainThread(() => {
                try {
                    buildMenu(act);
                } catch (e: any) {
                    menuBuilt = false;
                    log(`menü kurulamadı: ${e.message ?? e}`);
                }
            });
        };
        log("Activity.onResume bekleniyor");
    });

    Il2Cpp.perform(() => {
        log(`il2cpp hazır — unity ${Il2Cpp.unityVersion}`);
        // Sınıf listesini kendiliğinden yaz: menüden düğmeye basmaya gerek kalmasın.
        try {
            dumpClassNames();
        } catch (e: any) {
            log(`sınıf listesi yazılamadı: ${e.message ?? e}`);
        }
    });
}

main();
