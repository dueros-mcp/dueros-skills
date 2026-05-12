# Exit Codes

所有脚本使用统一的退出码约定，方便上层 Agent / 调用方按错误类型分发处理。

## 通用约定

| 退出码 | 含义 | 典型场景 |
|-------|-----|---------|
| `0` | 成功 | 正常完成 |
| `1` | 参数错误 | 缺少必选参数、未知参数 |
| `2` | 基础依赖缺失 | `jq` 未安装 |
| `3` | 底层 skill 依赖缺失 | `xiaodu-control-official` 未找到或脚本不可执行 |
| `4` | 资源不存在 | recipe / template 对应的文件不存在 |

## Recipe 操作相关

| 退出码 | 出自脚本 | 含义 |
|-------|---------|-----|
| `10` | `save_recipe.sh` | JSON 非法（无法被 jq 解析） |
| `11` | `save_recipe.sh` / `run_recipe.sh` | Schema 校验失败（缺 id / 非法 kebab-case / 缺 name / 缺 primary / steps 为空） |
| `12` | `_lib.sh::validate_recipe_json` | `id` 非法 kebab-case |
| `13` | `_lib.sh::validate_recipe_json` | `name` 为空 |
| `14` | `_lib.sh::validate_recipe_json` | `triggers.primary` 为空 |
| `15` | `_lib.sh::validate_recipe_json` | `steps` 为空 |
| `20` | `save_recipe.sh` / `import_template.sh`（间接） | 触发词冲突（primary/alias 与其他 recipe 重合） |

> ⚠️ 当前 `save_recipe.sh` / `run_recipe.sh` 对 schema 错误**统一退出 11**（10 也会被合并），10/12–15 只有直接调 `_lib.sh::validate_recipe_json` 时能拿到。上层 Agent 拿到 11 时应从 stderr 的 `ERROR: ...` 行读具体原因，不要期待精细化退出码。

## 执行相关

| 退出码 | 出自脚本 | 含义 |
|-------|---------|-----|
| `30` | `run_recipe.sh` | recipe 已执行但中途失败（非 optional 的 step 报错）。summary JSON 仍会正常输出到 stdout，供 Agent 读详细错误 |
| `40` | `import_template.sh` | 缺少**必选**占位符的值（required=true 的占位符 values 里没给或为空） |
| `41` | `import_template.sh` | 存在未知占位符（step 里有 `{{x}}` 但 placeholders 段未声明、values 里也没给，且没有 `skip_if_placeholder_empty` 兜底） |
| `50` | `verify_recipe.sh` | recipe 校验发现 missing 设备/场景（脚本不失败，只是告知） |
| `51` | `verify_recipe.sh` | **任一** list 后端不可用（xiaodu-control-official 缺失、脚本非可执行、或运行时报错），无法完全判断；没有 missing 时才会走到 51 |

> `run_recipe.sh --dry-run` 永远不会返回 30（不真正执行）。

## 分发建议（Agent 侧）

Agent 根据退出码可做以下路由：

- `0` → 读 stdout 作为主要信号
- `1` → 脚本使用错误，记日志
- `2` → 让用户 `brew install jq`
- `3` → 让用户检查 `xiaodu-control-official` 是否安装在 skill 同级目录
- `4` → recipe/template 不存在；建议跑 `list_recipes.sh` / `list_templates.sh` 确认
- `10–15` → Schema 错误；实操中 `save_recipe.sh` / `run_recipe.sh` 只会透出 11，具体原因读 stderr（如 `missing .triggers.primary`、`invalid .id 'Foo_Bar' (must be kebab-case)`）
- `20` → 触发词冲突；提示用户换一个触发词，或建议用 `--override-*` 参数（仅 `import_template.sh`）
- `30` → 执行失败；从 stdout 的 summary 读 `steps[].error` 指名道姓地汇报
- `40` → 必选占位符没填，提示用户补全
- `41` → 模板占位符用法不规范；让用户报告 / 报 bug
- `50` → recipe 有设备缺失，读 stdout 的 `missing` 字段建议用户修正 recipe 或检查设备名
- `51` → 任一底层 list 后端不可用（常见原因：`xiaodu-control-official` 未安装 / mcporter 未启动 / 对应 list 脚本运行报错）；读 stdout 的 `backends` 字段可知哪一类后端挂了，其他类仍已被校验

## stderr 约定

- 所有错误都打到 stderr
- 格式：`ERROR: ...`（硬错误）/ `WARN: ...`（可忽略警告，如损坏 JSON 跳过）
- 成功路径不往 stderr 写东西

因此 Agent 调用时推荐分离 stdout / stderr：

```bash
out=$(bash scripts/match_recipe.sh --query "..." 2>/tmp/err)
rc=$?
if [[ $rc -ne 0 ]]; then
  cat /tmp/err >&2
else
  echo "$out" | jq '...'
fi
```

**不要**用 `2>&1` 合流，否则 WARN 会污染 JSON 输出。
