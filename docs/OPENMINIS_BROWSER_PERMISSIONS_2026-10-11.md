# OpenMinis 手机浏览器、权限与工具界面对照

日期：2026-10-11。研究对象是 OpenMinis 仓库固定快照 `b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c`。本文件记录公开源码观察和 OpenMuse 当前采用方案；它不代表 OpenMinis 官方对所有版本的说明。

## OpenMinis 怎么在 iPhone 上查询网页

OpenMinis 不把浏览器能力等同于“模型自己能联网”。iOS tool schema 暴露 `browser_use`，描述其本地浏览器动作；`BrowserUseOffloadBridge` 接收请求并分派到当前会话的浏览器池。浏览器由 iOS 原生 WKWebView 管理，支持页面导航、文本提取、截图、点击、输入和多标签等交互，页面也可访问该会话的 `minis://` 资源。它和 iSH shell 是两类工具：browser 是系统侧 offload，shell 是 guest 里的命令行。

- [iOS 浏览器工具定义](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Agent/Chat/AIChatViewModel+ToolDefinitions.swift)
- [原生浏览器 offload bridge](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/NativeOffloads/BrowserUseOffloadBridge.swift)

Browser Use 可由工具设置开关关闭；源码对它做能力门控，没有为每一次公开网页浏览都强制弹确认框。公开网页里的指令仍是外部内容，浏览器可以做页面交互的能力不代表每种动作都适合无确认执行。

## OpenMinis 权限不是“全部免审批”

固定快照的原生 offload 权限有三个等级：`Bypass`、`Ask Once`、`Not Allowed`。照片、位置、日历等隐私类命令可在设置里按命令选择权限；低隐私风险的系统/媒体类命令采用免弹窗路径。`Ask Once` 的允许结果缓存于命令和聊天 session 维度；换会话后不自动沿用。浏览器另有独立启用开关。操作系统自身权限弹窗仍可能出现。

- [OffloadPermissionManager](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Agent/Offload/OffloadPermissionManager.swift)
- [Offload 权限设置页](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Views/Settings/OffloadPermissionSettingsView.swift)

所以值得借鉴的是：权限按工具风险和范围分层；只读、低风险工具不逐次打断；访问隐私数据或产生副作用的能力保留更强确认。不能把 OpenMinis 简化成“任何工具都没有审批”。

## OpenMinis 的小型工具界面

聊天里的 `ToolCapsuleView` 把工具步骤压成紧凑胶囊，按工具类型显示图标、名称、运行/完成状态和时长；点击后打开 `ToolLiveSheet` 查看参数、结果和更完整的运行信息。它把低层工具日志收起来，但仍让用户知道 agent 当前做了什么。

- [聊天内工具胶囊与详情入口](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Views/Chat/AssistantBlockView.swift)
- [工具详情面板](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Views/Chat/ToolLiveSheet.swift)

## OpenMuse 这次问题的根因

T54 前，OpenMuse iPhone 对话没有真正的本机浏览器工具。查询天气时模型只能调用 iSH shell；手机的 Alpine 环境中没有 `curl`，因此它提议改用 `wget` 并触发命令审批，最终不能完成查询。

加上本机浏览器工具后仍存在第二个独立问题：基础 system prompt 一处仍明确声称“当前没有网页搜索或浏览器操作工具”，而后续运行时提示又说手机有只读网页能力。这两个指令冲突，会诱导模型直接回答“没有联网工具”而不尝试调用。这是本次拒绝调用的根因之一，已经在 `OpenMuseAppModel.swift` 统一为按本轮实际提供的工具清单描述能力。

## OpenMuse 采用的方案与权限边界（D34–D37）

1. 手机端原生隔离浏览器负责公开网页搜索和正文读取，不依赖 iSH；用户问实时信息、明确要求联网或给出网址时才将相应工具放进模型请求。明确要求离线时不提供浏览器工具。搜索默认 Google，备用引擎从设置读取。
2. 公开网页只读查询免逐次审批。搜索只带必要的公开关键词，页面内容作为不可信资料；当前实现不登录、不填表、不提交或修改网页。网络搜索会把关键词发给搜索服务，不能把私人记忆拼进查询词。
3. iSH shell 作为普通手机 Agent 能力提供，模型按任务决定是否调用；不要求用户点名 iSH，普通命令及 guest 出站网络不逐次审批。执行仍受命令大小、最长运行时间和输出上限约束。
4. iSH 只看到当前对话 guest 运行目录、附件只读副本及自身 rootfs，不挂载正式记忆、数据库、Keychain、Mac 文件或其他 App 私有目录。当前对话临时工作区的 guest 修改不等同于 OpenMuse 正式工作区写入；正式工作区、正式记忆和结构化资料写入仍逐项确认。
5. 高影响外部操作由模型规则与原生工具审批约束；任意 shell 内的 HTTP 写请求无法被 OpenMuse 网络层逐次确认或硬拦截。不能把模型提示词边界描述为技术强制。
6. 逐次工具调用仍从头像进入现有活动记录；D38 增加独立操作详情记录，能查看工具名、稳定调用编号、执行设备、脱敏参数、返回/错误、运行状态、开始/结束时间与耗时，并复制调用详情。详情与活动按稳定 ID 关联，随现有设备同步/归档保存；常见凭证字段会遮盖，单条输入/输出/错误有限长，超限会显示截断标记。网页文本、文件内容和命令可能包含私人资料，不能放入公开日志。此详情只覆盖 OpenMuse 已实际支持并产生事件数据的工具，不包括 OpenMinis 的截图、交互浏览接管、编辑差异或图像专有面板。

## 是否集成 OpenMinis 小型工具胶囊

OpenMinis 用消息中的小型工具胶囊打开单次执行详情。用户随后确认，OpenMuse 不新增这一平行入口；工具执行细节从现有活动记录查看，整体任务仍由 Muse 头像和活动列表显示。D38 已把工具名、调用编号、执行设备、调用参数、返回/错误、状态与耗时接入独立活动操作记录，活动详情可展开和复制；此记录只反映当前工具真实产生的数据，未覆盖上游的浏览器快照、图像或编辑差异专属视图。实机对照和 UI 回归见 [T56](ITERATIONS.md)。

## OpenMuse 当前实现验收

T54 已在 iPhone 15 Pro Max 上安装并运行旧策略构建。使用用户已配置的 DeepSeek，在 Mac 未参与的手机本地回合中查询“广州今天的天气”；模型调用本机只读浏览器并返回百度来源。此记录仅证明旧版网页查询流程，不代表 D35 的 Google 默认策略已经验收。完整设备步骤与日志索引见 [T54](ITERATIONS.md)。

## 2026-10-11 后续权限复核

进一步核对固定提交后补充两点：第一，`permissionLevel(for:)` 使用 `UserDefaults.integer`，缺省为 `0`，正好映射 `Bypass`；这包括隐私类别命令，除非用户手动改成 `Ask Once` 或 `Not Allowed`。第二，shell 前置权限检查通过解析 shell 命令的第一个 token；源码注释明确指出 `sh -c`、脚本和子进程形式可能不经过这个检查。将来借鉴其低打断体验时，应把权限放在 Swift native handler/能力入口实施，不能只复制首 token 检测。另见 [OpenMinis 手机运行时差异分析](OPENMINIS_PHONE_RUNTIME_COMPARISON_2026-10-11.md)。

用户随后在 D37 明确选择 iSH 命令和网络不增加审批。该决定更新 T54 时的首次 shell 审批方案；iOS 原生敏感能力将来仍须在实际 Swift handler 处按类别授权。

## 2026-10-11 搜索实现源码对照

固定提交中的 `browser_use` 是通用浏览器动作接口，不是 Google 搜索 API：模型先调用 `navigate` 打开搜索页，再用 `get_readable` / `get_text` 读取。浏览器由会话级 tab pool 持有，导航完成后最多等待 5 秒观察 DOM，按 500 ms 间隔判断变更速率趋稳，再附上页面内容；导航有单独的超时结果。源码：[工具定义](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Agent/Chat/AIChatViewModel%2BToolDefinitions.swift)、[BrowserUseManager](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Agent/BrowserUse/BrowserUseManager.swift)、[BrowserTabPool](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Agent/BrowserUse/BrowserTabPool.swift)。

OpenMinis 的 WKWebView 导航代理允许 `http`、`https`、`about`、`blob`、`minis` scheme，并取消其他应用 scheme；它没有 OpenMuse 当前采用的“只允许公开 HTTPS 主页面”限制。源码参考不等于照搬权限：OpenMuse 继续限制顶层地址为公开 HTTPS，但允许安全的公开 HTTPS 子框架、`about:blank` / `about:srcdoc` 和由公开 HTTPS 页面创建的 `blob:` 子框架；危险子框架与新窗口直接取消，不把子框架拦截升级成整页搜索失败。

本轮确认的代码差异是：OpenMuse 之前对所有子框架一律取消，而 Google 等搜索页可能需要页面内框架；同时它在 `didFinish` 后立即抽正文，没有等待异步结果稳定。随后 D39 将本机浏览器升级为对话级持久标签和通用动作工具，按上游方式加入有界 DOM 稳定等待，并继续只允许公开 HTTPS 页面。天气搜索的实际根因以本轮真机调用结果为准；如果用户设置的备用引擎也无法访问，应用会在活动详情记录真实失败，不让模型编造搜索过程。

## D40/T61 源码复核与当前实现

固定的 OpenMinis commit `b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c` 将 `browser_use` 默认放进 Agent 工具清单，只有用户关闭浏览器能力时才移除；`BrowserTabPool` 使用移动视口并保存标签 URL，`BrowserUseManager` 以系统默认 WKWebKit data store 持久化站点状态。OpenMuse 旧版不仅实现细节不同，还会按消息意图隐藏浏览器，导致模型根本收不到 `browser_use`。这与“有工具但模型没用”是两种不同问题。

OpenMuse 已修正为默认向 iPhone Agent 提供持久浏览器工具，只在明确离线/不浏览时隐藏；明确打开 URL 会强制 `navigate`，天气等实时查询会强制 `search`，工具真实失败时本轮停止。`browser_use` 字符串不再被子串 `browse` 误判为搜索；用户明确说不要使用 iSH 时，不会再强制 shell。WKWebView 使用 390×844 视口和 `WKWebsiteDataStore.default()`；URL/title/选中标签按对话保存在本机。活动详情改为默认全高的统一可滚动时间线，参数、返回/错误、状态、执行设备、调用编号、耗时和复制入口都保留在现有活动详情。

在 iPhone 15 Pro Max 上的真实结果：`example.com` 的 `navigate → get_readable` 使用 `tab_id=1`；后续另一个模型回合先 `list_tabs` 再 `get_readable`，仍复用 `tab_id=1`。真机天气查询尝试 Google 后按设置切换至 Bing，并在活动详情记录 `cn.bing.com`，因此不能说 Google 已在当前网络验证成功，也不把 MSN 天气卡内容当成天气准确性结论。测试、完整缺口与构建证据见 [T58](ITERATIONS.md)。

## D41：iSH 与模型共用同一标签池

OpenMinis 固定快照不只让多次 `browser_use` 调用复用标签；其 `BrowserUseOffloadBridge` 也把 `minis-browser-use` shell 命令接到同一会话池。OpenMuse 已接入对应的 `openmuse-browser-use` 命令：iOS Agent 与 iSH 共用 `IOSPhoneBrowserRuntime`，shell 调用携带当前 conversation ID。真机先经 Agent 导航到 `https://example.com/`，再从 iSH `list_tabs` 与 `get_readable --tab-id 1` 复用同一页面；操作参数与结果在活动详情可查，覆盖安装后 URL 恢复亦已实测。该桥只调用 OpenMuse 已暴露的安全动作，未增加任意 JavaScript、Cookie、下载或截图能力；细节见 [D41](DECISIONS.md) 与 [T62](ITERATIONS.md)。
