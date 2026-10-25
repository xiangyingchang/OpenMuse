# 研究更新记录

## 2026-10-25：Muse Code 文件记忆与观察器

- 新核对 Meta 官方 Muse Code 配置、扩展和变更记录：记忆有个人项目、共享项目和跨项目个人范围；Markdown 用索引加主题文件组织，并按需加载；回合观察器对记忆召回、技能、目标和核验分别提出建议，再由协调环节决定是否交给主代理。
- 变更记录 1.4.0 说明会话开始后保存的新记忆（包括另一设备的更新）会在当前会话下一回合可见，并提供首次保存与迁移记忆的引导。它没有标注这些条目的具体发布日期，因此只记作本轮发现的版本行为。
- 这是 Muse Code 的公开机制，不是消费者 Muse App 的实现证据。它补充了按需召回与会话内更新时效的设计参考，但未披露周期性 dreaming、消费端的记忆文件结构、冲突合并或跨设备同步保证。
- `win4r/MuseAI-Skills` 的 HEAD 仍为 `38bbb45a2c5a0f70de975f6387385770b9ad8aac`；本轮没有新社区提交可供增量阅读。官方页面本地快照校验值及 OpenMuse 设计影响见[专题记录](MUSE_CODE_MEMORY_RUNTIME_2026-10-25.md)。

## 2026-10-18：Muse Wonder 的 Active Memory 与 Active Focus

- Meta 官方研究文章、新闻稿与 Model Card 新增了 Active Memory / Active Focus 的明确能力描述。前者强调跨对话保留重要背景并按当前任务主动取回；后者强调长任务中尝试替代路径、处理阻碍、适应新信息、必要时澄清并在重要操作前确认。
- Model Card 将记忆与持续执行分开评估：MemoryBench 包含 64K–100K 多轮对话、干扰项、冲突与后续更新；FocusBench 检查跨多轮交互处理动态阻碍的能力。评估设计不能当作生产机制说明。
- 这补充了“持续记忆必须兼顾恰当检索”的官方能力目标，但没有披露文件/数据库 schema、记忆写入与遗忘算法，也没有确认 Muse 使用 dreaming。公告称 Muse Wonder 将逐步进入 Muse；没有据此声称用户当前版本已经获得新模型。
- 社区 `main`/`HEAD` 仍是 `38bbb45a2c5a0f70de975f6387385770b9ad8aac`，无新增 commit。来源、OpenMuse 设计影响、原始材料校验见 [专题记录](ACTIVE_MEMORY_AND_FOCUS_2026-10-18.md)。

## 2026-10-12：OpenClaw Dreaming 与反思文件边界复核

- 复核 OpenClaw 官方当前 [Dreaming](https://docs.openclaw.ai/concepts/dreaming) 和 [Memory architecture](https://docs.openclaw.ai/concepts/memory-architecture)：Light/REM 整理短期候选与主题，Deep 在确定性门槛后才改写精选 `MEMORY.md`；`DREAMS.md` 是供人查看的日记和变更摘要，不是长期记忆晋升来源。
- 该文件在 OpenClaw 中服务于其三阶段周期维护和 Dreams UI；它与 `MEMORY.md` 区分有明确用途，但不是 Muse 的官方实现证据，也不是 OpenMuse 必须采用的文件约定。
- OpenMuse 选择结构化 `MaintenanceRunRecord` 保存每次反思和逐字证据，不新增 `DREAMS.md` 真值。用户画像事实/理解通过确认后进入 claim 与 MEMORY/USER/GLOBAL 视图；协作习惯经确认后进入 SOUL；回顾文本本身只供检查，不进入普通提示词。若以后需要日记式阅读/分享，按需从运行记录生成，不允许独立编辑。
- 这一选择降低双写、冲突、同步与遗忘清理风险；代价是当前缺少开放式日记浏览界面（现有设置页仅显示最近三次）。该历史 UX、跨周巩固和后续相似场景效果验证列为后续设计项。

## 2026-10-10：建立重点参考档案

- 检查上游 HEAD，仍为 38bbb45a2c5a0f70de975f6387385770b9ad8aac（提交日期 2026-09-28 UTC）。未发现新版本。
- 保存已取得的十份文档/schema 原件到忽略目录；公开文件目录与 SHA-256 校验，未重新发布原文。
- 新增记忆维护与 dreaming 归纳、行为验证问题和持续更新流程。
- 已知边界：社区真实性未独立核验；schema 只读 memory.claims/entries 等相关段；没有 Muse App 运行或文件变更实测。
- 设计影响：会话即时记忆与后台反思分开；追踪提交与交付；修复、人格演化和遗忘作为后续核对重点。

## 2026-10-10 真机观察与需求更新

新增主要 iOS 页面交互档案，私人截图留本地。确认身份页有 MEMORY.md 正文，修订其与 GLOBAL 的候选关系。用户将一期明确为 Muse 交互和机制对齐，并确定 Mac Pi 优先、手机接手、OpenAI/DeepSeek/自定义模型；长期电脑入口参考 UU 远程。社区机制来源未因此升级为官方验证。

### 同日第二轮

补看 SOUL Markdown 编辑态/导出菜单、动态指令/推荐原因/删除菜单，以及实际浏览器创建、画面、键盘、停止确认和恢复空态。仅创建并停止测试浏览器会话；原始截图增加 16 张，仍仅保存在本地。未知保存与动态任务不冒充已验证。

### 七天旅行真实工作流

完成授权请求、澄清、主题旁聊创建与自动承接、候选假设和聊天行程表生成观察。记录工作状态、内联选择卡、长表格与最新消息导航。未核验旅行内容、目标结构化写入或独立构件；私人详情不发布。

### 目标、备选构件与执行详情补验

实际核对旅行进度写入既有目标，并观察到重复条目。一次请求生成五天备选与七天对照网页构件，验证聊天卡、版本切换、资源库再次打开；不等于版本历史或后续编辑通过。按用户补充记录任务头像的工作/空闲姿态、阶段文案、活动摘要与半屏/全屏分组步骤。新增26张私人截图，索引与校验更新；没有连续视频，动画参数仍未知。需求补充目标事件去重、备选并存、成果真实交付、交互构件和三层执行反馈。

## 2026-10-11：公开记忆机制复核与代码对照

- 重查 Muse 官方设计文章/产品公告、OpenClaw 当前 Memory Core 与 dreaming 文档、Hermes 文件职责/FTS 会话检索文档、nanoMuse 当前 README/配置页；链接及边界见[机制对照](../MEMORY_RUNTIME_COMPARISON_2026-10-11.md)。
- Muse 官方确认持久跨对话记忆、可读可编辑文件、目标/主动任务/活动透明，但没有公开完整的记忆 schema 或更新算法。社区快照仍仅是非官方研究线索。
- OpenMuse 代码核对发现 SOUL 此前被包在低信任资料消息中，且无跨会话用户原话检索；本轮将人格/身份/工作区规则分层进入 system prompt，并增加本地 FTS5 历史召回。2026-10-11 WorkspacePersistenceTests 专项执行88项、86通过、2项因没有实时 Pi/Tailscale 端点跳过、0失败；Mac Debug 与 iOS Simulator Debug 均构建成功。提示注入行为尚未用真实模型验证。
- 记忆写入仍是有限规则白名单；不把它描述为通用事实抽取。外部资料与近期回顾模型候选仍要求用户确认。

## 2026-10-11：OpenMinis iOS 端侧 Agent Runtime

- 固定 OpenMinis HEAD：`b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c`（2026-09-29）。检查 README、BUILDING、iOS sandbox summary、`BackgroundKeepAliveManager.swift`、`ISHExecutionCoordinator.swift`、tool definitions 与 shell execution path。
- 核心结构：iOS 用自建 iSH fork 运行 Alpine aarch64；Android 使用 PRoot。宿主模型 tool loop 调用 shell/文件/记忆/原生工具；iSH 会话目录、memory、skills、attachments 和 offload 目录分开。原生 offload 将有限 Linux 命令转入 iOS 框架；不是 Android sandbox，也不是在手机本地运行大模型。
- 后台结构独立于沙箱：上游另管理短后台额度、静音音频、定位、媒体中断恢复、Live Activity 与通知；源码状态和发行结果不构成每台 iPhone 常驻或强制退出后重启的证明。
- 许可证：OpenMinis 与其 iSH fork 均标 GPL-3.0。OpenMuse 当前 MIT；在处理再分发许可证和构建链前不复制/链接该运行时，也不把项目仍仅标成 MIT。
- 代码影响：OpenMuse 增加 bounded OpenAI-compatible tool loop、本机历史原话检索和结构化目标读取；SQLite/Markdown 仍为唯一正式状态来源。完整 iSH/Alpine/native offload 尚未集成；当前代码没有通过真机或 DeepSeek function-call 实测。
- 详细方案、执行步骤和验收见 [ON_DEVICE_RUNTIME](../ON_DEVICE_RUNTIME.md)。

### 2026-10-11 后续实现补记

- OpenMuse 当前 iPhone runtime 已实际提供七项受限工具：本机原创历史搜索、结构化目标读取、核心文档列表/读取、当前对话工作区文件列表/读取/写入。工作区现在持久保存在 Application Support，限制相对路径、普通文本格式、80 个文件/16 MB/单文件 256 KB，并拒绝符号链接和目录越界；旧缓存按对话迁移，正文不进入活动日志。
- 这与 OpenMinis 的运行级别仍不同。OpenMinis 的 iSH/Alpine 支持 Linux 进程和 shell，OpenMuse 目前没有 Linux guest、命令执行或 native offload。当前验证是自动化工具回合和 Swift 沙箱测试，不是真机运行或真实 DeepSeek tool call。
- 方案对照、分层图和公开许可关卡现已补到 [ON_DEVICE_RUNTIME](../ON_DEVICE_RUNTIME.md)。源码研究继续固定在上述 commit；未来依赖升级要复核 iSH fork、构建脚本、根文件系统与许可证清单。

### 2026-10-11：端侧运行方式补充

用户要求把 OpenMinis 的端侧系统作为参考，且只调整手机运行方式。OpenMuse 因此把本机工作区从可回收缓存升级为持久目录，让任务中间材料在 App 重开后仍可接着读；文件继续由 Swift 宿主的明确工具操作，记忆仍由 SQLite/Markdown 掌权。手机模型请求仍发往所选 API，Mac Pi 路由和产品交互不变。

本轮未声称达到 OpenMinis 的 iSH shell parity。GPL/iSH 许可与构建关卡仍需单独处理；当前的手机工具集合没有 shell、任意目录访问、网络请求或常驻后台执行。参见 [端侧运行时方案](../ON_DEVICE_RUNTIME.md)。
