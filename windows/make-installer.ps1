# Dark Crown - автосборка установщика DarkCrown-Setup.exe (Windows PowerShell)
#
# Всё делает сам:
#   1. Находит LibreWolf или скачивает и устанавливает его
#   2. Находит Inno Setup или скачивает и устанавливает его
#   3. Накладывает настройки, расширения и тему
#   4. Собирает dist\DarkCrown-Setup.exe и кладёт копию на рабочий стол
#
# Запуск:   .\make-installer.ps1
# Своя папка LibreWolf:   .\make-installer.ps1 -LibreWolfDir "D:\LibreWolf"

param(
  [string]$LibreWolfDir = "",
  [switch]$NoBrandPatch
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
$ProgressPreference = "SilentlyContinue"

function Find-LibreWolf {
  $c = @(
    "$env:ProgramFiles\LibreWolf",
    "${env:ProgramFiles(x86)}\LibreWolf",
    "$env:LOCALAPPDATA\Programs\LibreWolf",
    "$env:LOCALAPPDATA\LibreWolf"
  ) | Where-Object { Test-Path "$_\librewolf.exe" } | Select-Object -First 1
  if ($c) { return $c }

  foreach ($k in @(
      "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\librewolf.exe",
      "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\librewolf.exe")) {
    try {
      $v = (Get-Item $k -ErrorAction Stop).GetValue("")
      if ($v -and (Test-Path $v)) { return (Split-Path $v) }
    } catch { }
  }
  foreach ($k in @(
      "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
      "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
      "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*")) {
    try {
      $hit = Get-ItemProperty $k -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*LibreWolf*" } | Select-Object -First 1
      if ($hit -and $hit.InstallLocation -and (Test-Path "$($hit.InstallLocation)\librewolf.exe")) {
        return $hit.InstallLocation.TrimEnd('\')
      }
    } catch { }
  }
  return $null
}

function Find-Iscc {
  return @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Test-Exe($path, $minSize = 1MB) {
  if (-not (Test-Path $path)) { return $false }
  if ((Get-Item $path).Length -lt $minSize) { return $false }
  $fs = [IO.File]::OpenRead($path)
  try { $b1 = $fs.ReadByte(); $b2 = $fs.ReadByte() } finally { $fs.Close() }
  return ($b1 -eq 0x4D -and $b2 -eq 0x5A)
}

# Скачивает файл по списку адресов, проверяет что это настоящий .exe
function Get-Exe($urls, $out, $minSize = 1MB) {
  foreach ($u in $urls) {
    foreach ($mode in @("iwr", "curl")) {
      try {
        if (Test-Path $out) { Remove-Item $out -Force }
        if ($mode -eq "iwr") {
          Invoke-WebRequest -Uri $u -OutFile $out -UseBasicParsing -MaximumRedirection 10
        } else {
          & curl.exe -L -s -S --fail -o $out $u 2>$null
          if ($LASTEXITCODE -ne 0) { continue }
        }
        if (Test-Exe $out $minSize) { return $true }
      } catch { }
    }
  }
  return $false
}

Write-Host "=== Dark Crown: автосборка ==="

# ---------- 1. LibreWolf ----------
if ($LibreWolfDir -and -not (Test-Path "$LibreWolfDir\librewolf.exe")) { $LibreWolfDir = "" }
if (-not $LibreWolfDir) { $LibreWolfDir = Find-LibreWolf }

if (-not $LibreWolfDir) {
  Write-Host "[1/4] LibreWolf не найден. Скачиваю и устанавливаю..."
  $setup = Join-Path $env:TEMP "librewolf-setup.exe"
  try {
    $rel = Invoke-RestMethod "https://codeberg.org/api/v1/repos/librewolf/bsys6/releases/latest"
    $asset = $rel.assets | Where-Object {
      $_.name -match "setup" -and $_.name -match "\.exe$" -and $_.name -notmatch "arm"
    } | Select-Object -First 1
    if (-not $asset) { throw "в релизе не нашёлся установщик .exe" }
    Write-Host "Скачиваю $($asset.name) ..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $setup -UseBasicParsing
    Write-Host "Устанавливаю (если Windows спросит разрешение — согласись)..."
    Start-Process $setup -ArgumentList "/S" -Wait
    $LibreWolfDir = Find-LibreWolf
    if (-not $LibreWolfDir) {
      Write-Host "Тихая установка не сработала. Запускаю обычный установщик: пройди его кнопкой 'Далее'."
      Start-Process $setup -Wait
      $LibreWolfDir = Find-LibreWolf
    }
  } catch {
    Write-Host "Автоустановка LibreWolf не удалась: $($_.Exception.Message)"
  }
}

if (-not $LibreWolfDir) {
  Write-Host "LibreWolf автоматически не найден."
  Write-Host "Если он установлен: ПКМ по ярлыку LibreWolf -> 'Расположение файла', скопируй путь к папке."
  Write-Host "Если нет: https://librewolf.net/installation/windows/"
  $typed = (Read-Host "Вставь путь к папке с librewolf.exe (или Enter, чтобы выйти)").Trim().Trim('"')
  if ($typed -and (Test-Path "$typed\librewolf.exe")) { $LibreWolfDir = $typed }
  else { Write-Host "librewolf.exe не найден. Выхожу."; exit 1 }
}
Write-Host "[1/4] LibreWolf: $LibreWolfDir"

# ---------- 2. Inno Setup ----------
$iscc = Find-Iscc
if (-not $iscc) {
  Write-Host "[2/4] Inno Setup не найден. Скачиваю и устанавливаю..."
  $isSetup = Join-Path $env:TEMP "innosetup.exe"
  $urls = @()
  # Inno Setup лежит на GitHub: ищем самую свежую версию 6.x
  try {
    $rels = Invoke-RestMethod "https://api.github.com/repos/jrsoftware/issrc/releases?per_page=30" -Headers @{ "User-Agent" = "DarkCrown" }
    $best = $null
    foreach ($r in $rels) {
      foreach ($asset in $r.assets) {
        if ($asset.name -match '^innosetup-(6\.\d+\.\d+)\.exe$') {
          $v = [version]$Matches[1]
          if (-not $best -or $v -gt $best.v) { $best = @{ v = $v; url = $asset.browser_download_url } }
        }
      }
    }
    if ($best) { $urls += $best.url }
  } catch { }
  # Запасные адреса
  $urls += "https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe"
  $urls += "https://jrsoftware.org/download.php/is.exe"

  if (Get-Exe $urls $isSetup) {
    try {
      Start-Process $isSetup -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-" -Wait
    } catch {
      Write-Host "Не удалось запустить установщик Inno Setup: $($_.Exception.Message)"
    }
  } else {
    Write-Host "Не удалось скачать Inno Setup автоматически."
  }
  $iscc = Find-Iscc
}
if (-not $iscc) {
  Write-Host "Inno Setup 6 не установлен. Открываю страницу загрузки: скачай, установи (кнопка 'Далее') и запусти build-me.bat снова."
  Start-Process "https://jrsoftware.org/isdl.php"
  exit 1
}
Write-Host "[2/4] Inno Setup: $iscc"

# ---------- проверка наших файлов ----------
foreach ($f in "icon.ico", "crowntools.xpi", "userChrome.css", "darkcrown.cfg", "darkcrown.iss",
               "themes\gold.css", "themes\purple.css", "themes\red.css", "themes\green.css", "themes\black.css",
               "userContent.css", "logo.css", "hardening-policies.json") {
  if (-not (Test-Path $f)) { Write-Host "Нет файла $f рядом со скриптом."; exit 1 }
}

# ---------- 3. Сборка папки stage ----------
Write-Host "[3/4] Готовлю файлы..."
if (Test-Path stage) { Remove-Item stage -Recurse -Force }
Copy-Item $LibreWolfDir stage -Recurse

$cfg = "stage\librewolf.cfg"
if (Test-Path $cfg) {
  Add-Content -Path $cfg -Value "`n"
  Add-Content -Path $cfg -Value (Get-Content darkcrown.cfg -Raw)
  Write-Host "Настройки Dark Crown добавлены в librewolf.cfg"
} else {
  Write-Host "ВНИМАНИЕ: librewolf.cfg не найден в $LibreWolfDir - настройки не добавлены."
}

$distDir = "stage\distribution"
New-Item -ItemType Directory -Force -Path $distDir | Out-Null
$polFile = "$distDir\policies.json"

if (Test-Path $polFile) {
  $pol = Get-Content $polFile -Raw | ConvertFrom-Json
} else {
  $pol = [pscustomobject]@{ policies = [pscustomobject]@{} }
}
if (-not $pol.policies.PSObject.Properties["ExtensionSettings"]) {
  $pol.policies | Add-Member -NotePropertyName ExtensionSettings -NotePropertyValue ([pscustomobject]@{})
}
$ext = $pol.policies.ExtensionSettings

$ext | Add-Member -Force -NotePropertyName "crowntools@darkcrown.local" -NotePropertyValue ([pscustomobject]@{
  installation_mode = "force_installed"
  install_url       = "file:///@@APP@@/crowntools.xpi"
  private_browsing  = $true
})
$ext | Add-Member -Force -NotePropertyName "{74145f27-f039-47ce-a470-a662b129930a}" -NotePropertyValue ([pscustomobject]@{
  installation_mode = "force_installed"
  install_url       = "https://addons.mozilla.org/firefox/downloads/latest/clearurls/latest.xpi"
  private_browsing  = $true
})

# Политики безопасности (hardening-policies.json): добавляются поверх остальных
if (Test-Path "hardening-policies.json") {
  $hard = Get-Content "hardening-policies.json" -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($p in $hard.policies.PSObject.Properties) {
    $pol.policies | Add-Member -Force -NotePropertyName $p.Name -NotePropertyValue $p.Value
  }
  Write-Host "Политики безопасности добавлены."
}

$json = $pol | ConvertTo-Json -Depth 20
[IO.File]::WriteAllText((Join-Path $here $polFile), $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "policies.json обновлён."

# ---------- 3a. Свой значок и имя ВНУТРИ браузера (необязательно, с проверкой запуска) ----------
# Заменяет значки LibreWolf в страницах браузера (настройки, вкладки, "О программе") на твой логотип
# и слово "LibreWolf" на "Dark Crown" в названиях. Если после замены браузер не запускается,
# всё возвращается как было. Отключить: .\make-installer.ps1 -NoBrandPatch
function Get-PngSize([byte[]]$b) {
  if ($b.Length -lt 24 -or $b[0] -ne 0x89 -or $b[1] -ne 0x50 -or $b[2] -ne 0x4E -or $b[3] -ne 0x47) { return $null }
  $w = ([int]$b[16] -shl 24) -bor ([int]$b[17] -shl 16) -bor ([int]$b[18] -shl 8) -bor [int]$b[19]
  $h = ([int]$b[20] -shl 24) -bor ([int]$b[21] -shl 16) -bor ([int]$b[22] -shl 8) -bor [int]$b[23]
  if ($w -le 0 -or $h -le 0 -or $w -gt 4096 -or $h -gt 4096) { return $null }
  return @($w, $h)
}

$script:logoCache = @{}
function New-LogoPng([int]$w, [int]$h) {
  $key = "$w x $h"
  if ($script:logoCache.ContainsKey($key)) { return $script:logoCache[$key] }
  $src = [System.Drawing.Image]::FromFile((Join-Path $here "branding\logo-tile.png"))
  $bmp = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)
  $side = [Math]::Min($w, $h)
  $g.DrawImage($src, [int](($w - $side) / 2), [int](($h - $side) / 2), $side, $side)
  $g.Dispose(); $src.Dispose()
  $ms = New-Object System.IO.MemoryStream
  $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  $bytes = $ms.ToArray()
  $script:logoCache[$key] = $bytes
  return $bytes
}

function Set-ZipEntry($zip, $entry, [byte[]]$bytes) {
  $name = $entry.FullName
  $entry.Delete()
  $new = $zip.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
  $s = $new.Open()
  try { $s.Write($bytes, 0, $bytes.Length) } finally { $s.Dispose() }
}

# Правит один архив omni.ja: значки в папках branding и слово LibreWolf в текстах интерфейса
function Edit-Omni([string]$path) {
  $stat = @{ png = 0; svg = 0; text = 0 }
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  $zip = [System.IO.Compression.ZipFile]::Open($path, [System.IO.Compression.ZipArchiveMode]::Update)
  try {
    foreach ($e in @($zip.Entries)) {
      $low = $e.FullName.ToLowerInvariant()
      if ($low -match '/branding/[^/]+\.png$') {
        $ms = New-Object System.IO.MemoryStream
        $rs = $e.Open(); try { $rs.CopyTo($ms) } finally { $rs.Dispose() }
        $size = Get-PngSize $ms.ToArray()
        if ($size) { Set-ZipEntry $zip $e (New-LogoPng $size[0] $size[1]); $stat.png++ }
      }
      elseif ($low -match '/branding/[^/]+\.svg$') {
        $b64 = [Convert]::ToBase64String((New-LogoPng 256 256))
        $svg = '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><image width="256" height="256" href="data:image/png;base64,' + $b64 + '"/></svg>'
        Set-ZipEntry $zip $e ($utf8.GetBytes($svg)); $stat.svg++
      }
      elseif ($low -match '\.(ftl|properties|dtd)$') {
        $rs = $e.Open(); $sr = New-Object System.IO.StreamReader($rs, $utf8)
        try { $text = $sr.ReadToEnd() } finally { $sr.Dispose() }
        if ($text.Contains("LibreWolf")) {
          Set-ZipEntry $zip $e ($utf8.GetBytes($text.Replace("LibreWolf", "Dark Crown"))); $stat.text++
        }
      }
    }
  } finally { $zip.Dispose() }
  return $stat
}

# Запускает браузер без окна на 10 секунд: жив ли процесс (значит, архивы не повреждены)
function Test-BrowserStarts([string]$exe) {
  $prof = Join-Path $env:TEMP ("dc-smoke-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $prof | Out-Null
  $alive = $false
  try {
    $p = Start-Process $exe -ArgumentList @("-headless", "-no-remote", "-profile", "`"$prof`"", "about:blank") -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 10
    $alive = -not $p.HasExited
  } catch { $alive = $false }
  finally {
    try { Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe } | Stop-Process -Force -ErrorAction SilentlyContinue } catch { }
    Start-Sleep -Milliseconds 800
    Remove-Item $prof -Recurse -Force -ErrorAction SilentlyContinue
  }
  return $alive
}

if (-not $NoBrandPatch -and (Test-Path (Join-Path $here "branding\logo-tile.png"))) {
  try {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stageExe = Join-Path $here "stage\librewolf.exe"
    $archives = @(Get-ChildItem (Join-Path $here "stage") -Recurse -Filter "*.ja" -File)
    if (-not $archives) { throw "в браузере не найдены архивы omni.ja" }

    Write-Host "Проверяю, что исходный браузер запускается (10 секунд)..."
    if (-not (Test-BrowserStarts $stageExe)) {
      Write-Host "Пробный запуск не удался: замену значков и названия пропускаю (браузер от этого не страдает)."
    } else {
      $bakDir = Join-Path $env:TEMP "dc-omni-backup"
      if (Test-Path $bakDir) { Remove-Item $bakDir -Recurse -Force }
      New-Item -ItemType Directory -Path $bakDir | Out-Null
      $i = 0
      $map = @{}
      foreach ($a in $archives) { $i++; $bak = Join-Path $bakDir ("$i.ja"); Copy-Item $a.FullName $bak; $map[$a.FullName] = $bak }

      Write-Host "Заменяю значки и название внутри браузера (это может занять минуту)..."
      foreach ($a in $archives) {
        $st = Edit-Omni $a.FullName
        Write-Host ("  {0}: значков {1}, векторных {2}, текстов {3}" -f $a.Name, $st.png, $st.svg, $st.text)
      }

      Write-Host "Проверяю, что браузер после замены запускается..."
      if (Test-BrowserStarts $stageExe) {
        Write-Host "Значки и название заменены."
      } else {
        Write-Host "После замены браузер не запустился: возвращаю исходные файлы."
        foreach ($k in $map.Keys) { Copy-Item $map[$k] $k -Force }
      }
      Remove-Item $bakDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  } catch {
    Write-Host "Замена значков и названия не удалась ($($_.Exception.Message)); продолжаю без неё."
    if ($map) { foreach ($k in $map.Keys) { try { Copy-Item $map[$k] $k -Force } catch { } } }
  }
}

# ---------- 3b. Иконка и имя самого браузера (необязательно) ----------
$rc = Join-Path $env:TEMP "rcedit-x64.exe"
$bak = Join-Path $env:TEMP "librewolf.exe.bak"
$exeBrowser = Join-Path $here "stage\librewolf.exe"
try {
  if (Get-Exe @("https://github.com/electron/rcedit/releases/latest/download/rcedit-x64.exe") $rc 200KB) {
    Copy-Item $exeBrowser $bak -Force
    & $rc $exeBrowser --set-icon (Join-Path $here "icon.ico") `
      --set-version-string "ProductName" "Dark Crown" `
      --set-version-string "FileDescription" "Dark Crown Browser" `
      --set-version-string "CompanyName" "Dark Crown"
    if ($LASTEXITCODE -ne 0) { throw "rcedit завершился с кодом $LASTEXITCODE" }
    $p = Start-Process $exeBrowser -ArgumentList "--version" -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit(15000)) { try { $p.Kill() } catch { }; throw "браузер не отвечает после замены иконки" }
    if ($p.ExitCode -ne 0) { throw "браузер не запускается после замены иконки" }
    Write-Host "Иконка и имя браузера заменены."
  } else {
    Write-Host "rcedit не скачался: иконка браузера останется прежней (не критично)."
  }
} catch {
  Write-Host "Замена иконки не удалась ($($_.Exception.Message)); возвращаю исходный файл."
  if (Test-Path $bak) { Copy-Item $bak $exeBrowser -Force }
}

# ---------- 4. Установщик ----------
Write-Host "[4/4] Собираю установщик..."
if (Test-Path "dist\DarkCrown-Setup.exe") { Remove-Item "dist\DarkCrown-Setup.exe" -Force }
& $iscc "darkcrown.iss"
if ($LASTEXITCODE -ne 0) { Write-Host "Inno Setup завершился с ошибкой."; exit 1 }

$exe = Join-Path $here "dist\DarkCrown-Setup.exe"
$desktop = [Environment]::GetFolderPath("Desktop")
try {
  if ($desktop -and (Test-Path $desktop)) { Copy-Item $exe (Join-Path $desktop "DarkCrown-Setup.exe") -Force }
} catch { Write-Host "Не удалось скопировать на рабочий стол: $($_.Exception.Message)" }
Write-Host ""
Write-Host "Готово: $exe"
Write-Host "Копия на рабочем столе: $desktop\DarkCrown-Setup.exe"
