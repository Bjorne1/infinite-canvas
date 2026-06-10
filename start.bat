@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT_DIR=%~dp0"
set "WEB_DIR=%ROOT_DIR%web"
set "BACKEND_PORT=18080"
set "WEB_PORT=13000"
set "URL=http://localhost:%WEB_PORT%"
set "API_BASE_URL=http://127.0.0.1:%BACKEND_PORT%"
if /I "%START_WEB_MODE%"=="production" (
    set "WEB_MODE=production"
    set "WEB_NPM_SCRIPT=start"
) else (
    set "WEB_MODE=development"
    set "WEB_NPM_SCRIPT=dev"
)
set "WEB_START_COMMAND=npm run %WEB_NPM_SCRIPT%"
set "RUNTIME_DIR=%TEMP%\infinite-canvas-runtime"
set "GO_BOOTSTRAP_DIR=%LOCALAPPDATA%\infinite-canvas-go"
set "LOCAL_GO_EXE=%GO_BOOTSTRAP_DIR%\go\bin\go.exe"
set "CODEX_GO_EXE=%TEMP%\codex-go\go\bin\go.exe"
set "DEFAULT_GOPROXY=https://goproxy.cn,direct"
set "BACKEND_PID_FILE=%RUNTIME_DIR%\backend.pid"
set "WEB_PID_FILE=%RUNTIME_DIR%\web.pid"
set "BACKEND_OUT=%RUNTIME_DIR%\backend.out.log"
set "BACKEND_ERR=%RUNTIME_DIR%\backend.err.log"
set "WEB_OUT=%RUNTIME_DIR%\web.out.log"
set "WEB_ERR=%RUNTIME_DIR%\web.err.log"

echo [infinite-canvas] One-click %WEB_MODE% startup
echo.

if not exist "%ROOT_DIR%go.mod" (
    echo [ERROR] Cannot find "%ROOT_DIR%go.mod".
    echo [ERROR] Please put this script in the project root.
    set "EXIT_CODE=1"
    goto finish
)

if not exist "%WEB_DIR%\package.json" (
    echo [ERROR] Cannot find "%WEB_DIR%\package.json".
    echo [ERROR] Please put this script in the project root.
    set "EXIT_CODE=1"
    goto finish
)

if not exist "%RUNTIME_DIR%" mkdir "%RUNTIME_DIR%"

where node >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Node.js is not installed or not available in PATH.
    set "EXIT_CODE=1"
    goto finish
)

where npm >nul 2>nul
if errorlevel 1 (
    echo [ERROR] npm is not installed or not available in PATH.
    set "EXIT_CODE=1"
    goto finish
)

call :resolve_go
if errorlevel 1 (
    set "EXIT_CODE=1"
    goto finish
)

echo [1/4] Checking web dependencies...
if exist "%WEB_DIR%\node_modules\next\package.json" (
    echo [INFO] Web dependencies already installed.
) else (
    cd /d "%WEB_DIR%"
    if errorlevel 1 (
        echo [ERROR] Failed to enter "%WEB_DIR%".
        set "EXIT_CODE=1"
        goto finish
    )

    if exist "%WEB_DIR%\package-lock.json" (
        call npm ci --legacy-peer-deps
    ) else (
        call npm install --legacy-peer-deps
    )

    if errorlevel 1 (
        echo.
        echo [ERROR] npm dependency installation failed.
        set "EXIT_CODE=1"
        goto finish
    )

    cd /d "%ROOT_DIR%"
)

echo.
echo [2/4] Starting backend on port %BACKEND_PORT%...
call :ensure_backend
if errorlevel 1 (
    set "EXIT_CODE=1"
    goto finish
)

echo.
echo [3/4] Starting %WEB_MODE% web on port %WEB_PORT%...
call :ensure_web
if errorlevel 1 (
    set "EXIT_CODE=1"
    goto finish
)

echo.
echo [4/4] Ready
echo [INFO] URL: %URL%
echo [INFO] Backend log: %BACKEND_ERR%
echo [INFO] Web log: %WEB_OUT%

if /I not "%START_NO_BROWSER%"=="1" start "" "%URL%"
set "EXIT_CODE=0"
goto finish

:resolve_go
for /f "delims=" %%G in ('where go 2^>nul') do (
    call :use_go_if_usable "%%G"
    if not errorlevel 1 exit /b 0
    echo [WARN] Ignoring unusable Go: %%G
)

if exist "%LOCAL_GO_EXE%" (
    call :use_go_if_usable "%LOCAL_GO_EXE%"
    if not errorlevel 1 exit /b 0
    echo [WARN] Existing local Go toolchain is not usable. Reinstalling it...
)

if exist "%CODEX_GO_EXE%" (
    call :use_go_if_usable "%CODEX_GO_EXE%"
    if not errorlevel 1 exit /b 0
    echo [WARN] Ignoring unusable Codex Go: %CODEX_GO_EXE%
)

echo [INFO] No usable Go toolchain found. Downloading a local Go toolchain...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.IO.Compression.FileSystem; function Test-GoZip($path){ if(-not (Test-Path -LiteralPath $path)){ return $false }; try { $z=[IO.Compression.ZipFile]::OpenRead($path); $z.Dispose(); return $true } catch { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue; return $false } }; $root=$env:GO_BOOTSTRAP_DIR; $goExe=Join-Path $root 'go\bin\go.exe'; New-Item -ItemType Directory -Force -Path $root | Out-Null; $releases=Invoke-RestMethod -Uri 'https://go.dev/dl/?mode=json' -TimeoutSec 30; $release=$releases | Where-Object { $_.stable -eq $true } | Select-Object -First 1; if(-not $release){ throw 'No stable Go release found.' }; $file=$release.files | Where-Object { $_.os -eq 'windows' -and $_.arch -eq 'amd64' -and $_.kind -eq 'archive' } | Select-Object -First 1; if(-not $file){ throw 'No windows-amd64 Go archive found.' }; $zip=Join-Path $root $file.filename; if(-not (Test-GoZip $zip)){ $ok=$false; $urls=@(('https://go.dev/dl/' + $file.filename), ('https://golang.google.cn/dl/' + $file.filename)); foreach($url in $urls){ try { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue; if(Get-Command curl.exe -ErrorAction SilentlyContinue){ & curl.exe -fL --retry 3 --retry-delay 2 --connect-timeout 30 -o $zip $url; if($LASTEXITCODE -ne 0){ throw ('curl failed: ' + $LASTEXITCODE) } } else { Invoke-WebRequest -Uri $url -OutFile $zip -TimeoutSec 300 }; if(Test-GoZip $zip){ $ok=$true; break }; throw 'Downloaded archive is not a valid zip.' } catch { Write-Warning ('Go download failed from ' + $url + ': ' + $_.Exception.Message) } }; if(-not $ok){ throw 'Failed to download a valid Go archive.' } }; $extractRoot=Join-Path $root 'extract'; $dest=Join-Path $root 'go'; if(Test-Path -LiteralPath $extractRoot){ Remove-Item -LiteralPath $extractRoot -Recurse -Force }; if(Test-Path -LiteralPath $dest){ Remove-Item -LiteralPath $dest -Recurse -Force }; New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null; Expand-Archive -LiteralPath $zip -DestinationPath $extractRoot -Force; Move-Item -LiteralPath (Join-Path $extractRoot 'go') -Destination $dest -Force; Remove-Item -LiteralPath $extractRoot -Recurse -Force; & $goExe version"
if errorlevel 1 (
    echo [ERROR] Failed to prepare Go toolchain.
    exit /b 1
)

call :use_go_if_usable "%LOCAL_GO_EXE%"
if errorlevel 1 (
    echo [ERROR] Local Go toolchain was prepared but is not usable.
    exit /b 1
)
exit /b 0

:use_go_if_usable
set "CANDIDATE_GO=%~1"
set "CANDIDATE_GOROOT="
set "INFERRED_GOROOT="
for %%D in ("%~dp1..") do (
    if exist "%%~fD\bin\go.exe" set "INFERRED_GOROOT=%%~fD"
)
if defined INFERRED_GOROOT (
    set "GOROOT=%INFERRED_GOROOT%"
) else (
    set "GOROOT="
)
for /f "delims=" %%R in ('"%CANDIDATE_GO%" env GOROOT 2^>nul') do set "CANDIDATE_GOROOT=%%R"
if not defined CANDIDATE_GOROOT exit /b 1
if not exist "%CANDIDATE_GOROOT%\bin\go.exe" exit /b 1
if not exist "%CANDIDATE_GOROOT%\src\fmt\print.go" exit /b 1
"%CANDIDATE_GO%" version >nul 2>nul
if errorlevel 1 exit /b 1
set "GO_CMD=%CANDIDATE_GO%"
set "GOROOT=%CANDIDATE_GOROOT%"
call :ensure_goproxy
echo [INFO] Using Go: %GO_CMD%
exit /b 0

:ensure_goproxy
set "GO_ENV_GOPROXY="
set "NORMALIZED_GOPROXY="
for /f "delims=" %%P in ('"%GO_CMD%" env GOPROXY 2^>nul') do set "GO_ENV_GOPROXY=%%P"
set "NORMALIZED_GOPROXY=!GO_ENV_GOPROXY:,=!"
set "NORMALIZED_GOPROXY=!NORMALIZED_GOPROXY:|=!"
set "NORMALIZED_GOPROXY=!NORMALIZED_GOPROXY: =!"
if not defined NORMALIZED_GOPROXY (
    set "GOPROXY=%DEFAULT_GOPROXY%"
    echo [INFO] GOPROXY was empty. Using %GOPROXY%
)
exit /b 0

:ensure_backend
call :get_port_pid %BACKEND_PORT% EXISTING_BACKEND_PID
if defined EXISTING_BACKEND_PID (
    call :check_backend_health
    if not errorlevel 1 (
        > "%BACKEND_PID_FILE%" echo !EXISTING_BACKEND_PID!
        echo [INFO] Backend already running. PID: !EXISTING_BACKEND_PID!
        exit /b 0
    )

    echo [WARN] Port %BACKEND_PORT% is already used by PID !EXISTING_BACKEND_PID!, but health check failed.
    call :show_process !EXISTING_BACKEND_PID!
    echo.
    choice /C YN /N /M "Stop this process and restart backend? [Y/N] "
    if errorlevel 2 exit /b 1
    taskkill /PID !EXISTING_BACKEND_PID! /T /F
    if errorlevel 1 exit /b 1
)

del "%BACKEND_OUT%" "%BACKEND_ERR%" >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Start-Process -FilePath $env:GO_CMD -ArgumentList @('run','.') -WorkingDirectory $env:ROOT_DIR -RedirectStandardOutput $env:BACKEND_OUT -RedirectStandardError $env:BACKEND_ERR -WindowStyle Hidden -PassThru; Set-Content -LiteralPath $env:BACKEND_PID_FILE -Value $p.Id"
if errorlevel 1 (
    echo [ERROR] Failed to start backend.
    call :show_backend_logs
    exit /b 1
)

call :wait_backend
if errorlevel 1 (
    echo [ERROR] Backend did not become healthy.
    call :show_backend_logs
    exit /b 1
)

set /p STARTED_BACKEND_PID=<"%BACKEND_PID_FILE%"
echo [INFO] Backend started. PID: !STARTED_BACKEND_PID!
exit /b 0

:ensure_web
call :get_port_pid %WEB_PORT% EXISTING_WEB_PID
if defined EXISTING_WEB_PID (
    call :check_front_proxy
    if not errorlevel 1 (
        call :check_web_mode !EXISTING_WEB_PID!
        if not errorlevel 1 (
            > "%WEB_PID_FILE%" echo !EXISTING_WEB_PID!
            echo [INFO] %WEB_MODE% web already running. PID: !EXISTING_WEB_PID!
            exit /b 0
        )

        echo [WARN] Port %WEB_PORT% is already used by PID !EXISTING_WEB_PID!, but it is not %WEB_MODE% mode.
        call :show_process !EXISTING_WEB_PID!
        echo.
        choice /C YN /N /M "Stop this process and restart web in %WEB_MODE% mode? [Y/N] "
        if errorlevel 2 exit /b 1
        taskkill /PID !EXISTING_WEB_PID! /T /F
        if errorlevel 1 exit /b 1
    ) else (
        echo [WARN] Port %WEB_PORT% is already used by PID !EXISTING_WEB_PID!, but frontend proxy check failed.
        call :show_process !EXISTING_WEB_PID!
        echo.
        choice /C YN /N /M "Stop this process and restart web? [Y/N] "
        if errorlevel 2 exit /b 1
        taskkill /PID !EXISTING_WEB_PID! /T /F
        if errorlevel 1 exit /b 1
    )
)

if /I "%WEB_MODE%"=="production" (
    if /I "%START_SKIP_WEB_BUILD%"=="1" (
        call :ensure_web_build
    ) else (
        call :build_web
    )
    if errorlevel 1 (
        if /I "%START_SKIP_WEB_BUILD%"=="1" (
            echo [ERROR] Web production bundle is not ready.
        ) else (
            echo [ERROR] Web production build failed.
        )
        exit /b 1
    )
)

del "%WEB_OUT%" "%WEB_ERR%" >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d','/s','/c',$env:WEB_START_COMMAND) -WorkingDirectory $env:WEB_DIR -RedirectStandardOutput $env:WEB_OUT -RedirectStandardError $env:WEB_ERR -WindowStyle Hidden -PassThru; Set-Content -LiteralPath $env:WEB_PID_FILE -Value $p.Id"
if errorlevel 1 (
    echo [ERROR] Failed to start web.
    call :show_web_logs
    exit /b 1
)

call :wait_front_proxy
if errorlevel 1 (
    echo [ERROR] Web did not become ready.
    call :show_web_logs
    exit /b 1
)

set /p STARTED_WEB_PID=<"%WEB_PID_FILE%"
echo [INFO] %WEB_MODE% web started. PID: !STARTED_WEB_PID!
exit /b 0

:build_web
echo [INFO] Building Next.js production bundle...
cd /d "%WEB_DIR%"
if errorlevel 1 exit /b 1
call npm run build
if errorlevel 1 exit /b 1
cd /d "%ROOT_DIR%"
exit /b 0

:ensure_web_build
if exist "%WEB_DIR%\.next\BUILD_ID" (
    echo [INFO] Using existing Next.js production bundle.
    exit /b 0
)

echo [ERROR] Production bundle not found: "%WEB_DIR%\.next\BUILD_ID".
echo [ERROR] Run build-pro.bat first, then run start-pro.bat again.
exit /b 1

:get_port_pid
set "%~2="
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":%~1 .*LISTENING"') do (
    set "%~2=%%P"
)
exit /b 0

:check_backend_health
powershell -NoProfile -Command "try { $r=Invoke-WebRequest -Uri 'http://127.0.0.1:%BACKEND_PORT%/api/health' -UseBasicParsing -TimeoutSec 3; if($r.StatusCode -eq 200 -and $r.Content.Trim() -eq 'ok'){ exit 0 } } catch {}; exit 1"
if errorlevel 1 exit /b 1
exit /b 0

:check_front_proxy
powershell -NoProfile -Command "try { $r=Invoke-WebRequest -Uri 'http://127.0.0.1:%WEB_PORT%/api/health' -UseBasicParsing -TimeoutSec 10; if($r.StatusCode -eq 200 -and $r.Content.Trim() -eq 'ok'){ exit 0 } } catch {}; exit 1"
if errorlevel 1 exit /b 1
exit /b 0

:check_web_mode
powershell -NoProfile -Command "$pidValue=%~1; $commands=@(); for($i=0; $i -lt 8 -and $pidValue -gt 0; $i++){ $p=Get-CimInstance Win32_Process -Filter ('ProcessId = ' + $pidValue) -ErrorAction SilentlyContinue; if(-not $p){ break }; $commands += [string]$p.CommandLine; $pidValue=[int]$p.ParentProcessId }; $cmd=$commands -join \"`n\"; if('%WEB_MODE%' -eq 'production'){ if($cmd -match 'next' -and $cmd -match '\bstart\b' -and $cmd -notmatch '\bdev\b'){ exit 0 } } else { if($cmd -match 'next' -and $cmd -match '\bdev\b'){ exit 0 } }; exit 1"
if errorlevel 1 exit /b 1
exit /b 0

:wait_backend
powershell -NoProfile -Command "$deadline=(Get-Date).AddSeconds(90); while((Get-Date) -lt $deadline){ try { $r=Invoke-WebRequest -Uri 'http://127.0.0.1:%BACKEND_PORT%/api/health' -UseBasicParsing -TimeoutSec 3; if($r.StatusCode -eq 200 -and $r.Content.Trim() -eq 'ok'){ exit 0 } } catch {}; Start-Sleep -Seconds 1 }; exit 1"
if errorlevel 1 exit /b 1
exit /b 0

:wait_front_proxy
powershell -NoProfile -Command "$deadline=(Get-Date).AddSeconds(120); while((Get-Date) -lt $deadline){ try { $r=Invoke-WebRequest -Uri 'http://127.0.0.1:%WEB_PORT%/api/health' -UseBasicParsing -TimeoutSec 5; if($r.StatusCode -eq 200 -and $r.Content.Trim() -eq 'ok'){ exit 0 } } catch {}; Start-Sleep -Seconds 1 }; exit 1"
if errorlevel 1 exit /b 1
exit /b 0

:show_process
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter 'ProcessId = %~1' | Select-Object -ExpandProperty CommandLine" 2>nul
exit /b 0

:show_backend_logs
if exist "%BACKEND_ERR%" (
    echo --- backend stderr ---
    powershell -NoProfile -Command "Get-Content -LiteralPath $env:BACKEND_ERR -Tail 80" 2>nul
)
if exist "%BACKEND_OUT%" (
    echo --- backend stdout ---
    powershell -NoProfile -Command "Get-Content -LiteralPath $env:BACKEND_OUT -Tail 80" 2>nul
)
exit /b 0

:show_web_logs
if exist "%WEB_ERR%" (
    echo --- web stderr ---
    powershell -NoProfile -Command "Get-Content -LiteralPath $env:WEB_ERR -Tail 80" 2>nul
)
if exist "%WEB_OUT%" (
    echo --- web stdout ---
    powershell -NoProfile -Command "Get-Content -LiteralPath $env:WEB_OUT -Tail 80" 2>nul
)
exit /b 0

:finish
if /I not "%START_NO_PAUSE%"=="1" pause
exit /b %EXIT_CODE%
