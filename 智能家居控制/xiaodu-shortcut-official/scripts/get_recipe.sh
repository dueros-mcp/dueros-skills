#!/usr/bin/env bash
# get_recipe.sh —— 获取单个 recipe 的完整 JSON
# 用法: get_recipe.sh --id <recipe-id>

set -eu
source "$(dirname "$0")/_lib.sh"
ensure_dirs
require_jq

ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) ID="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: get_recipe.sh --id <recipe-id>"
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ID" ]]; then
  echo "ERROR: --id is required" >&2
  exit 1
fi

f=$(recipe_file_by_id "$ID")
if [[ ! -f "$f" ]]; then
  echo "ERROR: recipe '$ID' not found at $f" >&2
  exit 4
fi

jq '.' "$f"
