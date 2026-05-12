#!/usr/bin/env bash
# verify_recipe.sh —— 检查 recipe 引用的设备/场景是否仍然存在
# 用法:
#   verify_recipe.sh --id <recipe-id>     # 校验单个
#   verify_recipe.sh --all                # 校验全部
#   verify_recipe.sh --file <path>        # 从文件（未落盘的 rendered recipe 也可）
#
# 输出 JSON:
#   {
#     "ok": false,
#     "backends": {"iot_device": "available", "smart_screen": "unavailable", "scene": "available"},
#     "recipes": [
#       {"id":"...", "ok": false,
#        "missing": [{"step_index":2, "bucket":"lights", "action":"control_iot",
#                     "kind":"iot_device", "field":"device_name", "value":"客厅落地灯"}],
#        "warnings": [...]
#       }
#     ]
#   }
#
# Exit codes:
#   0   全部通过
#   50  发现缺失（有 missing）
#   51  后端（list_* 脚本）不可用，无法校验
#   4   recipe 不存在
#   11  recipe schema 非法

set -eu
source "$(dirname "$0")/_lib.sh"
ensure_dirs
require_jq

ID=""
ALL=0
FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)   ID="$2"; shift 2 ;;
    --all)  ALL=1; shift ;;
    --file) FILE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ID" && "$ALL" -eq 0 && -z "$FILE" ]]; then
  echo "ERROR: one of --id / --all / --file is required" >&2; exit 1
fi

# --- 预取后端列表（懒加载，失败时标 unavailable）---
_iot_names=""
_iot_state="unknown"
_scr_names=""
_scr_state="unknown"
_scene_names=""
_scene_state="unknown"

run_list() {
  local kind="$1" script="$2"
  local out rc
  if [[ -z "$CONTROL_SCRIPTS" || ! -x "$script" ]]; then
    echo "__UNAVAILABLE__"
    return
  fi
  if ! out=$(bash "$script" 2>/dev/null); then
    echo "__UNAVAILABLE__"
    return
  fi
  # 抽取 name 列表（保持与 _placeholder_lib.sh list_candidates 的解析一致）
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

load_backend() {
  local kind="$1"
  case "$kind" in
    iot_device)
      if [[ "$_iot_state" == "unknown" ]]; then
        _iot_names=$(run_list iot_device "${CONTROL_SCRIPTS}/list_iot_devices.sh")
        if [[ "$_iot_names" == "__UNAVAILABLE__" ]]; then _iot_state="unavailable"; _iot_names=""
        else _iot_state="available"; fi
      fi ;;
    smart_screen)
      if [[ "$_scr_state" == "unknown" ]]; then
        _scr_names=$(run_list smart_screen "${CONTROL_SCRIPTS}/list_devices.sh")
        if [[ "$_scr_names" == "__UNAVAILABLE__" ]]; then _scr_state="unavailable"; _scr_names=""
        else _scr_state="available"; fi
      fi ;;
    scene)
      if [[ "$_scene_state" == "unknown" ]]; then
        _scene_names=$(run_list scene "${CONTROL_SCRIPTS}/list_scenes.sh")
        if [[ "$_scene_names" == "__UNAVAILABLE__" ]]; then _scene_state="unavailable"; _scene_names=""
        else _scene_state="available"; fi
      fi ;;
  esac
}

backend_has() {
  local kind="$1" value="$2"
  load_backend "$kind"
  local names state
  case "$kind" in
    iot_device)   names="$_iot_names"; state="$_iot_state" ;;
    smart_screen) names="$_scr_names"; state="$_scr_state" ;;
    scene)        names="$_scene_names"; state="$_scene_state" ;;
    *) echo "available:true"; return ;;
  esac
  if [[ "$state" == "unavailable" ]]; then
    echo "unavailable"; return
  fi
  if echo "$names" | grep -Fxq "$value"; then
    echo "available:true"
  else
    echo "available:false"
  fi
}

# --- 按 action 推断要校验的字段 ---
# 返回多行: kind<TAB>field<TAB>value
#
# 底层脚本的参数约定（run_recipe.sh 会把 params.key 按 snake_case→kebab-case 转成 --key value）：
#   control_iot      → --device        (params.device,       applianceName)
#   speak            → --device-name   (params.device_name,  客户端 cuid)
#   control_xiaodu   → --device-name
#   push_resource    → --device-name
#   try_scene        → --scene-name    (step.scene_name 或 params.scene_name)
fields_to_check() {
  local step_json="$1"
  local action bucket
  action=$(jq -r '.action // ""' <<<"$step_json")
  bucket=$(jq -r '.bucket // ""' <<<"$step_json")
  case "$action" in
    try_scene)
      local sn
      sn=$(jq -r '.scene_name // (.params.scene_name // "")' <<<"$step_json")
      [[ -n "$sn" ]] && printf 'scene\tscene_name\t%s\n' "$sn"
      ;;
    control_iot)
      # 主字段是 params.device（对应 --device → applianceName）
      local dn
      dn=$(jq -r '.params.device // (.params.device_name // "")' <<<"$step_json")
      [[ -n "$dn" ]] && printf 'iot_device\tdevice\t%s\n' "$dn"
      ;;
    speak|control_xiaodu|push_resource)
      local dn
      dn=$(jq -r '.params.device_name // ""' <<<"$step_json")
      [[ -n "$dn" ]] && printf 'smart_screen\tdevice_name\t%s\n' "$dn"
      ;;
  esac
}

# --- 校验单个 recipe 文件 ---
# 返回 JSON string
verify_one_file() {
  local f="$1"
  if ! validate_recipe_json "$f" 2>/dev/null; then
    jq -n --arg f "$f" '{id:"", ok:false, error:"schema invalid", file:$f}'
    return
  fi
  local id steps_n missing warnings
  id=$(jq -r '.id' "$f")
  steps_n=$(jq '.steps | length' "$f")
  missing="[]"
  warnings="[]"

  for (( i=0; i<steps_n; i++ )); do
    local step bucket action
    step=$(jq ".steps[$i]" "$f")
    bucket=$(jq -r '.bucket // ""' <<<"$step")
    action=$(jq -r '.action // ""' <<<"$step")
    # 若带 {{...}} 直接告警（说明 recipe 未完成渲染；不应发生）
    if echo "$step" | jq -r 'tostring' | grep -qE '\{\{[a-zA-Z_][a-zA-Z0-9_]*\}\}'; then
      warnings=$(echo "$warnings" | jq --argjson idx "$i" --arg b "$bucket" --arg a "$action" \
        '. + [{step_index:$idx, bucket:$b, action:$a, warning:"unrendered placeholder"}]')
    fi
    while IFS=$'\t' read -r kind field value; do
      [[ -z "$kind" ]] && continue
      local res
      res=$(backend_has "$kind" "$value")
      case "$res" in
        unavailable)
          warnings=$(echo "$warnings" | jq \
            --argjson idx "$i" --arg b "$bucket" --arg a "$action" \
            --arg k "$kind" --arg fld "$field" --arg v "$value" \
            '. + [{step_index:$idx, bucket:$b, action:$a, kind:$k, field:$fld, value:$v, warning:"backend unavailable, skipped"}]')
          ;;
        available:false)
          missing=$(echo "$missing" | jq \
            --argjson idx "$i" --arg b "$bucket" --arg a "$action" \
            --arg k "$kind" --arg fld "$field" --arg v "$value" \
            '. + [{step_index:$idx, bucket:$b, action:$a, kind:$k, field:$fld, value:$v}]')
          ;;
      esac
    done < <(fields_to_check "$step")
  done

  local ok=true
  if [[ "$(echo "$missing" | jq 'length')" -gt 0 ]]; then ok=false; fi
  jq -n --arg id "$id" --argjson ok "$ok" --argjson m "$missing" --argjson w "$warnings" \
    '{id:$id, ok:$ok, missing:$m, warnings:$w}'
}

# --- 选择要校验的文件列表 ---
TARGETS=()
if [[ -n "$FILE" ]]; then
  [[ -f "$FILE" ]] || { echo "ERROR: file not found: $FILE" >&2; exit 4; }
  TARGETS+=("$FILE")
elif [[ -n "$ID" ]]; then
  f=$(recipe_file_by_id "$ID")
  [[ -f "$f" ]] || { echo "ERROR: recipe '$ID' not found" >&2; exit 4; }
  TARGETS+=("$f")
else
  shopt -s nullglob
  for f in "$RECIPES_DIR"/*.json; do
    TARGETS+=("$f")
  done
fi

RESULTS="[]"
# 预扫描所有 target 文件中实际涉及的 kind，在主 shell 里 warm-up backend 状态
# （避免 $() 子 shell 中的状态丢失，使最终 backends 报告真实）
for f in "${TARGETS[@]+"${TARGETS[@]}"}"; do
  while IFS= read -r action; do
    case "$action" in
      try_scene)      load_backend scene ;;
      control_iot)    load_backend iot_device ;;
      speak|control_xiaodu|push_resource) load_backend smart_screen ;;
    esac
  done < <(jq -r '.steps[]? | .action // empty' "$f" 2>/dev/null)
done

for f in "${TARGETS[@]+"${TARGETS[@]}"}"; do
  r=$(verify_one_file "$f")
  RESULTS=$(echo "$RESULTS" | jq --argjson r "$r" '. + [$r]')
done

# 预热各 backend 状态字段（即便没被用到也尝试一次，便于调用方观察）
# 为避免无意义调用，只在 state 已被访问过时报告；unknown 视为 not_checked
fmt_state() {
  local s="$1"
  case "$s" in
    unknown) echo "not_checked" ;;
    *) echo "$s" ;;
  esac
}

BACKENDS=$(jq -n \
  --arg iot "$(fmt_state "$_iot_state")" \
  --arg scr "$(fmt_state "$_scr_state")" \
  --arg sc  "$(fmt_state "$_scene_state")" \
  '{iot_device:$iot, smart_screen:$scr, scene:$sc}')

ANY_MISSING=$(echo "$RESULTS" | jq '[.[] | select(.ok == false)] | length')
ANY_BACKEND_UNAVAIL=0
if [[ "$_iot_state$_scr_state$_scene_state" =~ (unknown|unavailable) ]]; then
  # 任一被访问过的 backend 是 unavailable → 标记无法完全判断
  if echo "$_iot_state $_scr_state $_scene_state" | grep -q "unavailable"; then
    ANY_BACKEND_UNAVAIL=1
  fi
fi

OK=true
[[ "$ANY_MISSING" -gt 0 ]] && OK=false

jq -n --argjson ok "$OK" --argjson b "$BACKENDS" --argjson r "$RESULTS" \
  '{ok:$ok, backends:$b, recipes:$r}'

if [[ "$ANY_MISSING" -gt 0 ]]; then exit 50; fi
if [[ "$ANY_BACKEND_UNAVAIL" -eq 1 ]]; then exit 51; fi
exit 0
