#!/bin/bash
# Nanomouse 拼音输入法 - Mac 安装脚本
# 适用于鼠须管 (Squirrel)

set -e

RIME_DIR="$HOME/Library/Rime"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHARED_DIR="$SCRIPT_DIR/../shared"

echo "🐭 Nanomouse 拼音输入法安装脚本"
echo "================================"

# 检查鼠须管是否安装
if [ ! -d "/Library/Input Methods/Squirrel.app" ]; then
    echo "❌ 未检测到鼠须管输入法"
    echo "请先从 https://rime.im/download/ 下载安装鼠须管"
    exit 1
fi

# 检查 Rime 配置目录
if [ ! -d "$RIME_DIR" ]; then
    echo "📁 创建 Rime 配置目录: $RIME_DIR"
    mkdir -p "$RIME_DIR"
fi

# 复制配置文件（仅复制需要的两个文件）
echo "📋 复制配置文件..."
cp -v "$SHARED_DIR/default.custom.yaml" "$RIME_DIR/"
cp -v "$SHARED_DIR/luna_pinyin_simp.custom.yaml" "$RIME_DIR/"

echo ""
echo "✅ 配置文件已复制到 $RIME_DIR"
echo ""

# 触发重新部署
echo "🔄 正在重新部署 Rime..."
"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --reload 2>/dev/null || true

echo ""
echo "🎉 安装完成！"
echo ""
echo "功能说明："
echo "  - 用 nn 代替 ng（后鼻音）"
echo "  - 用 vn 代替 uan"
echo "  - 用 vnn 代替 uang"
echo "  - 默认使用简体中文"
echo ""
echo "测试方法："
echo "  输入 'dann' 应该能看到 '当' 等候选词"
echo "  输入 'gvn' 应该能看到 '关' 等候选词"
