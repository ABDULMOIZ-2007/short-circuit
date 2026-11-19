"""Package source and assets. Use --output to choose an output directory."""
from pathlib import Path
import argparse, json, zipfile
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, default=root.parent / "deliverables")
output = parser.parse_args().output.resolve()
output.mkdir(parents=True, exist_ok=True)
archive = output / "Short_Circuit_Mobile_Source.zip"
skip = {"node_modules", "build", ".dart_tool", ".platform-host", "__pycache__", "projects", "test-output", "releases", ".gradle", ".git", ".kotlin", ".cxx", ".idea"}
files = sorted(p for p in root.rglob("*") if p.is_file() and p.name not in {"local.properties", "key.properties", ".flutter-plugins-dependencies", "GeneratedPluginRegistrant.java"} and not p.name.endswith((".jks", ".keystore", ".iml")) and not skip.intersection(p.relative_to(root).parts))
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for p in files:
        z.write(p, "Short_Circuit/" + p.relative_to(root).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    names = set(z.namelist())
    for p in ["README.md","MOBILE_BUILD.md","RUN_ANDROID.cmd","START_PREVIEW.cmd","BUILD_ANDROID.cmd","SETUP_AND_BUILD_ANDROID.cmd","tools/android_env.cmd","lib/main.dart","lib/component_editor.dart","lib/current_flow.dart","lib/design_system.dart","test/current_flow_geometry_test.dart","assets/fonts/SpaceGrotesk.ttf","assets/fonts/SpaceGrotesk-OFL.txt","assets/fonts/JetBrainsMono-Regular.ttf","assets/fonts/JetBrainsMono-OFL.txt","tests/current_flow_tests.cpp","android/app/src/main/AndroidManifest.xml",".github/workflows/android.yml","integration_test/mobile_smoke_test.dart","preview/index.html","packages/short_circuit_core/src/engine.hpp","assets/textures/pcb-copper.png"]:
        assert "Short_Circuit/" + p in names
print(json.dumps({"archive":str(archive),"files":len(files),"bytes":archive.stat().st_size}))

