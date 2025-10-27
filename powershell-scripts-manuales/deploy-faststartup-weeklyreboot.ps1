<#  deploy-faststartup-weeklyreboot.ps1
    - Desactiva Fast Startup
    - (Opcional) Desactiva hibernacion
    - Crea un checker diario que reinicia si uptime >= MinDias
    - Crea/actualiza una Tarea Programada (SYSTEM) con schtasks
    - Verifica y deja reporte en C:\IT\deploy_status.txt
#>

# --- Auto-elevacion (UAC) ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltinRole] "Administrator")) {
  Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit
}

# --- Parametros editables ---
$HoraDiaria = "19:30"        # Hora local a la que corre el checker cada dia (HH:mm)
$MinDias    = 7              # Dias minimos de uptime para reiniciar
$AvisoSeg   = 300            # Aviso en segundos antes del reinicio (5 min)
$MantenerHibernar = $false   # Si quieres conservar "Hibernar", pon $true

# --- Rutas/constantes ---
$FolderIT   = "C:\IT"
$Checker    = Join-Path $FolderIT "WeeklyRebootCheck.ps1"
$LogPath    = Join-Path $FolderIT "weekly_reboot.log"
$Report     = Join-Path $FolderIT "deploy_status.txt"
$TaskName   = "IT_Reinicio_Semanal_Forzado"

# --- Utilidades ---
function Write-Report($msg) {
  $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  Add-Content -Path $Report -Value "$stamp | $msg"
}

# Limpia/recrea carpeta y reporte
New-Item -Path $FolderIT -ItemType Directory -Force | Out-Null
Remove-Item $Report -Force -ErrorAction SilentlyContinue
New-Item -Path $Report -ItemType File -Force | Out-Null
Write-Report "Inicio de despliegue"

# --- 1) Desactivar Fast Startup ---
$fastOk = $false
try {
  $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
  New-Item -Path $regPath -Force | Out-Null
  Set-ItemProperty -Path $regPath -Name HiberbootEnabled -Type DWord -Value 0
  $val = (Get-ItemProperty -Path $regPath -Name HiberbootEnabled).HiberbootEnabled
  if ($val -eq 0) { $fastOk = $true }
  Write-Report "Fast Startup -> HiberbootEnabled=$val (OK=$fastOk)"
} catch {
  Write-Report "Fast Startup ERROR: $($_.Exception.Message)"
}

# --- 2) Hibernacion (opcional) ---
$hiberOk = $true
if (-not $MantenerHibernar) {
  try {
    & powercfg -h off | Out-Null
    $hiberOk = $LASTEXITCODE -eq 0
    Write-Report "Hibernacion deshabilitada (OK=$hiberOk)"
  } catch {
    $hiberOk = $false
    Write-Report "Hibernacion ERROR: $($_.Exception.Message)"
  }
} else {
  Write-Report "Hibernacion conservada por configuracion (MantenerHibernar=true)"
}

# --- 3) Crear el script checker ---
$checkerOk = $false
try {
  @(
    '# === WeeklyRebootCheck.ps1 ===',
    "param([int]`$MinDias=$MinDias,[int]`$AvisoSeg=$AvisoSeg,[string]`$LogPath=""$LogPath"")",
    'try {',
    '  $now=Get-Date',
    '  $lb=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime',
    '  $uptimeDays=($now-$lb).TotalDays',
    '  $enBateria=$false',
    '  try { $batt=Get-CimInstance Win32_Battery -ErrorAction Stop; if($batt){ if($batt.BatteryStatus -eq 3){$enBateria=$true} } } catch {}',
    '  $linea="{0:yyyy-MM-dd HH:mm:ss} | Uptime={1:n2}d | EnBateria={2} | " -f $now,$uptimeDays,$enBateria',
    '  if($uptimeDays -ge $MinDias -and -not $enBateria){',
    '    Add-Content -Path $LogPath -Value ($linea + "Reinicio programado en $AvisoSeg s")',
    '    shutdown.exe /r /t $AvisoSeg /c "Mantenimiento IT: reinicio automático en $([math]::Round($AvisoSeg/60)) min. Guarda tu trabajo."',
    '  } else {',
    '    Add-Content -Path $LogPath -Value ($linea + "Sin acción")',
    '  }',
    '} catch {',
    '  Add-Content -Path $LogPath -Value ("{0:yyyy-MM-dd HH:mm:ss} | ERROR: {1}" -f (Get-Date), $_.Exception.Message)',
    '}'
  ) | Set-Content -Path $Checker -Encoding UTF8
  if (Test-Path $Checker) { $checkerOk = $true }
  Write-Report "Checker creado en $Checker (OK=$checkerOk)"
} catch {
  Write-Report "Crear checker ERROR: $($_.Exception.Message)"
}

# --- 4) Asegura servicio del Programador ---
$schedOk = $false
try {
  $svc = Get-Service Schedule -ErrorAction Stop
  if ($svc.Status -ne 'Running') { Start-Service Schedule }
  $schedOk = (Get-Service Schedule).Status -eq 'Running'
  Write-Report "Servicio Schedule en ejecucion (OK=$schedOk)"
} catch {
  Write-Report "Servicio Schedule ERROR: $($_.Exception.Message)"
}

# --- 5) Crear/actualizar tarea programada (schtasks, SYSTEM) ---
$taskOk = $false
if ($checkerOk -and $schedOk) {
  try {
    $cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\IT\WeeklyRebootCheck.ps1"'
    # /RL HIGHEST con /RU SYSTEM no es necesario; SYSTEM ya tiene nivel alto
    schtasks /Create /TN "$TaskName" /TR "$cmd" /SC DAILY /ST $HoraDiaria /RU "SYSTEM" /F | Out-Null
    # Verificar
    $q = schtasks /Query /TN "$TaskName" /V /FO LIST 2>$null
    if ($LASTEXITCODE -eq 0 -and $q) { $taskOk = $true }
    Write-Report "Tarea programada '$TaskName' creada/actualizada (OK=$taskOk) Hora=$HoraDiaria"
  } catch {
    Write-Report "Crear tarea ERROR: $($_.Exception.Message)"
  }
} else {
  Write-Report "Se omite tarea: checkerOk=$checkerOk schedOk=$schedOk"
}

# --- 6) Verificacion final ---
#   - Fast Startup: HiberbootEnabled=0
#   - Tarea presente
$verifyReg = $false
$verifyTask = $false
try {
  $val2 = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled).HiberbootEnabled
  $verifyReg = ($val2 -eq 0)
  Write-Report "Verificacion registro: HiberbootEnabled=$val2 (OK=$verifyReg)"
} catch {
  Write-Report "Verificacion registro ERROR: $($_.Exception.Message)"
}
try {
  $q2 = schtasks /Query /TN "$TaskName" /V /FO LIST 2>$null
  $verifyTask = ($LASTEXITCODE -eq 0 -and $q2)
  Write-Report "Verificacion tarea '$TaskName' (OK=$verifyTask)"
} catch {
  Write-Report "Verificacion tarea ERROR: $($_.Exception.Message)"
}

# --- 7) Resultado y salida ---
$overallOk = ($fastOk -and $hiberOk -and $checkerOk -and $schedOk -and $taskOk -and $verifyReg -and $verifyTask)
if ($overallOk) {
  Write-Report "RESULTADO: EXITO"
  Write-Host "[OK] Configuracion aplicada correctamente. Reporte: $Report"
  exit 0
} else {
  Write-Report "RESULTADO: ERROR (revisar pasos anteriores)"
  Write-Host "[ERROR] Hubo problemas. Revisa el reporte: $Report"
  exit 1
}
