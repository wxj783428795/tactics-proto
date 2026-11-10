#!/usr/bin/env bash
# 备用发布方式（Actions 不可用时）：在本机导出网页版，并推送到 gh-pages 分支。
# 用法：GODOT=/path/to/Godot_v4.3-stable_linux.x86_64 tools/deploy_web.sh
# 前提：已安装 4.3 导出模板；仓库 Pages 来源设为 gh-pages 分支（根目录）。
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
mkdir -p build && touch build/.gdignore
"$GODOT" --headless --path . --import || true
rm -rf build/web && mkdir -p build/web
"$GODOT" --headless --path . --export-release Web build/web/index.html
touch build/web/.nojekyll
REMOTE="$(git remote get-url origin)"
TMP="$(mktemp -d)"
git -C "$TMP" init -q -b gh-pages
cp -r build/web/. "$TMP"/
git -C "$TMP" add -A
git -C "$TMP" commit -q -m "Deploy web build from $(git rev-parse --short HEAD)"
git -C "$TMP" push -f "$REMOTE" gh-pages
rm -rf "$TMP"
echo "已推送到 gh-pages。"
