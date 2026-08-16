# Windows kurulum yardımcısı — gerekli araçları kurar.
#
# Çalıştırma (PowerShell, yönetici GEREKMEZ):
#   powershell -ExecutionPolicy Bypass -File .\windows\kurulum.ps1
#
# Kurdukları: Git for Windows (Git Bash), JDK 21, Android platform-tools (adb).
# Python GEREKMİYOR (opsiyonel). Zaten kurulu olanları atlar.
# Sonrasında işlem Git Bash içinden yürür.

function Say($msg)  { Write-Host "==> $msg" -ForegroundColor Cyan }
function Good($msg) { Write-Host " ok  $msg" -ForegroundColor Green }
function Note($msg) { Write-Host " dikkat $msg" -ForegroundColor Yellow }

# PATH'i registry'den tazele — winget kurulumundan sonra bu process eski PATH'i taşır.
function Update-PathFromRegistry {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

function Have($name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if (-not $cmd) { return $false }
    # Windows'un "python.exe" Store kısayolu gerçek bir kurulum değildir.
    if ($cmd.Source -and $cmd.Source -like '*\WindowsApps\*') { return $false }
    return $true
}

# $ids birden fazla winget paket adı alabilir; ilki tutmazsa sıradakini dener
# (winget paket adları sürümle değişir, tek bir ada bağlanmak kırılgan).
function Install-WithWinget($ids, $label, $probe) {
    if (Have $probe) { Good "$label zaten kurulu"; return }
    if (-not (Have 'winget')) {
        Note "$label yok ve winget de yok."
        Note "  winget'i almak icin: Microsoft Store > 'App Installer' (Uygulama Yukleyici) kur,"
        Note "  ya da $label'i elle kur (README'deki baglantilar)."
        return
    }
    foreach ($id in @($ids)) {
        Say "$label kuruluyor (winget: $id)..."
        winget install --id $id -e --source winget --accept-package-agreements --accept-source-agreements
        Update-PathFromRegistry
        if ($LASTEXITCODE -eq 0 -or (Have $probe)) { Good "$label kuruldu"; return }
        Note "$id ile olmadi (kod $LASTEXITCODE), sonraki aday deneniyor..."
    }
    Note "$label kurulamadi. Elle kurman gerekiyor (README'deki baglantilar)."
}

Say "Windows kurulum yardımcısı"
Write-Host ""

Update-PathFromRegistry

Install-WithWinget 'Git.Git' 'Git for Windows (Git Bash)' 'git'
Install-WithWinget @('EclipseAdoptium.Temurin.21.JDK', 'EclipseAdoptium.Temurin.17.JDK') 'JDK' 'java'

# Python ARTIK GEREKLİ DEĞİL — kayıt dosyası düzenleme awk ile yapılıyor ve awk
# Git Bash'in içinde geliyor. Kuruluysa 05-engine-info.sh biraz daha ayrıntı verir.
if (Have 'python') {
    Good "Python 3 kurulu (opsiyonel, zaten var)"
} else {
    Good "Python yok — sorun değil, zincir Python'suz çalışıyor (opsiyonel bağımlılık)"
}

# --- adb: doğrudan Google'ın zip'inden, en güvenilir yol ---------------------
$ptDir = Join-Path $env:LOCALAPPDATA 'Android\platform-tools'

if (Have 'adb') {
    Good "adb zaten PATH'te"
} elseif (Test-Path (Join-Path $ptDir 'adb.exe')) {
    Good "adb zaten kurulu: $ptDir"
} else {
    Say "Android platform-tools (adb) indiriliyor..."
    $zip  = Join-Path $env:TEMP 'platform-tools.zip'
    $dest = Join-Path $env:LOCALAPPDATA 'Android'
    try {
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' `
                          -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $dest -Force
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Good "adb kuruldu: $ptDir"
    } catch {
        Note "platform-tools indirilemedi: $($_.Exception.Message)"
        Note "Elle indir: https://developer.android.com/tools/releases/platform-tools"
    }
}

# PATH'e ekle (kullanıcı seviyesi, yönetici gerekmez)
if (Test-Path (Join-Path $ptDir 'adb.exe')) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $userPath) { $userPath = '' }
    if ($userPath -notlike "*$ptDir*") {
        $newPath = ($userPath.TrimEnd(';') + ';' + $ptDir).TrimStart(';')
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Good "platform-tools kullanıcı PATH'ine eklendi"
        Note "Kalıcı olması için YENİ bir pencere açman gerekiyor."
    }
    $env:Path = $env:Path.TrimEnd(';') + ';' + $ptDir
}

Write-Host ""
Say "Durum"
$missing = @()
foreach ($tool in @('git', 'java', 'adb')) {
    if (Have $tool) { Good "$tool bulundu" } else { Note "$tool -> YOK (gerekli)"; $missing += $tool }
}
if (Have 'python') { Good "python bulundu (opsiyonel)" } else { Good "python yok (opsiyonel, gerekmiyor)" }

if ($missing.Count -gt 0) {
    Write-Host ""
    Note ("Eksik ve gerekli: " + ($missing -join ', '))
    Note "Yeni bir PowerShell penceresi acip bu script'i tekrar calistir; hala eksikse elle kur."
} else {
    Write-Host ""
    Good "Gerekli her sey hazir."
}

Write-Host ""
Say "Sirada ne var"
Write-Host @"
  1. Telefonda: Ayarlar > Telefon hakkinda > 'Yapi numarasi'na 7 kez dokun
     -> Gelistirici secenekleri > USB hata ayiklama: ACIK
  2. Telefonu USB ile bagla, ekranda cikan 'Bu bilgisayara izin ver' penceresini onayla.
  3. YENI bir pencere ac ve dogrula:   adb devices
     Cihaz 'device' olarak gorunmeli ('unauthorized' ise izni onaylamamissin).
  4. Bu klasorde sag tik > 'Open Git Bash here', sonra:

       ./tr.sh all
       ./tr.sh prefs list

"@
