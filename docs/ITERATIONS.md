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
