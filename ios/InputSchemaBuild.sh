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
    # 纠错：强力锁定音节映射，防止分词器切分（针对 S/D 邻居键误触）
    - derive/^shi$/dhi/
    - derive/^sha$/dha/
    - derive/^shu$/dhu/
    - derive/^she$/dhe/
    - derive/^shai$/dhai/
    - derive/^shei$/dhei/
    - derive/^shao$/dhao/
    - derive/^shou$/dhou/
    - derive/^shan$/dhan/
    - derive/^shen$/dhen/
    - derive/^shang$/dhang/
    - derive/^sheng$/dheng/
    - derive/^shua$/dhua/
    - derive/^shuan$/dhuan/
    - derive/^shuang$/dhuang/
    - derive/^shui$/dhui/
    - derive/^shuai$/dhuai/
    - derive/^sh/dh/
    - abbrev/^sh/dh/
    # 键位优化：uan → vn
    - derive/uan$/vn/
    # 键位优化：uang → vnn
    - derive/uang$/vnn/
NANOMOUSE_CONFIG

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
    JAROOMAJI_DIR="$OUTPUT/.$jaroomaji_scheme_name" \
    JAROOMAJI_EASY_DST="$OUTPUT/.$jaroomaji_easy_scheme_name/jaroomaji-easy.schema.yaml" \
    JAROOMAJI_EASY_DIR="$OUTPUT/.$jaroomaji_easy_scheme_name" \
    python3 - <<'PY'
import os
import re
from pathlib import Path

src = Path(os.environ["JAROOMAJI_SRC"])
src_dir = Path(os.environ["JAROOMAJI_DIR"])
dst = Path(os.environ["JAROOMAJI_EASY_DST"])
dst_dir = Path(os.environ["JAROOMAJI_EASY_DIR"])
text = src.read_text(encoding="utf-8")

# 1. 基础信息修改
text = text.replace("schema_id: jaroomaji", "schema_id: jaroomaji-easy", 1)
text = text.replace("name: 日本語ローマ字", "name: 日本語ローマ字 Easy", 1)
text = text.replace("dictionary: jaroomaji", "dictionary: jaroomaji-easy", 1)

# 2. 移除单辅音直接映射小促音的 Algebra 规则（解决 Stupid 问题）
def should_drop_xtu_single(line: str) -> bool:
    m = re.search(r'derive/([xX][tT][uU])/([^"]+)/', line)
    if not m:
        return False
    target = m.group(2)
    if target.lower() == "xtsu":
        return False
    # 如果映射结果只有 1 个字符，说明是 Stupid 规则（如 s -> xtu）
    return len(target) == 1

lines = []
for line in text.splitlines():
    if should_drop_xtu_single(line):
        continue
    lines.append(line)

text = "\n".join(lines) + "\n"

# 3. 注入特殊的促音渲染规则并启用预编辑 (实现 iOS 原生感模式)
# 启用连打补全 (解决 Progressive Lag 问题)
text = text.replace("enable_completion: false", "enable_completion: true", 1)

# 启用按音节删除 (实现 iOS 原生删除体验)
if "speller:" in text:
    text = text.replace("speller:", "speller:\n  backspace_by_syllable: true", 1)

# 注入 KeyBinder 规则：强制 BackSpace 删除整个假名 (音节)
# 这是在移动端实现“按假名删除”的最稳健方法
backspace_rule = "    - { when: composing, accept: BackSpace, send: Control+BackSpace }"
if "key_binder:" in text:
    # 在 bindings: 下方注入
    text = re.sub(r'(?m)^(  bindings:\s*\n)', r'\1' + backspace_rule + '\n', text)

# 清理 preedit_format：移除单字母直接变促音的规则（Stupid 回显根源）
# 同时也移除大写字符的单字母促音规则
def is_bad_preedit(line: str) -> bool:
    # 匹配类似 - "xform/s/っ/" 或 - "xform/S/ッ/" 的行
    return bool(re.search(r'xform/[A-Za-z]/[っッ]/', line))

lines = [l for l in text.splitlines() if not is_bad_preedit(l)]
text = "\n".join(lines) + "\n"

# 注入我们的双辅音渲染规则：在 preedit_format 列表的最顶部加入
sokuon_rule = "    - 'xform/([bcdfghjklmpqrstvwxyz])\\1/っ$1/'"
sokuon_rule_caps = "    - 'xform/([BCDFGHJKLMPQRSTVWXYZ])\\1/ッ$1/'"
# 注入到 preedit_format: 下方
text = re.sub(r'(?m)^  preedit_format:\s*\n', 
              lambda m: m.group(0) + sokuon_rule + "\n" + sokuon_rule_caps + "\n", 
              text)

dst.write_text(text, encoding="utf-8")

# 4. 定向音节合并：将 xtu 合并到下一个音节中（i xtu syo -> i ssyo）
# 核心：必须保留其他音节间的空格，防止 Rime 编译器产生组合爆炸(Hang/OOM)
consonants = set("bcdfghjklmnpqrstvwxyz")

def transform_code(code: str) -> str:
    tokens = code.split(" ")
    res = []
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        # 如果是促音标记且后面还有音节，则尝试合并
        if tok.lower() == "xtu" and i + 1 < len(tokens):
            nxt = tokens[i+1]
            if nxt and nxt[0].lower() in consonants:
                # 合并：首字母双写 + 剩余部分
                doubled = nxt[0] + nxt[0] + nxt[1:]
                res.append(doubled)
                i += 2
                continue
        res.append(tok)
        i += 1
    # 保持空格分隔，确保 O(n) 构建性能
    return " ".join(res)

def transform_dict(src_p, dst_p):
    in_body = False
    out_lines = []
    with src_p.open("r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            if line.startswith("name: "):
                line = line.replace("jaroomaji", "jaroomaji-easy", 1)
            if line.startswith("..."):
                in_body = True
                out_lines.append(line)
                continue
            if not in_body:
                out_lines.append(line)
                continue
            if "\t" in line:
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 2:
                    parts[1] = transform_code(parts[1])
                    line = "\t".join(parts) + "\n"
            out_lines.append(line)
    dst_p.write_text("".join(out_lines), encoding="utf-8")

# 生成主词库描述文件
main_dict = src_dir / "jaroomaji.dict.yaml"
main_text = main_dict.read_text(encoding="utf-8")
main_text = main_text.replace("name: jaroomaji", "name: jaroomaji-easy", 1)
main_text = re.sub(r'(?m)^\s*-\s+jaroomaji\.', "  - jaroomaji-easy.", main_text)
(dst_dir / "jaroomaji-easy.dict.yaml").write_text(main_text, encoding="utf-8")

# 对子词库进行定向合并转换
for p in src_dir.glob("jaroomaji.*.dict.yaml"):
    if p.name == "jaroomaji.dict.yaml": continue
    suffix = p.name.replace("jaroomaji.", "")
    transform_dict(p, dst_dir / f"jaroomaji-easy.{suffix}")



PY
    cd $OUTPUT/.$jaroomaji_easy_scheme_name
    zip -r $jaroomaji_easy_scheme_name.zip ./*
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
