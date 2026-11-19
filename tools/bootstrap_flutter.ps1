$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Install the Flutter SDK and add its bin directory to PATH. See MOBILE_BUILD.md.'
}
$androidRoot = Join-Path $projectRoot 'android'
if (-not (Test-Path -LiteralPath (Join-Path $androidRoot 'gradlew')) -or -not (Test-Path -LiteralPath (Join-Path $androidRoot 'settings.gradle.kts'))) {
    $hostRoot = Join-Path $projectRoot '.platform-host'
    & flutter create --project-name short_circuit --org edu.moiz --platforms=android --no-pub $hostRoot
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Android host generation failed.' }
    $generatedRoot = Join-Path $hostRoot 'android'
    foreach ($file in Get-ChildItem -LiteralPath $generatedRoot -File -Recurse) {
        $relative = $file.FullName.Substring($generatedRoot.Length).TrimStart([char[]]'\/')
        $target = Join-Path $androidRoot $relative
        if (-not (Test-Path -LiteralPath $target)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $target
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot '.metadata'))) {
        Copy-Item -LiteralPath (Join-Path $hostRoot '.metadata') -Destination (Join-Path $projectRoot '.metadata')
    }
}
$gradlePath = Join-Path $androidRoot 'app\build.gradle.kts'
$gradle = Get-Content -LiteralPath $gradlePath -Raw
$gradle = $gradle.Replace('minSdk = flutter.minSdkVersion','minSdk = maxOf(flutter.minSdkVersion, 24)')
[System.IO.File]::WriteAllText($gradlePath, $gradle, [System.Text.UTF8Encoding]::new($false))
Push-Location -LiteralPath $projectRoot
try {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed.' }
    & flutter analyze --no-fatal-infos --no-fatal-warnings
    if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis found errors. Resolve them before building.' }
} finally { Pop-Location }
Write-Output 'Android host ready. Use BUILD_ANDROID.cmd to create the installable APK.'
