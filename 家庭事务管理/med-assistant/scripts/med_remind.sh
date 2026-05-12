#!/bin/bash
set -euo pipefail

TIME=$1
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TEXT=$(python3 "$SCRIPT_DIR/med_broadcast.py" --time "$TIME" 2>/dev/null)
if [ -z "$TEXT" ]; then
  exit 0
fi

DEVICE_NAME=$(MED_SCRIPT_DIR="$SCRIPT_DIR" python3 - <<'EOF'
import json, os, sys
script_dir = os.environ.get('MED_SCRIPT_DIR', '')
data_dir = os.environ.get(
    'MED_DATA_DIR',
    os.path.normpath(os.path.join(script_dir, '..', '..', '..', 'memory', 'med-assistant'))
)
path = os.path.join(data_dir, 'medications.json')
if not os.path.exists(path):
    sys.exit(1)
with open(path) as f:
    data = json.load(f)
name = data.get('settings', {}).get('device_name', '').strip()
if not name:
    sys.exit(1)
print(name)
EOF
)

bash "$SCRIPT_DIR/../../xiaodu-control-official/scripts/speak.sh" \
  --device-name "$DEVICE_NAME" \
  --text "$TEXT"
