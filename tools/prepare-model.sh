#!/usr/bin/env bash
set -euo pipefail

# 下载 Qwen3-ASR CoreML 模型，编译并整理成 App 包内目录结构。
# 用法: bash tools/prepare-model.sh [输出目录]
# 默认输出: <repo>/AsrRecognize/Resources/Qwen3ASR

REPO="aufklarer/Qwen3-ASR-CoreML"
TOKENIZER_REPO="aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="${1:-$ROOT_DIR/AsrRecognize/Resources/Qwen3ASR}"
WORK="${TMPDIR:-/tmp}/qwen3-asr-coreml"
SRC="$WORK/src"
TOK="$WORK/tokenizer"

die() { echo "错误: $*" >&2; exit 1; }
note() { echo "==> $*"; }

[[ "$(uname -s)" == "Darwin" ]] || die "必须在 macOS 上运行（需要 xcrun coremlcompiler）"
command -v xcrun >/dev/null || die "找不到 xcrun，请安装 Xcode Command Line Tools"

note "工作目录: $WORK"
note "输出目录: $DEST"
rm -rf "$WORK"
mkdir -p "$SRC" "$TOK" "$DEST"

if command -v hf >/dev/null 2>&1; then
  DL_KIND="hf"
elif command -v huggingface-cli >/dev/null 2>&1; then
  DL_KIND="hfcli"
else
  die "缺少 Hugging Face CLI。请先执行: python3 -m pip install -U huggingface_hub"
fi

note "下载模型仓库 ${REPO}（约 1GB，首次较慢）"
if [[ "$DL_KIND" == "hf" ]]; then
  hf download "$REPO" --local-dir "$SRC"
  hf download "$TOKENIZER_REPO" --include vocab.json merges.txt tokenizer_config.json --local-dir "$TOK"
else
  huggingface-cli download "$REPO" --local-dir "$SRC"
  huggingface-cli download "$TOKENIZER_REPO" vocab.json merges.txt tokenizer_config.json --local-dir "$TOK"
fi

note "仓库文件清单（用于人工核对解码器结构）"
find "$SRC" -maxdepth 3 \( -name "*.mlpackage" -o -name "*.mlmodelc" -o -name "config.json" \) -print | sort

find_model() {
  local name="$1"
  find "$SRC" -name "$name" -type d -print -quit 2>/dev/null
}

compile_model() {
  local src="$1" out="$2"
  [[ -n "$src" ]] || die "找不到模型文件: $out"
  rm -rf "$out"
  if [[ "$src" == *.mlmodelc ]]; then
    cp -R "$src" "$out"
  else
    local tmp="$WORK/compile-$(basename "$out" .mlmodelc)"
    rm -rf "$tmp"; mkdir -p "$tmp"
    xcrun coremlcompiler compile "$src" "$tmp" >/dev/null
    local produced
    produced="$(ls -d "$tmp"/*.mlmodelc 2>/dev/null | head -n 1)"
    [[ -n "$produced" ]] || die "编译失败: $src"
    cp -R "$produced" "$out"
  fi
  note "已生成 $(basename "$out")"
}

# --- 编码器：优先 INT4，其次 INT8 ---
ENC_INT4="$(find_model encoder_int4.mlmodelc)"
[[ -n "$ENC_INT4" ]] || ENC_INT4="$(find_model encoder_int4.mlpackage)"
ENC_INT8="$(find_model encoder.mlmodelc)"
[[ -n "$ENC_INT8" ]] || ENC_INT8="$(find_model encoder.mlpackage)"

if [[ -n "$ENC_INT4" ]]; then
  compile_model "$ENC_INT4" "$DEST/encoder.mlmodelc"
elif [[ -n "$ENC_INT8" ]]; then
  echo "警告: 未找到 INT4 编码器，回退到 INT8。" >&2
  compile_model "$ENC_INT8" "$DEST/encoder.mlmodelc"
else
  die "仓库中既没有 encoder_int4 也没有 encoder"
fi

# --- 解码器 ---
EMB="$(find_model embedding.mlmodelc)"
[[ -n "$EMB" ]] || EMB="$(find_model embedding.mlpackage)"
P1="$(find_model decoder_part1.mlmodelc)"
[[ -n "$P1" ]] || P1="$(find_model decoder_part1.mlpackage)"
P2="$(find_model decoder_part2.mlmodelc)"
[[ -n "$P2" ]] || P2="$(find_model decoder_part2.mlpackage)"

if [[ -z "$P1" || -z "$P2" ]]; then
  echo "" >&2
  echo "停止: 解码器不是 decoder_part1/decoder_part2 结构。" >&2
  echo "Qwen3ASR 的 CoreMLTextDecoder 需要两个分段模型；若仓库只提供单个 decoder，" >&2
  echo "不要猜名，先根据上面的文件清单调整转换脚本或联系模型作者。" >&2
  echo "已找到: embedding='$EMB' part1='$P1' part2='$P2'" >&2
  exit 2
fi

compile_model "$EMB" "$DEST/embedding.mlmodelc"
compile_model "$P1" "$DEST/decoder_part1.mlmodelc"
compile_model "$P2" "$DEST/decoder_part2.mlmodelc"

# --- config.json ---
if [[ -f "$SRC/config.json" ]]; then
  cp "$SRC/config.json" "$DEST/config.json"
elif [[ -f "$(dirname "$P1")/config.json" ]]; then
  cp "$(dirname "$P1")/config.json" "$DEST/config.json"
else
  cat > "$DEST/config.json" <<'JSON'
{
  "max_seq_length": 1024,
  "vocab_size": 151936,
  "hidden_size": 1024
}
JSON
  note "仓库未提供 config.json，已写入默认值"
fi

# --- Tokenizer ---
for f in vocab.json merges.txt tokenizer_config.json; do
  [[ -f "$TOK/$f" ]] || die "缺少 tokenizer 文件: $f"
  cp "$TOK/$f" "$DEST/$f"
done

# --- 校验与体积 ---
required=(
  encoder.mlmodelc
  embedding.mlmodelc
  decoder_part1.mlmodelc
  decoder_part2.mlmodelc
  config.json
  vocab.json
  merges.txt
  tokenizer_config.json
)
for f in "${required[@]}"; do
  [[ -e "$DEST/$f" ]] || die "输出缺少 $f"
done

{
  echo "Qwen3-ASR model manifest"
  date
  echo
  du -sh "$DEST"/*
} | tee "$DEST/model-manifest.txt"

TOTAL_KB="$(du -sk "$DEST" | awk '{print $1}')"
if (( TOTAL_KB > 1150000 )); then
  echo "警告: 模型目录约 $((TOTAL_KB / 1024)) MB，超过 1.1GB 验收门槛。" >&2
else
  note "模型目录约 $((TOTAL_KB / 1024)) MB，体积在门槛内"
fi

note "完成: 模型已就位，$(basename "$DEST") 会作为蓝色文件夹打进 App。"
