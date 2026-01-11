#!/usr/bin/env bash
# encoding: utf-8
set -e

# 输入方案临时目录
if [[ -z "${CI_PRIMARY_REPOSITORY_PATH}" ]]; then
  CI_PRIMARY_REPOSITORY_PATH="$PWD"
  WORK=`pwd`
else
  CI_PRIMARY_REPOSITORY_PATH="${CI_PRIMARY_REPOSITORY_PATH}"
  WORK="${CI_PRIMARY_REPOSITORY_PATH}"
fi

# 如果方案存在就不再执行
# if [[  -f Resources/SharedSupport/SharedSupport.zip ]]
# then
#   exit 0
# fi

# 下载已编译过的rimelib
rime_version=1.8.5
rime_git_hash=08dd95f
if [[ ! -d .deps ]] 
then
  rime_archive="rime-${rime_git_hash}-macOS.tar.bz2"
  rime_download_url="https://github.com/rime/librime/releases/download/${rime_version}/${rime_archive}"

  rime_deps_archive="rime-deps-${rime_git_hash}-macOS.tar.bz2"
  rime_deps_download_url="https://github.com/rime/librime/releases/download/${rime_version}/${rime_deps_archive}"

  rm -rf .deps && mkdir -p .deps && (
      cd .deps
      [ -z "${no_download}" ] && curl -LO "${rime_download_url}"
      tar --bzip2 -xf "${rime_archive}"
      [ -z "${no_download}" ] && curl -LO "${rime_deps_download_url}"
      tar --bzip2 -xf "${rime_deps_archive}"
  )
fi



OUTPUT="$CI_PRIMARY_REPOSITORY_PATH/.tmp"
DST_PATH="$OUTPUT/SharedSupport"
rm -rf .plum $OUTPUT
mkdir -p $DST_PATH/opencc
cp -r .deps/share/opencc $DST_PATH

git clone --depth 1 https://github.com/rime/plum.git $OUTPUT/.plum

for package in prelude rime-essay; do
  bash $OUTPUT/.plum/scripts/install-packages.sh "${package}" $DST_PATH
done

# 绘文字
# 方案来源: https://github.com/rime/rime-emoji
rime_emoji_version="15.0"
rime_emoji_archive="rime-emoji-${rime_emoji_version}.zip"
rime_emoji_download_url="https://github.com/rime/rime-emoji/archive/refs/tags/${rime_emoji_version}.zip"
rm -rf $OUTPUT/.emoji && mkdir -p $OUTPUT/.emoji && (
    cd $OUTPUT/.emoji
    [ -z "${no_download}" ] && curl -Lo "${rime_emoji_archive}" "${rime_emoji_download_url}"
    unzip "${rime_emoji_archive}" -d .
    rm -rf ${rime_emoji_archive}
    cd rime-emoji-${rime_emoji_version}
    for target in category word; do
      ${WORK}/.deps/bin/opencc -c ${WORK}/.deps/share/opencc/t2s.json -i opencc/emoji_${target}.txt > ${target}.txt
      # workaround for rime/rime-emoji#48
      # macOS sed 和 GNU sed 不同，见 https://stackoverflow.com/a/4247319/6676742
      sed -i'.original' -e 's/鼔/鼓/g' ${target}.txt
      cat ${target}.txt opencc/emoji_${target}.txt | awk '!seen[$1]++' > ../emoji_${target}.txt
    done
  ) && \
cp ${OUTPUT}/.emoji/emoji_*.txt ${DST_PATH}/opencc/ && \
cp ${OUTPUT}/.emoji/rime-emoji-${rime_emoji_version}/opencc/emoji.json ${DST_PATH}/opencc/

# 整理 DST_PATH 输入方案文件, 生成最终版版本default.yaml
pushd "${DST_PATH}" > /dev/null

# 通过 schema_list.yaml 内容 改写 default.yaml 中 scheme_list 中内容
echo '' > schema_list.yaml
sed '{
  s/^config_version: \(["]*\)\([0-9.]*\)\(["]*\)$/config_version: \1\2.minimal\3/
  /- schema:/d
  /^schema_list:$/r schema_list.yaml
}' default.yaml > default.yaml.min
rm schema_list.yaml
mv default.yaml.min default.yaml

popd > /dev/null

# SharedSupport
mkdir -p $CI_PRIMARY_REPOSITORY_PATH/Resources/SharedSupport
(
  cp $CI_PRIMARY_REPOSITORY_PATH/Resources/SharedSupport/hamster.yaml $DST_PATH
  cd $DST_PATH/
  zip -r SharedSupport.zip *
) && cp $DST_PATH/SharedSupport.zip $CI_PRIMARY_REPOSITORY_PATH/Resources/SharedSupport/

# 内置方案雾凇
input_scheme_name=rime-ice

rm -rf $OUTPUT/.$input_scheme_name && \
  git clone --depth 1 https://github.com/iDvel/$input_scheme_name $OUTPUT/.$input_scheme_name && (
    cd $OUTPUT/.$input_scheme_name
    
    # === NanoMouse: 添加拼音映射规则 ===
    cat > rime_ice.custom.yaml << 'NANOMOUSE_CONFIG'
# NanoMouse 拼音优化配置
# https://github.com/xjwhnxjwhn/nanomouse

patch:
  "speller/algebra/+":
    # 后鼻音简化：ng → nn
    - derive/ng$/nn/
    # 键位优化：uan → vn
    - derive/uan$/vn/
    # 键位优化：uang → vnn
    - derive/uang$/vnn/
NANOMOUSE_CONFIG

    # === NanoMouse: 添加日语方案（增量，不覆盖原列表） ===
    cat > default.custom.yaml << 'DEFAULT_CONFIG'
# NanoMouse 默认方案配置
# 增量追加日语方案，保留原有 schema_list

patch:
  schema_list/+:
    - schema: japanese        # 日语
    - schema: jaroomaji       # 日语罗马字
    - schema: jaroomaji-easy  # 日语罗马字（英文码显示）
DEFAULT_CONFIG
    # === NanoMouse 配置结束 ===
    
    # 提前编译
    # export DYLD_FALLBACK_LIBRARY_PATH=$DYLD_FALLBACK_LIBRARY_PATH:$WORK/.deps/dist/lib
    # $WORK/.deps/dist/bin/rime_deployer --build .
    zip -r $input_scheme_name.zip ./*
  ) && \
  cp -R $OUTPUT/.$input_scheme_name/*.zip $CI_PRIMARY_REPOSITORY_PATH/Resources/SharedSupport/

# === 内置方案：日语 (rime-japanese) ===
japanese_scheme_name=rime-japanese

rm -rf $OUTPUT/.$japanese_scheme_name && \
  git clone --depth 1 https://github.com/gkovacs/$japanese_scheme_name $OUTPUT/.$japanese_scheme_name && (
    cd $OUTPUT/.$japanese_scheme_name
    zip -r $japanese_scheme_name.zip ./*
  ) && \
  cp -R $OUTPUT/.$japanese_scheme_name/*.zip $CI_PRIMARY_REPOSITORY_PATH/Resources/SharedSupport/

# === 内置方案：日语罗马字 (rime-jaroomaji) ===
jaroomaji_scheme_name=rime-jaroomaji

rm -rf $OUTPUT/.$jaroomaji_scheme_name && \
  git clone --depth 1 https://github.com/lazyfoxchan/$jaroomaji_scheme_name $OUTPUT/.$jaroomaji_scheme_name && (
    cd $OUTPUT/.$jaroomaji_scheme_name
    # 将 jaroomaji 默认的 ascii_mode 改为中文模式，和 rime-japanese 行为一致
    if [ -f jaroomaji.schema.yaml ]; then
      sed -i '' 's/reset: 1/reset: 0/g' jaroomaji.schema.yaml
    fi
    zip -r $jaroomaji_scheme_name.zip ./*
  ) && \
  cp -R $OUTPUT/.$jaroomaji_scheme_name/*.zip $CI_PRIMARY_REPOSITORY_PATH/Resources/SharedSupport/

# === 内置方案：日语罗马字（英文码显示）(rime-jaroomaji-easy) ===
jaroomaji_easy_scheme_name=rime-jaroomaji-easy

rm -rf $OUTPUT/.$jaroomaji_easy_scheme_name && \
  mkdir -p $OUTPUT/.$jaroomaji_easy_scheme_name && (
    JAROOMAJI_SRC="$OUTPUT/.$jaroomaji_scheme_name/jaroomaji.schema.yaml" \
    JAROOMAJI_EASY_DST="$OUTPUT/.$jaroomaji_easy_scheme_name/jaroomaji-easy.schema.yaml" \
    python3 - <<'PY'
import os
import re
from pathlib import Path

src = Path(os.environ["JAROOMAJI_SRC"])
dst = Path(os.environ["JAROOMAJI_EASY_DST"])
text = src.read_text(encoding="utf-8")

text = text.replace("schema_id: jaroomaji", "schema_id: jaroomaji-easy", 1)
text = text.replace("name: 日本語ローマ字", "name: 日本語ローマ字 Easy", 1)

# 移除单辅音直接映射小促音的快捷规则（保留显式 xtu/xtsu）
def should_drop_xtu(line: str) -> bool:
    m = re.search(r'derive/(x|X)tu/([^"]+)/', line)
    if not m:
        return False
    target = m.group(2)
    return target not in ("xtsu", "XTSU")

# 移除 L 作为长音符的快捷规则，改为 L 与 X 同样输入小假名
def should_drop_long_vowel_l(line: str) -> bool:
    return bool(re.search(r'^\s*- "derive/-/l/"\s*$', line) or re.search(r'^\s*- "derive/-/L/"\s*$', line))

lines = [line for line in text.splitlines() if not should_drop_xtu(line) and not should_drop_long_vowel_l(line)]

def insert_before_marker(lines: list[str], marker: str, extra: list[str]) -> list[str]:
    for i, line in enumerate(lines):
        if marker in line:
            return lines[:i] + extra + lines[i:]
    return lines + extra

lower_l_rules = [
    '    - "derive/xa/la/"',
    '    - "derive/xi/li/"',
    '    - "derive/xu/lu/"',
    '    - "derive/xe/le/"',
    '    - "derive/xo/lo/"',
    '    - "derive/xya/lya/"',
    '    - "derive/xyu/lyu/"',
    '    - "derive/xyo/lyo/"',
    '    - "derive/xwa/lwa/"',
    '    - "derive/xtu/ltu/"',
]

upper_l_rules = [
    '    - "derive/XA/LA/"',
    '    - "derive/XI/LI/"',
    '    - "derive/XU/LU/"',
    '    - "derive/XE/LE/"',
    '    - "derive/XO/LO/"',
    '    - "derive/XYA/LYA/"',
    '    - "derive/XYU/LYU/"',
    '    - "derive/XYO/LYO/"',
    '    - "derive/XWA/LWA/"',
    '    - "derive/XTU/LTU/"',
]

lines = insert_before_marker(lines, "# か行", lower_l_rules)
lines = insert_before_marker(lines, "# カ行", upper_l_rules)

text = "\n".join(lines) + "\n"

lines = text.splitlines()
out = []
inside_translator = False
skip_preedit = False
preedit_replaced = False
for line in lines:
    if line.startswith("translator:"):
        inside_translator = True
        out.append(line)
        continue
    if inside_translator:
        if skip_preedit:
            if re.match(r"^  [A-Za-z_]", line):
                skip_preedit = False
            else:
                continue
        if line.startswith("  preedit_format:"):
            out.append("  comment_format:")
            out.append('    - "xform/ //"')
            out.append("  preedit_format:")
            out.append('    - "xform/ //"')
            preedit_replaced = True
            skip_preedit = True
            continue
    out.append(line)

if not preedit_replaced:
    raise SystemExit("preedit_format not found in jaroomaji.schema.yaml")

dst.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
    cd $OUTPUT/.$jaroomaji_easy_scheme_name
    zip -r $jaroomaji_easy_scheme_name.zip jaroomaji-easy.schema.yaml
  ) && \
  cp -R $OUTPUT/.$jaroomaji_easy_scheme_name/*.zip $CI_PRIMARY_REPOSITORY_PATH/Resources/SharedSupport/

# === 依赖方案：terra_pinyin.extended (rime-terra-pinyin) ===
terra_pinyin_scheme_name=rime-terra-pinyin

rm -rf $OUTPUT/.$terra_pinyin_scheme_name && \
  git clone --depth 1 https://github.com/rime/$terra_pinyin_scheme_name $OUTPUT/.$terra_pinyin_scheme_name && (
    cd $OUTPUT/.$terra_pinyin_scheme_name

    # 生成 terra_pinyin.extended 方案（满足 rime-japanese 依赖）
    if [ -f terra_pinyin.dict.yaml ]; then
      cp terra_pinyin.dict.yaml terra_pinyin.extended.dict.yaml
      python3 - <<'PY'
from pathlib import Path
path = Path("terra_pinyin.extended.dict.yaml")
if path.exists():
    text = path.read_text(encoding="utf-8")
    text = text.replace("name: terra_pinyin", "name: terra_pinyin.extended", 1)
    path.write_text(text, encoding="utf-8")
PY
    fi
    if [ -f terra_pinyin.schema.yaml ]; then
      cp terra_pinyin.schema.yaml terra_pinyin.extended.schema.yaml
      python3 - <<'PY'
from pathlib import Path
path = Path("terra_pinyin.extended.schema.yaml")
if path.exists():
    text = path.read_text(encoding="utf-8")
    text = text.replace("schema_id: terra_pinyin", "schema_id: terra_pinyin.extended", 1)
    text = text.replace("dictionary: terra_pinyin", "dictionary: terra_pinyin.extended", 1)
    path.write_text(text, encoding="utf-8")
PY
    fi

    zip -r $terra_pinyin_scheme_name.zip ./*
  ) && \
  cp -R $OUTPUT/.$terra_pinyin_scheme_name/*.zip $CI_PRIMARY_REPOSITORY_PATH/Resources/SharedSupport/

# === 依赖方案：stroke (rime-stroke) ===
stroke_scheme_name=rime-stroke

rm -rf $OUTPUT/.$stroke_scheme_name && \
  git clone --depth 1 https://github.com/rime/$stroke_scheme_name $OUTPUT/.$stroke_scheme_name && (
    cd $OUTPUT/.$stroke_scheme_name
    zip -r $stroke_scheme_name.zip ./*
  ) && \
  cp -R $OUTPUT/.$stroke_scheme_name/*.zip $CI_PRIMARY_REPOSITORY_PATH/Resources/SharedSupport/

# === 依赖方案：hangyl (rime-hangyl) ===
hangyl_scheme_name=rime-hangyl

rm -rf $OUTPUT/.$hangyl_scheme_name && \
  git clone --depth 1 https://github.com/rime-aca/$hangyl_scheme_name $OUTPUT/.$hangyl_scheme_name && (
    cd $OUTPUT/.$hangyl_scheme_name
    zip -r $hangyl_scheme_name.zip ./*
  ) && \
  cp -R $OUTPUT/.$hangyl_scheme_name/*.zip $CI_PRIMARY_REPOSITORY_PATH/Resources/SharedSupport/

# === 依赖方案：hannomPS（来自 Rime-Hannom，生成 hannomPS.dict.yaml） ===
hannom_scheme_name=rime-hannomps

rm -rf $OUTPUT/.$hannom_scheme_name && \
  git clone --depth 1 https://github.com/huangjunxin/Rime-Hannom $OUTPUT/.$hannom_scheme_name && (
    cd $OUTPUT/.$hannom_scheme_name
    if [ -f hannom.dict.yaml ]; then
      cp hannom.dict.yaml hannomPS.dict.yaml
      python3 - <<'PY'
from pathlib import Path
path = Path("hannomPS.dict.yaml")
if path.exists():
    text = path.read_text(encoding="utf-8")
    text = text.replace("name: hannom", "name: hannomPS", 1)
    path.write_text(text, encoding="utf-8")
PY
    fi
    zip -r $hannom_scheme_name.zip ./*
  ) && \
  cp -R $OUTPUT/.$hannom_scheme_name/*.zip $CI_PRIMARY_REPOSITORY_PATH/Resources/SharedSupport/
