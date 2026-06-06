@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "BACKEND_PORT=18080"
set "WEB_PORT=13000"
set "RUNTIME_DIR=%TEMP%\infinite-canvas-runtime"
set "BACKEND_PID_FILE=%RUNTIME_DIR%\backend.pid"
set "WEB_PID_FILE=%RUNTIME_DIR%\web.pid"

echo [infinite-canvas] Stop services
echo.

call :stop_pid_file "%WEB_PID_FILE%" "web"
call :stop_pid_file "%BACKEND_PID_FILE%" "backend"

echo.
echo [INFO] Checking remaining listeners...
call :stop_port_if_needed %WEB_PORT% "web"
call :stop_port_if_needed %BACKEND_PORT% "backend"

echo.
echo [INFO] Stop command finished.
if /I not "%STOP_NO_PAUSE%"=="1" pause
exit /b 0

:stop_pid_file
set "PID_FILE=%~1"
set "NAME=%~2"
if not exist "%PID_FILE%" (
    echo [INFO] No %NAME% PID file.
    exit /b 0
)

set "PID="
set /p PID=<"%PID_FILE%"
if not defined PID (
    del "%PID_FILE%" >nul 2>nul
    echo [INFO] Removed empty %NAME% PID file.
    exit /b 0
)

powershell -NoProfile -Command "if(Get-Process -Id %PID% -ErrorAction SilentlyContinue){ exit 0 } exit 1" >nul 2>nul
if errorlevel 1 (
    del "%PID_FILE%" >nul 2>nul
    echo [INFO] Removed stale %NAME% PID file. PID: %PID%
    exit /b 0
)

echo [INFO] Stopping %NAME%. PID: %PID%
taskkill /PID %PID% /T /F >nul 2>nul
if errorlevel 1 (
    echo [WARN] Failed to stop %NAME% PID %PID%.
    exit /b 1
)

del "%PID_FILE%" >nul 2>nul
exit /b 0

:stop_port_if_needed
set "PORT=%~1"
set "NAME=%~2"
set "LISTENER_PID="
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":%PORT% .*LISTENING"') do (
    set "LISTENER_PID=%%P"
)

if not defined LISTENER_PID (
    echo [INFO] Port %PORT% is free.
    exit /b 0
)

echo [WARN] Port %PORT% is still used by PID !LISTENER_PID! for %NAME%.
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter 'ProcessId = !LISTENER_PID!' | Select-Object -ExpandProperty CommandLine" 2>nul
echo.

if /I "%STOP_ASSUME_YES%"=="1" (
    taskkill /PID !LISTENER_PID! /T /F >nul 2>nul
    exit /b 0
)

choice /C YN /N /M "Stop this process? [Y/N] "
if errorlevel 2 exit /b 0

taskkill /PID !LISTENER_PID! /T /F >nul 2>nul
if errorlevel 1 (
    echo [WARN] Failed to stop PID !LISTENER_PID!.
    exit /b 1
)

exit /b 0
