# Routing Rules —— 与其他编排 skill 的共存规则

`xiaodu-shortcut` 是一个"通用快捷指令编排"skill，容易与生态中其他"场景编排类"专用 skill 在语义上重合（例如睡前、起床、观影、离家、起夜等以名词即功能的场景）。本文定义本 skill 的自我约束，不绑定具体 skill 名。

## 核心原则

**本 skill 与其他编排 skill 解耦**：不感知、不硬编码任何具体专用 skill 的名字；让位判断由上层 Agent 根据当前注册的 skill 集合自行决策。

本 skill 只承担两个责任：
1. **老老实实说自己做什么**：只做"用户自定义快捷指令"，不做也不假装做"睡前/起床/观影……"这类有固定行业语义的整体流程。
2. **在合适的时机退出竞争**：当用户 query 语义明显属于某个常见预设场景，且本 skill 没有精确命中任何用户自定义 recipe 时，主动交出决策权，让上层 Agent 决定去哪里。

## 不让位的唯一例外：用户意图压倒一切

如果 `match_recipe.sh` 返回 `matched: true` 且返回的 `matched_trigger` 在规范化（trim + lowercase）后与用户 query 完全一致（= **精确命中**），说明用户是用自己定义的快捷指令在说话，此时本 skill **直接执行该快捷指令，不让位**。

## 判定流程（Agent 执行）

```
收到 query
  │
  ▼
1. 先跑 match_recipe.sh --query "..."
  │
  ├── 精确命中（matched:true 且 matched_trigger≡query）
  │     └─→ 直接 run_recipe.sh，不让位
  │
  └── 未精确命中
        │
        ▼
      2. query 是否语义属于某个常见预设场景？
          （睡前 / 起床 / 观影 / 离家 / 起夜……这类"名词即功能"的场景）
          ├── 是 → 本 skill 退出竞争，交回上层 Agent 由它决定路由
          │        （上层 Agent 若发现有相应专用 skill 注册，就路由过去；
          │         若没有，可回落到本 skill 的创建向导）
          └── 否 → 继续走本 skill 的语义 fallback / 创建向导
```

## 精确命中的定义

"精确命中"= `match_recipe.sh` 返回 `matched: true` **且** `ambiguous` 字段不存在 **且** `matched_trigger` 规范化（trim + lowercase）后与用户 query 完全一致。标点不强制区分。

## 冲突场景举例

### 场景 1：语义看似属于常见预设场景，但用户配了对应的快捷指令
- 用户 query："开始睡觉计划"
- 用户在本 skill 里配了 recipe `my-sleep-plan`，primary = "开始睡觉计划"
- 判定：match_recipe 精确命中 → **直接执行该快捷指令**，不让位

### 场景 2：用户说的是常见预设场景的常规触发词
- 用户 query："带孩子睡觉"
- 本 skill 里没有这个触发词
- 判定：match_recipe 未命中 → query 属于"睡前"类 → 本 skill 退出竞争，交回上层 Agent

### 场景 3：语义相似但都没精确命中
- 用户 query："晚安小度"
- 本 skill 里有 recipe "晚安模式"（description="晚安问候 + 关灯"）
- 判定：match_recipe 未精确命中，但 candidates 含语义近似项 → Agent **先询问用户**"你是想触发『晚安模式』还是走通用的晚安流程？"，由用户选择

## 不要做的事

- 不要尝试"聪明地合并"本 skill 与其他编排 skill：两套逻辑各自独立演化
- 不要在本 skill 的 step 里悄悄调用其他 skill 的脚本当作"子流程"（破坏可预测性、引入隐式耦合）
- 不要在本 skill 文档里硬编码具体专用 skill 的名字作为"让位目标清单"——那是上层 Agent 的工作
