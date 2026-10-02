#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
mkdir -p "$HOME/Applications"
ditto "dist/YT Subs.app" "$HOME/Applications/YT Subs.app"
printf 'Installed %s\n' "$HOME/Applications/YT Subs.app"
