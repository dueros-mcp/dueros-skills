# Skill 列表

这个文件用于快速查看当前仓库已有 Skill，避免逐层目录点开查找。

当前共 9 个 Skill。

> 维护说明：贡献者不需要手动修改本文件。新增或调整 Skill 后，由仓库维护者运行 `python3 scripts/update_skills_index.py` 统一更新。

## 快速总览

| 分类 | Skill | 用途 |
|---|---|---|
| 智能家居控制 | [xiaodu-bedtime-soother-official](智能家居控制/xiaodu-bedtime-soother-official/SKILL.md) | 基于已安装的 xiaodu-control-official 编排儿童睡前场景。 |
| 智能家居控制 | [xiaodu-control](智能家居控制/xiaodu-control-official/SKILL.md) | 当用户要连接、配置、验证、排障或控制小度智能屏 MCP 与小度 IoT MCP 时使用，包括识别小度授权页文本、写入 mcporter 配置、列设备、文本播报、语音指令、拍照、资源推送，以及灯光/空调/风扇/窗帘/电视机顶盒/投影/扫地机/门锁等 IoT 控制与场景触发。 |
| 智能家居控制 | [xiaodu-leave-home-mode-official](智能家居控制/xiaodu-leave-home-mode-official/SKILL.md) | 基于已安装的 xiaodu-control-official 编排离家场景。 |
| 智能家居控制 | [xiaodu-movie-mode-official](智能家居控制/xiaodu-movie-mode-official/SKILL.md) | 基于已安装的 xiaodu-control-official 编排观影场景。 |
| 智能家居控制 | [xiaodu-senior-night-assist-official](智能家居控制/xiaodu-senior-night-assist-official/SKILL.md) | 基于已安装的 xiaodu-control-official 编排老人夜间短时起身的安全辅助场景。 |
| 智能家居控制 | [xiaodu-shortcut](智能家居控制/xiaodu-shortcut-official/SKILL.md) | 用户自定义家庭场景编排与快捷指令触发。 |
| 智能家居控制 | [xiaodu-wake-up-routine-official](智能家居控制/xiaodu-wake-up-routine-official/SKILL.md) | 基于已安装的 xiaodu-control-official 编排儿童起床场景。 |
| 家庭事务管理 | [med-assistant](家庭事务管理/med-assistant/SKILL.md) | 用药助手。 |
| 家庭事务管理 | [xiaodu-ai-memo-official](家庭事务管理/xiaodu-ai-memo-official/SKILL.md) | AI 备忘录管理 skill。 |

## 按分类查看

### 智能家居控制

#### [xiaodu-bedtime-soother-official](智能家居控制/xiaodu-bedtime-soother-official/SKILL.md)

- 目录：`智能家居控制/xiaodu-bedtime-soother-official/`
- 用途：基于已安装的 xiaodu-control-official 编排儿童睡前场景。当用户说“带孩子睡觉”“开始睡前模式”“帮我哄孩子睡觉”，或要求把房间调整到适合睡觉的状态时使用。这个 skill 会复用 xiaodu-control-official 的现有脚本，对小度智能屏和小度 IoT 设备执行 scene-first 的睡前编排，而不是重做底层控制。

#### [xiaodu-control](智能家居控制/xiaodu-control-official/SKILL.md)

- 目录：`智能家居控制/xiaodu-control-official/`
- 用途：当用户要连接、配置、验证、排障或控制小度智能屏 MCP 与小度 IoT MCP 时使用，包括识别小度授权页文本、写入 mcporter 配置、列设备、文本播报、语音指令、拍照、资源推送，以及灯光/空调/风扇/窗帘/电视机顶盒/投影/扫地机/门锁等 IoT 控制与场景触发。

#### [xiaodu-leave-home-mode-official](智能家居控制/xiaodu-leave-home-mode-official/SKILL.md)

- 目录：`智能家居控制/xiaodu-leave-home-mode-official/`
- 用途：基于已安装的 xiaodu-control-official 编排离家场景。当用户说“出门了”“离家模式”“出门前检查一下”“帮我把家里设备关一下”时使用。这个 skill 会复用 xiaodu-control-official 的现有脚本，对小度智能屏和小度 IoT 设备执行 scene-first 的离家编排，同时在出门前汇总天气、日历和提醒事项等信息，帮助用户确认“出门前有没有漏掉什么”。不是单纯的关灯 skill，而是出门前一站式安全检查清单。

#### [xiaodu-movie-mode-official](智能家居控制/xiaodu-movie-mode-official/SKILL.md)

- 目录：`智能家居控制/xiaodu-movie-mode-official/`
- 用途：基于已安装的 xiaodu-control-official 编排观影场景。当用户说“开始观影模式”“我要看电影”“把房间调成适合看电影的状态”“准备看电影了”时使用。这个 skill 会复用 xiaodu-control-official 的现有脚本，对小度智能屏和小度 IoT 设备执行 scene-first 的观影编排，而不是重做底层控制。

#### [xiaodu-senior-night-assist-official](智能家居控制/xiaodu-senior-night-assist-official/SKILL.md)

- 目录：`智能家居控制/xiaodu-senior-night-assist-official/`
- 用途：基于已安装的 xiaodu-control-official 编排老人夜间短时起身的安全辅助场景。当用户说“夜里起夜”“我要去卫生间”“帮我开一下夜灯”“夜间辅助模式”这类请求时使用。这个 skill 会复用 xiaodu-control-official 的现有脚本，对小度智能屏和小度 IoT 设备执行 scene-first 的夜间辅助编排，而不是重做底层控制。它的目标不是普通开灯，而是用最少的光、最短的话和最稳的收尾，帮助老人安全完成夜间短时活动。

#### [xiaodu-shortcut](智能家居控制/xiaodu-shortcut-official/SKILL.md)

- 目录：`智能家居控制/xiaodu-shortcut-official/`
- 用途：用户自定义家庭场景编排与快捷指令触发。基于 xiaodu-control-official 的底层能力，让用户用一句自己起的快捷指令（如"开始学习模式"、"番茄钟"、"派对时间"、"做饭模式"、"阅读时间"等）触发一套自己编排好的 IoT + 智能屏组合动作。也响应对快捷指令的元命令："设置/创建快捷指令"、"修改快捷指令"、"删除快捷指令"、"我有哪些快捷指令"、以及显式调用 "快捷指令 X"等。

#### [xiaodu-wake-up-routine-official](智能家居控制/xiaodu-wake-up-routine-official/SKILL.md)

- 目录：`智能家居控制/xiaodu-wake-up-routine-official/`
- 用途：基于已安装的 xiaodu-control-official 编排儿童起床场景。当用户说“叫孩子起床”“开始早安模式”“帮我把孩子叫醒”，或要求让房间进入起床状态时使用。这个 skill 会复用 xiaodu-control-official 的现有脚本，对小度智能屏和小度 IoT 设备执行 scene-first 的晨起编排，而不是重做底层控制。

### 家庭事务管理

#### [med-assistant](家庭事务管理/med-assistant/SKILL.md)

- 目录：`家庭事务管理/med-assistant/`
- 用途：用药助手。当用户要管理用药计划、设置服药提醒、查询药单、修改或停用药物时触发。支持每天固定、疗程、隔天用药以及血压/血糖监测提醒。家属用自然语言配置，小度智能屏语音播报。依赖 xiaodu-control-official 进行设备播报。

#### [xiaodu-ai-memo-official](家庭事务管理/xiaodu-ai-memo-official/SKILL.md)

- 目录：`家庭事务管理/xiaodu-ai-memo-official/`
- 用途：AI 备忘录管理 skill。用于记录、保存和检索用户已保存的文本备忘或文本加图片备忘；当用户明确要保存信息，或明确要查询”之前记的/备忘录里/我记录过的/你帮我记过的”内容时使用。不要因为普通查询词如”查一下今天天气””查一下路线””查一下新闻”而触发；这类没有指向已保存备忘的实时信息查询应由上层 agent 使用其他能力处理。备忘数据存储在本地固定 JSON 文件中；查询时读取结构化 JSON，由上层 agent 综合文本、图片描述、标签和时间进行语义判断。

### 专属生活助手

当前还没有 Skill，保留用于后续共建。

### 出行规划

当前还没有 Skill，保留用于后续共建。

### 知识问答

当前还没有 Skill，保留用于后续共建。

### 学习教育

当前还没有 Skill，保留用于后续共建。

### 内容创作

当前还没有 Skill，保留用于后续共建。

### 办公效率

当前还没有 Skill，保留用于后续共建。

### 开发者工具

当前还没有 Skill，保留用于后续共建。

### 系统工具

当前还没有 Skill，保留用于后续共建。
