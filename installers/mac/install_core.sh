#!/bin/bash
# Nanomouse 安装器核心脚本
# 由 AppleScript App 调用

set -e

RIME_DIR="$HOME/Library/Rime"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 检查鼠须管是否安装
if [ ! -d "/Library/Input Methods/Squirrel.app" ]; then
    echo "ERROR: Squirrel not installed"
    exit 1
fi

# 创建目录
mkdir -p "$RIME_DIR"

# 复制配置文件（从 App bundle 内的 Resources 目录）
RESOURCES_DIR="$SCRIPT_DIR/../Resources"
cp "$RESOURCES_DIR/default.custom.yaml" "$RIME_DIR/"
cp "$RESOURCES_DIR/luna_pinyin_simp.custom.yaml" "$RIME_DIR/"

# 重新部署
"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --reload 2>/dev/null || true

echo "SUCCESS"
