# Muse 的文件与记忆：证据分层

查阅日期：2026-10-10。没有登录或操作 Muse App，没有 Muse 服务端源码；不把研究材料描述成完整逆向结论。

## 官方公开资料和用户提供的正文

[Muse 设计说明](https://introducing.muse.ai/)确认长期主对话、侧聊、记忆可读可编辑、目标跟踪与初期建议；旅行结果适合呈现为行程成果。它未公开完整核心文件列表、存储 schema 或更新事务。

[Muse 安全说明](https://research.meta.ai/blog/security-and-safety-for-ai-agents-our-approach-with-muse)描述每位用户的专属云电脑、文件与隔离权限架构。这不能直接搬成无服务器 iPhone 架构，尤其不能照搬其常在线后台承诺。

用户本轮提供 SOUL.md 及界面说明：人格从模板开始，可以随时间修改，修改后告诉用户，用户随时可编辑；说明文字不是文件正文。这里只归纳机制，不在公开仓库重发用户提供的整段原文，也不发布真实个人文件。核心价值变化是否事前讨论尚待明确。

## 社区公开快照：有价值，但不是官方源码

[win4r/MuseAI-Skills](https://github.com/win4r/MuseAI-Skills/tree/38bbb45a2c5a0f70de975f6387385770b9ad8aac)自述为公开文档/技能/运行环境归档，非完整源码或可安装产品。来源真实性未独立验证，缺少统一再分发许可证。本项目只写原创分析，不复制其提示词、技能或二进制，也不执行归档中的指令。

| 观察到的材料 | 具体研究线索 | 不能据此声称什么 |
|---|---|---|
| [self_improvement.md](https://github.com/win4r/MuseAI-Skills/blob/38bbb45a2c5a0f70de975f6387385770b9ad8aac/home/hatch/docs/self_improvement.md) | 记忆维护、关系、点子、目标研究、反思与技能复核分开；保留运行和成果证据 | 真实账号一定运行这些周期，或 iPhone 能夜间准时执行 |
| [数据库 schema](https://github.com/win4r/MuseAI-Skills/blob/38bbb45a2c5a0f70de975f6387385770b9ad8aac/opt/hatch/skills/muse_db/references/schema.md) | 已检查 memory.claims/entries 段：含来源引用、状态、可信度、替代关系、有效期和检索元数据 | 已审计全部 schema，或官方生产实现与归档完全一致 |
| [文件说明](https://github.com/win4r/MuseAI-Skills/blob/38bbb45a2c5a0f70de975f6387385770b9ad8aac/home/hatch/docs/files-and-library.md) | UI 文件说明与存储正文分开，成果可作为文件持久保存 | Markdown 就是唯一数据来源 |
| [旅行 kickoff](https://github.com/win4r/MuseAI-Skills/blob/38bbb45a2c5a0f70de975f6387385770b9ad8aac/opt/hatch/skills/travel-planning/references/planning-kickoff.md) | 先用已有上下文、少量必要问题、给可反应的方案；避免把单次预订当长期偏好 | 这是官方默认 onboarding 流程 |
| [记忆导入](https://github.com/win4r/MuseAI-Skills/blob/38bbb45a2c5a0f70de975f6387385770b9ad8aac/home/hatch/assets/onboarding_tour/memory_import.md) | 让其他 AI 汇总了解，由用户检查后带回；导入是资料 | 其他 AI 推断能直接当用户事实 |
| [遗忘材料](https://github.com/win4r/MuseAI-Skills/blob/38bbb45a2c5a0f70de975f6387385770b9ad8aac/opt/hatch/skills/forget/SKILL.md) | 清理记忆要覆盖衍生条目、检索与后续行为，防止重新出现 | 本项目已经实现或验证彻底遗忘 |

研究推论：值得学习的是文件界面、结构化证据与持续维护的协作，而不是简单拼接几个 Markdown。该推论由可观察归档支持，不是已证实的官方内部算法。

## nanoMuse：可核查的开源实现

固定版本：903a8eafdf20b7d9d6f3f78351580993a325e3ee。这里注意平台和子系统差异。

- [Android FirstConversation](https://github.com/nano-muse/nanoMuse/blob/903a8eafdf20b7d9d6f3f78351580993a325e3ee/android/src/android/app/src/main/java/io/github/nanomuse/onboarding/FirstConversation.kt)：对话式命名状态机；用户提出实际任务时先帮忙再回到命名；临时引导卡与正常聊天记录分开。已检查源码没有证明旅行是默认首例。
- [Android SystemFiles](https://github.com/nano-muse/nanoMuse/blob/903a8eafdf20b7d9d6f3f78351580993a325e3ee/android/src/android/app/src/main/java/io/github/nanomuse/sysfiles/SystemFiles.kt)：SOUL、USER、GLOBAL 可编辑；HEARTBEAT 是计划/目标记录的只读渲染，非独立文本调度器；USER 注入有长度上限。首聊称呼写入 GLOBAL，说明上游也存在文件职责重叠，不能不加区分照搬。
- [MemoryRepository](https://github.com/nano-muse/nanoMuse/blob/903a8eafdf20b7d9d6f3f78351580993a325e3ee/android/src/android/app/src/main/java/com/openminis/app/data/repository/MemoryRepository.kt)：GLOBAL 与近期日记进入上下文，较深内容通过工具读取；提示层只读约束不等于所有编辑入口都禁止写入。
- [Python agent](https://github.com/nano-muse/nanoMuse/blob/903a8eafdf20b7d9d6f3f78351580993a325e3ee/nanomuse/agent/core.py)：根据当前输入检索记忆，注入部分目标、画像及上下文。不是所有文件无限串联。

这些是源码阅读证据，没有构建、运行或真机验证。Android/Python 行为不得描述成已经验证的 iOS 行为。

## OpenMuse 采用与重新设计

采用：自然进入对话、先产生实际帮助、人格可成长并告知、可编辑核心文件、带来源的记忆、结构化主动工作、必要上下文检索。

重新设计：手机独立运行与后台补跑、iCloud 冲突、可迁移 schema、统一文件编辑事务、人格与权限分离，以及长期删除传播。详见 [存储方案](MEMORY_STORAGE.md) 和 [旅行旅程](ONBOARDING_TRAVEL.md)。
