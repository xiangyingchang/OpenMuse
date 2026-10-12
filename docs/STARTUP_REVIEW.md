# 开工状态与方案入口

## 最新设备版本：2026-10-12 iPhone 16 Pro 安装（T78）

当前源码以 Personal Team 签名为 `0.1.0 (6)`，安装到 iPhone 16 Pro / iOS 27.2；设备应用清单确认版本号，`devicectl` 启动成功，`codesign --verify --deep --strict` 通过。没有进行 PUA 视觉页面验收、模型请求或核心旅行流程重测。构建与安装日志见 [T78](ITERATIONS.md#t78)。

## 最新验收：2026-10-12 发送凭证竞态修复（T77）

Keychain 异步读取尚未完成时首次发送会误报模型未配置；现在发送路径会异步刷新凭证状态。另将 Bridge 启动测试改用临时端口，并消除共享初始化器引用 macOS-only 类型造成的 iOS 编译失败。测试专用内存 Keychain 后端下 Core 全量测试251项执行、249项通过、2项条件跳过、0失败；首次目标追踪回归与 Bridge 健康路由各1/1通过。修改后 Mac Debug 与 iOS Simulator Debug 构建通过。内存后端测试不覆盖真实系统 Keychain；全套17项 UI 结果仍是 T76，未在 T77 后重跑。日志和具体边界见 [T77](ITERATIONS.md#t77)。

当前任务的 Computer Use 接口返回 `apps=[]`，只提供浏览器标签，不能控制桌面应用。Xcode Signing & Capabilities 仍未目视核查；命令行工程设置没有选定 Team/profile。需要在有本机 Computer Use 的 Codex 桌面任务中继续，不能把浏览器 CDP 设置当作桌面控制开关。

## 最新验收：2026-10-12 修复后完整 iOS Simulator UI 回归（T76）

在 T75 钥匙串异步读取修复后的当前源码上，iPhone 17 Pro / iOS 26.5 Simulator 完整运行17项 UI 自动化，17项通过、0失败，运行时427秒。结果包 `.build/logs/OpenMuseT75FullUIAfterKeychainfix.xcresult`，日志 `.build/logs/openmuse-t75-ios-full-ui-after-keychainfix.log`。该结果验证模拟器 UI，不代表 iPhone 真机安装、后台能力、真实模型请求或跨设备验收。

## Mac 首屏卡顿修复与 Xcode 签名状态（T75）

Build 5 Mac App 首屏曾因在 SwiftUI 渲染中同步读取 API 密钥而卡住，导致本机桥接健康检查超时。现在钥匙串读取移到后台，模型就绪状态使用缓存；Mac Debug 重建、启动、签名校验通过，本机 `127.0.0.1:4388/openmuse/health` 返回 HTTP 200，Mac bridge 启动测试 1/1 通过。iOS Simulator Debug 构建和修复后导航/设置页 UI 测试 2/2 通过；本轮全套17项 UI 自动化也通过，但它在修复前已启动。

完整 Core 回归两次停在 macOS 系统钥匙串 `SecItemAdd`/`SecItemCopyMatching`，均未得到完整结果；不能算测试通过，也没有断言失败。T73 的247项完整回归仍是最近一次成功的完整 Core 结果。T75 未进行真实模型请求或 iPhone 重装。

当前 Computer Use 会话的桌面应用列表为空，所以没有完成 Xcode Signing & Capabilities 页面目视检查。`xcodebuild -showBuildSettings` 显示 iOS target 使用 Automatic Signing，但 `DEVELOPMENT_TEAM` 和 provisioning profile 未设置；这不能单独判断 Xcode 账号是否已登录。需要在具有桌面 Computer Use 能力的 Codex 桌面会话中复核该页面。细节和日志见 [T75](ITERATIONS.md#t75)。

## Build 5 设备构建记录：2026-10-12（T74，后续由 T75 补验）

当前源码已生成 iOS ARM64 Device Debug 与 Mac Debug，版本均为 `0.1.0 (5)`。iOS `.app` 位于本机忽略的 `.build/derived-openmuse-device-current/Build/Products/Debug-iphoneos/OpenMuse.app`，架构 arm64，且包内含 Alpine rootfs；两端产物均未签名，Mac App 未启动验收。签名构建被 Xcode 当前无法访问 Personal Team 账号/描述文件阻挡，因此本轮没有安装真机。构建日志与版本号调整见 [T74](ITERATIONS.md#t74)。

## 最近一次成功的完整 Core 回归：2026-10-12 Dreaming 记忆方案（T73）

针对 T72 调整重新运行完整 Core 测试：247项执行、245项通过、2项因未配置实时 Tailscale 路由与本地 Pi RPC 服务而跳过、0失败。iPhone 17 Pro / iOS 26.5 Simulator 上3项相关 UI 自动化通过；Mac Debug 和未签名 iOS Simulator Debug 构建成功。证据和日志见 [T73](ITERATIONS.md#t73)。这不是完整 UI 套件，也没有运行真实模型、实时 Pi/Tailscale 集成或真机重装；最近一次真机记录仍为 T68。

## 历史工作区回归：2026-10-12（T71）

本轮针对当前本地工作区重新核对，不代表代码已安装到真机。`swift test` 执行247项，245项通过、2项因未配置实时 Pi/Tailscale 地址跳过、0失败；记忆视图与备份定向测试8/8通过。Mac Debug 与 iOS Simulator Debug 均构建成功。日志：`.build/logs/openmuse-status-convergence-2026-10-12-swift-test.log`、`.build/logs/openmuse-status-convergence-2026-10-12-mac-build.log`、`.build/logs/openmuse-status-convergence-2026-10-12-ios-simulator-build.log`。构建仍有非阻断警告，包括未使用变量、已弃用的 `WKProcessPool`、恒真类型转换，以及没有声明输出的构建脚本阶段。

T70 当时记载的 `WorkspaceBackup.swift` 编译错误已被后续源码变化消除；T71 的双端构建验证了当前文件。最近一次记录的真机安装仍是 T68 的 iPhone 15 Pro Max / iOS 27.2 / Build 4，本轮没有重装、跑 iOS UI 自动化、确认当前手机模型密钥或发送真实模型请求。之前首次 Mac 同步留下的18项冲突仍待用户选择；本轮未检查设备当前在线状态。完整一期仍未通过：真实 iPhone→Mac Pi 接管、蜂窝/中国网络、锁屏后台、真实连接器、Muse 逐页视觉对照与十四天自用等仍待验。逐项状态见[需求覆盖审计](REQUIREMENT_AUDIT_2026-10-10.md)和[一期对照表](PHASE1_PARITY.md)。

## 最新补充：2026-10-12 核心记忆文件职责落地（T70）

`USER.md`、`MEMORY.md`、`GLOBAL.md` 现在是同一批结构化记忆的画像、完整有效账本和主题索引三种视图；编辑自动维护条目会回写同一 claim，遗忘会在一个 SQLite 事务中更新三份视图并清理其旧修订，启动会从 SQLite 修复本地 Markdown 副本。`SOUL.md` 的人格修订与 `HEARTBEAT.md` 的计划仍各走自己的记录流程。T70 的构建阻塞已由 T71 当前工作区 Mac/iOS Simulator Debug 构建通过结果取代；一般事实自动抽取、通用冲突处理和完整 dreaming 仍是独立缺口。

## 最新状态：2026-10-11 Build 4 真机部署与浏览器验收（T68）

手动签名的 iOS 0.1.0 Build 4 已安装并启动于 iPhone 15 Pro Max / iOS 27.2，PUA 确认 OpenMuse 在前台。真机 DeepSeek 回合逐项验证了 `get_backbone`、`scroll_and_collect`、`hover`：页面结构树和悬停成功，采集返回10条；工具未给截断标记，因此不据此声称全页完整。T68 修复了异步采集结果未从 `callAsyncJavaScript` 返回而静默成为 `{}` 的问题。iSH 的 T67 DNS/HTTPS 结果仍受 `198.18.0.45` 保留地址限制，不能代表直连公网 DNS。Mac 本机 health 正常，Tailscale Serve 路由未改；当前 tailnet 没有在线移动设备，真实手机到 Mac Pi 接管仍未验。完整证据见 [T68](ITERATIONS.md)、[端侧运行时](ON_DEVICE_RUNTIME.md) 和 [需求审计](REQUIREMENT_AUDIT_2026-10-10.md)。

## 最新补充：2026-10-11 活动详情逐次操作记录（D38）

用户要求活动详情保留 OpenMinis 胶囊里能检查的操作细节，同时继续从现有头像/活动列表进入、不增加消息胶囊。上游显示工具名、状态/时长，可打开单次参数与结果并复制；详情按 shell、文件、浏览器、记忆、图片等类型呈现专有内容。OpenMuse 的独立活动操作记录保存工具参数、结果/错误、状态、起止时间、稳定调用编号和执行设备；详情可展开和复制，运行中持续显示已用时间并可停止本轮回复，常见凭证脱敏，单条内容有上限，并随活动设备同步/归档。iPhone 上已实测 OpenMinis 的 Shell 详情；模拟器 UI 自动化记录与尚未覆盖的专属数据视图见 [T56](ITERATIONS.md) 和 [研究笔记](OPENMINIS_ACTIVITY_DETAILS_2026-10-11.md)。

## 最新补充：2026-10-11 iSH 网络与手机端工具策略（D37）

用户明确选择 iSH 普通命令和出站网络与 OpenMinis 一致，不额外弹网络审批；模型按任务选择本机隔离工具，不要求用户先点名 iSH。正式记忆/共享资料仍由 Swift 宿主控制，guest 只访问当前对话运行区、附件只读副本及自身 rootfs。此选择允许 guest 把它可读的资料发送到互联网，任意 HTTP 写操作没有 guest 级硬拦截。Google 搜索默认、备用引擎可配置，执行详情通过活动记录查看。当前正在实现及验证，不能把测试替身结果等同于真机 iSH/中国网络验收。

## 新增未决项：2026-10-11 Google 搜索与手机本地运行时（T47）

用户希望搜索上海天气改用 Google，并要求没有连接 Mac 时，iPhone 交互和本地 Agent 运行方式与 OpenMinis 对齐。源码对照发现 OpenMuse 当前搜索固定百度后回退 Bing，普通请求不会开放 iSH；OpenMinis 将 shell、文件、交互浏览器作为 Agent 工具，并用 native offload 桥接部分 iOS API。详见 [T47 运行时对照](OPENMINIS_PHONE_RUNTIME_COMPARISON_2026-10-11.md)。

用户已确认 D34 风险分层权限、D35 Google 默认并自动切换用户配置的备用引擎，以及 D36 从活动记录查看执行详情且不新增消息胶囊。T47 写下时，iSH 出站网络仍待讨论；后续 D37 已确认不额外审批，见本页最新补充。Google/备用引擎真机可达性仍需验收。

## 最新更新：2026-10-11 手机本机网页查询修复与验收（T54）

后续决定（D36）：工具执行详情从 OpenMuse 已有活动记录进入，不新增消息胶囊入口。上方旧记录中的“暂不复制胶囊”反映 T54 当时状态，现由用户明确指定活动记录作为详情入口。

修复了无 Mac 时 iPhone 查实时信息却回复“没有联网工具”的问题。根因有二：当时没有本机浏览器工具，模型只可能误用 iSH；增加浏览器后，基础提示词还与运行时能力说明冲突。本机隔离只读浏览器现在按实时查询/明确联网意图开放，且提示词只声明本轮实际可用工具。真实 DeepSeek 天气请求在 iPhone 15 Pro Max 上完成，结果显示来自百度搜索页并附来源链接，没有调用 iSH 或弹命令审批。天气准确性未与气象官方来源独立核对。26项定向 Core 测试全通过，iOS Simulator Debug、iPhone 签名构建、安装及启动通过。远程桌面由 D33 确认后置二期；一期先完成其他已确认能力。见 [T54](ITERATIONS.md)、[OpenMinis 权限和界面对照](OPENMINIS_BROWSER_PERMISSIONS_2026-10-11.md)、[一期对齐](PHASE1_PARITY.md)。

审批边界：只读公开网页查询免逐次审批；iSH 命令首用显示完整命令，可选单次或本对话授权（仅本次 App 运行内）；正式资料写入逐项确认；未来发送邮件/付款/预订/外部删除等仍需逐项确认。OpenMinis 的紧凑工具胶囊暂不复制，先沿用 Muse 头像和活动步骤，复杂长任务再复核。

## 历史更新：2026-10-11 DeepSeek iSH 工具调用验收（T53，审批方式后由 D37 更新）

本段审批卡与“尚未批准”状态仅表示 T53 当日行为。D37 后普通 iSH 命令和出站网络不再逐条审批；最新 DNS 构建与签名状态见下方 T63。

iPhone 模型设置已显示 DeepSeek key 保存在本机。首次显式 shell 请求在 `tool_choice:auto` 下只得到模型文字回复；活动详情没有工具事件、审批列表为空，因此该内容没有执行证据，不能记为真实结果，先前误称执行成功已更正。已修复为显式 shell 请求强制命名 iSH 工具调用，并在模型未返回工具调用时 fail closed。真实 DeepSeek 回合现已在 iPhone 显示完整命令的正式审批卡。卡片尚未由用户批准，因此 shell/Alpine 输出未运行，DNS 也未执行。定向测试10/10通过；全量 Core 216项中214项通过、2项因无实时端点跳过、0失败；签名真机 Debug 构建、校验和覆盖安装通过。详见 [T53](ITERATIONS.md)、[端侧运行时](ON_DEVICE_RUNTIME.md) 和本机截图索引 `.research-local/openmuse-device/2026-10-11/INDEX.md`。

## 前次更新：2026-10-11 iSH/Alpine 真机集成（T52 时状态）

T52 当日，用户已确认 GPL-3.0 与 iSH 路线。iSH ARM64 静态库和 Alpine 3.24.2 rootfs 已进入 iOS target；iPhone 15 Pro Max 签名安装并启动成功，Mac Debug、iOS Simulator Debug、iOS 真机 Debug 均构建通过。Core 回归 212 项中210通过、2项因实时 Pi/Tailscale 地址缺失跳过。包内许可证和 notices 已检查。当时手机设置尚未保存模型密钥，因此没有真实 DeepSeek tool-call 或 guest shell/DNS 结果；此项状态由最新 T53 更新。此前各日期段记录当时状态，旧的“iSH未集成/MIT”描述为历史记录；当前状态和证据以本页最新段落、[T53](ITERATIONS.md) 与 [端侧运行时](ON_DEVICE_RUNTIME.md) 为准。

## 2026-10-10：实现已获授权，首轮正在进行

用户以D31授权双端实现、必要测试、构建和可用设备安装。首轮工程采用Swift Package共享数据/模型层和XcodeGen双端工程；本地SQLite与核心Markdown已实现。当前状态：iPhone 16 Pro 真机安装、DeepSeek 对话和旅行构件通过；Mac App 已重建并打开，iPhone 经 Tailscale 完成配对和首次工作区同步。当前尚有18项版本冲突待用户选择；蜂窝外网与 Mac Pi 真正接管仍待验。OpenAI 供应商切换、后台续跑也未验证。完整证据见[ITERATIONS](ITERATIONS.md)和[覆盖审计](REQUIREMENT_AUDIT_2026-10-10.md)。

2026-10-11 构件方案更新：现在可在同一旅行构件保留七天原案并新增五天方案，编辑当前方案不会覆盖另一案；iOS 模拟器切换测试及 Core 持久化/构件包测试通过。外部事实核验、真机操作、Mac 离线恢复与跨设备方案冲突仍待验，其他一期缺口继续按审计处理。

更新2026-10-10。本轮用户明确指定补齐文档，六类缺口均有可审核方案；不是六类功能已实现，也不等于逐项参数已批准。旧审查报告保留当时缺口，新方案从此页进入。

2026-10-11 长期记忆召回更新：已让聊天上下文和手机历史工具共用本地概念别名扩展，定向与完整 Core 测试通过，iOS Simulator Debug 和 Mac Debug 构建通过。该改进只覆盖维护过的词表；任意语义召回、事实有效期与长期跨日效果仍未完成。证据和准确范围见 [T32](ITERATIONS.md) 与 [当前覆盖审计](REQUIREMENT_AUDIT_2026-10-10.md)。

2026-10-11 后续记忆时效切片：`MemoryClaim` 已支持可选有效期；明确偏好纠正会结束旧记录并开始新记录，检索和 USER.md 投影都会过滤尚未生效/已过期的记忆，日期可由用户编辑。历史导入不猜时间。一般事实冲突、主体判断、自然语言时间抽取和长期日常效果仍未覆盖；验证见 [T33](ITERATIONS.md)。

| 原缺口 | 本轮处理 | 状态 |
|---|---|---|
| 外出Mac连接与接管 | Tailscale；配对/HTTPS/事件/检查点/失联分支/去重 | App 配对与首次同步已在同一 tailnet 验证；18项冲突待选择，蜂窝与 Pi 接管待验证 |
| 免费安装/iCloud | 免费个人签名有限自用；iCloud允许后接，先认证通道直接同步 | 后置已确认；签名实际有效期、安装及同步待验证 |
| 后台/耗电 | 后台行为关卡；耗电采集后优化 | 阶段调整已确认；不能承诺永久后台 |
| 构件 | 包与数据/不可变版本/Web限制/导出恢复 | ARTIFACTS已制定，隔离与设备行为待验证 |
| 主动/成本/遗忘 | 频率/预算/安静/漏跑/预览/旁聊/敏感/删除/备份 | POLICIES默认方案已制定，数值可调 |
| 设计/任务/验收/节奏 | 实看10图的UI_SPEC、K01–K16与验收映射 | 已准备，未另做高保真稿；真实工期在首批结果后估计 |

[双端协议](RUNTIME_PROTOCOL.md)、[构件](ARTIFACTS.md)、[行为规则](POLICIES.md)、[页面规格](UI_SPEC.md)、[实施任务](IMPLEMENTATION_PLAN.md)。推荐原生Swift路线，首批A关卡先证实运行/连接/存储，再持续安装完整体验。

首轮已构建并启动Mac Debug App，也在iOS模拟器安装启动；真机签名因Xcode没有登录Apple Account且无开发描述文件而阻塞，等待用户在本机登录后继续。真实模型端点/密钥尚未在App内配置，QQ授权范围、Notion/Obsidian所选资料、OpenMinis复用依赖许可证仍待后续对应工作。密钥不经公开文档传递。引用OpenMinis代码前检查具体文件/依赖，应用许可证与实际复用边界一起定；原创文档MIT保持。

首轮暂定的执行边界：Pi 当前只用于模型回合并关闭工具，避免未建立工作区授权和隔离前访问Mac文件或运行命令。该决定可逆，但它意味着Mac执行本地操作尚未交付；在K05/K06实现工具授权、范围限制、取消和日志后再开放。

2026-10-10 更新：K06 的本机聊天桥接和设备配对已在代码中实现并通过合成集成测试，配对后手机聊天可路由到 Mac 的 Pi；Mac Settings 提供单独的 Tailscale Serve 8443 私有路由启用动作。代码检查会拒绝覆盖该端口已有服务，并核验其他端口配置不变。真实 tailnet 端到端与蜂窝验收还未完成。该桥接只代转模型回合，Pi 工具仍关闭，Mac 本地文件/浏览器操作未完成；模型真实凭证和 iPhone 真机签名仍各自需要用户配置/参与。

后续实测补记：当前 Mac 已启用独立 `8443/openmuse` Serve 路由，验证旧443根路由仍代理到原4387，Funnel也只在443。OpenMuse loopback `/health` 和 Mac 上三种 `curl` HTTPS 检查（默认、绕过代理、固定 tailnet IP）通过；OpenMuse `URLSession` 报 SecureTransport `-9816`。Apple 对该码的定义是服务端关闭会话但未发送通知，不足以判断为证书或 TLS 握手校验错误；具体差异未定位。当前 iPhone 的 Tailscale 节点离线，尚未真机配对，不能把 Serve 路由存在视为跨设备可用。待手机连入后分别验证 DNS、HTTPS、配对和聊天；社区中的 iPhone Serve HTTPS 报告仅作线索，详见 RUNTIME_PROTOCOL。

2026-10-10 模型实测补记：真实 `deepseek-chat` 通过 `OpenAICompatibleRuntime` 直连成功；Mac `PiRuntime`（本机 Pi 1.0.4）连通测试成功。再通过 OpenMuse 模型层完成恩施 7 天旅行的两轮对话，确认目标、旅行构件和两条完成活动记录均写入本机 OpenMuse 工作区，并在重新打开模型后读回。DeepSeek 配置与凭证只保存在本机设置/登录钥匙串，凭证值没有写进仓库或验证日志。Mac Debug 与 iOS Simulator 构建通过，模拟器应用已安装并启动；本轮没有在 iPhone 真机或 App 界面内输入/点击，不能据此宣称真机验收。该 key 未同步到 iPhone；正式使用前应在已连接的设备上分别配置，并在撤销当前临时 key 后换新。详见 [ITERATIONS](ITERATIONS.md)。

本页前文记录开工授权前状态。用户2026-10-10以D31明确进入代码阶段，替代此前“仍待授权”的门槛；无需重问D01–D30。若技术实验迫使改变重要产品承诺，记录失败并回到讨论。

### 历史补记：2026-10-10 最新完整验收

- 已解决：前文记录的 Mac `URLSession` 访问 Tailscale HTTPS Serve 失败现象。`MacBridgeClient` 改为空代理字典直连；本机当前私有 Serve 路由的 `URLSession` 健康检查与同一路由的 `curl` 均返回 HTTP 200。早期 `-9816` 是修复前记录，不能再视为当前未解决缺陷。
- 本轮自动化：`swift test` 17 项通过、0 失败、0 跳过；运行时启用了 loopback 合成 OpenAI SSE 服务与本机当前 Tailscale Serve 路由，覆盖 Pi RPC 回合和 Mac 到自身私有路由的 HTTPS 请求。iPhone 17 Pro / iOS 26.5 模拟器的 2 项 UI 测试通过，覆盖主导航、陪伴者面板、身份文件列表、侧栏搜索和模型设置表单。修改后的 Mac Debug 构建成功。
- 设备边界：Tailscale HTTPS 结果只证明这台 Mac 访问自身 Serve 入口，不证明 iPhone 到家中 Mac 的跨设备连接。PUA 与 Xcode 都报告真机离线；本轮没有 iPhone 安装、真机 UI、真机钥匙串或蜂窝网络验收。Mac 界面也没有做逐项点击验收。
- 模型边界：本轮用本机合成服务验证 Pi RPC；先前记录的真实 DeepSeek 两轮旅行闭环仍是当前可用证据，本轮未再次发送真实模型请求。OpenAI 真实账号切换、iOS 真机模型请求、流式、取消和 usage 仍未验收。
- 证据位于忽略的本机 `.build/logs/`：`swift-test-complete-verified.log`、`ios-ui-test-verified.log`、`final-mac-build.log`。完整功能状态按 [PHASE1_PARITY](PHASE1_PARITY.md) 的最新测试矩阵读取；未实现功能不因空状态页面测试通过而算作已实现。

### 2026-10-11 验收记录：真机旅行闭环（配对前）

- iPhone 16 Pro / iOS 27.2 已签名安装并启动 OpenMuse 0.1.0 (2)。DeepSeek `deepseek-chat` 连接测试和恩施旅行计划真实对话通过；7/7 构件、目标 1/3、成功活动状态和覆盖安装后数据保留通过。
- iPhone Tailscale 已连接，Safari 访问 Mac 专用 HTTPS `8443 /openmuse/health` 返回200；这不是蜂窝外网验收。App 内配对码、共享资料同步和 Mac Pi 任务接管尚未完成。
- `swift test` 最终 137 项执行、135 项通过、2 项因实时 Tailscale/Pi 端点缺失而跳过、0 失败。Mac 与 iOS 真机 Debug 构建通过。最终 UI 状态提示位置由真机手工验收可见，状态提示修复后没有重跑完整 iOS UI 自动化。
- 后续顺序：完成 App 配对和共享资料同步；在可控的蜂窝网络下验收 Mac 接管；单独验证锁屏/后台续跑。OpenAI、连接器真实账号、14 天观察和逐页 Muse 视觉验收仍未完成。

### 2026-10-11 更新：Mac 共享工作区身份与 iPhone 首次同步

- 根因与修复：此前手机提示 Mac 未提供共享工作区身份。对照运行包和源码后确认 `dist/OpenMuse.app` 落后于已更新的桥接源码；另一次检查发现服务未响应。重建并重新打开当前 Mac Debug App 后，服务恢复，配对响应包含共享工作区身份。
- 设备实测：用户在 iPhone 内直接输入 Mac 一次性配对码；OpenMuse 设置显示“已配对”，可用 Tailscale 地址访问 Mac。Mac 本机 `127.0.0.1:4388/health` 和 Tailscale `8443/openmuse/health` 均返回 HTTP 200；Mac App 签名校验通过。
- 同步结果：首轮传输 176 条、接收 36 条后提示尚有批次；再次同步后待发送/接收均为 0，附件与构件图片本轮传输均为 0。仍有18项版本冲突待选择，界面明确显示双方版本都已保留；未替用户决定冲突版本。
- 回归：新增配对集成断言，要求配对响应返回与 Mac 相同的 `workspaceID`；聚焦测试结果与日志见 [ITERATIONS](ITERATIONS.md)。Mac 重建日志为 `.build/logs/openmuse-mac-2026-10-11-repair-bridge-identity.log`，签名产物位于本机忽略目录 `dist/OpenMuse.app`。
- 未完成：本次没有执行真实 Mac Pi 委派，未测试蜂窝网络、冲突解决、锁屏/后台运行或连接器真实账号。配对和同步通过不等于完整一期通过。

### 2026-10-11 更新：OpenMinis 端侧工作区与 iPhone 启动

- 已完成：iPhone Agent Workspace 已改为 Application Support 下按对话隔离的持久目录；旧 Caches 文件只迁移一次且保留源；不自动过期，设有文件类型、路径、符号链接、数量和体积上限。正式记忆/目标继续由 SQLite 与 Markdown 管理，工具不能把工作文件直接写成记忆。
- 验证：全量 `swift test` 为 151 项、149 项通过、2 项实时 Pi/Tailscale 条件跳过、0 失败；记录在 `.build/logs/openmuse-on-device-runtime-full.log`。iOS Simulator Debug、Mac Debug 和 iOS device Debug 均构建成功。设备包位于 `.build/derived-openminis-runtime-device/Build/Products/Debug-iphoneos/OpenMuse.app`。
- 真机：iPhone 16 Pro / iOS 27.2 已由 Xcode/`devicectl` 安装并启动 `org.openmuse.ios`。PUA 控制服务启动后，WDA 遇到系统认证取消，`pua_ready` 仍返回 `pua_unreachable`；故真机页面、模型工具调用、工作区持久化、DeepSeek tool-call、锁屏后台均未验收。用户需要在手机上解锁并处理 Face ID/UI 自动化提示后才能继续 PUA 验收。
- 重要缺口：当前是受控 Swift 原生 Agent Runtime，不含 OpenMinis iOS 的 iSH/Alpine shell 或 native offload。固定上游源码的许可涉及 GPL-3.0 和 iSH 附加文本；在公开发行许可证、构建和安全策略明确之前，不改项目 LICENSE 或把 GPL 代码并入产品。这个缺口已写入 [端侧运行时方案](ON_DEVICE_RUNTIME.md)；产品使命、Muse 交互、模型选择、Mac Pi 优先和长期记忆数据合同保持不变。
- 下一步：收到用户完成手机解锁/系统授权的通知后，先重新验证 PUA READY，再在真机检查启动界面和当前会话工作区读写/重开保留。iSH 发行许可证是独立重大决策；在这个决策前只继续验证现有原生 runtime，不把它报告为 OpenMinis 完整 parity。

### 2026-10-11 iSH ARM64 构建可行性重试

固定 iSH fork 已在忽略的 `.build` 研究目录中验证到 ARM64 scheme 和 Meson 配置阶段；第一次因缺少 `ld.lld` 停止。Homebrew 安装 LLVM/LLD 将升级现有全局工具链依赖，因此已在安装前中断；当前没有全局软件包变更。后续在 `.build` 内使用官方 LLVM 15.0.7 x86_64 macOS linker 重试，同一 ARM64 Release device scheme 在关闭 `ISH_FFMPEG_TEST` 后也构建通过；`.app` 包含 Alpine rootfs，宿主可执行文件为 arm64。直接选择常规 target 的构建路径遇到上游 libarchive 平台配置问题。产物未签名、未装入 iPhone，OpenMuse 尚未集成 iSH；许可证、适配和隔离仍是后续关卡。日志与边界见 [T28](ITERATIONS.md) 和 [端侧运行时方案](ON_DEVICE_RUNTIME.md)。

补充验证：iSH `libiSHApp` helper target 以 `iphoneos/arm64` 单独编译成功，但该 archive 不是可直接调用的 kernel/shell 集成包。OpenMuse 尚未链接它；下一步仍需适配 OpenMinis 的实际 kernel host 接口并解决组合发行许可。详见 [T29](ITERATIONS.md)。

端侧宿主已新增 OpenMinis 风格的会话挂载表及 5 项目录隔离/只读策略测试；目前只是独立 Core 能力，尚未由 AppModel 调用或接入 guest。见 [T30](ITERATIONS.md)。

2026-10-11 后续切片：iPhone 本机工具现在可只读列出并提取当前对话附件，按 conversation ID 限制范围、读取前核验 SHA-256、最多列 40 项且每份最多 20 KB；3 项定向测试通过，完整 Core 回归 158 项中 156 项通过、2 项因无实时 Pi/Tailscale 地址跳过，iOS Simulator Debug 和 Mac Debug 构建成功。该能力由 Swift 宿主执行，未挂入 iSH guest，真机 tool-call 未验。详细证据见 [T31](ITERATIONS.md)。

2026-10-11 后续切片：旅行构件现可在同一构件中保留七天原案并新增五天备选，普通修改只更新当前方案；两端通过同一 artifact 同步事件传输整组方案，失败回复不会覆盖旧成果。QQ IMAP 解析新增受限的嵌套 multipart 纯文本提取、常见编码解码与附件排除。Core 全量 172 项中170项通过、2项依赖实时 Pi/Tailscale 端点跳过；本轮 Mac Debug 和 iOS Simulator Debug 构建通过。没有重装 iPhone，也没有用真实 QQ 账号验收。另保存 OpenMuse 图标概念稿 v3，尚未应用到双端 AppIcon。详见 [T34–T36](ITERATIONS.md)。

2026-10-11 Dreaming 后续切片：近期回顾现在可对进行中目标提出有来源的小步骤，只有用户接受后才追加；暂停目标、跨对话来源、可识别敏感的目标步骤/提案字段/摘要会被拦截或清空。运行摘要哈希覆盖实际 system prompt 与 sanitized user context，不保存完整提示文本。Core 全量 176 项中174项通过、2项依赖实时 Pi/Tailscale 端点条件跳过；Mac Debug、iOS Simulator Debug 构建成功。此前目标步骤审批 UI 自动化通过。该能力仍只是一种有限的 dreaming 候选，不含周期目标研究、关系维护、外部行动或可靠锁屏后台；敏感词检测也不能保证覆盖所有表达。详见 [T37](ITERATIONS.md)、[讨论 T33](DISCUSSIONS.md) 和需求审计。

2026-10-11 兴趣动态补充：已将有限本地主题词组用于动态说明、明确用户兴趣、进度目标和已保存的正负反馈；当前有效期外或敏感记忆不参加排序。初次复用全量中文 n-gram 出现过误排序，定向测试发现后改成小型词组匹配并限制单类分值。真实 RSS 来源、跨会话语义学习与自用排序效果仍未验。见 [T38](ITERATIONS.md) 和 [讨论 T34](DISCUSSIONS.md)。

### 2026-10-11 更新：手机工作区写入审批闭环

iPhone 的对话隔离工作区写入现在要求逐项确认，单次上限 8 KB；确认页展示路径、创建/替换状态与完整正文。拒绝不写入，取消与 App 重启会废弃待批请求；写入前复查目标指纹。模型运行及等待批准期间禁止切换或新建对话，避免审批跨会话错配。相关 Core 测试 18/18 通过；完整 Core 184 项中182项通过、2项因没有实时 Pi/Tailscale 端点而跳过；iOS 模拟器审批 UI 1/1 通过；Mac Debug 与 iOS device arm64 未签名 Debug 构建通过。详见 [T39](ITERATIONS.md)。

真机 UI 验收仍未完成：iPhone-use 服务已按现有配置启动，但 Xcode 报告已连接的 iPhone 处于锁屏状态，WDA 不能启动。已经请求用户解锁并保持亮屏；在用户完成前不执行手机操作，也不把模拟器结果说成真机结果。Mac Pi 仍无写工具，浏览器/桌面、iSH/Alpine、后台持续执行等一期缺口继续保留。

### 2026-10-11 后续：持久浏览器与活动详情复验（T58）

iPhone 15 Pro Max 已重新连接并通过 PUA READY。签名版 `org.openmuse.ios` build 2 安装、签名校验和启动通过。真实模型先在 `tab_id=1` 打开并读取 `example.com`，后续回合通过 `list_tabs` 找回同一标签；天气搜索实际尝试 Google 后回退到 Bing。活动详情在本轮暴露了中高度面板裁切参数的问题，现已改成默认全高、统一滚动；模拟器活动详情 UI 测试 1/1 通过，真机展开确认工具名、调用编号、执行设备、查询参数、标签 ID 与返回内容。

33 项定向 Core 测试通过。尚未验证 Google 在当前网络成功、网站 Cookie/localStorage 跨重装、iSH DNS/外网命令、iSH 取消与崩溃恢复、可靠锁屏后台和蜂窝网络；天气卡只用于工具流程验证，不作为天气准确性证明。完整状态见 [T58](ITERATIONS.md)、[一期对照表](PHASE1_PARITY.md) 与 [端侧运行时](ON_DEVICE_RUNTIME.md)。

### 2026-10-11 后续：模型与 iSH 共用浏览器标签（D41/T62）

已按 OpenMinis 固定源码实现会话级共享：iPhone Agent 和 iSH `openmuse-browser-use` 现在操作同一个浏览器 runtime。真机 DeepSeek 先用 `browser_use` 打开 `https://example.com/`，再从 iSH 列出 `tab_id=1` 并用同一 ID 读取正文；两条 iSH 操作详情都能回看命令、设备、参数和结果。全量 Core 测试执行 235 项、233 通过、2 项跳过；更新后的 iOS 签名构建与安装结果见 [T62](ITERATIONS.md)。上游截图、任意 JS、Cookie、下载仍没有接入；不声称全量功能一致。

### 2026-10-11 后续：guest DNS 对齐与签名阻塞（T63）

OpenMinis 固定源码使用 iOS 系统 resolver nameserver 配置 guest，并在网络路径变化时刷新；OpenMuse 之前的宿主 `getaddrinfo` 合成代理在 iPhone 上出现假地址和 guest 请求失败。已按上游路线替换，并链接 iOS `libresolv`；arm64 unsigned Debug 编译/链接通过。当前 Xcode 命令行报告没有 Apple 账号及 `org.openmuse.ios` provisioning profile，故新包未签名、未安装。旧代码 DNS 真机失败已确认，新代码 DNS/HTTPS 尚未验。继续验收需要在 Xcode 重新添加 Apple Account/Personal Team 并生成描述文件，再构建安装；日志为 `.build/logs/openmuse-ish-network-device-build.log` 与 `.build/logs/openmuse-ish-network-device-signed-build.log`。

### 2026-10-11 后续：浏览器动作向 OpenMinis 补齐（T64）

再次按固定源码复核后确认：持久标签、默认模型浏览器、与 iSH 共池及活动详情已由 D40/D41/T62 实现并真机验证；T64 新增页面结构树、连续滚动采集及悬停，模型与 iSH 共用实现。Core 参数测试 8/8、iOS Simulator Debug 编译通过；新增动作尚未安装至真机。截图回传、下载、任意 JS 和 Cookie 工具仍是明确差距，完整边界与实现记录见 [T64](ITERATIONS.md)。

### 2026-10-11 端侧工作区迁移补齐

用户显式导出的含聊天迁移包现可携带会话 Agent 草稿；不含聊天的包排除草稿。导入按路径/大小/摘要校验，同内容幂等跳过，冲突另存；如果数据库先落盘而草稿恢复失败，界面会说明部分成功并支持重试。草稿仍不自动同步到 Mac，也不进入核心记忆。Core 回归与双端构建证据见 [T41](ITERATIONS.md)。iSH/Alpine 的上游集成仍受组合许可证和运行时隔离关卡约束，当前原生 Swift runtime 不应描述成完整 OpenMinis parity。

### 2026-10-11 guest 工作区安全边界复核

端侧目录合同已修正：未来 iSH 可写的 `/var/minis/workspace` 将映射到每个对话专属运行草稿区，不再映射正式 `OnDeviceAgentWorkspace`，避免绕过 Swift 原生写入审批。6 项定向测试、194 项 Core 回归（2 项实时端点条件跳过）及 Mac/iOS Simulator Debug 构建通过，证据见 [T44](ITERATIONS.md)。这只是隔离边界和编译验证，当前 AppModel 仍未调用该 mount 表；iSH/Alpine、只读记忆/skills 投影、真机 shell、native offload 和后台续跑未完成。许可证问题待用户决定，期间保留 MIT、未引入 GPL 代码。
