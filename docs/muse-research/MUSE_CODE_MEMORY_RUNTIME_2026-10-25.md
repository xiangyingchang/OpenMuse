# Muse Code 的文件记忆与回合观察器

查阅日期：2026-10-25。来源级别：Meta 官方 Muse Code 配置文档、扩展文档与变更记录。本文讨论的是 **Muse Code 编程代理**，不是 Muse 消费者 App，也不是 Muse Wonder 模型的内部实现；不能据此认定两者共用同一套记忆系统。

## 官方资料明确说明的内容

- **记忆按范围分层**：默认的个人项目记忆保存在本机仓库之外，只对当前用户和项目可见；项目记忆放在仓库的 `.agents/memory/` 并可随仓库共享；个人记忆则跨项目使用。
- **Markdown 文件按需读取**：`MEMORY.md` 是主题文件索引，每个主题另有 Markdown 文件。会话开始时，Muse Code 注入索引和主题文件路径，不把所有主题正文一次塞入上下文；代理需要时再读正文。文档还说明，后台观察器可以在回答前补入相关记忆。官方给出的文件数上限是 48。
- **观察器先建议，再经协调**：Muse Code 文档列出记忆召回、技能召回、目标跟进、结果核验四种观察器。它们在主会话之外检查各自关注点，把简短建议交给协调环节；只有被接受的建议才进入主代理下一回合。官方文档称四种观察器默认开启，但运行门控或设置可以关闭。
- **已打开的会话可接收新记忆**：当前变更记录的 1.4.0 条目包括首次保存记忆和导入其他编码代理记忆的引导，也记录了会话开始后（包括在另一设备）保存的记忆会在该会话下一回合出现。变更记录没有给这些条目标注具体发布日期，因此这里只记录版本条目与本次查阅日期。
- **提醒存在模型条件**：同一变更记录说明，待办、记忆和目标提醒只在特定 Spark 版本且低于 `max` 推理强度时默认开启，其他配置默认关闭。此项提醒开关不能与上面所说的观察器默认状态混为一谈。

## 对记忆与 dreaming 的边界判断

**研究推论：**这份资料补充了“如何组织文件”和“当前回合如何取回文件”的官方实例。它把可持久的 Markdown 记忆、按需召回、回合内观察器分成不同职责；观察器只提出经过协调的上下文建议，不等于记忆写入或长期记忆晋升。

这与周期性回顾或 OpenMuse 所说的 dreaming 不同：观察器面向下一回合，资料没有描述夜间周期、对话归纳、人格演化或自动改写长期文件。也没有说明 Muse Code 如何合并冲突、判断过期、执行彻底遗忘或跨设备同步。更不能把这些行为归给 Muse App；消费端 Muse 的具体记忆维护算法仍未公开。

## 对 OpenMuse 研究与设计的影响

1. 持续记忆要分别回答“事实保存在哪里”和“当前问题挑哪些事实进入上下文”。`MEMORY.md` 索引加主题文件的方式说明，完整资料可留在文件中，提示词只放轻量索引，具体内容按需读取；这是一种可参考的组织方案，不证明 OpenMuse 必须采用相同存储结构。
2. 保存后要有明确的可见性时效。Muse Code 的官方变更记录给出了一个具体交互结果：新记忆无需重启会话，下一回合即可使用。OpenMuse 可据此把“当前会话写入后能否读取”和“其他设备更新何时可见”作为独立验收场景；资料没有披露其同步实现或延迟保证。
3. 把召回建议与事实晋升隔开。回合观察器可以帮助模型想起相关资料，但不应因此自动把推测写进用户画像或 SOUL。持久化仍需来源与证据，任何用户确认门槛按 OpenMuse 自身决定执行。
4. 不以这份开发者产品资料推断 Muse App 的 dreaming、记忆 schema 或同步语义。继续保留“官方消费端机制未公开”的结论。

以上是对官方开发者资料的归纳和 OpenMuse 研究推论，没有进行 Muse Code 运行测试或 Muse App 真机观察。

## 来源与本地原始材料

- Meta Model API，[Configuration and context](https://dev.meta.ai/docs/muse-code/configuration)，查阅于 2026-10-25。
- Meta Model API，[Extending and automating](https://dev.meta.ai/docs/muse-code/extending)，查阅于 2026-10-25。
- Meta Model API，[Changelog](https://dev.meta.ai/docs/muse-code/changelog)，查阅于 2026-10-25；相关条目见 1.4.0。
- Meta AI Research，[Muse Wonder: A Frontier Model For Personal & Professional AI Agents](https://research.meta.ai/blog/muse-wonder)，发表于 2026-10-12，作为消费端公开能力的边界参照；查阅记录见 [上一专题](ACTIVE_MEMORY_AND_FOCUS_2026-10-18.md)。

网页原件仅保存在被 Git 忽略的 `.research-local/muse-official/2026-10-25/`，不进入公开仓库：

| 本地原件 | 字节数 | SHA-256 |
|---|---:|---|
| `configuration.html` | 199038 | `7a5ef453d4da9b397d715b1ec96269b40e4caefc57b94cb46aa8010e73e5b34a` |
| `extending.html` | 232584 | `08811f13b070ec7629182f4979070ff9b3bcc24d7e5eece70b0c46baa209eda9` |
| `changelog.html` | 2059232 | `af04d021d3128c2bea41f1bdac6889d49246c2ae2ae8237985250562e9ea1aae` |
