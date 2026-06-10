@echo off
setlocal EnableExtensions

set "ROOT_DIR=%~dp0"
set "WEB_DIR=%ROOT_DIR%web"

echo [infinite-canvas] Build production web bundle
echo.

if not exist "%WEB_DIR%\package.json" (
    echo [ERROR] Cannot find "%WEB_DIR%\package.json".
    echo [ERROR] Please put this script in the project root.
    set "EXIT_CODE=1"
    goto finish
)

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

echo [1/2] Checking web dependencies...
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
)

echo.
echo [2/2] Building Next.js production bundle...
cd /d "%WEB_DIR%"
if errorlevel 1 (
    echo [ERROR] Failed to enter "%WEB_DIR%".
    set "EXIT_CODE=1"
    goto finish
)

call npm run build
if errorlevel 1 (
    echo.
    echo [ERROR] Web production build failed.
    set "EXIT_CODE=1"
    goto finish
)

echo.
echo [INFO] Production bundle is ready.
set "EXIT_CODE=0"

:finish
if /I not "%BUILD_NO_PAUSE%"=="1" pause
exit /b %EXIT_CODE%
