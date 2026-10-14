# OpenMuse

一个持续认识你、陪你把想做的事情一步步做成的开源个人 AI。面向中国用户，正在开发 iOS 与 macOS 客户端，并支持自定义模型。

> 当前状态（2026-10-15，本地工作区）：T88 Release `0.1.4 (16)` 已安装并启动于 iPhone 16 Pro / iOS 27.2；本轮修复结构化参考资料被模型当作用户消息回显的问题。完整 `swift test` 通过288项（286通过、2项条件跳过），Release ARM64 构建与签名校验通过。没有重放真实模型聊天、做 PUA 视觉验收或旅行流程回归，也没有导出 IPA。真实 iPhone→Mac Pi 委派、蜂窝外网、中国境内网络、锁屏后台、真实连接器、14天连续自用和 Muse 逐页视觉对照仍未完成。详见[开工状态与方案入口](docs/STARTUP_REVIEW.md)、[T88 记忆上下文泄漏修复](docs/ITERATIONS.md#t88)、[覆盖审计](docs/REQUIREMENT_AUDIT_2026-10-10.md)和[一期对照表](docs/PHASE1_PARITY.md)。

长期目标是让一个人拥有可携带、可纠正、会随生活变化而成长的 AI 陪伴者。产品价值来自真实帮助、连续理解与目标进展。

> 端侧运行：iOS 已集成固定版本的 iSH/Alpine ARM64。用户确认普通 iSH 命令和 guest 出站网络无需逐次审批；guest 可发送其可读资料到互联网。T67 真机 HTTPS GET 返回200，但 DNS 结果为 `198.18.0.45` 保留地址，只能证明当时设备网络路径可用，不能证明公网 DNS 或中国境内直连。Build 4 的真机浏览器操作见 T68；T88 已重装，但没有重测浏览器与 iSH 功能。详见[端侧运行时](docs/ON_DEVICE_RUNTIME.md)和[迭代记录](docs/ITERATIONS.md)。

## 四个核心体验

- **目标陪伴**：从对话发现意图，默认主动记录和追踪，通过提问形成计划，随执行结果调整，直到完成、暂停或放弃。
- **兴趣动态**：结合兴趣与当前目标推荐有来源的内容；从一条内容直接继续对话、学习或实践。
- **持续记忆**：区分事实、推测、短期状态和历史，持续更新，并允许查看、纠正、遗忘和迁移。
- **个性化点子**：结合获准接入的邮件、Notion、Obsidian、导入聊天和手动记忆，给出值得行动的建议。

## 已确定的方向

一期以 Muse 的交互和运行机制为对齐目标。Mac 在线连接本机 Pi 执行，Mac 离线由 iPhone 接手其支持的任务；首期支持 OpenAI、DeepSeek 和自定义模型 API；不依赖自建云端执行服务器；数据同步优先研究 iCloud。模型 API 可以是用户选择的远程服务，“无云端执行服务器”不代表所有推理都在本地。

Mac 配对通道代码可转发 Pi 模型回合并同步结构化工作区记录，含记忆遗忘墓碑；Mac 本机可选定只读资料目录，Pi 通过受限临时快照列出/读取文本文件。单轮任务 owner 交接、工具事件轮询和检查点有 Core/bridge 测试，但真实 iPhone→Mac Pi 委派尚未真机验收。此前 iPhone 与 Mac 配对和首次同步已通过；18项版本冲突仍待用户选择。断线状态确认、长任务续跑、离线分支选择、Mac 浏览器和写文件仍未完成，不能把它描述为完整电脑控制。Mac 首次启用时会在独立 HTTPS 8443 端口添加 `/openmuse` Serve 路由；若端口已被其他服务占用，会停止并保留原设置。它不修改现有443路由，也不启用 Funnel。

iOS 端侧 runtime 参考 OpenMinis 的 iSH/Alpine、tool loop、隔离工作区与原生 offload 分层；原生交互技术参考 Lody iOS，产品交互结构参考 Muse。固定版本的 iSH/Alpine ARM64 已集成；按用户确认，普通命令和 guest 出站网络不增加逐次审批，只能访问当前对话挂载目录和 guest 私有 rootfs。iSH 与 App 共进程，不是强隔离虚拟机。原生 iOS offload、rootfs 升级和锁屏持续执行仍待完成或实测。真机命令验收状态见[端侧运行时设计](docs/ON_DEVICE_RUNTIME.md)与[最新迭代记录](docs/ITERATIONS.md)。

## 讨论与迭代查询

从[讨论索引](docs/DISCUSSIONS.md)查询历史修正、[决定](docs/DECISIONS.md)、[待决事项](docs/STARTUP_REVIEW.md)和[迭代记录](docs/ITERATIONS.md)。新增[设计原则](docs/DESIGN_PRINCIPLES.md)、[双端与文件关系](docs/DEVICE_AND_FILES.md)及[长期记忆运行机制对照与评估](docs/MEMORY_RUNTIME_COMPARISON_2026-10-11.md)。

从[开工状态](docs/STARTUP_REVIEW.md)查询方案与实际实现进度。请以[需求覆盖审计](docs/REQUIREMENT_AUDIT_2026-10-10.md)和[迭代记录](docs/ITERATIONS.md)中的测试、构建和设备证据为准。

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
17. [iPhone 端侧 Agent Runtime 设计](docs/ON_DEVICE_RUNTIME.md)

长期“电脑”入口将参考 UU 远程，连接个人电脑的远程桌面；连接与控制方案待设计。

## 开源与命名

本仓库原创应用代码与文档采用 GNU GPL-3.0；iSH fork 保留自己的许可文件，ZIPFoundation 与 Alpine 软件包按各自许可分发。具体版本、依赖清单与许可说明见[第三方声明](THIRD_PARTY_NOTICES.md)，iPhone App 内也可查看许可材料。公开仓库不保存个人对话、记忆、凭证或私人连接器数据。

OpenMuse 是暂定工作名。本项目独立于 Meta Muse、nanoMuse、OpenMinis、Lody 及已有的 CopilotKit/OpenMuse 项目，正式发布前会重新确认品牌命名。
