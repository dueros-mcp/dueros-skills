#!/usr/bin/env bash
# xiaodu-shortcut-official 共用函数库
# 被 list_recipes / get_recipe / save_recipe / delete_recipe / match_recipe / run_recipe 引用
#
# 注意：此文件作为库被 source，不应修改调用者的 shell 选项（如 set -e/-u）。
# 选项设置由各个脚本自行负责。

# --- 路径常量 ---
SHORTCUT_HOME="${HOME}/.openclaw/workspace/memory/xiaodu-shortcut"
RECIPES_DIR="${SHORTCUT_HOME}/recipes"
STATS_FILE="${SHORTCUT_HOME}/stats.json"
README_FILE="${SHORTCUT_HOME}/README.md"

# 依赖 skill 的脚本目录（相对当前 scripts/ 目录定位）
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_SCRIPTS="$(cd "${_SELF_DIR}/../../xiaodu-control-official/scripts" 2>/dev/null && pwd || echo "")"

# --- 基础工具 ---

ensure_dirs() {
  mkdir -p "$RECIPES_DIR"
  if [[ ! -f "$STATS_FILE" ]]; then
    echo '{}' > "$STATS_FILE"
  fi
  if [[ ! -f "$README_FILE" ]]; then
    cat > "$README_FILE" <<'EOF'
# xiaodu-shortcut 数据目录

此目录由 `xiaodu-shortcut-official` skill 维护。

- `recipes/`  每个 recipe 一个 JSON 文件。可手工编辑，但建议通过 skill 的 save_recipe 脚本写入以获得 schema 校验。
- `stats.json`  使用统计（触发次数、最近时间），用于偏好排序。
- 删除某个 recipe：直接删除 `recipes/<id>.json`，或使用 `delete_recipe.sh --id <id>`。

详情参考 skill 内的 `references/recipe-schema.md`。
EOF
  fi
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: 'jq' is required but not installed. Please install jq first." >&2
    exit 2
  fi
}

require_control_skill() {
  if [[ -z "$CONTROL_SCRIPTS" || ! -x "${CONTROL_SCRIPTS}/control_iot.sh" ]]; then
    echo "ERROR: xiaodu-control-official scripts not found. Expected at sibling directory." >&2
    exit 3
  fi
}

# --- recipe 工具 ---

# 规范化字符串：小写 + trim
normalize_str() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | awk '{$1=$1;print}'
}

recipe_file_by_id() {
  printf '%s/%s.json' "$RECIPES_DIR" "$1"
}

# 校验单个 recipe JSON：必选字段、id 格式、steps 非空
# 参数: $1 = 文件路径
# 成功返回 0，失败打印错误到 stderr 返回非 0
validate_recipe_json() {
  local f="$1"
  if ! jq empty "$f" >/dev/null 2>&1; then
    echo "invalid JSON: $f" >&2; return 10
  fi
  local id name primary steps_n
  id=$(jq -r '.id // ""' "$f")
  name=$(jq -r '.name // ""' "$f")
  primary=$(jq -r '.triggers.primary // ""' "$f")
  steps_n=$(jq '.steps | length // 0' "$f" 2>/dev/null || echo 0)
  if [[ -z "$id" ]]; then echo "missing .id" >&2; return 11; fi
  if ! [[ "$id" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "invalid .id '$id' (must be kebab-case)" >&2; return 12
  fi
  if [[ -z "$name" ]]; then echo "missing .name" >&2; return 13; fi
  if [[ -z "$primary" ]]; then echo "missing .triggers.primary" >&2; return 14; fi
  if [[ "$steps_n" == "0" ]]; then echo "empty .steps" >&2; return 15; fi
  return 0
}
