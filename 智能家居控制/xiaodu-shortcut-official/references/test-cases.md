# Test Cases

覆盖 6 类核心场景。每条给出：**输入** / **期望行为** / **验证点**。

## 1. 严格命中执行

**输入**：用户已配 recipe `study-mode`（primary="开始学习模式"），说："开始学习模式"

**期望行为**：
1. `match_recipe.sh --query "开始学习模式"` → `matched:true`, `recipe_id:"study-mode"`, `matched_trigger:"开始学习模式"`
2. Agent 不让位（即使这类 query 不属于 5 个专用场景也好）
3. `run_recipe.sh --recipe-id study-mode` 按 step 串行执行
4. 播报摘要

**验证点**：
- match 输出 `ambiguous` 字段不存在
- summary 的 `ok` 与所有 step 的 `ok` 一致
- `stats.json.study-mode.triggered_count` +1

## 2. 语义命中，需要用户确认

**输入**：recipe `study-mode` 存在，description="进入专注学习"；用户说："进入专注状态"

**期望行为**：
1. `match_recipe.sh` 返回 `matched:false`, `candidates` 含 study-mode
2. Agent 识别 "进入专注状态" ≈ "进入专注学习"
3. Agent 询问用户："你是想触发『学习模式』吗？"
4. 用户确认后执行 `run_recipe.sh --recipe-id study-mode`

**验证点**：
- 不绕过用户确认
- 用户否认时不执行，询问是否创建新 recipe

## 3. 创建向导（对话式）

**输入**：用户说："以后我说『番茄钟』就关电视、关客厅射灯"

**期望行为**：
1. Agent 走创建向导
2. 补齐 id / name / primary / aliases / steps
3. 展示 JSON 预览
4. `save_recipe.sh --stdin` 接收 JSON
5. 保存成功返回 `{ok:true, id:"pomodoro", action:"created", path:"..."}`

**验证点**：
- `recipes/pomodoro.json` 文件存在且 schema 合法
- `created_at` 与 `updated_at` 已注入
- `schema_version = "1"`

## 4. 触发词冲突检测

**输入**：已有 recipe `a` 的 primary="开始工作"；用户要创建 recipe `b`，alias 中也含"开始工作"

**期望行为**：
- `save_recipe.sh` 退出码 20
- stderr 打印 `trigger '开始工作' conflicts with existing recipe 'a'`
- `recipes/b.json` 不被创建

**验证点**：
- 冲突检测忽略大小写和首尾空白
- 若 save 的是同 id 的更新，自身的 trigger 不视为冲突

## 5. 路由让位（与生态其他编排 skill 解耦）

### 5.1 让位成功
**输入**：用户说："带孩子睡觉"；本 skill 无任何 recipe 与之精确命中

**期望行为**：
- Agent 检查 `match_recipe` 未精确命中
- 判定属于"睡前"类常见预设场景语义 → 本 skill 退出竞争，交回上层 Agent（由上层决定路由到哪个专用 skill 或回落）
- **不调用** `run_recipe.sh`

### 5.2 让位例外：用户有精确匹配
**输入**：用户 recipe `my-bed` 的 primary="带孩子睡觉"；用户说："带孩子睡觉"

**期望行为**：
- `match_recipe` 精确命中 my-bed
- **不让位**，执行 `run_recipe.sh --recipe-id my-bed`

## 6. 依赖缺失与异常

### 6.1 xiaodu-control-official 缺失
**输入**：跑 `run_recipe.sh --recipe-id study-mode`（非 dry-run），但 `xiaodu-control-official/scripts/control_iot.sh` 不存在

**期望**：退出码 3，stderr 提示缺失依赖；summary 未输出

### 6.2 jq 缺失
**输入**：任何脚本执行

**期望**：退出码 2，stderr 提示安装 jq

### 6.3 recipe JSON 损坏
**输入**：`recipes/broken.json` 不是合法 JSON

**期望**：
- `list_recipes.sh` 整体行为需要健壮：允许返回已有的合法 recipe（当前实现会让 jq -s 在遇到损坏文件时失败 —— 测试用例用于确认此 trade-off，必要时可后续迭代改为逐个跳过）
- `match_recipe.sh` 对损坏文件打 WARN 并跳过，不影响其他匹配

### 6.4 step 中途失败（optional=false）
**输入**：recipe 的 step 2 是 `control_iot`，设备名错误；step 2 `optional=false`

**期望**：
- step 1 `ok:true`，step 2 `ok:false`，step 3 及之后不执行
- summary 的 `ok:false`
- `stats.last_success = false`, `last_failures` 含 step 2

### 6.5 step 失败但 optional=true
**输入**：同上但 step 2 `optional=true`

**期望**：
- step 2 `ok:false`，step 3+ 继续执行
- 若后续 step 全部成功，summary `ok:true`

### 6.6 try_scene 成功 + bucket stop
**输入**：step 1 `try_scene`（scene 存在） + `on_success=stop_remaining_steps_in_same_bucket`，step 2/3 同 bucket 的 `control_iot`

**期望**：
- step 1 `ok:true`
- step 2/3 `skipped:true, reason:"bucket_stopped_by_scene"`
- 其他 bucket 的 step 正常执行

## 7. 模板占位符

### 7.1 --describe 返回填槽元信息
**输入**：`import_template.sh --template pomodoro --describe`

**期望**：
- 输出 JSON 含 `placeholders` 数组
- 每项含 `name/prompt/kind/required/candidates/default/default_key`
- `required=true` 的条目至少包含 `tv` / `smart_screen`
- 候选列表来自 `list_iot_devices.sh` / `list_devices.sh`（后端不可用时 `candidates:[]`，不报错）

### 7.2 带值导入 + 回写 defaults
**输入**：
```bash
import_template.sh --template pomodoro \
  --values-json '{"tv":"客厅电视","spot_light":"客厅射灯","smart_screen":"小度智能屏2"}'
```

**期望**：
- `recipes/pomodoro.json` 生成，其中所有 `{{...}}` 已被替换
- 最终 recipe 不包含 `placeholders` 字段、step 上不再有 `skip_if_placeholder_empty`
- `placeholder-defaults.json` 被更新：`{"living_room_tv":"客厅电视", "spot_light":"客厅射灯", "smart_screen":"小度智能屏2"}`（key 来自每个占位符的 `default_key`）

### 7.3 可选占位符留空 → step 被丢弃
**输入**：
```bash
import_template.sh --template pomodoro \
  --values-json '{"tv":"客厅电视","spot_light":"","smart_screen":"小度智能屏2"}'
```

**期望**：
- 最终 recipe 的 `steps` 数组少了一条（spot_light 对应的那条带 `skip_if_placeholder_empty:"spot_light"`）
- 不因 `spot_light` 留空而 exit 40；退出 0

### 7.4 必填占位符缺失 → exit 40
**输入**：
```bash
import_template.sh --template pomodoro \
  --values-json '{"spot_light":"","smart_screen":"小度智能屏2"}'   # 缺 tv
```

**期望**：
- 退出码 40
- stderr 出现 `required placeholder '{{tv}}' is missing`
- `recipes/pomodoro.json` 未创建

### 7.5 --dry-run 不落盘
**输入**：`import_template.sh --template pomodoro --values-json '{...}' --dry-run`

**期望**：
- stdout 直接输出渲染后的 recipe JSON
- `recipes/` 目录没有新增文件
- `placeholder-defaults.json` 没有被更新

### 7.6 defaults 跨模板复用
**前置**：7.2 已执行过（defaults 含 smart_screen）

**输入**：`import_template.sh --template party-time --describe`

**期望**：响应里 `smart_screen` 占位符的 `default` 字段 = "小度智能屏2"；Agent 可以提示"还是用上次的小度智能屏2吗？"

## 8. verify_recipe

### 8.1 引用不存在设备
**输入**：recipe `study-mode` 中 step `control_iot` 的 `device_name="不存在的灯"`；`list_iot_devices.sh` 返回不含这个名字

**期望**：
- `verify_recipe.sh --id study-mode` 退出 50
- 输出 JSON `ok:false`，`recipes[0].missing` 含该 step 的 `{kind:"iot_device", value:"不存在的灯"}`

### 8.2 后端不可用
**输入**：`xiaodu-control-official/scripts/list_iot_devices.sh` 不可执行

**期望**：
- 退出 51
- `backends.iot_device` = `"unavailable"`
- 该类型的 step 归入 `warnings`（不归入 `missing`）

### 8.3 未渲染占位符残留
**输入**：某个手工编辑过的 recipe 还带 `{{tv}}`（不该发生，但要防御）

**期望**：`warnings` 中有 `"unrendered placeholder"` 提示

## 如何手动跑这些用例

由于 xiaodu-control 的底层要求 mcporter + 真实设备，推荐：
1. 对 **1、2、4、5** 用例：只测 `match_recipe.sh` + `save_recipe.sh` 即可，不需真实设备
2. 对 **3** 用例：跑 `save_recipe.sh --stdin` 并检查文件
3. 对 **6** 用例：大量用例用 `run_recipe.sh --dry-run` 验证命令拼接；真正的执行失败可在 recipe 里故意写个不存在的设备名，跑非 dry-run 验证
4. 对 **7** 用例：`--describe` 和 `--dry-run` 纯本地可测；候选列表依赖 `xiaodu-control-official`，未安装时 `candidates:[]` 即可
5. 对 **8** 用例：改动 recipe 文件或给 `list_iot_devices.sh` 加权限位模拟 unavailable
