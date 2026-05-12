#!/usr/bin/env bash
# match_recipe.sh —— 给定用户原话 query，返回严格匹配结果 + 候选列表
# 用法: match_recipe.sh --query "<用户原话>"
#
# 输出 JSON:
#   严格命中: {"matched": true, "recipe_id": "...", "matched_trigger": "...", "recipe": {...}}
#   未命中:   {"matched": false, "candidates": [{id, name, description, triggers}, ...]}
#   多命中:   {"matched": true, "recipe_id": "...", "ambiguous": true, "all_matches": [...]}
#            （按 stats.last_triggered_at 取最近，并暴露完整列表供 Agent 确认）

set -eu
source "$(dirname "$0")/_lib.sh"
ensure_dirs
require_jq

QUERY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --query) QUERY="$2"; shift 2 ;;
    -h|--help) echo "Usage: match_recipe.sh --query \"<text>\""; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$QUERY" ]] || { echo "ERROR: --query is required" >&2; exit 1; }

Q_NORM=$(normalize_str "$QUERY")

shopt -s nullglob
files=( "$RECIPES_DIR"/*.json )
if [[ ${#files[@]} -eq 0 ]]; then
  jq -n '{matched: false, candidates: []}'
  exit 0
fi

# 收集所有严格命中的 id
hits=()
hit_triggers=()
for f in "${files[@]}"; do
  jq empty "$f" >/dev/null 2>&1 || { echo "WARN: skip invalid json $f" >&2; continue; }
  id=$(jq -r '.id' "$f")
  triggers=$(jq -r '[.triggers.primary] + (.triggers.aliases // []) | .[]' "$f" | awk 'NF')
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    if [[ "$(normalize_str "$t")" == "$Q_NORM" ]]; then
      hits+=("$id")
      hit_triggers+=("$t")
      break
    fi
  done <<< "$triggers"
done

if [[ ${#hits[@]} -eq 1 ]]; then
  id="${hits[0]}"
  trig="${hit_triggers[0]}"
  f=$(recipe_file_by_id "$id")
  jq --arg id "$id" --arg trig "$trig" \
     '{matched: true, recipe_id: $id, matched_trigger: $trig, recipe: .}' "$f"
  exit 0
fi

if [[ ${#hits[@]} -gt 1 ]]; then
  # 多个命中：按 stats.last_triggered_at 取最近
  best_id=""
  best_ts=""
  all_matches="[]"
  for i in "${!hits[@]}"; do
    id="${hits[$i]}"
    ts=$(jq -r --arg id "$id" '.[$id].last_triggered_at // ""' "$STATS_FILE")
    if [[ -z "$best_id" ]] || [[ "$ts" > "$best_ts" ]]; then
      best_id="$id"; best_ts="$ts"
    fi
  done
  # 构造 all_matches 数组
  tmp_list=$(mktemp); trap 'rm -f "$tmp_list"' EXIT
  for i in "${!hits[@]}"; do
    id="${hits[$i]}"
    trig="${hit_triggers[$i]}"
    jq --arg trig "$trig" '{id, name, matched_trigger: $trig}' "$(recipe_file_by_id "$id")" >> "$tmp_list"
  done
  all_matches=$(jq -s '.' "$tmp_list")
  best_file=$(recipe_file_by_id "$best_id")
  jq --arg id "$best_id" --argjson all "$all_matches" \
     '{matched: true, recipe_id: $id, ambiguous: true, all_matches: $all, recipe: .}' "$best_file"
  exit 0
fi

# 未命中：返回所有合法 recipe 作为 candidates，供 Agent 做语义匹配
# 逐文件处理避免单个损坏 JSON 破坏整体输出
cand_tmp=$(mktemp); trap 'rm -f "$cand_tmp"' EXIT
for f in "${files[@]}"; do
  jq -e '{
    id: .id,
    name: .name,
    description: (.description // ""),
    triggers: (.triggers // {primary: "", aliases: []})
  }' "$f" >> "$cand_tmp" 2>/dev/null || true
done
jq -s '{matched: false, candidates: .}' "$cand_tmp"
