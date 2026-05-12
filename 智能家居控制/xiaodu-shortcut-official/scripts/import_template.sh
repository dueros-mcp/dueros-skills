#!/usr/bin/env bash
# import_template.sh —— 把内置模板导入为用户 recipe（支持占位符）
#
# 用法:
#   # 1. 先拿填槽元信息（含候选设备列表 + 默认值建议）
#   import_template.sh --template <template-id> --describe
#
#   # 2. 实际导入（Agent 询问用户后传值）
#   import_template.sh --template <template-id> \
#       --values-json '{"tv":"75寸三星","smart_screen":"小度智能屏2"}'
#   import_template.sh --template <template-id> --values-file /path/to/values.json
#
#   # 其他可选参数
#   --override-id <new-id>          # 改 id 避免覆盖同 id recipe
#   --override-primary <trigger>    # 改主触发词
#   --clear-aliases                 # 清空别名避免冲突
#   --dry-run                       # 渲染但不 save，直接打印最终 recipe
#   --no-defaults                   # 不读/不写 placeholder-defaults.json
#
# 兼容: 模板没有 placeholders 段时，不需要传 values；行为等同 v1 直接 save。

set -eu
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_placeholder_lib.sh"
ensure_dirs
require_jq

TPL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../references/recipe-templates" && pwd)"
SAVE_SH="$(dirname "$0")/save_recipe.sh"

TEMPLATE_ID=""
NEW_ID=""
NEW_PRIMARY=""
CLEAR_ALIASES=0
DESCRIBE=0
VALUES_JSON=""
VALUES_FILE=""
DRY_RUN=0
NO_DEFAULTS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --template)         TEMPLATE_ID="$2"; shift 2 ;;
    --override-id)      NEW_ID="$2"; shift 2 ;;
    --override-primary) NEW_PRIMARY="$2"; shift 2 ;;
    --clear-aliases)    CLEAR_ALIASES=1; shift ;;
    --describe)         DESCRIBE=1; shift ;;
    --values-json)      VALUES_JSON="$2"; shift 2 ;;
    --values-file)      VALUES_FILE="$2"; shift 2 ;;
    --dry-run)          DRY_RUN=1; shift ;;
    --no-defaults)      NO_DEFAULTS=1; shift ;;
    -h|--help)
      sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$TEMPLATE_ID" ]] || { echo "ERROR: --template is required" >&2; exit 1; }
TPL_FILE="$TPL_DIR/$TEMPLATE_ID.json"
[[ -f "$TPL_FILE" ]] || { echo "ERROR: template '$TEMPLATE_ID' not found" >&2; exit 4; }

# --describe 模式：只输出填槽元信息
if [[ "$DESCRIBE" -eq 1 ]]; then
  if [[ "$NO_DEFAULTS" -eq 1 ]]; then
    # 临时把 defaults 换成空；无论 describe_template 成功/失败都恢复原值
    orig_defaults=$(load_defaults)
    echo '{}' > "$DEFAULTS_FILE"
    trap 'echo "$orig_defaults" > "$DEFAULTS_FILE"' EXIT
    describe_template "$TPL_FILE"
    echo "$orig_defaults" > "$DEFAULTS_FILE"
    trap - EXIT
  else
    describe_template "$TPL_FILE"
  fi
  exit 0
fi

# 取 values
VALUES='{}'
if [[ -n "$VALUES_FILE" ]]; then
  [[ -f "$VALUES_FILE" ]] || { echo "ERROR: values file not found: $VALUES_FILE" >&2; exit 1; }
  VALUES=$(cat "$VALUES_FILE")
elif [[ -n "$VALUES_JSON" ]]; then
  VALUES="$VALUES_JSON"
fi

# 校验 values 是合法 JSON 对象
if ! echo "$VALUES" | jq 'if type == "object" then . else error("not object") end' >/dev/null 2>&1; then
  echo "ERROR: values must be a JSON object" >&2
  exit 1
fi

# 检查模板是否需要占位符；如果需要但 values 为空对象，提示
HAS_PLACEHOLDERS=$(jq -r '(.placeholders // {}) | keys | length' "$TPL_FILE")
if [[ "$HAS_PLACEHOLDERS" -gt 0 ]] && [[ "$(echo "$VALUES" | jq 'keys | length')" == "0" ]]; then
  echo "ERROR: template '$TEMPLATE_ID' has $HAS_PLACEHOLDERS placeholder(s); --values-json or --values-file is required" >&2
  echo "Hint: run with --describe to see placeholders and their candidates" >&2
  exit 1
fi

# 渲染
RENDERED=$(render_template "$TPL_FILE" "$VALUES") || {
  rc=$?
  # render_template 已经把错误打 stderr，这里直接透传退出码
  exit $rc
}

# 应用 override
if [[ -n "$NEW_ID" ]]; then
  RENDERED=$(echo "$RENDERED" | jq --arg id "$NEW_ID" '.id = $id')
fi
if [[ -n "$NEW_PRIMARY" ]]; then
  RENDERED=$(echo "$RENDERED" | jq --arg p "$NEW_PRIMARY" '.triggers.primary = $p')
fi
if [[ "$CLEAR_ALIASES" -eq 1 ]]; then
  RENDERED=$(echo "$RENDERED" | jq '.triggers.aliases = []')
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "$RENDERED"
  exit 0
fi

# 交给 save_recipe.sh 做 schema + 冲突校验并写入
# 注意：在 set -e 下，save_recipe.sh 退出非 0 时本脚本会直接以相同退出码结束，
# 其 stderr 已输出；因此只在成功分支继续做 defaults 回写。
echo "$RENDERED" | bash "$SAVE_SH" --stdin

# 回写 defaults（save 成功才会走到这里）
if [[ "$NO_DEFAULTS" -ne 1 ]]; then
  UPDATE=$(compute_defaults_update "$TPL_FILE" "$VALUES")
  if [[ "$(echo "$UPDATE" | jq 'keys | length')" -gt 0 ]]; then
    save_defaults "$UPDATE"
  fi
fi
