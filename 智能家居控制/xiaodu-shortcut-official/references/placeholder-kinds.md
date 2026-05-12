# Placeholder Kinds

占位符 `kind` 与 xiaodu-control-official 底层脚本的映射契约。

`_placeholder_lib.sh` 的 `list_candidates` 函数和 `verify_recipe.sh` 均依赖此映射。修改这里需要同步改这两个脚本。

## 映射表

| kind | 语义 | 候选来源 | 用途示例 |
|------|-----|---------|---------|
| `iot_device` | 智能家居设备（灯、电视、窗帘、空调、风扇、投影、门锁…） | `xiaodu-control-official/scripts/list_iot_devices.sh` | `control_iot` 的 `device` 参数 |
| `smart_screen` | 小度智能屏/音箱（播报/指令目标） | `xiaodu-control-official/scripts/list_devices.sh` | `speak` / `control_xiaodu` / `push_resource` 的 `device_name` 参数 |
| `scene` | xiaodu-iot 预配场景 | `xiaodu-control-official/scripts/list_scenes.sh` | `try_scene` 的 `scene_name` |
| `any` | 任意文本，不做校验 | — | 自由文本（如播报内容、URL 等），一般不推荐放占位符 |

## 行为约定

- `list_candidates` 对每个 kind 调一次对应 list 脚本，把设备名字段抽出来返回每行一个
- 底层脚本缺失或返回非 0 时：`list_candidates` 打印 `WARN` 到 stderr，stdout 返回空
- `verify_recipe.sh` 把同样的映射用于反向校验（recipe 里的值是否在候选列表里）

## 候选字段抽取规则

`_placeholder_lib.sh::list_candidates` 和 `verify_recipe.sh::run_list` 共用同一份解析逻辑（修改要两处同步），以兼容不同底层脚本的真实返回结构。

**当前观测到的真实格式**（来自 xiaodu-control-official）：

| 脚本 | 顶层 | 单项字段（设备名） |
|------|------|-------------------|
| `list_iot_devices.sh` | `{"return":[...]}` | `applianceName`（另有 `roomName` / `applianceTypes` / `status`） |
| `list_devices.sh` | 顶层数组 `[...]` | `device_name`（另有 `client_id` / `cuid` / `location`） |
| `list_scenes.sh` | `{"return":[...]}` | `sceneName`（对应 `trigger_scene.sh --scene-name`） |

**解析链**（按顺序兜底）：

```jq
(if type=="array" then .
 elif has("return") then .return
 elif has("devices") then .devices
 elif has("scenes") then .scenes
 elif has("data") then .data
 else [] end)
| map(.applianceName // .device_name // .sceneName
      // .name // .friendlyName // .scene_name // .deviceName // empty)
```

若底层后续变更（新增字段或改包装键），**只改这两处解析链**，占位符 kind 的语义不用动。
