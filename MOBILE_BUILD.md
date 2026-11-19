# Build Short Circuit for Android

This package contains the Flutter/C++ source. The tested toolchain is Flutter 3.47.8, Dart 3.13.7, Java 21, Android SDK 36, Build-Tools 36.0.0, and NDK 28.2.13676358.

## One-time setup on Windows

1. Install the [Flutter SDK](https://docs.flutter.dev/install) and add its bin directory to PATH. The Windows launchers also look for Flutter in Downloads and Downloads/Compressed.
2. Install a standalone [JDK 21](https://learn.microsoft.com/en-us/java/openjdk/download). Set the Windows user environment variable JAVA_HOME to its installation folder.
3. Download the [Android SDK command-line tools](https://developer.android.com/studio#command-line-tools-only). Set the Windows user environment variable ANDROID_HOME to your SDK folder. The default is %LOCALAPPDATA%\Android\Sdk. Follow the [sdkmanager setup](https://developer.android.com/tools/sdkmanager) so that sdkmanager.bat is in cmdline-tools\latest\bin within that folder.
4. Open a new PowerShell window. Install the packages and select the JDK and SDK for Flutter.

~~~powershell
& "$env:ANDROID_HOME\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root="$env:ANDROID_HOME" "platform-tools" "platforms;android-36" "build-tools;36.0.0" "ndk;28.2.13676358"
flutter config --jdk-dir "$env:JAVA_HOME"
flutter config --android-sdk "$env:ANDROID_HOME"
~~~

Review the SDK licenses when prompted. For live testing, connect an Android phone with USB debugging enabled and run flutter devices to get its device ID.

## Make the APK

Double-click **SETUP_AND_BUILD_ANDROID.cmd** to review the Android SDK licenses and build the APK. Keep an internet connection available for the first build so Flutter and Gradle can fetch dependencies.

The script generates the version-matched Android Gradle host without replacing app source, resolves dependencies, runs Flutter analysis, builds the debug APK, and copies it to:

`releases/Short_Circuit.apk`

The original Flutter output is `build/app/outputs/flutter-apk/app-debug.apk`. Copy the APK to your Android phone and open it to install. This is a debug-signed development build for demonstrating the project. Store distribution requires your own release signing configuration.

To run directly on a connected device, double-click **RUN_ANDROID.cmd**. With multiple devices use `RUN_ANDROID.cmd -d <device-id>` in a terminal.

## macOS or Linux

From this folder, run:

```sh
python3 tools/prepare_android.py
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter build apk --debug
python3 tools/check_apk.py
```

For a smaller release APK targeting ARM64 phones such as Pixel 7 Pro:

```sh
flutter build apk --release --split-per-abi --target-platform android-arm64
python3 tools/check_apk.py build/app/outputs/flutter-apk/app-arm64-v8a-release.apk --abi arm64-v8a
```

This build is optimized for release and uses the development signing configuration. Android 7.0 / API 24 is the minimum. Copy the APK to your phone and open it to install; Android may ask you to allow installation from the app you opened it with. Store distribution requires your own release signing key.

The Python preparation script requires Python 3.8+. The Windows build scripts do not require Python.

## Build through GitHub Actions

Create a repository with this folder's **contents at its root**, including .github/workflows/android.yml. After pushing, open Actions → Android APK. A successful build uploads **Short-Circuit-Android-APK** containing app-debug.apk. The workflow also checks library packaging and runs the actual Flutter app on an Android emulator. This workflow has not been run from this session.

## Native integration

The local short_circuit_core package compiles src/short_circuit.cpp with the Dart native build hook. It includes engine.hpp and targets C++17. android_libcpp_shared bundles the Android C++ runtime required by the engine. The UI sends requests through dart:ffi on worker isolates; it contains no electrical solver.

## Run verification

On a machine with a desktop C++ toolchain:

```sh
flutter test
cmake -S . -B build/native
cmake --build build/native
ctest --test-dir build/native --output-on-failure
```

On an attached Android emulator/device:

```sh
flutter test integration_test/mobile_smoke_test.dart -d <device-id>
```

The Android smoke test exercises the packaged native library, an example simulation, and saving to the project shelf. It catches runtime library loading problems that desktop tests cannot.

## Current delivery status

Version 0.5 includes the redesigned dark circuit lab, 13 component types, a 4800 × 3200 workspace, continuous current-particle streams and selectable playback speeds. See README.md and docs/ui-validation.json for release evidence. Version 0.2 was confirmed working on the user's Android phone; no phone or emulator is attached to the 0.5 build session.

### Windows host tests without Visual Studio

With the official LLVM-MinGW x64 toolchain installed, run:

~~~powershell
powershell -File tools/test_host_windows.ps1 -Compiler C:/path/to/llvm-mingw/bin/clang++.exe
~~~

This compiles and runs all three native suites, then compiles the same source into build/host/short_circuit_core.dll for Flutter host tests. The build hook only uses this optional DLL for Windows x64; Android release builds always compile source with the NDK. Rerun the script whenever the native source changes.

Integration references: https://docs.flutter.dev/platform-integration/bind-native-code and https://pub.dev/packages/android_libcpp_shared.
