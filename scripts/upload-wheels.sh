#!/usr/bin/env bash
# upload-wheels.sh — publish local wheels to GitHub Releases (default) or any
# object storage, then point wheels/<variant>/urls.txt at them.
#
# Requires: gh CLI (brew install gh && gh auth login)
#
# Usage:
#   ./scripts/upload-wheels.sh cu128-torch2.11
#
# Uploads wheels/<variant>/*.whl to release tag "wheels-<variant>" and rewrites
# urls.txt with the release asset URLs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${REPO:-erhuoyan/pytorch-gpu-dev}"

[[ $# -ge 1 ]] || { echo "usage: ./scripts/upload-wheels.sh <variant>" >&2; exit 1; }
VARIANT="$1"
WD="$ROOT/wheels/$VARIANT"
TAG="wheels-$VARIANT"

[[ -d "$WD" ]] || { echo "missing $WD" >&2; exit 1; }
shopt -s nullglob
wheels=("$WD"/*.whl)
(( ${#wheels[@]} > 0 )) || { echo "no wheels in $WD" >&2; exit 1; }

command -v gh >/dev/null || { echo "gh CLI required: brew install gh && gh auth login" >&2; exit 1; }

echo ">>> [release] $REPO tag=$TAG"
if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  echo "    release exists, uploading (clobber)"
else
  gh release create "$TAG" -R "$REPO" \
    --title "Wheels $VARIANT" \
    --notes "Prebuilt FlashAttention wheels for variant \`$VARIANT\`. Downloaded automatically by CI and build.sh."
fi

gh release upload "$TAG" "${wheels[@]}" -R "$REPO" --clobber

echo ">>> [manifest] rewriting $WD/urls.txt"
{
  echo "# Wheel 下载地址清单（每个 variant 一个目录，一行一个 URL）"
  echo "#"
  echo "# CI 和本地构建都会读取本文件，用 curl 下载到 wheels/<variant>/ 后再构建镜像。"
  echo "# 换存储（GitHub Releases / 阿里云 OSS / 腾讯云 COS / S3）只需改这里的 URL。"
  echo "#"
  echo "# 格式：每行一个 URL，# 开头为注释，空行忽略。"
  echo "#"
  echo "# 当前指向 GitHub Releases。上传方法见 documentation/wheel-reuse.md。"
  for w in "${wheels[@]}"; do
    echo "https://github.com/$REPO/releases/download/$TAG/$(basename "$w")"
  done
} > "$WD/urls.txt"

echo ">>> Done. urls.txt:"
cat "$WD/urls.txt"
