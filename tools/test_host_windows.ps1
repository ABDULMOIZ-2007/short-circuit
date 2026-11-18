param([string]$Compiler = 'clang++.exe', [switch]$SkipFlutter)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
  $out = Join-Path $projectRoot 'build/host'
  New-Item -ItemType Directory -Path $out -Force | Out-Null
  $source = 'packages/short_circuit_core/src'
  & $Compiler -std=c++17 -O2 -static "-I$source" tests/core_tests.cpp "$source/short_circuit.cpp" -o "$out/core_tests.exe"
  if ($LASTEXITCODE) { throw 'Core test compilation failed.' }
  & "$out/core_tests.exe"
  if ($LASTEXITCODE) { throw 'Core checks failed.' }
  & $Compiler -std=c++17 -O2 -static "-I$source" tests/extended_core_tests.cpp -o "$out/extended_core_tests.exe"
  if ($LASTEXITCODE) { throw 'Extended test compilation failed.' }
  & "$out/extended_core_tests.exe"
  if ($LASTEXITCODE) { throw 'Extended checks failed.' }
  & $Compiler -std=c++17 -O2 -static "-I$source" tests/current_flow_tests.cpp -o "$out/current_flow_tests.exe"
  if ($LASTEXITCODE) { throw 'Current flow test compilation failed.' }
  & "$out/current_flow_tests.exe"
  if ($LASTEXITCODE) { throw 'Current flow checks failed.' }
  & $Compiler -std=c++17 -O2 -static -shared "-I$source" "$source/short_circuit.cpp" -o "$out/short_circuit_core.dll"
  if ($LASTEXITCODE) { throw 'Native test library compilation failed.' }
  if (-not $SkipFlutter) { flutter test; if ($LASTEXITCODE) { throw 'Flutter checks failed.' } }
} finally { Pop-Location }
