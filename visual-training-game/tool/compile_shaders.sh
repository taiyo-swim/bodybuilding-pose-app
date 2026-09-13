#!/usr/bin/env bash
# フラグメントシェーダーが GLES / Vulkan / Metal 向けにコンパイルできるかを検証する。
#
# シェーダーはモデルが目視確認できない領域なので（仕様書 12）、
# せめて「コンパイルが通る」ことは機械的に確かめる。実機での見え方の確認は別途必要。
#
# 使い方: tool/compile_shaders.sh
set -euo pipefail

FLUTTER_BIN="$(command -v flutter)"
FLUTTER_ROOT="$(dirname "$(dirname "$(readlink -f "$FLUTTER_BIN")")")"

case "$(uname -s)" in
  Darwin) HOST="darwin-x64" ;;
  Linux)  HOST="linux-x64" ;;
  *) echo "未対応のホスト: $(uname -s)" >&2; exit 1 ;;
esac

ENGINE="$FLUTTER_ROOT/bin/cache/artifacts/engine/$HOST"
IMPELLERC="$ENGINE/impellerc"

if [[ ! -x "$IMPELLERC" ]]; then
  echo "impellerc が見つからない: $IMPELLERC" >&2
  echo "先に 'flutter precache' を実行すること" >&2
  exit 1
fi

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

status=0
for frag in shaders/*.frag; do
  name="$(basename "$frag" .frag)"
  if "$IMPELLERC" \
      --runtime-stage-gles \
      --runtime-stage-vulkan \
      --runtime-stage-metal \
      --iplr \
      --sl="$OUT/$name.iplr" \
      --spirv="$OUT/$name.spirv" \
      --input="$frag" \
      --input-type=frag \
      --include=shaders \
      --include="$ENGINE/shader_lib"; then
    echo "OK   $frag"
  else
    echo "FAIL $frag" >&2
    status=1
  fi
done

exit "$status"
