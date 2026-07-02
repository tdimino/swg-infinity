#!/usr/bin/env bash
#
# Download SWG Infinity game files directly from the patch server.
# Bypasses the Tauri launcher (which crashes under Wine/CrossOver).
#
# Usage:
#   ./download-game.sh [target-directory]
#
# Default target: ./game-files/
# Requires: curl, python3

set -euo pipefail

TARGET="${1:-./game-files}"
MANIFEST_URL="https://updater.swginfinity.com/manifest.json"
MANIFEST_FILE="$(mktemp)"

trap 'rm -f "$MANIFEST_FILE"' EXIT

echo "SWG Infinity Game File Downloader"
echo "================================="
echo ""

# Fetch manifest
echo "Fetching file manifest..."
curl -sL "$MANIFEST_URL" -o "$MANIFEST_FILE"

# Parse manifest and show summary
FILE_COUNT=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['required']))" "$MANIFEST_FILE")
TOTAL_SIZE=$(python3 -c "import json,sys; print(sum(f['size'] for f in json.load(open(sys.argv[1]))['required']))" "$MANIFEST_FILE")
TOTAL_GB=$(python3 -c "print(f'{int(\"$TOTAL_SIZE\") / (1024**3):.2f}')")

echo "  Files: $FILE_COUNT"
echo "  Total: ${TOTAL_GB} GB"
echo "  Target: $TARGET"
echo ""

mkdir -p "$TARGET"

# Download each file
python3 - "$MANIFEST_FILE" "$TARGET" <<'PYEOF'
import json, subprocess, os, hashlib, sys

manifest = json.load(open(sys.argv[1]))
target = sys.argv[2]
files = manifest['required']
total = len(files)
failures = 0

for i, f in enumerate(files, 1):
    name = f['name']
    url = f['url']
    expected_size = f['size']
    expected_md5 = f['md5']
    dest = os.path.join(target, name)

    os.makedirs(os.path.dirname(dest) if os.path.dirname(dest) else target, exist_ok=True)

    # Skip if file exists with correct size and MD5
    if os.path.exists(dest) and os.path.getsize(dest) == expected_size:
        h = hashlib.md5()
        with open(dest, 'rb') as fh:
            for chunk in iter(lambda: fh.read(8192), b''):
                h.update(chunk)
        if h.hexdigest() == expected_md5:
            size_mb = expected_size / (1024**2)
            print(f'[{i}/{total}] {name} ({size_mb:.1f} MB) — verified')
            continue

    size_mb = expected_size / (1024**2)
    print(f'[{i}/{total}] {name} ({size_mb:.1f} MB) — downloading...')
    result = subprocess.run(
        ['curl', '-L', '--progress-bar', '--connect-timeout', '30', '-o', dest, url],
    )
    if result.returncode != 0:
        print(f'  ERROR: download failed (curl exit {result.returncode})', file=sys.stderr)
        failures += 1
        continue

    actual_size = os.path.getsize(dest)
    if actual_size != expected_size:
        print(f'  WARNING: size mismatch (got {actual_size}, expected {expected_size})')
        failures += 1
        continue

    h = hashlib.md5()
    with open(dest, 'rb') as fh:
        for chunk in iter(lambda: fh.read(8192), b''):
            h.update(chunk)
    if h.hexdigest() != expected_md5:
        print(f'  WARNING: MD5 mismatch')
        failures += 1
        continue

print()
if failures:
    print(f'{failures} file(s) failed. Re-run the script to retry.')
    sys.exit(1)
else:
    print('Download complete. Copy the contents into your Sikarugir')
    print('wrapper at C:\\SWG Infinity\\ and launch SwgClient_r.exe.')
PYEOF
