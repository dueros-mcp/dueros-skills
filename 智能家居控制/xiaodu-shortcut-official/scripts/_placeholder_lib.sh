#!/usr/bin/env bash
# _placeholder_lib.sh —— 占位符渲染 + 候选获取 + defaults 持久化
# 被 import_template.sh / verify_recipe.sh 共用
# 此文件作为库被 source，不修改调用者 shell 选项

# 依赖: _lib.sh 已被 source（提供 SHORTCUT_HOME / CONTROL_SCRIPTS / require_jq 等）

DEFAULTS_FILE="${SHORTCUT_HOME}/placeholder-defaults.json"

ensure_defaults_file() {
  [[ -f "$DEFAULTS_FILE" ]] || echo '{}' > "$DEFAULTS_FILE"
}

# 读取 defaults；损坏时打 WARN 并回退为空对象
load_defaults() {
  ensure_defaults_file
  if jq empty "$DEFAULTS_FILE" >/dev/null 2>&1; then
    cat "$DEFAULTS_FILE"
  else
    echo "WARN: placeholder-defaults.json corrupted, fallback to empty" >&2
    echo '{}'
  fi
}

# 写入 defaults；输入为完整 JSON 对象
save_defaults() {
  local json="$1"
  ensure_defaults_file
  # 合并策略：浅合并（新值覆盖旧值）
  local merged
  merged=$(jq -n --argjson old "$(load_defaults)" --argjson new "$json" '$old * $new')
  echo "$merged" > "$DEFAULTS_FILE"
}

# 扫描模板中出现的所有 {{name}} 占位符（去重）
# 用法: extract_placeholders <template_file>
# 输出: 每行一个 placeholder name
extract_placeholders() {
  local f="$1"
  # 把整个 JSON 压成字符串再 grep 出 {{...}}
  jq -r 'tostring' "$f" | grep -oE '\{\{[a-zA-Z_][a-zA-Z0-9_]*\}\}' | sed 's/[{}]//g' | sort -u
}

# 根据 kind 返回候选设备/场景名（每行一个）
# 用法: list_candidates <kind>
# 底层脚本缺失时打 WARN，stdout 返回空
list_candidates() {
  local kind="$1"
  local script=""
  case "$kind" in
    iot_device)   script="${CONTROL_SCRIPTS}/list_iot_devices.sh" ;;
    smart_screen) script="${CONTROL_SCRIPTS}/list_devices.sh" ;;
    scene)        script="${CONTROL_SCRIPTS}/list_scenes.sh" ;;
    any)          return 0 ;;
    *) echo "WARN: unknown placeholder kind '$kind'" >&2; return 0 ;;
  esac

  if [[ ! -x "$script" ]]; then
    echo "WARN: backend script unavailable: $script" >&2
    return 0
  fi

  # 捕获输出，失败则 WARN
  local out err rc err_file
  err_file=$(mktemp)
  out=$(bash "$script" 2>"$err_file") ; rc=$?
  err=$(cat "$err_file"); rm -f "$err_file"

  if [[ $rc -ne 0 ]]; then
    echo "WARN: backend $script exit $rc: $err" >&2
    return 0
  fi

  # 尝试从 JSON 输出中抽设备名；兼容多种字段名
  # xiaodu-control-official 的实际输出格式：
  #   list_iot_devices.sh → {"return":[{"applianceName":..., "roomName":...}]}
  #   list_devices.sh     → [{"device_name":..., "location":...}]
  #   list_scenes.sh      → {"return":[{"sceneName":...}]}
  echo "$out" | jq -r '
    (if type == "array" then .
     elif has("return") then .return
     elif has("devices") then .devices
     elif has("scenes") then .scenes
     elif has("data") then .data
     else [] end)
    | map(.applianceName // .device_name // .sceneName // .name // .friendlyName // .scene_name // .deviceName // empty)
    | .[]
  ' 2>/dev/null | awk 'NF' | sort -u
}

# 渲染模板：给定模板文件 + values JSON，输出最终 recipe JSON 或退出码 40/41
# 用法: render_template <template_file> <values_json_string>
render_template() {
  local tpl="$1"
  local values="$2"

  # 第 1 步: 过滤 steps —— 跳过 skip_if_placeholder_empty 指向空值的 step
  # 同时 strip 掉 skip_if_placeholder_empty / placeholders / default_key 等导入期字段
  local filtered
  filtered=$(jq --argjson vals "$values" '
    .steps = [.steps[] | select(
      (.skip_if_placeholder_empty // null) as $k |
      if $k == null then true
      else (($vals[$k] // "") | tostring | length) > 0
      end
    )]
    | .steps = [.steps[] | del(.skip_if_placeholder_empty)]
    | del(.placeholders)
  ' "$tpl")

  # 第 2 步: 在所有字符串叶子上做 {{name}} 替换
  local rendered
  rendered=$(echo "$filtered" | jq --argjson vals "$values" '
    def subst:
      if type == "string" then
        . as $s |
        reduce ($vals | to_entries[]) as $kv (
          $s;
          gsub("\\{\\{" + $kv.key + "\\}\\}"; ($kv.value // "" | tostring))
        )
      elif type == "array" then map(subst)
      elif type == "object" then with_entries(.value |= subst)
      else . end;
    subst
  ')

  # 第 3 步: 检查是否还有残留的 {{...}}
  local residual
  residual=$(echo "$rendered" | jq -r 'tostring' | grep -oE '\{\{[a-zA-Z_][a-zA-Z0-9_]*\}\}' | sed 's/[{}]//g' | sort -u || true)

  if [[ -n "$residual" ]]; then
    # 判断这些残留是否有 required=true 的声明
    local has_required=0
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      local req
      req=$(jq -r --arg n "$name" 'if (.placeholders[$n] | type) == "object" and (.placeholders[$n] | has("required")) then .placeholders[$n].required else true end' "$tpl")
      if [[ "$req" == "true" ]]; then
        echo "ERROR: required placeholder '{{$name}}' is missing" >&2
        has_required=1
      else
        echo "ERROR: unknown/optional placeholder '{{$name}}' unresolved (no skip_if_placeholder_empty guard)" >&2
      fi
    done <<< "$residual"
    if [[ "$has_required" -eq 1 ]]; then return 40; fi
    return 41
  fi

  # 输出最终 recipe
  echo "$rendered"
  return 0
}

# 给定模板，输出 describe JSON（含 placeholders 元信息 + 候选 + defaults 建议）
# 用法: describe_template <template_file>
describe_template() {
  local tpl="$1"
  ensure_defaults_file
  local defaults
  defaults=$(load_defaults)

  # 顺序规则：优先按 .placeholders 声明顺序（keys_unsorted），
  # 对出现在 steps 里但未声明的 placeholder，按字母序附在末尾。
  local declared_order used_set ordered
  declared_order=$(jq -r '(.placeholders // {}) | keys_unsorted | .[]' "$tpl")
  used_set=$(extract_placeholders "$tpl")
  ordered=""
  # 先取声明且实际被用到的
  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    if echo "$used_set" | grep -Fxq "$k"; then
      ordered+="$k"$'\n'
    fi
  done <<< "$declared_order"
  # 再取用到但未声明的
  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    if ! echo "$declared_order" | grep -Fxq "$k"; then
      ordered+="$k"$'\n'
    fi
  done <<< "$used_set"

  # 对每个 key，拼装元信息
  local items="[]"
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    # 查声明
    local decl
    decl=$(jq --arg k "$key" '.placeholders[$k] // null' "$tpl")
    local prompt kind required default_key default candidates
    if [[ "$decl" == "null" ]]; then
      # step 里出现但未声明：按 any + required 兜底（更安全的处理：视为必选）
      prompt="请填写 $key"
      kind="any"
      required="true"
      default_key="$key"
    else
      prompt=$(echo "$decl" | jq -r '.prompt // ""')
      kind=$(echo "$decl" | jq -r '.kind // "any"')
      # 用 if-then-else 而非 //，避免 false 被当作"缺省值"
      required=$(echo "$decl" | jq -r 'if has("required") then .required else true end')
      default_key=$(echo "$decl" | jq -r '.default_key // ""')
      [[ -z "$default_key" ]] && default_key="$key"
    fi

    default=$(echo "$defaults" | jq -r --arg k "$default_key" '.[$k] // ""')
    # 候选列表
    if [[ "$kind" == "any" ]]; then
      candidates='[]'
    else
      local cand_lines
      cand_lines=$(list_candidates "$kind" 2>/dev/null || true)
      candidates=$(echo "$cand_lines" | jq -R -s 'split("\n") | map(select(length > 0))')
    fi

    items=$(echo "$items" | jq \
      --arg name "$key" --arg prompt "$prompt" --arg kind "$kind" \
      --argjson required "$required" --arg default_key "$default_key" \
      --arg default "$default" --argjson candidates "$candidates" \
      '. + [{name: $name, prompt: $prompt, kind: $kind, required: $required,
             default_key: $default_key, default: $default, candidates: $candidates}]')
  done <<< "$ordered"

  jq -n --argjson ph "$items" '{placeholders: $ph}'
}

# 根据模板的 placeholders 声明 + 本次 values，生成应回写到 defaults 的 key/value
# 用法: compute_defaults_update <template_file> <values_json>
compute_defaults_update() {
  local tpl="$1"
  local values="$2"
  jq --argjson vals "$values" '
    (.placeholders // {}) as $decl
    | [$decl | to_entries[] | {
        key: (.value.default_key // .key),
        value: ($vals[.key] // "")
      } | select(.value | length > 0)]
    | from_entries
  ' "$tpl"
}
