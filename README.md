# OpenMuse

一个持续认识你、陪你把想做的事情一步步做成的开源个人 AI。面向中国用户，计划提供 iOS 与 macOS 客户端，可自定义模型。

> 当前状态：需求与技术调研阶段。没有可运行 App；尚未批准进入实现。

长期目标是让一个人拥有可携带、可纠正、会随生活变化而成长的 AI 陪伴者。产品价值来自真实帮助、连续理解与目标进展。

## 四个核心体验

- **目标陪伴**：从对话发现意图，默认主动记录和追踪，通过提问形成计划，随执行结果调整，直到完成、暂停或放弃。
- **兴趣动态**：结合兴趣与当前目标推荐有来源的内容；从一条内容直接继续对话、学习或实践。
- **持续记忆**：区分事实、推测、短期状态和历史，持续更新，并允许查看、纠正、遗忘和迁移。
- **个性化点子**：结合获准接入的邮件、Notion、Obsidian、导入聊天和手动记忆，给出值得行动的建议。

## 已确定的方向

一期以 Muse 的交互和运行机制为对齐目标。Mac 在线连接本机 Pi 执行，Mac 离线由 iPhone 接手其支持的任务；首期支持 OpenAI、DeepSeek 和自定义模型 API；不依赖自建云端执行服务器；数据同步优先研究 iCloud。模型 API 可以是用户选择的远程服务，“无云端执行服务器”不代表所有推理都在本地。

iOS 运行环境参考 OpenMinis，原生交互技术参考 Lody iOS，产品交互结构参考 Muse。手机后台长期执行仍是待验证边界，不能以同步或保活代码替代真实设备证明。

## 讨论文档

1. [产品需求](docs/PRD.md)
2. [交互与典型旅程](docs/EXPERIENCE.md)
3. [公开资料调研](docs/RESEARCH.md)
4. [技术方案与取舍](docs/ARCHITECTURE.md)
5. [手机后台执行专项](docs/IOS_BACKGROUND.md)
6. [落地节奏和验收](docs/ROADMAP.md)
7. [已确认与待决策事项](docs/DECISIONS.md)
8. [证据版本快照](docs/SOURCES.json)
9. [轻松首聊：旅行计划](docs/ONBOARDING_TRAVEL.md)
10. [核心文件、记忆与迁移](docs/MEMORY_STORAGE.md)
11. [Muse 记忆机制的证据分层](docs/MUSE_MEMORY_RESEARCH.md)
12. [Muse 持续研究档案：记忆维护与 dreaming](docs/muse-research/README.md)
13. [其他 AI 记忆迁移与预埋提示词](docs/MEMORY_TRANSFER.md)
14. [iOS/macOS 技术选型推荐](docs/APP_STACK.md)
15. [一期 Muse 对齐与需求验收](docs/PHASE1_PARITY.md)
16. [Muse iOS 真机交互记录](docs/muse-research/IOS_INTERACTIONS_2026-10-10.md)

长期“电脑”入口将参考 UU 远程，连接个人电脑的远程桌面；连接与控制方案待设计。

## 开源与命名

本仓库当前原创文档使用 MIT 许可证。未来应用代码的许可证必须与实际复用的上游组件共同确定；尚未导入任何上游代码。公开仓库不保存个人对话、记忆、凭证或私人连接器数据。

OpenMuse 是暂定工作名。本项目独立于 Meta Muse、nanoMuse、OpenMinis、Lody 及已有的 CopilotKit/OpenMuse 项目，正式发布前会重新确认品牌命名。
