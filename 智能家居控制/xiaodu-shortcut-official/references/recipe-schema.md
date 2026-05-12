# Recipe Schema

本文定义 `xiaodu-shortcut` 的 recipe JSON 格式。所有 recipe 存放于：

```
~/.openclaw/workspace/memory/xiaodu-shortcut/recipes/<id>.json
```

## 顶层字段

| 字段 | 类型 | 必选 | 说明 |
|------|------|------|------|
| `schema_version` | string | 推荐 | 当前 `"1"`。保存时若缺省会自动补 `"1"` |
| `id` | string | ✓ | kebab-case，仅小写字母数字和连字符，用作文件名 |
| `name` | string | ✓ | 显示名称 |
| `description` | string |  | 用户可读描述（用于语义 fallback 匹配） |
| `triggers.primary` | string | ✓ | 主触发词（严格匹配） |
| `triggers.aliases` | string[] |  | 别名数组（同样走严格匹配） |
| `preferences` | object |  | 自定义偏好（默认房间/音量），可在 step params 中直接引用具体值 |
| `steps` | array | ✓ | 按顺序执行的步骤列表，至少 1 条 |
| `created_at` / `updated_at` | ISO8601 |  | `save_recipe.sh` 自动维护 |

## Steps

`steps` 是有序数组。每个 step 至少包含 `bucket` 和 `action`。

```json
{
  "bucket": "lights",
  "action": "control_iot",
  "optional": false,
  "params": {
    "device": "书房吸顶灯",
    "action": "turnOn"
  }
}
```

### step 字段

| 字段 | 类型 | 必选 | 说明 |
|------|------|------|------|
| `bucket` | string | ✓ | 所属 bucket，用于顺序组织（如 `scene` / `lights` / `display` / `smart-screen-speech` / `smart-screen-assistant` / `push-resource`） |
| `action` | string | ✓ | 见下节"支持的 action" |
| `optional` | boolean |  | 默认 false。true 时失败不中止后续 step |
| `params` | object |  | 参数对象，key 为 `snake_case`，执行时自动转为 `--kebab-case` 透传给底层脚本 |
| `scene_name` | string |  | `action=try_scene` 时使用（也可写在 params.scene_name） |
| `on_success` | string |  | 仅 `try_scene` 有效，取 `stop_remaining_steps_in_same_bucket` 表示场景命中后跳过同 bucket 剩余步骤 |

## 支持的 Action（与底层脚本映射）

| action | 映射到 | 必选 params（snake_case） |
|--------|--------|--------------------------|
| `try_scene` | `xiaodu-control-official/scripts/trigger_scene.sh` | `scene_name`（也可放 step 顶层），可选 `server` |
| `control_iot` | `control_iot.sh` | `device`、`action`；`action=set` 时额外需 `attribute`、`value`；可选 `room`、`server` |
| `speak` | `speak.sh` | `text` + (`device_name` 或 `cuid`+`client_id`)；可选 `server` |
| `control_xiaodu` | `control_xiaodu.sh` | `command` + (`device_name` 或 `cuid`+`client_id`)；可选 `server` |
| `push_resource` | `push_resource.sh` | `resource_type` + 对应 URL 字段 + (`device_name` 或 `cuid`+`client_id`) |

### params 命名约定

- JSON key 用 snake_case，如 `device_name`
- 执行时 `run_recipe.sh` 自动转为 kebab-case CLI 参数：`--device-name`
- value 原样透传

> 注意：`control_iot.sh` 的底层参数本身就是 `--device`（不带 name），所以 recipe 里写 `"device": "xxx"`；而 `speak.sh` / `control_xiaodu.sh` / `push_resource.sh` 的底层参数是 `--device-name`，所以 recipe 里写 `"device_name": "xxx"`。不要混用。

## 完整示例

```json
{
  "schema_version": "1",
  "id": "study-mode",
  "name": "学习模式",
  "description": "进入专注学习：冷白灯 + 关电视 + 播报今日任务",
  "triggers": {
    "primary": "开始学习模式",
    "aliases": ["进入学习模式", "学习时间到了", "我要学习了"]
  },
  "preferences": {
    "default_room": "书房",
    "default_volume": 30
  },
  "steps": [
    {
      "bucket": "scene",
      "action": "try_scene",
      "scene_name": "学习",
      "optional": true,
      "on_success": "stop_remaining_steps_in_same_bucket"
    },
    {
      "bucket": "lights",
      "action": "control_iot",
      "params": { "device": "书房吸顶灯", "action": "turnOn" }
    },
    {
      "bucket": "lights",
      "action": "control_iot",
      "params": {
        "device": "书房吸顶灯",
        "action": "set",
        "attribute": "color_temperature",
        "value": "cool"
      }
    },
    {
      "bucket": "display-off",
      "action": "control_iot",
      "optional": true,
      "params": { "device": "客厅电视", "action": "turnOff" }
    },
    {
      "bucket": "smart-screen-speech",
      "action": "speak",
      "params": {
        "device_name": "小度智能屏2",
        "text": "学习模式已开启，祝专注高效"
      }
    },
    {
      "bucket": "smart-screen-assistant",
      "action": "control_xiaodu",
      "optional": true,
      "params": {
        "device_name": "小度智能屏2",
        "command": "今天有什么日程"
      }
    }
  ]
}
```

## 执行顺序与并发

- step 严格按数组顺序串行执行（**不并发**）
- bucket 仅作为语义分组 + `try_scene.on_success` 的跳过范围
- `try_scene` 成功且设置 `on_success=stop_remaining_steps_in_same_bucket` → 跳过同 bucket 后续 step（通常是为了 scene-first + fallback）

## 校验规则（save_recipe.sh 会强制）

1. 合法 JSON
2. `id` 非空且为 kebab-case
3. `name` 非空
4. `triggers.primary` 非空
5. `steps` 非空
6. **触发词全局唯一**：新 recipe 的任何 trigger（primary + aliases）不得与其他 recipe 的任何 trigger 冲突（大小写和前后空白不敏感）

任何校验失败会以非 0 退出并在 stderr 打印错误。

## 同 id 覆盖语义

`save_recipe.sh` 对 `id` 相同的情况视为**更新**，不是冲突：

- 同 id 再次 save → `action: "updated"`，`created_at` 保留原值，`updated_at` 刷新
- 其他 recipe 的触发词冲突 → 退出码 20，拒绝保存
- 自身原有的触发词不视为冲突（允许改动 triggers）

若需要**同一个模板导入多份**（比如家里有两间书房，想分别叫"书房1学习模式""书房2学习模式"），用 `import_template.sh`：

```bash
# 第 1 份：模板原样
import_template.sh --template study-mode

# 第 2 份：换 id 和主触发词，清空 aliases 避免冲突
import_template.sh --template study-mode \
  --override-id study-mode-room2 \
  --override-primary "书房2学习模式" \
  --clear-aliases
```

直接再次 `import_template.sh --template study-mode` 不加 override → 会把第 1 份**覆盖**（因为 id 相同）。

## 占位符（仅模板使用，非运行时概念）

**模板**支持 `{{name}}` 占位符，在 `import_template.sh` 期间由 Agent 填槽后渲染为字面值再保存。保存后的 recipe **不包含**占位符。

### `placeholders` 段

```json
{
  "placeholders": {
    "tv": {
      "prompt": "客厅电视叫什么名字？",
      "kind": "iot_device",
      "required": true,
      "default_key": "living_room_tv"
    },
    "spot_light": {
      "prompt": "客厅射灯叫什么？没有就跳过",
      "kind": "iot_device",
      "required": false
    }
  },
  "steps": [
    {
      "action": "control_iot",
      "params": { "device": "{{tv}}", "action": "turnOff" }
    },
    {
      "action": "control_iot",
      "params": { "device": "{{spot_light}}", "action": "turnOff" },
      "skip_if_placeholder_empty": "spot_light"
    }
  ]
}
```

### 字段说明

| 路径 | 必选 | 说明 |
|------|------|------|
| `placeholders.<key>.prompt` | ✓ | 人话描述，给用户看 |
| `placeholders.<key>.kind` | ✓ | `iot_device` / `smart_screen` / `scene` / `any`，见 `placeholder-kinds.md` |
| `placeholders.<key>.required` |  | 默认 true。false 时用户可跳过，引用它的 step 需配 `skip_if_placeholder_empty` |
| `placeholders.<key>.default_key` |  | 跨模板复用时用的 key；缺省使用占位符名本身作 default key |
| `steps[].skip_if_placeholder_empty` |  | 指向某个占位符 key；若该占位符值为空则该 step 在渲染后被**移除** |

### 渲染规则

- 只替换 step 内字符串值中的 `{{name}}`（以及 `try_scene` 的 `scene_name` 字段）
- 不替换 recipe 顶层的 `id`/`name`/`description`/`triggers`
- 未知占位符（出现在 step 但 `placeholders` 段未声明，且 values 里也没给）：
  - `required: true` → `import_template.sh` 退出码 40
  - 有 `skip_if_placeholder_empty` 指向它 → 整个 step 被 drop
  - 其它 → 退出码 41
- 保存的最终 recipe **不包含** `placeholders` / `skip_if_placeholder_empty` / `default_key` 字段

### 跨模板默认值

`~/.openclaw/workspace/memory/xiaodu-shortcut/placeholder-defaults.json` 存用户上次填过的值：

```json
{
  "living_room_tv": "75寸三星",
  "smart_screen": "小度智能屏2"
}
```

`import_template.sh --describe` 输出时会把 `default_key` 命中的默认值作为 `default` 字段暴露给 Agent；导入成功后，`import_template.sh` 自动把本次填的值回写此文件。
