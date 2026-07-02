#!/usr/bin/env bash
# Game file download from patch server manifest.

SWG_MANIFEST_URL="https://updater.swginfinity.com/manifest.json"

swg_cmd_download() {
    local target="$SWG_ROOT/game-files"
    while [ $# -gt 0 ]; do
        case "$1" in
            --target)
                [ $# -ge 2 ] || { echo "Error: --target requires a directory argument"; return 1; }
                target="$2"; shift 2
                ;;
            --help|-h) echo "Usage: swg download [--target dir]"; return 0 ;;
            *) target="$1"; shift ;;
        esac
    done

    local manifest
    manifest=$(mktemp)
    trap 'rm -f "$manifest"' EXIT RETURN

    echo "SWG Infinity Game File Downloader"
    echo "================================="
    echo ""
    echo "Fetching file manifest..."
    if ! curl -fsSL "$SWG_MANIFEST_URL" -o "$manifest"; then
        swg_die "Failed to fetch manifest from $SWG_MANIFEST_URL"
    fi

    local file_count total_size total_gb
    file_count=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['required']))" "$manifest")
    total_size=$(python3 -c "import json,sys; print(sum(f['size'] for f in json.load(open(sys.argv[1]))['required']))" "$manifest")
    total_gb=$(python3 -c "import sys; print(f'{int(sys.argv[1])/(1024**3):.2f}')" "$total_size")

    echo "  Files: $file_count"
    echo "  Total: ${total_gb} GB"
    echo "  Target: $target"
    echo ""

    mkdir -p "$target"

    python3 - "$manifest" "$target" <<'PYEOF'
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

    if os.path.isabs(name) or '..' in name.split('/'):
        print(f'[{i}/{total}] SKIPPED {name} — unsafe path', file=sys.stderr)
        failures += 1
        continue

    dest = os.path.realpath(os.path.join(target, name))
    if not dest.startswith(os.path.realpath(target) + os.sep) and dest != os.path.realpath(target):
        print(f'[{i}/{total}] SKIPPED {name} — path escapes target', file=sys.stderr)
        failures += 1
        continue

    os.makedirs(os.path.dirname(dest) if os.path.dirname(dest) else target, exist_ok=True)

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
    print(f'{failures} file(s) failed. Re-run to retry.')
    sys.exit(1)
else:
    print('Download complete.')
PYEOF
}
