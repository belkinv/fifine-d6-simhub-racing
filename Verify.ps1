$ErrorActionPreference = 'Stop'

$streamDockRoot = Join-Path $env:APPDATA 'HotSpot\StreamDock'
$pluginRoot = Join-Path $streamDockRoot 'plugins\net.planetrenner.simhub.sdPlugin'
$profilesRoot = Join-Path $streamDockRoot 'profiles'
$profileIds = @(
    '6A5941E2-BB4B-4070-B1A4-17D4D1589F66.sdProfile',
    'MOXDMBR0-263R-2D4X-FN8O-MB4OA3223981.sdProfile',
    'E8D3F36B-B0D3-42CA-AAD5-BBF9A39C8B9F.sdProfile'
)
$errors = @()

$simHub = @(
    Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue
    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue
) |
    Where-Object { $_.DisplayName -match '^SimHub version ' } |
    Select-Object -First 1

if (-not $simHub) {
    $commonDirectories = @(
        (Join-Path ${env:ProgramFiles(x86)} 'SimHub'),
        (Join-Path $env:ProgramFiles 'SimHub')
    ) | Where-Object { $_ }
    foreach ($directory in $commonDirectories) {
        $exe = Join-Path $directory 'SimHubWPF.exe'
        if (Test-Path -LiteralPath $exe -PathType Leaf) {
            $simHub = [pscustomobject]@{
                DisplayVersion = (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion
                InstallLocation = $directory
            }
            break
        }
    }
}
if (-not $simHub) {
    $errors += 'SimHub не найден'
}
else {
    Write-Host "PASS: SimHub установлен, версия $($simHub.DisplayVersion)"
}

$simHubDirectory = if ($simHub -and $simHub.InstallLocation) {
    $simHub.InstallLocation.TrimEnd('\')
}
else {
    Join-Path ${env:ProgramFiles(x86)} 'SimHub'
}
$propertyServer = Join-Path $simHubDirectory 'PropertyServer.dll'
if (-not (Test-Path -LiteralPath $propertyServer)) {
    $errors += 'PropertyServer.dll не найден'
}
elseif ((Get-Item -LiteralPath $propertyServer).VersionInfo.FileVersion -ne '1.16.13.7942') {
    $errors += 'Версия Property Server не равна 1.16.13'
}

$pluginManifestPath = Join-Path $pluginRoot 'manifest.json'
if (-not (Test-Path -LiteralPath $pluginManifestPath)) {
    $errors += 'StreamDeckSimHub для FIFINE не найден'
}
else {
    $pluginManifest = Get-Content -LiteralPath $pluginManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($pluginManifest.Version -ne '2.3.36.23190') {
        $errors += "Неверная версия StreamDeckSimHub: $($pluginManifest.Version)"
    }
}

foreach ($profileId in $profileIds) {
    $profileRoot = Join-Path $profilesRoot $profileId
    $manifestPath = Join-Path $profileRoot 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        $errors += "Не найден профиль $profileId"
        continue
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $pageCount = 1 + @(Get-ChildItem -LiteralPath (Join-Path $profileRoot 'Profiles') -Directory -ErrorAction SilentlyContinue).Count
    if ($pageCount -ne 3) {
        $errors += "$($manifest.Name): найдено $pageCount страниц вместо 3"
    }
    else {
        Write-Host "PASS: $($manifest.Name), 3 страницы"
    }
}

if (Get-Process -Name 'SimHubWPF' -ErrorAction SilentlyContinue) {
    try {
        $client = [Net.Sockets.TcpClient]::new()
        $connect = $client.BeginConnect('127.0.0.1', 18082, $null, $null)
        if (-not $connect.AsyncWaitHandle.WaitOne(1500)) {
            $errors += 'Property Server не отвечает на порту 18082'
        }
        else {
            $client.EndConnect($connect)
            Write-Host 'PASS: Property Server отвечает на порту 18082'
        }
        $client.Dispose()
    }
    catch {
        $errors += "Property Server недоступен: $($_.Exception.Message)"
    }
}
else {
    Write-Warning 'SimHub сейчас не запущен; сетевую проверку Property Server пропускаю.'
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "FAIL: $_" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS: автономный комплект установлен корректно' -ForegroundColor Green
