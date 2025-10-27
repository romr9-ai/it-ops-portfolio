$txt = (powercfg /a | Out-String)
$hibernationDisabled = ($txt -match '(?i)Hibernation has not been enabled') -or
                       ($txt -match '(?i)Hibernation is not available') -or
                       ($txt -match '(?i)Hibernate\s*:\s*Not available') -or
                       ($txt -match '(?i)Hibernaci[oó]n\s*:\s*no disponible') -or
                       ($txt -match '(?i)hibernaci[oó]n.*no\s+ha\s+sido\s+habilitada')

$fs = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled).HiberbootEnabled
$taskOut = schtasks /Query /TN "IT_Reinicio_Semanal_Forzado" /FO LIST 2>$null
$taskExists = ($LASTEXITCODE -eq 0 -and $taskOut)
$logExists = Test-Path "C:\IT\weekly_reboot.log"

[PSCustomObject]@{
  FastStartup_Off      = ($fs -eq 0)
  Task_Exists          = $taskExists
  Hibernation_Disabled = $hibernationDisabled
  Log_Exists           = $logExists
}
