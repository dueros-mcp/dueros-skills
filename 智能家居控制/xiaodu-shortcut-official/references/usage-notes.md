# Usage Notes

## 这个 skill 解决什么问题

生态里可能会存在一些专用场景 skill（例如睡前、起床、观影、离家、起夜等有固定行业语义的场景），它们覆盖了一些**典型**家庭场景。但每个家庭的生活节奏、设备布局、偏好都不同：

- 有人想做"学习模式"、"工作模式"、"番茄钟"
- 有人想做"做饭模式"、"吃饭模式"、"洗碗模式"
- 有人想做"派对模式"、"K 歌模式"
- 有人想做"孩子写作业"、"阅读时间"

把这些都做成 official skill 不现实。`xiaodu-shortcut` 让用户**自己**定义：
- 一句快捷指令（含别名）
- 一串具体的动作（IoT + 智能屏）

下次说这句话，Agent 就按 recipe 执行。

## 什么时候用本 skill

- ✓ 用户自定义的、个人化的家庭场景
- ✓ 固定组合的 IoT 动作 + 播报
- ✓ 需要精准触发（每次结果一致）

## 什么时候不用本 skill

- ✗ 通用意图可直接调 `xiaodu-control-official` 的（"关客厅灯"、"把空调调到 24 度"）—— 让底层 skill 处理
- ✗ 语义明显属于某个常见预设场景且上层 Agent 注册了对应专用 skill（见 `routing-rules.md`）—— 让位
- ✗ 一次性的、不会重复的请求 —— 不必创建 recipe

## 典型工作流

### 工作流 0：从模板快速开始（推荐首次使用）

如果你从零开始不知道怎么写 recipe，可以直接导入内置模板。模板现在用占位符设计，导入时必须填真实设备名。

```bash
SH=xiaodu-shortcut-official/scripts

# 1. 看一下有哪些模板
bash $SH/list_templates.sh | jq

# 2. 拿模板的占位符元信息（Agent 用这个询问用户）
bash $SH/import_template.sh --template pomodoro --describe | jq
# 输出大致：
# {"placeholders":[
#   {"name":"tv","prompt":"...","kind":"iot_device",
#    "required":true,"candidates":["客厅电视",...],"default":""},
#   {"name":"spot_light","prompt":"...","kind":"iot_device",
#    "required":false,"candidates":[...],"default":""},
#   {"name":"smart_screen","prompt":"...","kind":"smart_screen",
#    "required":true,"candidates":[...],"default":""}
# ]}

# 3. 带值导入
bash $SH/import_template.sh --template pomodoro \
  --values-json '{"tv":"客厅电视","spot_light":"","smart_screen":"小度智能屏2"}'

# 4. dry-run 预览（不保存）
bash $SH/import_template.sh --template pomodoro \
  --values-json '{...}' --dry-run | jq

# 冲突时可改 id / primary / 清 aliases
bash $SH/import_template.sh --template pomodoro \
  --values-json '{...}' \
  --override-id my-pomodoro --override-primary "我的番茄钟" --clear-aliases
```

占位符规则：
- `required=true` 不填 → 脚本 exit 40（缺必填）
- `required=false` 留空 → 带 `skip_if_placeholder_empty` 的 step 被整段丢弃，其它 step 里的占位符保持空字符串
- 填过的值会记到 `~/.openclaw/workspace/memory/xiaodu-shortcut/placeholder-defaults.json`，下次导入其他模板时按 `default_key` 匹配自动回填到 `default` 字段供参考（用 `--no-defaults` 关闭此行为）

模板文件位于 `references/recipe-templates/`，当前提供：
- `study-mode.json`  学习模式
- `pomodoro.json`    番茄钟
- `party-time.json`  派对时间

详见 `references/placeholder-kinds.md`（kind → 候选来源映射）。

### 工作流 A：创建 recipe

用户说的可能是：
- "帮我记一个快捷指令..."
- "以后我说 XXX 就..."
- "定义一个场景..."

Agent 的对话骨架：
1. 确认主触发词："下次你说什么话时触发？"
2. 询问别名："还有别的说法吗？没有也没关系。"
3. 询问每个动作（逐个追问设备/参数）
4. 展示生成的 JSON：
   ```
   【预览】
   - 触发词：XXX（别名：YYY/ZZZ）
   - 步骤 1：把 AAA 灯打开
   - 步骤 2：把 BBB 电视关闭
   - 步骤 3：小度智能屏2 播报"..."
   确认保存？
   ```
5. 调 `save_recipe.sh --stdin` 写入
6. 播报"已记住"

### 工作流 B：触发执行

```
Agent 收到 query
  → match_recipe.sh --query "..."
  → 精确命中 → run_recipe.sh --recipe-id <id>
  → 读 summary → 汇报
```

### 工作流 C：查看 / 修改 / 删除

- 列出："我有哪些快捷指令？" → `list_recipes.sh`
- 查看单个："学习模式那个快捷指令怎么配的？" → `get_recipe.sh --id study-mode`
- 删除："删掉学习模式这个快捷指令" → `delete_recipe.sh --id study-mode`
- 修改：实际上是"读出来 → 修改 JSON → save_recipe 覆盖"。Agent 可以拉下来让用户改哪里，然后 save 即可（save 会保留 `created_at`）

## 与 xiaodu-control-official 的依赖

本 skill 的所有 `run_recipe` 都走这些脚本（不重做）：

```
xiaodu-control-official/scripts/
├── trigger_scene.sh        ← try_scene
├── control_iot.sh          ← control_iot
├── speak.sh                ← speak
├── control_xiaodu.sh       ← control_xiaodu
└── push_resource.sh        ← push_resource
```

未安装 `xiaodu-control-official` 时：
- 只能用 `list_recipes / get_recipe / save_recipe / delete_recipe`（CRUD 不依赖底层）
- `run_recipe.sh` 会 `exit 3` 并报错
- `run_recipe.sh --dry-run` 仍可用（只拼接命令不执行）

## 设备名一致性

创建 recipe 时**务必**让用户用真实设备名（跑 `list_iot_devices.sh` / `list_devices.sh` 拿到的名字）。

不一致会导致：
- `control_iot` 直接失败，错误信息"设备不存在"
- `speak` / `control_xiaodu` 路由不到具体小度设备

Agent 在创建向导里的最佳实践：
- 先列出当前家里的 IoT 设备 / 智能屏设备
- 让用户从列表里选，而不是自由输入
- 对用户描述（"客厅的那盏大灯"）做一次语义映射确认

## 偏好与使用统计

`stats.json` 每个 recipe 维护：
```json
{
  "study-mode": {
    "triggered_count": 12,
    "last_triggered_at": "2026-05-06T10:00:00Z",
    "last_success": true,
    "last_failures": []
  }
}
```

使用场景：
- 用户问"我最常用的快捷指令"/"最近用过什么" → 读这里
- ambiguous 匹配时选"最近使用"作为默认建议
- 排查问题："上次失败在哪一步" → 读 `last_failures`

## 常见坑

| 问题 | 原因 | 解决 |
|-----|------|-----|
| `save_recipe.sh` 拒绝保存，提示 trigger 冲突 | 触发词已被其他 recipe 占用 | 换一个触发词，或先 delete 另一个 |
| `run_recipe.sh` 某步失败 | 底层脚本返回非 0（通常是设备不存在或 mcporter 未启动） | 看 summary 的 `steps[].error`；修正设备名或启动 mcporter |
| match_recipe 总是精确命中不了 | trigger 里有标点或额外空格 | 规范化只处理大小写 + trim，不处理标点；建议触发词不带标点 |
| Agent 让位过度积极 | 非专用语义也被判为"类似睡前" | 让用户改一个不带让位关键词的 primary，或直接用精确命中（例：把 primary 写全"开始我的特殊睡前计划"） |

## 调试

- 手动跑 match：`bash scripts/match_recipe.sh --query "开始学习模式" | jq`
- 手动 dry-run：`bash scripts/run_recipe.sh --recipe-id study-mode --dry-run | jq`
- 直接编辑 recipe：`~/.openclaw/workspace/memory/xiaodu-shortcut/recipes/<id>.json`（手工改完无需触发任何同步）
- 清空统计：`echo '{}' > ~/.openclaw/workspace/memory/xiaodu-shortcut/stats.json`

## 校验已存在的 recipe（verify_recipe.sh）

用户改了设备名、换了智能屏、或怀疑某个 recipe 跑不动时，用 `verify_recipe.sh` 扫一遍，不跑真实动作：

```bash
bash scripts/verify_recipe.sh --id study-mode   | jq
bash scripts/verify_recipe.sh --all             | jq
bash scripts/verify_recipe.sh --file /tmp/r.json | jq  # 未落盘的 rendered recipe 也可
```

输出结构：
```json
{
  "ok": false,
  "backends": {"iot_device":"available","smart_screen":"available","scene":"not_checked"},
  "recipes": [
    {"id":"study-mode","ok":false,
     "missing":[{"step_index":1,"bucket":"lights","action":"control_iot",
                 "kind":"iot_device","field":"device_name","value":"书房主灯"}],
     "warnings":[]}
  ]
}
```

Exit code：
- `0` 全部通过
- `50` 发现 missing（`ok=false`）→ Agent 提示用户改设备名或删掉该 recipe
- `51` 后端（`list_*`）不可用 → 无法判断，建议用户确认 xiaodu-control-official 是否正常

`backends` 里 `not_checked` 表示该 kind 没有 step 用到，没必要调底层查。
