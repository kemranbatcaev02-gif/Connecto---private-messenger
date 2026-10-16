# Connecto: собрать всё одной командой
#   powershell -ExecutionPolicy Bypass -File C:\connecto\app\build_all.ps1 -Release
# Результат — в папке C:\connecto\dist:
#   Connecto-Setup.exe — установщик для компьютера
#   Connecto.apk       — приложение для телефона
#   web\               — сайт
# Ключи:
#   -Release   — всё сразу: ПК + APK + сайт, сайт на сервер, APK и установщик на сервер
#                (у всех, у кого Connecto уже стоит, появится «Доступно обновление»)
#   -NoApk / -NoWindows / -NoWeb — пропустить часть
#   -Upload    — залить сайт на сервер,  -Publish — выложить APK и установщик как обновление
#   -Clean     — flutter clean перед сборкой (если сборка странно падает)
# Пароль от сервера спросит два раза (отправка файлов и распаковка).

param([switch]$NoApk, [switch]$NoWindows, [switch]$NoWeb, [switch]$Clean,
      [switch]$Web, [switch]$Upload, [switch]$Publish, [switch]$Release)
if ($Release) { $Web = $true; $Upload = $true; $Publish = $true }
if ($Upload) { $Web = $true }
if ($NoWeb) { $Web = $false; $Upload = $false }
$server = 'root@193.233.112.115'
# версия из pubspec.yaml (version: 1.0.0+7 → 1.0.0 и сборка 7)
$appVersion = '1.0.0'; $appBuild = '0'
$verLine = Select-String -Path (Join-Path $PSScriptRoot 'pubspec.yaml') -Pattern '^version:\s*([0-9.]+)\+([0-9]+)' | Select-Object -First 1
if ($verLine) {
  $appVersion = $verLine.Matches[0].Groups[1].Value
  $appBuild = $verLine.Matches[0].Groups[2].Value
}

$ErrorActionPreference = 'Continue'
$app  = $PSScriptRoot
$dist = Join-Path (Split-Path $app -Parent) 'dist'
Set-Location $app
New-Item -ItemType Directory -Force -Path $dist | Out-Null

function Step($t) { Write-Host ''; Write-Host "==> $t" -ForegroundColor Cyan }
function Fail($t) { Write-Host ''; Write-Host "ОШИБКА: $t" -ForegroundColor Red; exit 1 }

# Java для сборки APK (Gradle). Ищем: JAVA_HOME → Android Studio → установленные JDK.
# Ничего нет — ставим Microsoft OpenJDK 17 через winget (один раз).
function Find-Jdk {
  $cands = @()
  if ($env:JAVA_HOME) { $cands += $env:JAVA_HOME }
  $cands += @(
    "$env:ProgramFiles\Android\Android Studio\jbr",
    "$env:ProgramFiles\Android\Android Studio\jre",
    "$env:LOCALAPPDATA\Programs\Android Studio\jbr",
    "$env:LOCALAPPDATA\Google\AndroidStudio\jbr"
  )
  foreach ($root in @("$env:ProgramFiles\Microsoft", "$env:ProgramFiles\Eclipse Adoptium",
                      "$env:ProgramFiles\Java", "$env:ProgramFiles\Zulu", "$env:ProgramFiles\BellSoft",
                      "$env:LOCALAPPDATA\JetBrains\Toolbox\apps")) {
    if (Test-Path $root) {
      $cands += Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'jdk|jbr|AndroidStudio|android-studio' } |
        Sort-Object Name -Descending | ForEach-Object { $_.FullName; "$($_.FullName)\jbr" }
    }
  }
  foreach ($c in $cands) {
    if (-not $c) { continue }
    # путь без косой черты в конце: «...hotspot\"» в кавычках ломает запуск Gradle
    $c = $c.Trim().Trim('"').TrimEnd('\', '/')
    if (Test-Path (Join-Path $c 'bin\java.exe')) { return $c }
  }
  return $null
}

function Ensure-Java {
  $jdk = Find-Jdk
  if (-not $jdk) {
    Write-Host 'Java (JDK) не найдена — ставлю Microsoft OpenJDK 17 (один раз)...' -ForegroundColor Yellow
    winget install --id Microsoft.OpenJDK.17 -e --accept-source-agreements --accept-package-agreements
    $jdk = Find-Jdk
  }
  if (-not $jdk) { Fail 'не нашла Java. Поставь: winget install Microsoft.OpenJDK.17 — и запусти снова' }
  $jdk = $jdk.TrimEnd('\', '/')
  $env:JAVA_HOME = $jdk
  $env:Path = "$jdk\bin;$env:Path"
  # чтобы и flutter, и Android Studio брали эту же Java (тоже без «\» в конце)
  flutter config --jdk-dir "$jdk" | Out-Null
  # Gradle держит в памяти процесс со старой Java — останавливаем его
  if (Test-Path "$app\android\gradlew.bat") {
    Push-Location "$app\android"; try { .\gradlew --stop | Out-Null } catch {}; Pop-Location
  }
  Write-Host "Java: $jdk" -ForegroundColor DarkGray
}

if ($Clean) {
  Step 'Чищу старую сборку'
  if (-not $NoApk) { Ensure-Java }
  Push-Location android; try { .\gradlew --stop | Out-Null } catch {}; Pop-Location
  flutter clean
}

Step 'Скачиваю зависимости (flutter pub get)'
flutter pub get
if ($LASTEXITCODE -ne 0) { Fail 'flutter pub get не прошёл' }

if (-not $NoWindows) {
  Get-Process Connecto -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

  Step 'Собираю версию для компьютера (несколько минут)'
  flutter build windows --release --dart-define=APP_BUILD=$appBuild
  if ($LASTEXITCODE -ne 0) { Fail 'сборка Windows не прошла — пришли вывод выше' }

  Step 'Делаю установщик'
  $iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $iscc) {
    Write-Host 'Inno Setup не найден — ставлю (один раз)...' -ForegroundColor Yellow
    winget install --id JRSoftware.InnoSetup -e --accept-source-agreements --accept-package-agreements
    $iscc = @(
      "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
      "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
      "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
  }
  if (-not $iscc) { Fail 'не получилось поставить Inno Setup: winget install JRSoftware.InnoSetup' }
  # 64-битный Visual C++ runtime рядом с Connecto.exe (иначе на чистом ПК не запустится)
  $sys = if ([Environment]::Is64BitProcess) { "$env:WINDIR\System32" } else { "$env:WINDIR\Sysnative" }
  $vcrt = Join-Path $app 'build\vcrt'
  New-Item -ItemType Directory -Force -Path $vcrt | Out-Null
  foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    if (Test-Path "$sys\$dll") { Copy-Item "$sys\$dll" $vcrt -Force }
    else { Write-Host "Нет $dll — поставь Visual C++ Redistributable x64" -ForegroundColor Yellow }
  }
  & $iscc /Q "/DMyAppVersion=$appVersion" "$app\installer\connecto.iss"
  if ($LASTEXITCODE -ne 0) { Fail 'Inno Setup не собрал установщик' }
  Copy-Item "$app\build\installer\Connecto-Setup.exe" "$dist\Connecto-Setup.exe" -Force
  Write-Host "Готово: $dist\Connecto-Setup.exe" -ForegroundColor Green
}

if (-not $NoApk) {
  Step 'Собираю приложение для телефона (APK)'
  Ensure-Java
  flutter build apk --release --target-platform android-arm64 --dart-define=APP_BUILD=$appBuild
  if ($LASTEXITCODE -ne 0) { Fail 'сборка APK не прошла — попробуй с ключом -Clean' }
  Copy-Item "$app\build\app\outputs\flutter-apk\app-release.apk" "$dist\Connecto.apk" -Force
  Write-Host "Готово: $dist\Connecto.apk" -ForegroundColor Green
}

if ($Web) {
  Step 'Собираю веб-версию (сайт)'
  # --no-web-resources-cdn: движок кладём рядом с сайтом, а не грузим с серверов Google
  flutter build web --release --no-web-resources-cdn --dart-define=APP_BUILD=$appBuild
  if ($LASTEXITCODE -ne 0) { Fail 'сборка сайта не прошла — пришли вывод выше' }
  $webOut = Join-Path $dist 'web'
  if (Test-Path $webOut) { Remove-Item $webOut -Recurse -Force }
  Copy-Item "$app\build\web" $webOut -Recurse -Force
  Write-Host "Готово: $webOut" -ForegroundColor Green

}

# ── на сервер: одним scp и одним ssh (пароль — два раза) ──
$send = @()
$remote = @()
if ($Upload) {
  $tgz = Join-Path $dist 'web.tgz'
  tar -czf $tgz -C "$app\build\web" .
  if ($LASTEXITCODE -ne 0) { Fail 'не получилось упаковать сайт (tar)' }
  $send += $tgz
  $remote += 'mkdir -p /opt/connecto-web && rm -rf /opt/connecto-web/* && tar -xzf /tmp/web.tgz -C /opt/connecto-web && rm -f /tmp/web.tgz && echo SITE-OK'
}
if ($Publish) {
  $flags = ''
  if (-not $NoApk) { $send += "$dist\Connecto.apk"; $flags += ' --apk' }
  if (-not $NoWindows) { $send += "$dist\Connecto-Setup.exe"; $flags += ' --exe' }
  if ($flags) {
    $remote += "mkdir -p /opt/connecto-server/downloads && for f in Connecto.apk Connecto-Setup.exe; do if [ -f /tmp/`$f ]; then mv -f /tmp/`$f /opt/connecto-server/downloads/; fi; done; python3 /opt/connecto-server/publish_release.py --version $appVersion --build $appBuild$flags"
  }
}
if ($send.Count -gt 0) {
  Step 'Отправляю на сервер (спросит пароль от сервера)'
  scp $send "${server}:/tmp/"
  if ($LASTEXITCODE -ne 0) { Fail 'не получилось отправить файлы на сервер (scp)' }
  Step 'Раскладываю на сервере (ещё раз пароль)'
  ssh $server ($remote -join ' && ')
  if ($LASTEXITCODE -ne 0) { Fail 'сервер не разложил файлы — пришли вывод выше' }
  if ($Upload) { Remove-Item (Join-Path $dist 'web.tgz') -Force -ErrorAction SilentlyContinue }
  Write-Host 'Сервер обновлён.' -ForegroundColor Green
  if ($Upload) { Write-Host 'Сайт: https://connectomes.duckdns.org (Ctrl+F5, если видна старая версия)' -ForegroundColor Green }
}

Write-Host ''
Write-Host "Всё собрано! Версия $appVersion, сборка $appBuild." -ForegroundColor Green
if (-not $Publish) {
  Write-Host 'Выложить обновление: Админ-панель → Обновления → «Выложить новую» (файлы — в папке dist).' -ForegroundColor Green
  Write-Host "Номер сборки там укажи $appBuild. Для следующей версии подними +N в pubspec.yaml." -ForegroundColor DarkGray
}
Write-Host 'Открываю папку dist.' -ForegroundColor Green
explorer $dist
