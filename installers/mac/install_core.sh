#!/bin/bash
# Nanomouse 安装器核心脚本
# 由 AppleScript App 调用
# 智能安装：备份用户配置，避免覆盖

set -e

RIME_DIR="$HOME/Library/Rime"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="$SCRIPT_DIR/../Resources"
BACKUP_DIR="$RIME_DIR/nanomouse_backup_$(date +%Y%m%d_%H%M%S)"

# 检查鼠须管是否安装
if [ ! -d "/Library/Input Methods/Squirrel.app" ]; then
    echo "ERROR: Squirrel not installed"
    exit 1
fi

# 创建目录
mkdir -p "$RIME_DIR"

# 检查是否有现有配置需要备份
NEED_BACKUP=false
if [ -f "$RIME_DIR/default.custom.yaml" ] || [ -f "$RIME_DIR/luna_pinyin_simp.custom.yaml" ]; then
    NEED_BACKUP=true
fi

# 备份现有配置
if [ "$NEED_BACKUP" = true ]; then
    mkdir -p "$BACKUP_DIR"
    echo "备份现有配置到 $BACKUP_DIR"
    [ -f "$RIME_DIR/default.custom.yaml" ] && cp "$RIME_DIR/default.custom.yaml" "$BACKUP_DIR/"
    [ -f "$RIME_DIR/luna_pinyin_simp.custom.yaml" ] && cp "$RIME_DIR/luna_pinyin_simp.custom.yaml" "$BACKUP_DIR/"
fi

# 智能合并 luna_pinyin_simp.custom.yaml
if [ -f "$RIME_DIR/luna_pinyin_simp.custom.yaml" ]; then
    # 检查是否已包含 nanomouse 规则
    if grep -q "derive/ng\$/nn/" "$RIME_DIR/luna_pinyin_simp.custom.yaml" 2>/dev/null; then
        echo "Nanomouse 规则已存在，跳过"
    else
        # 追加规则到现有文件
        echo "追加 Nanomouse 规则到现有配置"
        cat >> "$RIME_DIR/luna_pinyin_simp.custom.yaml" << 'NANOMOUSE_RULES'

    # === Nanomouse 规则（自动添加）===
    - derive/ng$/nn/      # ng → nn
    - derive/uan$/vn/     # uan → vn
    - derive/uang$/vnn/   # uang → vnn
NANOMOUSE_RULES
    fi
else
    # 没有现有配置，直接复制
    cp "$RESOURCES_DIR/luna_pinyin_simp.custom.yaml" "$RIME_DIR/"
fi

# 处理 default.custom.yaml（方案选择）
if [ ! -f "$RIME_DIR/default.custom.yaml" ]; then
    # 没有现有配置，直接复制
    cp "$RESOURCES_DIR/default.custom.yaml" "$RIME_DIR/"
else
    echo "保留用户现有的 default.custom.yaml"
fi

# 重新部署
"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --reload 2>/dev/null || true

echo "SUCCESS"
if [ "$NEED_BACKUP" = true ]; then
    echo "BACKUP_PATH=$BACKUP_DIR"
fi
