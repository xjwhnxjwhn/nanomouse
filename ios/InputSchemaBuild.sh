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
    
    # === Nanomouse: 添加拼音映射规则 ===
    cat > rime_ice.custom.yaml << 'NANOMOUSE_CONFIG'
# Nanomouse 拼音优化配置
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

    # === Nanomouse: 添加日语方案（增量，不覆盖原列表） ===
    cat > default.custom.yaml << 'DEFAULT_CONFIG'
# Nanomouse 默认方案配置
# 增量追加日语方案，保留原有 schema_list

patch:
  schema_list/+:
    - schema: japanese        # 日语
DEFAULT_CONFIG
    # === Nanomouse 配置结束 ===
    
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
