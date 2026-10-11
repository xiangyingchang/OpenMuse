# Muse 官方公开机制补充核对

核对日期：2026-10-11。来源级别：Meta 官方产品设计、产品公告与安全技术文章。本文是对公开说明的原创归纳，不是源码审计或 Muse 账号行为实测。

## 本轮核对结果

`win4r/MuseAI-Skills` 的 `main` 与 `HEAD` 仍为 `38bbb45a2c5a0f70de975f6387385770b9ad8aac`，与 2026-10-10 固定快照一致；没有新社区提交需要增量阅读。本轮补充细读了官方安全架构说明，填补此前仅作高层引用、尚未纳入记忆设计评估的部分。

## 官方公开资料确认的机制

- **数据驻留与系统记录**：每位用户有独立的云端 Linux VM，官方称该 VM 是用户放入 Muse 的数据之系统记录位置。客户端通过安全传输直接连接用户 VM。官方还说明 VM 数据会持续备份，用户可以查看、编辑和下载文件，包括 Muse 对用户的记忆。
- **文件与结构化状态并存**：工作区、文件和运行工具位于隔离运行容器；官方同时说明持久应用状态存放在运行容器与凭证库之外的 PostgreSQL 中。公开文章没有解释记忆文件与数据库表的同步关系，不能据此推断 Markdown 文件是唯一真值，或 PostgreSQL 里存放哪些记忆字段。
- **人格与能力演进**：产品设计说明支持为 Muse 选择名字、头像和风格；安全文章概述 Muse 能构建自己的工具并编辑自身。公开材料没有说明它是否会自动改写人格文件、变更审批、版本控制或通知规则。用户提供的 SOUL 文件说明属于用户材料，不能提升为公开的通用机制证明。
- **长期与主动工作**：官方确认主对话跨会话保留记忆，并用侧聊隔离复杂主题；目标可进入专门视图持续跟踪。任务可以按计划或相关事件在 App 关闭后继续，完成后台工作后，系统判断是否有实质新进展或需要用户决策再通知。Ideas 会结合目标、模式和对话建议下一步或计划调整。官方未公开定时器、事件判定、记忆抽取或 dreaming 的具体实现。
- **安全与授权边界**：主 Agent 在受限运行单元内处理不可信输入；凭证服务与内置连接器工作进程分离，Agent 不直接看到真实凭证。Sentinel 是连接器操作及网络出口的独立授权点。常规浏览和满足窄范围策略的低风险流量可免打扰；对外发送、购买及其他需要人工决定的操作会停下请求批准。官方把逐次审批与访问控制区分，而不是对每条本地命令一律弹窗。
- **忘记与训练**：用户可以要求 Muse 忘记指定信息，并可选择不将其交互用于 Meta 模型训练。公开资料没有完整描述遗忘如何清理派生索引、历史副本、dreaming 产物和备份恢复后的数据。

来源：[How We Designed Muse](https://introducing.muse.ai/)；[Introducing Muse](https://about.fb.com/news/2026/09/introducing-muse-personal-ai-agent/)；[How We Built Safety Into Muse](https://research.meta.ai/blog/security-and-safety-for-ai-agents-our-approach-with-muse)。官方文章发表于 2026-09；本轮于 2026-10-11 重新查阅。完整链接另见本研究档案及忽略目录中的原始网页快照。

## 对 OpenMuse 的判断

官方资料进一步支持“可靠结构化记录 + 人可读文件 + 独立运行时和凭证边界”的方向，但没有提供可照抄的 Muse 记忆 schema 或更新算法。OpenMuse 应继续把 SQLite 结构化记录作为可验证的事实与目标状态来源，把 Markdown 作为可阅读、可编辑和可迁移的工作区投影，并清楚记录两者的映射、修订和冲突；不能声称 Muse 也是这样实现的。

Dreaming、事实写入和人格演化应是不同的维护流程：反思可提出候选，但不应顺带取得工具权限；记忆候选需要来源和时间；用户纠正、删除和遗忘要覆盖后续检索及派生摘要。定时维护只能报告真实运行状态，不能把 Muse 云端 VM 的后台持续执行承诺照搬到 iOS。

这次资料没有补出官方 dreaming 算法、记忆文件清单、自动更新节奏、事实冲突裁决、SOUL 改写流程或完整遗忘语义。上述仍是闭源未知，需结合用户的 Muse 实际使用继续核对。

## 原始网页快照校验

HTML 原件只保存在被 Git 忽略的 `.research-local/muse-official/2026-10-11/`，不进入公开仓库。SHA-256：

| 原件 | 来源 | SHA-256 |
|---|---|---|
| `how-we-designed-muse.html` | [introducing.muse.ai](https://introducing.muse.ai/) | `5123aee2196429b0a0890d3ebb91a79afb2a284625c0c2164b17c85ea841bc79` |
| `introducing-muse.html` | [about.fb.com](https://about.fb.com/news/2026/09/introducing-muse-personal-ai-agent/) | `1a002a97dfc169b3bbbb5619c1e09ace7f4ea4f9d8762914b08e8ee02ee73132` |
| `how-we-built-safety-into-muse.html` | [research.meta.ai](https://research.meta.ai/blog/security-and-safety-for-ai-agents-our-approach-with-muse) | `5ce808d29396024e94b3bcc8bb355d941b576c1e9338f53b5edc9c7701b843f7` |
