@echo off
setlocal
cd /d "%~dp0"
echo Short Circuit - Android setup and build
call "%~dp0tools\android_env.cmd"
if errorlevel 1 (
    pause
    exit /b 1
)
echo Android SDK: %ANDROID_HOME%
echo Review the Android SDK licenses below and respond yourself when prompted.
call flutter doctor --android-licenses
if errorlevel 1 (
    echo Android SDK license setup did not complete. Check the message above.
    pause
    exit /b 3
)
call "%~dp0BUILD_ANDROID.cmd"
set "SC_BUILD_EXIT=%ERRORLEVEL%"
if not "%SC_BUILD_EXIT%"=="0" (
    echo The APK build stopped. Keep this window open so the error can be reviewed.
    pause
    exit /b %SC_BUILD_EXIT%
)
echo Ready: %~dp0releases\Short_Circuit.apk
pause
