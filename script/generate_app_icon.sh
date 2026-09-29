#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "$#" -eq 1 ] || { echo 'Usage: generate_app_icon.sh /path/to/icon.png' >&2; exit 2; }
SOURCE_IMAGE="$1"
ICON_FOLDER="$TASK_ROOT/App/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICON_FOLDER"
python3 - "$ICON_FOLDER" "$SOURCE_IMAGE" <<'PY'
import json
import subprocess
import sys
from pathlib import Path
folder = Path(sys.argv[1])
source = Path(sys.argv[2]).resolve()
images = []
for size in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        filename = f'icon_{size}x{size}@{scale}x.png'
        pixels = str(size * scale)
        subprocess.run(['sips', '--resampleHeightWidth', pixels, pixels,
                        str(source), '--out', str(folder / filename)],
                       check=True, stdout=subprocess.DEVNULL)
        images.append({'idiom': 'mac', 'size': f'{size}x{size}',
                       'scale': f'{scale}x', 'filename': filename})
(folder / 'Contents.json').write_text(json.dumps({'images': images,
    'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
(folder.parent / 'Contents.json').write_text(json.dumps({
    'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
print('Created the macOS AppIcon asset catalog at every required size.')
PY
