@echo off
setlocal EnableExtensions

set "START_WEB_MODE=production"
call "%~dp0start.bat"
exit /b %ERRORLEVEL%
