#!/usr/bin/env bash
# run_recipe.sh —— 执行一个 recipe
# 用法:
#   run_recipe.sh --recipe-id <id>        从 recipes 目录加载
#   run_recipe.sh --file <path>           直接从文件加载（用于调试）
#   [--dry-run]                           只打印将执行的命令，不真正调用
#
# 输出: summary JSON（每步结果 + 总体 ok + 耗时）
#
# Action → xiaodu-control-official 脚本映射:
#   try_scene       → trigger_scene.sh
#   control_iot     → control_iot.sh
#   speak           → speak.sh
#   control_xiaodu  → control_xiaodu.sh
#   push_resource   → push_resource.sh
#
# Params 转换规则:
#   recipe.steps[].params 是 key/value 对象
#   key 转 kebab-case 后前缀 "--"，value 作为参数值
#   例: { "device_name": "小度智能屏2", "text": "hi" }
#   →   --device-name "小度智能屏2" --text "hi"

set -u
source "$(dirname "$0")/_lib.sh"
ensure_dirs
require_jq

RECIPE_ID=""
RECIPE_FILE=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --recipe-id) RECIPE_ID="$2"; shift 2 ;;
    --file)      RECIPE_FILE="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)
      echo "Usage: run_recipe.sh (--recipe-id <id> | --file <path>) [--dry-run]"
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$RECIPE_ID" && -z "$RECIPE_FILE" ]]; then
  echo "ERROR: one of --recipe-id / --file is required" >&2; exit 1
fi

if [[ -n "$RECIPE_ID" && -z "$RECIPE_FILE" ]]; then
  RECIPE_FILE=$(recipe_file_by_id "$RECIPE_ID")
fi

if [[ ! -f "$RECIPE_FILE" ]]; then
  echo "ERROR: recipe file not found: $RECIPE_FILE" >&2; exit 4
fi

if ! validate_recipe_json "$RECIPE_FILE"; then
  echo "ERROR: recipe schema invalid" >&2; exit 11
fi

# 非 dry-run 时才要求依赖
if [[ "$DRY_RUN" -eq 0 ]]; then
  require_control_skill
fi

RECIPE_ID=$(jq -r '.id' "$RECIPE_FILE")
STEPS_N=$(jq '.steps | length' "$RECIPE_FILE")

# 毫秒级时间戳：优先 python3，其次 perl，最后退化到秒级并注明精度
now_ms() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time;print(int(time.time()*1000))'
  elif command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf("%d\n", time()*1000)'
  else
    echo $(( $(date +%s) * 1000 ))
  fi
}
_has_ms_clock=0
if command -v python3 >/dev/null 2>&1 || command -v perl >/dev/null 2>&1; then
  _has_ms_clock=1
fi

START_TS=$(now_ms)
RESULTS=()      # 每个元素是一个 step 的 JSON 结果
OVERALL_OK=1
STOP_BUCKETS=()  # 命中 on_success=stop_remaining_steps_in_same_bucket 的 bucket 列表

# snake_case → kebab-case
to_kebab() { printf '%s' "$1" | tr '_' '-'; }

# action → script 路径
script_for_action() {
  case "$1" in
    try_scene)      printf '%s' "${CONTROL_SCRIPTS}/trigger_scene.sh" ;;
    control_iot)    printf '%s' "${CONTROL_SCRIPTS}/control_iot.sh" ;;
    speak)          printf '%s' "${CONTROL_SCRIPTS}/speak.sh" ;;
    control_xiaodu) printf '%s' "${CONTROL_SCRIPTS}/control_xiaodu.sh" ;;
    push_resource)  printf '%s' "${CONTROL_SCRIPTS}/push_resource.sh" ;;
    *) return 1 ;;
  esac
}

for (( i=0; i<STEPS_N; i++ )); do
  step=$(jq ".steps[$i]" "$RECIPE_FILE")
  bucket=$(jq -r '.bucket // ""' <<<"$step")
  action=$(jq -r '.action // ""' <<<"$step")
  optional=$(jq -r '.optional // false' <<<"$step")
  on_success=$(jq -r '.on_success // ""' <<<"$step")

  # 检查 bucket 是否被 stop
  skipped_by_bucket=0
  for sb in "${STOP_BUCKETS[@]+"${STOP_BUCKETS[@]}"}"; do
    if [[ "$sb" == "$bucket" ]]; then skipped_by_bucket=1; break; fi
  done
  if [[ "$skipped_by_bucket" -eq 1 ]]; then
    RESULTS+=("$(jq -n --arg b "$bucket" --arg a "$action" '{bucket:$b, action:$a, ok:true, skipped:true, reason:"bucket_stopped_by_scene"}')")
    continue
  fi

  script=$(script_for_action "$action" || true)
  if [[ -z "$script" ]]; then
    msg="unsupported action: $action"
    RESULTS+=("$(jq -n --arg b "$bucket" --arg a "$action" --arg e "$msg" '{bucket:$b, action:$a, ok:false, error:$e}')")
    if [[ "$optional" != "true" ]]; then OVERALL_OK=0; break; fi
    continue
  fi

  # 组装 CLI 参数
  args=()
  # 特殊处理：try_scene 把 scene_name 放在 step 顶层（方便阅读）
  if [[ "$action" == "try_scene" ]]; then
    scene_name=$(jq -r '.scene_name // (.params.scene_name // "")' <<<"$step")
    [[ -n "$scene_name" ]] && args+=( "--scene-name" "$scene_name" )
    # 允许 params 覆盖 server
    server=$(jq -r '.params.server // ""' <<<"$step")
    [[ -n "$server" ]] && args+=( "--server" "$server" )
  else
    # 遍历 params 的 key/value，转为 --kebab-case value
    # 使用 jq 输出 tab 分隔的 key\tvalue 行
    while IFS=$'\t' read -r k v; do
      [[ -z "$k" ]] && continue
      kebab=$(to_kebab "$k")
      args+=( "--${kebab}" "$v" )
    done < <(jq -r '.params // {} | to_entries | .[] | "\(.key)\t\(.value)"' <<<"$step")
  fi

  # 构造可读命令串（仅用于日志/dry-run）
  cmd_str="$script"
  for a in "${args[@]}"; do cmd_str+=" $(printf '%q' "$a")"; done

  if [[ "$DRY_RUN" -eq 1 ]]; then
    RESULTS+=("$(jq -n --arg b "$bucket" --arg a "$action" --arg c "$cmd_str" '{bucket:$b, action:$a, ok:true, dry_run:true, cmd:$c}')")
    # dry-run 下 try_scene 视作成功，也触发 bucket stop
    if [[ "$action" == "try_scene" && "$on_success" == "stop_remaining_steps_in_same_bucket" ]]; then
      STOP_BUCKETS+=("$bucket")
    fi
    continue
  fi

  # 实际执行
  out_file=$(mktemp); err_file=$(mktemp)
  set +e
  bash "$script" "${args[@]}" >"$out_file" 2>"$err_file"
  rc=$?
  set -e
  stdout=$(cat "$out_file"); stderr=$(cat "$err_file")
  rm -f "$out_file" "$err_file"

  if [[ $rc -eq 0 ]]; then
    RESULTS+=("$(jq -n --arg b "$bucket" --arg a "$action" --arg c "$cmd_str" --arg o "$stdout" \
      '{bucket:$b, action:$a, ok:true, cmd:$c, stdout:$o}')")
    if [[ "$action" == "try_scene" && "$on_success" == "stop_remaining_steps_in_same_bucket" ]]; then
      STOP_BUCKETS+=("$bucket")
    fi
  else
    RESULTS+=("$(jq -n --arg b "$bucket" --arg a "$action" --arg c "$cmd_str" --arg e "$stderr" --argjson rc "$rc" \
      '{bucket:$b, action:$a, ok:false, cmd:$c, exit_code:$rc, error:$e}')")
    if [[ "$optional" != "true" ]]; then
      OVERALL_OK=0
      break
    fi
  fi
done

END_TS=$(now_ms)
DURATION=$(( END_TS - START_TS ))

# 拼装 summary
steps_json=$(printf '%s\n' "${RESULTS[@]+"${RESULTS[@]}"}" | jq -s '.')
SUMMARY=$(jq -n \
  --arg id "$RECIPE_ID" \
  --argjson ok "$OVERALL_OK" \
  --argjson dur "$DURATION" \
  --argjson has_ms "$_has_ms_clock" \
  --argjson steps "$steps_json" \
  '{
    recipe_id: $id,
    ok: ($ok==1),
    duration_ms: $dur,
    duration_precision: (if $has_ms==1 then "ms" else "s" end),
    steps: $steps
  }')

# 更新 stats.json（dry-run 不写）
if [[ "$DRY_RUN" -eq 0 ]]; then
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  TMP=$(mktemp)
  # 提取本次失败步骤
  failures=$(jq '[.steps[] | select(.ok == false) | {bucket, action, error: (.error // "")}]' <<<"$SUMMARY")
  jq --arg id "$RECIPE_ID" --arg now "$NOW" \
     --argjson ok "$OVERALL_OK" \
     --argjson fails "$failures" '
    .[$id] = (.[$id] // {triggered_count: 0}) |
    .[$id].triggered_count = ((.[$id].triggered_count // 0) + 1) |
    .[$id].last_triggered_at = $now |
    .[$id].last_success = ($ok == 1) |
    .[$id].last_failures = $fails
  ' "$STATS_FILE" > "$TMP" && mv "$TMP" "$STATS_FILE"
fi

printf '%s\n' "$SUMMARY"
# 返回非 0 exit 以便上层感知失败（但 summary 已输出）
if [[ "$OVERALL_OK" -ne 1 ]]; then exit 30; fi
exit 0
