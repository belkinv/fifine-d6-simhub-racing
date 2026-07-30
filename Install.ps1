param(
    [switch]$NoStart
)

$ErrorActionPreference = 'Stop'
$profileIds = @(
    '6A5941E2-BB4B-4070-B1A4-17D4D1589F66.sdProfile',
    'MOXDMBR0-263R-2D4X-FN8O-MB4OA3223981.sdProfile',
    'E8D3F36B-B0D3-42CA-AAD5-BBF9A39C8B9F.sdProfile'
)

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`""
    )
    if ($NoStart) { $arguments += '-NoStart' }
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList ($arguments -join ' ') -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
}

$packageRoot = Split-Path -Parent $PSCommandPath
$payloadRoot = Join-Path $packageRoot 'Payload'
$propertyServerSource = Join-Path $payloadRoot 'Installers\PropertyServer.dll'
$pluginSource = Join-Path $payloadRoot 'StreamDockPlugins\net.planetrenner.simhub.sdPlugin'
$profilesSource = Join-Path $payloadRoot 'Profiles'
$checksumsPath = Join-Path $packageRoot 'payload-checksums.json'
$logPath = Join-Path $env:TEMP ("FIFINE-D6-install-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

Start-Transcript -LiteralPath $logPath | Out-Null
try {
    Write-Host 'FIFINE D6 / D6-Pro: установка плагина и сцен для SimHub' -ForegroundColor Cyan
    Write-Host "Журнал: $logPath"

    foreach ($requiredPath in @($propertyServerSource, $pluginSource, $profilesSource, $checksumsPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "В пакете отсутствует обязательный файл: $requiredPath"
        }
    }

    Write-Host 'Проверка целостности пакета...'
    $checksumEntries = Get-Content -LiteralPath $checksumsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in $checksumEntries) {
        $filePath = Join-Path $packageRoot $entry.Path
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            throw "Не найден файл пакета: $($entry.Path)"
        }
        $actualHash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
        if ($actualHash -ne $entry.Sha256) {
            throw "Контрольная сумма не совпала: $($entry.Path)"
        }
    }
    Write-Host '  OK'

    $controlDeckCandidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'fifine Control Deck\fifine Control Deck.exe'),
        (Join-Path $env:ProgramFiles 'fifine Control Deck\fifine Control Deck.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    $controlDeckExe = $controlDeckCandidates | Select-Object -First 1
    if (-not $controlDeckExe) {
        throw 'Не найдено приложение FIFINE Control Deck. Установите его и один раз подключите D6/D6-Pro.'
    }

    $streamDockRoot = Join-Path $env:APPDATA 'HotSpot\StreamDock'
    if (-not (Test-Path -LiteralPath $streamDockRoot)) {
        Write-Host 'Первый запуск FIFINE Control Deck...'
        Start-Process -FilePath $controlDeckExe
        Start-Sleep -Seconds 8
        Get-Process | Where-Object { $_.ProcessName -eq 'fifine Control Deck' } | Stop-Process -Force
    }
    if (-not (Test-Path -LiteralPath $streamDockRoot)) {
        throw "FIFINE Control Deck не создал папку настроек: $streamDockRoot"
    }

    function Get-SimHubInstall {
        $registryRoots = @(
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        foreach ($root in $registryRoots) {
            $item = Get-ItemProperty $root -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match '^SimHub version ' } |
                Sort-Object { try { [version]$_.DisplayVersion } catch { [version]'0.0' } } -Descending |
                Select-Object -First 1
            if ($item) { return $item }
        }

        $commonDirectories = @(
            (Join-Path ${env:ProgramFiles(x86)} 'SimHub'),
            (Join-Path $env:ProgramFiles 'SimHub')
        ) | Where-Object { $_ }
        foreach ($directory in $commonDirectories) {
            $exe = Join-Path $directory 'SimHubWPF.exe'
            if (Test-Path -LiteralPath $exe -PathType Leaf) {
                $fileVersion = (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion
                return [pscustomobject]@{
                    DisplayName = 'SimHub (обнаружен по файлу)'
                    DisplayVersion = if ($fileVersion) { $fileVersion } else { 'не определена' }
                    InstallLocation = $directory
                }
            }
        }
        $null
    }

    $installed = Get-SimHubInstall
    if (-not $installed) {
        throw 'SimHub не найден. Сначала установите SimHub с официального сайта https://www.simhubdash.com/, затем снова запустите Install.cmd.'
    }
    Write-Host "SimHub обнаружен (версия $($installed.DisplayVersion)). Программа не переустанавливается и не обновляется."

    $simHubDirectory = if ($installed -and $installed.InstallLocation) {
        $installed.InstallLocation.TrimEnd('\')
    }
    else {
        Join-Path ${env:ProgramFiles(x86)} 'SimHub'
    }
    $simHubExe = Join-Path $simHubDirectory 'SimHubWPF.exe'
    if (-not (Test-Path -LiteralPath $simHubExe)) {
        throw "Не найден исполняемый файл SimHub: $simHubExe"
    }

    Write-Host 'Остановка программ перед копированием...'
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -in @('fifine Control Deck', 'StreamDeckSimHub', 'SimHubWPF') } |
        Stop-Process -Force
    Start-Sleep -Seconds 2

    $documents = [Environment]::GetFolderPath('MyDocuments')
    $backupRoot = Join-Path $documents ("FIFINE-D6-Backup\{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    $pluginsRoot = Join-Path $streamDockRoot 'plugins'
    $profilesRoot = Join-Path $streamDockRoot 'profiles'
    New-Item -ItemType Directory -Path $pluginsRoot, $profilesRoot -Force | Out-Null
    $pluginTarget = Join-Path $pluginsRoot 'net.planetrenner.simhub.sdPlugin'

    if (Test-Path -LiteralPath $pluginTarget) {
        Copy-Item -LiteralPath $pluginTarget -Destination $backupRoot -Recurse -Force
    }
    foreach ($profileId in $profileIds) {
        $target = Join-Path $profilesRoot $profileId
        if (Test-Path -LiteralPath $target) {
            Copy-Item -LiteralPath $target -Destination $backupRoot -Recurse -Force
        }
    }
    $propertyServerTarget = Join-Path $simHubDirectory 'PropertyServer.dll'
    if (Test-Path -LiteralPath $propertyServerTarget) {
        Copy-Item -LiteralPath $propertyServerTarget -Destination $backupRoot -Force
    }

    [pscustomobject]@{
        Created = (Get-Date).ToString('o')
        Computer = $env:COMPUTERNAME
        User = $env:USERNAME
        StreamDockRoot = $streamDockRoot
        SimHubDirectory = $simHubDirectory
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backupRoot 'backup-info.json') -Encoding UTF8

    function Remove-ScopedDirectory {
        param([string]$Target, [string]$AllowedParent)
        $targetFull = [IO.Path]::GetFullPath($Target).TrimEnd('\')
        $parentFull = [IO.Path]::GetFullPath($AllowedParent).TrimEnd('\') + '\'
        if (-not $targetFull.StartsWith($parentFull, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Отказ от удаления пути вне разрешённой папки: $targetFull"
        }
        if (Test-Path -LiteralPath $targetFull) {
            Remove-Item -LiteralPath $targetFull -Recurse -Force
        }
    }

    Write-Host 'Установка StreamDeckSimHub и Property Server...'
    Remove-ScopedDirectory -Target $pluginTarget -AllowedParent $pluginsRoot
    Copy-Item -LiteralPath $pluginSource -Destination $pluginsRoot -Recurse -Force
    Copy-Item -LiteralPath $propertyServerSource -Destination $propertyServerTarget -Force

    Write-Host 'Установка сцен Le Mans Ultimate, ACC и Assetto Corsa EVO...'
    foreach ($profileId in $profileIds) {
        $source = Join-Path $profilesSource $profileId
        $target = Join-Path $profilesRoot $profileId
        Remove-ScopedDirectory -Target $target -AllowedParent $profilesRoot
        Copy-Item -LiteralPath $source -Destination $profilesRoot -Recurse -Force
    }

    function Get-SteamLibraries {
        $steamRoots = @(
            (Join-Path ${env:ProgramFiles(x86)} 'Steam'),
            (Join-Path $env:ProgramFiles 'Steam')
        ) | Where-Object { $_ }
        $libraries = [Collections.Generic.List[string]]::new()
        foreach ($steamRoot in $steamRoots) {
            if (Test-Path -LiteralPath $steamRoot) {
                $libraries.Add($steamRoot)
                $vdf = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
                if (Test-Path -LiteralPath $vdf) {
                    $text = Get-Content -LiteralPath $vdf -Raw
                    foreach ($match in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
                        $libraries.Add($match.Groups[1].Value.Replace('\\', '\'))
                    }
                }
            }
        }
        $libraries | Select-Object -Unique
    }

    $gameDefinitions = @(
        [pscustomobject]@{
            ProfileId = '6A5941E2-BB4B-4070-B1A4-17D4D1589F66.sdProfile'
            RelativeExe = 'steamapps\common\Le Mans Ultimate\Le Mans Ultimate.exe'
            Name = 'Le Mans Ultimate'
        },
        [pscustomobject]@{
            ProfileId = 'MOXDMBR0-263R-2D4X-FN8O-MB4OA3223981.sdProfile'
            RelativeExe = 'steamapps\common\Assetto Corsa Competizione\AC2\Binaries\Win64\AC2-Win64-Shipping.exe'
            Name = 'Assetto Corsa Competizione'
        },
        [pscustomobject]@{
            ProfileId = 'E8D3F36B-B0D3-42CA-AAD5-BBF9A39C8B9F.sdProfile'
            RelativeExe = 'steamapps\common\Assetto Corsa EVO\AssettoCorsaEVO.exe'
            Name = 'Assetto Corsa EVO'
        }
    )

    $steamLibraries = @(Get-SteamLibraries)
    foreach ($game in $gameDefinitions) {
        $detectedExe = $steamLibraries |
            ForEach-Object { Join-Path $_ $game.RelativeExe } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if ($detectedExe) {
            $manifestPath = Join-Path (Join-Path $profilesRoot $game.ProfileId) 'manifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $manifest.AppIdentifier = $detectedExe
            $json = $manifest | ConvertTo-Json -Depth 100
            [IO.File]::WriteAllText($manifestPath, $json, [Text.UTF8Encoding]::new($false))
            Write-Host "  Путь $($game.Name): $detectedExe"
        }
        else {
            Write-Warning "Игра $($game.Name) не найдена. Сцена установлена, но автоматическое переключение потребует указать путь к игре."
        }
    }

    Write-Host 'Проверка установленных файлов...'
    $pluginManifest = Get-Content -LiteralPath (Join-Path $pluginTarget 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($pluginManifest.Version -ne '2.3.36.23190') {
        throw "Неверная версия StreamDeckSimHub: $($pluginManifest.Version)"
    }
    if ((Get-Item -LiteralPath $propertyServerTarget).VersionInfo.FileVersion -ne '1.16.13.7942') {
        throw 'Неверная версия Property Server.'
    }
    foreach ($profileId in $profileIds) {
        $profilePath = Join-Path $profilesRoot $profileId
        $pageCount = 1 + @(Get-ChildItem -LiteralPath (Join-Path $profilePath 'Profiles') -Directory -ErrorAction SilentlyContinue).Count
        if ($pageCount -ne 3) {
            throw "Профиль $profileId содержит $pageCount страниц вместо 3."
        }
    }

    if (-not $NoStart) {
        Write-Host 'Запуск SimHub и FIFINE Control Deck...'
        Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$simHubExe`""
        Start-Sleep -Seconds 10
        Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$controlDeckExe`""
        Start-Sleep -Seconds 8
    }

    Write-Host ''
    Write-Host 'УСТАНОВКА ЗАВЕРШЕНА' -ForegroundColor Green
    Write-Host 'Сцены: Le Mans Ultimate, Assetto Corsa Competizione и Assetto Corsa EVO (по 3 страницы)'
    Write-Host 'StreamDeckSimHub: 2.3.36; Property Server: 1.16.13'
    Write-Host "Резервная копия прежних настроек: $backupRoot"
    Write-Host "Журнал установки: $logPath"
}
catch {
    Write-Host ''
    Write-Host "ОШИБКА: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Подробности сохранены в журнале: $logPath"
    exit 1
}
finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
