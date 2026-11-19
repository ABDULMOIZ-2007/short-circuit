"""Check an APK includes the C++ engine and runtime for each packaged ABI."""
import argparse
from pathlib import Path, PurePosixPath
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("apk", nargs="?", type=Path,
    default=Path("build/app/outputs/flutter-apk/app-debug.apk"))
parser.add_argument("--abi", action="append",
    choices=("arm64-v8a", "armeabi-v7a", "x86_64"),
    help="Required ABI; repeat for more than one. Defaults to all three.")
args = parser.parse_args()
required = set(args.abi or ["arm64-v8a", "armeabi-v7a", "x86_64"])
with zipfile.ZipFile(args.apk) as archive:
    names = set(archive.namelist())
    detected = {n.split("/")[1] for n in names if n.startswith("lib/") and n.endswith(".so")}
    checked = sorted(required | detected)
    for abi in checked:
        for library in ("libshort_circuit_core.so", "libc++_shared.so"):
            assert f"lib/{abi}/{library}" in names, f"Missing {library} for {abi}"
    assert not any(PurePosixPath(n).name.startswith(".") for n in names if n.startswith("lib/")), "Temporary native files in APK"
    assert "AndroidManifest.xml" in names
    assert archive.testzip() is None, "Corrupt APK entry"
print(f"PASS: native engine and C++ runtime packaged for {', '.join(checked)}: {args.apk.name}")
