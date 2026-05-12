#!/usr/bin/env bash
# delete_recipe.sh —— 删除一个 recipe
# 用法: delete_recipe.sh --id <recipe-id>
# 同时清理 stats.json 中对应条目

set -eu
source "$(dirname "$0")/_lib.sh"
ensure_dirs
require_jq

ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) ID="$2"; shift 2 ;;
    -h|--help) echo "Usage: delete_recipe.sh --id <recipe-id>"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$ID" ]] || { echo "ERROR: --id is required" >&2; exit 1; }

f=$(recipe_file_by_id "$ID")
if [[ ! -f "$f" ]]; then
  echo "ERROR: recipe '$ID' not found" >&2
  exit 4
fi

rm -f "$f"

# 从 stats.json 删除对应字段
TMP=$(mktemp)
jq --arg id "$ID" 'del(.[$id])' "$STATS_FILE" > "$TMP" && mv "$TMP" "$STATS_FILE"

jq -n --arg id "$ID" '{ok: true, id: $id, deleted: true}'
