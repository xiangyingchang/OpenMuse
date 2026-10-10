# 讨论与迭代索引

更新：2026-10-10。此页负责查找；确认事实见 DECISIONS，需求见 PRD，行为证据见 Muse 研究档案。历史不覆盖，后续按日期追加。以下为会话归纳，不是逐字完整聊天副本；私人信息不发布。

| 记录 | 讨论与修正 | 结果与查询 |
|---|---|---|
| T01 初始需求 | 开源、可换模型、Apple双端、终身陪伴 | D01–D10；PRD、APP_STACK |
| T02 运行方向 | 云端执行建议撤回；手机环境、iCloud；后明确Mac Pi优先 | D07、D16；ARCHITECTURE、IOS_BACKGROUND |
| T03 首聊与记忆 | 英语案例改为轻松旅行；核心文件必须可读、迭代、迁移 | D11–D14；ONBOARDING_TRAVEL、MEMORY_STORAGE、MEMORY_TRANSFER |
| T04 一期范围 | Muse交互与机制对齐；完整一期与内部里程碑分开；长期UU式桌面 | D15–D19；PHASE1_PARITY、ROADMAP |
| T05 真机研究 | 主要页面、浏览器启动/停止、旅行旁聊、目标进度、网页构件、头像与活动步骤 | muse-research/IOS_INTERACTIONS_2026-10-10.md第1–15节；原图只在本地INDEX |
| T06 2026-10-10 开工复查 | 用户要求先查未决项，所有讨论和迭代可查询；两本书设计原则，Muse风格 | DESIGN_PRINCIPLES、STARTUP_REVIEW；未授权应用实现 |
| T07 2026-10-10 记忆与接入 | 明确事实自动更新可撤销；外部提取/推断先确认；人格变更告知；QQ优先、Gmail后续；无付费开发者账号 | D20–D23；MEMORY_STORAGE；安装与iCloud门槛仍需处理 |
| T08 2026-10-10 双端关系 | 手机独立可用；Mac连接优先及专属任务；共享本地副本+iCloud；外出连接家中Mac首轮必须支持 | D24–D25；DEVICE_AND_FILES；连接方案待评估 |

## 每次讨论和交付的记录方式

1. 追加日期、问题、用户原意的简短归纳、建议、用户答案和仍未知部分。
2. 明确答案进入DECISIONS，保留稳定D编号；尚无答案放STARTUP_REVIEW，不伪装成默认批准。
3. 修改PRD及对应方案，注明替代哪条旧建议；需求关联验收ID。
4. 每次实现迭代追加ITERATIONS：范围、关联需求/决定、实际检查、结果与失败、剩余问题、提交或证据位置。
5. 私人反馈与截图留本地，公开记录用脱敏描述；Git保留文档版本，不存凭证。

查询入口：README → 本页 → 对应决定/需求/证据。精确旧版本可通过Git提交历史查询。

## T09：2026-10-10 文档复查

用户要求再审查并判断是否完整。本轮结论为需求覆盖基本齐全、完整一期实施定稿尚缺；修正当前过期状态，保留历史。完整差距和修订见[审查报告](DOCUMENT_REVIEW_2026-10-10.md)。没有新增产品决定或应用开工授权。

## T10：2026-10-10 六类缺口补齐

用户选择Tailscale参考本地Lody、无免费iCloud则后接、耗电后优化，并要求制定剩余规则、设计与任务。D27–D30登记明确选择；本轮具体方案入口STARTUP_REVIEW。公开不发布Lody私有源码/配置；原图仍本地。按新协议可审核状态替代T09当时“尚未制定”，真实能力仍待实现验证。

## T11：2026-10-10 明确开始双端实现

用户直接授权持续开发到可体验的 iOS/Mac App，提供公开仓库、目标、一期纵向闭环和交付清单；明确允许必要构建/测试/安装、项目内提交与推送。签名、模型密钥和设备本人操作等环境依赖仍分别验证；无凭证时先完成其他工作。跨端同步、Tailscale、后台接管不得以界面假象代替结果。详见D31与本轮[迭代记录](ITERATIONS.md)。

## T12：2026-10-10 首轮运行边界

首轮采用共享 Swift Package、XcodeGen 双端原生工程、本地 SQLite/Markdown 与按模型端点隔离的本机钥匙串密钥。Mac Pi 先只承担模型回合且关闭工具；在授权工作区、隔离、取消和日志完成前，不开放本机文件/命令工具。Mac Debug 与 iOS 模拟器已能启动；真机签名待用户登录 Xcode，真实模型对话待配置密钥。该执行限制是可逆实现选择，不缩小一期需求；详见 STARTUP_REVIEW 与 ITERATIONS。

## T13：2026-10-10 Mac 与 iPhone 的首轮连接

落实双端关系时，先实现了 Mac 私有配对和 Pi 聊天代理。连接使用独立 HTTPS 8443 `/openmuse` 路由、Mac loopback 服务、短期一次性码、钥匙串凭证和设备撤销；不复用 Lody 的端口或凭证。单元/集成测试已覆盖本机配对生命周期，但当前 tailnet 路由、真实模型调用和蜂窝真机还需验证。聊天桥接不代表工作区同步或 Mac 工具执行。

尚未解决的实现边界：要让 Pi 安全读写指定 Mac 文件并打开浏览器，需要确定沙箱方案、目录授权界面、审批/取消和副作用日志。当前首轮关闭 Pi 工具是安全默认；建议下一步只开放 OpenMuse 专属任务目录中的受限文件操作，再独立验证浏览器动作，绝不暴露任意 shell。此建议待后续讨论，暂不改变一期需求。

## T14：2026-10-10 Tailscale HTTPS 的 iPhone 验收风险

当前 Mac 的 Serve HTTPS 路由从 `curl` 可用，但相同路由的 Swift `URLSession` 自连接测试失败，错误码 `-9816`；本机 loopback HTTP 正常。尚无在线iPhone测试，因此根因未定。Tailscale公开问题[#19147](https://github.com/tailscale/tailscale/issues/19147)报告过iPhone无法打开 `.ts.net` Serve HTTPS；一位贡献者在其中将一组案例归因到第三方DoH/DNS覆盖，另有后续用户报告尚无解决方案。问题记录是排查线索，不证明OpenMuse或该手机存在相同问题。

2026-10-10 排查补充：Apple 将 SecureTransport `-9816` 定义为 `errSSLClosedNoNotify`（服务端关闭会话但未发送通知），它本身不表示证书校验失败。Mac 上普通、显式绕过代理、强制解析到 tailnet IP 的 `curl` 均返回 HTTP 200 且证书校验结果为0；进程环境没有代理变量。故排除“curl 只是经普通 HTTP 代理成功”的解释，但 `URLSession` 的差异仍未定位。Apple 错误码说明见[Secure Transport Result Codes](https://developer.apple.com/documentation/security/secure-transport-result-codes)及[`errSSLClosedNoNotify`](https://developer.apple.com/documentation/security/errsslclosednonotify)。iPhone 未连接，仍不能从 Mac 测试推断手机结果。

本轮不降级为明文、不跳过证书验证、不改动Shadowrocket/VPN/DNS。等iPhone解锁并连接Tailscale后，先测MagicDNS解析与Mac的HTTPS健康地址；若失败，再按设备日志判断要不要试独立网络配置，先回退、单变量验证。备选架构另行记录和讨论，不作为当前既定实现。

## T15：2026-10-10 Muse 前端交互对齐复查

用户要求对 code review 中的页面元素、文案和交互尽量贴近 Muse，并授权直接落地。本轮对照本地截图与交互档案，补齐 iPhone 侧栏/对话分组、头像陪伴者面板、活动步骤、滚动追新、可读构件和可操作的动态/点子页面；点子生成旁聊会关联来源目标。以上是首轮界面切片，不代表完整 V1c/V1d 的真实推荐、来源和反馈机制已完成。当前无新增产品决定；未完成交互继续按 UI_SPEC、PHASE1_PARITY 与 K12/K14 验收，真机、大字号/VoiceOver、逐页交互还需后续实测。实现与证据见本轮 ITERATIONS。
