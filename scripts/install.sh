#!/bin/bash
# 构建并安装 Tuck.app 到 /Applications，然后启动
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
pkill -x Tuck 2>/dev/null && sleep 1 || true
rm -rf /Applications/Tuck.app
cp -R build/Tuck.app /Applications/Tuck.app
open /Applications/Tuck.app
echo "已安装到 /Applications/Tuck.app"
