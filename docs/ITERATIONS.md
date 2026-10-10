# 迭代记录

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
