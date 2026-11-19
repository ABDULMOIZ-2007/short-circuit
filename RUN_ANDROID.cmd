@echo off
setlocal
cd /d "%~dp0"
call "%~dp0tools\android_env.cmd"
if errorlevel 1 exit /b %ERRORLEVEL%
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\bootstrap_flutter.ps1"
if errorlevel 1 exit /b 1
call flutter run %*
