param([switch]$AllDrives)

# ---- Auto-elevacion ----
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -AllDrives:$($AllDrives.IsPresent)" -Verb RunAs
    exit
}

# ---- Log ----
$logDir = 'C:\Logs'
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }
$log = Join-Path $logDir 'bitlocker_disable.log'
function Write-Log { param([string]$m)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $log -Value "$ts | $m"
}

Write-Log '============================================================'
Write-Log "Inicio desactivacion BitLocker. AllDrives=$($AllDrives.IsPresent)"

# ---- Unidad del sistema ----
$systemDrive = $env:SystemDrive  # ej. C:
Write-Log "Unidad de sistema: $systemDrive"

# ---- Detectar si existe Get-BitLockerVolume ----
$useCmdlet = $false
try {
    if (Get-Command -Name Get-BitLockerVolume -ErrorAction Stop) { $useCmdlet = $true }
} catch { $useCmdlet = $false }

if ($useCmdlet) {
    Write-Log 'Usando cmdlet Get-BitLockerVolume.'
    try {
        $vols = Get-BitLockerVolume
        if (-not $AllDrives) {
            $vols = $vols | Where-Object { $_.MountPoint -eq $systemDrive }
        }
        $targets = $vols | Where-Object {
            $_.ProtectionStatus -eq 'On' -or $_.VolumeStatus -in @('FullyEncrypted','EncryptionInProgress')
        }
        if ($null -eq $targets -or $targets.Count -eq 0) {
            Write-Log 'No hay unidades cifradas (cmdlet).'
            Write-Host 'No hay unidades cifradas.' -ForegroundColor Green
        } else {
            foreach ($t in $targets) {
                $mp = $t.MountPoint
                Write-Log "Disable-BitLocker en $mp"
                Write-Host "Desactivando BitLocker en $mp" -ForegroundColor Cyan
                Disable-BitLocker -MountPoint $mp -ErrorAction Stop | Out-Null
            }
            Write-Log 'Comandos de desactivacion invocados (cmdlet).'
            Write-Host 'Proceso iniciado. El descifrado puede tardar.' -ForegroundColor Green
        }
    } catch {
        Write-Log ("ERROR con cmdlet: " + $_.Exception.Message)
        Write-Host ("ERROR con cmdlet: " + $_.Exception.Message) -ForegroundColor Red
    }
}
else {
    # Fallback con manage-bde
    Write-Log 'Get-BitLockerVolume no disponible. Usando manage-bde.'
    $letters = @('C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z')
    if (-not $AllDrives) { $letters = @($systemDrive.TrimEnd(':','\')) }  # solo unidad del sistema
    foreach ($L in $letters) {
        $drive = ($L + ':')
        $status = & manage-bde -status $drive 2>$null
        if ($LASTEXITCODE -ne 0) { continue }
        $txt = $status -join "`n"
        if ($txt -match 'Protection Status\s*:\s*On') {
            Write-Host "Desactivando BitLocker en $drive (manage-bde)" -ForegroundColor Cyan
            Write-Log "manage-bde -off $drive"
            & manage-bde -off $drive 2>&1 | ForEach-Object { Write-Log $_ }
        } else {
            Write-Log "No cifrado detectado en $drive (manage-bde)."
        }
    }
    Write-Host 'Comandos manage-bde invocados cuando aplico.' -ForegroundColor Green
    Write-Log 'manage-bde: comandos invocados si aplico.'
}

# ---- Estado final ----
try {
    if ($useCmdlet) {
        $st = Get-BitLockerVolume | Select-Object MountPoint,ProtectionStatus,VolumeStatus,EncryptionPercentage
        Write-Log 'Estado actual (cmdlet):'
        $st | ForEach-Object { Write-Log (($_ | Out-String).Trim()) }
        Write-Host "`nEstado (cmdlet):"
        $st | Format-Table -Auto
    } else {
        $mb = & manage-bde -status 2>&1
        Write-Log 'Estado actual (manage-bde):'
        $mb | ForEach-Object { Write-Log $_ }
        Write-Host "`nEstado (manage-bde):"
        $mb | ForEach-Object { Write-Host $_ }
    }
} catch {
    Write-Log ("ERROR al obtener estado final: " + $_.Exception.Message)
    Write-Host ("ERROR al obtener estado final: " + $_.Exception.Message) -ForegroundColor Red
}

Write-Log 'Fin.'
Write-Log '============================================================'

try { Start-Process notepad.exe -ArgumentList $log } catch { }
Write-Host "`nProceso finalizado. Log en $log"
Read-Host -Prompt 'Presiona Enter para cerrar'
