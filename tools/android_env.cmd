@echo off
rem Called by the Windows launchers inside their setlocal scope.
set "SC_FLUTTER_ROOT="
if defined FLUTTER_ROOT if exist "%FLUTTER_ROOT%\bin\flutter.bat" set "SC_FLUTTER_ROOT=%FLUTTER_ROOT%"
if not defined SC_FLUTTER_ROOT (
    where flutter.bat >nul 2>nul
    if errorlevel 1 (
        for %%D in ("%USERPROFILE%\Downloads\Compressed\flutter" "%USERPROFILE%\Downloads\flutter" "C:\flutter" "C:\src\flutter") do if not defined SC_FLUTTER_ROOT if exist "%%~D\bin\flutter.bat" set "SC_FLUTTER_ROOT=%%~D"
    )
)
if defined SC_FLUTTER_ROOT set "PATH=%SC_FLUTTER_ROOT%\bin;%PATH%"
where flutter.bat >nul 2>nul
if errorlevel 1 (
    echo Flutter was not found. Set FLUTTER_ROOT or add Flutter's bin directory to PATH.
    echo See MOBILE_BUILD.md for setup.
    exit /b 1
)

if not defined JAVA_HOME (
    echo Set JAVA_HOME to your standalone JDK 21 directory. See MOBILE_BUILD.md.
    exit /b 2
)
if not exist "%JAVA_HOME%\bin\javac.exe" (
    echo JAVA_HOME does not point to a JDK. See MOBILE_BUILD.md.
    exit /b 2
)
set "PATH=%JAVA_HOME%\bin;%PATH%"

if not defined ANDROID_HOME set "ANDROID_HOME=%ANDROID_SDK_ROOT%"
if not defined ANDROID_HOME set "ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk"
if not exist "%ANDROID_HOME%\platform-tools\adb.exe" (
    echo Set ANDROID_HOME to your SDK and install platform-tools. See MOBILE_BUILD.md.
    exit /b 3
)
set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
exit /b 0
