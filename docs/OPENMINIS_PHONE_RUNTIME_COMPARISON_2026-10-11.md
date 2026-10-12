# OpenMinis 手机端运行时与 OpenMuse 差异

日期：2026-10-11。OpenMinis 研究固定在公开仓库提交 `b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c`；OpenMuse 依据当前工作树源码。本文记录该版本的源码行为、用户已确认目标和仍待确认的边界，不代表 OpenMinis 所有版本。

## 当前状态更新（2026-10-11，D41/T62/T63/T64）

下文的“首轮差异结论”和“首轮实现差异”保留 T47/T60 的历史起点，其中搜索固定百度、临时 WebView、模型按意图才能看到浏览器等描述均已被后续迭代修正，不代表当前代码。当前 iPhone Agent 默认得到通用 `browser_use` 工具；模型和 iSH 的 `openmuse-browser-use` 命令现在共用同一个 `IOSPhoneBrowserRuntime` 与对话标签池。模型先打开 `https://example.com/` 返回 `tab_id=1`，之后 iSH `list_tabs` 和 `get_readable --tab-id 1` 实际读取同一标签。真实操作详情记录了命令、参数、设备、调用编号、退出码、结果及耗时。搜索默认 Google；当前网络下的天气测试尝试 Google 后按设置回退至 Bing。验收证据见 [T58](ITERATIONS.md)、[T62](ITERATIONS.md)。

与固定 OpenMinis 提交仍非全量一致：OpenMuse 不提供任意 JavaScript、Cookie 操作、下载或页面截图图像回传；保留当前公开 HTTPS 与可识别高影响页面操作边界。后续差异不能再把“模型/iSH 共用标签”记为未实现。

### 浏览器动作补齐（T64）

固定上游的 [BrowserAction 定义](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Agent/BrowserUse/BrowserUseActions.swift) 还包括 `get_backbone`、`scroll_and_collect`、`hover`、截图、任意 JavaScript、Cookie、下载、UA 和视口调整等。OpenMuse 已在模型工具和 `openmuse-browser-use` 命令中增加前三种常用动作：结构树最多8层/120节点；连续采集最多40条/20步/15秒，支持滚动方向、步长、容器自动识别和异步内容等待；悬停按 CSS 选择器触发。异步采集使用 WKWebKit 的 [`callAsyncJavaScript`](https://developer.apple.com/documentation/webkit/wkwebview/callasyncjavascript%28_%3Aarguments%3Ain%3Acontentworld%3A%29) 等待页面 Promise 完成。所有结果仍回到已有模型工具循环，并进入活动操作详情，不另加审批或另一套状态入口。Core 参数测试8/8通过；完整 Core 回归235项中233通过、2项条件跳过；iOS Simulator 与 iPhone ARM64 unsigned Debug 构建通过。本轮尚未把新版本安装到 iPhone，所以真实网页行为与活动详情显示仍待真机复验。

截图目前不能直接送回模型，因为 OpenMuse 的浏览器工具结果与兼容模型消息仍是文本结构；下载也尚无受约束的本机会话构件落点。任意 JS 与 Cookie 动作涉及网站副作用和认证资料。以上能力仍是未完成的上游差异，不能把 T64 写成完整 API 一致。

### DNS/guest 网络复核（T63）

固定上游的 iOS host adapter 直接读取系统 resolver 列表，并把 nameserver 写进 guest `resolv.conf`；上游 `NetworkMonitor` 用 `NWPathMonitor` 在路径变化时刷新，工程显式链接 `libresolv.tbd`。OpenMuse 早先把所有 DNS 交给宿主 `getaddrinfo` 后自行合成应答；真机观察到这条路径向 Alpine 返回 `198.18.0.45`，但 `wget` 失败。现已移除代理和 iSH socket 重写，改为与上游相同的系统 resolver 配置/网络变化刷新，并在每次 guest 执行前更新 resolver，再补上 `-lresolv`。OpenMuse arm64 unsigned Debug 和 Simulator Debug 构建通过；签名构建报告 Xcode 无账号/描述文件，故修正版本还没有安装或真机验证。源码依据：[OpenMinis `ISHKernel.m`](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/iSH/ISHKernel.m)、[`NetworkMonitor.swift`](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Shared/NetworkMonitor.swift)、[iOS target link settings](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Minis.xcodeproj/project.pbxproj)。实测与限制见 [T63](ITERATIONS.md)。

## 首轮差异结论（T47 初查，历史记录）

上海天气结果来自百度，是 OpenMuse 当前搜索器写死的行为：`IOSPhoneBrowserRuntime.search` 先打开百度，内容不足时再退到 Bing；工具说明也明确告诉模型搜索词会发给百度。它没有搜索引擎设置。OpenMinis 的做法不同：它提供可交互的通用本机浏览器，模型可以导航到 Google 搜索，而不是把某个搜索站固定在搜索函数里。

更大的差异是手机 Agent 能力的开放方式。OpenMuse 已有本机 iSH/Alpine，也有搜索、核心记忆、目标、附件和对话工作区等 Swift 宿主工具；但普通手机请求不会把 iSH 工具交给模型，只有用户明确提到 iSH/shell 并要求执行命令时才开放，首次还要确认。OpenMinis 在工具开关开启时会把 shell、文件工具和浏览器作为一般 Agent 工具提供，模型可以根据任务自行选择；iSH 的命令和原生 iOS 能力之间另有 offload 桥。

因此，单纯把百度 URL 换成 Google，可以满足搜索偏好的一部分，但不能满足“没有 Mac 时，让手机本地运行环境完成各种任务”的目标。

## 公开源码中的 OpenMinis 工作方式

1. **Agent 工具回合**：会话工具清单包含 `shell_execute`、`file_read`、`file_write`、`file_edit` 和 `browser_use`。工具执行结果回到模型，Agent 可继续下一步。浏览器工具可由设置关闭；shell 一般不要求用户先说“请运行 shell”。
2. **iSH 与文件区**：Alpine 命令在手机端 guest 进程中执行，运行区按会话组织。guest 命令和专门文件工具可处理会话草稿，不等同于操作 Mac 上的目录。
3. **原生能力 offload**：部分命令会由 iSH 转到 App 的 Swift/Objective-C handler，再调用天气、地图、提醒、日历、照片、位置、剪贴板等 iOS 能力。它们不是 Alpine 里安装的 Linux 软件，也不是 shell 自动拥有的系统权限。
4. **浏览器与命令行共用会话状态**：`browser_use` 通过原生 `BrowserTabPool` 管理 WKWebView 标签；`minis-browser-use` 命令经 `BrowserUseOffloadBridge` 进入同一个会话的浏览器池。一次导航后，后续浏览器动作或 shell 脚本可以继续使用相应标签。浏览器支持导航、读取、截图、点击、输入、滚动、下载和多标签等动作，远多于“搜索并提取文字”。
5. **工具状态界面**：消息中用紧凑工具胶囊显示动作名称、执行状态和耗时，点击后打开详情面板看参数与结果。它是每条消息的工具痕迹，不替代 App 的整体任务/活动状态。

源码入口：[工具定义](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Agent/Chat/AIChatViewModel%2BToolDefinitions.swift)、[浏览器会话桥](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/NativeOffloads/BrowserUseOffloadBridge.swift)、[浏览器 offload 命令](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/NativeOffloads/BrowserUseOffload.m)、[工具权限管理](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Agent/Offload/OffloadPermissionManager.swift)、[消息工具胶囊](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Views/Chat/AssistantBlockView.swift)。

## 权限实际如何工作

OpenMinis 并非所有操作都逐次确认，也不能概括成“没有权限审批”。原生 offload 有 `Bypass`、`Ask Once`、`Not Allowed` 三种设置；`Ask Once` 的允许状态按会话和命令缓存，iOS 自身的系统权限仍可弹窗。需特别注意，这个固定提交中 `UserDefaults.integer` 的缺省值是 `0`，对应 `Bypass`，所以隐私类命令如果用户没有改设置，也可能不触发 App 内确认。工具管理器另外提供“全部 Bypass”。

还有一项不能照搬的安全问题：shell 执行前的权限逻辑从 shell 字符串的第一个命令词识别原生 offload。源码注释承认 `sh -c`、脚本或子进程等间接调用不会被这个前置识别捕获。OpenMuse 如果增加原生能力桥，应在 Swift 原生 handler/能力分发点做权限校验，不应只扫描 shell 文本来决定是否审批。

## 与 OpenMuse 首轮实现的逐项差异（T47 历史基线）

| 能力 | OpenMuse 当前实现 | 与 OpenMinis 的差异 |
|---|---|---|
| 搜索引擎 | `IOSPhoneBrowserRuntime.search` 固定百度，正文不足后回退 Bing；没有用户设置；模型工具说明也写明百度 | OpenMinis 提供通用浏览器，不把搜索引擎固定为百度；模型可以导航到 Google |
| 浏览器能力 | 原生 WKWebView 只读打开/读取公开 HTTPS 页面；每次调用新建临时、不持久化的 WebView，读取完即销毁；不能点击、输入、截图、保留标签/登录态 | OpenMinis 有会话级多标签浏览器，支持页面交互；shell 的浏览器命令与 Agent 浏览器共用标签状态 |
| iSH 可用性 | iSH 已嵌入 iPhone 构建，但只有最新消息明确提到 iSH/shell 且要求运行/执行时才把命令工具暴露给模型；运行时还强制模型调用命名工具 | shell 在 OpenMinis 工具开关开启后属于普通 Agent 能力，模型可根据任务决定何时调用 |
| 命令确认 | 第一次命令显示完整命令并逐次确认；可允许本对话后续命令，但只在当前 App 进程内有效。限制为 4 KB、45 秒、12 KB 输出 | 普通 shell 命令不走整条命令的逐次确认；原生 offload 按命令类型/设置管理 |
| iOS 原生能力 | OpenMuse 已有由 Swift 宿主提供的结构化只读工具，以及经宿主审批的工作区写入；iSH 与 Swift 系统能力尚无 OpenMinis 式通用 offload 注册表 | OpenMinis 将一部分 iOS API 包装为 guest 可调用的 offload 命令，并对隐私类别单独配置权限 |
| 本地资料 | 正式记忆/目标/构件由 SQLite、Markdown 和 Swift 宿主管理；guest 只能看到当前对话隔离挂载，正式工作区不直接交给 shell | OpenMinis 也区分会话运行文件与共享 memory/skills；OpenMuse 的正式状态边界更严格，应该保留 |
| 执行位置 | Mac 在线且能力匹配时按现有策略优先交给 Pi；Mac 不在线则由手机当前可用的 Swift 工具处理 | 当前不改变 Mac 优先规则；差异集中在手机的工具集合、调用门槛和浏览器会话 |
| 操作反馈 | Muse 头像/活动步骤记录总任务和工具开始/结束；OpenMuse 由现有活动记录进入工具详情 | OpenMinis 在消息下方放工具胶囊，点击进入详情；用户已选择活动记录作为 OpenMuse 的详情入口，不另加一套胶囊 |

iSH 与 OpenMuse App 共进程，不是硬件隔离虚拟机；“本地虚拟环境”应理解为 App 内的 Alpine guest 和受限会话目录。模型推理仍调用用户配置的 OpenAI/DeepSeek 等 API；没有 Mac 不等于模型、网页都能离线运行。公开搜索会从 iPhone 网络访问搜索网站。

## Google 搜索与网络边界

偏好已确认：搜索默认 Google；Google 不可达时自动切换到用户设置的备用引擎，并标明实际来源；没有备用引擎时报告不可用。iPhone 真机天气查询已尝试 Google，并按设置回退到 Bing；这验证了失败回退路径，不证明 Google 在所有 Wi-Fi、蜂窝或网络配置下都可达，也不证明天气内容准确。详见 [T58](ITERATIONS.md)。

## 已确认的对齐目标（当前实现见本文顶部）

1. **手机端 Agent 自动选择能力**：无 Mac 时仍使用同一 Agent、记忆与成果体系，按任务将可用工具交给模型，不要求用户先说“用 iSH”。
2. **组合本地能力**：iSH/Alpine 负责隔离计算、命令和会话草稿；WKWebView 提供浏览器；Swift 宿主负责正式记忆、目标、结构化构件和 iOS 原生能力。浏览器与 shell 可共享会话级浏览状态；guest 不直接访问数据库、Keychain、Mac 文件或正式记忆写权限。
3. **按风险分层减少打断（D34）**：普通隔离运行和公开 HTTPS 页面范围内的受限浏览交互不逐次审批；日历、照片、位置、剪贴板等敏感 iOS 数据按类别授权；正式记忆/共享资料变更和外部高影响操作仍确认。
4. **Google 默认和用户指定备用（D35）**：失败时按已配置引擎自动切换，并显示实际来源；没有备用引擎时明确报告失败。
5. **详情从活动记录进入（D36）**：OpenMinis 用消息胶囊打开单次工具详情；OpenMuse 复用 Muse 风格头像和活动记录，用户从对应活动打开执行详情，不增加平行胶囊入口。详情需追溯工具步骤、结果/来源和失败原因，具体字段沿用现有活动详情结构。

## 用户已确认的网络边界（D37）

OpenMinis 在所查提交中允许通用 iSH shell 直接联网，`curl`、`wget` 和软件包安装不会因为联网单独触发 App 审批。Native offload 的权限设置不限制任意 shell 网络。因此 guest 能访问当前挂载的文件时，也可能把其内容传出。用户已明确要求 OpenMuse 不为 iSH 命令或网络另加审批，与 OpenMinis 保持一致。

实现保留目录、超时、命令长度和输出范围限制，但不做逐条网络审批。guest 可把当前对话挂载区可读内容发送到互联网，也可自行提交 HTTP 请求；OpenMuse 目前没有 guest 内任意网络写操作的硬拦截。正式记忆、数据库、Keychain、Mac 文件和其他 App 私有目录仍不挂入 guest。共享浏览器提供受限的公开 HTTPS 页面交互，并作为独立的原生能力供 Agent 与 iSH 调用；它不等于 guest 获得 WebKit、Cookie 或任意 JavaScript 的直接控制权。

对安全实现的要求：不能仅在执行前按 shell 命令首词识别敏感 offload。每个原生 Swift handler 必须在实际调用处校验对应类别权限；guest 网络也要在宿主/隔离层施加一致策略，或如实说明当前 iSH 共进程环境只能通过设置/工具暴露收敛风险，而非声称硬隔离。

## 当前仍待验证的差异

- 已在 iPhone 实测模型与 iSH 共用标签、页面读取、URL 元数据跨 App 重启恢复，以及活动详情；还未测 Cookie/localStorage 跨重启、登录站点、DOM/滚动状态恢复（当前仅恢复 URL 并重新加载）。
- OpenMinis 的页面截图回传、任意 JavaScript、Cookie 操作、下载和无限列表采集未接入 OpenMuse；这些差异有意保留，需在对应产品需求和安全边界确定后再评估。
- iSH DNS/外网命令、超时取消与崩溃恢复、锁屏后台续跑和蜂窝网络下的跨端连接仍需单独验收；这些不影响本次已验证的共享标签流程。
- Google 在这次天气查询中不可达并回退 Bing；其他网络下的可达性未测。搜索结果来源回退已验证，天气数值准确性未验证。
- 旧版基线和 T47/T54 记录仍保留在下文与 [端侧运行时方案](ON_DEVICE_RUNTIME.md)，供追溯演进；当前完成情况以本文顶部的 D41/T62 状态和后续迭代记录为准。

## iPhone 闹钟与计时器（2026-10-12，D44/T81）

固定提交 `b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c` 的 [`AlarmOffload.m`](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/NativeOffloads/AlarmOffload.m) 注册 `apple-alarm`，解析 `set`、`timer`、`list`、`cancel` 并转到 [`AlarmOffloadBridge.swift`](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/NativeOffloads/AlarmOffloadBridge.swift) 调用 AlarmKit。该桥接支持一次性/每天/工作日闹钟和倒计时；闹钟标签由应用本地保存，因为 AlarmKit 列表数据不回传展示标题。首次调用请求 AlarmKit 授权；该实现要求 iOS 26+。仓库里的摘要文档把 `AlarmOffload` 表格列为 EventKit/提醒事项，但固定提交的直接源代码明确使用 AlarmKit；本次以源代码和 Apple 文档为准。Apple 要求 Info.plist 提供 `NSAlarmKitUsageDescription`，拒绝授权时创建会失败。

OpenMuse 采用相同分层但使用原创命令名 `openmuse-alarm`：iSH guest 解析受限参数，由 iOS 宿主调用 AlarmKit；重复日期、标签和状态可以从列表核对；用户请求“在这台 iPhone 响”的闹钟不转交 Mac。目标进度提醒继续由原有通知机制处理。没有逐命令审批，只出现一次系统授权；iOS 26 以下明确返回不支持，不降级成普通通知。源码实现、测试和真机验收分别记录在 [T81](ITERATIONS.md)。

T82 真机首次调度返回 AlarmKit error 0 后，按用户要求重新核对 OpenMinis 的直接 bridge 源码：普通闹钟只传 `AlarmPresentation.Alert`，不同时声明 Countdown/Paused。OpenMuse 初版给每个闹钟都声明三种状态，而产品没有 AlarmKit widget extension。Apple 官方示例说明 Countdown 与 Paused presentation 可选；仅 Alert 的闹钟不需要它们，支持 countdown presentation 则需要 widget extension，否则系统可能关闭闹钟且不响。OpenMuse 已改为 alert-only，与上游做法一致；计时器的 countdown duration 与显示状态分开。真机重试结果见 [T82](ITERATIONS.md)，不把本次失败归因于权限审批差异。
