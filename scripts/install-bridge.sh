#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product YTSubsBridge
BRIDGE_DIR="$HOME/Library/Application Support/YT Subs"
HOST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
mkdir -p "$BRIDGE_DIR" "$HOST_DIR"
cp "$(swift build -c release --show-bin-path)/YTSubsBridge" "$BRIDGE_DIR/YTSubsBridge.new"
chmod 700 "$BRIDGE_DIR/YTSubsBridge.new"
mv "$BRIDGE_DIR/YTSubsBridge.new" "$BRIDGE_DIR/YTSubsBridge"
python3 - "$BRIDGE_DIR/YTSubsBridge" "$HOST_DIR/com.ytsubs.studio.json" <<'PY'
import sys,json,hashlib,base64
manifest=json.load(open('extension/manifest.json'))
key=base64.b64decode(manifest['key'])
ext_id=''.join(chr(int(c,16)+97) for c in hashlib.sha256(key).hexdigest()[:32])
with open(sys.argv[2],'w') as f:
    json.dump({'name':'com.ytsubs.studio','description':'Local YT Subs Studio bridge','path':sys.argv[1],'type':'stdio','allowed_origins':['chrome-extension://'+ext_id+'/']},f,indent=2)
print('Native host installed. Load the extension/ folder in chrome://extensions.')
PY
