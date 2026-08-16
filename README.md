# Traffic Racer — root'suz mod araç zinciri

Root gerektirmeden, kendi telefonunda Traffic Racer'ın kayıt verisini (para, açılmış
araçlar, skor) düzenlemeni sağlayan script'ler.

Seçilen yöntem **en kolay ve en az kırılgan olanı**: oyunun koduna/dex'ine hiç
dokunulmuyor. Sadece `AndroidManifest.xml` içine `android:debuggable="true"`
ekleniyor, APK yeniden imzalanıyor — bu tek satır sayesinde `adb shell run-as` ile
uygulamanın özel veri klasörüne **root olmadan** erişilebiliyor. Oradaki Unity
PlayerPrefs dosyası düz XML; değeri değiştirip geri yazıyorsun.

Neden bu yol: smali/IL2CPP yamalamak yeniden derleme hatası, ARM64 disassembly ve
saatlerce deneme gerektirir. Manifest yaması ise tek satır, geri alınabilir ve
oyunun her sürümünde aynı şekilde çalışır.

---

## Gereksinimler

| Ne | Nasıl |
|---|---|
| JDK 17+ | Windows: `windows\kurulum.ps1` · Linux: `sudo apt install openjdk-17-jdk` · macOS: `brew install openjdk@17` |
| adb (platform-tools) | Windows: `windows\kurulum.ps1` · Linux: `sudo apt install android-tools-adb` · macOS: `brew install android-platform-tools` |
| python3 | opsiyonel ama tavsiye edilir (kayıt dosyasını listeleme/düzenleme kolaylığı) |
| Telefon | USB hata ayıklama açık, USB ile bağlı, Traffic Racer **Play Store'dan kurulu** |

> APK'yı ben indirmiyorum ve sen de üçüncü parti "mod apk" sitelerinden indirme.
> Zincir, APK'yı **senin kendi cihazından** çeker — hem tek yasal kaynak bu, hem de
> o siteler malware doludur.

---

## Windows

Script'ler bash. Windows'ta **Git Bash** üzerinden çalışıyorlar — WSL, sanal makine
ya da ayrı bir Linux gerekmiyor. `windows\kurulum.ps1` eksik araçları kurar.

**1. Bağımlılıkları kur** — PowerShell aç (yönetici gerekmez), klasöre gel:

```powershell
git clone https://github.com/Nestyyyyyy/Tr.git
cd Tr
powershell -ExecutionPolicy Bypass -File .\windows\kurulum.ps1
```

Git for Windows, JDK 21, Python 3 ve adb'yi kurar; kurulu olanları atlar.
Git yoksa `git clone` da çalışmaz — o durumda önce https://git-scm.com/download/win
adresinden Git'i kur, sonra bu adımı tekrarla.

**2. Telefonu hazırla**
- Ayarlar → Telefon hakkında → **Yapı numarası**'na 7 kez dokun (geliştirici modu açılır)
- Geliştirici seçenekleri → **USB hata ayıklama: açık**
- USB kabloyu tak, telefonda çıkan **"Bu bilgisayara izin ver"** penceresini onayla
- Yeni bir pencerede `adb devices` → cihaz `device` olarak görünmeli

**3. Zinciri çalıştır** — klasörde sağ tık → **"Open Git Bash here"**:

```bash
./tr.sh all            # araçları indir + APK'yı çek + yamala + kur
```

Sonra oyunu bir kez aç, 10–15 saniye oyna, ana menüye dön. Ardından:

```bash
./tr.sh prefs list                  # tüm anahtarları göster
./tr.sh prefs guess                 # para/ilerleme adaylarını süz
./tr.sh prefs set <anahtar> 999999
```

Windows'a özel notlar:
- **PowerShell'de `./tr.sh` çalışmaz** — bash script'i, Git Bash penceresi gerekiyor.
- `make` Windows'ta yok; `tr.sh` onun yerine geçiyor (Linux/macOS'ta da çalışır).
- `.gitattributes` script'leri LF satır sonuyla tutuyor. Yine de `$'\r': command not
  found` hatası alırsan: `git config --global core.autocrlf false` sonra depoyu
  yeniden klonla.
- Telefon `adb devices` çıktısında hiç görünmüyorsa USB sürücüsü eksiktir — telefon
  üreticisinin USB driver'ını kur, ya da kabloyu "dosya aktarımı (MTP)" moduna al.

---

## Linux / macOS

```bash
git clone https://github.com/Nestyyyyyy/Tr.git && cd Tr
adb devices          # cihaz "device" olarak görünmeli, telefondaki izni onayla

make tools           # apktool + uber-apk-signer + APKEditor indirir (bir kere)
make pull            # APK'yı telefonundan çeker, split ise birleştirir
make patch           # manifest'i yamalar, zipalign + imza
make install         # orijinali kaldırır, yamalıyı kurar
```

Sonra **oyunu bir kez aç, 10–15 saniye oyna, ana menüye dön** (kayıt dosyası ancak
o zaman oluşur). Ardından:

```bash
make prefs                              # tüm anahtarları ve değerleri listeler
./tools/04-prefs.sh guess               # para/ilerleme adaylarını süzer
./tools/04-prefs.sh set <anahtar> 999999
```

`./tr.sh <komut>` her platformda `make <komut>` ile aynı işi yapar.

`set` komutu sırayla: oyunu kapatır → dosyayı çeker → `out/` altına yedek alır →
değeri değiştirir → geri yazar → cihazdaki dosyayı geri okuyup karşılaştırır.

---

## Adım adım ne oluyor

| Script | İş |
|---|---|
| `tools/00-fetch-tools.sh` | apktool, uber-apk-signer, APKEditor jar'larını `bin/`'e indirir |
| `tools/01-pull.sh` | `pm path` ile APK yollarını bulur, çeker; App Bundle ise APKEditor ile tek APK'ya birleştirir → `work/original.apk` |
| `tools/02-patch.sh` | `apktool d -s` (dex'e dokunmaz) → manifest'e `debuggable` + `allowBackup` → `apktool b` → zipalign + imza → `out/<paket>-debuggable.apk` |
| `tools/03-install.sh` | Orijinali kaldırır (imza farklı, üzerine kurulmaz), yamalıyı kurar, `run-as` erişimini test eder |
| `tools/04-prefs.sh` | Kayıt dosyasını `run-as` ile okur/yazar: `list`, `guess`, `get`, `set`, `pull`, `push`, `backup` |
| `tools/05-engine-info.sh` | Plan B: APK Mono mu IL2CPP mi, hangi dosyaya bakılacak |

| `tools/selftest.sh` | Cihaz/APK gerektirmeyen test: manifest yaması ve prefs düzenleyici mantığını doğrular |
| `tr.sh` | Hepsinin tek giriş noktası (`make` olmayan Windows için) |
| `windows/kurulum.ps1` | Windows'ta Git, JDK, Python ve adb kurar |

Farklı bir oyun için paket adını ver:

```bash
PKG=com.ornek.oyun make pull patch install
PKG=com.ornek.oyun ./tools/04-prefs.sh list
```

---

## Bilmen gereken üç şey

1. **Mevcut ilerlemen silinir.** İmza değiştiği için orijinal uygulamanın kaldırılması
   zorunlu, kaldırma da veriyi siler. Root'suz bunu atlamanın yolu yok — sıfırdan
   başlayıp değeri script ile ayarlaman gerekir.
2. **Skor tablosuna dokunma.** Traffic Racer'ın online skor tablosu var. Şişirilmiş
   skor göndermek diğer oyuncuları etkiler ve ban sebebidir; bu zincir tek oyunculu,
   yerel ilerleme içindir.
3. **Modlu APK'yı dağıtma.** Kendi cihazında kullanmak ile yeniden yayınlamak arasında
   telif açısından net fark var. `.gitignore` zaten APK'ların repoya girmesini engelliyor.

Ek olarak: imza değiştiği için Google Play Games / bulut kaydı bağlantısı kopabilir.

---

## Sorun giderme

**`adb devices` boş / "unauthorized"**
Ayarlar → Geliştirici seçenekleri → USB hata ayıklama açık mı; kabloyu tak, telefonda
çıkan "Bu bilgisayara izin ver" penceresini onayla. Gerekirse `adb kill-server && adb devices`.

**`run-as` reddedildi (`run-as: package not debuggable`)**
Yamalı sürüm kurulu değil demektir — `make install` çıktısını kontrol et. Xiaomi/MIUI'da
"MIUI optimizasyonu" `run-as`'ı engelleyebiliyor; geliştirici seçeneklerinden kapat.

**`INSTALL_FAILED_UPDATE_INCOMPATIBLE`**
Orijinal hâlâ kurulu: `adb uninstall com.skgames.trafficracer`, sonra tekrar `make install`.

**`INSTALL_FAILED_INVALID_APK` / kurulum reddi**
Telefonda "USB ile uygulama kurma" iznini onayla. Play Protect uyarısı çıkarsa
"yine de kur" de.

**`shared_prefs boş`**
Oyunu kurduktan sonra bir kez açıp oynamadın. Oyna, ana menüye dön, sonra `make prefs`.

**`apktool build başarısız`**
Nadir. `work/decoded/` altındaki apktool hata çıktısına bak; genelde `bin/apktool.jar`
sürümünü güncellemek çözer (`00-fetch-tools.sh` içindeki `APKTOOL_VER`).

**(Windows) `$'\r': command not found` veya `syntax error near unexpected token`**
Script'ler CRLF'e çevrilmiş. `git config --global core.autocrlf false`, sonra depoyu
sil ve yeniden klonla.

**(Windows) `./tr.sh: command not found` / `is not recognized`**
PowerShell veya CMD'desin. Klasörde sağ tık → **"Open Git Bash here"**.

**(Windows) `java` veya `adb` bulunamadı**
`windows\kurulum.ps1` PATH'i değiştirdiyse **yeni** bir pencere açman gerekir; açık
Git Bash eski PATH'i taşır.

**(Windows) `adb devices` cihazı hiç göstermiyor**
USB sürücüsü eksik. Telefonu "dosya aktarımı (MTP)" moduna al, olmazsa üreticinin USB
driver'ını kur. Kablo veri taşımıyorsa (bazı şarj kabloları) hiçbir şey görünmez.

---

## Plan B — kayıt dosyası yetmezse

`04-prefs.sh list` çıktısında para anahtarı yoksa ya da değerler şifreli/anlamsız
görünüyorsa, oyun kaydı kendi şifreliyor demektir. O zaman koda inmek gerekir:

```bash
make info    # Mono mu IL2CPP mi söyler
```

- **Mono** → `assets/bin/Data/Managed/Assembly-CSharp.dll` dosyasını çıkar, **dnSpyEx**
  ile aç, ilgili metodu C# olarak düzenle, APK'ya geri koy, `02-patch.sh`'deki gibi imzala.
- **IL2CPP** → `Il2CppDumper` ile `global-metadata.dat` + `libil2cpp.so`'dan sembolleri
  çıkar, Ghidra/IDA'da fonksiyonu bul ve ARM64 talimatını yamala. Daha hızlı alternatif:
  APK'ya `frida-gadget` enjekte edip çalışma zamanında hook'lamak (bu da root istemez).

---

## Doğrulama durumu

- `tools/selftest.sh` — 30 test, cihazsız çalışır (manifest yaması + prefs düzenleyici).
- APK zinciri (`00` → `02`) özgür lisanslı bir APK üzerinde uçtan uca çalıştırıldı:
  çöz → manifest yamala → yeniden paketle → zipalign → imzala. Çıkan APK yeniden
  çözüldüğünde `android:debuggable="true"` manifestte görünüyor, `uber-apk-signer -y`
  çıktısı `zipalign verified` + `signature verified [v1, v2, v3]`.
- Windows'un kullandığı kod yolları (unzip'siz Python fallback, `python`/`py` çözümü)
  Linux'ta simüle edilerek test edildi; Git Bash'in kendisinde çalıştırılmadı.
- `windows/kurulum.ps1` PowerShell gerektirdiği için burada çalıştırılamadı. Yaptığı iş
  winget çağrıları + bir zip indirmesi; başarısız olursa README'deki elle kurulum
  bağlantıları aynı sonucu verir.
- `01-pull.sh`, `03-install.sh` ve `04-prefs.sh` bağlı bir telefon gerektirdiği için
  ancak sende çalıştırıldığında doğrulanır.

---

## Yasal not

Bu araçlar **kendi cihazında, kendi kopyanda, tek oyunculu ilerleme için** yazıldı.
Oyunun kullanım şartlarını ihlal eder; hesap yaptırımı riski sana aittir. Modlu APK'yı
dağıtmak ayrıca telif ihlalidir.
