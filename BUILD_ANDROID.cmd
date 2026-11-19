@echo off
setlocal
cd /d "%~dp0"
call "%~dp0tools\android_env.cmd"
if errorlevel 1 exit /b %ERRORLEVEL%
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\bootstrap_flutter.ps1"
if errorlevel 1 exit /b 1
call flutter build apk --debug
if errorlevel 1 exit /b 1
if not exist "%~dp0releases" mkdir "%~dp0releases"
copy /y "%~dp0build\app\outputs\flutter-apk\app-debug.apk" "%~dp0releases\Short_Circuit.apk" >nul
if errorlevel 1 exit /b 1
echo APK ready: %~dp0releases\Short_Circuit.apk
