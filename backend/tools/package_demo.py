"""Package the review APK, source and demo guides without local credentials."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import zipfile


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if not args.apk.is_file():
        parser.error('Build the demo release APK first')
    if args.output.exists() and any(args.output.iterdir()):
        parser.error('Choose a new or empty package directory')
    version = re.search(r'^version:\s*(\S+)', (root / 'pubspec.yaml').read_text(), re.M).group(1)
    args.output.mkdir(parents=True, exist_ok=True)
    apk = args.output / f'SpendTrail-{version}-usb-demo.apk'
    shutil.copy2(args.apk, apk)
    for name in ('SETUP_GUIDE.md', 'DEMO_GUIDE.md', 'RELEASE_VERIFICATION.md'):
        shutil.copy2(root / 'docs' / name, args.output / name)
    shutil.copy2(root / 'assets/imports/sample_purchases.csv', args.output / 'sample_purchases.csv')
    files = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root).decode().split('\0')
    allowed_roots = {'lib', 'test', 'assets', 'android', 'ios', 'linux', 'macos', 'windows', 'web', 'backend', 'docs'}
    selected = []
    for name in sorted(set(files)):
        if not name:
            continue
        path = Path(name)
        if len(path.parts) > 1 and path.parts[0] not in allowed_roots:
            continue
        lower = name.lower()
        # The outer bundle's checksum is generated after source.zip; including
        # that checksum inside its own input would create a circular digest.
        if name == 'docs/evidence/release-20261109/package.json':
            continue
        if any(part in {'.local', '.git', '.gradle', '.venv', '__pycache__', 'build'} for part in path.parts):
            continue
        if path.name.startswith('.env') and path.name != '.env.example':
            continue
        if path.name in {'local.properties', 'key.properties', 'google-services.json'}:
            continue
        if any(pattern in lower for pattern in ('service-account', 'firebase-adminsdk', 'firebase-config.json')):
            continue
        if path.suffix.lower() in {'.dump', '.jks', '.keystore', '.log', '.apk', '.zip', '.pyc'}:
            continue
        if (root / path).is_file():
            selected.append(name)
    source = args.output / f'SpendTrail-{version}-source.zip'
    with zipfile.ZipFile(source, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name in selected:
            archive.write(root / name, 'SpendTrail/' + name)
    with zipfile.ZipFile(source) as archive:
        assert archive.testzip() is None
        assert 'SpendTrail/pubspec.yaml' in archive.namelist()
        assert 'SpendTrail/android/app/src/demo/AndroidManifest.xml' in archive.namelist()
        assert not any('/.local/' in name or name.endswith('/.env') or 'service-account' in name for name in archive.namelist())
    manifest = {'created_utc': datetime.now(timezone.utc).isoformat(), 'version': version,
                'package': 'com.hjm.Spendtrail', 'flavor': 'demo', 'compilation': 'release',
                'signing': 'existing development certificate; local review distribution',
                'api': 'http://127.0.0.1:8000 over adb reverse', 'source_files': len(selected),
                'private_credentials_and_databases_included': False,
                'files': {path.name: {'bytes': path.stat().st_size, 'sha256': sha(path)}
                          for path in sorted(args.output.iterdir()) if path.is_file()}}
    (args.output / 'MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    bundle = args.output.parent / (args.output.name + '.zip')
    with zipfile.ZipFile(bundle, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(args.output.iterdir()):
            if path.is_file():
                archive.write(path, path.name)
    with zipfile.ZipFile(bundle) as archive:
        assert archive.testzip() is None
    proof = dict(manifest, bundle={'name': bundle.name, 'bytes': bundle.stat().st_size, 'sha256': sha(bundle)})
    evidence = root / 'docs/evidence/release-20261109/package.json'
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps(proof, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'bundle': str(bundle.resolve()), 'apk': str(apk.resolve()),
                      'source_files': len(selected), 'bundle_sha256': sha(bundle)}, indent=2))


if __name__ == '__main__':
    main()
