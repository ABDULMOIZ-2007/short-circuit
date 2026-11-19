"""Generate Flutter's version-matched Gradle host; preserve checked-in app files."""
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def prepare():
    flutter = shutil.which("flutter")
    if not flutter:
        raise SystemExit("Flutter is not on PATH. Install the stable Flutter SDK first.")
    android = ROOT / "android"
    if not (android / "gradlew").exists() or not (android / "settings.gradle.kts").exists():
        host = ROOT / ".platform-host"
        subprocess.run([flutter, "create", "--project-name", "short_circuit", "--org", "edu.moiz",
                        "--platforms=android", "--no-pub", str(host)], cwd=ROOT, check=True)
        for source in (host / "android").rglob("*"):
            if source.is_file():
                target = android / source.relative_to(host / "android")
                if not target.exists():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, target)
        if not (ROOT / ".metadata").exists():
            shutil.copy2(host / ".metadata", ROOT / ".metadata")
    gradle = android / "app/build.gradle.kts"
    text = gradle.read_text(encoding="utf-8")
    text = text.replace("minSdk = flutter.minSdkVersion", "minSdk = maxOf(flutter.minSdkVersion, 24)")
    gradle.write_text(text, encoding="utf-8")
    (android / "gradlew").chmod(0o755)
    print("Android host ready. Application ID: edu.moiz.short_circuit; minimum SDK: 24.")

if __name__ == "__main__":
    prepare()
