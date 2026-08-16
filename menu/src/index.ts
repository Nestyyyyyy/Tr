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

/**
 * Hook yazabilmek icin gereken tek sey: hedef siniflarin alan ve metot imzalari.
 * Sinif listesi yetmiyor, imzalar lazim. Bunlari acilista files/api.txt'ye yaziyoruz.
 */
const API_TARGETS = [
    "CarMover", "TrafficMover", "RandomCarSpawner", "CarCollisionDetector",
    "SaveGameManager", "SecureSaveGameManager", "MenuCashAnimator",
    "UpgradeSpeedButton", "BuyButtonDoubleCash", "MenuCarMover", "MenuTrafficMover",
];

function dumpApi(): void {
    Il2Cpp.perform(() => {
        const out: string[] = [];
        for (const asm of Il2Cpp.domain.assemblies) {
            if (!asm.name.startsWith("Assembly-CSharp")) continue;
            for (const klass of asm.image.classes) {
                const name = klass.type.name;
                if (!API_TARGETS.some(t => name === t || name.indexOf(t + ".") === 0)) continue;
                try {
                    out.push("=== " + name);
                    for (const f of klass.fields) {
                        out.push(`  ALAN  ${f.isStatic ? "static " : ""}${f.type.name} ${f.name}`);
                    }
                    for (const m of klass.methods) {
                        const ps = m.parameters.map(x => `${x.type.name} ${x.name}`).join(", ");
                        out.push(`  MET   ${m.isStatic ? "static " : ""}${m.returnType.name} ${m.name}(${ps})`);
                    }
                    out.push("");
                } catch (e: any) {
                    out.push(`  (okunamadı: ${e.message ?? e})`);
                }
            }
        }
        const f = new File(`/data/data/${PKG}/files/api.txt`, "w");
        f.write(out.join("\n"));
        f.flush();
        f.close();
        log(`api.txt yazıldı (${out.length} satır)`);
    });
}

// ------------------------------------------------------------ hileler -------
/*
 * api.txt'den cikan gercekler:
 *   SaveGameManager.saveTotalMoney(int, bool)            -> TOTAL_MONEY
 *   SecureSaveGameManager.saveTotalMoneyNew(int, bool)   -> TOTAL_MONEY_NEW
 * Oyun ikisini karsilastiriyor; sadece birini yazarsan parayi 0'a cekiyor.
 * Oyunun kendi kaydetme fonksiyonunu cagirdigimiz icin sifrelemeyle
 * ugrasmiyoruz - onu kendisi yapiyor.
 *
 *   CarMover.isAI  -> oyuncunun arabasini trafikten ayirir (kritik)
 *   RandomCarSpawner.SpawnCar / canSpawn  -> trafik
 *   CarCollisionDetector.OnTriggerEnter/Stay -> carpisma
 */

const state = {
    noCollision: false,
    noTraffic: false,
    superSpeed: false,
};

let speedTimer: any = null;

function csClass(name: string): Il2Cpp.Class | null {
    for (const asmName of ["Assembly-CSharp", "Assembly-CSharp-firstpass"]) {
        try {
            const k = Il2Cpp.domain.assembly(asmName).image.tryClass(name);
            if (k != null) return k;
        } catch (e) { /* yok */ }
    }
    return findClass(name);
}

/** Canli nesneler arasindan sinifa uyanlari gezer. */
function eachInstance(className: string, cb: (o: Il2Cpp.Object) => void): number {
    const k = csClass(className);
    if (k == null) { log(`${className} bulunamadı`); return 0; }
    let n = 0;
    for (const obj of Il2Cpp.gc.choose(k)) {
        try { cb(obj); n++; } catch (e: any) { log(`${className} örneği atlandı: ${e.message ?? e}`); }
    }
    return n;
}

// ------------------------------------------------------------------ para ----
function getMoney(): number {
    const sec = csClass("SecureSaveGameManager");
    if (sec == null) return -1;
    return sec.method<number>("getTotalMoneyNew").invoke() as unknown as number;
}

function setMoney(amount: number): void {
    const sec = csClass("SecureSaveGameManager");
    const old = csClass("SaveGameManager");
    if (sec == null || old == null) { log("kayıt yöneticisi bulunamadı"); return; }
    // IKISI BIRDEN yazilmali; yoksa oyun uyusmazlik gorup parayi sifirliyor.
    old.method("saveTotalMoney").invoke(amount, true);
    sec.method("saveTotalMoneyNew").invoke(amount, true);
    log(`para -> ${amount}`);
}

function addMoney(delta: number): void {
    Il2Cpp.perform(() => {
        const cur = getMoney();
        const next = (cur < 0 ? 0 : cur) + delta;
        setMoney(next > 2000000000 ? 2000000000 : next);
    });
}

// -------------------------------------------------------------- kilitler ----
function unlockAllCars(): void {
    Il2Cpp.perform(() => {
        const sec = csClass("SecureSaveGameManager");
        const old = csClass("SaveGameManager");
        if (sec == null || old == null) return;
        let n = 0;
        for (let id = 0; id < 60; id++) {
            try {
                sec.method("saveAvailableForCarNew").invoke(id, true, true);
                old.method("saveAvailableForCar").invoke(id, true, true);
                n++;
            } catch (e) { /* o id yok */ }
        }
        log(`${n} araba açıldı`);
    });
}

function maxUpgrades(): void {
    Il2Cpp.perform(() => {
        const old = csClass("SaveGameManager");
        if (old == null) return;
        const LEVEL = 6;
        for (let id = 0; id < 60; id++) {
            try {
                old.method("saveSpeedLevelForCar").invoke(id, LEVEL);
                old.method("saveHandlingLevelForCar").invoke(id, LEVEL);
                old.method("saveBrakingLevelForCar").invoke(id, LEVEL);
                for (let c = 0; c < 8; c++) old.method("saveColorAvailableForCar").invoke(c, id, true);
                for (let w = 0; w < 8; w++) old.method("saveWheelAvailableForCar").invoke(w, id, true);
                for (let v = 0; v < 8; v++) old.method("saveVinylAvailableForCar").invoke(v, id, true);
            } catch (e) { /* yok */ }
        }
        log("yükseltmeler ve görsel kilitler maksimuma çekildi");
    });
}

function unlockExtras(): void {
    Il2Cpp.perform(() => {
        const sec = csClass("SecureSaveGameManager");
        const old = csClass("SaveGameManager");
        if (sec == null || old == null) return;
        const secFlags = ["saveHasRemoveAds", "saveHasDoubleCash", "saveHasStarterKit",
                          "saveLocation3AvailableNew", "saveLocation4AvailableNew",
                          "saveLocationRainyAvailable", "saveLocationAutumnAvailable",
                          "saveLocationForestAvailable", "saveLocationDesertAvailable"];
        for (const m of secFlags) {
            try { sec.method(m).invoke(true, true); } catch (e) { /* imza farkli */ }
        }
        const oldFlags = ["saveLocationSnowyAvailable", "saveLocationCityAvailable",
                          "saveLocationRainyAvailable", "saveLocationAutumnAvailable",
                          "saveLocationForestAvailable", "saveLocationDesertAvailable"];
        for (const m of oldFlags) {
            try { old.method(m).invoke(true, true); } catch (e) { /* yok */ }
        }
        log("reklamsız + çift para + tüm lokasyonlar açıldı");
    });
}

// ------------------------------------------------------------ çarpışma ------
function setNoCollision(on: boolean): void {
    Il2Cpp.perform(() => {
        const k = csClass("CarCollisionDetector");
        if (k == null) { log("CarCollisionDetector yok"); return; }
        for (const name of ["OnTriggerEnter", "OnTriggerStay"]) {
            try {
                const m = k.method(name);
                if (on) m.implementation = function () { /* çarpışmayı yut */ };
                else m.revert();
            } catch (e: any) {
                log(`${name} hook hatası: ${e.message ?? e}`);
            }
        }
        state.noCollision = on;
        log(`çarpışma ${on ? "KAPALI" : "açık"}`);
    });
}

// --------------------------------------------------------------- trafik -----
function setNoTraffic(on: boolean): void {
    Il2Cpp.perform(() => {
        const k = csClass("RandomCarSpawner");
        if (k == null) { log("RandomCarSpawner yok"); return; }
        try {
            const m = k.method("SpawnCar");
            if (on) m.implementation = function () { /* araç doğurma */ };
            else m.revert();
        } catch (e: any) {
            log(`SpawnCar hook hatası: ${e.message ?? e}`);
        }
        // Mevcut spawner'lari da kapat/ac.
        eachInstance("RandomCarSpawner", o => { o.field<boolean>("canSpawn").value = !on; });
        state.noTraffic = on;
        log(`trafik ${on ? "KAPALI" : "açık"}`);
    });
}

// ----------------------------------------------------------- süper hız ------
const SPEED_MULT = 3.0;

/** Sadece OYUNCUNUN arabasi: isAI == false. Trafik etkilenmiyor. */
function applySuperSpeed(): void {
    eachInstance("CarMover", o => {
        if (o.field<boolean>("isAI").value) return;
        const maxSpeed = o.field<number>("maxSpeed");
        const accel = o.field<number>("maxAcceleration");
        const base = maxSpeed.value as unknown as number;
        if (base > 0 && base < 400) {
            maxSpeed.value = base * SPEED_MULT;
            accel.value = (accel.value as unknown as number) * 2;
        }
    });
}

function setSuperSpeed(on: boolean): void {
    state.superSpeed = on;
    if (speedTimer != null) { clearInterval(speedTimer); speedTimer = null; }
    if (on) {
        // Araba her yarista yeniden olusuyor; periyodik olarak tekrar uygula.
        speedTimer = setInterval(() => {
            try { Il2Cpp.perform(() => applySuperSpeed()); } catch (e) { /* yarış dışı */ }
        }, 1500);
        Il2Cpp.perform(() => applySuperSpeed());
    }
    log(`süper hız ${on ? "AÇIK" : "kapalı"}`);
}

// ------------------------------------------------------------- menü ---------
interface MenuItem {
    label: () => string;
    run: () => void;
}

const onOff = (b: boolean) => (b ? "AÇIK" : "kapalı");

const ITEMS: MenuItem[] = [
    { label: () => "Para +1.000.000", run: () => addMoney(1000000) },
    { label: () => "Para +100.000", run: () => addMoney(100000) },
    { label: () => `Çarpışma yok  ·  ${onOff(state.noCollision)}`,
      run: () => setNoCollision(!state.noCollision) },
    { label: () => `Trafik yok  ·  ${onOff(state.noTraffic)}`,
      run: () => setNoTraffic(!state.noTraffic) },
    { label: () => `Süper hız (sadece ben)  ·  ${onOff(state.superSpeed)}`,
      run: () => setSuperSpeed(!state.superSpeed) },
    { label: () => "Tüm arabaları aç", run: () => unlockAllCars() },
    { label: () => "Yükseltmeleri maksla", run: () => maxUpgrades() },
    { label: () => "Reklamsız + çift para + haritalar", run: () => unlockExtras() },
    { label: () => "Oyun hızı ×2  (her şey)", run: () => setTimeScale(2.0) },
    { label: () => "Oyun hızı ×1  (normal)", run: () => setTimeScale(1.0) },
    { label: () => "API dökümü çıkar", run: () => dumpApi() },
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
    const ScrollView = Java.use("android.widget.ScrollView");
    const Button = Java.use("android.widget.Button");
    const TextView = Java.use("android.widget.TextView");
    const FrameLayoutParams = Java.use("android.widget.FrameLayout$LayoutParams");
    const LinearParams = Java.use("android.widget.LinearLayout$LayoutParams");
    const GradientDrawable = Java.use("android.graphics.drawable.GradientDrawable");
    const Gravity = Java.use("android.view.Gravity");
    const Typeface = Java.use("android.graphics.Typeface");

    const WRAP = -2;
    const MATCH = -1;
    const VERTICAL = 1;
    const GONE = 8;
    const VISIBLE = 0;

    // Ham piksel kullanmak ekrandan ekrana bozuk gorunuyordu (bu telefon 2772x1280).
    // Her olcuyu ekran yogunluguyla carpiyoruz; yazi boyutlari da SP birimiyle.
    const density: number = activity.getResources().getDisplayMetrics().density.value;
    const dp = (v: number) => Math.round(v * density);
    const SP = 2; // TypedValue.COMPLEX_UNIT_SP

    const sp = (view: any, size: number) =>
        view.setTextSize.overload("int", "float").call(view, SP, size);

    /** Yuvarlak kose + dolgu rengi. Duz setBackgroundColor kutu gibi duruyordu. */
    const rounded = (view: any, color: number, radiusDp: number) => {
        const g = GradientDrawable.$new();
        g.setColor.overload("int").call(g, color);
        g.setCornerRadius(dp(radiusDp));
        view.setBackground(g);
    };

    let panel: any;
    const buttons: any[] = [];

    /** Toggle'dan sonra etiketler ACIK/kapali'yi yansitsin. */
    const refreshLabels = () => {
        ITEMS.forEach((item, i) => {
            const b = buttons[i];
            if (b != null) {
                try { setText(b, item.label()); } catch (e) { /* onemsiz */ }
            }
        });
    };

    const Click = Java.registerClass({
        name: "tr.mod.Click",
        implements: [Java.use("android.view.View$OnClickListener")],
        fields: { idx: "int" },
        methods: {
            onClick(this: any, _view: any) {
                const i = this.idx.value;
                try {
                    if (i === -1) {
                        const vis = panel.getVisibility();
                        panel.setVisibility(vis === VISIBLE ? GONE : VISIBLE);
                    } else {
                        ITEMS[i].run();
                        refreshLabels();
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

    // --- panel --------------------------------------------------------------
    panel = LinearLayout.$new(activity);
    panel.setOrientation(VERTICAL);
    panel.setPadding(dp(12), dp(12), dp(12), dp(12));
    rounded(panel, argb(242, 18, 18, 24), 14);
    panel.setVisibility(GONE);

    const title = TextView.$new(activity);
    setText(title, "TRAFFIC RACER  ·  MOD");
    title.setTextColor(argb(255, 110, 215, 255));
    sp(title, 13);
    title.setTypeface(Typeface.DEFAULT_BOLD.value);
    title.setPadding(dp(4), 0, 0, dp(10));
    panel.addView(title);

    ITEMS.forEach((item, i) => {
        try {
            const b = Button.$new(activity);
            setText(b, item.label());
            b.setAllCaps(false);
            sp(b, 13);
            b.setTextColor(argb(255, 238, 240, 245));
            b.setGravity(Gravity.CENTER_VERTICAL.value | Gravity.LEFT.value);
            b.setPadding(dp(14), 0, dp(14), 0);
            b.setMinimumHeight(dp(42));
            rounded(b, argb(255, 38, 40, 52), 9);
            b.setOnClickListener(mkClick(i));

            const lp = LinearParams.$new(MATCH, dp(42));
            lp.setMargins(0, dp(3), 0, dp(3));
            b.setLayoutParams(lp);
            panel.addView(b);
            buttons[i] = b;
        } catch (e: any) {
            log(`düğme eklenemedi (${i}): ${e.message ?? e}`);
        }
    });

    // Cok oge olunca ekrandan tasmasin.
    const scroll = ScrollView.$new(activity);
    scroll.addView(panel);
    const scrollLp = LinearParams.$new(dp(240), WRAP);
    scroll.setLayoutParams(scrollLp);

    // --- açma düğmesi -------------------------------------------------------
    const toggle = Button.$new(activity);
    setText(toggle, "MOD");
    toggle.setAllCaps(false);
    sp(toggle, 12);
    toggle.setTextColor(argb(255, 255, 255, 255));
    toggle.setTypeface(Typeface.DEFAULT_BOLD.value);
    toggle.setPadding(0, 0, 0, 0);
    toggle.setMinimumWidth(dp(58));
    toggle.setMinimumHeight(dp(34));
    rounded(toggle, argb(230, 200, 45, 65), 17);
    toggle.setOnClickListener(mkClick(-1));

    const toggleLp = LinearParams.$new(dp(58), dp(34));
    toggleLp.setMargins(0, 0, 0, dp(6));
    toggle.setLayoutParams(toggleLp);

    // --- ekrana ekle --------------------------------------------------------
    const wrapper = LinearLayout.$new(activity);
    wrapper.setOrientation(VERTICAL);
    wrapper.addView(toggle);
    wrapper.addView(scroll);

    const params = FrameLayoutParams.$new(WRAP, WRAP);
    params.gravity.value = Gravity.TOP.value | Gravity.LEFT.value;
    params.leftMargin.value = dp(10);
    params.topMargin.value = dp(40);

    activity.addContentView(wrapper, params);
    log(`menü eklendi (yoğunluk ${density})`);
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
            dumpApi();
        } catch (e: any) {
            log(`döküm yazılamadı: ${e.message ?? e}`);
        }
    });
}

main();
