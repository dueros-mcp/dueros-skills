#!/usr/bin/env bash
# list_recipes.sh —— 列出所有已保存 recipe 的索引
# 输出: JSON 数组 [{id, name, description, triggers}, ...]

set -eu
source "$(dirname "$0")/_lib.sh"
ensure_dirs
require_jq

shopt -s nullglob
files=( "$RECIPES_DIR"/*.json )
if [[ ${#files[@]} -eq 0 ]]; then
  echo '[]'
  exit 0
fi

# 逐文件处理：损坏的 JSON 跳过并 WARN，不影响其他 recipe
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
for f in "${files[@]}"; do
  if ! jq -e '. as $r | {
    id: $r.id,
    name: $r.name,
    description: ($r.description // ""),
    triggers: ($r.triggers // {primary: "", aliases: []})
  }' "$f" >> "$tmp" 2>/dev/null; then
    echo "WARN: skip invalid recipe file: $f" >&2
  fi
done

jq -s '.' "$tmp"
