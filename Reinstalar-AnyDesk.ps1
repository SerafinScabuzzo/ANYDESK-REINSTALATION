#Requires -RunAsAdministrator
$ErrorActionPreference = 'Continue'
try { cmd /c "chcp 65001 >nul" } catch {}
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir = Join-Path ${env:ProgramFiles(x86)} 'AnyDesk'
$Desktop = [Environment]::GetFolderPath('Desktop')
$ResultadoTxt = Join-Path $Desktop 'AnyDesk-acceso.txt'

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host ("==> " + $Message)
}

function Read-PlainPassword([string]$Prompt) {
    $secure = Read-Host $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Stop-AnyDesk {
    Get-Process -Name 'AnyDesk' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $svc = Get-Service -Name 'AnyDesk' -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Stopped') {
        try { Stop-Service -Name 'AnyDesk' -Force -ErrorAction Stop } catch {}
        & sc.exe stop AnyDesk | Out-Null
    }
    $deadline = (Get-Date).AddSeconds(20)
    do {
        $left = @(Get-Process -Name 'AnyDesk' -ErrorAction SilentlyContinue)
        if ($left.Count -eq 0) { return }
        $left | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
}

function Remove-Tree([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    for ($i = 1; $i -le 5; $i++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        } catch {
            Stop-AnyDesk
            Start-Sleep -Seconds 2
        }
        if (-not (Test-Path -LiteralPath $Path)) { return $true }
    }
    return $false
}

function Get-AnyDeskExe {
    $candidates = @(
        (Join-Path $InstallDir 'AnyDesk.exe'),
        (Join-Path $env:ProgramFiles 'AnyDesk\AnyDesk.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

function Get-AnyDeskIdFromConf {
    $files = @(
        (Join-Path $env:ProgramData 'AnyDesk\system.conf'),
        (Join-Path $env:APPDATA 'AnyDesk\system.conf')
    )
    foreach ($file in $files) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $match = Select-String -LiteralPath $file -Pattern '^ad\.anynet\.id=(\d{5,})' | Select-Object -First 1
        if ($match) {
            $id = $match.Matches[0].Groups[1].Value
            if ($id -and $id -ne '0') { return $id }
        }
    }
    return $null
}

function Get-AnyDeskIdFromCli([string]$Exe) {
    if (-not $Exe) { return $null }
    $output = & $Exe --get-id 2>&1 | Out-String
    $match = [regex]::Match($output, '\d{9,}')
    if ($match.Success) { return $match.Value }
    return $null
}

function Test-PasswordSaved {
    $serviceConf = Join-Path $env:ProgramData 'AnyDesk\service.conf'
    $systemConf = Join-Path $env:ProgramData 'AnyDesk\system.conf'
    foreach ($file in @($serviceConf, $systemConf)) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $hit = Select-String -LiteralPath $file -Pattern 'pwd_hash=.+|unattended_access\.pwd=.+' | Select-Object -First 1
        if ($hit) { return $true }
    }
    return $false
}

function Set-AnyDeskPassword([string]$Exe, [string]$Password) {
    $tmp = Join-Path $env:TEMP ("adpw-" + [guid]::NewGuid().ToString("N"))
    try {
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($Password + "`r`n")
        [System.IO.File]::WriteAllBytes($tmp, $bytes)
        $proc = Start-Process -FilePath $Exe -ArgumentList '--set-password' -RedirectStandardInput $tmp -Wait -PassThru -WindowStyle Hidden
        if (-not $proc) { return $false }
    } catch {
        return $false
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Seconds 2
    return (Test-PasswordSaved)
}

Write-Host ""
Write-Host "Reinstalacion completa de AnyDesk"
Write-Host "Se cierra el programa, se borra toda la configuracion guardada,"
Write-Host "se instala de nuevo y se aplica la contrasena que escribas."
Write-Host "Al terminar queda abierto y se crea el archivo:"
Write-Host $ResultadoTxt
Write-Host ""
Write-Host "El codigo de esta PC va a cambiar. El codigo anterior deja de servir."
Write-Host ""

$installer = Get-ChildItem -LiteralPath $ScriptDir -Filter '*.exe' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'AnyDesk*' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $installer) {
    Write-Host "No encontre AnyDesk.exe en esta carpeta:"
    Write-Host $ScriptDir
    Write-Host "Deja el instalador junto a este programa y volve a ejecutarlo."
    exit 2
}

Write-Host ("Instalador: " + $installer.FullName)
Write-Host ""

$password = $null
do {
    $password = Read-PlainPassword "Contrasena nueva para AnyDesk"
    $repeat = Read-PlainPassword "Repeti la contrasena"
    if ([string]::IsNullOrWhiteSpace($password)) {
        Write-Host "La contrasena no puede estar vacia."
        $password = $null
        continue
    }
    if ($password -ne $repeat) {
        Write-Host "Las contrasenas no coinciden."
        $password = $null
        continue
    }
    if ($password.Length -lt 8) {
        Write-Host "Usa al menos 8 caracteres."
        $password = $null
        continue
    }
    if ($password -notmatch '^[\x20-\x7E]+$') {
        Write-Host "Usa letras, numeros y simbolos simples. Sin eñe ni acentos."
        $password = $null
    }
} while (-not $password)

$oldId = Get-AnyDeskIdFromConf
if ($oldId) {
    Write-Host ""
    Write-Host ("Codigo actual, se va a borrar: " + $oldId)
}

Write-Host ""
$go = Read-Host "Escribi S para desinstalar e instalar de nuevo"
if ($go -notmatch '^[sS]$') {
    Write-Host "Cancelado. AnyDesk no se modifico."
    exit 1
}

Write-Step "Cerrando AnyDesk"
Stop-AnyDesk

$installedExe = Get-AnyDeskExe
if ($installedExe) {
    Write-Step "Desinstalando"
    $un = Start-Process -FilePath $installedExe -ArgumentList @('--silent', '--uninstall') -PassThru
    if (-not $un.WaitForExit(90000)) {
        Write-Host "La desinstalacion tardo demasiado. Sigo borrando los archivos que queden."
        try { $un.Kill() } catch {}
    }
    Start-Sleep -Seconds 2
    Stop-AnyDesk
    if (Test-Path -LiteralPath $installedExe) {
        $un2 = Start-Process -FilePath $installedExe -ArgumentList @('--silent', '--remove') -PassThru
        if (-not $un2.WaitForExit(90000)) {
            try { $un2.Kill() } catch {}
        }
        Start-Sleep -Seconds 2
        Stop-AnyDesk
    }
}

Write-Step "Borrando configuracion, historial e ID"
$targets = @(
    (Join-Path $env:ProgramData 'AnyDesk'),
    $InstallDir,
    (Join-Path $env:ProgramFiles 'AnyDesk')
)
Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $targets += (Join-Path $_.FullName 'AppData\Roaming\AnyDesk')
    $targets += (Join-Path $_.FullName 'AppData\Local\AnyDesk')
}

$pending = @()
foreach ($target in ($targets | Select-Object -Unique)) {
    if (Test-Path -LiteralPath $target) {
        Write-Host ("Borrando " + $target)
        if (-not (Remove-Tree $target)) {
            $pending += $target
        }
    }
}

$regKeys = @(
    'HKLM:\SOFTWARE\AnyDesk',
    'HKLM:\SOFTWARE\WOW6432Node\AnyDesk',
    'HKCU:\SOFTWARE\AnyDesk'
)
foreach ($key in $regKeys) {
    if (Test-Path $key) {
        Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
)
foreach ($root in $uninstallRoots) {
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($props.DisplayName -eq 'AnyDesk') {
            Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$svcLeft = Get-Service -Name 'AnyDesk' -ErrorAction SilentlyContinue
if ($svcLeft) {
    Stop-AnyDesk
    & sc.exe delete AnyDesk | Out-Null
    Start-Sleep -Seconds 2
    $query = (& sc.exe query AnyDesk 2>&1 | Out-String)
    if ($query -match 'marcado para elimin|marked for deletion') {
        Write-Host "Windows dejo el servicio a medias. Reinicia la PC y ejecuta este programa otra vez."
        exit 3
    }
}

if ($pending.Count -gt 0) {
    Write-Host ""
    Write-Host "No pude borrar estas carpetas. Cierra AnyDesk, reinicia la PC y ejecuta este programa otra vez:"
    $pending | ForEach-Object { Write-Host $_ }
    exit 3
}

Write-Step "Instalando AnyDesk"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $installer.FullName
$psi.Arguments = "--install `"$InstallDir`" --start-with-win --silent --create-shortcuts --create-desktop-icon"
$psi.UseShellExecute = $true
$setup = [System.Diagnostics.Process]::Start($psi)
if (-not $setup.WaitForExit(180000)) {
    Write-Host "La instalacion no termino. Revisa si quedo una ventana de AnyDesk."
    exit 3
}
if ($setup.ExitCode -ne 0) {
    Write-Host ("El instalador termino con codigo " + $setup.ExitCode)
}

$installedExe = $null
$deadline = (Get-Date).AddSeconds(60)
do {
    $installedExe = Get-AnyDeskExe
    if ($installedExe) { break }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

if (-not $installedExe) {
    Write-Host "No quedo instalado AnyDesk.exe. La reinstalacion no se completo."
    exit 3
}

Write-Step "Iniciando el servicio"
$deadline = (Get-Date).AddSeconds(60)
$serviceReady = $false
do {
    $svc = Get-Service -Name 'AnyDesk' -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        $serviceReady = $true
        break
    }
    if ($svc -and $svc.Status -eq 'Stopped') {
        try { Start-Service -Name 'AnyDesk' -ErrorAction Stop } catch {}
    }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

if (-not $serviceReady) {
    Write-Host "El servicio no arranco. Sigo con la configuracion de la ventana."
}

Write-Step "Aplicando la contrasena"
$passwordOk = $false
for ($i = 1; $i -le 3; $i++) {
    if (Set-AnyDeskPassword $installedExe $password) {
        $passwordOk = $true
        break
    }
    Start-Sleep -Seconds 3
}

if ($passwordOk) {
    Write-Host "Contrasena aplicada."
} else {
    Write-Host "No pude confirmar que la contrasena quedo guardada."
    Write-Host "Cuando se abra AnyDesk, entrala en Seguridad, Acceso desatendido."
}

Write-Step "Abriendo AnyDesk y esperando el codigo nuevo"
Start-Process -FilePath $installedExe | Out-Null

$newId = $null
$deadline = (Get-Date).AddSeconds(120)
do {
    $newId = Get-AnyDeskIdFromConf
    if ($newId) { break }
    Write-Host "Esperando el codigo de vinculacion..."
    Start-Sleep -Seconds 4
} while ((Get-Date) -lt $deadline)

if (-not $newId) {
    $newId = Get-AnyDeskIdFromCli $installedExe
}

$fecha = Get-Date -Format 'yyyy-MM-dd HH:mm'
$lineas = New-Object System.Collections.Generic.List[string]
$lineas.Add('AnyDesk')
$lineas.Add('Fecha: ' + $fecha)
if ($newId) {
    $lineas.Add('Codigo de vinculacion: ' + $newId)
} else {
    $lineas.Add('Codigo de vinculacion: todavia no aparecio. Miralo en la ventana de AnyDesk.')
}
$lineas.Add('Contrasena: ' + $password)
if (-not $passwordOk) {
    $lineas.Add('Aviso: no se pudo confirmar la contrasena dentro de AnyDesk.')
}
$utf8 = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllLines($ResultadoTxt, $lineas.ToArray(), $utf8)

Write-Host ""
Write-Host "Listo."
Write-Host ("Archivo: " + $ResultadoTxt)
if ($newId) {
    Write-Host ("Codigo de vinculacion: " + $newId)
    if ($oldId -and $newId -eq $oldId) {
        Write-Host "Ese codigo es el mismo que el anterior."
    }
} else {
    Write-Host "AnyDesk quedo abierto, pero el codigo nuevo todavia no aparecio."
    Write-Host "Cuando se vea en la ventana, copia ese numero al txt del escritorio."
}
if (-not $passwordOk) { exit 4 }
if (-not $newId) { exit 5 }
exit 0
