---
name: med-assistant
description: 用药助手。当用户要管理用药计划、设置服药提醒、查询药单、修改或停用药物时触发。支持每天固定、疗程、隔天用药以及血压/血糖监测提醒。家属用自然语言配置，小度智能屏语音播报。依赖 xiaodu-control-official 进行设备播报。
---

# 用药助手 (med-assistant)

仅在已确认 `xiaodu-control-official` 已安装，且 `mcporter` 已经配置好 `xiaodu` 时使用本 skill。

## 依赖

- 设备播报复用现有脚本：
  - `skills/xiaodu-control-official/scripts/speak.sh`
- 除非依赖脚本缺失，否则不要绕过依赖 skill 重写底层 MCP 调用。

## 路径

- 药单数据：`memory/med-assistant/medications.json`
- 数据脚本：`scripts/med_store.py`
- 播报脚本：`scripts/med_broadcast.py`
- cron 提醒脚本：`scripts/med_remind.sh`（生成 TTS 文本并通过 `speak.sh` 播出，供 cron job 调用）

## 触发条件

- "帮我配一下用药" / "录入药单" / "设置服药提醒"
- "修改/停用某个药"
- "查一下在吃什么药" / "药单是什么"
- "加一个监测提醒"（血压、血糖等）

## 核心原则

1. **确认后再执行**：解析药单后，列出结构化结果请用户确认，不静默写入
2. **变更告知影响**：修改药物时，说明会取消哪些旧闹钟/任务
3. **停药保留记录**：停药只置 `active: false`，不删除历史数据
4. **配置时预计算 TTS**：设置闹钟前先运行 med_broadcast.py 生成完整播报文本

## 调度机制选择

| `schedule.type` | 提醒方式 |
|---|---|
| `daily` / `weekdays` | 配置时在小度设备端设置循环闹钟，传入预生成的 TTS 文本 |
| `every_n_days` / `course` | 注册 OpenClaw cron job，触发时运行播报脚本并调小度 TTS |

> 若小度设备端闹钟不支持自定义 TTS 文本，`daily` 和 `weekdays` 也改用 OpenClaw cron。

---

## 工作流一：新增药单

### 第一步：解析用户输入

从自然语言中提取：

| 字段 | 说明 |
|---|---|
| `name` | 药物名称 |
| `dose` | 剂量，自由文本（"半片"、"两片"、"一粒"） |
| `schedule.times` | 时间点列表，格式 `HH:MM` |
| `broadcast_note` | 服药说明，如"饭后服用"、"和水送服"，可为空 |
| `schedule.type` | `daily` / `every_n_days` / `course` / `weekdays` |
| `schedule.interval_days` | `every_n_days` 时使用 |
| `schedule.course_days` | `course` 时使用 |
| `schedule.start_date` | 开始日期，默认今天（格式 YYYY-MM-DD） |
| `warnings` | 药物注意事项，可为空 |

监测项（血压/血糖等）单独提取，写入 `monitoring`。

### 第二步：确认播报设备

若 `settings.device_name` 为空，询问用户：

> "用哪台小度设备播报服药提醒？"

用户回答后写入：

```bash
python3 scripts/med_store.py update-settings \
  --data '{"device_name":"小度智能屏X"}'
```

若 `settings.device_name` 已有值，跳过此步。

### 第三步：展示解析结果，请用户确认

```
我理解的配置如下，请确认：

药物：
- 07:30 降压药半片（饭后服用）
- 07:30 阿司匹林一片
- 20:00 二甲双胍两片（饭后服用）

监测：
- 07:30 量血压

确认后我会在小度上设好提醒。有没有需要修改的地方？
```

### 第四步：用户确认后执行

**4a. 写入药单**

对每个药物条目执行：

```bash
python3 scripts/med_store.py add \
  --data '{"name":"降压药","dose":"半片","broadcast_note":"饭后服用","warnings":"","notes":"","schedule":{"type":"daily","times":["07:30"],"interval_days":null,"course_days":null,"start_date":"2026-04-28","end_date":null}}'
```

记录输出的 `med_id`。

若有监测项：

```bash
python3 scripts/med_store.py update-monitoring \
  --key blood_pressure \
  --data '{"enabled":true,"times":["07:30"],"reminder_text":"别忘了量血压"}'
```

**4b. 生成 TTS 文本**

按时间点分组，每个时间点生成一次播报文本：

```bash
python3 scripts/med_broadcast.py --time 07:30
```

输出示例：`爸爸，该吃药啦。降压药半片，饭后服用；阿司匹林一片；别忘了量血压。`

**4c. 设置提醒**

- **`daily` / `weekdays` 类型：**
  - 读取 `xiaodu-control-official` SKILL.md，调用设备端循环闹钟能力，传入 TTS 文本、时间和重复规则
  - 将返回的 alarm ID 写入对应药物：
    ```bash
    python3 scripts/med_store.py update-alarm-refs \
      --id <med_id> --refs '["<alarm_id>"]'
    ```
  - 若小度不支持自定义 TTS 循环闹钟，改用 cron 方式：注册 cron job，触发时执行：
    ```bash
    bash scripts/med_remind.sh HH:MM
    ```

- **`every_n_days` 类型：**
  - 注册 OpenClaw cron job，间隔天数为 `interval_days`，从 `start_date` 起算
  - cron 触发时执行（其中 `<device_name>` 取自 `settings.device_name`）：
    ```bash
    TEXT=$(python3 scripts/med_broadcast.py --ids <med_id> --time HH:MM)
    bash ../xiaodu-control-official/scripts/speak.sh \
      --device-name "<device_name>" --text "$TEXT"
    ```
  - 将 cron ID 写入：
    ```bash
    python3 scripts/med_store.py update-cron-refs \
      --id <med_id> --refs '["<cron_id>"]'
    ```

- **`course` 类型：**
  - 同 `every_n_days`，额外在 `start_date + course_days` 当天设置一次性到期任务：取消 cron job 并执行停药流程（见工作流三）

**4d. 告知用户**

```
已设置好 3 个服药提醒和 1 个监测提醒：
- 07:30 小度播报："爸爸，该吃药啦。降压药半片，饭后服用；阿司匹林一片；别忘了量血压。"
- 20:00 小度播报："爸爸，该吃药啦。二甲双胍两片，饭后服用。"
```

---

## 工作流二：修改药物

1. 查询当前药单：
   ```bash
   python3 scripts/med_store.py list --active
   ```
   如有歧义（多个药名相近），列出让用户选择。

2. 展示当前配置和变更后配置，请用户确认。

3. 确认后：
   - 从条目读取 `alarm_refs` 和 `cron_refs`，调用对应能力取消旧闹钟和 cron job
   - 更新 JSON：
     ```bash
     python3 scripts/med_store.py update \
       --id <med_id> --data '{"dose":"一片"}'
     ```
   - 按新配置重新执行步骤 4b/4c

---

## 工作流三：停药

1. 确认要停用哪个药（如有歧义则先列出让用户选择）。

2. 告知影响并请确认：
   > "停药后将取消相关提醒，历史记录保留不删除。确认停用吗？"

3. 确认后执行停药，获取旧 refs：
   ```bash
   python3 scripts/med_store.py deactivate \
     --id <med_id>
   ```
   输出 JSON 包含 `old_alarm_refs` 和 `old_cron_refs`。

4. 逐一取消 `old_alarm_refs` 中的小度闹钟（通过 xiaodu-control），逐一取消 `old_cron_refs` 中的 cron job。

5. 告知用户已停用，闹钟已清除。

---

## 工作流四：查询药单

```bash
python3 scripts/med_store.py list --active
```

按时间点分组汇总后回复。示例：

```
爸爸目前的用药情况：
- 07:30：降压药半片（饭后）、阿司匹林一片、量血压
- 20:00：二甲双胍两片（饭后）
```

若无活跃药物，回复"当前没有配置用药提醒"。

---

## 修改患者信息

```bash
python3 scripts/med_store.py update-settings \
  --data '{"patient_name":"妈妈"}'
```

可配置字段：

| 字段 | 说明 |
|---|---|
| `patient_name` | 播报中的称呼，如"爸爸"、"妈妈" |
| `broadcast_prefix` | 播报开场白，默认"该吃药啦" |
| `device_name` | 播报用的小度设备名，用于 `med_remind.sh` 通过 `speak.sh` 定位设备 |

> 注意：修改患者名称或播报前缀后，已设置的小度闹钟 TTS 文本不会自动更新。如需同步，提示用户重新配置药单。
