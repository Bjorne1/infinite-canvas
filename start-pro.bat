@echo off
setlocal EnableExtensions

set "START_WEB_MODE=production"
set "START_SKIP_WEB_BUILD=1"
call "%~dp0start.bat"
exit /b %ERRORLEVEL%
