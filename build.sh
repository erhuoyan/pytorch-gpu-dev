#!/usr/bin/env bash
# build.sh — build and optionally push one image variant.
#
# Wheels are NOT stored in git. Each variant has wheels/<variant>/urls.txt
# listing download URLs (GitHub Releases, OSS, COS, S3 — anything HTTP).
# Preflight downloads them into wheels/<variant>/ before the image build.
#
# Usage:
#   ./build.sh <variant> [--push] [--tag <suffix>] [--user <dockerhub_user>]
#
# Example:
#   ./build.sh cu128-torch2.11
#   ./build.sh cu128-torch2.11 --push --user erhuoyan313 --tag 30102026
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE_NAME="pytorch-gpu-dev"

base_image_for() {
  case "$1" in
    cu128-torch2.11) echo "pytorch/pytorch:2.11.0-cuda12.8-cudnn9-runtime" ;;
    *) return 1 ;;
  esac
}

usage() {
  echo "usage: ./build.sh <variant> [--push] [--tag <suffix>] [--user <dockerhub_user>]" >&2
  echo "variants: cu128-torch2.11" >&2
  exit 1
}

[[ $# -ge 1 ]] || usage
VARIANT="$1"; shift

PUSH=0
SUFFIX="$(date +%d%m%Y)"
USER_NAME="${DOCKERHUB_USERNAME:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push) PUSH=1; shift ;;
    --tag)  SUFFIX="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) usage ;;
  esac
done

BASE_IMAGE="$(base_image_for "$VARIANT")" || { echo "unknown variant: $VARIANT" >&2; exit 1; }
WHEELS_DIR="$ROOT/wheels/$VARIANT"
MANIFEST="$WHEELS_DIR/urls.txt"

[[ -f "$MANIFEST" ]] || { echo "missing $MANIFEST" >&2; exit 1; }

# --- download missing wheels ------------------------------------------------
echo ">>> [wheels] resolving $VARIANT from $MANIFEST"
while read -r url; do
  [[ -z "$url" || "$url" == \#* ]] && continue
  fname="$(basename "$url")"
  dest="$WHEELS_DIR/$fname"
  if [[ -f "$dest" ]] && ! head -c 200 "$dest" | grep -q "git-lfs.github.com/spec"; then
    echo "    cached: $fname"
    continue
  fi
  echo "    downloading: $fname"
  curl -fL --retry 3 --retry-delay 5 --connect-timeout 20 -o "$dest" "$url"
done < "$MANIFEST"

shopt -s nullglob
wheels=("$WHEELS_DIR"/*.whl)
(( ${#wheels[@]} > 0 )) || { echo "no wheels resolved in $WHEELS_DIR" >&2; exit 1; }
ls -lh "${wheels[@]}"

# --- build ------------------------------------------------------------------
[[ -n "$USER_NAME" ]] || { echo "need --user <dockerhub_user> (or DOCKERHUB_USERNAME)" >&2; exit 1; }
IMAGE="${USER_NAME}/${IMAGE_NAME}"

echo ">>> [build] ${IMAGE}:${VARIANT}-${SUFFIX} (base: ${BASE_IMAGE})"
DOCKER_BUILDKIT=1 docker build \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --build-arg WHEELS_DIR="wheels/$VARIANT" \
  -t "${IMAGE}:${VARIANT}-${SUFFIX}" \
  -t "${IMAGE}:${VARIANT}" \
  -t "${IMAGE}:latest" \
  "$ROOT"

# --- push -------------------------------------------------------------------
if [[ $PUSH -eq 1 ]]; then
  for t in "${VARIANT}-${SUFFIX}" "${VARIANT}" latest; do
    echo ">>> [push] ${IMAGE}:${t}"
    docker push "${IMAGE}:${t}"
  done
fi

echo ">>> Done: ${IMAGE}:${VARIANT}-${SUFFIX}"
