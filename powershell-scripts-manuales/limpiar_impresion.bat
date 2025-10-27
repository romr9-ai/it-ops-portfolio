@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ================== Auto-elevación (UAC) ==================
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Solicitando permisos de administrador...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

:: ================== Configuración ==================
set "LOGDIR=C:\Logs"
set "LOG=%LOGDIR%\spool_fix.log"
set "SPOOL=%systemroot%\System32\spool\PRINTERS"

if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1

echo ============================================================>>"%LOG%"
echo [%date% %time%] Inicio limpieza de cola de impresion        >>"%LOG%"
echo.                                                           >>"%LOG%"

echo Reiniciando cola de impresion...

:: 1) Detener Spooler
sc query spooler | find /I "RUNNING" >nul
if %errorlevel%==0 (
  echo Deteniendo servicio "Cola de impresion"...
  net stop spooler /y >>"%LOG%" 2>&1
) else (
  echo El servicio Spooler ya estaba detenido.
  echo Spooler ya detenido                                       >>"%LOG%"
)

:: 2) Limpiar carpeta de trabajos
echo Limpiando archivos en: "%SPOOL%"
if exist "%SPOOL%" (
  del /Q /F "%SPOOL%\*.*" >>"%LOG%" 2>&1
) else (
  echo Carpeta no encontrada: "%SPOOL%"                           >>"%LOG%"
)

:: 3) Iniciar Spooler
echo Iniciando servicio "Cola de impresion"...
net start spooler >>"%LOG%" 2>&1

:: 4) Verificacion
sc query spooler | find /I "RUNNING" >nul
if %errorlevel%==0 (
  echo ✅ Listo: cola limpia y servicio en ejecucion.
  echo [%date% %time%] OK - Spooler en ejecucion                 >>"%LOG%"
  set "RESULT=OK"
) else (
  echo ❌ Error al iniciar el servicio Spooler. Revisa el log.
  echo [%date% %time%] ERROR - Spooler no inicio                 >>"%LOG%"
  set "RESULT=ERROR"
)

echo.
echo Se guardo un log en: %LOG%

:: Ventana emergente informativa
powershell -NoProfile -Command "Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('Resultado: %RESULT%`nLog: %LOG%','Limpieza de cola de impresion',[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Information)" >nul 2>&1

timeout /t 2 >nul
endlocal
