---
name: xiaodu-shortcut
description: 用户自定义家庭场景编排与快捷指令触发。基于 xiaodu-control-official 的底层能力，让用户用一句自己起的快捷指令（如"开始学习模式"、"番茄钟"、"派对时间"、"做饭模式"、"阅读时间"等）触发一套自己编排好的 IoT + 智能屏组合动作。也响应对快捷指令的元命令："设置/创建快捷指令"、"修改快捷指令"、"删除快捷指令"、"我有哪些快捷指令"、以及显式调用 "快捷指令 X"等。
---

## 依赖与路由规则

### 强依赖
- **xiaodu-control-official**：所有底层设备控制、场景触发、智能屏播报都复用它的脚本。未安装时本 skill 无法执行，只能做 recipe 的增删查。
- `jq`：本 skill 脚本依赖 `jq` 解析 JSON。

### 让位原则（与其他编排 skill 解耦）

本 skill 的定位是 **"用户自定义快捷指令"**，不感知、不耦合任何具体的场景编排 skill。

- **让位判断交给上层 Agent**：上层 Agent 能看到当前注册的所有 skill description，知道哪些专用场景 skill 可用。本 skill 不在 SKILL.md 里硬编码"让位给 XXX"的清单。
- **本 skill 的自我约束**：当用户 query 语义明显属于某个**常见预设场景**（如睡前、起床、观影、离家、起夜等"名词即功能"的场景），且 `match_recipe.sh` **未精确命中**任何用户自定义 recipe 时，本 skill 不要抢路由，把决策权交回上层 Agent——让它决定是走其他专用 skill，还是继续本 skill 的创建向导。
- **例外（用户意图压倒一切）**：如果 `match_recipe.sh` 返回 `matched: true` 且 query 与某 recipe 的 primary / alias **精确命中**，说明用户已用自己定义的快捷指令说话，此时**不让位**，直接执行该快捷指令。

这条规则让本 skill 和生态里其他编排 skill 解耦：新增或移除任何专用场景 skill 都不需要改这里。

## 定位与核心原则

- **定位**：元 skill / 场景编排 skill，不是底层控制 skill。
- **不重做**：一切 IoT / 智能屏控制都通过 `xiaodu-control-official/scripts/*.sh` 间接完成。
- **结构化优先**：recipe 使用 JSON schema（见 `references/recipe-schema.md`），Agent 按 step 执行，不再做自然语言二次翻译。
- **严格匹配优先 + 语义 fallback**：先按触发词精确命中，未命中再做语义匹配并向用户确认。
- **防误控**：只按 recipe 声明的 step 执行，不擅自添加动作；未知设备调用失败不强行重试。

## 脚本清单

所有脚本在本 skill 的 `scripts/` 目录，输入输出均为 JSON，便于 Agent 解析：

| 脚本 | 作用 |
|------|------|
| `list_recipes.sh` | 列出所有已保存 recipe 索引 |
| `get_recipe.sh --id <id>` | 获取单个 recipe 完整 JSON |
| `save_recipe.sh --file <path>` / `--json <str>` / `--stdin` | 创建或更新 recipe（带 schema + 冲突校验） |
| `delete_recipe.sh --id <id>` | 删除 recipe + 清理 stats |
| `match_recipe.sh --query "<text>"` | 匹配触发词，输出 matched 结果或 candidates |
| `run_recipe.sh --recipe-id <id> [--dry-run]` | 执行 recipe，输出 step-by-step summary JSON |
| `list_templates.sh` | 列出内置模板（study-mode / pomodoro / party-time 等） |
| `import_template.sh --template <id> --describe` | 输出模板占位符元信息（含候选设备列表 + 历史默认值），供 Agent 询问用户 |
| `import_template.sh --template <id> --values-json '<json>'` | 带值导入：渲染占位符后保存为 recipe，并回写 `placeholder-defaults.json` |
| `import_template.sh --template <id> ... --dry-run` | 仅输出渲染后的 recipe，不保存 |
| `verify_recipe.sh --id <id>` / `--all` / `--file <path>` | 检查 recipe 引用的设备/场景是否仍存在；输出 missing/warnings |

数据存储路径（用户空间，随 skill 升级保留）：

```
~/.openclaw/workspace/memory/xiaodu-shortcut/
├── recipes/                    # 每个 recipe 一个 JSON 文件
├── placeholder-defaults.json   # 模板导入时用户填过的设备名/场景名，供下次复用
├── stats.json                  # 使用统计
└── README.md                   # 自动生成
```

## 首次使用 / 空库引导

**触发条件**：当 `list_recipes.sh` 返回 `[]`（空库），且用户语句属于以下任一情况时，Agent **必须走首次引导流程**：

- 用户意图是触发某个快捷指令（说了一句没命中任何专用 skill、也没命中任何 recipe 的话）
- 用户意图是创建快捷指令（"帮我记一个快捷指令…"、"以后我说 XXX 就…"）
- 用户主动问"这个 skill 怎么用 / 有什么快捷指令"

> **优先级提醒**：让位原则永远优先于首次引导。当 query 语义明显属于某个常见预设场景（睡前/起床/观影/离家/起夜等），即便空库也不进首次引导——由上层 Agent 决定路由。只有 query 不属于这类预设场景语义时才进来。

### 首次引导执行顺序（严格按序）

#### Step 0：依赖就绪检查（upfront，避免用户走完设置才翻车）

先探测 `xiaodu-control-official` 是否可用（下面命令假定 cwd 为 skills 仓库根目录；若不在，先 `cd` 到仓库根或把路径改成绝对路径）：

```bash
bash xiaodu-control-official/scripts/list_iot_devices.sh 2>/dev/null \
  | jq '(if type=="array" then . elif has("return") then .return else [] end) | length'
```

底层脚本输出可能是 `{"return":[...]}`（iot/scene）或顶层数组（smart screen），上面那行 jq 两种都能拿到真实设备数。分三种情况：

- 输出为正整数 → **就绪**，继续 Step 1
- 输出为 0 → 依赖脚本在，但**未绑定设备**，提示用户"小度账号下暂时没有 IoT 设备，建议先在小度 App 里添加设备再来配快捷指令"，询问是否仍要继续（继续的话候选列表会是空）
- 命令失败 / 输出为空 / 脚本不存在 → **依赖未就绪**，明确告知："这个 skill 依赖 `xiaodu-control-official`（底层 IoT/智能屏控制）。当前它不可用——可以创建和管理快捷指令，但**触发时不会真的执行动作**。要继续配置吗？"

Step 0 决定是否向用户展示"只能配置、不能执行"的预期，避免用户配完才发现跑不起来。

#### Step 1：按用户 query 语义推荐模板（非平铺）

拿 `list_templates.sh` 的结果，尝试用 query 去匹配模板的 `name` / `aliases` / `description`：

- **精确命中**（query 完全等于某模板的 primary 或 alias，normalize 后）：直接"你是想用内置的『{模板 name}』模板吗？" → 用户确认即进 Step 2
- **语义近似**（query 含有模板 name 的关键词，如 query="进入专注状态" ↔ study-mode.description "进入专注学习"）：优先推荐该模板 + 附带"如果不是，我这里还有 X 个其他模板"
- **无匹配**（如 query 是"帮我记一个快捷指令"这种纯创建意图）：平铺 3 个模板让用户选，或进 Step 3（从零创建）

#### Step 2：从模板导入（占位符式）

1. `import_template.sh --template <id> --describe` 拿占位符元信息 JSON（**声明顺序**，不是字母序）
2. 逐项询问用户，每个占位符的询问策略（按优先级判断）：
   - **优先 1：`default` 非空**（跨模板复用的历史值）→ "用上次填过的『{default}』吗？"，用户说"是/对/嗯"直接用；说"换一个"或"不是"再进下一档
   - **优先 2：`candidates` 非空** → 展示候选（默认展示前 5 个 + 总数），让用户选，不鼓励自由输入；`required=false` 时额外给"跳过"选项
   - **优先 3：`candidates` 为空且 Step 0 已告知降级** → "这里我查不到候选列表，请输入你家对应设备的完整名字（稍后会自动校验）"
   - **额外规则**：`required=false` 的占位符在最终 prompt 后要补一句**具体后果**。例：spot_light → "不填的话，番茄钟启动时就不动射灯这一块"；scene → "不填的话不会触发小度 App 里预设的场景，只执行下面几步"
3. 汇总 values JSON → `import_template.sh --template <id> --values-json '...'`
   - 退 40（缺必填）→ 从缺失字段重新问
   - 退 20（触发词冲突）→ "『{primary}』已经被『{other_id}』用了。你主触发词改叫什么？比如『我的{模板 name}』。" 拿到新触发词后加 `--override-primary` + `--override-id`（id 也跟着改，否则更新会覆盖现有 recipe）重试
4. **导入成功后立即 `verify_recipe.sh --id <新 id>`**（不问用户，默认就跑）：
   - 退 0 → "已导入『{name}』，下次说『{primary}』即可触发，要不要现在试一下？"
   - 退 50（missing）→ 提取 `recipes[0].missing[].value` 列出："有 N 个设备在你家设备列表里没找到：[列表]。要改一下吗？"（用户可改可接受带损保存）
   - 退 51（后端不可用）→ 仅在 Step 0 未发现不可用时才可能出现；提示"底层暂不可用，保存了但触发时可能失败"
5. 用户说"试一下" → `run_recipe.sh --recipe-id <id>`（Step 0 探测到不可用时改用 `--dry-run` 演示命令拼接，不真调用）

#### Step 3：从零创建（当 Step 1 用户明确说"没有合适的模板"）

进标准流程 step 4，但新手场景下 Agent 要**用具体问题而非 schema 术语**引导，见下方"创建向导对话骨架"。

### 非空库处理

`list_recipes.sh` 非空时：
- **不要重复播报欢迎语**
- 走标准执行流程（match → run / 创建向导）
- 用户主动问"这个 skill 怎么用" → 简短回答 + 列出当前已有的 recipe，不重跑首次引导

## 元命令识别（优先于标准执行流程）

用户说话含以下"快捷指令"显式词时，**不走语义匹配**，直接按元命令分发到对应操作。识别策略：query 里出现 "快捷指令" 或 "快捷词"（兼容旧叫法），且匹配下列动词模式之一：

| 用户可能说的话 | 动作 | 对应脚本 / 流程 |
|---------------|------|----------------|
| "设置一个快捷指令" / "创建一个快捷指令" / "记一个快捷指令" / "加一个快捷指令" | 进创建向导 | 跳到 [标准执行流程 step 4](#4-recipe-创建向导对话式) 或走 [首次引导 Step 1](#step-1按用户-query-语义推荐模板非平铺) |
| "修改 XX 快捷指令" / "改一下 XX 快捷指令" | 更新已有 recipe | `get_recipe.sh --id <id>` → 询问改哪部分（触发词 / steps / 别名）→ 改后 `save_recipe.sh --stdin`（同 id 覆盖） |
| "删除 XX 快捷指令" / "把 XX 快捷指令去掉" | 删除 | 先 `match_recipe.sh --query "XX"` 确认命中；命中后**二次确认**再 `delete_recipe.sh --id <id>` |
| "我有哪些快捷指令" / "列一下快捷指令" / "快捷指令列表" | 列表 | `list_recipes.sh` → 用人话汇报（"你现在有：番茄钟、学习模式、派对时间"），**不直接贴 JSON** |
| "开始一个快捷指令" / "触发一个快捷指令"（无具体名字） | 歧义，问用户 | `list_recipes.sh` → "你想触发哪个？这几个都可以：[列表]" |
| "快捷指令 XX" / "开始 快捷指令 XX" | 显式调用 | **剥离 "快捷指令" 前缀**后，用剩余部分作为 query 走标准执行流程的 match_recipe |

> **剥离规则**："快捷指令"/"快捷词"（兼容旧叫法）作为前缀或夹在动词（开始/触发/执行）与名字之间时都要剥掉。例："开始快捷指令番茄钟" → query = "番茄钟"；"执行一下快捷指令 派对时间" → query = "派对时间"。剥离后若得到空字符串，按"开始一个快捷指令"歧义处理。

> **为什么需要这套元命令**：上层 Agent 路由只看本 skill 的 description（它看不到用户已创建哪些具体快捷指令）。用户一旦在 query 里说"快捷指令"这四个字，就等于**显式点名本 skill**，无论具体触发词多怪都能可靠路由进来——这是命名奇葩触发词的用户的"逃生出口"。

## 标准执行流程

当用户说出一句可能触发快捷指令的话时，Agent 按以下顺序处理：

### 1. 路由优先级判断
- 看 query 是否强语义属于某个常见预设场景（睡前/起床/观影/离家/起夜等"名词即功能"的场景）
- 是 → 不抢路由，交回上层 Agent，**除非**下一步 match_recipe 精确命中
- 否 → 进入 step 2

### 2. 匹配 recipe
```
scripts/match_recipe.sh --query "<用户原话>"
```
解析输出：
- `matched: true` 且 `ambiguous` 字段不存在 → **直接执行**（step 3）
- `matched: true` 且 `ambiguous: true` → 展示 `all_matches` 让用户选一个（或默认最近使用的 recipe_id）
- `matched: false` 且 `candidates` 非空 → Agent 尝试语义匹配：
  - 若有 candidate 的 `name` / `description` 与 query 语义高度相似 → 询问"是想触发『XXX』吗？"
  - 用户确认后 → step 3
  - 用户否认或无语义相似项 → step 4（创建向导）
- `matched: false` 且 `candidates` 为空 → step 4

### 3. 执行 recipe
```
scripts/run_recipe.sh --recipe-id <id>
```
读取输出 JSON：
- `ok: true` → 简要播报"XXX 已开启"
- `ok: false` → 告知用户失败原因（从 `steps[].error` 提取），询问是否重试或跳过

### 4. Recipe 创建向导（对话式）
当用户意图是"定义一个新快捷指令"，或 match 未命中且首次引导里用户明确说"没有合适的模板"时走此路径。

**新手场景关键原则**：用**具体问题**而非 schema 术语，Agent 内部再翻译成 steps。

对话骨架（按序）：

1. **问触发词**："下次你说什么话时触发？"（primary）
2. **问别名**："还有别的说法吗？没有也行。"（aliases；空就不加）
3. **问做什么（开放式）**："触发时你希望发生哪些事？可以挑：
   - 开关某些灯 / 调颜色 / 调亮度
   - 关掉电视或投影
   - 让小度屏说一句话或播放内容
   - 触发一个你在小度 App 里已经编好的场景"
4. **对每一类"要做的事"，Agent 负责追问具体参数**，并**同步拉设备候选列表**供用户选择：
   - 涉及灯 → 跑 `xiaodu-control-official/scripts/list_iot_devices.sh`，让用户从实际设备里挑，不要自由输入
   - 涉及小度屏 → 跑 `list_devices.sh`
   - 涉及已有场景 → 跑 `list_scenes.sh`，让用户从真实 scene 名里挑
   - 底层查不到 → 告知用户"查不到候选，请输入完整名字"，并在最后步骤 6 跑 verify_recipe 验一次
5. **展示 JSON 预览**，用**人话描述**而不是直接贴 JSON：
   ```
   【预览】触发词：番茄钟（别名：开始番茄钟）
   触发时：
     1) 关掉 客厅电视
     2) 小度智能屏2 播报"番茄钟开始"
   确认保存吗？
   ```
6. 用户确认 → `save_recipe.sh --stdin` 写入 → **自动跑 `verify_recipe.sh --id <新 id>`** → 退 50 时提示设备名有问题，退 0 时简短确认
7. 播报"已记住。下次说『XXX』即可触发"

### 5. 汇报风格
- 成功：简短、不啰嗦，突出关键动作（"学习模式已开启：灯调冷白、电视已关、今日3项日程"）
- 失败：告知**哪一步**失败 + **原因的人话版本** + 建议下一步
- 不要复读全部 step 细节

## 极简确认规则

以下情况**不需要**向用户再确认：
- match 精确命中、recipe 无破坏性操作（关屏/关灯/播放）
- dry-run 成功后的正式执行

以下情况**需要**向用户确认：
- match 语义匹配（非精确）
- recipe 包含门锁、摄像头、扫地机等较重操作
- 多个 recipe 同时命中（ambiguous）

## 防误控规则

- 不对 `xiaodu-control-official/scripts/list_iot_devices.sh` 未返回的设备下发指令——在创建 recipe 时提示用户"该设备当前不存在，将保存但可能无法执行"
- 导入模板前应走 `--describe` 拿 `candidates` 让用户从真实设备里挑；事后可跑 `verify_recipe.sh` 复核（exit 50 = 有缺失，exit 51 = 后端不可用无法判断）
- `optional=false` 的 step 失败 → 立即中止剩余 step（见 `run_recipe.sh` 实现）
- 绝不擅自增加 recipe 没有的动作
- 触发词冲突时 `save_recipe.sh` 会拒绝保存

## 偏好记忆

`stats.json` 记录每个 recipe 的：
- `triggered_count`：触发次数
- `last_triggered_at`：最近一次时间
- `last_success`：上次是否成功
- `last_failures`：上次失败的 step 列表

用途：
- ambiguous 时按最近使用排序
- 创建向导中，Agent 可以提示"你最近常用的几个 recipe：..."
- 失败诊断

## 示例请求与回复

### 示例 A：已有 recipe，直接触发
> 用户："开始学习模式"
> Agent：→ `match_recipe.sh` 精确命中 study-mode → `run_recipe.sh --recipe-id study-mode`
> 回复："学习模式已开启——书房灯冷白、电视已关、今日有 3 项日程。"

### 示例 B：语义近似，询问确认
> 用户："进入专注状态"
> Agent：→ match 未精确命中，但 candidates 里 study-mode 的 description 包含"专注"
> 回复："你是想触发『学习模式』吗？"
> 用户："对"
> Agent：→ `run_recipe.sh --recipe-id study-mode`

### 示例 C：创建新 recipe（已有其他 recipe，非空库）
> 用户："以后我说『番茄钟』就帮我关电视、关客厅射灯"
> Agent：（创建向导）"好的。你家电视叫什么？"（同步 `list_iot_devices.sh` 展示候选让用户选）
> 用户："客厅电视"
> Agent："射灯呢？"
> 用户："客厅射灯"
> Agent："要不要让小度屏播报一句？"
> 用户："说『番茄钟开始』"
> Agent：（展示 JSON 预览）"【预览】番茄钟（别名：开始番茄钟）触发时：关客厅电视、关客厅射灯、小度智能屏2 播报『番茄钟开始』。确认？"
> 用户："保存"
> Agent：→ `save_recipe.sh --stdin` → 成功 → 立即 `verify_recipe.sh --id pomodoro`
> - verify 退 0 → "已记住，下次说『番茄钟』即可触发"
> - verify 退 50 → "保存好了，但『客厅射灯』我在你家设备里没找到。要改成别的名字吗？"

### 示例 D：空库首次 + 语义命中内置模板
> 用户（空库）："开始学习模式"
> Agent：Step 0 探活 ✓ → Step 1 拿 `list_templates`，发现 study-mode 的 primary 就是"开始学习模式"
> 回复："看起来你是想直接用内置的『学习模式』模板？我来问你几个问题帮你配置。"
> → 进 Step 2：describe → 逐项询问 → 导入 → auto verify → 播报

### 示例 E：与常见预设场景语义冲突，让位
> 用户："开始睡前模式"
> Agent：语义属于"睡前"类常见预设场景 → 即便空库也**不**进首次引导 → 先 `match_recipe.sh` 检查精确命中 → 未命中 → 本 skill 不抢路由，交回上层 Agent 决定

### 示例 F：元命令显式点名，不让位（与示例 E 对照）
> 用户："快捷指令 睡前模式"
> Agent：识别到"快捷指令"显式前缀 → 剥离前缀 → `match_recipe.sh "睡前模式"`
> - 精确命中 → 直接 `run_recipe.sh`
> - 未命中 → 进入创建向导（即便"睡前模式"语义属于常见预设场景，**也不再让位**——用户已显式点名本 skill）

> 同理，"设置一个睡前模式的快捷指令"、"删除睡前模式快捷指令"、"我有哪些快捷指令"等含管理动词 + "快捷指令"关键字的说法，一律进本 skill，不触发让位判断。

## 引用文档

- `references/recipe-schema.md`：recipe 字段规范、支持的 action、占位符声明、同 id 覆盖语义
- `references/placeholder-kinds.md`：占位符 kind 与 `list_*` 后端脚本的映射
- `references/routing-rules.md`：与生态其他编排 skill 的共存与解耦规则、精确命中例外、判定流程
- `references/usage-notes.md`：何时用本 skill、常见坑、调试方法、`verify_recipe` 使用
- `references/exit-codes.md`：脚本退出码约定与 Agent 错误分发建议
- `references/test-cases.md`：测试用例，覆盖严格命中/语义命中/创建/冲突/让位/依赖缺失/占位符导入
