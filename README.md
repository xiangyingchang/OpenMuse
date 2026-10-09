# OpenMuse

一个持续认识你、陪你把想做的事情一步步做成的开源个人 AI。面向中国用户，正在开发 iOS 与 macOS 客户端，并支持自定义模型。

> 当前状态（2026-10-10）：双端原生工程、本机持久化和首个体验界面已实现。Mac Debug App 已构建并启动，iOS 模拟器 App 已安装并启动；iPhone 真机签名等待在 Xcode 登录 Apple Account。Mac 的 loopback 桥接、一次性配对与独立 Tailscale Serve 路由已实现；本机配对生命周期测试通过，但 Mac 的 `URLSession` 对 Tailscale HTTPS 自连接仍失败，iPhone 当前离线，因此跨设备能力尚未验收。真实模型凭证、资料同步和 Pi 电脑工具也未完成。详见[迭代记录](docs/ITERATIONS.md)与[双端协议](docs/RUNTIME_PROTOCOL.md)。

长期目标是让一个人拥有可携带、可纠正、会随生活变化而成长的 AI 陪伴者。产品价值来自真实帮助、连续理解与目标进展。

## 四个核心体验

- **目标陪伴**：从对话发现意图，默认主动记录和追踪，通过提问形成计划，随执行结果调整，直到完成、暂停或放弃。
- **兴趣动态**：结合兴趣与当前目标推荐有来源的内容；从一条内容直接继续对话、学习或实践。
- **持续记忆**：区分事实、推测、短期状态和历史，持续更新，并允许查看、纠正、遗忘和迁移。
- **个性化点子**：结合获准接入的邮件、Notion、Obsidian、导入聊天和手动记忆，给出值得行动的建议。

## 已确定的方向

一期以 Muse 的交互和运行机制为对齐目标。Mac 在线连接本机 Pi 执行，Mac 离线由 iPhone 接手其支持的任务；首期支持 OpenAI、DeepSeek 和自定义模型 API；不依赖自建云端执行服务器；数据同步优先研究 iCloud。模型 API 可以是用户选择的远程服务，“无云端执行服务器”不代表所有推理都在本地。

当前连接实验只转发模型回合，不会同步消息、记忆、目标或构件，也没有打开 Mac 文件和浏览器工具；Pi 工具保持关闭。不能把模型代理称为电脑执行。Mac 首次启用时会在独立 HTTPS 8443 端口添加 `/openmuse` Serve 路由；若端口已被其他服务占用，会停止并保留原设置。它不修改现有443路由，也不启用 Funnel。

iOS 运行环境参考 OpenMinis，原生交互技术参考 Lody iOS，产品交互结构参考 Muse。手机后台长期执行仍是待验证边界，不能以同步或保活代码替代真实设备证明。

## 讨论与迭代查询

从[讨论索引](docs/DISCUSSIONS.md)查询历史修正、[决定](docs/DECISIONS.md)、[待决事项](docs/STARTUP_REVIEW.md)和[迭代记录](docs/ITERATIONS.md)。新增[设计原则](docs/DESIGN_PRINCIPLES.md)及[双端与文件关系](docs/DEVICE_AND_FILES.md)。

从[开工状态](docs/STARTUP_REVIEW.md)查询方案与实际实现进度。请以[迭代记录](docs/ITERATIONS.md)中的测试、构建和设备证据为准。

## 讨论文档

1. [产品需求](docs/PRD.md)
2. [交互与典型旅程](docs/EXPERIENCE.md)
3. [公开资料调研](docs/RESEARCH.md)

## 本地构建

需要 Xcode、Swift 和 XcodeGen。运行 `xcodegen generate` 后打开 `OpenMuse.xcodeproj`，选择 `OpenMuseMac` 或 `OpenMuseiOS` scheme。核心测试和 Pi 本地夹具见[开发验证说明](docs/DEV_TESTING.md)。
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

本仓库原创文档与应用代码使用 MIT 许可证。当前没有导入上游代码；以后如复用上游组件，会先核对许可证和分发要求。公开仓库不保存个人对话、记忆、凭证或私人连接器数据。

OpenMuse 是暂定工作名。本项目独立于 Meta Muse、nanoMuse、OpenMinis、Lody 及已有的 CopilotKit/OpenMuse 项目，正式发布前会重新确认品牌命名。
