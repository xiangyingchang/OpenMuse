# Muse Active Memory 推出进展与长期任务线索

查阅日期：2026-11-22。本文记录官方公开资料与社区增量检查；没有登录或操作 Muse App，也没有检查用户账号是否收到新模型。这里的“推出”仅表示 Meta 已公开宣布逐步提供，不代表每个地区、账号或版本均已获得。

## 官方公开资料

### 专用模型把 Active Memory 扩展到 Muse

Meta AI Research 在 2026-11-06 宣布，将以 Muse Wonder 训练的专用模型逐步提供给 Muse 与 Meta AI 用户。Meta 称这些模型把 Active Memory 与 Active Focus 带到更广泛的产品模型中。

- **Active Memory 的能力描述**：记住重要信息，在后续对话中识别何时相关；模型被训练去区分临时和长期信息、跨时间推理，以及识别仍有效或已过时的内容。
- **官方公布的评估结果**：Meta 报告 Muse 模型在 Active Memory 评估上的结果为 90%，此前模型为 76%；另称忘记关键目标信息的情况减少 2.4 倍。文章未在此处给出评估样本、具体方法或置信区间，数字应作为 Meta 自报结果，而不是独立复现结果。
- **Active Focus**：Meta 报告，遇到意外阻碍时，Muse 完成日常任务的表现提升 67%。这支持“处理阻碍并继续推进”的能力方向，不说明代理在手机后台持续运行，也没有披露任务调度器或唤醒机制。

这次公告把 Active Memory 从 Muse Wonder 的能力介绍推进到面向 Muse 产品的专用模型推出阶段，是相对于 2026-10-18 记录的实质进展。它仍然是模型能力与产品推广的公开描述：没有说明生产环境的记忆数据库、文件格式、写入/纠错/合并/删除事务、用户审阅流程，也没有提到 dreaming 或自动改写 SOUL。

### 跨周复用偏好的具体产品场景

Meta 在 2026-11-18 介绍 Loblaw 零售连接器时称，Muse 可以记住品牌偏好和食物过敏信息，让用户下周继续规划餐食时受益。公告也说明用户选择 Muse 可访问的连接器，并且发送邮件、购买等敏感操作前会再次确认。

这是官方公开的“偏好在重复任务中跨周复用”例子。它没有说明偏好是用户明确保存、从对话推断还是由其他方式形成，也没有披露记忆如何纠正、过期或删除。不能据此推断 OpenMuse 应把饮食偏好写入某一个特定 Markdown 文件。

### Muse Code 的上下文与后台工作更新

对照本地忽略目录中 2026-11-15 保存的官方 Muse Code changelog（页面当时显示 1.4.18）与 2026-11-22 页面（现显示 1.4.24），本轮定位到以下相关条目。官方 changelog 未为这些版本标注发布日期：

- **1.4.21**：`run.system_prompt_append` 将用户补充文本附加在内置 system prompt 后；会话可覆盖该设置，恢复或分叉时保留其值。这是 Muse Code 的会话配置行为，不是消费者 Muse App 的人格文件机制。
- **1.4.23**：上下文压缩摘要使用同一会话和 prompt cache；摘要保留用户消息列表，长消息被缩短时将完整文本放在文件中。这是对长对话溯源和内容保留的工程处理，不代表这些原文文件是长期记忆。
- **1.4.24**：慢速 MCP 调用可转到后台继续；用户发送新消息时也可触发切换，完成结果之后加入当前对话。这是 Muse Code 的可见后台任务生命周期，不代表手机 App 能在用户离开后持续执行。

这些变更把“提示配置、对话原文与压缩摘要、后台任务结果”作为不同的运行态对象处理。它们可作为稳健上下文管理的技术参考，但不应归因于消费者 Muse 的内部实现。

Meta 于 2026-11-17 发布 Muse 在澳大利亚推出的公告，也提到当地逐步提供 Spaces 和语音；该公告是地区功能可用性信息，没有增加记忆维护或 dreaming 机制证据。

## 社区增量

`win4r/MuseAI-Skills` 的 `main` 与 `HEAD` 在 2026-11-22 均为 `e222ba4391b6270ba394cd2b8c3809ff959ab609`，与 2026-11-15 检查点相同。没有新 commit，因此本轮没有新增社区文件可读，也没有变化可归入社区实现证据。上一检查点相对于原始快照的四个 commit 只修改 README 中的 Bilibili 链接标题，详见[2026-11-15 增量审阅](INCREMENTAL_REVIEW_2026-11-15.json)。本轮固定 commit 对比记录见[增量检查 JSON](INCREMENTAL_REVIEW_2026-11-22.json)。

## 对 OpenMuse 研究的影响

以下是研究推论，不是 Muse 官方实现说明，也不是用户批准的实现变更：

1. **把记忆是否持久与本轮是否适用分开评估。** 一条稳定偏好可以保留，但检索时还要判断当前任务是否相关；短时状态需要时间边界。评测可构造跨日相对时间场景，检查过期状态是否仍被误当作当前安排。
2. **为跨周重复任务建立可核验场景。** 例如下周再次规划时应取回用户明确给出的长期偏好；用户纠正偏好后，应使用新值并保留来源和更新时间。评估重点是“恰当取回、辨别过时、尊重纠正”，不是仅看答案是否提到旧信息。
3. **长任务要分别检查用户原话、压缩摘要、文件成果和后台结果。** Muse Code 的 changelog 显示它们有不同的保存与到达路径；对 OpenMuse 的研究问题是重开/压缩/新消息到达后，哪些证据和任务状态仍可追溯。不要把运行缓存当成长记忆。
4. **Dreaming 与人格演化仍属未公开机制。** Active Memory 的新描述没有证实周期回顾、夜间任务或自动改写 SOUL。OpenMuse 的研究边界仍是：反思可以提出候选更新，但长期事实和人格改动需要独立证据、可见变更与用户控制。

## 来源与原件校验

来源等级为官方公开资料；查阅日期均为 2026-11-22。原始网页只保存在被 Git 忽略的 `.research-local/muse-official/2026-11-22/`，未复制原文到公开文档。

| 来源 | 页面日期/范围 | 本地原件 | 字节数 | SHA-256 |
|---|---|---|---:|---|
| [Meta AI Research：Bringing Specialized Models to Muse and Meta AI](https://research.meta.ai/blog/specialized-models-for-muse-and-metaai) | 2026-11-06 | `specialized-models.html` | 200161 | `ca1f8b8755d24de513a01d801f9a9b3be492c2ea06bbad0d1ac3ac6be67ec381` |
| [Meta Newsroom：Meta Welcomes Loblaw as First Canadian Retail Partner to Muse](https://about.fb.com/news/2026/11/meta-welcomes-loblaw-as-first-canadian-retail-partner-to-muse/) | 2026-11-18 | `loblaw-connector.html` | 538001 | `846655da367e0e214527fad29de289b62542693522fdeb26226d3f2e8680479a` |
| [Meta Newsroom：Muse Is Now Available in Australia](https://about.fb.com/news/2026/11/muse-is-now-available-in-australia/) | 2026-11-17 | 地区可用性核对 | 335108 | `82a62f59ce6acee793b9d2c950ffa468800da2f1f84cdd4b13fbc544a75fc2b4` |
| [Meta Model API：Muse Code changelog](https://dev.meta.ai/docs/muse-code/changelog) | 2026-11-22 页面显示 1.4.24；与 2026-11-15 原件显示的 1.4.18 对比 | `changelog.html` | 3836192 | `224a28565d7daee820a600714962cae806392ae4b6fc444aa8a08c65f23f9262` |

校验命令：`sha256sum .research-local/muse-official/2026-11-22/*`。以上四个原件均由 `.gitignore` 中的 `.research-local/` 规则忽略，不进入 Git 提交。
