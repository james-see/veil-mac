#!/usr/bin/env bash
# Download Rampart (nationaldesignstudio/rampart, CC BY 4.0) into Veil's model dir.
set -euo pipefail
REV="${RAMPART_REV:-b1993e4e68b082835b80ffc65acc03325ea2e501}"   # pinned HF commit (2026-06-30)
DEST="${1:-$HOME/Library/Application Support/Veil/rampart}"
BASE="https://huggingface.co/nationaldesignstudio/rampart/resolve/${REV}"
mkdir -p "$DEST/onnx"
for f in config.json tokenizer.json tokenizer_config.json special_tokens_map.json vocab.txt LICENSE MODEL_CARD.md onnx/model_q4.onnx; do
  echo "→ $f"; curl -fL --retry 3 -o "$DEST/$f" "$BASE/$f"
done
size=$(wc -c < "$DEST/onnx/model_q4.onnx")
[ "$size" -gt 1000000 ] || { echo "model_q4.onnx is only $size bytes (LFS pointer?)" >&2; exit 1; }
echo "Rampart installed in: $DEST ($size bytes)"
