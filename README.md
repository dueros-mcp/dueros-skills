# DuerOS Skills

这是一个面向 OpenClaw 和 DuerOS Agent 的 Skill 共建仓库。

Skill 是给 Agent 使用的能力包。一个 Skill 可以是一组提示词、一套操作流程、几个本地脚本，也可以封装外部工具或设备能力。Agent 通过 Skill 把用户的自然语言请求转成具体动作，例如控制小度设备、管理家庭备忘、设置用药提醒等。

这个仓库的目标是让这些能力可以被复用、组合和持续迭代。

## 什么是 Skill

一个典型 Skill 通常包含：

- `SKILL.md`：说明这个 Skill 什么时候应该被使用、能做什么、不能做什么、依赖哪些能力，以及执行时要遵守的规则。
- `scripts/`：可选。本地脚本，用于完成具体动作。
- `references/`：可选。测试用例、排障说明、模板、协议、示例或补充文档。
- `models/` 或其他资源文件：可选。Skill 运行所需的模型、配置或资产。

Agent 不需要用户手动打开这些文件。用户只需要用自然语言表达需求，Agent 会根据 `SKILL.md` 判断是否使用对应 Skill。

## Skill 列表

当前仓库已有 Skill 请看：

[SKILLS.md](SKILLS.md)

这个文件由脚本生成，用于快速查看仓库里有哪些 Skill、分别属于哪个分类、用途是什么。

## 分类目录

当前按使用场景分为以下目录：

- `智能家居控制/`：小度设备、智能屏、IoT 家电、家庭场景编排。
- `家庭事务管理/`：家庭备忘、用药提醒、健康监测、日程和清单。
- `专属生活助手/`：饮食、菜谱、购物、习惯、个人生活建议。
- `出行规划/`：旅行、路线、天气、交通和差旅安排。
- `知识问答/`：搜索、百科、新闻、实时信息和结构化知识回答。
- `学习教育/`：学习、教学、科研、笔记和知识整理。
- `内容创作/`：文案、营销、社媒、图片、视频和创意内容。
- `办公效率/`：文档、表格、会议、邮件、项目管理和组织协作。
- `开发者工具/`：代码、调试、部署、API、日志和工程自动化。
- `系统工具/`：技能发现、技能创建、诊断、记忆、路由等平台基础能力。

如果不确定新 Skill 应该放到哪里，优先选择最贴近用户使用场景的目录。

## 仓库结构

```text
.
├── README.md
├── SKILLS.md
├── scripts/
│   └── update_skills_index.py
├── 智能家居控制/
│   ├── README.md
│   ├── xiaodu-control-official/
│   └── ...
├── 家庭事务管理/
│   ├── README.md
│   ├── med-assistant/
│   └── ...
└── ...
```

每个 Skill 都应该是一个独立目录，并且至少包含一个 `SKILL.md`。

## 如何使用

直接打开对应 Skill 的 `SKILL.md` 查看说明即可。

例如：

- [xiaodu-control-official](智能家居控制/xiaodu-control-official/SKILL.md)：小度智能屏和 IoT 设备控制。
- [med-assistant](家庭事务管理/med-assistant/SKILL.md)：用药计划、服药提醒和药单查询。
- [xiaodu-ai-memo-official](家庭事务管理/xiaodu-ai-memo-official/SKILL.md)：文本和图片备忘管理。

部分 Skill 会依赖其他 Skill。例如多个家庭场景类 Skill 会复用 `xiaodu-control-official` 的底层设备控制能力。

## 如何贡献 Skill

本仓库使用 GitHub Flow。

**主分支 `main` 是受保护分支，禁止直接提交、禁止直接合入。所有修改都必须通过新分支提交 Pull Request，经过 Review 后再合并。**

### 1. Fork 或拉取最新主分支

如果你没有仓库写权限，请先 Fork 本仓库，再 clone 到本地。

如果你已有写权限，请先同步最新主分支：

```bash
git checkout main
git pull origin main
```

### 2. 创建工作分支

每个修改都从 `main` 新建独立分支：

```bash
git checkout -b feature/my-new-skill
```

建议分支命名：

| 修改类型 | 前缀 | 示例 |
|---|---|---|
| 新增 Skill | `feature/` | `feature/morning-news` |
| 修复问题 | `fix/` | `fix/med-reminder-timezone` |
| 文档修改 | `docs/` | `docs/skill-index` |
| 仓库维护 | `chore/` | `chore/update-skill-list` |

### 3. 添加或修改 Skill

把完整 Skill 目录放到最合适的分类下面。

示例：

```bash
cp -R ~/openclaw/skills/my-new-skill ./家庭事务管理/my-new-skill
```

推荐结构：

```text
my-new-skill/
├── SKILL.md
├── scripts/
└── references/
```

只有 `SKILL.md` 是必需的。脚本、参考文档、模板和测试用例按需添加。

### 4. 本地自查

提交前请检查：

- `SKILL.md` 是否清楚说明了触发场景。
- 是否说明了依赖的其他 Skill、外部工具或运行环境。
- 示例是否足够通用，不能包含私人账号、真实 token、内部链接或敏感数据。
- 脚本是否能从 Skill 目录正常运行，或者文档里说明了运行目录要求。
- 不要提交本地缓存、日志、用户数据、运行时生成文件。

### 5. 提交到自己的分支

确认修改后，在自己的分支上提交：

```bash
git status
git add .
git commit -m "feat: add my-new-skill"
git push origin feature/my-new-skill
```

提交信息建议使用清晰的英文前缀，例如：

- `feat:` 新增 Skill 或能力。
- `fix:` 修复问题。
- `docs:` 修改文档。
- `chore:` 仓库维护。

### 6. 创建 Pull Request

在 GitHub 上从你的分支创建 Pull Request，目标分支选择 `main`。

PR 描述里建议写清楚：

- 新增或修改了哪个 Skill。
- 这个 Skill 属于哪个分类。
- 用户什么情况下会触发它。
- 如何测试。
- 是否依赖其他 Skill、外部工具、模型或配置。

### 7. Review 和合并

Pull Request 创建后，由维护者进行 Review。

合并前可能会要求你补充说明、调整分类、修改 `SKILL.md` 描述、移除敏感信息或补充测试。所有修改继续提交到同一个分支，PR 会自动更新。

Review 通过后，由维护者合并到 `main`。合并完成后，可以删除已合并的工作分支。

### 8. 更新 Skill 列表

`SKILLS.md` 是自动生成的。

维护者在新增、删除或移动 Skill 后运行：

```bash
python3 scripts/update_skills_index.py
```

然后检查变化：

```bash
git diff -- SKILLS.md
```

普通贡献者可以不手动更新 `SKILLS.md`，由维护者在合并前统一处理。

## 安全和隐私

不要提交以下内容：

- Access Token、API Key、Cookie、Bearer Token。
- 带有凭证的本地配置文件。
- 个人设备 ID、账号 ID、手机号、邮箱等个人信息。
- 私有链接、内部文档、内部系统地址。
- 用户数据、聊天记录、截图、日志、缓存文件。

示例里请使用占位符，例如：

- `<ACCESS_TOKEN>`
- `<device_name>`
- `<your-url>`
- `<user-id>`

## 维护者说明

新增、删除或移动 Skill 后，维护者需要重新生成索引：

```bash
python3 scripts/update_skills_index.py
```

如果后续 Skill 中包含较大的模型文件，建议使用 Git LFS 或改为运行时下载，避免超过 GitHub 单文件大小限制。

## License

本仓库使用 [MIT License](LICENSE)。
