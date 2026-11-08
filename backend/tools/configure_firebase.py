"""Create public Flutter build settings from an Android Firebase config file.

This tool never accepts, copies or embeds a server service-account private key.
"""
import argparse
import json
from pathlib import Path


def main():
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser()
    parser.add_argument('--android-config', type=Path, default=root / 'android' / 'app' / 'google-services.json')
    parser.add_argument('--output', type=Path, default=root / 'backend' / '.local' / 'firebase-config.json')
    parser.add_argument('--api-base-url', default='http://127.0.0.1:8000')
    args = parser.parse_args()
    try:
        data = json.loads(args.android_config.read_text(encoding='utf-8-sig'))
        matches = [c for c in data['client'] if c['client_info']['android_client_info']['package_name'] == 'com.hjm.Spendtrail']
        if len(matches) != 1:
            raise ValueError()
        client = matches[0]
        config = {
            'FIREBASE_PROJECT_ID': data['project_info']['project_id'],
            'FIREBASE_SENDER_ID': data['project_info']['project_number'],
            'FIREBASE_APP_ID': client['client_info']['mobilesdk_app_id'],
            'FIREBASE_API_KEY': client['api_key'][0]['current_key'],
            'API_BASE_URL': args.api_base_url,
        }
        if not all(isinstance(value, str) and value for value in config.values()):
            raise ValueError()
    except (OSError, ValueError, KeyError, TypeError, IndexError):
        raise SystemExit('Use the Android google-services.json for package com.hjm.Spendtrail. Do not use a service-account key.') from None
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(config, indent=2) + '\n', encoding='utf-8')
    print('Firebase app build settings prepared for project ' + config['FIREBASE_PROJECT_ID'])


if __name__ == '__main__':
    main()
