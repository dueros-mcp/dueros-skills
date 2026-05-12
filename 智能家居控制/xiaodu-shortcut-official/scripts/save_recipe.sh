#!/usr/bin/env bash
# save_recipe.sh —— 创建或更新一个 recipe
# 用法:
#   save_recipe.sh --file <path-to-json>          # 从 JSON 文件读取
#   save_recipe.sh --json '<json-string>'         # 直接传 JSON 字符串
#   save_recipe.sh --stdin                        # 从 stdin 读取
#
# 校验:
#   - schema（必选字段、id 格式、steps 非空）
#   - 触发词冲突（primary/aliases 与现有 recipe 不能有任何一个完全相同，除非是同一个 id 在更新）
#
# 默认覆盖同 id 的已有 recipe（更新语义）。
# 成功输出: {"ok": true, "id": "...", "action": "created"|"updated", "path": "..."}

set -eu
source "$(dirname "$0")/_lib.sh"
ensure_dirs
require_jq

SRC_FILE=""
SRC_JSON=""
FROM_STDIN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)  SRC_FILE="$2"; shift 2 ;;
    --json)  SRC_JSON="$2"; shift 2 ;;
    --stdin) FROM_STDIN=1; shift ;;
    -h|--help)
      echo "Usage: save_recipe.sh (--file <path> | --json <str> | --stdin)"
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# 读取输入到临时文件
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

if [[ -n "$SRC_FILE" ]]; then
  [[ -f "$SRC_FILE" ]] || { echo "ERROR: file not found: $SRC_FILE" >&2; exit 1; }
  cp "$SRC_FILE" "$TMP"
elif [[ -n "$SRC_JSON" ]]; then
  printf '%s' "$SRC_JSON" > "$TMP"
elif [[ "$FROM_STDIN" -eq 1 ]]; then
  cat > "$TMP"
else
  echo "ERROR: one of --file / --json / --stdin is required" >&2
  exit 1
fi

# 基础 schema 校验
if ! validate_recipe_json "$TMP"; then
  echo "ERROR: recipe validation failed" >&2
  exit 11
fi

ID=$(jq -r '.id' "$TMP")
PRIMARY=$(jq -r '.triggers.primary' "$TMP")

# 触发词冲突检查：遍历已有 recipes，除 id==当前 外，不允许有任何 primary/alias 与新 recipe 的任何触发词重复
NEW_TRIGGERS=$(jq -r '[.triggers.primary] + (.triggers.aliases // []) | .[]' "$TMP" | awk 'NF')

shopt -s nullglob
for f in "$RECIPES_DIR"/*.json; do
  other_id=$(jq -r '.id // ""' "$f" 2>/dev/null || echo "")
  [[ "$other_id" == "$ID" ]] && continue
  other_triggers=$(jq -r '[.triggers.primary] + (.triggers.aliases // []) | .[]' "$f" 2>/dev/null | awk 'NF')
  while IFS= read -r nt; do
    [[ -z "$nt" ]] && continue
    nt_norm=$(normalize_str "$nt")
    while IFS= read -r ot; do
      [[ -z "$ot" ]] && continue
      if [[ "$(normalize_str "$ot")" == "$nt_norm" ]]; then
        echo "ERROR: trigger '$nt' conflicts with existing recipe '$other_id'" >&2
        exit 20
      fi
    done <<< "$other_triggers"
  done <<< "$NEW_TRIGGERS"
done

TARGET=$(recipe_file_by_id "$ID")
ACTION="created"
[[ -f "$TARGET" ]] && ACTION="updated"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# 注入 created_at / updated_at
if [[ "$ACTION" == "created" ]]; then
  jq --arg now "$NOW" '.created_at = (.created_at // $now) | .updated_at = $now | .schema_version = (.schema_version // "1")' "$TMP" > "$TARGET"
else
  # 保留原 created_at
  prev_created=$(jq -r '.created_at // ""' "$TARGET")
  jq --arg now "$NOW" --arg prev "$prev_created" '
    .created_at = (if ($prev | length) > 0 then $prev else (.created_at // $now) end)
    | .updated_at = $now
    | .schema_version = (.schema_version // "1")
  ' "$TMP" > "$TARGET"
fi

jq -n --arg id "$ID" --arg action "$ACTION" --arg path "$TARGET" \
  '{ok: true, id: $id, action: $action, path: $path}'
