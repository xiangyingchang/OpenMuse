# 迭代记录

## T83：2026-10-13 主聊构件卡按来源消息排序

- 问题：用户第二次指出旅行计划草稿卡一直固定在主聊底部，哪怕后续已有新的聊天；要求先对方案确认后再改。本轮已按确认方案修复。
- 根因与处理：聊天视图过去先绘制全部消息，再把所有构件卡统一追加到列表末尾。现在构件卡和消息使用同一时间线，按卡片来源消息放在最近一条来源消息之后；后续聊天自然显示在卡片之后。同名构件仍合并成一张呈现卡。没有来源消息可匹配的旧构件不会再占据主聊位置，仍能从资源库打开，底层数据不删除。
- 验证：Core 时间线定向测试 4/4 通过；iPhone 17 Pro Max / iOS 26.5 Simulator 时间线 UI 回归 1/1 通过，检查顺序为“来源回复 → 构件卡 → 后续用户消息”。测试日志 `.build/logs/openmuse-t83-core-tests.log`、`.build/logs/openmuse-t83-artifact-timeline-ui-rerun.log`，UI 结果 `.build/OpenMuse-T83-ArtifactTimeline-UI2.xcresult`。`git diff --check` 通过。
- Release：iOS ARM64 Archive 和 IPA 导出通过；包内 `codesign --verify --deep --strict` 通过，版本 `0.1.3 (12)`，Bundle ID `org.openmuse.ios`。个人开发签名的描述文件于 2026-10-18 到期；需在有效期内安装，之后需重新签名。IPA 位于 `.build/OpenMuse-T83-iOS-Release/export/OpenMuse.ipa`，SHA-256 `e82879250eb5bed7fd0a3dbbd3b1e6a2a77536379dde175f0291bb91cff4d944`。本轮未安装真机，模拟器 UI 通过不代表本机 iPhone 已更新。首次归档因 iSH 脚本找不到 LLD 失败；确认已有 iSH 构建计划和二进制均为 Ninja `no work to do` 后，用 `OPENMUSE_REUSE_CACHED_RUNTIME=1` 重试并成功，没有安装全局 LLVM。日志 `.build/logs/openmuse-t83-ios-release-archive-retry.log`、`.build/logs/openmuse-t83-ios-release-export.log`。
- 发布边界：此处的 Release 包是本机可安装 IPA；本轮没有创建 GitHub Release，也没有提交或推送。

## T82：2026-10-13 主聊列表、同名成果、回复风格与 AlarmKit 对齐

- 用户提出三个体验问题并补充要求闹钟实现重新对照 OpenMinis。Muse 本机侧栏截图已实际查看：“聊天”在上方选项卡，下面只列旁聊；没有单独“主聊”行。
- 根因：旧根会话并入持续主聊后，多个同名成果记录仍是独立数据；聊天页逐条展示，造成重复卡片。现在按同类型和标题在聊天页合并呈现，默认打开最新记录，并可从菜单分别打开底层记录；没有删除或覆盖任何成果。
- 侧栏保留 Muse 的上方“聊天”标签并令其直接打开唯一主聊。下方不再列主聊行，只列旁聊和导入聊天；撰写按钮直接新建以主聊为父级的旁聊。视觉参考 Muse 2026-10-10 侧栏观察和本地归档图，原图不进入公开仓库。
- 回复风格按用户明确要求调整：简单问题优先直接、简短，不重复背景；分析、计划和高影响事项说明必要依据与步骤，不设置固定字数上限。persona 反馈识别补充“太多废话”和“简洁有用”等表达，仍按现有 SOUL 可撤销流程保存。
- 闹钟首次真机调度曾返回 AlarmKit error 0。按用户要求再次对照 OpenMinis 固定提交：其 bridge 的普通闹钟使用 Alert-only，不提供 Countdown/Paused；OpenMuse 没有 widget extension，故普通闹钟改成 Alert-only，计时器仍提供 countdown duration。Apple 官方 AlarmKit 示例也将 Countdown/Paused 设为可选；没有复制上游代码。新构建真机通过四条创建/查询/取消闭环：HH:mm 一次性、带时区 ISO8601 一次性、工作日重复、1 小时计时器；每次 set 与 list 的 ID、名称及适用的时间/状态相符，按 ID 取消后 list 均为空。旧版 error 0 与新构建成功之间尚不能证明唯一因果；本轮没有等到响铃，以免夜间打扰，实际响铃仍待合适时段验证。
- 自动化验证：定向 Core 测试 12/12、完整 Core 测试 267 项中 2 项条件跳过且 0 失败；主聊侧栏模拟器 UI 用例 1/1 通过。iOS ARM64 Release Archive 与 IPA 导出、`codesign --verify --deep --strict` 通过；安装后确认 iPhone 上显示 `0.1.3 (11)`。真机侧栏显示顶部“聊天”入口、下方只有“旁聊”说明；点击顶部“聊天”返回原主聊成功。真机四类闹钟/计时器创建、列表核对、按 ID 取消及清空列表均通过；实际系统响铃没有测试。
- 交付：本地签名 IPA 为 `.build/OpenMuse-T82-iOS-Release/export/OpenMuse.ipa`，SHA-256 `d76aad0856c84815c775839a400abcc0be5416888075f4bfd72d4ab301f31aad`；公开源码 Release 已发布为 [v0.1.3](https://github.com/xiangyingchang/OpenMuse/releases/tag/v0.1.3)，不附设备专用签名包。构建与 UI 日志位于 `.build/logs/openmuse-t82-ios-release-archive.log`、`.build/logs/openmuse-t82-ios-release-export.log`、`.build/logs/openmuse-t82-sidebar-ui-test.log`。

## T81：2026-10-12 iPhone 闹钟能力与备份包审计

- 需求与依据：用户报告 OpenMinis 可设置闹钟、OpenMuse 不可用；对照固定源码 `OpenMinis b4c0661d5631ebab1d4a2e6f3fd4c805d4030a6c`，iSH `apple-alarm` 通过原生 offload 调用 AlarmKit。新增 OpenMuse 的 `openmuse-alarm` 命令桥，支持单次/重复闹钟、计时器、列表与取消；需 iOS 26+ 和系统 AlarmKit 授权，Mac 离线时由手机本地执行。另按上游 fail-closed 检查运行时 AlarmKit 是否真的存在，避免兼容运行环境误报 iOS 26+ 后进入不可加载框架。OpenMinis 源码只作行为参考，未复制上游代码。
- 备份代码审计：外层 ZIP 导入过去先把目录条目物化为数组，再限制条目数；改为有界遍历并拒绝超量、重复或非文件条目。文件选择后先检查大小，拒绝超出格式上限或无法确认大小的文件，再映射读取。手动备份说明现在明确本机 AlarmKit 闹钟/计时器不在共享工作区备份内。
- 本机备份核验未发现格式结构问题；个人归档、聊天内容、路径、规模和摘要不写入公开项目文档。
- 代码级剩余边界：通用导入会恢复 `ScheduleRecord`，但不会自动向系统通知中心重新注册本机提醒。系统级提醒恢复策略单独登记，不在备份导入中静默重建。
- 自动验证：`PhoneAlarmCommandTests` 7/7 与 `WorkspaceBackupTests` 6/6 通过。完整 Core 回归 263 项、2 项因缺少 Pi 集成端点跳过、0 失败；其中一个旧会话切换测试改为创建真实旁聊，以匹配持续主聊语义。iOS Simulator Debug 与 Mac Debug 构建通过。Release ARM64 Archive 和 Personal Team IPA 导出成功，版本 `0.1.1 (9)`；完整归档与签名校验通过。首次归档因脚本找不到本机 LLD 失败，已使用项目缓存中的 LLD 重试。日志：`.build/logs/openmuse-t81-core-tests-final.log`、`.build/logs/openmuse-t81-phone-approval-current-contract.log`、`.build/logs/openmuse-alarm-command-tests.log`、`.build/logs/openmuse-backup-audit-tests.log`、`.build/logs/openmuse-t81-ios-simulator-build.log`、`.build/logs/openmuse-t81-macos-build.log`、`.build/logs/openmuse-t81-ios-archive-final.log`、`.build/logs/openmuse-t81-ios-release-export.log`。
- 真机与交付：当时已完成安装和命令行启动，但真实 UI、模型工具调用和设备闹钟尚未验收；安装/启动不等于功能验收。该闹钟验收已在 T82 以新构建补做。

## T79：2026-10-12 聊天回复状态、流式文本与透明顶部

- 需求：用户指出回复期间头像缺少 Muse 式任务反馈、文字要等模型全部结束才出现、顶部背景挡住对话，并要求核对当前行为后再实现。
- 现状与根因：工具调用默认路径固定请求 `stream: false`，所以即使 API 支持 SSE，手机也只能显示完整答案。Mac 的 Pi RPC 和 iPhone 配对协议也只把完整回复返回手机。头像环没有可见的持续动效；活动阶段只更新在工具操作详情里，聊天顶部没有显示。聊天顶部单独占布局高度且有不透明背景，消息不能滚到其后方。
- 变更：OpenAI-compatible 工具调用请求按模型能力开启 SSE，解析文本和分片函数参数，按序显示普通回复及工具调用后的回答；若用户明确要求 iSH/浏览器而模型只给普通文字，先暂存文本，确认真实工具调用后才展示，避免失败时误把文字当执行结果。Mac Pi 读取 RPC `message_update.assistantMessageEvent.text_delta`，经配对设备认证的活动轮询通道回传 iPhone；旧协议仍可解码，关闭流式的模型继续走原非流式分支。聊天顶栏改为透明浮层，圆形操作和可点击名称胶囊保留半透明材质，任务阶段是无底色文字；头像在发送时轻柔脉动并尊重系统“减少动态效果”，阶段文案取自真实 ActivityRecord。
- 验证：测试专用内存 Keychain 下 `swift test` 执行252项，2项因实时环境条件跳过、0失败。定向 Core 用例覆盖 SSE 工具参数分片、回复与工具事件顺序、Pi 增量、认证桥接增量、强制工具失败时不显示普通文字，均通过。Mac Debug 构建通过；iOS Simulator 的聊天首屏 UI 截图用例 1/1 通过，已查看合成截图；iOS ARM64 签名 Debug 构建通过。结果日志仅留在本机忽略目录 `.build/`。
- 未验收：该轮没有真机视觉/动效验收、真实模型首字延迟测试或已配对 iPhone→Mac 在线回合。模拟器截图用例证明首屏布局可渲染，不证明发送中的动画、阶段切换或模型流式体验已在真机通过。其余一期需求按 [PHASE1_PARITY](PHASE1_PARITY.md) 继续跟踪。

## T78：2026-10-12 安装当前版本到 iPhone

- 构建：将 iOS 构建号从5递增到6，Mac 版本号保持5。当前源码以 Personal Team 自动签名构建为 `0.1.0 (6)`；使用仓库忽略目录中的 LLD 构建 iSH，没有修改全局工具链。
- 安装与启动：`devicectl` 安装 `org.openmuse.ios`、启动应用，并从设备应用清单确认版本 `0.1.0 (6)`。`codesign --verify --deep --strict` 通过。
- 证据：`.build/logs/openmuse-t78-iphone16-signed-build.log`、`.build/logs/openmuse-t78-iphone16-install-verify.log`。
- 边界：完成构建、签名、安装和命令行启动验收；本轮未做 PUA 视觉页面验收、模型请求或核心流程重测。测试与构建证据见 [T77](ITERATIONS.md#t77)，T76 的完整模拟器 UI 回归仍是17/17。

## T77：2026-10-12 发送前模型凭证竞态与跨端构建回归

- 根因与修复：Keychain 凭证异步读取尚未完成时，用户首次发送会看到“未配置模型”。发送前现在会异步刷新凭证状态，再决定是否拦截；健康路由测试改用临时端口，避免占用运行中的 Mac 服务。初始化器注入端口值而非 macOS 专属类型，修复首次 iOS 模拟器编译发现的条件编译错误。
- 回归：使用仅测试启用的 `OPENMUSE_TEST_IN_MEMORY_KEYCHAIN=1` 后端运行 Core 全量测试，251项执行、249项通过、2项条件跳过、0失败；该结果不覆盖真实系统 Keychain 集成。首次发送目标追踪回归 1/1 通过，Mac Bridge 本机健康路由测试 1/1 通过。
- 构建：修改后 Mac Debug 和 iOS Simulator Debug 均构建成功。iOS 模拟器完整 UI 17/17 的结果属于 T76（发送竞态修复前），本轮没有重跑全套 UI。
- 证据：`.build/logs/openmuse-t77-core-tests-final.log`、`.build/logs/openmuse-t77-credential-readiness-regression.log`、`.build/logs/openmuse-t77-bridge-startup-port-isolation.log`、`.build/logs/openmuse-t77-mac-build.log`、`.build/logs/openmuse-t77-ios-sim-build.log`；T76 UI 结果见 `.build/logs/OpenMuseT75FullUIAfterKeychainfix.xcresult`。
- 未完成：真机未重装；真实模型密钥/系统 Keychain 路径未在本轮端到端验证。当前 Computer Use 会话 `apps=[]`，没有桌面应用控制，仍不能目视 Xcode Signing & Capabilities；CLI 的 Team/profile 设置也未选定。需要在提供原生桌面控制的本机 Codex 任务中继续。

## T76：2026-10-12 修复后完整 iOS Simulator UI 回归

- 范围：在 T75 将 Keychain 读取移出主线程后，对当前源码重新运行完整 iOS UI 套件，避免只沿用修复前结果。
- 环境与结果：iPhone 17 Pro / iOS 26.5 Simulator；17项通过、0失败，运行时427.340秒。覆盖活动操作详情和复制、构件删除与旅行方案、键盘/底部栏、设置、记忆导入与有效期、工具审批、人格撤销、目标进度、本地网页构件。
- 证据：`.build/logs/openmuse-t75-ios-full-ui-after-keychainfix.log`；`.build/logs/OpenMuseT75FullUIAfterKeychainfix.xcresult`。
- 边界：这是模拟器 UI 验收，不证明真机安装、真实模型请求、锁屏后台、Tailscale 连接或硬件交互。Core 全量测试仍受 T75 记录的系统 Keychain 阻塞影响。

## T75：2026-10-12 Mac 首屏钥匙串阻塞修复与签名检查

- 根因：Build 5 Mac App 启动后，`127.0.0.1:4388/openmuse/health` 超时。`sample` 显示主线程在 `ChatHomeView.body` 读取 `isModelReady` 时同步调用 `SecItemCopyMatching`，随后卡在 Keychain 解密；桥接健康请求也无法在主线程处理。
- 修复：`SecureStore` 增加异步 API 密钥和配对令牌读取；`OpenMuseAppModel` 用可观察的缓存状态供 SwiftUI 首屏渲染，模型调用和配对流程改为异步读取。旧的在途读取不能覆盖后续保存/删除状态。
- 验证：Mac Debug `0.1.0 (5)` 构建成功，`codesign --verify --deep --strict` 通过，启动后本机健康路由返回 HTTP 200；`MacAppBridgeStartupTests` 1/1 通过。iOS Simulator Debug 构建成功；修复后导航/设置页定向 UI 2/2 通过，随后 T76 在修复后的当前源码上完整 UI 17/17 通过。相关日志：`.build/logs/openmuse-t75-mac-keychainfix-build.log`、`.build/logs/openmuse-t75-mac-bridge-startup-test.log`、`.build/logs/openmuse-t75-ios-keychainfix-build.log`、`.build/logs/openmuse-t75-ios-keychainfix-ui.log`；修复前17项结果包 `.build/logs/OpenMuseT75SimulatorUI.xcresult`，修复后定向2项结果包 `.build/logs/OpenMuseT75KeychainfixUI.xcresult`，修复后完整17项结果包 `.build/logs/OpenMuseT75FullUIAfterKeychainfix.xcresult`。
- 未完成：完整 `swift test` 重跑两次都停在测试本身的同步 Keychain `SecItemAdd`/`SecItemCopyMatching`，没有产生断言失败，也没有得到完整 Core 通过结果；进程已停止。日志为 `.build/logs/openmuse-t75-core-tests-after-async-keychain.log` 和 `.build/logs/openmuse-t75-core-tests-after-keychainfix.log`。真实模型密钥读取/请求未验，真机版未安装。
- Xcode 签名核对：当前 Computer Use 会话只暴露浏览器，桌面应用列表为空；虽然已把 `OpenMuse.xcodeproj` 交给 macOS 的 Xcode 打开，仍无法目视 `Signing & Capabilities`。CLI 确认 iOS target 为 `CODE_SIGN_STYLE=Automatic`、bundle ID 为 `org.openmuse.ios`，但 `DEVELOPMENT_TEAM` 与 provisioning profile 均未设置。此结果不能证明 Apple 账号未登录，只能说明当前工程构建设置没有选定 Team/profile；待可用桌面控制会话后再目视复核。

## T74：2026-10-12 双端 Build 5 构建

- 范围：为当前源码生成新的双端 Debug 构建；将 iOS 与 macOS 构建号从4递增到5，供后续验收区分。
- 构建：iOS ARM64 Device Debug 与 Mac Debug 均编译成功，版本均为 `0.1.0 (5)`。iOS 产物位于 `.build/derived-openmuse-device-current/Build/Products/Debug-iphoneos/OpenMuse.app`，确认架构为 arm64；Mac 产物位于 `.build/derived-dreaming-mac/Build/Products/Debug/OpenMuse.app`。日志：`.build/logs/openmuse-v5-ios-device-unsigned-build-2026-10-12.log`、`.build/logs/openmuse-v5-mac-build-2026-10-12.log`。
- 签名/安装：iOS 包未签名，未安装到 iPhone。Xcode 命令行找不到 Personal Team 对应的账号和开发描述文件；即使请求自动配置也无法生成。Mac 包本轮也未签名、未启动验收。解决 iOS 签名后才可安装 Build 5。
- 处理：iSH ARM64 构建使用 `.build/ish-tooling` 中现有 LLD 的绝对路径；没有修改全局工具链。构建包含未声明输出的脚本阶段等非阻断警告。功能测试沿用 T73 的 Core 与3项相关 UI 结果，本轮仅改版本元数据并验证构建；`git diff --check`、iOS Info.plist / Xcode 项目 lint 与 `project.yml` YAML 检查通过。

## T73：2026-10-12 Dreaming 记忆方案回归验证

- 范围：对 T72 的维护反思记录调整做后续完整回归；本轮只验证，不改应用实现。
- 自动化：`swift test` 执行247项，245项通过、2项条件跳过、0失败。跳过项分别需要实时 Tailscale 路由与本地 Pi RPC 服务。iPhone 17 Pro / iOS 26.5 Simulator 上与 dreaming 来源、步骤采纳、记忆更新确认相关的3项 UI 自动化全部通过。没有运行完整 UI 套件。
- 构建：`OpenMuseMac` Debug 与未签名的 `OpenMuseiOS` generic Simulator Debug 均构建成功。`git diff --check` 通过。日志：`.build/logs/openmuse-dreaming-final-swift-test-2026-10-12.log`、`.build/logs/openmuse-dreaming-final-mac-build-2026-10-12.log`、`.build/logs/openmuse-dreaming-final-ios-simulator-build-2026-10-12.log`、`.build/logs/openmuse-dreaming-final-ios-ui-tests-2026-10-12.log`；UI 结果包 `.build/logs/OpenMuse-Dreaming-UI-Tests-2026-10-12.xcresult`。
- 未验：未启动实时 Pi/Tailscale 集成、没有请求真实模型，也没有构建/安装真机版；最近一次真机记录仍是 T68。Xcode 构建含构建脚本未声明输出的非阻断警告；UI 测试期间还打印调试器版本信息告警，但3项均通过。

## T71：2026-10-12 当前工作区状态收敛

- 范围：复核 T70 后的当前源代码、记忆/备份测试和双端 Debug 构建，并将当前状态与历史设备证据分开记录；没有修改产品实现。
- 自动化：`swift test` 执行247项，245项通过、2项因未配置实时 Pi/Tailscale 地址跳过、0失败。另跑 `MemoryDocumentProjectionTests` 与 `WorkspaceBackupTests`，8/8通过。完整日志 `.build/logs/openmuse-status-convergence-2026-10-12-swift-test.log`。
- 构建：`OpenMuseMac` Debug 与 `OpenMuseiOS` Debug（generic iOS Simulator，未签名）均构建成功。日志分别为 `.build/logs/openmuse-status-convergence-2026-10-12-mac-build.log` 和 `.build/logs/openmuse-status-convergence-2026-10-12-ios-simulator-build.log`。两端均有非阻断警告；此次没有跑 UI 自动化、真机设备构建或安装。
- 诊断更新：T70 的 `WorkspaceBackup.swift` 编译错误对应旧源码状态；当前文件已变化，T71 重新构建通过，因此该项不再是当前阻塞。当前本地代码没有因此自动成为已部署版本。
- 设备边界：最近一次记录的真机版本仍是 T68 的 iPhone 15 Pro Max / iOS 27.2 / Build 4；T71 未重装、未检查当前 Keychain、未发送真实 DeepSeek 请求，也未确认设备目前在线。T67 保留地址 DNS 结果不能证明中国境内直连。18项首次同步冲突仍按上次实测记录为待选择，本轮未读取设备来确认是否变化。
- 尚未完成：真实 iPhone→Mac Pi 任务、蜂窝与中国网络、当前代码的真机安装、锁屏后台、完整 UI 自动化、真实连接器、Muse 逐页像素对照、十四天自用和 iCloud 同步仍不因本轮构建通过而关闭。

## 2026-10-11：原创图标接入双端构建

- 设计：新增 OpenMuse 原创图标概念稿，以相向弧形和暖色星芒形成陪伴意象；保留 PNG 原稿作为可追溯母版。
- 接入：生成 iOS 1024×1024 AppIcon 与 macOS 16–1024 Retina 尺寸，分别加入两个 Asset Catalog，并在 iOS/macOS targets 的资源阶段引用。无 Muse 原始图形或私人截图进入资产。
- 验证：iOS Simulator Debug 与 macOS Debug 构建均成功；iOS `Assets.car` 中确认 `AppIcon` phone 与 pad 图像均为 1024×1024，Mac 包生成 `Contents/Resources/AppIcon.icns`，Info.plist 的 icon 名称为 `AppIcon`。签名 iOS 真机 Debug 构建通过，`codesign --verify --deep --strict` 通过，并在已连接 iPhone 16 Pro 上安装和启动 `org.openmuse.ios` 成功。工程 `plutil -lint`、四份 asset JSON/文件引用和 `git diff --check` 均通过。日志：`.build/logs/openmuse-appicon-ios.log`、`.build/logs/openmuse-appicon-macos.log`、`.build/logs/openmuse-appicon-device.log`。
- 边界：手机版本已重装并启动，但尚未用手机界面截图核对主屏幕小尺寸图标；Mac 图标已打包，Dock 的视觉检查未做。

## 2026-10-11：OpenMinis iSH ARM64 构建可行性关卡

- 范围：尝试按固定上游 iSH fork `e6521d9cfe9cd48f19917fc3b23aea622ba358b4` 构建 iOS ARM64 guest，不向 OpenMuse 产品树导入源码或二进制。
- 环境：在忽略的 `.build/upstream/ish-build-venv` 安装 Meson/Ninja，未改全局 Python。首次误用 `iSH+Linux` x86 scheme，暴露缺少 `ld.lld`；改用 `iSH-ARM64-ffmpeg` 后确认 `GUEST_ARCH=arm64`，Meson 成功配置 ARM64 VDSO，但仍因本机没有 ELF linker `ld.lld` 而停止。
- 安全边界：Homebrew 提议安装 LLVM/LLD 并升级全局 xz、证书、readline 和 Python；在任何 formula 安装前已中断，没有全局包变更。没有改 OpenMuse/LICENSE，也没有复制 GPL 代码。
- 结果与下一步：此关证明 ARM64 scheme 可被选择并进入 Meson 配置，尚未证明完整上游 iSH build 或 OpenMuse 集成成功。继续尝试仅放入 `.build` 的 Intel macOS LLD 二进制，再重跑目标构建；许可证与正式集成仍须单独通过门槛。日志：`.build/logs/openmuse-ish-arm64-build.log`、`.build/logs/openmuse-ish-arm64-library-build.log`。

## 2026-10-11：Mac 共享工作区身份修复与 iPhone 首次同步

- 根因与修复：手机此前提示 Mac 未提供共享工作区身份。对照运行包和源码确认 `dist/OpenMuse.app` 落后于已更新的桥接源码；排查中还发现 Mac 服务未响应。重建并重新打开 Mac Debug App 后，本机服务恢复，配对响应提供工作区身份。
- 设备验收：用户在 iPhone 内直接输入一次性配对码，设置页显示“已配对”。iPhone 连接 Mac 的 Tailscale 地址；Mac 本机 `127.0.0.1:4388/health` 与 tailnet `8443/openmuse/health` 当前均返回 HTTP 200。Mac App 通过 `codesign --verify --deep --strict`。
- 同步：首轮发送176条、接收36条后提示仍有批次；再次同步后待发送/接收均为0，附件与构件图片本轮上传/下载均为0。还有18项版本冲突待用户选择，双方版本保留；没有替用户选择冲突版本。
- 回归与构建：配对集成测试现传入非空 `workspaceID` 并断言响应一致；`swift test --filter WorkspacePersistenceTests.testMacBridgePairsForOneUseThenRevokesTheDevice` 通过，1项、0失败，日志 `.build/logs/openmuse-mac-bridge-workspace-identity-test-2026-10-11.log`。Mac Debug 重建日志 `.build/logs/openmuse-mac-2026-10-11-repair-bridge-identity.log`。App 版本号未变，不能把版本号当作此次重建标识。
- 未通过：蜂窝外网、真实 Mac Pi 任务接管、冲突解决、后台/锁屏续跑及真实连接器账号仍未验证。配对与事件同步的成功不等于这些能力通过。

## 2026-10-11：iPhone DeepSeek 真机与旅行计划闭环（配对前记录）

- 范围：继续完成用户授权的 iPhone 安装与真实模型验收，修复旅行计划没有进入资源库的问题，并确认覆盖安装后的数据保留。
- 真机与模型：iPhone 16 Pro / iOS 27.2 上安装并启动 `org.openmuse.ios` 0.1.0 (2)。用户在 App 中保存 DeepSeek 凭证；设置页“保存并测试”真实请求成功，状态显示“连接成功。模型设置已保存在这台设备。”凭证只保存在 Keychain，没有进入日志、代码或仓库。实际模型对话生成恩施七日旅行计划，资源库显示可编辑“旅行计划草稿”且覆盖 7/7 天；旅行目标显示 1/3，首个进度来源为 OpenMuse 保存的计划，活动状态为成功。打开过构件详情与编辑器，没有改动正文。
- 缺陷与修复：第一次真实模型回复没有自动成为资源库构件，真机资源库为空、目标仍为 0/3。原因是“旅行计划”这样的后续请求未关联当前会话唯一的活跃旅行目标。`IntentCapture` 加入旅行计划/路线/行程类上下文指代，并拒绝把明确点名的其他目的地（例如日本）误挂到恩施目标；新增真机流对应的 Core 回归测试。第二轮真实请求保存为 7/7 草案并完成首个目标步骤。检查模型设置时发现成功状态文字被固定底栏遮住；将其移至底栏上方，并在最终签名安装版重新运行真实连接测试，现可直接看见成功提示。
- 持久性：在最终版覆盖安装后，目标页仍显示 1/3 与七日计划；侧栏历史中仍有旅行会话。初次启动聊天停在错误滚动位置，看起来空白；手势滚回消息后，七日正文与 7/7 构件卡正常显示。这次确认是视口位置问题，不是消息丢失。只为诊断短暂复制了设备 SQLite 文件，核对到 1 个旅行会话和 13 条消息后立即删除副本及临时 WAL/SHM 文件。
- 构建与检查：iOS 真机 Debug 签名构建成功、`codesign --verify --deep --strict` 通过、`devicectl` 安装并由 PUA 启动验证；Mac Debug 构建成功。日志：`.build/logs/openmuse-iphone-2026-10-11-visible-model-status.log`、`.build/logs/openmuse-iphone-2026-10-11-visible-model-status-install.log`、`.build/logs/openmuse-mac-2026-10-11-visible-model-status.log`。私有截图索引：`.research-local/openmuse-device/2026-10-11/INDEX.md`；截图目录受 Git 忽略。
- 自动化：新增的旅行后续关联回归通过。早先一轮 137 项全量回归中 Pi 取消子进程测试偶发“子进程未启动”；该项独立重跑 1/1 通过，最终 UI 修复后的全量 `swift test` 为 137 项执行、2 项条件跳过、0 失败。跳过项分别需要实时 Tailscale 地址与本地 Pi RPC 端点。最终日志 `.build/logs/openmuse-2026-10-11-full-tests-after-status-fix.log`。
- Tailscale 网络切片：iPhone Tailscale 从未连接切换为已连接，同一 tailnet 的 Mac 显示在线；Safari 通过 HTTPS 打开 Mac 专用 `8443 /openmuse/health`，收到 HTTP 200 和 `OpenMuse Mac` 响应。Mac 既有443/Funnel路由未改动。手机界面已填入 Mac 地址；App 一次性配对、共享资料同步、Pi 接管以及蜂窝外网路径仍未通过。一次性配对码只由用户直接输入 iPhone，没有写进聊天、代码或日志。
- 边界：尚未验证 Tailscale 蜂窝跨网、iPhone 到家中 Mac 的真实 Pi 接管、锁屏/后台续跑、QQ/Notion 真实账号或 14 天连续自用。旅行里的交通、票价、开放时间等仍标为待核实，没有实时查证或预订。

## 2026-10-10：方案与证据基线

- 范围：公开调研、产品/数据/技术草案、Muse真机交互观察、截图归档与使用方法。
- 已交付：旅行旁聊、目标进度、两版交互构件、任务头像与执行详情观察；文档提交4bcc1d2。
- 检查：上一轮104张本地截图SHA-256、变更文档链接/围栏、Git差异和远端提交核对通过。
- 未完成：应用代码、构建、双端连接、后台、同步、模型与连接器设备验收；原版精确动画参数也未测量。
- 本轮追加：设计原则、讨论索引、开工复查、记忆规则及双端文件关系。文档检查结果在本轮交付时登记。

后续每轮按日期追加，包含需求ID、决定ID、变更、检查、结果、未决项和证据；不得将源码检查写成真机通过。

本轮检查：新增/修改Markdown链接与围栏核对、git diff --check通过；无应用代码，未运行构建或设备验收。公开提交与远端核对在本轮完成。

## 2026-10-10：文档完整性复查

检查需求覆盖、当前与历史状态一致性、实施缺口；修正QQ、记忆预览、五入口与旅行实测状态。产物见DOCUMENT_REVIEW_2026-10-10，未修改应用代码。变更文档引用、围栏和Git差异检查见本轮交付。

本轮验证结果：变更Markdown本地引用与围栏检查、git diff --check通过。未做应用构建或设备验证。

## 2026-10-10：六类方案缺口补齐

- 范围：D27–D30；Tailscale协议、本地同步/检查点、构件版本与隔离、主动/成本/遗忘规则、10图实看页面规格、K01–K16任务及验收。
- 证据：本地Lody只读源码与哈希manifest，公开仅脱敏归纳；10张已归档Muse图片实际打开。
- 未做：应用代码、构建/安装、Tailscale或Lody服务变更、后台/耗电或连接器运行测试。
- 新默认值为制定方案而非用户逐项批准；实施证据不得由文档检查替代。

本轮检查通过：变更Markdown本地引用/围栏、git diff --check、104张原图SHA-256、10张页面图引用存在、K01–K16编号完整、研究原件未跟踪。仅为文档和证据检查，非应用验收。

## 2026-10-10：首个双端应用切片

- 范围：D31、K01–K05 首轮骨架；SwiftUI 双端界面、SQLite 结构化记录、SOUL/USER/GLOBAL/HEARTBEAT 等 Markdown 修订、模型设置/钥匙串、旅行目标与构件、活动状态、Pi RPC 适配。
- 检查：普通 `swift test` 6 项通过、0 失败；按设计跳过 1 项需要本地 Pi 夹具的集成测试。随后用合成 SSE 服务运行该 Pi RPC 集成测试，1 项通过。测试覆盖本地重开与修订、结构化目标、未来数据库版本保护、URL 安全校验、按服务端点区分密钥、OpenAI 兼容请求/响应与 Pi RPC 生命周期。没有访问真实模型。Mac Debug、iOS Simulator 和 iOS arm64 未签名构建均通过；Mac App 复制到 `dist/OpenMuse.app` 后启动，iPhone 17 Pro 模拟器重装并启动成功，首屏截图见 `.build/logs/ios-simulator-final.png`。
- 未完成：用户尚未在 Xcode 登录 Apple Account，iPhone 真机安装暂阻塞；真实 API 密钥/端点未设置，未完成真实模型聊天；Pi 工具关闭，Mac 本地电脑操作未实现；Tailscale 配对/同步、手机离线推理、小环境、后台恢复、连接器、动态、点子、dreaming 未实现。
- 临时方案：先以本机 SQLite/Markdown 保证离线可读；密钥按服务端点分别存钥匙串；可编辑记忆作为单独用户级参考数据传入模型，不提升为系统指令。Mac 本地工具待权限范围与隔离完成再开放。
- 证据：`.build/logs/swift-test.log`、`pi-rpc-integration.log`、`macos-build.log`、`ios-simulator-build.log`、`ios-device-unsigned-build.log` 与 `ios-simulator-final.png`（本地忽略）；`dist/OpenMuse.app/` 是本机 Intel Mac 可打开的 adhoc 签名 Debug 包（本地忽略，不提交二进制）。真机签名失败日志保留在 `.build/ios-signed-build.log`。私人 Muse 原图仍仅位于 `.research-local/`，未复制到应用或公开文件。

## 2026-10-10：双端体验切片与 Mac 私有桥接

- 范围：K01–K06 纵向切片；Mac/iPhone 聊天桥接、一次性设备配对、Tailscale Serve 独立入口、撤销、旅行目标延续、旅行构件编辑/版本历史。
- 行为验证：`swift test` 11项通过、0失败；2项按条件跳过（实时 tailnet 地址、Pi 合成 RPC 环境变量）。新增旅行会话测试覆盖“日期未定先轻松追问→下一句不重复旅行关键词仍延续目标→生成路线后存入资源库→用户修改形成新版本”。测试发现并修复了同一对话后续消息未关联已有目标的断点。Pi 合成 RPC 集成此前通过；当前没有真实模型凭证，本轮没有真实供应商聊天。
- 构建：Mac Debug、iOS Simulator、iOS arm64 未签名构建均通过。iPhone 17 Pro 模拟器安装并启动；欢迎页截图为 `.build/logs/ios-simulator-final-rerun.png`，可见旅行入口、模型设置提醒与五个主导航。该截图只证明首页启动，不证明完成 UI 旅行交互。
- Mac 交付：`dist/OpenMuse.app/` 已更新至 0.1.0 (build 2)，x86_64、ad-hoc 签名，本机 `codesign --verify --deep --strict` 通过；App 正在运行。本机服务仅监听 `127.0.0.1:4388`，`/health` 返回 `OpenMuse Mac`。该包为当前 Mac 可直接打开的 Debug 版本，不是公证发布包。
- 连接实测：本机 `curl`、显式绕过代理的 `curl`、强制解析到 tailnet IP 的 `curl` 均对 Tailscale HTTPS 8443 返回200，证书校验结果为0；既有443路由/Funnel保持原状态，OpenMuse 使用独立8443 `/openmuse` Serve。OpenMuse `URLSession` 到同一 `.ts.net` 地址报告 SecureTransport `-9816`；Apple 对应码为服务端关闭会话但未发送通知，不足以判定证书校验失败，具体差异未定位。iPhone 配对与跨网络连接尚未验收；当前手机 Tailscale 节点离线，未进行 iPhone 真机测试。启用路由前现增加“无法读取现有 Serve 配置即拒绝更改”的保护。
- 真机限制：iOS arm64 仅无签名构建成功。Xcode 尚无 Apple Account/开发描述文件，且设备未处于可测试状态；没有把模拟器说成真机安装。用户需要登录 Xcode 的 Apple Account（免费 Personal Team）并解锁/连接 iPhone 后，才能继续签名安装和真实链路测试。
- 未完成：真实 OpenAI/DeepSeek/自定义服务聊天；Pi 电脑文件/浏览器工具；同步与冲突合并；离线小环境、后台恢复；动态、点子、dreaming、QQ/Notion/Obsidian/邮箱连接器；iPhone 真机 UI/耗电验收。Tailscale 桥接目前只代理模型回合，不传输目标、消息历史、记忆或构件。
- 证据：忽略的本地日志 `.build/logs/swift-test-final-rerun.log`、`macos-final-rerun.log`、`ios-simulator-final-rerun.log`、`ios-device-final-rerun.log`、模拟器截图 `ios-simulator-final-rerun.png`；Mac 可运行包 `dist/OpenMuse.app/`。真机签名失败旧日志 `.build/ios-signed-build.log`。所有 Muse 私人截图仍留在被 Git 忽略的 `.research-local/`。
- 下一步：先用在线 iPhone 验证实际 DNS/HTTPS/配对，再针对 Mac `URLSession` 的会话关闭错误定位客户端差异；由用户在 App 设置中直接录入自己的模型凭证后验收真实聊天。之后继续 K07 同步/检查点和 Mac 工具授权，不改变完整一期目标。

## 2026-10-10：Muse 前端交互对齐复查

- 范围：按用户 code review 后续要求，优先落实 iPhone 导航、聊天、头像/活动、目标、动态/点子、资源库与构件页面；关联 D31、K08–K10、K12、K14。实际对照本地 Muse 聊天与空闲头像截图，原图只留在 `.research-local/`。
- 变更：新增滑出侧栏、五入口图标导航、聊天/旁聊分组搜索、每段对话独立草稿及父对话上下文；头像进入活动/批准/桌面端/近期/身份面板；聊天追新按钮、停止回复和居中欢迎卡；目标步骤展开/勾选/完成/关闭；活动写入真实本地处理阶段并展示步骤时间线；动态指令可编辑、无内容时明确说明数据来源尚未接入；点子由未完成目标生成，接受后创建关联目标的旁聊；构件支持独立预览、编辑、版本历史和恢复旧版。
- 兼容性：新增的旁聊父 ID 和活动步骤字段都是可选字段；新增回归测试验证旧数据库 JSON 记录仍可解码。旅行测试验证四个活动步骤与资源库保存状态。
- 检查：`swift test` 13 项通过、0 失败、2 项按条件跳过（实时 Tailscale 地址与本地 Pi RPC 服务）；iOS Simulator 与 Mac Debug `xcodebuild` 均通过；iPhone 17 Pro 模拟器重装并启动成功。首屏截图 `.build/logs/muse-parity-ios-final.png`（本机忽略文件）已实际查看；`git diff --check` 通过。
- 未完成：没有在本轮执行模拟器逐页点击/VoiceOver 测试或安装真机；没有真实模型聊天。附件/语音、动态真实内容与反馈、个性化点子反馈、待审批与计划任务、Pi 工具、浏览器控制、真实同步、后台恢复、iCloud、耗电测试均未完成。头像为原创占位表情及工作状态光圈，不是 Muse 素材或动画曲线复刻；当前画面和信息结构是首轮接近实现，完整 V1 仍逐项按 PHASE1_PARITY 验收。
- 证据边界：模拟器截图证明新版首屏可启动，不证明导航点击、双端互通或真机体验。具体未完功能和首轮实现映射见 [UI_SPEC](UI_SPEC.md) 与 [Muse交互研究](muse-research/IOS_INTERACTIONS_2026-10-10.md)。

## 2026-10-10：顶部与底栏像素对照修正

- 需求：移除 iPhone 顶部“OpenMuse”下方的固定陪伴标语，放大头像，并按 Muse 截图调整底部导航样式。
- 变更：头像由38pt增至64pt（约占模拟器屏宽16%）；名称改为贴近头像下缘的半透明胶囊；左右圆按钮上移到接近头像上缘；iOS 顶部不再显示状态副文案。导航改用线框聊天、书页、灯泡、勾选框和资源网格；未选中图标提高亮度，选中项改为较暗胶囊，底色和外描边置于图标之后。
- 检查：iOS 17模拟器与Mac Debug构建成功；iPhone 17 Pro模拟器重新安装并启动成功；启动截图`.build/logs/muse-parity-ios-final.png`已实际查看；`git diff --check`通过。第一次截图在界面渲染前抓取为白屏，等待两秒后重抓确认正常。
- 未做：未做真机截图、逐个导航点击、不同屏幕尺寸/辅助功能测试；头像仍为OpenMuse原创表情，导航符号为系统SF Symbols。截图缩放比例未知，按相对占屏比例复刻视觉层级，不声称Muse原始点数完全相同。
- 证据：Muse源图仍仅保存在被忽略的`.research-local/`目录；最终OpenMuse模拟器截图保存在`.build/logs/`，均未加入提交。

## 2026-10-10：DeepSeek 实际模型与旅行闭环

- 范围：K03、K05；验证 DeepSeek 凭证保存、OpenAI 兼容直连、Mac Pi 模型回合，以及旅行目标/构件在本机工作区的保存与重开读取。
- 真实服务：DeepSeek `deepseek-chat` 的 OpenAI 兼容直连成功；Mac Pi 1.0.4 的模型设置连通测试成功。模型凭证从本机登录钥匙串读取，配置保存在本机；凭证值未进入源码、版本控制或验证日志。
- 真实产品流程：完成恩施 7 天旅行的两轮模型对话；OpenMuse 先建旅行目标，第二轮生成按天草案并保存旅行构件；两条活动均完成。关闭并重新创建模型后，目标、构件、两条回复与活动记录仍可读取。测试数据留在本机 OpenMuse 工作区，供后续打开应用体验。
- 检查：两次临时真实服务测试均通过；常规 `swift test` 13项通过、0失败、2项按条件跳过（在线 Tailscale 地址与本地 Pi RPC 服务）；`OpenMuseMac` Debug 与 `OpenMuseiOS` Simulator 构建均成功。更新后的 `dist/OpenMuse.app` 通过 `codesign --verify --deep --strict`；iPhone 17 Pro Simulator 已安装并启动新版。
- 未验证：当前 PUA 无法连接 iPhone，Xcode 也找不到该真机；因此没有验证真机 UI、iPhone 钥匙串或 iOS 内的真实点击聊天。Mac 界面没有完成逐项 UI 点击验收。OpenAI 真实供应商切换、模型流式/取消/usage、Tailscale 跨网和 Mac 文件/浏览器执行仍未完成。
- 证据：本轮工具输出记录实时请求与构建结果；产品本机包为 `dist/OpenMuse.app/`，模拟器包为 `.build/derived-ios/Build/Products/Debug-iphonesimulator/OpenMuse.app/`。本次旅行对话使用真实模型并写入本机工作区，未将回复内容或密钥复制进公共文档。

## 2026-10-10：完整验收回合与 Tailscale 客户端修复

- 范围：复测现有实现、补上 iOS 模拟器界面自动化、验证 Pi RPC 与真实 Tailscale Serve 健康检查，并修复 Mac/iOS 共用的桥接客户端代理配置。
- 缺陷与修复：最初通过 Mac 的 `URLSession` 访问本机 Tailscale HTTPS Serve 路由失败（CFNetwork 310 / SecureTransport -9816）；同一地址的 `curl` 直连返回 HTTP 200。对比系统代理配置、空代理字典和显式关闭代理标志后，只有空代理字典成功。`MacBridgeClient` 现用空字典建立直连；同一路由的真实 `URLSession` 检查随后通过。
- 自动化：`swift test` 在本机合成 SSE 服务和 Mac 当前 Tailscale Serve 路由均启用时，17 项通过、0 失败、0 跳过。新增用例覆盖钥匙串限定写入/删除、目标步骤与状态重开、构件恢复生成新版本、明确记忆保存而提问不记为事实、模型失败保留请求并标记活动失败。iPhone 17 Pro / iOS 26.5 模拟器的 2 项 UI 测试通过，覆盖五个主入口、陪伴者五个面板、身份文件列表、侧栏搜索和模型设置表单。
- 构建：修改后的 Mac Debug 构建成功；iOS 模拟器 UI 测试构建、安装并启动成功。`git diff --check` 通过。证据日志和 xcresult 保存在本机忽略的 `.build/logs/`。
- 边界：Tailscale 检查是这台 Mac 访问自己的私有 Serve 路由，不是手机到家中 Mac 的跨设备验收。重新检查时 PUA READY 不可达；一次启动尝试因 Xcode 找不到配置的真机目的地而失败，没有执行任何手机动作。因此本轮没有真机安装、真机 UI、iPhone 钥匙串或蜂窝连接测试。此前记录的真实 DeepSeek 两轮恩施旅行闭环仍有效，但本轮没有重复消耗模型 API。
- 未实现/未验收：Mac 文件/浏览器工具、远程桌面、双端资料同步与任务接管、iOS 离线推理和可靠后台任务、计划任务与 dreaming、真实动态来源/反馈、邮箱/Notion/Obsidian 连接器、iCloud、OpenAI 真实供应商切换、模型流式/取消/usage，以及完整一期多日自用观察。具体范围继续按 K01–K16 和 PHASE1_PARITY，不将已通过的旅行闭环扩大解释为全产品通过。

## 2026-10-10：目标暂停、恢复、多目标与修订历史

- 范围：按需求审计继续补 K09 / G1–G2；补齐目标暂停/恢复入口、多目标并行、重复目标去重，以及目标/步骤变化的可追溯修订。
- 变更：目标页分开显示追踪中、已暂停与已完成/已关闭；目标菜单可暂停、恢复、完成、关闭或重新追踪。明确提出不同目标时新建并保留来源，重复提出同标题目标不重复建档；暂停目标不会因聊天内容自动恢复；明确重新提出已完成/关闭目标才重新追踪。目标初始状态、步骤变化和状态变化均写入 SQLite 修订与 outbox。目标标题取用户陈述的首个子句，减少把附加说明并入标题。
- 验证：`swift test` 执行 22 项，20 项通过、2 项条件跳过、0 失败。两个跳过项分别需要配置实时 Tailscale 地址和 Pi RPC 端点。iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 3 项通过。Mac Debug 构建成功。日志和结果包位于本机忽略的 `.build/logs/ios-goal-ui-tests.log`、`.build/logs/OpenMuse-Goals-iOS-2026-10-10.xcresult`、`.build/logs/mac-goal-revision-build.log`；Core 测试终端结果为本轮工具记录。
- 边界：未做 iPhone 真机、目标页 UI 点击/VoiceOver、用户真实模型对话或多日主动跟进测试。意图候选及后续关联仍为保守中文规则；进展事件幂等、提醒、等待设备和自然语言纠正仍未实现。iCloud 按用户决定后接；真机仍按用户此前“稍后再测”保持未验证。
- 文档：更新 [需求审计](REQUIREMENT_AUDIT_2026-10-10.md)、[实施计划](IMPLEMENTATION_PLAN.md)、[UI_SPEC](UI_SPEC.md)、[PHASE1_PARITY](PHASE1_PARITY.md) 与 [MEMORY_STORAGE](MEMORY_STORAGE.md)，不改变完整一期范围。

## 2026-10-10：动态来源、流式回复与迁移/记忆修复

- 范围：按逐条需求审计继续补动态来源和模型体验，并修复导入记忆在编辑/撤销后被 USER.md 投影破坏的问题。
- 变更：Feed 支持用户添加/停用 RSS、Atom HTTPS 来源；解析标题、摘要、文章链接、发布时间和安全的 HTTPS 配图地址。配图默认关闭，用户开启后才连接图片托管服务。排序显示关键词匹配理由，支持稍后、不感兴趣、带来源开旁聊。OpenAI-compatible 直连有流式文本、取消传播和供应商 usage 解析，真实 token 记录可在设置查看；无价格表时不推算费用。记忆投影只在用户明确保存 USER.md 时解析人工修改；结构化更新重建视图不再反写旧标注。
- 缺陷与修复：改动导入记忆来源类型后，旧 Markdown 行可能被错当成手工修改，来源标注被写进记忆正文；修正为手工编辑仅从文档保存入口进入协调流程。回归覆盖导入编辑、批次撤销并保留用户修改。
- 验证：`swift test` 37 项，35 通过、2 项因缺少实时 Pi/Tailscale 端点条件跳过、0 失败。iOS 模拟器 UI 自动化 3 项通过；Mac Debug、iOS Simulator Debug 构建通过。日志：`.build/logs/swift-requirements-coverage-final-2026-10-10.log`、`.build/logs/ios-requirements-ui-tests-final.log`、`.build/logs/mac-requirements-coverage-final.log`、`.build/logs/ios-requirements-coverage-final.log`；UI 结果：`.build/logs/OpenMuse-Requirement-Coverage-Final-2026-10-10.xcresult`。
- 边界：未访问真实 RSS 站点，未重新调用模型供应商；fixtures 只能验证解析/请求格式。Mac/Pi 路径目前不展示流式更新和 token usage。真机、蜂窝跨网、锁屏后台按用户指示稍后验收。
- 需求矩阵现已区分已实现切片与剩余缺口；附件/删除同步、owner/epoch/checkpoint、主动计划/dreaming、真实连接器、旅行构件沙箱/附件、OpenAI 真实切换、真机/后台与像素级验收仍未完成。

## 2026-10-10：模型 usage 兼容回退与核心文件读取预算

- 模型：经核对 OpenAI 与 DeepSeek 的官方 Chat Completions 文档后，流式请求显式请求 usage；仅当兼容端点以 400/422 明确拒绝 `stream_options` 时，重试一次不带可选 usage 字段的流式请求。对一般认证、模型或服务错误不重试。停止生成现由真实 AppModel 回归覆盖：活动转为取消，未完成的流式片段不会保存成正式回复。
- 读取：每轮按模型配置窗口的四分之一（最多12,000估算token）分层读取七份核心文件；预算超限时明确告知模型哪些文件被截取/未载入。token数是通用估值；最近聊天和旁聊未并入同一总预算，当前也没有按问题做相关来源检索。
- 验证：新增模型拒绝 usage 字段后的单次回退测试、AppModel 流式取消测试及超长 USER.md 的预算/截断提示测试。完整 Core 测试结果在上一条动态实现记录中更新，最终准确数以最新覆盖审计和本轮日志为准。
- 官方接口依据：[OpenAI Chat Completions](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)；[DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)。

## 2026-10-10：逐条需求覆盖审计

- 范围：用户要求对照需求确认每个点并检查漏项；审查 PRD 全部章节和各专项规格，抽查当前 Swift 实现、Core 测试、iOS UI 测试与已有真实模型记录。
- 文档变更：新增 REQUIREMENT_AUDIT_2026-10-10，列出每个 PRD 范围及 MEMORY_STORAGE、ARTIFACTS、POLICIES、RUNTIME_PROTOCOL、设备/文件、后台、迁移、旅行引导和 UI 的验收状态；PRD/PHASE1_PARITY 加 CN1 中国境内直接使用验收；UI_SPEC 将同设备截图叠加/差异比较纳入像素级验收；修正 D31 授权后仍称未授权的状态文字；DISCUSSIONS 增加 T18。
- 结论：确认的一期能力没有被删除，但大量能力尚未实现；明确记忆、连接器、动态、dreaming、双端同步/接管、远程桌面、构件沙箱、费用/通知/遗忘和像素级 UI 仍有缺口。用户已选择实体手机测试“稍后再测”，真机、蜂窝和后台结果继续标为未验证。
- 检查：本轮为文档审计，没有改应用代码；Markdown 链接/格式和 git diff --check 通过后记录。未重跑应用构建与功能测试；沿用最新已记录的 17 项 Core、2 项模拟器 UI 与 Mac Debug 构建结果，不把文档检查当成产品验收。

## 2026-10-10：目标本机提醒与到期回访

- 范围：继续覆盖 G1/G2、V1h、K09/K11 里“目标约定时间后回来继续”的可落地切片。
- 变更：进行中目标可设置本机一次性系统提醒；“近期”列出提醒并支持暂停、恢复、取消。提醒数据带目标、设备 owner、时区、状态及 `show-on-next-open` 漏跑策略，并进入既有设备同步 outbox。到期后只预填目标对话，由用户决定发送；不在锁屏时调用模型。通知权限拒绝或系统登记失败时，保留到期记录，打开 App 后补显。
- 检查：Core 测试新增 2 项，覆盖本地保存/同步事件、暂停/恢复/取消以及过期计划只产生草稿、不运行模型；全套 `swift test` 执行 42 项，40 项通过、2 项条件跳过、0 失败。iOS UI 自动化 3 项通过，覆盖近期提醒空状态；Mac Debug 构建和 iOS 模拟器 UI 构建/启动通过。最新记录见下方“文本构件 Markdown/JSON 导出”。
- 边界：系统可能拒绝或延后通知；当前没有自动跟进推理、周期任务、安静时段、后台补跑或 dreaming。iOS 通知权限、锁屏送达与真机恢复仍待验收，真机按用户“稍后再测”保持待测。用户可自设提醒不同于主动工作策略已经验收。

## 2026-10-10：文本构件 Markdown/JSON 导出

- 范围：补 K10、§14、ARTIFACTS 中单个旅行成果的便携导出。
- 变更：构件操作菜单可将当前文本版本通过系统文件导出器保存为 Markdown 或 JSON；JSON 包含当前 ArtifactRecord（标题、关联对话/目标、版本号和正文）。原有系统分享入口保留。
- 检查：Mac Debug 构建通过；iOS 模拟器 UI 自动化 3 项通过，Core 42 项执行、40 项通过、2 项条件跳过、0 失败。日志：`.build/logs/coverage-follow-up-mac-build.log`、`.build/logs/coverage-follow-up-ios-ui.log`、`.build/logs/coverage-follow-up-swift-test.log`；xcresult：`.build/derived-ios-coverage-followup/Logs/Test/Test-OpenMuseiOS-2026.10.10_13-22-57-+0800.xcresult`。
- 边界：尚未在系统文件选择器中实际保存并重开 Markdown/JSON 文件，也没有网页构件 ZIP、PDF、附件、批量导出或删除。导出路径已通过构建，外部文件交付验收仍待补。

## 2026-10-10：ChatGPT 对话 JSON 手动迁移

- 范围：推进 K13/C1–C2 的聊天迁移入口，先覆盖用户直接提供的 ChatGPT `conversations.json`；ZIP 解包与连接器仍单独排期。
- 变更：从“身份与记忆”选择 JSON 文件，按 ChatGPT 当前消息分支整理用户/助手文本，过滤工具消息并提供会话及消息预览。用户可按会话选择导入；对话和每条消息保留来源名称与原始 ID，按来源会话 ID 去重。导入内容只进入历史对话，不写入 USER.md、不调用模型。设置 50 MB 文件、10,000 个会话、200,000 条消息上限。
- 验证：新增 Core 测试覆盖当前分支解析、非文本工具消息过滤、来源持久化、重复导入去重及无记忆写入。`swift test` 执行 44 项，42 通过、2 项因本机无 Pi/Tailscale 测试端点而条件跳过、0 失败；iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 3 项通过；Mac Debug 构建成功。日志：`.build/logs/chat-import-swift-test.log`、`.build/logs/chat-import-ios-ui.log`、`.build/logs/chat-import-mac-build.log`；结果包：`.build/derived-ios-chat-import/Logs/Test/Test-OpenMuseiOS-2026.10.10_13-30-56-+0800.xcresult`。
- 边界：目前只接受 JSON 文件，不读 ZIP 容器；没有真实用户导出文件验收，没有迁移时语义冲突检测，也没有 QQ 邮箱、Notion、Obsidian 或 Gmail 连接器。模拟器测试不证明真机文件选择体验。
- 文档：同步更新需求审计、一期验收矩阵、实施计划与迁移说明；剩余连接器和 ZIP 要求继续保留。

## 2026-10-10：ChatGPT 导出 ZIP 安全读取

- 范围：补上上一轮明确登记的 ChatGPT 聊天 ZIP 缺口，只读取档案中的 `conversations.json`，不解压附件或其他条目。
- 实现：以锁定版本 ZIPFoundation 0.9.20 流式读取目标条目；目标 JSON 最大 50 MB，档案最多枚举 100,000 个条目；遇到多个同名 JSON 拒绝导入。未将任意档案路径写入文件系统。添加 MIT 许可证声明与 `Package.resolved` 锁定版本。
- 验证：Core 全套 45 项执行、43 项通过、2 项条件跳过、0 失败；新增 ZIP fixture 测试验证子目录中的 `conversations.json` 可导入，另一个 `../../outside.txt` 项不被解压。Mac Debug 构建通过；iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 3 项通过。日志：`.build/logs/chat-zip-swift-test.log`、`.build/logs/chat-zip-mac-build.log`、`.build/logs/chat-zip-ios-ui.log`；xcresult：`.build/derived-ios-chat-zip/Logs/Test/Test-OpenMuseiOS-2026.10.10_13-39-35-+0800.xcresult`。
- 边界：只测试了合成 ZIP，不含用户真实导出包和大档案压力测试；Claude/Gemini、QQ 邮箱、Notion、Obsidian、Gmail 连接器及记忆语义冲突仍未实现。真机文件选择按用户要求稍后测试。
- 需求：同步更新 [审计](REQUIREMENT_AUDIT_2026-10-10.md)、[一期验收矩阵](PHASE1_PARITY.md)、[实施计划](IMPLEMENTATION_PLAN.md) 与[迁移说明](MEMORY_TRANSFER.md)。

## 2026-10-10：动态反馈排序与撤销隐藏点子

- 范围：补 F1/I1 的反馈有后续影响、用户可修正选择的基本闭环。
- 变更：继续讨论的动态主题会为关键词相似内容加权；不感兴趣主题会减权，直接被标记的文章仍从主列表隐藏。身份页的“已隐藏动态”折叠区可恢复文章。点子页的“不合适”项目进入“已跳过的点子”，可撤销跳过并放回稍后列表。分值和解释来自本地关键词规则，不调用模型。
- 验证：Core 新增跨重开验证，确认正向/负向主题反馈影响排序且恢复负反馈后排序还原；覆盖与旧反馈数据兼容。全套 `swift test` 执行 46 项、44 通过、2 项需真实 Pi/Tailscale 端点而条件跳过、0 失败。Mac Debug 构建成功，iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 3 项通过。`git diff --check` 通过。日志：`.build/logs/coverage-latest-swift-test.log`、`.build/logs/coverage-latest-mac-build.log`、`.build/logs/coverage-latest-ios-ui.log`；结果包：`.build/derived-ios-coverage-latest/Logs/Test/Test-OpenMuseiOS-2026.10.10_13-49-07-+0800.xcresult`。
- 边界：尚无基于含义的个性化、用户兴趣画像学习、多源点子或真实 RSS 刷新验收；模拟器 UI 自动化没有单独点击隐藏区和点子恢复区，后续需补实际界面验收。
- 需求：更新[覆盖审计](REQUIREMENT_AUDIT_2026-10-10.md)、[一期验收](PHASE1_PARITY.md)与[实施计划](IMPLEMENTATION_PLAN.md)，明确这只是可解释反馈切片。

## 2026-10-10：任务接管状态基础与旅行构件校验

- 范围：推进 K07/E1 的任务 owner、epoch、checkpoint、显式交接与离线分支协议；修复旅行计划回复误触发构件及缺少来源/覆盖状态的问题。
- 变更：新增独立的 `TaskExecutionRecord` 和 `TaskCheckpointRecord`，保存任务约束版本、能力、状态、设备所有者、运行代数、幂等步骤键和结果引用。领取/恢复使用 expectedEpoch 比较交换；检查点与恢复指针在一个 SQLite 事务提交；确认交接要求最新检查点并推进 epoch；失联续跑创建独立候选分支，不假设原设备已停。记录进入现有同步 outbox，并随包含聊天的迁移包导出。旅行构件要求至少两个不同日程标题，“第1天”与“Day 1”去重；识别用户要求的行程天数，记录已覆盖天数、消息来源和显式假设，未覆盖全程不会完成目标步骤。旧构件字段缺省解码保持兼容。
- 验证：`swift test` 执行 55 项，53 通过、2 项条件跳过、0 失败；跳过项需要实时 Pi RPC 与 Tailscale 地址。测试覆盖任务领取、epoch 拒绝、检查点幂等/冲突、双端事件同步、工作区迁移、确认交接、失联分支和旅行构件边界。Mac Debug 构建通过，日志 `.build/final-mac-build.log`；iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 3 项通过，结果包 `.build/derived-final-ios-ui/Logs/Test/Test-OpenMuseiOS-2026.10.10_14-30-06-+0800.xcresult`；日志 `.build/final-ios-ui.log`。Core 日志 `.build/final-swift-test.log`。
- 限制：任务数据模型还没有接入聊天发送、Pi 调用/工具步骤、心跳、活动界面、远程取消或副作用幂等。各设备离线时没有全局原子锁；失联分支的结果比较/选择尚未实现，因此还不能称为完整双端任务接管。旅行标题结构检查不验证外部事实、价格、天气、交通或预订。模拟器 UI 自动化未新增任务/构件细节的界面点击；真机和蜂窝验收依用户“稍后再测”保持未做。
- 文档：更新 [RUNTIME_PROTOCOL](RUNTIME_PROTOCOL.md)、[ARTIFACTS](ARTIFACTS.md)、[需求审计](REQUIREMENT_AUDIT_2026-10-10.md)、[一期矩阵](PHASE1_PARITY.md)、[实施计划](IMPLEMENTATION_PLAN.md) 与 README。

## 2026-10-10：旅行构件进度可见性

- 范围：根据本地 Muse 资源列表、构件菜单和旅行构件页面截图，让已实现的草稿校验状态在产品界面里可持续查看；截图只留在 `.research-local/muse-ui/`，未复制或公开私人原图。
- 变更：资源卡显示版本与行程覆盖进度；构件页显示已覆盖/计划天数、来源消息数量和待确认假设。已逐张查看 Muse 资源库列表、菜单和打开的旅行构件页面截图后实施。
- 验证：Mac Debug 构建通过，日志 `.build/final-mac-build.log`；iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 3 项通过，结果包 `.build/derived-final-ios-ui/Logs/Test/Test-OpenMuseiOS-2026.10.10_14-38-50-+0800.xcresult`，日志 `.build/final-ios-ui.log`。自动化没有直接点击构件条目并断言进度字段；真实 iPhone 未测。
- 边界：只补状态可见性，不代表完整还原 Muse 交互或通过像素差异验收；旅行事实核验、动态网页构件、附件/PDF、资源库逐项 UI 操作仍有缺口。

## 2026-10-10：聊天执行状态接入任务检查点

- 范围：继续推进 E1/K07，让 execution-task/checkpoint 从协议原语进入真实应用的模型聊天生命周期，并让活动详情展示已有状态。
- 变更：每轮聊天以活动 ID 建立协调任务记录，记录本机协调 owner、目标约束修订与所需模型能力；读取相关资料和保存回复后分别提交检查点，成功后等待用户继续，失败和取消写终态。启动恢复只暂停本机 owner 的遗留运行，不误停配对设备的任务。活动详情显示执行状态、已保存检查点数和最近保存位置。这里的协调 owner 不代表 Mac 已执行 Pi 工具。
- 验证：`swift test` 执行 57 项、55 通过、2 项条件跳过、0 失败；新增本机/远端 owner 重启边界与真实 AppModel 成功、失败、取消、跨重开状态检查。Core 日志 `.build/task-runtime-integration-swift-test.log`。Mac Debug 构建通过，日志 `.build/task-runtime-mac-build.log`；iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 3 项通过，结果包 `.build/derived-task-runtime-ios/Logs/Test/Test-OpenMuseiOS-2026.10.10_14-52-37-+0800.xcresult`，日志 `.build/task-runtime-ios-ui.log`。
- 边界：没有把任务检查点连到 Pi RPC 工具步骤、重放/实际续跑、Mac owner 交接、心跳、远程取消或副作用控制；活动详情没有专门 UI 自动化断言。真机/蜂窝和后台仍按用户“稍后再测”暂缓。
- 文档：更新 [RUNTIME_PROTOCOL](RUNTIME_PROTOCOL.md)、[需求审计](REQUIREMENT_AUDIT_2026-10-10.md)、[一期矩阵](PHASE1_PARITY.md)、[UI_SPEC](UI_SPEC.md)、[实施计划](IMPLEMENTATION_PLAN.md) 与 README。

## 2026-10-10：未接入工具的能力提示

- 范围：落实 §12/K05 的真实能力边界，避免当前仅调用模型时把规划说成已打开浏览器、检索网页、发邮件、预订或修改 Mac 文件。
- 变更：主聊天系统提示明确列出目前不可用的网页搜索、邮件、Notion、Obsidian、预订、Mac 文件和浏览器工具；配对 Mac 只代理模型推理，不代表 Pi 已操作电脑。要求模型没有明确工具结果时不声称执行完成，并在能力不足时说明限制。
- 验证：新增提示内容回归，确认发送请求时系统提示包括上述具体边界；`swift test` 执行 58 项、56 通过、2 项条件跳过、0 失败，日志 `.build/capability-boundary-swift-test.log`。Mac Debug 构建通过，日志 `.build/capability-boundary-mac-build.log`；iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 3 项通过，结果包 `.build/derived-capability-ios/Logs/Test/Test-OpenMuseiOS-2026.10.10_15-01-09-+0800.xcresult`，日志 `.build/capability-boundary-ios-ui.log`。
- 边界：这是提示约束，不是硬性工具权限系统，不能保证所有模型永不违反；真正的工具执行结果、Mac 文件/浏览器工具、审批与审计仍未实现。真机和联网模型体验尚未重测。
- 文档：同步更新 [需求审计](REQUIREMENT_AUDIT_2026-10-10.md)、[一期矩阵](PHASE1_PARITY.md)、[RUNTIME_PROTOCOL](RUNTIME_PROTOCOL.md)、[实施计划](IMPLEMENTATION_PLAN.md) 与 README。

## 2026-10-10：旅行构件详情界面验收

- 范围：补 K10 的界面专项验收，确认旅行构件已显示的覆盖状态、来源数和待确认假设能从资源库实际打开查看。
- 变更：Debug UI 测试可使用独立 UUID 工作区和合成旅行草稿，不读取或改写用户本机工作区；构件入口、覆盖天数、来源数及假设增加稳定的辅助功能标识。记忆迁移页的说明改为区分“AI 记忆快照”与单独导入的 ChatGPT 历史对话，移除已过期的“聊天 ZIP 尚未接入”。
- 验证：`swift test` 执行 58 项、56 项通过、2 项因缺少实时 Pi/Tailscale 端点条件跳过、0 失败，日志 `.build/artifact-detail-swift-test.log`；iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 4 项通过、0 失败，结果包 `.build/derived-artifact-ui2/Logs/Test/OpenMuse-Artifact-UI.xcresult`，日志 `.build/artifact-detail-ios-ui.log`；Mac Debug 构建成功，日志 `.build/artifact-detail-mac-build.log`。
- 边界：自动化使用合成数据，只验证模拟器界面和本轮读取路径，不验证用户真实旅行构件、真机可访问性、Muse 像素差异或外部旅行事实。

## 2026-10-10：目标进展来源与回到对话

- 范围：按 PRD 的目标持续追踪要求，补齐进展事件的来源、幂等保存、同步和界面回溯。
- 变更：明确的步骤/目标完成语句会生成稳定 ID 的 `GoalProgressEventRecord`；重复处理同一来源不会重复记账。结构完整的旅行路线只推进“整理路线”步骤，不能误报整趟旅行完成；部分草稿在唯一活动目标上下文中补齐后更新原构件并记入来源。进展事件和目标修订在同一 SQLite 事务提交，并进入设备同步。目标详情展示进展步骤、时间、来源摘要和“查看对话”入口；多目标指代不明时不自动绑定。
- 验证：`swift test` 执行 61 项，59 项通过、2 项因未配置实时 Pi/Tailscale 端点而条件跳过、0 失败，日志 `.build/goal-progress-swift-test.log`。iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 5 项通过、0 失败，结果包 `.build/goal-progress-ios-ui.xcresult`，日志 `.build/goal-progress-ios-ui.log`。Mac Debug 构建通过，日志 `.build/goal-progress-mac-build.log`；`git diff --check` 通过。
- 边界：中文完成意图仍由有限规则识别；无语义候选预览、跨设备离线并发的全局去重/仲裁、主动跟进和真机验收。真机测试按用户“稍后再测”保持未进行。
- 文档：更新 [PRD](PRD.md)、[需求审计](REQUIREMENT_AUDIT_2026-10-10.md)、[MEMORY_STORAGE](MEMORY_STORAGE.md)、[RUNTIME_PROTOCOL](RUNTIME_PROTOCOL.md)、[UI_SPEC](UI_SPEC.md)、[PHASE1_PARITY](PHASE1_PARITY.md) 与 [IMPLEMENTATION_PLAN](IMPLEMENTATION_PLAN.md)。

## 2026-10-10：SOUL 协作习惯自动修订与撤销

- 范围：落实 D21 已确认的“人格可成长、每次修改告知；使命和权限由用户决定”，让有限的沟通反馈形成可查、可撤销的 SOUL 修订。
- 变更：只识别三类明确反馈：陪伴太严肃/正式、回复太长/啰嗦、澄清问题过多；转换为固定的协作习惯，不让规则推断或改写使命/权限。SOUL 文档、来源消息摘录、理由与修订记录使用同一 SQLite 事务保存并同步。成功回复、模型失败和用户停止时都会告知。身份页列出所有修订和原句，撤销只移除对应 OpenMuse 管理的习惯行；用户手动改写该行时安全拒绝自动撤销。无聊天的迁移包保留 SOUL 当前内容，但不导出修订记录中含的对话摘录。
- 验证：Core `swift test` 执行 63 项，61 项通过、2 项因未设置实时 Pi/Tailscale 端点条件跳过、0 失败，日志 `.build/persona-refinement-final-swift-test.log`。包含范围过滤、来源绑定、跨端同步、用户手写内容保留、连续修订逐条撤销、聊天告知和无聊天档案隐私边界。iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 6 项通过、0 失败，结果 `.build/persona-refinement-final-ios-ui.xcresult`，日志 `.build/persona-refinement-final-ios-ui.log`。Mac Debug 构建通过，日志 `.build/persona-refinement-final-mac-build.log`；`git diff --check` 通过。
- 边界：这是有限规则切片，不是通用 dreaming 或模型自主的人格反思；长时效果、并发设备修改、用户手动改写后的冲突处理和真机体验仍未验收。
- 文档：更新 [DISCUSSIONS](DISCUSSIONS.md)、[需求审计](REQUIREMENT_AUDIT_2026-10-10.md)、[MEMORY_STORAGE](MEMORY_STORAGE.md)、[UI_SPEC](UI_SPEC.md)、[一期对齐清单](PHASE1_PARITY.md) 与 [实施计划](IMPLEMENTATION_PLAN.md)。

## 2026-10-10：Mac Pi 只读工具进入活动记录与检查点

- 范围：继续补 K05、K07、K14；把 Mac 本机 Pi 文件工具的真实运行状态接到本轮活动和任务检查点。
- 变更：Pi RPC 现在只把两个已批准只读工具的开始/完成/失败/取消事件发送给 AppModel。活动详情以“Mac 本机资料”步骤组显示每次调用；工具结束后即提交一个稳定幂等键的检查点。检查点不包含文件正文，也不写文件路径；保存回复时从最新任务序号继续，避免覆盖前面的 Pi 工具检查点。其他工具名的 RPC 事件不会出现在活动记录中。
- 验证：`swift test` 执行 68 项、66 项通过、2 项因缺少实时 Pi/Tailscale 端点条件跳过、0 失败；其中新增 Swift 真实子进程 RPC 解析测试与 AppModel 活动/检查点集成测试通过。Node Pi 1.0.4 RPC/只读路径安全测试 5/5 通过。Mac Debug 构建成功；iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 6/6 通过；`git diff --check` 通过。日志：`.build/logs/openmuse-pi-tool-checkpoints-full.log`、`.build/logs/openmuse-pi-read-node-final.log`、`.build/logs/openmuse-pi-tool-mac-build.log`、`.build/logs/openmuse-pi-tool-ios-ui.log`；UI 结果包 `.build/derived-pi-tools-ios/Logs/Test/Test-OpenMuseiOS-2026.10.10_16-32-02-+0800.xcresult`。
- 未验证：没有通过 macOS 文件选择器真实授权/撤销目录，也没有使用用户真实资料验证；iPhone 委派到 Mac 时的 owner 转移和远端工具事件尚未打通；没有远端取消、写文件审批、浏览器或桌面控制。真机仍按用户“稍后再测”保持未验收。
- 文档：更新 [需求审计](REQUIREMENT_AUDIT_2026-10-10.md)、[运行协议](RUNTIME_PROTOCOL.md)、[策略](POLICIES.md)、[UI 规格](UI_SPEC.md)、[一期对齐](PHASE1_PARITY.md)、[实施计划](IMPLEMENTATION_PLAN.md) 与 README 当前状态。

## 2026-10-10：配对 Mac 的远程任务取消

- 范围：补 K05/K07/E1 中用户停止 iPhone 委派任务时，Mac Pi 子进程仍继续运行的问题。
- 变更：配对请求携带稳定 request ID；iPhone 取消网络请求时，通过独立的认证连接调用 Mac `/v1/cancel`。Mac 根据配对设备身份只允许取消该设备发起的活动请求，取消信号沿异步任务传到 Pi 运行时并终止子进程。取消先于聊天连接抵达时，Mac 保存 30 秒设备范围的取消意图，阻止 Pi 随后启动；并限制活动请求与待处理取消数量。iOS 取消后不会因为桥接返回错误而回退启动本机模型。
- 验证：`swift test` 执行 70 项、68 项通过、2 项因缺少实时 Pi/Tailscale 端点条件跳过、0 失败，日志 `.build/logs/openmuse-remote-cancel-full.log`。新增两个 MacBridge 集成测试覆盖同设备取消、跨配对设备拒绝、取消到达 Pi handler，以及取消先到竞态。Mac Debug 构建通过，日志 `.build/logs/openmuse-remote-cancel-mac-build.log`。iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 6 项通过，结果包 `.build/derived-remote-cancel-ios/Logs/Test/OpenMuseRemoteCancel.xcresult`，日志 `.build/logs/openmuse-remote-cancel-ios-ui.log`。
- 边界：这是在线请求级取消，不转移 Mac 任务 owner，也没有心跳/断线状态确认、实时事件流、检查点续跑或离线设备全局锁。测试在同机 loopback 模拟两台已配对设备，不证明真实 Tailscale/蜂窝网络取消。真实 iPhone 继续按用户“稍后再测”暂缓。
- 文档：更新 [运行协议](RUNTIME_PROTOCOL.md)、[需求审计](REQUIREMENT_AUDIT_2026-10-10.md)、[一期验收矩阵](PHASE1_PARITY.md)、[实施计划](IMPLEMENTATION_PLAN.md) 与 README 当前状态。

## 2026-10-10：单轮任务转交 Mac 并交还 iPhone

- 范围：推进 E1/K07，让 Mac 在线时不仅代跑模型，也成为这轮任务的真实执行 owner；手机先提供任务和最新检查点，Mac 完成后再由手机保存回复。
- 变更：配对返回 Mac 的稳定 owner ID。iPhone 先同步本机 task/checkpoint，再经 epoch 交接并确认 Mac 已收到；Mac 校验 task ID、epoch、检查点和配对设备身份后领取任务。Mac Pi 只读工具结束时保存逐项无正文检查点；生成回复后提交检查点，并把 owner 按新 epoch 交回 iPhone。手机同步 Mac outbox、拒绝旧 epoch 结果、重新领取后才保存助手消息与旅行成果。Mac 明确执行失败会将任务交还手机再回退本地模型；交接后网络状态不明时不并行启动手机模型，避免重复执行。旧版 Mac 缺 owner ID 时保留兼容的单轮代理路径，可重新配对启用正式转交。
- 验证：`swift test` 执行 71 项、69 项通过、2 项因缺少实时 Pi/Tailscale 端点条件跳过、0 失败，日志 `.build/logs/openmuse-task-handoff-full.log`。新增双数据库 MacBridge 集成测试覆盖初始同步、owner 转交、Mac 领取、Pi 检查点、交还手机、手机重新领取和旧 epoch 写入拒绝；另覆盖错误 return owner 拒绝。Mac Debug 构建通过，日志 `.build/logs/openmuse-task-handoff-mac-build.log`。iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 6 项通过，结果包 `.build/derived-task-handoff-ios/Logs/Test/OpenMuseTaskHandoff.xcresult`，日志 `.build/logs/openmuse-task-handoff-ios-ui.log`。
- 边界：这是一次一轮请求的交接；没有实时任务步骤推送、心跳、Mac 崩溃续跑、断线后自动分支和离线设备全局锁。模拟 bridge 同机运行，不能证明 Tailscale/蜂窝端的真实交接。iPhone 真机验收仍按用户“稍后再测”暂缓。
- 文档：更新 [运行协议](RUNTIME_PROTOCOL.md)、[需求审计](REQUIREMENT_AUDIT_2026-10-10.md)、[一期验收矩阵](PHASE1_PARITY.md)、[实施计划](IMPLEMENTATION_PLAN.md) 与 README。

## 2026-10-10：聊天附件双端同步、迁移与删除

- 范围：完成 A1/K02/K07/K08 的 TXT、Markdown 与 PDF 附件原件生命周期，让记录元数据之外的二进制文件也能在已配对双端之间传递，并能随工作区迁移或明确删除。
- 变更：新增认证的附件 HEAD/GET/PUT 端点，仅允许传输当前数据库登记的附件 ID；上传和下载均核对大小与 SHA-256，摘要不符时拒绝接收/覆盖。iPhone 发起同步时会补传缺失原件或下载 Mac 端原件。选择包含聊天的工作区 JSON 迁移包会携带原件；不含聊天时 manifest 明示省略并清除悬空消息引用。删除操作在事务内清除当前消息引用并写无正文墓碑，删除本机原件；另一端收到墓碑后清理副本，旧聊天修订导出也过滤已删除附件 ID。
- 验证：`swift test` 执行 77 项、75 项通过、2 项因未配置实时 Pi/Tailscale 端点而条件跳过、0 失败，日志 `.build/logs/openmuse-attachment-delete-core.log`。新增测试覆盖双向认证传输、损坏摘要拒绝、含附件归档往返/导入、无聊天省略和删除引用/原件/墓碑。Mac Debug 构建成功，日志 `.build/logs/openmuse-attachments-mac-build-final.log`。iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 6 项通过，结果包 `.build/OpenMuseiOS-20261010-attachment-delete.xcresult`，日志 `.build/logs/openmuse-attachments-ios-ui-final.log`。
- 边界：验证为 Core/本机桥接集成与模拟器构建，不证明真实 iPhone/Tailscale 蜂窝传输；真机仍按用户“稍后再测”暂缓。附件类型仍只有 TXT/Markdown/PDF；图像、音视频、扫描 PDF OCR、视觉请求、受控备份擦除和 iCloud 未实现。
- 文档：更新 [README](../README.md)、[附件与构件协议](ARTIFACTS.md)、[设备与文件范围](DEVICE_AND_FILES.md)、[记忆存储](MEMORY_STORAGE.md)、[实施计划](IMPLEMENTATION_PLAN.md)、[一期对齐矩阵](PHASE1_PARITY.md) 和 [需求审计](REQUIREMENT_AUDIT_2026-10-10.md)。

## 2026-10-10：构件永久删除与旧归档抑制

- 范围：补 ARTIFACTS/K10 的全版本删除和遗忘一致性，避免用户删除成果后旧迁移包带回内容。
- 变更：资源库条目和构件详情菜单可永久删除构件；SQLite 事务通过通用删除墓碑清掉当前记录、全部修订和同步冲突，并向配对设备传播。回归测试发现旧工作区归档会被 tombstone 阻止恢复当前记录，但修订/冲突载荷仍可能被导入；现在导入阶段同时过滤已有墓碑覆盖的修订与冲突。新增 Core/UI 测试覆盖当前数据清理、旧包恢复抑制和删除确认流程。
- 验证：`swift test` 执行 78 项，76 项通过、2 项因未配置实时 Pi/Tailscale 端点条件跳过、0 失败，日志 `.build/logs/openmuse-artifact-delete-core-final.log`。Mac Debug 构建通过，日志 `.build/logs/openmuse-artifact-delete-mac-final.log`。iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 7 项通过，删除操作返回空资源库，结果包 `.build/OpenMuseiOS-20261010-artifact-delete.xcresult`，日志 `.build/logs/openmuse-artifact-delete-ios-ui.log`。
- 边界：模拟器不等于真机交互验收。独立网页/附件资源尚未接入构件，所以当前删除尚无缩略图或构件附件文件可清理；后续加入时需纳入相同 tombstone 范围。旧版客户端、真机跨设备和外部手动导出文件清理未验证。
- 文档：更新 [ARTIFACTS](ARTIFACTS.md)、[IMPLEMENTATION_PLAN](IMPLEMENTATION_PLAN.md)、[PHASE1_PARITY](PHASE1_PARITY.md)、[需求审计](REQUIREMENT_AUDIT_2026-10-10.md) 和 [README](../README.md)。

## T21：2026-10-10 iOS 近期回顾的机会式后台请求

- 范围：继续补 K11/IOS_BACKGROUND。用户同意参考 OpenMinis 的手机端执行边界；本次采用 iOS 原生 `BGAppRefreshTask` 延伸每日回顾，不把系统后台当作常驻服务。
- 变更：用户开启每日回顾后，OpenMuse 请求系统在安静时段结束后安排一次刷新；打开 App 时仍检查漏跑。关闭选项会撤销后续请求并取消正在进行的后台回顾。后台时间由系统决定，可能延迟或跳过；用户强制退出后不承诺唤醒。请求到期会取消当前模型调用，未完成运行保持失败/待重试状态，不能伪装成成功。设置页已明确说明限制，新增安静时段后的下次机会日期测试。后台刷新默认关闭，不使用音频、定位或其他延长运行方式。
- 验证：完整 `swift test` 执行 84 项、82 项通过、2 项因缺少实时 Pi/Tailscale 服务条件跳过、0 失败，日志 `.build/logs/openmuse-background-core-tests.log`。Mac Debug 构建成功，日志 `.build/logs/openmuse-background-mac-build.log`。iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 8 项通过，包含回顾提案来源和拒绝，结果包 `.build/DerivedData/Logs/Test/Test-OpenMuseiOS-2026.10.10_18-45-30-+0800.xcresult`，日志 `.build/logs/openmuse-background-ios-ui.log`。已用 PlistBuddy 检查任务 ID 与 `fetch` 后台模式。
- 边界：这证明代码编译、前台应用测试和系统任务注册声明，不证明系统真的在锁屏时调度执行。真机后台刷新状态、锁屏时长、系统回收、强制退出、断网和耗电均待验；用户此前要求稍后再连接实体 iPhone。没有完整 HEARTBEAT 编辑器、定时目标检查、费用预算、其他 dreaming 类型或可靠后台保证。
- 文档：更新 [PRD](PRD.md)、[主动工作策略](POLICIES.md)、[后台专题](IOS_BACKGROUND.md)、[记忆存储](MEMORY_STORAGE.md)、[实施计划](IMPLEMENTATION_PLAN.md)、[一期验收矩阵](PHASE1_PARITY.md)、[需求审计](REQUIREMENT_AUDIT_2026-10-10.md) 与 README。

## 2026-10-10：整份工作区迁移包含构件图片

- 范围：补齐 K02/K10 的资料可迁移要求，避免网页构件在整库搬家后只剩 `openmuse-asset://` 引用、图片原件丢失。
- 变更：工作区 ZIP 新增 `artifact-assets/{artifactId}/{assetId}.bin` 条目；不论是否包含聊天，都会打包构件当前版本、历史版本和待解决冲突版本引用的图片。导入会验证安全 ID、允许的图片类型、大小和 SHA-256，再写入本地素材库；若数据库导入失败，会清除没有任何本地版本/冲突引用的孤立文件。记录 ID 必须与构件 payload 一致，冲突两侧的素材也纳入完整性校验。聊天附件仍只在包含聊天的导出中携带。
- 验证：`swift test` 执行 134 项、132 项通过、2 项因缺少实时 Pi/Tailscale 端点条件跳过、0 失败，日志 `.build/logs/openmuse-workspace-artifact-assets-final-core.log`。新增用例覆盖不含聊天迁移、冲突两侧各自引用图片及 AppModel 导出—导入—预览—再导出。iPhone 17 Pro / iOS 26.5 模拟器 UI 自动化 10/10 通过，网页本地交互和外链取消保持页面均已验证；结果包 `.build/logs/OpenMuseWorkspaceAssetsFinalUI.xcresult`，日志 `.build/logs/openmuse-workspace-assets-ios-ui-final.log`。Mac Debug 构建通过，日志 `.build/logs/openmuse-workspace-artifact-assets-final-mac-build.log`；iOS Simulator Debug 构建通过，日志 `.build/logs/openmuse-workspace-artifact-assets-final-ios-build.log`。
- 边界：未验证真实 iPhone 文件选择、蜂窝跨网同步或新设备实际恢复；图片迁移使用合成 PNG 数据。字体、音频/视频构件资源仍未实现。手机真机仍按用户之前“稍后再测”的安排暂缓。
- 文档：更新 [构件协议](ARTIFACTS.md)、[需求审计](REQUIREMENT_AUDIT_2026-10-10.md)、[一期验收矩阵](PHASE1_PARITY.md)、[实施计划](IMPLEMENTATION_PLAN.md) 与 README。

## 2026-10-10：陪伴者页截图对照与真机通道恢复

- 范围：继续 UI_SPEC 像素对齐，并响应用户确认 iPhone 已连接后的真机验收授权。
- 界面变更：陪伴者活动页采用无圆角的大尺寸展示并隐藏系统拖拽条；关闭/分享控件叠放在顶部，不再挤压头像；头像、标题、状态和五入口导航按私人 Muse 截图调整纵向间距与高度。按钮视觉圆形为40pt、点击范围44pt，兼顾截图观感与最小触控尺寸。移除分享内容中的固定陪伴标语。
- 界面验证：已打开本地 Muse 参考图与 iPhone 17 Pro / iOS 26.5 模拟器截图，查看布局差异；陪伴者页截图结果在 `.build/logs/OpenMuseCompanionHitTargetFinal.xcresult`。UI 自动化检查关闭按钮位于顶部安全区、触控宽度不少于44pt、页面不含固定标语。完整模拟器 UI 回归10项、0失败，日志 `.build/logs/openmuse-requirements-current-ios-ui.log`；触控尺寸更新后的单页截图验收另行重跑，最终结果以 `.build/logs/OpenMuseCompanionHitTargetFinal.xcresult` 为准。
- 真机通道：PUA WDA 已 READY，设备为 iPhone 16 Pro / iOS 27.2，当前前台为 Codex；OpenMuse 尚未安装。针对 `org.openmuse.ios` 的 Debug 真机签名构建失败，Xcode 返回 `No Accounts` 和缺少 provisioning profile，日志 `.build/logs/openmuse-real-iphone-build.log`。工作站有其他团队的开发证书，但本项目没有签名授权文件；没有复用其他项目凭证或绕过签名。
- 待用户参与：在 Xcode「设置 → 账户」加入 Apple 账号，并给 OpenMuse 选择 Personal Team 后可继续签名安装；无需付费开发者会员，账号密码不要发到聊天。已经通过异步问题向用户请求完成通知；等待其明确回复期间继续不依赖真机的测试、构建和代码工作。
- 边界：本轮未在真机启动 OpenMuse、输入模型密钥、发送真实模型请求或测试 Tailscale/后台。因此不能把 PUA 通道 READY 描述为 OpenMuse 真机验收通过。截图覆盖仅为陪伴者活动空态，不代表 Muse 所有页面、任务头像动画和状态均实现像素级相同。
- 文档：更新 [UI_SPEC](UI_SPEC.md)、[需求覆盖审计](REQUIREMENT_AUDIT_2026-10-10.md)、[一期验收矩阵](PHASE1_PARITY.md) 和 README。

## 2026-10-10：扫描 PDF OCR 与 iPhone 签名重试

- 范围：补齐附件导入中扫描 PDF 无文本层的可读性，并继续处理用户授权的 iPhone 真机安装。
- 变更：文件选择时验证 PDF，不在主线程提前读取内容；聊天需要附件文本时在后台任务用 Vision 识别最多 20 个无文本页面，单份 PDF 最多读取 100 页，超限会在模型上下文中标明。OCR 文本沿用不可信输入边界与每轮 20KB 上限。当前 Mac 上已用 Xcode 打开 `OpenMuse.xcodeproj`，用户截图中的 Personal Team 已确认，但目标尚未选择该团队。
- 验证：Core 全量执行 136 项、134 项通过、2 项因缺少实时 Pi/Tailscale 条件跳过、0 失败，日志 `.build/logs/openmuse-ocr-final-core.log`；扫描页识别和 20 页上限测试通过。Mac Debug 构建成功，日志 `.build/logs/openmuse-ocr-final-mac-build.log`；iOS Simulator Debug 构建成功，日志 `.build/logs/openmuse-ocr-final-ios-build.log`；iOS 模拟器 UI 自动化 10/10 通过，日志 `.build/logs/openmuse-ocr-ios-ui.log`；`git diff --check` 通过。
- 真机签名：项目已在 Xcode 打开，之后以截图账号对应的团队再次构建，仍报 `No Accounts`、没有可用的 iOS Development 私钥证书及 `org.openmuse.ios` profile；日志 `.build/logs/openmuse-iphone-signing-after-xcode-open.log`。当前只需在 OpenMuseiOS target 的 Signing & Capabilities 选 Personal Team 并启用自动签名，再由 Xcode 生成项目专用 profile；不复用 Lody 或 PUA 的签名配置。OpenMuse 未安装到手机。
- 边界：OCR 是本机 Vision 转文字，不等于图片视觉问答；图片/音频/视频理解仍未实现。iPhone 模型请求、Tailscale 跨网、锁屏后台和耗电均未验收。
# 2026-10-11：长期记忆提示词边界与检索回归

- 范围：对照 Muse、OpenClaw、Hermes Agent 与 nanoMuse 的公开记忆机制，核对模型每轮读取 SOUL.md、USER.md、MEMORY.md 等文件的真实路径，修正会误导长期记忆维护的提示词边界。研究和机制评估见 [长期记忆运行机制对照](MEMORY_RUNTIME_COMPARISON_2026-10-11.md)；保留讨论记录见 T23。
- 变更：SOUL/IDENTITY/AGENTS 作为分开的用户级设置传给模型；普通资料、外部来源和历史原话继续作为低信任背景，带来源和过期提示。普通聊天排除 HEARTBEAT 计划正文。SQLite FTS5 只索引原始用户消息，按关键词召回其他会话；导入对话、助手内容、当前会话和未明确保留的敏感内容不会成为历史检索结果。确定性自动入库仍只支持有限的明确句式。另修正 system prompt 对 AGENTS 与 HEARTBEAT 角色的自相矛盾描述，并补回归断言。
- 验证：`swift test --filter WorkspacePersistenceTests` 执行88项，86通过、2项因缺少实时Pi/Tailscale端点跳过、0失败；`testModelPromptStatesToolResultsAndMacFileBoundaries` 单项复测通过。Mac Debug `OpenMuseMac` 构建成功，产物 `.build/derived-memory-review-mac/Build/Products/Debug/OpenMuse.app`；iOS Simulator Debug `OpenMuseiOS` 构建成功，产物 `.build/derived-memory-review-ios/Build/Products/Debug-iphonesimulator/OpenMuse.app`；`git diff --check` 通过。
- 边界：这是基于公开产品资料与当前源码的机制对照，不代表掌握 Muse 私有的记忆表结构或写入算法。FTS5 不能处理纯同义改写；通用自然语言事实抽取、广义时效/主体冲突处理、长期 dreaming 闭环和真实模型提示注入行为仍未验证。OpenMuse 当前不会自动读取用户 Obsidian vault；同名 Markdown 是 App 工作区数据库的可读投影，外部直接修改可能在投影修复时被覆盖。
- 后续建议：先用合成且带来源的跨周对话集评估事实写入准确率、历史召回率、过时信息处理和纠正后的行为变化，再决定是否加入模型抽取候选与混合检索；推断/外部来源仍应先预览确认。

# 2026-10-11：OpenMinis 端侧运行机制对齐

- 范围：落实用户要求，完整核对 OpenMinis iOS 的端侧系统，并仅调整 OpenMuse 手机运行方式；保留整体 PRD、Muse 交互、Mac 在线优先 Pi、用户选模型、记忆与目标的正式存储规则。
- 上游证据：固定在 `OpenMinis/OpenMinis` commit `b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c`。阅读 README、BUILDING、iOS sandbox summary、`ISHExecutionCoordinator.swift`、`BackgroundKeepAliveManager.swift` 与 `ISHKernel.m`。确认 iOS 使用 iSH/Alpine aarch64，Android 使用 PRoot；会话目录与共享 memory/skills 分开；原生 offload 将特定 guest 命令桥接到 iOS 框架；后台保活是另一层且不代表常驻保证。iSH、Alpine rootfs 与其他 native dependencies 需要从源码构建。
- 实现：OpenMuse 保持 Swift 宿主；手机本机可用受限 tool loop 读历史/目标/核心文件，并在对话隔离临时文本区整理中间材料。SQLite 与 Markdown 仍是唯一正式用户状态来源；Mac 在线且能力匹配时走既有 Pi 路由，Mac 离线时不改变模型/API路径，由 iPhone 接手其支持步骤。没有将 shell、网络或任意目录访问伪装成已支持能力。新建端侧 runtime 对照表和分层图，补充七项工具、缓存生命周期、正式资料边界与 iSH 集成/许可证关卡。
- 验证：`swift test` 全量执行 149 项，147 项通过、2 项因未配置实时 Pi/Tailscale 地址而按条件跳过、0 失败。新增 `OnDeviceAgentWorkspaceTests` 5 项、`PhoneAgentRuntimeTests` 3 项和 AppModel 环境接线测试 1 项通过。iOS Simulator Debug 与 Mac Debug `xcodebuild` 均成功；最终 `git diff --check` 通过。
- 未验证：iPhone 真机 runtime、DeepSeek 真实 function-call、iSH 构建/命令/隔离、原生 offload 权限流程、锁屏长任务。不得将模拟器/自动化状态描述为真机验收或 OpenMinis parity。
- 待决与推荐：OpenMinis README 声明 GPL-3.0；其固定 iSH fork commit `e6521d9cfe9cd48f19917fc3b23aea622ba358b4` 另有 GPL-2.0 补充许可和 `LICENSE.IOS` 专项承诺。OpenMuse 当前 MIT。推荐若一期明确要求 iOS Linux shell，则评估转为 GPL-3.0、保留全部 iSH/嵌套依赖 notices，并完成代码归属及 Apple 分发审查后再集成；若必须保留 MIT，则继续受限 native runtime 或另找兼容执行引擎。当前没有改 `LICENSE`、没有把 GPL 源码导入产品树；固定上游快照仅在忽略的 `.build/upstream` 研究目录。影响与回退路径写在 [T24 补记](DISCUSSIONS.md) 和 [端侧运行时方案](ON_DEVICE_RUNTIME.md)。

## T25：2026-10-11 OpenMinis 端侧工作区持久化与真机启动

- 实现：按 OpenMinis 的“每会话执行工作区与正式共享记忆分层”处理 iPhone runtime。工作区从可清理的 Caches 移入 Application Support；旧版本缓存按 conversation ID 首次打开时迁移，保留原文件，不再按七天清理。每个对话限 80 个文本文件、单文件 256 KB、总量 16 MB，沿用相对路径、文件类型、符号链接和总容量校验。模型上下文明确当前设备工具能力、模型 API 仍在远端、正式 SQLite/Markdown 是事实来源，以及工作区和正式记忆/构件的边界。
- 产品边界：本轮只调整手机端执行/工作文件的保存方式，不改 Muse 式交互、用户选模型、Mac 在线优先 Pi、目标与记忆的结构化存储或产品使命。会话文件当前不参与双端同步/迁移；最终旅行结果仍要保存为正式构件。没有集成 iSH/Alpine shell 或原生 offload，因此本轮完成的是可持久的 Swift 原生 runtime 基线，不是完整 OpenMinis 执行环境。
- 自动化验证：`swift test` 全量执行 151 项，149 项通过、2 项因未配置实时 Pi/Tailscale 地址而跳过、0 失败。新增的工作区测试覆盖超期与重开后保留、旧缓存迁移且源文件保留、单文件/文件数/16 MB 总量限制；AppModel 测试覆盖本机工具工作区与正式记忆只读边界。日志：`.build/logs/openmuse-on-device-runtime-full.log`。`git diff --check` 通过。
- 构建与真机：iOS Simulator Debug、Mac Debug 构建成功；签名的 iOS device Debug 构建成功，产物 `.build/derived-openminis-runtime-device/Build/Products/Debug-iphoneos/OpenMuse.app`。iPhone 16 Pro / iOS 27.2 已通过 `devicectl` 安装 `org.openmuse.ios` 并报告成功启动。PUA/XCTest 随后因 LocalAuthentication「认证已取消」退出，READY 未通过；因此尚无真机界面观察、本机工具读写或真实模型 function-call 证据。用户已被提示在手机解锁、保持亮屏并处理系统授权后继续验收。
- 未完成与回退：iSH 集成仍受 GPL-3.0/iSH 附加许可、发行许可证选择、Alpine 资源包、隔离和设备安全验收约束；没有修改 LICENSE 或导入 GPL 代码。保留现在的 Swift 原生 runtime，可继续真机验证与日常任务；若后续批准 GPL 发行并通过审查，再增加 iSH adapter，不需要改变产品数据合同。当前 iPhone 会话工作区无同步/迁移能力，模型真实 tool-call、锁屏续跑及耗电仍未验。
- 决策记录：[T25 讨论](DISCUSSIONS.md)、[端侧运行时方案](ON_DEVICE_RUNTIME.md)、[启动状态](STARTUP_REVIEW.md)。

## T28：2026-10-11 iSH ARM64 上游 App 构建通过

- 范围：继续 T27 的端侧运行环境可行性验证；只在忽略的 `.build/upstream` 中使用固定 iSH fork，不向 OpenMuse 产品树复制或链接上游代码。
- 处理：将[官方 LLVM 15.0.7 x86_64 macOS 工具包](https://github.com/llvm/llvm-project/releases/tag/llvmorg-15.0.7)下载到 `.build`，只提取 `ld.lld` 实际目标 `lld`；没有运行 Homebrew 安装，也没有改变系统 Python/LLVM。Meson/Ninja 继续使用独立 venv。
- 验证：固定提交 `e6521d9cfe9cd48f19917fc3b23aea622ba358b4` 的 `iSH-ARM64-ffmpeg` Release device scheme 完整构建成功。随后临时从忽略目录上游 checkout 的 ARM64 xcconfig 移除 `ISH_FFMPEG_TEST`，同一 scheme 再次构建成功；构建后已恢复上游文件，确认 checkout 干净。`file`/`lipo -info` 确认宿主 App 可执行文件为 iOS `arm64`；产物 App 包含 3.7 MB 的 `root.tar.gz` Alpine rootfs，整个未签名 `.app` 为 6.8 MB。日志：`.build/logs/openmuse-ish-arm64-build.log`、`.build/logs/openmuse-ish-arm64-no-ffmpeg-build.log`；产物：`.build/upstream/ish-derived-normal2/Build/Products/Release-iphoneos/iSH ARM64 ffmpeg.app`。
- 构建路径观察：直接 `-target iSH-ARM64` 未通过，因为上游 Xcode 子项目在该路径把 `libarchive.a` 以 macOS 目标构建后链接到 iOS；使用上游共享 scheme 会正确构建 iOS 依赖。最终验证关闭了 FFmpeg 测试宏，但产物仍沿用测试 scheme 的文件名和 Bundle ID，不能当作正式发布包。
- 结论边界：这证明固定上游 ARM64 guest、基础 App 代码与 rootfs 能在当前 Intel Mac/Xcode 工具链下编译；它不是 OpenMuse 的 iSH runtime 集成，也没有在 iPhone 安装、启动或执行 shell。根许可证仍为 MIT；GPL/iSH notices、组合发行许可、OpenMuse 侧适配、隔离、rootfs 生命周期和真机命令验收仍未解决。后续必须先做许可/分发决策和最小静态库适配验证，再判断是否进入正式集成；详情见 T28 [讨论](DISCUSSIONS.md) 与 [端侧运行时方案](ON_DEVICE_RUNTIME.md)。

## T29：2026-10-11 iSH App helper 静态库 target 验证

- 范围：检查固定 iSH fork 是否能把 iOS App host helper target 单独编成 OpenMuse 可依赖的 arm64 静态库，为后续 kernel/shell 适配选择正确入口。
- 验证：`libiSHApp` 首次未指定 SDK 的 target build 失败，因 Xcode 忽略 destination 并对 `mach_excServer` 生成多架构重复输出。改为显式 `-sdk iphoneos -arch arm64 ONLY_ACTIVE_ARCH=YES`、独立 `SYMROOT/OBJROOT` 后 `BUILD SUCCEEDED`；`lipo -info` 确认 arm64。产物 `.build/upstream/ish-libiSHApp-arm64/Build/Products/Release-iphoneos/libiSHApp.a`，日志 `.build/logs/openmuse-ish-libiSHApp-arm64-build.log`。
- 结果边界：该 archive 只含上游 App helper 源码，不含 OpenMinis 自己的 `ISHKernel` 宿主封装；未链接 kernel、未启动 guest、未执行命令，也未接入 OpenMuse。当前状态仍为 K04 部分完成；iSH license/distribution route 未确认，不能将此静态库并入公开产品。
- 文档：同步更新 [端侧运行时](ON_DEVICE_RUNTIME.md)、[实施计划](IMPLEMENTATION_PLAN.md)、[需求审计](REQUIREMENT_AUDIT_2026-10-10.md) 与 [集成讨论](DISCUSSIONS.md)。

## T30：2026-10-11 OpenMinis 风格会话挂载布局

- 范围：为 K04 的本机执行宿主准备安全、可审计的 per-conversation guest mount contract，使后续 iSH adapter 不需要把整个 App Container 暴露给 guest。
- 变更：新增 `OnDeviceRuntimeFilesystem`，按 conversation ID hash 创建独立运行区，并生成 `/var/minis/{offloads,attachments,workspace,browser}` 映射。现有受限文本工作区只映射为 workspace；其他目录保存在另一个 Application Support 分区，不会被旧的工作区列表递归收录。attachment mount 为只读，其余三项为读写；拒绝空会话 ID 和符号链接目录，iOS 目录启用首次解锁后保护。没有把 SQLite、Keychain、任意用户目录或核心记忆文件加入 mount 表。
- 验证：`swift test --filter OnDeviceRuntimeFilesystemTests` 5/5 通过，日志 `.build/logs/openmuse-runtime-filesystem-tests.log`。iOS Simulator Debug、iOS device Debug（未签名）和 Mac Debug 构建均通过，日志分别为 `.build/logs/openmuse-runtime-layout-ios-build.log`、`.build/logs/openmuse-runtime-layout-device-build.log`、`.build/logs/openmuse-runtime-layout-mac-build.log`。覆盖 guest 路径与访问级别、工作区映射、运行区持久性/互相隔离、执行目录不混入文本工作区列表、符号链接拒绝和空会话拒绝。
- 结果边界：这是宿主目录和 mount contract 的实现，尚未被 `OpenMuseAppModel` 调用，也未接 iSH kernel，不会执行命令。记忆只读投影、shell command loop、native offload、超时/取消、后台恢复、iSH 真机命令和许可组合仍待实现/验收。没有改变根许可证或引入第三方代码。
- 文档：更新 [端侧运行时](ON_DEVICE_RUNTIME.md)、[实施计划](IMPLEMENTATION_PLAN.md) 与 [需求审计](REQUIREMENT_AUDIT_2026-10-10.md)。

## T31：2026-10-11 iPhone Runtime 当前对话附件只读工具

- 范围：把 OpenMinis 的“附件区与工作区分开，附件只读”落实到 OpenMuse 当前 Swift 本机 Agent Runtime；不改变长期记忆、正式构件或 iSH 许可证边界。
- 变更：新增 `OnDeviceAgentAttachmentAccess`，仅按当前 conversation ID 列出附件，最近 40 项优先；读取时再校验附件记录、当前对话归属、SHA-256 原件和输出上限（20 KB）。iPhone tool loop 增加列表/读取两项工具；附件正文标记为不可信资料，正文不写入活动日志；读取在后台任务进行，避免 PDF OCR 阻塞主线程。模型只能获得 Swift 宿主提取文本，不会得到附件存储路径或其他对话 ID 的可读权限。
- 验证：`swift test --filter 'OnDeviceAgentAttachmentAccessTests|PhoneAgentEnvironmentTests'` 执行 3 项、通过 3 项、0 失败。覆盖当前对话可读、跨对话/穿越 ID 拒绝、最近 40 项/20 KB 限制、UTF-8 安全截断，以及 AppModel 模型工具列表/读取/活动记录接线。完整 `swift test` 共执行 158 项，156 项通过、2 项因缺少实时 Mac Pi/Tailscale 地址而跳过、0 失败；日志 `.build/logs/openmuse-t31-core-full.log`。iOS Simulator Debug 构建成功，日志 `.build/logs/openmuse-t31-ios-build.log`；Mac Debug 构建成功，日志 `.build/logs/openmuse-t31-mac-build.log`。测试输出中有一条既有 `ReferenceConnectorURLProtocol` Sendable 警告，与本次代码无关。
- 边界：这使本机受控工具接口实现只读附件区语义，但没有复制文件到物理 guest mount，也没有集成 iSH/Alpine shell、skills、browser/offload、后台常驻或真机工具运行。iSH 与 MIT 的组合发行决策仍待明确。
- 文档：更新 [端侧运行时方案](ON_DEVICE_RUNTIME.md)、[实施计划](IMPLEMENTATION_PLAN.md)、[需求覆盖审计](REQUIREMENT_AUDIT_2026-10-10.md) 与 [启动状态](STARTUP_REVIEW.md)。

## T32：2026-10-11 长期记忆本地概念别名召回

- 范围：补 K02/K09 在同义表达下的本地召回缺口；不改变事实写入/确认规则、来源和敏感信息边界，也不把词典匹配描述成语义理解。
- 变更：新增可审阅的中英文本地概念别名表；对话上下文、结构化记忆/目标/参考资料和 iPhone 本机历史搜索统一使用 `retrievalTerms` 扩展查询词。没有新增网络请求或依赖。测试覆盖“安排一次出行”召回“去恩施旅游”历史和“出游时不赶行程”的结构化偏好，同时排除无关英语学习历史；既有测试继续覆盖当前对话、导入历史、助手文字和未授权敏感对话排除。
- 验证：上述两个定向测试通过。完整 `swift test` 执行159项，157项通过、2项因未配置实时 Mac Pi/Tailscale 地址跳过、0失败；日志 `.build/logs/openmuse-memory-alias-full-tests.log`。iOS Simulator Debug 构建成功，日志 `.build/logs/openmuse-memory-alias-ios-build.log`；Mac Debug 构建成功，日志 `.build/logs/openmuse-memory-alias-mac-build.log`。`git diff --check` 通过。
- 边界与后续：词表外语义改写、事实有效期/冲突和长期跨日效果仍未验证。暂不每轮执行 NLEmbedding：本机小样本显示计算开销与弱相关误召回风险；先建立合成问答集测召回率、误召回和手机耗时，再决定是否加入混合检索。手机实际模型 tool-call 未在本轮真机验收。
- 文档：更新 [核心记忆方案](MEMORY_STORAGE.md)、[记忆机制对照](MEMORY_RUNTIME_COMPARISON_2026-10-11.md)、[覆盖审计](REQUIREMENT_AUDIT_2026-10-10.md)、[实施计划](IMPLEMENTATION_PLAN.md) 与 [讨论记录](DISCUSSIONS.md)。

## T33：2026-10-11 结构化记忆有效期

- 范围：补齐 K02/K09 中记忆有效期、明确偏好纠正与过期记录召回边界；不扩展到任意事实冲突或猜测历史资料日期。
- 变更：`MemoryClaimRecord` 增加可选 `validFrom`/`validUntil`，老 JSON 缺少字段仍可解码。明确消息捕获时记录生效时间；明确纠正会结束旧偏好并以同一时刻开始新版本。过期记录不会阻止再次保存同一内容，也不会被新偏好纠正逻辑覆盖。相关上下文、用户文件投影、重复检测和候选记忆去重均按当前有效期处理。记忆页可修订日期并记录 revision；日期选择器的截止日包含当天。有效期写入成功但 Markdown 投影失败时，会如实显示部分成功并尝试同步已提交记录。
- 验证：定向 Core 测试 4/4 通过，日志 `.build/logs/openmuse-memory-validity-targeted.log`。完整 `swift test` 执行 162 项、160 项通过、2 项因缺少实时 Mac Pi/Tailscale 地址跳过、0 失败，日志 `.build/logs/openmuse-memory-validity-full-tests.log`。iPhone 17 Pro / iOS 26.5 模拟器日期编辑 UI 测试 1/1 通过，日志 `.build/logs/openmuse-memory-validity-ui-test.log`。iOS Simulator Debug 与 Mac Debug 构建成功，日志分别为 `.build/logs/openmuse-memory-validity-ios-build.log`、`.build/logs/openmuse-memory-validity-mac-build.log`。`git diff --check` 通过。
- 边界：不自动给其他 AI 导入资料或模型推断补日期；不做一般事实冲突消解、主体识别、自由文本日期抽取，也没有跨月真实自用效果证据。`validFrom`/`validUntil` 为空时仍保留来源记录并作为未限定时间的 claim。
- 文档：同步更新 [核心记忆方案](MEMORY_STORAGE.md)、[运行机制对照](MEMORY_RUNTIME_COMPARISON_2026-10-11.md)、[PRD](PRD.md)、[一期验收](PHASE1_PARITY.md)、[需求覆盖审计](REQUIREMENT_AUDIT_2026-10-10.md)、[实施计划](IMPLEMENTATION_PLAN.md)、[启动复查](STARTUP_REVIEW.md) 与本讨论记录。

## T34：2026-10-11 旅行构件备选方案与完整日期覆盖

- 范围：补齐“保留原方案，新增备选”的旅行构件能力，以及按明确行程天数判断完成的缺口；普通修订仍只改当前方案。
- 变更：`ArtifactRecord` 新增可选方案数组和当前方案 ID；每个方案独立保留正文、来源消息、假设、预期/覆盖天数和更新时间，旧构件缺少新字段时仍可读取。用户明确表达保留/新增/备选/对比意图时将旧正文作为方案保留并加入新案；后续普通修改只更新当前案。无效行程回复在持久化前拒绝，原构件和方案集合不变；较短备选不会完成较长目标。计划为 N 天时，只有第 1 到第 N 天标题都存在才算覆盖完成；缺失中间日期不能用重复或跳号标题的数量冒充完整覆盖。
- 界面与迁移：资源库显示方案数量，预览页可切换方案并显示天数差；编辑、历史恢复、JSON/ZIP 构件包保留方案内容。ZIP 校验方案上限、正文大小、唯一 ID 与当前方案引用。系统提示会列出当前方案名称/覆盖度，引导模型按用户意图输出完整的新增案。
- 验证：`swift test --filter Travel` 9/9 通过；完整 `swift test` 执行167项、165项通过、2项按环境条件跳过、0失败，日志 `.build/logs/openmuse-t34-full-tests.log`。跳过项分别需要私有 Tailscale Mac 地址和本地 Pi RPC 端点。iPhone 17 Pro / iOS 26.5 模拟器方案切换 UI 测试 1/1 通过，结果 `.build/derived-travel-variants-ui/Logs/Test/Test-OpenMuseiOS-2026.10.11_06-34-35-+0800.xcresult`；Mac Debug 构建通过，日志 `.build/logs/openmuse-t34-mac-build.log`。补充测试确认两个方案通过同一同步记录复制到另一端。`git diff --check` 通过。
- 边界：未在真实 iPhone 重装验收；模型意图仍依赖明确用词，模糊表达不会触发备选；界面差异目前主要呈现天数/覆盖度，不是逐日语义差分。跨设备方案冲突选择、Mac 离线/新设备恢复、外部景点事实核验、本地字体与复杂构件状态机仍未完成。
- 文档：更新 [ARTIFACTS](ARTIFACTS.md)、[PRD](PRD.md)、[一期验收](PHASE1_PARITY.md)、[实施计划](IMPLEMENTATION_PLAN.md)、[启动复查](STARTUP_REVIEW.md)、[需求覆盖审计](REQUIREMENT_AUDIT_2026-10-10.md) 和 [讨论 T32](DISCUSSIONS.md)。

## T35：2026-10-11 OpenMuse 图标概念稿 v3

- 变更：新增原创深靛蓝与暖光的开放环形图标候选，以中心光点和延伸光路表达陪伴、记忆积累与共同前进；保留 v1/v2 历史稿。
- 产物：[概念稿 v3](design/OpenMuse-AppIcon-Concept-v3.png)，设计说明见 [APP_ICON](design/APP_ICON.md)。本稿未替换当前双端 AppIcon 资源，也未做主屏幕/Dock 小尺寸识别验收。

## T36：2026-10-11 QQ 邮件 multipart 纯文本解析

- 范围：缩小只读 QQ IMAP 连接器对常见复杂邮件的正文解析缺口；仍不导入邮件附件，也不改变邮件服务器内容。
- 变更：邮件头解析同时接受 CRLF 与 LF 行尾并展开折行字段。MIME 解析会在最多 8 层、64 个 part 内递归查找 `text/plain`，跳过标为附件或带文件名的 part，支持 quoted-printable、base64、UTF-8、GB18030、ISO-8859-1 与 Windows-1252；没有可安全读取的正文时只返回主题/发件人摘要提示。
- 验证：QQ 邮件连接器定向测试 7/7 通过；完整 `swift test` 执行172项、170项通过、2项依赖实时 Tailscale 地址或本地 Pi RPC 端点而按条件跳过、0失败，日志 `.build/logs/openmuse-t35-full-tests.log`。Mac Debug 与 iOS Simulator Debug 构建通过，日志分别为 `.build/logs/openmuse-t35-mac-build.log`、`.build/logs/openmuse-t35-ios-simulator-build.log`；`git diff --check` 通过。
- 边界：协议桩测试不等于 QQ 真账号验收；没有验证真实邮箱的特殊 MIME、HTML 正文、附件、增量游标、蜂窝网络或中国网络可达性。真实授权仍需用户在 App 内配置。
- 文档：更新 [记忆资料来源范围](MEMORY_STORAGE.md)、[连接器隐私边界](POLICIES.md)、[一期验收矩阵](PHASE1_PARITY.md)、[实施计划](IMPLEMENTATION_PLAN.md) 与 [需求覆盖审计](REQUIREMENT_AUDIT_2026-10-10.md)。

## T37：2026-10-11 Dreaming 目标小步骤与隐私边界

- 范围：在近期对话回顾中，为明确进行中的目标增加一种有来源的小步骤提案；加强回顾上下文的隐私过滤和运行可审计性。
- 变更：模型最多看到8个近期活动目标、每项目标最多4个未完成且可识别非敏感的步骤；goal-step 必须指向当前活动目标，并引用同一对话内真实用户消息。候选展示前拒绝含敏感词的标题、内容或理由，敏感摘要清空。接受时重新核对目标仍进行中、来源仍存在且属于原对话，然后以单个事务写入新 GoalStep 和 accepted 提案，目标状态不变、不建提醒、不执行外部操作。Dreaming run 以 SHA-256 记录本次实际 system prompt 与清理后模型上下文的摘要，不保存完整提示文本。
- 验证：`swift test --filter DreamingReviewTests` 11/11 通过，日志 `.build/logs/openmuse-t37-dreaming-tests.log`；全量 `swift test` 176 项执行、174 项通过、2 项因实时 Pi/Tailscale 条件跳过、0 失败，日志 `.build/logs/openmuse-t37-full-tests.log`。iPhone 17 Pro / iOS 26.5 模拟器的“加入目标步骤”确认 UI 测试 1/1 通过，结果 `.build/derived-t35-ios/Logs/Test/Test-OpenMuseiOS-2026.10.11_06-50-26-+0800.xcresult`。Mac Debug 与 iOS Simulator Debug 构建通过，日志 `.build/logs/openmuse-t37-mac-build.log`、`.build/logs/openmuse-t37-ios-simulator-build.log`。`git diff --check` 通过，新增 Dreaming 源码/测试无尾随空白。
- 边界：敏感识别依赖维护中的关键词表，不能覆盖所有表达；没有真机锁屏后台或 14 天使用证据。该窄功能不等同 Muse 的完整 dreaming、外部目标研究、关系维护或周期反思。建议频率与步骤粒度按用户自用反馈确认，回退可拒绝提案或关闭目标步骤候选。
- 文档：更新 [讨论 T33](DISCUSSIONS.md)、[一期验收](PHASE1_PARITY.md)、[需求覆盖审计](REQUIREMENT_AUDIT_2026-10-10.md)、[启动复查](STARTUP_REVIEW.md) 和 Muse dreaming 机制记录。

## T38：2026-10-11 兴趣动态的有限主题匹配

- 范围：改善 F1/K12 动态排序对常见兴趣改说法的匹配，并避免过期或敏感记忆参与个性化。
- 变更：兴趣说明、进行中目标、已确认且仍有效的非敏感用户兴趣记忆、正负反馈，先做原关键词匹配，再补一组有限的本地兴趣主题词（旅行/轻松出游、徒步登山、摄影、露营、骑行）。相似主题贡献有上限，不做远端模型改写、不自动发现来源；推荐理由显示用户记忆原文或简体中文主题。英文同义词按整词匹配，避免 `cycling` 误命中 `recycling`。
- 验证：Feed 定向测试 4/4 通过，日志 `.build/logs/openmuse-t38-feed-tests.log`；其中覆盖“徒步”兴趣匹配“爬山”文章、过期骑行兴趣不再影响排序、正负反馈跨说法、英文词边界和理由可读性。全量 `swift test` 177 项执行、175 项通过、2 项因实时 Pi/Tailscale 端点条件跳过、0 失败，日志 `.build/logs/openmuse-t38-full-tests.log`。最新源码的 Mac Debug 与 iOS Simulator Debug 构建均成功，日志 `.build/logs/openmuse-t38-mac-build.log`、`.build/logs/openmuse-t38-ios-simulator-build.log`。`git diff --check` 和本轮源码/测试尾随空白扫描通过。
- 修复记录：初次直接用完整检索 n-gram 做对称扩展，Feed 定向用例发现泛词重叠导致正负信号被放大及排序反转；实现改为小型主题表、单项分值封顶后定向与全量测试均通过。首次失败输出只留在当时的工具结果；随后成功重跑覆盖了同名日志，没有单独保存失败日志。错误现象在本条记录中说明，最终通过不代表首次尝试通过。
- 边界：该实现仍是窄主题表与词项匹配，不是通用语义推荐；没有真实 RSS 来源、跨周使用或推荐点击率数据。未来词组维护应基于用户反馈，避免推断敏感兴趣或自行添加内容来源。
- 文档：更新 [讨论 T34](DISCUSSIONS.md)、[一期验收](PHASE1_PARITY.md)、[需求覆盖审计](REQUIREMENT_AUDIT_2026-10-10.md)、[实施计划](IMPLEMENTATION_PLAN.md)、[启动复查](STARTUP_REVIEW.md) 和 [界面规格](UI_SPEC.md)。

## T39：2026-10-11 iPhone 工作区写入审批与会话绑定

- 范围：把一期“工具请求可审查、拒绝必须有效”落到手机真实存在的工作区写入工具；不开放核心记忆、共享工作区、资源库、Mac 目录写入或通用 shell。
- 变更：模型每次最多提出 8 KB 写入；宿主先做无副作用预检，再展示相对路径、创建/替换状态和完整正文。批准只适用于当前一次写入，写入前复查目标文件指纹；拒绝回传模型且不触碰文件。取消会将工具活动记录为已取消，App 重启会将待批步骤标为取消、活动标为暂停，不保存可恢复的批准。执行或等待批准时，模型层阻止切换/新建对话，确保确认卡片与目标工作区属于同一对话。
- 验证：审批相关 Core 定向测试 18/18 通过，日志 .build/logs/openmuse-approval-targeted-final.log。完整 swift test 为 184 项、182 项通过、2 项条件跳过、0 失败，日志 .build/logs/openmuse-approval-core-full.log；跳过项分别要求实时 Tailscale 地址和本地 Pi RPC 端点。iPhone 17 Pro / iOS 26.5 模拟器审批页 UI 测试 1/1 通过，结果 .build/openmuse-approval-ui-final.xcresult，日志 .build/logs/openmuse-approval-ios-ui-test.log。Mac Debug 构建与 iOS device arm64 未签名 Debug 构建通过，日志分别为 .build/logs/openmuse-approval-mac-build.log 和 .build/logs/openmuse-approval-ios-device-build.log。git diff --check 通过。
- 修复记录：第一次取消回归发现文件没有写入，但活动步骤仍停在“等待确认”；已补发取消事件，并把取消后的说明改为明确的“没有执行写入”。最终相关测试全部通过。初次失败输出保存在 .build/logs/openmuse-approval-targeted-initial-failure.log。
- 真机边界：iPhone-use 当前 READY 未通过；重新启动检查发现连接的 iPhone 锁屏，Xcode 无法启动 WDA。已请求用户解锁并保持亮屏；本轮没有安装新 iOS 包，也没有真机审批交互证据。模拟器与未签名 device build 均不代表真机安装或验收。
- 后续缺口：Mac Pi 写工具及其审批、浏览器/桌面操作、iSH/Alpine、后台续跑、真实蜂窝端到端仍未实现或验收；不能把该审批切片报告为 OpenMinis 完整 parity。
- 文档：更新端侧运行方案、运行协议、权限政策、一期验收矩阵、实施计划、需求审计、启动复查和讨论记录。

## T40：2026-10-11 OpenMuse 图标概念稿 v5

- 变更：新增原创图标候选，以开放环表达持续对话和陪伴，以中心微光表达启发；采用深靛蓝与暖金、浅桃色，减少小尺寸难以辨认的细节。
- 产物：[概念稿 v5](design/OpenMuse-AppIcon-Concept-v5.png)，设计说明见 [APP_ICON](design/APP_ICON.md)。使用内置图像生成工具生成 1254×1254 原稿，并检查 32×32 缩图中的识别度。
- 状态：仅新增设计候选，未替换双端 AppIcon 资源；未运行构建或设备验收。

## T41：2026-10-11 Agent 工作区草稿迁移与恢复

- 范围：补齐用户显式迁移时会丢失的手机 Agent 对话草稿；不把中间文件混入长期记忆或自动双端同步。
- 变更：只有迁移导出勾选“包含聊天记录、活动、AI 迁移原文和任务草稿”时，才按归档内的会话 ID 收集草稿；不含聊天时排除。ZIP 新格式 v2 增加 `agent-workspaces.jsonl`，旧 ZIP v1 和 JSON 迁移文件继续兼容。导入校验会话归属、相对路径、文本编码、文件数/容量与 SHA-256；相同内容跳过，本机同名不同内容留在原位，外来版本保存到 `_openmuse_import_conflicts/`。资料库先导入、草稿后恢复发生文件系统错误时，错误明确说明部分结果；修复后重复导入会补回草稿且不重复写记录。导出界面明确说明需勾选聊天选项。
- 验证：迁移定向测试 14/14 通过，日志 `.build/logs/openmuse-t41-agent-migration-final.log`；完整 `swift test` 执行 192 项、190 项通过、2 项因当前未提供实时 Tailscale 路由地址和本机 Pi RPC endpoint 而跳过、0 失败，日志 `.build/logs/openmuse-t41-final-full-tests.log`。Mac Debug 与 iOS Simulator Debug 构建均 `BUILD SUCCEEDED`，日志 `.build/logs/openmuse-t41-mac-build.log`、`.build/logs/openmuse-t41-ios-simulator-build.log`。`git diff --check` 在收尾前复核。首次定向编译发现测试未解包可选状态字符串，修正后通过；第一次输出被成功复跑日志覆盖，未单独留存。
- 边界：没有自动工作区同步、iSH/Alpine guest 或真实 iPhone 迁移页验收；当前 iPhone-use 真机控制仍受设备锁屏阻塞。OpenMinis iSH 组合许可证的决策仍未改变，未导入 GPL 源码或修改 LICENSE。
- 文档：更新 [PRD](PRD.md)、[端侧运行时方案](ON_DEVICE_RUNTIME.md)、[记忆存储](MEMORY_STORAGE.md)、[一期验收](PHASE1_PARITY.md)、[实施计划](IMPLEMENTATION_PLAN.md)、[需求审计](REQUIREMENT_AUDIT_2026-10-10.md)、[启动复查](STARTUP_REVIEW.md) 与讨论记录。

## T42：2026-10-11 OpenMuse 图标概念稿 v6

- 变更：新增一版原创图标候选，使用开放圆环、中心暖光和向上舒展的双弧表达陪伴与成长；采用深靛蓝、暖金、珊瑚色和少量紫色，控制轮廓简洁以适配小尺寸。
- 产物：[概念稿 v6](design/OpenMuse-AppIcon-Concept-v6.png)，说明见 [APP_ICON](design/APP_ICON.md)。通过内置图像生成工具生成，原稿为 1254×1254。
- 状态：仅增加可评审的设计候选；没有替换 iOS 或 macOS 的 AppIcon，也没有运行构建或设备验收。

## T43：2026-10-11 自然语言周末目标捕获

- 范围：补上 PRD 中“我想周末出去走走，别太累”的轻松旅行案例，让明确表达在主聊中自动进入目标追踪，并能由用户关闭。
- 变更：显式短途出游表达会建立“准备一次周末轻松出游”目标，记录原始用户消息来源、预设可调整步骤，并在本轮状态提示中告知用户已开始追踪以及如何关闭。完成/关闭状态继续写入可查看的目标修订。没有目的地或日期时不伪造行程事实。明确拒绝、假设句和第三方愿望保持不入库。识别到明确七天时目标标题保留“恩施 7 天旅行”边界，便于后续自然表达继续匹配同一目标。
- 验证：目标捕获及端到端发送测试 2/2 通过；标题兼容旅行备选的回归测试 1/1 通过。完整 Core 回归 193 项执行、192 项通过、1 项因未设置实时 Tailscale 路由而跳过、0 失败；Pi RPC 另用本机模拟服务实际启动 Pi CLI，1/1 通过，日志 `.build/logs/openmuse-t43-full-tests-with-pi-fixture.log`、`.build/logs/openmuse-t43-pi-rpc-live-fixture.log`。Node 集成测试实际启动 Pi 并完成隔离快照 `list/read` 工具回合，1/1 通过，日志 `.build/logs/openmuse-t43-pi-read-live-fixture.log`。这些 Pi 测试只请求绑定 `127.0.0.1` 的合成模型，不调用真实模型。第一次全量回归发现目标标题把目的地与“7 天”连写，导致后续消息无法匹配；修复后定向及全量测试通过。首次失败原始日志保留于 `.build/logs/openmuse-t43-full-tests-initial-failure.log`。Mac Debug 与 iOS Simulator Debug 构建成功，日志 `.build/logs/openmuse-t43-mac-build.log`、`.build/logs/openmuse-t43-ios-simulator-build.log`。
- 边界：这是有限本地规则对一个明确 PRD 场景的支持，不是通用语义目标抽取；没有模型候选预览、自动定时跟进、真实多日旅行观察或本轮真机 UI 验收。Pi 本机模拟模型测试不等于配对 iPhone 委派、真实模型调用或家中 Mac 蜂窝验收。其他 PRD 需求保持未完成或部分实现状态。
- 文档：更新 [需求覆盖审计](REQUIREMENT_AUDIT_2026-10-10.md)、[一期验收矩阵](PHASE1_PARITY.md) 和 [实施计划](IMPLEMENTATION_PLAN.md)。

## T44：2026-10-11 OpenMinis guest 工作区隔离修正

- 范围：复核 iOS 运行环境目录合同，避免未来 iSH shell 绕过手机 Agent 工作区的逐次写入审批；不导入 iSH 代码、不改变产品 UI、Mac Pi 路由或长期记忆权威来源。
- 变更：`OnDeviceRuntimeFilesystem` 将 `offloads`、`attachments`、`workspace`、`browser` 四个 guest 目录全部置于对应对话的 `AgentRuntimeSessions/{conversation-hash}` 下。guest `workspace` 是独立草稿区，不再指向正式的 `OnDeviceAgentWorkspace`；正式草稿仍只能由 Swift 宿主经完整预览、逐次批准和写前指纹复核写入。附件目录保持只读合同；拒绝符号链接目录和空会话标识。PRD 与端侧运行方案同步明确该约束。
- 验证：定向 `OnDeviceRuntimeFilesystemTests` 6/6 通过；全量 `swift test` 执行 194 项，192 项通过、2 项因未配置实时 Pi/Tailscale 地址而跳过、0 失败。Mac Debug 与 iOS Simulator Debug 构建均 `BUILD SUCCEEDED`；日志 `.build/logs/openmuse-t44-full-tests.log`、`.build/logs/openmuse-t44-mac-build.log`、`.build/logs/openmuse-t44-ios-simulator-build.log`。首次定向测试发现旧断言仍要求 guest `workspace` 指向正式 Agent 工作区；更新断言后定向和全量测试均通过。`git diff --check` 在文档收尾后复验。
- 未验证/待完成：目录合同尚未由 AppModel 调用，iSH/Alpine guest、只读记忆/技能投影、native offload、iPhone 真机运行以及锁屏恢复都没有本轮验收。固定 OpenMinis/iSH 代码采用 GPL 许可；OpenMuse 未经用户确认不得改变公开仓库授权，因此当前不集成上游代码或二进制。参考研究与具体门槛见 [端侧运行时方案](ON_DEVICE_RUNTIME.md) 与 [讨论 T37](DISCUSSIONS.md)。
- 回退：恢复旧目录映射即可；本轮没有创建用户运行时文件或迁移已有 Agent 工作区内容。

## T45：2026-10-11 OpenMuse 图标概念稿 v7

- 变更：新增原创图标候选，以开放粗弧和一枚暖光表达长期在场、为用户留出空间；与先前中心星芒、多层光效方向拉开差异。
- 产物：[概念稿 v7](design/OpenMuse-AppIcon-Concept-v7.png)，说明见 [APP_ICON](design/APP_ICON.md)。使用内置图像生成工具生成 1254×1254 原稿，并人工检查 32×32 与 16×16 缩图的轮廓辨识度。
- 状态：仅新增设计候选，未替换双端 AppIcon 资源；未运行构建或真机图标验收。用户确认采用后再制作平台尺寸并接入。

## T46：2026-10-11 居住地记忆的时效更新

- 范围：让明确搬家或现居地变化更新当前画像，同时保留籍贯等不同时间属性的事实；不扩大为通用事实冲突或自然语言抽取。
- 变更：明确现居陈述和当前搬迁会结束旧现居 claim 的有效期，保留来源与修订；同句同时表达籍贯和现居时按现居子句更新，原籍 claim 不变。含计划或不确定搬迁、且没有现居子句的句子不会作为长期记忆保存。记忆回执按类别显示“记忆”或“偏好”。
- 验证：意图捕获与端到端居住地用例 2/2 通过；完整 `swift test` 执行 195 项，193 项通过、2 项按配置跳过、0 失败。跳过项要求真实 Tailscale Mac Bridge 地址和本机 Pi RPC endpoint；日志 `.build/logs/openmuse-t46-targeted-final.log`、`.build/logs/openmuse-t46-full-tests-final2.log`。Mac Debug 与 iOS Simulator Debug 构建均 `BUILD SUCCEEDED`，日志 `.build/logs/openmuse-t46-mac-build-final2.log`、`.build/logs/openmuse-t46-ios-simulator-build-final2.log`。`git diff --check` 通过。
- 边界：这是对有限中文句式的保守规则；不支持任意复合句拆分、模糊指代、跨来源冲突或通用语义判断。本轮未做 iPhone 安装、运行或 UI 验收；本机 Pi/Tailscale 两个集成测试因没有对应实时 endpoint 而跳过。
- 文档：更新 [记忆存储](MEMORY_STORAGE.md)、[需求覆盖审计](REQUIREMENT_AUDIT_2026-10-10.md)、[一期验收](PHASE1_PARITY.md)、[实施计划](IMPLEMENTATION_PLAN.md) 和 [讨论记录 T39](DISCUSSIONS.md)。

## T47：2026-10-11 Dreaming 提案逐字来源证据

- 范围：让每条新回顾提案都能在用户采纳前核对具体原话；引文用于验证出处，不冒充语义正确性证明。
- 变更：模型输出必须为每个来源用户消息提供不超过120字的连续原文；解析时逐条核对消息角色、来源 ID 和 UTF-8 字节片段，缺失、伪造、错配或 assistant 来源的提案会被丢弃。身份页同时展示引文和完整来源，并将 confidence 标成“模型自评把握度”。用户采纳前再次核验；来源被编辑后建议过期且不会写入。旧 JSON 仍可解码；记录校验拒绝重复来源 ID 或重复证据项。
- 验证：DreamingReview 全部14项通过；完整 `swift test` 执行198项，196项通过、2项因未提供实时 Tailscale 路由与本机 Pi RPC 端点而跳过、0失败，日志 `.build/logs/openmuse-t47-full-tests-final.log`。iPhone 17 Pro / iOS 26.5 模拟器的引文显示与拒绝 UI 测试 1/1 通过，结果 `.build/results/openmuse-t47-dreaming-ui-final.xcresult`，日志 `.build/logs/openmuse-t47-dreaming-ui-final.log`。Mac Debug 与 iOS Simulator Debug 构建结果记于 `.build/logs/openmuse-t47-mac-build-final.log`、`.build/logs/openmuse-t47-ios-simulator-build-final.log`；`git diff --check` 通过。首次复核发现模型自评百分比易被误读为校准置信度，已改为显式标签；解析和采纳边界均按文档更新。
- 边界：逐字出处不保证模型推断语义成立，仍需用户逐条决定；旧提案无 evidence 字段时继续兼容，不将历史 JSON 误判损坏。iPhone 真机 UI 与长期回顾质量仍未验收。
- 文档：更新 [记忆存储](MEMORY_STORAGE.md)、[记忆运行机制对照](MEMORY_RUNTIME_COMPARISON_2026-10-11.md)、[Muse dreaming 研究](muse-research/MEMORY_AND_DREAMING.md)、[需求审计](REQUIREMENT_AUDIT_2026-10-10.md)、[一期验收](PHASE1_PARITY.md) 和 [讨论 T40](DISCUSSIONS.md)。

## T48：2026-10-11 OpenMuse 图标概念稿 v8

- 变更：新增微启门廊与门内暖光的原创图标候选，去掉人物和星芒，保留深靛蓝与薰衣草紫方向，并让主轮廓占据较大面积。
- 产物：[概念稿 v8](design/OpenMuse-AppIcon-Concept-v8.png)，说明见 [APP_ICON](design/APP_ICON.md)。原稿为1254×1254。
- 状态：已保存到项目设计档案，32×32 与 16×16 缩图轮廓可辨；仍是候选，没有替换 iOS/macOS AppIcon，也未验收设备圆角裁切。

## T49：2026-10-11 OpenMuse 图标概念稿 v9

- 变更：新增一版非对称、未闭合的连续彩带弧线，强调长期对话和成长；与 v8 门廊方向区分，不使用闭合环、文字或人物符号。
- 产物：[概念稿 v9](design/OpenMuse-AppIcon-Concept-v9.png)，说明见 [APP_ICON](design/APP_ICON.md)。原稿为 1254×1254。
- 检查：人工查看 32×32 和 16×16 缩图，主弧线仍可辨；`git diff --check` 通过。
- 状态：新增候选稿，未替换 iOS/macOS AppIcon，未运行双端构建或真机/Dock 图标验收。

## T50：2026-10-11 Dreaming 一对一记忆更新与来源复验

- 范围：补齐一般中文规则未覆盖的窄范围记忆冲突提示，同时确保模型不能修改本轮未见过的记忆；不把模型总结直接写成用户确认事实。
- 变更：Dreaming 提示和解析器共用同一组相关、有效、user scope、非推断、非敏感记忆；提案需要指向一条旧记忆并提供逐字用户来源。身份页并排显示旧记忆、新版本、引文和来源。采纳前重查目标 claim 的更新时间、来源引文及原消息全文 SHA-256；任一变化即标记过期。接受后 SQLite 事务保留旧修订并标记 superseded、写入新来源与新 claim、更新提案状态，之后重建 USER.md 当前投影；新 claim 继续标记为推断。旧版 proposal/evidence JSON 缺少新增可选字段时仍可解码。
- 验证：Dreaming 定向测试 18/18 通过，覆盖隐去未提供的有效记忆、更新写入前不变更、旧/新 claim 修订与来源保存、并发改写旧 claim 使提案过期、原消息追加文字但保留原引文仍过期，以及旧 evidence JSON 兼容；日志 `.build/logs/openmuse-memory-update-dreaming-tests-final.log`。全量 `swift test` 共 202 项，200 项通过、2 项因缺少实时 Tailscale/Pi 端点条件跳过、0 失败；日志 `.build/logs/openmuse-memory-update-full-tests.log`。iPhone 17 Pro / iOS 26.5 模拟器记忆更新确认 UI 1/1 通过，结果 `.build/results/openmuse-memory-update-ios-ui-final.xcresult`，日志 `.build/logs/openmuse-memory-update-ios-ui-final.log`。Mac Debug 与 iOS Simulator Debug 构建通过，日志 `.build/logs/openmuse-memory-update-mac-build.log`、`.build/logs/openmuse-memory-update-ios-build.log`。
- 修复记录：首轮集成测试断言误读采纳前的 proposal 值对象，改为检查 SQLite 中采纳后的状态和关系后通过。来源失效逻辑最初按引文是否仍存在判断；回归加入“保留引文但追加正文”的编辑后，增加全文摘要绑定，现该场景会使提案过期。
- 边界：候选只依赖本地有限关键词相关性；检索不命中就不会提出更新。模型改写仍属推断，用户采纳后可以继续编辑；一般事实语义冲突、主体/时间抽取和自动裁决仍未解决。未做真机 UI、锁屏后台或跨设备实时冲突验收。
- 文档：更新 [讨论 T41](DISCUSSIONS.md)、[记忆存储](MEMORY_STORAGE.md)、[需求覆盖审计](REQUIREMENT_AUDIT_2026-10-10.md)、[一期验收](PHASE1_PARITY.md) 和 [实施计划](IMPLEMENTATION_PLAN.md)。

## T51：2026-10-11 Dreaming 类别提示召回

- 问题：Dreaming 原先只按主题词召回旧记忆。“我换了工作，现在负责海外市场”与旧记录“我是产品经理”不共享关键词时，模型不会看到旧记录，无法提醒用户确认更新。
- 变更：用户本人明确提到偏好、居住地、工作或姓名变化时，允许附带读取同类别当前有效的已确认、user scope、非敏感、非推断记忆；职业变化也能找到被归为 identity 且有明确职业词的旧记录，姓名变化只找姓名 claim，不连带职业 claim。最多保留12条，第三方变化与一般修改/改稿表达不触发。提示和解析共用同一筛选结果；候选仍须逐条用户确认并通过原话来源复验。
- 验证：DreamingReview 19/19 通过，日志 `.build/logs/openmuse-t51-dreaming-tests.log`；全量 `swift test` 203 项，201项通过、2项因缺少实时 Tailscale/Pi 端点条件跳过、0失败，日志 `.build/logs/openmuse-t51-full-tests.log`。Mac Debug 构建成功，日志 `.build/logs/openmuse-t51-mac-build.log`；iPhone 17 Pro / iOS 26.5 Simulator Debug 构建成功，日志 `.build/logs/openmuse-t51-ios-build.log`。新增回归确认无共享词时召回旧工作记忆、排除无关旅行偏好、第三方工作变化不触发；`git diff --check` 通过。
- 复核：首轮测试后发现 `identity` 同时容纳姓名和部分职业记录，已按姓名词与职业词分别限定同类别召回，避免姓名变化带入职业信息。
- 限制：只覆盖列出的明确中文变化提示，不是通用语义冲突识别；没有匹配类别规则时仍可能漏掉更新。没有更改实时聊天自动记忆捕获规则或敏感数据边界；此候选仍是推断，须由用户确认。
- 文档：[讨论 T42](DISCUSSIONS.md)、[记忆存储](MEMORY_STORAGE.md)、[记忆运行机制对照](MEMORY_RUNTIME_COMPARISON_2026-10-11.md)、[PRD](PRD.md)、[实施计划](IMPLEMENTATION_PLAN.md)、[一期验收](PHASE1_PARITY.md)、[需求覆盖审计](REQUIREMENT_AUDIT_2026-10-10.md)。

## T52：2026-10-11 GPL-3.0 与 iSH/Alpine 真机集成

- 范围：落实用户已确认的 GPL-3.0+iSH 方案，使 iPhone 在没有 Mac 时有可选 guest shell；不改变 Mac 在线优先、Swift 宿主管理模型/权限/记忆的整体合同。
- 变更：根许可证为 GNU GPL-3.0；固定 `OpenMinis/ish-arm64` 子模块 commit `e6521d9cfe9cd48f19917fc3b23aea622ba358b4`；构建 iSH ARM64 静态库和 Alpine 3.24.2 aarch64 rootfs，SHA-256 固定，rootfs 打入 iPhone App。iPhone 工具每条命令完整预览并单独批准，最多4 KB、45秒、输出12 KB；只挂当前对话隔离运行目录，附件只读，允许 guest 网络，私有 rootfs 可变；Swift 宿主管理取消/超时，guest 与 App 共进程而非强隔离 VM。Rootfs 首次复制后持久化，暂不自动升级。iSH/iOS 许可文件与第三方清单进入双端 App 包；OpenMuse 的 iSH DNS socket patch 作为独立可重复应用的 GPL patch 保存在 `Vendor/patches`。
- DNS 实现：iOS SDK 声明的 `res_ninit/res_getservers/res_nclose` 实际链接失败，故不读取私有 resolver 符号，也不硬编码公网 DNS。guest 的 `127.0.0.1:53` 目标由固定 iSH socket patch 改写至本机临时高端口代理；宿主使用系统 `getaddrinfo`，并发查询最多4项，预期遵循当前 Wi-Fi/蜂窝/VPN 策略。该代码已编译，但 DNS 网络命令尚未在真机执行。
- 验证：`swift test` 212项，210通过、2项因缺少实时 Pi/Tailscale 地址按条件跳过、0失败，日志 `.build/logs/openmuse-ish-final-core-tests.log`。Mac Debug、iOS Simulator Debug、iOS真机 arm64 Debug 均 `BUILD SUCCEEDED`；真机最终日志 `.build/logs/openmuse-ish-ios-device-build-final.log`，Mac `.build/logs/openmuse-ish-mac-build.log`，Simulator `.build/logs/openmuse-ish-ios-simulator-build-final.log`。`devicectl` 确认当前设备 marketing name 为 iPhone 15 Pro Max、iOS 27.2；个人签名包 `org.openmuse.ios` 安装成功，签名验证有效，PUA READY 且 OpenMuse 前台可读；最终页面为旅行引导首屏。最终 App 含 9.9 MB Alpine rootfs、root license、第三方 notices、iSH `LICENSE.md`/`LICENSE.IOS` 与 Alpine 包 notices。`git diff --check`、构建脚本 bash 语法检查通过。
- 失败与修复：首轮链接因私有 resolver 符号失败，改为本机 DNS 代理；后发现 XcodeGen 工程没有把许可证资源复制到 App 包，改为双端 post-build 显式复制并重建；模拟器也补齐相同许可材料。最终签名构建、安装、启动和 codesign verify 均通过。
- 未验证/阻塞（T52 时状态，现由 T53 更新模型与审批结果）：手机模型设置当时没有已保存的 API key，因此真实 DeepSeek tool-call、模型触发的 shell 审批、`uname`/Alpine版本及网络 DNS 尚未测试。取消/45秒超时、内存压力、guest 崩溃恢复、Mac 离线任务交接、原生 offload、只读记忆/skills guest 投影、rootfs升级、后台锁屏和 App Store 分发仍未验。此轮未把 App 启动冒充 shell 命令成功。
- 回退：可关闭 `openmuse_phone_run_ish_command` 工具并从 iPhone target 移除静态库/rootfs/submodule，保留 Swift 原生工具；公开仓库 GPL-3.0 授权仍需单独决定，除非另做许可变更。
- 文档：更新 [端侧运行时](ON_DEVICE_RUNTIME.md)、[需求覆盖审计](REQUIREMENT_AUDIT_2026-10-10.md)、[实施计划](IMPLEMENTATION_PLAN.md)、[一期对照表](PHASE1_PARITY.md)、[后台策略](IOS_BACKGROUND.md)、[启动审查](STARTUP_REVIEW.md)、[README](../README.md) 与 [第三方声明](../THIRD_PARTY_NOTICES.md)。

## T53：2026-10-11 DeepSeek iSH 调用必须 fail closed

- 问题与证据：用户已在 iPhone 设置中保存 DeepSeek key，且开启本机工具。首次真实模型回合针对明确的 iSH 命令返回了文字形式的“已执行”及环境输出，但活动详情没有 iSH 工具事件，审批列表也为空。因此没有证据证明命令真实运行；该回复不能作为执行结果。此前一度把回复误报成执行成功，已当场更正。
- 修复：用户明确要求执行 shell 时，OpenAI-compatible runtime 只提供 iSH 工具，并使用命名 `tool_choice` 要求模型返回该工具调用；若工具关闭/不可用、模型仍只返回文字或返回错误工具名，均在执行前失败并说明命令未运行。只有收到真实工具结果后才继续生成回复；普通聊天与明确要求不要再运行的消息不强制 shell 工具。系统提示也明确禁止复用历史终端输出伪装成本轮结果。
- 验证：`PhoneAgentRuntimeTests` 定向10项通过；全量 `swift test` 执行216项、2项因缺少实时 Tailscale/Pi 地址条件跳过、0失败，日志 `.build/logs/openmuse-full-test-after-toolchoice.log`。iOS 真机 Debug 签名构建、`codesign --verify` 与覆盖安装通过，构建日志 `.build/logs/openmuse-device-forced-tool-choice.log`；PUA 重新打开应用后进行真实 DeepSeek 对话，iPhone 显示正式 iSH 审批卡，卡片明确展示 `uname -a && cat /etc/alpine-release` 及“拒绝/允许本次执行”。截图保存在忽略目录 `.research-local/openmuse-device/2026-10-11/`。
- 当前边界：审批卡显示证明真实模型回合已进入工具审批边界，不证明用户已批准或命令已运行。仍等用户在手机选择允许或拒绝；本轮普通 App 路径下的 shell、Alpine 版本、DNS 均尚无执行结果，DNS 请求也未发起。测试日志中两个跳过项分别要求实时私有 Tailscale 地址和本机 Pi RPC endpoint。
- 回退：若目标模型不支持指定工具调用，当前行为是安全失败；不要退回 `tool_choice:auto` 并把任意文本回复当作执行结果。

## T54：2026-10-11 iPhone 本机网页查询与审批精简

- 用户问题：iPhone 未连接 Mac 时查询广州天气，模型却说没有联网工具；用户同时要求参考 OpenMinis 检查哪些审批可以免掉，并决定是否需要它的小型工具界面。用户另确认远程桌面放到二期，一期先完成其他需求（D33）。
- 根因：手机原先没有本机网页工具，模型只能误走 iSH；设备内 Alpine guest 当时没有 `curl`。此外，基础 system prompt 仍写着当前没有网页搜索/浏览器工具，和后续“手机有只读网页能力”的运行提示互相冲突。工具实现本身存在不等于模型会使用；提示词需要与本轮真实工具清单一致。
- 修复：手机增加原生隔离、只读网页搜索和页面正文读取；仅在实时问题、明确联网或用户给出 URL 时向模型开放，明确离线请求则不提供。搜索词仅使用必要公开关键词；不登录、不填表、不提交、不修改页面。修正基础 system prompt，避免继续宣称没有工具。普通聊天不再收到无关 shell/网页工具；用户明确执行命令时只暴露 iSH 并强制命名工具调用，模型未返回真实工具调用时 fail closed。
- 权限策略：只读公开网页查询无需逐次审批。iSH 首次展示完整命令，用户可选单次授权或允许当前对话后续命令免重复确认；当前对话授权保存在本次 App 运行内存，App 重启或新会话后失效。正式资料和工作区写入仍逐项审批；将来的发送邮件、付款、预订、外部删除等副作用逐项确认。guest 的网络和私有 rootfs 修改能力没有扩展到正式记忆、Keychain、Mac 或整个 App 容器。
- OpenMinis 对照：固定 commit `b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c` 的 iOS `browser_use` 经原生 WKWebView/offload 执行；浏览器有独立开关。offload 权限分 `Bypass`、`Ask Once`、`Not Allowed`，按命令和风险区分，并非全部免审批。工具胶囊可点开详情面板。源码、权限表和 UI 判断见 [对照研究](OPENMINIS_BROWSER_PERMISSIONS_2026-10-11.md)。
- 真机验收：iPhone 15 Pro Max / iOS 27.2 安装并启动新签名构建。DeepSeek 新对话实际查询广州今日天气，回复注明使用 iPhone 本机只读浏览器、未用 iSH，展示百度搜索结果页摘要与来源链接；该页面天气数值未另与官方气象来源交叉验证。任务在活动页显示完成；详情页确认记录本轮回复保存。消息首次输入只进入草稿，检查后通过发送按钮提交一次；一次等待工具调用的参数不被接受后改用有效短等待，发生连接暂时不可达，未重复发请求，恢复 PUA READY 后检查到最终回复。真实设备截图只保存在本机 iPhone-use 产物区，未复制进公开仓库。
- 自动验证：`swift test --filter 'PhoneAgent(Runtime|Environment)Tests|PhoneSandboxRuntimeTests'` 26/26 通过；iOS Simulator Debug 构建通过；签名 iPhone 15 Pro Max Debug 构建、签名校验、`org.openmuse.ios` 覆盖安装和启动通过。测试覆盖天气强制搜索、离线 opt-out、普通旅行聊天不暴露网页工具、未请求 shell/浏览器不下发、工具调用与来源回传。
- UI 决定：当前使用 Muse 式头像状态和活动详情作为主要任务入口；短查询的回答已带来源链接，任务状态由活动步骤承载，先不额外加 OpenMinis 通用胶囊。多网页、长时间或可交互任务出现后，再评估消息下方的紧凑摘要/展开详情。
- 文档同步：更新 [PRD](PRD.md)、[一期对齐](PHASE1_PARITY.md)、[权限策略](POLICIES.md)、[端侧运行时](ON_DEVICE_RUNTIME.md)、[启动审查](STARTUP_REVIEW.md) 与 [讨论索引](DISCUSSIONS.md)。

## T55：2026-10-11 OpenMinis 工具活动详情对齐

- 研究：固定 OpenMinis commit `b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c`，确认胶囊展示工具、状态和耗时；点开后按工具类型看参数、输出/错误、文件/网页/记忆/图片等专属数据；长按可复制完整调用。逐项代码依据见 [活动详情对照](OPENMINIS_ACTIVITY_DETAILS_2026-10-11.md)。沿用 D36：OpenMuse 仍从头像的活动记录进入，不新增聊天胶囊。
- 实现：模型工具事件现在带调用参数、返回文本/错误及时间；iPhone 本机浏览器和 iSH、Mac Pi 当前开放的只读文件工具均把逐次操作作为独立 SQLite 记录保存，以稳定 ID 关联活动并走现有同步/归档链路。活动详情逐步展示工具名、脱敏参数、返回/错误、来源/路径、状态、开始/结束时间；执行中每秒更新耗时，并可停止当前回复。可展开大文本并复制完整操作与时间记录。参数/结果/错误设字节上限，保存前遮盖常见密钥形式，终端控制字符只在显示时清理。
- 验证：定向 Core 套件 26/26 通过，覆盖浏览器/iSH/Pi 的实际工具事件、参数/结果持久化与重开、SQLite/同步归档、凭证遮盖和截断。iOS Simulator Debug 与 macOS Debug 均构建成功。日志：`.build/logs/openmuse-t55-activity-tests.log`、`.build/logs/openmuse-t55-ios-simulator-build.log`、`.build/logs/openmuse-t55-mac-build.log`；`git diff --check` 通过。
- 边界：未在真机点开活动详情或检查复制/滚动手感。停止按钮结束当前回复等待；若任务已经交给远端 Mac，远端动作可能继续。OpenMuse 当前工具没有 OpenMinis 的浏览器交互快照、图片工具、文件编辑差异视图等数据源，因此没有伪造这些专属面板；常见凭证脱敏不是完整秘密检测，记录仍属私人资料。来源和实现细节见 [研究笔记](OPENMINIS_ACTIVITY_DETAILS_2026-10-11.md)。

## T56：2026-10-11 OpenMinis 实机详情对照与操作记录补齐

- 实机研究：通过 iPhone-use 打开手机上现有的 OpenMinis Shell 测试调用，未触发新模型请求或执行命令。胶囊显示工具图标、名称、耗时；点开后，终端正文显示完整命令和输出，固定底栏显示成功状态、执行工具、调用摘要、耗时、完成时间与前后调用导航。面板本身无可见复制按钮；源码中的胶囊长按菜单复制调用名、调用编号、参数、返回与状态。截图留在本机 `~/.local/share/iphone-use/artifacts/20261011T083630759838Z-0324edcd.jpg`，未进入仓库。浏览器、文件差异、记忆与图片面板仍只由固定源码确认；本次实机没有这些操作记录可检查。
- 实现：`ActivityOperationRecord` 增加可选 `toolCallID`，旧记录仍能解码；活动详情展开显示调用编号与执行设备，复制文本包含这两项。操作记录如果先于/缺少活动摘要步骤到达，也会单独生成详情入口，避免同步时把操作隐藏。工具分组保持首次出现顺序；没有返回正文时说明仍在执行或无文本结果。复制按钮增加明确的无障碍名称/标识，并将“已复制”反馈延长至 3 秒。没有为当前纯文本工具伪造截图、文件编辑差异或图片内容。
- 验证：`swift test --filter 'ActivityToolDetailPolicyTests|PhoneAgentEnvironmentTests'` 共 13 项通过，覆盖独立记录、同步/归档往返、旧记录兼容与手机工具行为；iPhone 17 Pro / iOS 26.5 模拟器通过 `testActivityDetailsShowOperationIDInputOutputAndCopyWithoutSummaryStep`，逐项检查工具名、状态、调用编号、设备、参数、结果、起止时间、耗时及复制反馈。`git diff --check` 通过。证据日志为 `.build/logs/openmuse-activity-detail-core-tests-final.log` 和 `.build/logs/openmuse-activity-parity-uitest-verified.log`。
- 边界：本轮没有把最新 OpenMuse 构建安装到 iPhone；OpenMuse 当前手机安装版本不能作为这次修改的真机验收。最新活动详情行为已在模拟器验证；执行中只显示状态和计时，不逐块显示 Shell 实时输出。上游浏览器快照、文件差异、记忆、图片等富视图仍需对应工具先真实产出结构化数据，再逐类实现和验收。详见 [OpenMinis 活动详情对照](OPENMINIS_ACTIVITY_DETAILS_2026-10-11.md)。

## T57：2026-10-11 iSH 运行中输出与真机活动详情

- 范围：让 iSH 命令执行中的累计输出进入 D38 既有活动详情记录；不新增聊天胶囊，不改变 OpenMinis 风格对照中确定的详情入口。
- 实现：`PhoneSandboxCommandRuntime` 增加兼容旧实现的输出回调；iSH Objective-C bridge 约每 250 毫秒轮询 bounded guest 输出并发送累计快照，Swift runtime 按序转发；AppModel 将每个快照保存为同一稳定 tool-call ID 的 `running` 操作记录，命令完成后更新为终态。运行中摘要明确说明输出会继续更新。guest 输出仍受 12 KB 上限，记录继续使用既有脱敏、同步和截断规则。
- 自动验证：`swift test --filter 'PhoneAgentEnvironmentTests|PhoneSandboxRuntimeTests|PhoneAgentRuntimeTests'` 执行 27 项、27 通过、0 失败；日志 `.build/logs/openmuse-stream-output-core-tests.log`。端到端 fixture 在命令返回前先发出中间输出，再发出累计输出；测试检查 `running` 操作记录已持久化中间文本。
- 真机验证：iPhone 15 Pro Max / iOS 27.2 上，新签名构建已安装并启动（`org.openmuse.ios`，版本 0.1.0，build 2）。`codesign --verify --deep --strict` 通过；构建日志 `.build/logs/openmuse-stream-output-device-retry.log`，安装日志 `.build/logs/openmuse-stream-output-device-install.log`。首次构建因隔离 iSH 工具目录未找到 `ld.lld` 失败，随后使用仓库忽略的 `.build/ish-tooling/bin/ld.lld` 链接和 `OPENMUSE_VDSO_LLD` 重试成功，没有改全局工具安装。
- 真实模型操作：DeepSeek 在手机上实际调用 iSH 执行 `printf '第一行\n'; sleep 4; printf '第二行\n'`，返回退出码0、输出“第一行”和“第二行”、`outputTruncated=false`。从活动记录展开的真实操作详情显示工具 `openmuse_phone_run_ish_command`、稳定调用编号、执行设备 iPhone、完整参数和输出结果。详情截图只留在本机 iPhone-use 产物区，未复制到仓库。
- 未验证：本轮是在命令结束后打开详情检查终态，没有在仍运行的命令期间展开页面观察屏幕是否按快照刷新；因此代码与 Core 中间态已验证，设备 UI 流式刷新仍待做。浏览器快照、文件差异、图片等 OpenMinis 专属富视图仍待对应数据源和单独验收。
- 文档：更新 [OpenMinis 活动详情对照](OPENMINIS_ACTIVITY_DETAILS_2026-10-11.md)、[一期对齐](PHASE1_PARITY.md)、[PRD](PRD.md)、[需求审计](REQUIREMENT_AUDIT_2026-10-10.md) 与 [讨论 T49](DISCUSSIONS.md)。

## T58：2026-10-11 持久浏览器对齐、工具路由修正与活动详情可见性

- 用户要求：让模型像 OpenMinis 一样操作持久浏览器标签；搜索、工具路由和其他相似问题优先查源码，按已确认权限决定实施；活动详情保留每次网页操作的参数和返回。
- 上游证据：固定 OpenMinis commit `b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c` 的 iOS `browser_use` 默认出现在 Agent 工具清单中，只有用户关闭能力时才移除。它使用对话级标签池、390×844 iPhone 视口、系统默认持久 `WKWebsiteDataStore`，保存 URL 并惰性恢复。OpenMuse 先前按消息意图隐藏浏览器、WebView 为零尺寸且使用非持久 store；另外，`browser_use` 里的 `browse` 被误当成搜索关键词，中文否定“不要用 iSH”也曾强制 shell。源码和差异更新在 [浏览器权限研究](OPENMINIS_BROWSER_PERMISSIONS_2026-10-11.md) 与 [讨论 T61](DISCUSSIONS.md)。
- 实现：手机 Agent 默认收到通用持久 `browser_use`，仅用户明确要求离线/不要浏览时隐藏；`WKWebView` 改用固定移动视口和系统持久数据存储，URL/title/选中标签留在本机按对话恢复。明确 URL 导航强制 `navigate`，实时天气类搜索强制 `search`；真实工具失败会终止本轮并返回错误。修正搜索意图误判与“不要运行 iSH”的中文否定识别。公开 HTTPS 浏览免逐次确认，iSH 网络按 D37 不额外审批；不引入任意 JS、Cookie、下载或页面截图能力。
- 活动详情修正：真机首看发现中高度 sheet 会把展开参数裁在可视区域外。现在详情默认全高，检查点和工具记录共用可滚动区；用户从头像进入活动记录，展开操作可查看工具名、稳定调用编号、执行设备、参数、返回/错误、状态、耗时并复制，不新增聊天胶囊。
- 自动测试：`swift test --filter 'PhoneAgentRuntimeTests|PhoneAgentEnvironmentTests|PhoneSandboxRuntimeTests'` 执行33项，33通过、0失败。iPhone 17 Pro / iOS 26.5 模拟器的 `testActivityDetailsShowOperationIDInputOutputAndCopyWithoutSummaryStep` 执行1项、1通过，覆盖展开参数/结果、滚动后复制按钮可达与复制反馈。xcresult：`.build/openmuse-activity-scroll-ui/Logs/Test/Test-OpenMuseiOS-2026.10.11_19-28-56-+0800.xcresult`。
- 真机安装：iPhone 15 Pro Max / iOS 27.2，`org.openmuse.ios` 0.1.0 (2)。签名构建成功，`codesign --verify --deep --strict`、`devicectl` 安装和启动通过。构建产物 `.build/openmuse-browser-activity-device/Build/Products/Debug-iphoneos/OpenMuse.app`。未将本机私密截图复制到仓库。
- 真机动作：真实模型在 `tab_id=1` 打开 `https://example.com/` 并读取标题/正文/链接；后续回合 `list_tabs` 显示该标签，再用同一 `tab_id=1` 执行 `get_readable`，没有创建新标签，也没有调用 iSH。覆盖安装并启动后再检查标签列表，URL 元数据仍可用。展开真实天气搜索的活动记录后，屏幕显示 `openmuse_phone_browser_use`、稳定调用编号、`iPhone`、动作 `search`、查询词“广州未来三天天气预报”、`tab_id=1`、返回内容及 `cn.bing.com` 来源。
- 搜索路径结果：本次天气流程尝试 Google 后，按设置回退到 Bing 的 MSN 天气卡；日期标注不完整、天气值未与官方来源交叉验证，因此该结果只证明工具调用、回退和操作记录，不是天气准确性验收。Google 在当前网络下成功仍未验证。
- 边界：覆盖安装/进程恢复后 URL 元数据可见，不等于网站 Cookie/localStorage 已通过跨重启测试；也不会恢复原页面 DOM、滚动或未提交表单。iSH DNS/外网 shell 命令、guest 超时取消/崩溃恢复、锁屏后台、蜂窝网络及上游浏览器截图/JS/Cookie/下载能力仍未验。活动详情复制按钮已在模拟器 UI 测试，真机本轮检查了参数和返回内容，未单独点复制。
- 文档：更新 D38/D40、PRD、K04/E1b、端侧运行时、启动审查、OpenMinis 权限/活动详情对照和 T61 讨论；`git diff --check` 通过。

## T62：2026-10-11 iSH 与模型共用持久浏览器标签

- 需求：参考 OpenMinis 源码，让模型可以持续操作持久浏览器标签；其它类似运行问题先研究上游，按 OpenMuse 已确认的权限边界实现。
- 上游核对：固定 OpenMinis commit `b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c` 的 `BrowserTabPool` 由 Agent `browser_use` 和 `BrowserUseOffloadBridge` 下的 `minis-browser-use` 共用；一个聊天中的导航后可由 shell 命令继续操作同一标签。
- 实现：iOS App 把同一个 `IOSPhoneBrowserRuntime` 注入 Agent 和 `ISHPhoneSandboxRuntime`；Core sandbox API 把 conversation ID 一并传到 guest bridge。iSH 注册 `openmuse-browser-use` native offload 命令，允许模型/脚本对当前对话调用 `search`、`navigate`、`get_readable`、`get_text`、`get_page_info`、`find_elements`、`click`、`type`、`scroll`、DOM 等待和 tab 管理，返回结果进入现有 shell 操作详情。`encodeJSON` 在达到响应上限时缩短正文后重新序列化，避免输出无效的半截 JSON。
- 真机流程：PUA READY 确认 iPhone 15 Pro Max 解锁且 `org.openmuse.ios` 前台可操作。真实模型先调用 `browser_use` 导航到公开测试页，收到 `tab_id=1`、`Example Domain` 和 `https://example.com/`。后续请求明确只用 iSH，真实调用 `openmuse-browser-use list_tabs` 后返回同一标签；再执行 `openmuse-browser-use get_readable --tab-id 1`，返回同一标签的标题、URL 和完整页面正文。没有重新导航或新建标签。两条活动操作详情在手机上均显示 iPhone 设备、稳定调用编号、完整命令参数、成功状态、退出码0、返回 JSON 和耗时；截图证据保留在本机 iPhone-use 产物目录，未复制到仓库。覆盖安装并重启 App 后，同一对话再次从 iSH 列出已保存的 `tab_id=1` 并读取到 Example Domain；保存的 URL 按需恢复成功，未测试 Cookie/localStorage 内容。
- 自动回归：完整 `swift test` 执行 235 项，233 通过、2 项条件跳过、0 失败；日志 `.build/logs/openmuse-browser-shared-core-test.log`。签名 iOS 真机构建成功，日志 `.build/logs/openmuse-browser-shared-device-final-build.log`；`codesign --verify --deep --strict` 通过，安装并启动 `org.openmuse.ios` 0.1.0 (2) 成功，安装后 PUA READY 仍可见同一对话及标签。`git diff --check` 通过。
- 安全与范围：iSH 普通网络仍按 D37 不逐条审批；共享浏览器仍限公开 HTTPS 和受限动作，不开放任意 JavaScript、Cookie 读写、下载或页面截图回传。guest shell 本身的外网能力由用户已确认的 D37 管理，网页内容继续作为不可信数据。本轮覆盖安装后通过真实 iSH 工具调用验证 URL 元数据惰性恢复；没有登录测试站点，也未检查 Cookie/localStorage 跨重启。
- 尚缺：OpenMinis 截图回传、页面快照、无限列表采集、任意 JS、Cookie 和下载不在本次实现范围；iSH DNS、超时取消/崩溃恢复和可靠后台续跑仍待单独验收。详见 [D41](DECISIONS.md)、[T62 讨论](DISCUSSIONS.md)、[OpenMinis 对照](OPENMINIS_PHONE_RUNTIME_COMPARISON_2026-10-11.md)。

## T63：2026-10-11 按 OpenMinis 修正 iSH guest DNS

- 需求：用户要求类似的端侧运行问题先核对 OpenMinis 源码，找到已验证做法后再改，权限决策继续遵循 D37。
- 上游证据：固定提交 `b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c` 的 `ISHKernel.configureDns()` 用 `res_ninit`/`res_getservers` 读取 iOS 当前 nameserver 并写入 guest `/etc/resolv.conf`；`NetworkMonitor` 在 `NWPathMonitor` 路径变化时刷新；Xcode target 显式链接 `libresolv.tbd`。源码链接见[端侧运行时对照](OPENMINIS_PHONE_RUNTIME_COMPARISON_2026-10-11.md)。
- 旧实现失败证据：iPhone 15 Pro Max / iOS 27.2 上 `uname -a`、`cat /etc/alpine-release` 成功；`nslookup example.com` 返回 `198.18.0.45`，`wget -S -O /dev/null --timeout=20 https://example.com/` 报 `bad address` / 实际 exit 1；绕过 DNS 直连 `93.184.215.14:443` 等待45秒后被宿主停止。数据证明旧 DNS 代理路径失败；没有用浏览器成功来推断 guest socket 可用。
- 实现：移除宿主 `getaddrinfo` 合成应答代理、guest `127.0.0.1:53` socket 重写和相关构建补丁。host adapter 现在读取 resolver server/search domain 并写入持久 `resolv.conf`；每条 guest 命令开始前及 `NWPathMonitor` 收到路径变化时重新读取系统 DNS。iOS target 补 `-lresolv`，XcodeGen source 与已生成工程保持一致。权限不变：普通 guest command/network 不逐条审批，正式资料写回和敏感原生能力继续由宿主控制。
- 自动构建：初次设备目标构建未设置仓库忽略目录中已有的隔离 LLD，失败；设置 `OPENMUSE_VDSO_LLD=.build/ish-tooling/bin/ld.lld` 后 iOS arm64 unsigned Debug 编译、链接和打包通过；iOS Simulator Debug 也通过。日志 `.build/logs/openmuse-ish-network-device-build.log` 与 `.build/logs/openmuse-ish-network-simulator-build.log`。`git diff --check` 通过。
- Core 回归：重新运行 `swift test`，235 项中233通过、2项条件跳过、0失败；覆盖手机 Agent 默认浏览器、iSH 普通任务无需审批、活动操作详情等相关既有测试，日志 `.build/logs/openmuse-ish-network-core-tests.log`。此套 Core 测试不执行设备 guest DNS 请求，不能替代真机网络验证。
- 真机安装状态：签名构建分别提示没有 development team/profile，加入 `-allowProvisioningUpdates` 后 Xcode 仍报告 `No Accounts` 和找不到 `org.openmuse.ios` profile。证书身份存在于本机 Keychain，但 Xcode 当前没有可用 Account；尚未签名、安装或启动这版程序。日志 `.build/logs/openmuse-ish-network-device-signed-build.log`。先前版本仍是最后一次设备安装，不得把新 DNS 实现报告为已真机通过。
- 下一步：在 Xcode 设置重新添加 Apple Account/Personal Team 并生成 `org.openmuse.ios` iOS Development profile；然后签名构建、安装到同一台 iPhone，记录 `cat /etc/resolv.conf`、`nslookup`、HTTPS GET 的命令、退出码和完整错误/状态。若 DNS 成功而 HTTPS 仍失败，再依据新证据研究代理/路由，不恢复未经证实的 `getaddrinfo` workaround。

## T64：2026-10-11 按 OpenMinis 补齐手机浏览器常用动作

- 目标：模型持续操作按当前对话保存的浏览器标签；模型和 iSH 保持同一标签、权限及活动详情行为。此前核心标签池已由 D40/D41/T62 实现和真机验证，本轮对照固定 OpenMinis 提交 `b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c` 后，聚焦仍缺少的常用网页操作。
- 上游证据：`src/ios/Agent/BrowserUse/BrowserUseActions.swift` 声明 `get_backbone`、`scroll_and_collect`、`hover` 等动作；浏览器 tool definition 将 `tab_id` 用于连续调用同一标签。该快照也包含截图、任意 JS、Cookie、下载、UA/视口动作，但它们需要 OpenMuse 尚无的多模态工具响应或安全的凭证/文件数据流。
- 变更：Core `PhoneBrowserActionRequest` 增加 `get_backbone`、`scroll_and_collect`、`hover` 和对应有界参数；iOS WKWebView 执行结构提取、连续页面滚动/去重采集和悬停事件；模型 schema、活动步骤标题、iSH `openmuse-browser-use` 参数与帮助同步。三个动作使用既有每对话标签池，无逐次审批，输入、返回值/错误、状态、设备和耗时继续写入现有活动操作详情。
- 约束：结构深度1–8、树节点最多120；采集1–20次滚动、最多40条、最大等待15秒；selector 与文本参数有字节上限。公开页面仍是不可信内容，顶层 URL 继续限公开 HTTPS；现有密码字段与可识别高影响点击限制不变。
- 验证：`swift test --filter PhoneSandboxRuntimeTests`：8/8通过；完整 Core 回归235项中233通过、2项因未配置实时 Tailscale 端点跳过、0失败；iOS Simulator Debug 与 iPhone ARM64 unsigned Debug `xcodebuild` 均成功，日志分别为 `.build/logs/openmuse-browser-parity-build.log` 与 `.build/logs/openmuse-browser-parity-device-unsigned-build.log`。构建有现存 `WKProcessPool` 弃用与资源脚本重复运行 warning，无新增编译错误。Core 测试覆盖动作解析和边界，不执行 WKWebView JavaScript。
- 未验收与后续：T64 版本尚未签名安装 iPhone；三个新增动作没有真机网页与活动 UI 证据。当前浏览器签名安装仍受 T63 记录的 Xcode `No Accounts`/缺 profile 阻塞。截图回传、下载、任意 JS、Cookie、UA 和视口动作仍未覆盖；Cookie/JS 不可仅照搬，需先验证具体权限边界，截图要先支持模型多模态工具结果，下载要进入受限会话工作区或构件存储。详见 [D42](DECISIONS.md)、[讨论 T64](DISCUSSIONS.md) 与 [OpenMinis 对照](OPENMINIS_PHONE_RUNTIME_COMPARISON_2026-10-11.md)。

## T65：2026-10-11 聊天输入条垂直对齐

- 需求：用户指出 iPhone 输入框内的加号与“说说你在想什么…”占位文字没有视觉居中，要求对照其他 App 小幅调整。
- 参考：用 iPhone Use 在同一台手机实看 Muse 与 OpenMuse 的键盘态。Muse 的加号、占位文字和语音按钮在固定高度胶囊内共用垂直中心；OpenMuse 之前将 HStack 设为 bottom alignment，发送按钮外层的对称内边距抬高了 HStack 高度，导致另外两项相对胶囊中心偏低。
- 变更：聊天输入 HStack 改为 center alignment，让加号、文本框和发送/停止按钮以视觉容器中心对齐；单行输入不再沿用底边对齐，多行字段继续自然增高。
- 验证：iPhone 17 Pro / iOS 26.5 模拟器 UI 测试 `testComposerResourceEntryAndKeyboardHideBottomTabs` 通过；新增断言要求加号、占位文字和发送按钮的可访问性中心坐标相差不超过 1.5pt。iPhone ARM64 unsigned Debug 与 Mac Debug 构建通过，日志 `.build/logs/openmuse-browser-parity-final-device-unsigned.log`、`.build/logs/openmuse-browser-parity-final-mac-build.log`；UI 结果包 `.build/OpenMuseComposerAlignment.xcresult`。浏览器改动后的 Core 全回归235项中233通过、2项条件跳过、0失败，日志 `.build/logs/openmuse-browser-parity-final-swift-test.log`。新代码未装到真机：签名构建仍提示 Xcode `No Accounts` 且找不到 `org.openmuse.ios` profile，日志 `.build/logs/openmuse-browser-parity-device-signed-build.log`。Muse 与旧版 OpenMuse 原始截图分别为 `20261011T134508323099Z-7d8af4b1.jpg`、`20261011T134514897056Z-d224f3c0.jpg`，留在 iPhone Use 本机 artifact 目录，没有复制到仓库。
- 边界：本轮只调整聊天输入条对齐，不改输入/发送逻辑、键盘时 Tab 隐藏或附件行为。


## T66：2026-10-11 Mac Pi 实时活动与 iPhone 真机部署

- Mac 活动：配对桥接新增认证的 `v1/chat-events` 游标短轮询端点，Mac 保留任务/检查点的持久写入者身份；iPhone 在 Mac 持有任务期间以内存状态展示收到的工具事件，最终结果仍走已有同步与 owner 交还。Mac 每5秒发心跳，连续3次轮询没有新鲜心跳时手机显示等待状态。活动事件只允许当前配对设备读取。
- 验证：全量 `swift test` 执行236项，234通过、2项因实时 Tailscale/Pi 地址未配置条件跳过、0失败；新增 bridge 集成测试确认 Pi 回复仍阻塞时手机已收到工具事件、心跳可见，另一配对设备无法读取该活动。Mac Debug、iOS Simulator Debug、iPhone ARM64 Debug 构建均通过；输入条 UI 测试在 iPhone 17 Pro / iOS 26.5 模拟器通过，日志 `.build/logs/openmuse-t66-mac-build.log`、`.build/logs/openmuse-t66-ios-build.log`、`.build/logs/openmuse-t66-device-unsigned-build.log`、`.build/logs/openmuse-t66-composer-ui-test.log`。
- 真机部署：目标为 iPhone 15 Pro Max / iOS 27.2。Xcode 自动签名因当前 Account 服务报 `No Accounts` 失败；改用本机仍有效、包含该设备且 App ID 匹配的 Personal Team profile 和本机 Apple Development 身份手动签名。`codesign --verify --deep --strict` 通过，`devicectl` 安装并启动成功，设备端确认 `org.openmuse.ios` 为 0.1.0 (3)；Phone Use READY 显示 OpenMuse 前台主聊天可读。安装与签名证据 `.build/logs/openmuse-t66-device-install-verify.log`，安装包 `.build/OpenMuse-T66-iphone-signed-v2.app`。
- 有效期与边界：当前 Personal Team profile 于2026-10-18到期，之后需用续期 profile 重签并重装。真机本轮只验安装、启动和前台页面；没有从手机发起远端 Pi 任务，因此新增事件流/心跳仍只有 Core 集成测试证据；蜂窝接管、断线续跑及 iSH DNS 不在本次部署验收内。此前安装数据仍可见；没有重新测试模型 API。
- 签名诊断日志 `.build/logs/openmuse-t66-device-signed-build.log` 与 `.build/logs/openmuse-t66-device-manual-signed-build.log` 保留了 Xcode Account/profile 失败及手动 profile 被 Xcode managed 标记拒绝的原始记录；未更改 Xcode 账号设置，也未触碰其他项目。

## T67：2026-10-11 iSH guest DNS/HTTPS 真机验收与 Mac 接管预检

- 真机与版本：iPhone 15 Pro Max / iOS 27.2，`org.openmuse.ios` 0.1.0 Build 3；Phone Use READY 显示 OpenMuse 前台，`devicectl device info apps` 确认安装路径为 `OpenMuse-T66-iphone-signed-v2.app`。当前源码目录中除文档外，没有比 Build 3 可执行文件更新的应用源码；T64 浏览器动作已随该构建安装，但没有在本轮逐项执行新动作。
- 网络操作：手机活动详情中有三条真实 iSH 调用。`call_00_hRTNhMXOZWzd1hcY2I620461` 执行 `cat /etc/resolv.conf`，输出 `nameserver 198.18.0.2`，退出码0；`call_00_ODPHBufAp56LuVjbtBam4272` 执行 `nslookup example.com`，由 `198.18.0.2` 返回 `198.18.0.45`，退出码0；`call_00_uCNzwV7XUpj0FM0Pd4406337` 执行 `wget -S -O /dev/null --timeout=15 https://example.com/`，返回 `HTTP/1.1 200 OK`、`Server: cloudflare`，下载577字节，退出码0，未截断且未超时。每次操作的工具名、调用编号、设备、参数和实际输出均在真机活动详情核对；私人截图只留在本机 iPhone Use artifact 区，未复制进仓库。细节记录在忽略目录 `.build/logs/openmuse-t67-iphone-ish-network-activity.log`。
- 结论与限制：iSH guest 经当前 resolver/设备网络路径可以完成 HTTPS GET。返回的 `198.18.0.45` 属于 IANA IPv4 特殊用途注册表中的 Benchmarking 网段（`Globally Reachable=False`），因此这不是直连公网 DNS 的证明；通过本机 VPN/代理或合成地址转换层转发只是可能解释，具体路径未确定。[IANA IPv4 Special-Purpose Registry](https://www.iana.org/assignments/iana-ipv4-special-registry)。其他网络、DNS 路径变化、超时取消和强制终止恢复仍待验。
- Mac 接管预检：Mac OpenMuse 进程仍运行，`127.0.0.1:4388/health` 返回 HTTP 200。Mac Tailscale 原先为 Stopped；启动现有客户端后状态为 Running、健康列表为空，`tailscale serve status` 仍显示 tailnet-only `:8443/openmuse` 代理到 `127.0.0.1:4388`，443 根路由和 Funnel 未改。tailnet 当前没有在线移动设备，iPhone Use 的已安装 App 查询未找到 Tailscale，因此本轮不能验证真实 iPhone→Mac Pi 接管。该连接验收需要 iPhone Tailscale 客户端连入同一 tailnet；其他 iOS/Mac 实现和验证不受此阻塞。

## T68：2026-10-11 修复浏览器结构采集并部署 Build 4

- 修复：真实列表页上 `hover(selector="div.quote a")` 能命中元素，但 `scroll_and_collect` 返回空对象。`IOSPhoneBrowserRuntime` 将 IIFE 表达式直接传给 `WKWebView.callAsyncJavaScript`；该 API 要求匿名函数体，且无显式 `return` 时返回 `nil`。现改为显式 `return await` 并校验结构化字典，空结果转为明确动作错误，避免静默转换成 `{}`。依据：[Apple `callAsyncJavaScript` 文档](https://developer.apple.com/documentation/webkit/wkwebview/callasyncjavascript%28_%3Aarguments%3Ain%3Acontentworld%3A%29)。
- 回归与构建：`swift test` 执行236项，234通过、2项因实时 Tailscale/Pi 地址未配置条件跳过、0失败；iOS Simulator Debug 与 iPhone ARM64 unsigned Debug 构建成功。真机构建复用了 Ninja 检查为无需重建的忽略目录 iSH 产物；未改全局工具链。一次并行构建因同一 DerivedData 数据库锁定失败，随后停止重复构建并等首个构建完成；成功的 device build 日志为 `.build/logs/openmuse-t67-device-unsigned-build.log`，模拟器日志为 `.build/logs/openmuse-t67-simulator-build.log`，Core 日志为 `.build/logs/openmuse-t67-swift-test.log`。
- 签名与部署：Build 4 用本机有效 Personal Team profile 手动签名。首次安装包启动时，`dyld` 报缺少 `OpenMuse.debug.dylib` 签名；为 `OpenMuse.debug.dylib` 与 `__preview.dylib` 单独签名后重签 App，`codesign --verify --deep --strict` 通过。最终 `org.openmuse.ios` 0.1.0 Build 4 安装到 iPhone 15 Pro Max / iOS 27.2，`devicectl` 确认安装版本，PUA 确认 OpenMuse 前台并保留原对话。签名包 `.build/OpenMuse-T68-iphone-signed-v1.app`；安装与启动日志 `.build/logs/openmuse-t68-device-install-signed.log`、`.build/logs/openmuse-t68-device-launch-signed.log`；首次签名缺项的诊断见 `.build/logs/openmuse-t68-device-console-launch.log`。Personal Team profile 将于2026-10-18到期。
- 真机模型验收：在现有 `tab_id=1` 的 `quotes.toscrape.com` 上，Build 4 的真实 DeepSeek 回合依次执行 `get_backbone(max_depth=4)`、`scroll_and_collect(direction=down, scroll_count=3, amount=600, item_selector="div.quote", timeout=10)`、`hover(selector="div.quote a")`。模型显示结构树含引用、作者和作者链接；采集返回10条，`scrollPosition=126`、`scrollSteps=1`、`totalItemsSeen=20`；hover 命中爱因斯坦作者链接且未导航。`scroll_and_collect` 返回体没有截断字段，所以只把10条记为实际返回量，不推断页面全量或 `totalItemsSeen` 的计数口径。该轮显式等待 DOM 稳定，未隔离等待与显式返回修复各自对先前 `{}` 的贡献。私密屏幕截图仍留在本机 iPhone Use artifacts。
- 仍未完成：Mac tailnet 中没有在线移动设备，iPhone→Mac Pi 真接管仍未验；guest 超时/强制终止恢复、锁屏续跑、其他网络 DNS/HTTPS、Cookie/localStorage 跨重启和全页采集边界继续列为未验。

## T69：2026-10-11 复核聊天输入条垂直对齐

- 需求：用户再次反馈加号和占位文字在输入框内看起来未居中，要求对照其他 App 微调。
- 参考：遵循 `docs/muse-research/SCREENSHOT_GUIDE.md`，实际查看本地 Muse 键盘截图并在同一台 iPhone 15 Pro Max 打开 Muse 与 OpenMuse 的键盘态。Muse 输入胶囊的加号、占位文字和语音入口共用中心线；Muse 的底栏在键盘后方被遮挡。OpenMuse 保留用户先前明确要求的键盘态隐藏底栏行为。
- 结论：本机 OpenMuse 已安装 0.1.0 (4)，包含 T65 的垂直居中修复。当前真机 PUA 观察 `b1cfb82c324a` 中，加号、占位文字和发送按钮的可访问布局中心均为 y=522pt，键盘态五入口 Tab 不在界面树中，截图目测中心线一致；没有再加入无证据的像素偏移。
- 验证：iPhone 17 Pro / iOS 26.5 Simulator 的 `testComposerResourceEntryAndKeyboardHideBottomTabs` 通过，1 项、0 失败；结果 `.build/openmuse-composer-before.xcresult`，日志 `.build/logs/openmuse-composer-before.log`。真实设备安装版本由 `devicectl` 确认为 0.1.0 Build 4；真机截图 `20261011T152744145774Z-e084ac2a.jpg` 与 Muse 键盘截图 `20261011T152122392987Z-4d0a754a.jpg` 仅留在本机 iPhone Use artifacts，未复制进仓库。
- 变更范围：本轮不改应用代码；将复核结论补入讨论记录。若当前 Build 4 仍可稳定看到字形偏移，再针对相同键盘状态检查胶囊边界、字形基线和实际截图，不凭空叠加 offset。

## T70：2026-10-12 USER、MEMORY、GLOBAL 记忆视图闭环

- 问题：SQLite 中已有结构化 `MemoryClaimRecord`，但自动投影只维护 `USER.md`；`MEMORY.md` 没有完整当前记忆账本，`GLOBAL.md` 也没有结构化导航索引。手动追加记忆还可能成为无来源的 Markdown 文本。
- 实现：`MemoryClaimRecord` 继续作为记忆事实的唯一结构化真值。`USER.md` 展示当前画像类别；`MEMORY.md` 展示所有有效 claim 及来源性质、日期、范围、可信度和有效期；`GLOBAL.md` 按主题链接到 MEMORY 条目。三个自动区域共用稳定 claim ID，保留各自区域外的手写正文。USER/MEMORY 中编辑条目会连同来源和三份文档修订在一个 SQLite 事务中保存；手动添加记忆改为创建 claim 与来源记录；遗忘后清理三份视图及对应文档修订历史。旧 USER 自动标记会迁移到新区域。损坏/缺失的本地 Markdown 副本在启动时从 SQLite 恢复。
- 文件边界：`SOUL.md` 仍使用独立的人格修订、告知与撤销流程；`HEARTBEAT.md` 仍呈现结构化主动计划。T70 没有把人格或计划混入用户记忆 claim。
- 验证：`swift test --filter MemoryDocumentProjectionTests` 执行4项、4通过；覆盖三种视图差异、过期过滤、手写内容保留、旧标记迁移、编辑后跨视图更新、遗忘及重启恢复。`swift test --filter WorkspacePersistenceTests` 执行102项、100通过、2项因未设置实时 Pi/Tailscale 地址而跳过、0失败；原子遗忘调整后又重跑记忆视图4项及 `testForgetMemoryClaimRemovesProjectionHistoryAndKeepsSourceChat`，5项通过。`git diff --check` 通过。iOS Simulator 和 macOS Debug 构建在原子遗忘小幅收紧前通过；收紧后的重建被另一份当前未跟踪源码 `Sources/OpenMuseCore/WorkspaceBackup.swift` 的编译错误挡住（`includeConversations` 未定义及 `Archive.count` 类型推断失败），该文件不属于本轮改动且未修改，因此当前不能报告最终双端 target build 通过。
- 未验：本轮没有安装真机、在 App 中编辑文件或发送新模型请求；也未运行全量测试。Muse 未公开这些文件的数据库映射，故这是 OpenMuse 的实现方案，不声称复刻 Muse 内部实现。一般聊天事实抽取、通用冲突裁决与完整主动 dreaming 仍不由本轮补齐，状态沿用需求审计。

## T71：2026-10-12 重要资料随时备份、导出与恢复

- 需求：用户持续使用 OpenMuse；聊天、核心 Markdown、结构化记录和其他重要工作区文件都不能随意丢失，并且用户应能随时备份、导出。用户明确不需要专用加密，希望在自己允许时让其他 AI 读取；要求包含聊天与 USER.md 等全部相关文件，并支持定时备份和导入。
- 实现：新增[备份与恢复说明](BACKUP_RESTORE.md)，并在 PRD、双端文件关系和政策文档记录长期要求、内容边界、导入行为与系统限制。手动和定时操作生成标准未加密 ZIP，包中提供可读的所有工作区 Markdown 副本及完整、校验过的工作区恢复包；导入预览后合并，不静默覆盖。用户选择备份文件夹，可选 iCloud Drive；每天可选时间，默认 21:00、定时开关默认关闭。定时备份默认留存 7 份，可设 1–30 份。
- 防丢失边界：手动导出改用独立 `OpenMuse-Export-` 命名，永不参与定时轮换；自动清理只匹配 `OpenMuse-ScheduledBackup-` 文件，旧命名备份、用户其他文件和手动导出都保留。UI 明示凭证、设备运行环境与浏览器会话不在包内；用户手动导出的副本由用户自行管理，OpenMuse 的“忘记”不会删除它们。
- 验证：`swift test --filter WorkspaceBackupTests` 执行 5 项、5 通过；覆盖可读 Markdown、校验包读取、每日时间、定时轮换范围、定时写入会触发轮换及手动导出不会触发轮换。`swift test --filter WorkspacePersistenceTests.testWorkspaceArchiveRoundTripsChecksumsAndImportsIdempotently` 执行 1 项、1 通过。iOS Simulator target 与 macOS target 的通用 Debug 构建均成功。构建输出含既有未使用变量、WKProcessPool 弃用和构建脚本重复运行警告，无构建失败；`git diff --check` 通过。
- 未验：未在真实 iPhone 文件选择器向 iCloud Drive 写入/读取，也未验证锁屏时 iOS 实际获批的后台刷新次数、用户大包压力或损坏设备后的完整恢复。iOS 定时任务由系统调度，时间可能延迟或没有后台窗口；需要真机持续使用验证。完整范围和这些限制见[备份与恢复](BACKUP_RESTORE.md)。

## T72：2026-10-12 移除 DREAMS.md 核心文件方案

- 结论：不新增 `DREAMS.md`。OpenClaw 官方将它用作人类可读的 dreaming 日记与 Deep 阶段变更摘要，`MEMORY.md` 才是可晋升的精选长期记忆；该分工解释了 OpenClaw 为什么有两者，但 OpenMuse 的 `MaintenanceRunRecord` 已能以结构化、带来源证据的方式保存每次回顾，不需要另造一份可同步/可迁移的重复文件。Muse 内部机制没有公开，不能宣称对齐到其内部文件映射。
- 实现：保留可选 `reflection` 与 `reflectionEvidence` 字段在结构化运行记录中；设置页说明反思和长期记忆/人格的不同写入路径。移除 `DREAMS.md` 的核心文件、日记投影测试及归档/遗忘分支假设。回顾记录在包含聊天的迁移包随结构化记录迁移；不含聊天的迁移包省略私密回顾运行。遗忘来源会删除相关运行记录及修订。
- 文档：更新 [MEMORY_STORAGE](MEMORY_STORAGE.md)、[PRD](PRD.md)、[PHASE1_PARITY](PHASE1_PARITY.md)、[机制对照](MEMORY_RUNTIME_COMPARISON_2026-10-11.md)、[研究更新](muse-research/UPDATES.md) 与讨论索引 T72。
- 验证：`swift test --filter DreamingReviewTests` 执行21项、21通过、0失败；覆盖反思原话验证、记录来源约束、旧记录解码、含聊天归档保留反思、不含聊天省略私密记录、遗忘清理和同步载荷。`git diff --check` 通过。没有运行完整测试、双端构建或真机回归；本轮改动未触及其他平台特定代码。
- 未完成：反思记录目前身份页只展示最近三次；更深的历史浏览、导出、跨周主题巩固、模型采纳反馈和后续行为效果评价尚无专门 UX/实现。该方案不声称 dreaming 闭环已完成。

## T80：2026-10-12 主聊连续性、活动标题与身份页可读性

- 需求与参考：用户反馈侧栏出现多个主聊天、活动记录都叫“继续聊一聊”、Dreaming 设置拥挤，并询问“已确认记忆”与 `MEMORY.md` 是否重复。对照本机 Muse 截图，确认可见层面将主要聊天与旁聊分区；活动列表用具体任务标题，阶段作为说明。截图只能证明界面呈现，不能推断 Muse 的内部数据或标题算法。Muse 原图留在忽略目录，不进公开仓库；本轮 OpenMuse Dreaming 模拟器截图保存在 `.research-local/openmuse-device/2026-10-12/T80-dreaming-settings.png`。
- 根因：OpenMuse 将每个无父会话都放进“聊天”分组，“新对话”新建根会话；普通回复的活动标题无目标时固定回退到“继续聊一聊”。Dreaming 同时平铺计划细项，窄屏下时间与长标签挤在一起。记忆列表未说明自己是结构化记录的管理界面，也未说明三个 Markdown 视图的差异。
- 实现：增加向后兼容的可选主聊/归档标记。启动和同步后确定唯一主聊，将旧本地根会话消息按时间归并，迁移消息附件、目标、构件、活动和任务执行的会话关联；旧会话行保留为隐藏迁移痕迹。旁聊继续独立、重新挂在主聊下；导入的 AI 聊天不参与合并。若旧会话在另一设备迟到同步消息或旁聊，加载时再次归并。侧栏只显示一个“主聊”和旁聊，打开主聊回到同一条记录。
- 活动：新活动关联来源消息 ID；标题优先采用目标名，否则从用户请求提取不超过28字的标题，状态与阶段仍单独显示。升级时仅对同一非导入会话中一分钟内且尚未关联的用户请求回填旧通用标题；找不到可靠来源时保留原数据，不猜。
- Dreaming 与记忆：设置按说明、手动回顾、自动开关、计划预算和回顾记录分组；自动关闭时隐藏细项，历史记录折叠，时段使用定宽 `HH:00`，预算标签和值分开。身份页改为“当前记忆”，说明活跃 claim 列表包含过期/未生效项供调整并展示有效期；`MEMORY.md` 自动维护区只投影当前有效记录，`USER.md` 是当前用户画像，`GLOBAL.md` 是主题索引。它们是同一结构化真值的不同视图；更正写回同一记录，外部导入和推断先确认，修订保留来源。
- 验证：`swift test --scratch-path .build/core-test-final --filter ConversationContinuityTests` 执行3项、3通过，覆盖旧根会话、附件和关联数据迁移、旁聊与导入隔离、迟到同步归并、活动标题回填边界和标题截断。iPhone 17 Pro / iOS 26.5 Simulator 上目标 UI 用例分别通过：侧栏主聊/旁聊用例1/1，Dreaming 布局用例1/1；后一结果包 `.build/openmuse-t80-ui/Logs/Test/Test-OpenMuseiOS-2026.10.12_19-51-46-+0800.xcresult`。最终源码合并重跑时，模拟器在测试 runner 启动前卡黑屏；新模拟器重试停在 runner 调度阶段，均未作为通过结果。`git diff --check` 通过。
- Release：iOS ARM64 Release Archive 和 Personal Team 开发签名 IPA 导出成功，bundle `org.openmuse.ios`，版本 `0.1.0 (8)`；`codesign --verify --deep --strict` 通过，二进制确认 arm64。最新 IPA `.build/OpenMuse-T80-iOS-Release-final2/OpenMuse.ipa`，SHA-256 `7381c2b2dc3ec7ce3965c08f8581a348ac38576adf7f40823920c3817d1aa8f3`，大小9.6 MB；iOS Team Provisioning Profile 有2台设备名额、于2026-10-18到期。Archive/export 日志在 `.build/logs/openmuse-t80-ios-release-final2.log`、`.build/logs/openmuse-t80-ios-release-export-final3.log`。本轮未安装真机，未用用户实际 SQLite 执行迁移，也未复测模型请求；这些 UI/Core 结果不能代替安装后验收。完整需求仍以 PRD 和 [一期对照表](PHASE1_PARITY.md) 为准。
