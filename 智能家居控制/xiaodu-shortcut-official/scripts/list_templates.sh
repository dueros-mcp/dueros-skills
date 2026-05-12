#!/usr/bin/env bash
# list_templates.sh —— 列出内置 recipe 模板
# 模板位于 ../references/recipe-templates/*.json
# 输出: [{id, name, description, triggers}, ...]

set -eu
source "$(dirname "$0")/_lib.sh"
require_jq

TPL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../references/recipe-templates" && pwd)"

shopt -s nullglob
files=( "$TPL_DIR"/*.json )
if [[ ${#files[@]} -eq 0 ]]; then
  echo '[]'
  exit 0
fi

# 逐文件处理：损坏模板跳过并 WARN
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
for f in "${files[@]}"; do
  if ! jq -e '{
    id: .id,
    name: .name,
    description: (.description // ""),
    triggers: (.triggers // {primary: "", aliases: []})
  }' "$f" >> "$tmp" 2>/dev/null; then
    echo "WARN: skip invalid template file: $f" >&2
  fi
done

jq -s '.' "$tmp"
