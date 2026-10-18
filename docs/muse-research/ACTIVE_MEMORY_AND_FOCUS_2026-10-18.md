# Muse Wonder 的 Active Memory 与 Active Focus

核对日期：2026-10-18。来源级别：Meta 官方研究文章、新闻稿与 Muse Wonder Model Card。本文是对公开材料的原创归纳，不是 Muse 源码审计、产品运行实测或 OpenMuse 实现说明。

## 官方新说明

Meta 在 2026-10-12 发布 Muse Wonder / Muse Wonder Full，并把两项能力命名为 **Active Memory** 和 **Active Focus**：

- **Active Memory**：在不同对话间保留重要上下文，并在当前任务需要时主动找回相关细节。官方描述的是“跨对话保留 + 按当前任务检索”的能力目标，没有公开它依赖的文件、数据库、索引、记忆写入方式或检索排序算法。
- **Active Focus**：面对困难目标继续推进，尝试替代办法、处理阻碍并适应新信息；需要时向用户澄清，并在重要操作前确认。这是模型及其 agent 工作能力的描述，不等于 Muse 会对所有任务持续后台运行。
- **Model Card 的评估范围**：MemoryBench 用 64K–100K tokens 的多轮对话检查事实回忆，包含干扰对话、冲突信息和后续更新；FocusBench 检查个人 agent 在多轮交互和动态环境中处理真实阻碍、持续推进与适应的能力。这些是评估任务说明，不是对应的生产记忆流水线。
- **执行依赖 harness**：Model Card 明确指出实际表现会受量化、服务配置、提示、工具和 agent harness 影响。长上下文上限或模型自身能力，不能单独保证正确记忆或任务完成。

Meta 同时表示 Muse Wonder 先通过 Meta Model API 和 Muse Code 提供；公告称它将逐步用于 Muse，先向订阅用户推出。本文没有验证 Muse App 截至核对日是否已向特定账号开放新模型，不能把公告计划写成用户可见的已交付功能。

## 对记忆与 dreaming 的边界判断

**研究推论：Active Memory 更像“当前回合如何取用已有记忆”，不是独立的长期记忆数据库，也不是 dreaming。** 它说明记忆要能跨对话保留，也要能按当前任务重新找回。它没有说明事实如何抽取、纠错、过期、合并或遗忘。

Dreaming/反思可以负责在对话之外审阅近期互动、提出长期记忆或协作方式的候选更新；Active Memory 则更直接地指向对话或任务执行时的相关信息检索。两者可能协作，但 Meta 这次的公开资料没有说 Muse Wonder 使用夜间 dreaming、周期回顾或自动改写 SOUL 等机制。此前“闭源实现未知”的结论继续成立。

Active Focus 也不能替代 dreaming：前者强调当前目标的持续执行和适应，后者在 OpenMuse 的研究方案里是跨回合维护和反思。任务运行器负责尝试、检查阻碍与确认；记忆维护器负责提出有证据的持久化更新，不能因为任务完成就自动写入用户画像。

## 对 OpenMuse 设计的影响

1. 继续分清“持久事实存在哪里”和“本轮挑哪些事实放入上下文”。可靠的结构化记录与可读 Markdown 视图是 OpenMuse 的选择；Muse Wonder 的公开说明支持按任务取回相关背景的目标，但没有证实 Muse 使用相同存储结构。
2. 检索应带上来源、时间和有效状态，并优先使用与当前任务相关的信息。遇到更新或冲突时，不能把旧摘要无条件重复注入；应让新近明确纠正优先，同时保留变化历史。
3. 用两类场景分别验证：记忆测试覆盖跨对话、干扰项、相互冲突与后续更新；任务测试覆盖多轮阻碍、替代路径、新信息、澄清和重要操作确认。不能用单纯“回答里提到一条旧信息”代表记忆系统通过。
4. 不因模型支持长上下文就把全部历史或核心文件塞进每轮提示。检索与 agent harness 仍决定信息是否恰当、是否过期、是否安全；来源引用和敏感信息过滤仍要由产品层负责。

这些是研究对 OpenMuse 的建议，不是经用户批准的实现变更。

## 社区快照复核

`win4r/MuseAI-Skills` 的 `main` 与 `HEAD` 仍为 `38bbb45a2c5a0f70de975f6387385770b9ad8aac`，与 `SNAPSHOT.json` 固定版本相同；本轮没有新的社区 commit 可增量阅读。该仓库仍是社区归档，不能作为 Muse 官方实现证据。

## 来源与本地原始材料

- Meta AI Research，[Muse Wonder: A Frontier Model For Personal & Professional AI Agents](https://research.meta.ai/blog/muse-wonder)，发表于 2026-10-12，查阅于 2026-10-18。
- Meta Newsroom，[Introducing Muse Wonder and Muse Wonder Full: Frontier Models for Agents](https://about.fb.com/news/2026/10/introducing-muse-wonder-models/)，发表于 2026-10-12/13，查阅于 2026-10-18。
- Meta AI Research，[Muse Wonder Model Card](https://research.meta.ai/static/muse-wonder-model-card)，版本日期 2026-10-12，查阅于 2026-10-18。

原始网页与 PDF 只保存在被 Git 忽略的 `.research-local/muse-official/2026-10-18/`，不进入公开仓库：

| 本地原件 | 字节数 | SHA-256 |
|---|---:|---|
| `muse-wonder.html` | 337281 | `b564d477214db44b93a973c227df23244197d2427ecb5b8bdce2122d17fbea79` |
| `introducing-muse-wonder-models.html` | 497721 | `3cba068dd7b27e8a00f9a142eb04028b67b68a6d485176f10e451e414f1479ac` |
| `muse-wonder-model-card.pdf` | 384723 | `63e19276146bc146f1a14a2534360b9712641918f617ca432ef1443991f4edce` |
