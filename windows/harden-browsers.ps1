# Dark Crown - усиление безопасности ДРУГИХ браузеров на этом компьютере (необязательно).
# Chrome, Edge, Brave и Firefox: отключает менеджер паролей и автозаполнение, блокирует сторонние куки,
# отключает вход в аккаунт и синхронизацию (через них токены уходят в облако),
# закрывает удалённую отладку, включает только-HTTPS и защиту от утечки адреса через WebRTC.
#
#   harden-browsers.bat            применить
#   harden-browsers.bat blockext   то же + запретить установку новых расширений в Chrome/Edge/Brave
#   harden-browsers.bat undo       снять всё, что поставил этот скрипт
#
# Работает через политики Windows: в Chrome/Edge появится надпись "Управляется вашей организацией".
# Нужны права администратора (скрипт сам попросит).

param(
  [switch]$Undo,
  [switch]$BlockExtensions
)

$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  $argsList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
  if ($Undo) { $argsList += "-Undo" }
  if ($BlockExtensions) { $argsList += "-BlockExtensions" }
  Start-Process powershell -Verb RunAs -ArgumentList $argsList
  exit
}

$chromiumCommon = [ordered]@{
  PasswordManagerEnabled    = 0
  AutofillAddressEnabled    = 0
  AutofillCreditCardEnabled = 0
  BlockThirdPartyCookies    = 1
  SyncDisabled              = 1
  BrowserSignin             = 0
  RemoteDebuggingAllowed    = 0
}

$targets = @(
  @{ Name = "Google Chrome"; Chromium = $true; Path = "HKLM:\SOFTWARE\Policies\Google\Chrome"
     Extra = @{ MetricsReportingEnabled = 0; HttpsOnlyMode = "force_enabled"; WebRtcIPHandling = "default_public_interface_only" } },
  @{ Name = "Microsoft Edge"; Chromium = $true; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
     Extra = @{ DiagnosticData = 0; WebRtcLocalhostIpHandling = "DefaultPublicInterfaceOnly" } },
  @{ Name = "Brave"; Chromium = $true; Path = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"
     Extra = @{ MetricsReportingEnabled = 0; HttpsOnlyMode = "force_enabled"; WebRtcIPHandling = "default_public_interface_only" } },
  @{ Name = "Mozilla Firefox"; Chromium = $false; Path = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
     Extra = @{ PasswordManagerEnabled = 0; OfferToSaveLogins = 0; DisableFirefoxAccounts = 1; DisableProfileImport = 1
                DisableFormHistory = 1; NetworkPrediction = 0; DisableTelemetry = 1; HttpsOnlyMode = "force_enabled"
                AutofillAddressEnabled = 0; AutofillCreditCardEnabled = 0 } }
)

function Remove-IfEmpty($path) {
  if (Test-Path $path) {
    $item = Get-Item $path
    if (($item.ValueCount -eq 0) -and ($item.SubKeyCount -eq 0)) { Remove-Item $path -Force }
  }
}

foreach ($t in $targets) {
  $values = [ordered]@{}
  if ($t.Chromium) { foreach ($k in $chromiumCommon.Keys) { $values[$k] = $chromiumCommon[$k] } }
  foreach ($k in $t.Extra.Keys) { $values[$k] = $t.Extra[$k] }

  if ($Undo) {
    if (-not (Test-Path $t.Path)) { continue }
    foreach ($k in $values.Keys) { Remove-ItemProperty -Path $t.Path -Name $k -ErrorAction SilentlyContinue }
    $blk = Join-Path $t.Path "ExtensionInstallBlocklist"
    if ($t.Chromium -and (Test-Path $blk)) { Remove-Item $blk -Recurse -Force }
    Remove-IfEmpty $t.Path
    Write-Host "$($t.Name): политики сняты."
  } else {
    New-Item -Path $t.Path -Force | Out-Null
    foreach ($k in $values.Keys) {
      $v = $values[$k]
      $type = if ($v -is [string]) { "String" } else { "DWord" }
      New-ItemProperty -Path $t.Path -Name $k -Value $v -PropertyType $type -Force | Out-Null
    }
    if ($BlockExtensions -and $t.Chromium) {
      $blk = Join-Path $t.Path "ExtensionInstallBlocklist"
      New-Item -Path $blk -Force | Out-Null
      New-ItemProperty -Path $blk -Name "1" -Value "*" -PropertyType String -Force | Out-Null
    }
    Write-Host "$($t.Name): политики безопасности применены."
  }
}

Write-Host ""
Write-Host "Готово. Перезапусти браузеры. Проверка: chrome://policy, edge://policy, about:policies."
Read-Host "Нажми Enter, чтобы закрыть"
