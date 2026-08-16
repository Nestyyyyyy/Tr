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
 * PERFORMANS NOTU (onemli):
 * Ilk surumde super hiz icin her 1.5 sn'de Il2Cpp.gc.choose() cagriliyordu.
 * O cagri TUM heap'i tarar; oyun ortasinda surekli yapinca hem kasiyor hem
 * cokertiyordu. Artik periyodik tarama YOK:
 *   - Araba olustugunda CarMover.myStart'a Interceptor.attach ile baglaniyoruz
 *     (orijinal kod calismaya devam eder, sadece dinliyoruz -> bedava).
 *   - gc.choose yalnizca kullanici bir toggle'a bastiginda, tek seferlik.
 */

const state = {
    noCollision: false,
    noTraffic: false,
    superSpeed: false,
    noBoundary: false,
    slowTraffic: false,
    speedMult: 3,
};

let lastStatus = "hazır";
let carStartHook: any = null;

/** Degistirdigimiz alanlarin orijinalleri (nesne bazinda). */
const originals = new Map<string, { ms: number; acc: number }>();
const spawnerOriginals = new Map<string, { min: number; max: number }>();

function csClass(name: string): Il2Cpp.Class | null {
    for (const asmName of ["Assembly-CSharp", "Assembly-CSharp-firstpass"]) {
        try {
            const k = Il2Cpp.domain.assembly(asmName).image.tryClass(name);
            if (k != null) return k;
        } catch (e) { /* yok */ }
    }
    return findClass(name);
}

/** Tek seferlik heap taramasi. Periyodik ASLA cagirma. */
function eachInstance(className: string, cb: (o: Il2Cpp.Object) => void): number {
    const k = csClass(className);
    if (k == null) { log(`${className} bulunamadı`); return 0; }
    let n = 0;
    for (const obj of Il2Cpp.gc.choose(k)) {
        try { cb(obj); n++; } catch (e: any) { log(`${className} atlandı: ${e.message ?? e}`); }
    }
    return n;
}

function status(msg: string): void {
    lastStatus = msg;
    log(msg);
}

/** Metodu bos implementasyona alir / geri dondurur. */
function toggleStub(className: string, methods: string[], on: boolean): void {
    const k = csClass(className);
    if (k == null) { log(`${className} yok`); return; }
    for (const name of methods) {
        try {
            const m = k.method(name);
            if (on) m.implementation = function () { /* yut */ };
            else m.revert();
        } catch (e: any) {
            log(`${className}.${name}: ${e.message ?? e}`);
        }
    }
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
    if (sec == null || old == null) { status("kayıt yöneticisi yok"); return; }
    // IKISI BIRDEN yazilmali; yoksa oyun uyusmazlik gorup parayi sifirliyor.
    old.method("saveTotalMoney").invoke(amount, true);
    sec.method("saveTotalMoneyNew").invoke(amount, true);
    status(`para: ${amount.toLocaleString("tr")}`);
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
        status(`${n} araba açıldı`);
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
        status("yükseltmeler ve görseller maksimum");
    });
}

function unlockExtras(): void {
    Il2Cpp.perform(() => {
        const sec = csClass("SecureSaveGameManager");
        const old = csClass("SaveGameManager");
        if (sec == null || old == null) return;
        for (const m of ["saveHasRemoveAds", "saveHasDoubleCash", "saveHasStarterKit",
                         "saveLocation3AvailableNew", "saveLocation4AvailableNew",
                         "saveLocationRainyAvailable", "saveLocationAutumnAvailable",
                         "saveLocationForestAvailable", "saveLocationDesertAvailable"]) {
            try { sec.method(m).invoke(true, true); } catch (e) { /* imza farkli */ }
        }
        for (const m of ["saveLocationSnowyAvailable", "saveLocationCityAvailable",
                         "saveLocationRainyAvailable", "saveLocationAutumnAvailable",
                         "saveLocationForestAvailable", "saveLocationDesertAvailable"]) {
            try { old.method(m).invoke(true, true); } catch (e) { /* yok */ }
        }
        status("reklamsız + çift para + haritalar");
    });
}

function maxScores(): void {
    Il2Cpp.perform(() => {
        const old = csClass("SaveGameManager");
        if (old == null) return;
        for (const m of ["saveBestExtremeScoreNormal", "saveBestSprintScoreNormal",
                         "saveBestTimeAttackScoreNormal", "saveBestPoliceChaseScore"]) {
            try { old.method(m).invoke(999999.0); } catch (e) { /* yok */ }
        }
        status("skorlar maksimuma çekildi");
    });
}

// ------------------------------------------------------------ çarpışma ------
function setNoCollision(on: boolean): void {
    Il2Cpp.perform(() => {
        toggleStub("CarCollisionDetector", ["OnTriggerEnter", "OnTriggerStay"], on);
        state.noCollision = on;
        status(`çarpışma ${on ? "KAPALI" : "açık"}`);
    });
}

function setNoBoundary(on: boolean): void {
    Il2Cpp.perform(() => {
        toggleStub("CarMover", ["checkBoundary", "hitBoundary"], on);
        state.noBoundary = on;
        status(`yol sınırı ${on ? "KAPALI" : "açık"}`);
    });
}

// --------------------------------------------------------------- trafik -----
function setNoTraffic(on: boolean): void {
    Il2Cpp.perform(() => {
        toggleStub("RandomCarSpawner", ["SpawnCar"], on);
        eachInstance("RandomCarSpawner", o => { o.field<boolean>("canSpawn").value = !on; });
        state.noTraffic = on;
        status(`trafik ${on ? "KAPALI" : "açık"}`);
    });
}

function setSlowTraffic(on: boolean): void {
    Il2Cpp.perform(() => {
        eachInstance("RandomCarSpawner", o => {
            const key = o.handle.toString();
            const fMin = o.field<number>("trafficMinSpeed");
            const fMax = o.field<number>("trafficMaxSpeed");
            if (!originals.has(key) && !spawnerOriginals.has(key)) {
                spawnerOriginals.set(key, {
                    min: fMin.value as unknown as number,
                    max: fMax.value as unknown as number,
                });
            }
            const orig = spawnerOriginals.get(key);
            if (orig == null) return;
            fMin.value = on ? orig.min * 0.25 : orig.min;
            fMax.value = on ? orig.max * 0.25 : orig.max;
        });
        state.slowTraffic = on;
        status(`yavaş trafik ${on ? "AÇIK" : "kapalı"}`);
    });
}

// ----------------------------------------------------------- süper hız ------
/** Sadece OYUNCUNUN arabasi: isAI == false. */
function applySpeedTo(o: Il2Cpp.Object, on: boolean): void {
    if (o.field<boolean>("isAI").value) return;
    const key = o.handle.toString();
    const fMs = o.field<number>("maxSpeed");
    const fAcc = o.field<number>("maxAcceleration");
    if (!originals.has(key)) {
        originals.set(key, {
            ms: fMs.value as unknown as number,
            acc: fAcc.value as unknown as number,
        });
    }
    const orig = originals.get(key);
    if (orig == null) return;
    fMs.value = on ? orig.ms * state.speedMult : orig.ms;
    fAcc.value = on ? orig.acc * 2 : orig.acc;
}

/**
 * Araba olustugunda yakala. Interceptor.attach ORIJINALI BOZMAZ - sadece
 * dinler. Yarista bir kez calisir, yani bedava.
 */
function installCarHook(): void {
    if (carStartHook != null) return;
    const k = csClass("CarMover");
    if (k == null) return;
    let m: any = null;
    for (const name of ["myStart", "Start", "Awake"]) {
        try { m = k.method(name); break; } catch (e) { /* sonrakini dene */ }
    }
    if (m == null) { log("CarMover başlangıç metodu yok"); return; }
    try {
        carStartHook = Interceptor.attach(m.virtualAddress, {
            onEnter(this: any, args: any) { this.self = args[0]; },
            onLeave(this: any) {
                if (!state.superSpeed) return;
                try {
                    applySpeedTo(new Il2Cpp.Object(this.self), true);
                } catch (e) { /* bu nesne olmadi */ }
            },
        });
        log("CarMover hook kuruldu (olay tabanlı, taramasız)");
    } catch (e: any) {
        log(`CarMover hook kurulamadı: ${e.message ?? e}`);
    }
}

function setSuperSpeed(on: boolean): void {
    state.superSpeed = on;
    Il2Cpp.perform(() => {
        installCarHook();
        // Su an sahnedeki arabaya da uygula: TEK SEFERLIK tarama.
        eachInstance("CarMover", o => applySpeedTo(o, on));
    });
    status(`süper hız ${on ? `AÇIK ×${state.speedMult}` : "kapalı"}`);
}

function cycleSpeedMult(): void {
    state.speedMult = state.speedMult >= 5 ? 2 : state.speedMult + 1;
    if (state.superSpeed) {
        Il2Cpp.perform(() => eachInstance("CarMover", o => applySpeedTo(o, true)));
    }
    status(`hız çarpanı ×${state.speedMult}`);
}

function instantMaxSpeed(): void {
    Il2Cpp.perform(() => {
        eachInstance("CarMover", o => {
            if (o.field<boolean>("isAI").value) return;
            const max = o.method<number>("getMaxSpeed").invoke() as unknown as number;
            o.method("setSpeed").invoke(max);
        });
        status("anında maksimum hız");
    });
}

// ------------------------------------------------------------- menü ---------
type Row =
    | { kind: "head"; text: string }
    | { kind: "item"; label: () => string; run: () => void; active?: () => boolean };

const ROWS: Row[] = [
    { kind: "head", text: "PARA & KİLİTLER" },
    { kind: "item", label: () => "Para  +1.000.000", run: () => addMoney(1000000) },
    { kind: "item", label: () => "Para  +100.000", run: () => addMoney(100000) },
    { kind: "item", label: () => "Tüm arabaları aç", run: () => unlockAllCars() },
    { kind: "item", label: () => "Yükseltmeleri maksla", run: () => maxUpgrades() },
    { kind: "item", label: () => "Reklamsız + çift para + haritalar", run: () => unlockExtras() },
    { kind: "item", label: () => "Skorları maksla", run: () => maxScores() },

    { kind: "head", text: "YARIŞ" },
    { kind: "item", label: () => "Çarpışma yok", run: () => setNoCollision(!state.noCollision),
      active: () => state.noCollision },
    { kind: "item", label: () => "Trafik yok", run: () => setNoTraffic(!state.noTraffic),
      active: () => state.noTraffic },
    { kind: "item", label: () => "Yavaş trafik", run: () => setSlowTraffic(!state.slowTraffic),
      active: () => state.slowTraffic },
    { kind: "item", label: () => "Yol sınırı yok", run: () => setNoBoundary(!state.noBoundary),
      active: () => state.noBoundary },

    { kind: "head", text: "HIZ  (sadece senin araban)" },
    { kind: "item", label: () => `Süper hız  ×${state.speedMult}`,
      run: () => setSuperSpeed(!state.superSpeed), active: () => state.superSpeed },
    { kind: "item", label: () => `Çarpanı değiştir  (şu an ×${state.speedMult})`,
      run: () => cycleSpeedMult() },
    { kind: "item", label: () => "Anında maksimum hız", run: () => instantMaxSpeed() },

    { kind: "head", text: "DİĞER" },
    { kind: "item", label: () => "Oyun hızı ×2  (her şey)", run: () => setTimeScale(2.0) },
    { kind: "item", label: () => "Oyun hızı ×1  (normal)", run: () => setTimeScale(1.0) },
    { kind: "item", label: () => "API dökümü çıkar", run: () => dumpApi() },
];

let menuBuilt = false;

// Frida 17'nin Java koprusu, JS degerini hangi asiri yuklemeye gonderecegini
// secemiyor (setText/setTextSize hepsinde birden fazla imza var).
function jstr(s: string): any {
    return Java.use("java.lang.String").$new(s);
}

function setText(view: any, s: string): void {
    view.setText.overload("java.lang.CharSequence").call(view, jstr(s));
}

/** Java'nin int renk formati. Color.argb da asiri yuklu, o yuzden elle. */
function argb(a: number, r: number, g: number, b: number): number {
    return ((a << 24) | (r << 16) | (g << 8) | b) | 0;
}

const COL = {
    panel:     argb(245, 16, 17, 22),
    head:      argb(255, 122, 132, 158),
    title:     argb(255, 108, 214, 255),
    itemBg:    argb(255, 34, 36, 46),
    itemOnBg:  argb(255, 24, 104, 72),
    itemTx:    argb(255, 232, 235, 242),
    itemOnTx:  argb(255, 178, 255, 220),
    status:    argb(255, 150, 156, 172),
    toggleBg:  argb(235, 198, 44, 66),
};

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

    const WRAP = -2, MATCH = -1, VERTICAL = 1, GONE = 8, VISIBLE = 0;

    // Ham piksel her ekranda farkli goruntu veriyordu; her olcu yogunlukla carpiliyor.
    const density: number = activity.getResources().getDisplayMetrics().density.value;
    const dp = (v: number) => Math.round(v * density);
    const sp = (view: any, size: number) =>
        view.setTextSize.overload("int", "float").call(view, 2 /* SP */, size);

    const rounded = (view: any, color: number, radiusDp: number) => {
        const g = GradientDrawable.$new();
        g.setColor.overload("int").call(g, color);
        g.setCornerRadius(dp(radiusDp));
        view.setBackground(g);
    };

    let panel: any;
    let statusView: any;
    const buttons: any[] = [];

    const refresh = () => {
        ROWS.forEach((row, i) => {
            if (row.kind !== "item") return;
            const b = buttons[i];
            if (b == null) return;
            try {
                setText(b, row.label());
                const on = row.active != null && row.active();
                rounded(b, on ? COL.itemOnBg : COL.itemBg, 9);
                b.setTextColor(on ? COL.itemOnTx : COL.itemTx);
            } catch (e) { /* önemsiz */ }
        });
        try { setText(statusView, lastStatus); } catch (e) { /* önemsiz */ }
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
                        return;
                    }
                    const row = ROWS[i];
                    if (row != null && row.kind === "item") row.run();
                } catch (e: any) {
                    status(`hata: ${e.message ?? e}`);
                }
                refresh();
            },
        },
    });

    const mkClick = (i: number) => {
        const c = Click.$new();
        c.idx.value = i;
        return c;
    };

    // --- panel içeriği ------------------------------------------------------
    panel = LinearLayout.$new(activity);
    panel.setOrientation(VERTICAL);
    panel.setPadding(dp(12), dp(10), dp(12), dp(12));
    rounded(panel, COL.panel, 14);
    panel.setVisibility(GONE);

    const title = TextView.$new(activity);
    setText(title, "TRAFFIC RACER  ·  MOD");
    title.setTextColor(COL.title);
    sp(title, 13);
    title.setTypeface(Typeface.DEFAULT_BOLD.value);
    title.setPadding(dp(2), 0, 0, dp(8));
    panel.addView(title);

    ROWS.forEach((row, i) => {
        try {
            if (row.kind === "head") {
                const h = TextView.$new(activity);
                setText(h, row.text);
                h.setTextColor(COL.head);
                sp(h, 10);
                h.setTypeface(Typeface.DEFAULT_BOLD.value);
                h.setPadding(dp(2), dp(10), 0, dp(4));
                panel.addView(h);
                return;
            }
            const b = Button.$new(activity);
            setText(b, row.label());
            b.setAllCaps(false);
            sp(b, 12.5);
            b.setTextColor(COL.itemTx);
            b.setGravity(Gravity.CENTER_VERTICAL.value | Gravity.LEFT.value);
            b.setPadding(dp(12), 0, dp(12), 0);
            rounded(b, COL.itemBg, 9);
            b.setOnClickListener(mkClick(i));

            const lp = LinearParams.$new(MATCH, dp(40));
            lp.setMargins(0, dp(3), 0, dp(3));
            b.setLayoutParams(lp);
            panel.addView(b);
            buttons[i] = b;
        } catch (e: any) {
            log(`satır eklenemedi (${i}): ${e.message ?? e}`);
        }
    });

    statusView = TextView.$new(activity);
    setText(statusView, lastStatus);
    statusView.setTextColor(COL.status);
    sp(statusView, 10.5);
    statusView.setPadding(dp(2), dp(10), 0, 0);
    panel.addView(statusView);

    // Uzun liste ekrandan tasmasin.
    const scroll = ScrollView.$new(activity);
    scroll.addView(panel);
    scroll.setLayoutParams(LinearParams.$new(dp(250), dp(360)));

    // --- açma düğmesi -------------------------------------------------------
    const toggle = Button.$new(activity);
    setText(toggle, "MOD");
    toggle.setAllCaps(false);
    sp(toggle, 12);
    toggle.setTextColor(argb(255, 255, 255, 255));
    toggle.setTypeface(Typeface.DEFAULT_BOLD.value);
    toggle.setPadding(0, 0, 0, 0);
    rounded(toggle, COL.toggleBg, 17);
    toggle.setOnClickListener(mkClick(-1));
    const tLp = LinearParams.$new(dp(60), dp(34));
    tLp.setMargins(0, 0, 0, dp(6));
    toggle.setLayoutParams(tLp);

    const wrapper = LinearLayout.$new(activity);
    wrapper.setOrientation(VERTICAL);
    wrapper.addView(toggle);
    wrapper.addView(scroll);

    const params = FrameLayoutParams.$new(WRAP, WRAP);
    params.gravity.value = Gravity.TOP.value | Gravity.LEFT.value;
    params.leftMargin.value = dp(10);
    params.topMargin.value = dp(36);

    activity.addContentView(wrapper, params);
    refresh();
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
