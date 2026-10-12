# 双端连接、同步与接管协议 v1

2026-10-10。Tailscale路线由用户确定；以下具体协议是本轮设计基线，未经设备验证。独立OpenMuse服务，不复用现有Lody端口、Token或运行状态。

## 连接

首轮使用独立Tailscale客户端：手机、Mac进入同一tailnet，Mac服务监听loopback，经Tailscale Serve发布HTTPS入口。连接界面填写/扫描地址、一次性配对码；Mac本地确认新设备，换取可撤销的设备凭证保存在Keychain。配对码五分钟有效、一次使用，尝试限流；网络身份不替代应用授权。初始状态校验协议版本、workspaceId、设备与工具能力。WebSocket传事件，REST补快照和附件；游标过期重取快照。

一期不把服务发布为公网Funnel。用户选择Tailscale不等于授权修改本机现有入口。Tailscale提供组网/可能的中继，不运行我们的agent。手机其他VPN可能影响路由，须在实际蜂窝与Wi-Fi上验证；不可达时手机独立用。参考[官方Serve说明](https://tailscale.com/docs/features/tailscale-serve)，查阅2026-10-10。

本地Lody参考：SELF_HOSTED的loopback+Serve+配对；bridge/src/config.mjs的项目范围；server.mjs的Bearer认证/bootstrap；mobile/src/local/bridge.ts的HTTPS/WebSocket和连接状态。当前HEAD为2ebdcdbce7d43cae00770c295c020a832d404960，工作区有未提交修改，不能把所读文件全部归于该commit；具体哈希保存在本地研究manifest。仅借鉴协议，不复制私有代码或其凭证；未启动/重启/修改Lody或Tailscale。

## 首轮已实现的连接切片（2026-10-10）

Mac App 打开时，OpenMuse 服务绑定 `127.0.0.1:4388`；iPhone 不直接访问局域网端口。Mac 设置页可为独立的 Tailscale Serve 入口启用 HTTPS `8443`、`/openmuse`，转发到该 loopback 服务。现有 `443` 路由不复用；8443 已有配置时拒绝覆盖；设置代码会比较其他端口路由，只有确认既有路由保持一致才报告成功。此专用端口通过 Serve 建立，不调用 Funnel。Tailscale Serve 可把本机服务限定在同一 tailnet，Funnel 才会把服务发布到公网；具体端口和 path 仍须用真实客户端验证。[Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve) 与 [Serve CLI](https://tailscale.com/docs/reference/tailscale-cli/serve)，查阅2026-10-10。

配对码由 Mac 生成，8位、5分钟有效、成功一次后失效，最多尝试5次。配对凭证由两端分别存入钥匙串；Mac 端可以撤销已配对设备。iPhone 连接时校验 HTTPS 端点；远程主机限定为 Tailscale `.ts.net` 域名，本地 HTTP 仅用于 loopback 测试。请求正文限长并限制消息角色。Mac 服务只在 App 运行期间可用。

当前 iPhone 主聊可在设备直连模型与 Mac Pi 之间选择；Mac 在线且配对成功时，手机同步任务/检查点并按 epoch 转交 owner，Mac 执行后写检查点、交还手机，再由手机保存最终回复。Mac 不可达时在交接前可回退手机模型；交接后状态不明时不并行重试。工作区结构化记录与附件可通过认证通道同步；TXT/Markdown/PDF 附件二进制端点校验登记 ID、大小和 SHA-256。iPhone 已提供按意图开放的只读网页搜索/读取；它不需要逐次审批，明确离线时不开放，搜索词只带必要公开关键词。iSH 仅在用户明确要求命令时开放，首用逐条展示并确认，可选择单次或当前对话授权；正式资料写入仍逐项确认。Mac 桥接新增 `v1/chat-events` 有序事件短轮询与5秒心跳：手机按游标读取当前 Pi 工具活动，当前会话临时呈现，最终同步仍由 Mac 检查点和手机接回流程持久化；Core bridge 测试覆盖回复结束前事件可见、心跳和跨配对设备隔离。仍无崩溃续跑或离线分支自动选择，真实 iPhone→Mac Pi 任务待真机验收；iPhone 的写入目前仅限当前对话隔离临时区，没有对共享/外部资料的写入工具。不能把“Mac 已回复”说成“Pi 已操作电脑”。配对、凭证撤销、owner 交接、Pi 检查点、附件传输和在线取消都有合成集成测试；T54 已用真机验证手机本机网页查询，蜂窝接管与其他跨网络能力仍待设备验收。

2026-10-10 补充验收：本机 `/health` 返回200；Mac 上普通 `curl`、绕过代理的 `curl`、强制解析到 tailnet IP 的 `curl` 访问 Tailscale HTTPS 8443 都返回200，证书校验结果为0；443既有根路由仍指向本地4387，Funnel仅保留在443。OpenMuse 的 Swift `URLSession` 对相同 HTTPS 地址自测失败并报告 SecureTransport `-9816`。Apple 将此码定义为 `errSSLClosedNoNotify`，即服务端关闭会话但未发送关闭通知；它本身不代表证书校验失败。[Apple 错误码说明](https://developer.apple.com/documentation/security/errsslclosednonotify)。关闭系统HTTP/SOCKS代理也不改变结果，因此当时根因未定位。不要用HTTP、关闭TLS校验或更改现有VPN/DNS配置来掩盖失败。

2026-10-11 iPhone 真机补充：iPhone 16 Pro 上的 Tailscale 已连接到与 Mac 相同的 tailnet，设备列表显示 Mac 在线；Safari 通过 HTTPS 访问专用 `8443 /openmuse/health` 得到 HTTP 200 和 `OpenMuse Mac` 响应。该结果证明当前 iPhone 网络下的 Tailscale DNS、TLS 与 Serve 路由可达；没有证明蜂窝网络外出路径、OpenMuse App 配对凭证、资料同步或 Pi 任务接管。Mac 的 `443` Funnel 路由未修改；OpenMuse 的 `8443 /openmuse` 仍为 tailnet-only。旧 Swift `URLSession` `-9816` 对照问题尚未在这轮重新定位，实际 iPhone Safari 成功也不等于桥接客户端已通过。

2026-10-10 后续客户端修复：排查后发现显式设置多个 `HTTPEnable/HTTPSEnable/SOCKSEnable = 0` 代理标志会导致 `URLSession` 自连接失败；将 `connectionProxyDictionary` 设为空字典后，同一路由的 `URLSession` 健康检查返回 HTTP 200，Tailscale 私有 HTTPS Serve 路由测试通过。T14 的客户端失败描述保留为修复前记录。以上只验证 Mac 访问自身路由；iPhone 仍离线，跨设备验收未完成。`swift test` 本轮 17 项通过、0 失败、0 跳过，详见 [ITERATIONS](ITERATIONS.md)。

## 数据同步：一期本地为主

iCloud可后接（用户允许）。两端SQLite+工作区，连接Mac时通过相同认证通道交换不可变变更和内容寻址附件；Mac断开后均可本地提交，重连合并。同步操作与任务执行分离，手机同步不依赖Pi运行。Mac离线而两端不能连接时，不承诺变更即时互达；在已同步资料上工作，标明待同步。手动迁移包是备用，不替代自动合并。

事件信封：schemaVersion、eventId(UUID)、workspaceId、deviceId、deviceSeq、objectId、baseRevision、parentRevisionIds、kind、payloadHash、payload、createdAt。服务持久化后ACK；相同eventId同内容重复ACK，不同内容拒绝。每设备连续序号与缺口补拉，不把单个时间戳当共同游标。会话消息、事实、文档、目标、目标进展事件、计划、构件、反馈共用协议；凭证不进同步。进展事件保留来源消息与步骤，事件写入和对应目标修订在同一设备本地事务提交。

合并：同基线并发编辑保留双方；明确纠正压过未确认推断；相互矛盾的两条明确事实进入待核对。自由Markdown保留冲突副本；用户选择后新增修订。删除标记优先于旧重放，详见POLICIES。附件先上传暂存、校验hash/大小再提交引用；未下载给占位，失败重试不产生成功成果。内容块默认1MiB，单附件试用上限25MiB，较大资料提供手动导入；参数可调整。

## 执行

Task：taskId、goalId、conversationId、constraintRevision、requiredCapabilities、status、runEpoch、ownerDeviceId、lastCommittedCheckpointId。Attempt/Step：attemptId、stepId、idempotencyKey、inputRevision、effectClass、status、outputRefs。状态为queued/running/waiting_user/waiting_device/suspended/completed/failed/cancelled。

手机发起任务先落本地；Mac连通且接受任务时明确确认owner与epoch，再执行。心跳建议10秒，连续30秒无响应标为连接不确定，仅表示失联，不证明Mac已停。每个有意义工具步骤后保存输入版本、工具结果、可携带附件与下一步；ACK丢失靠稳定ID查询，不重复发送新任务。

接管分两种：①双方连通：旧端停止并提交检查点、释放执行权；新端确认后递增epoch运行。②失联：手机可从检查点开启只读/可重建步骤的分支尝试；Mac可能仍在运行，不能声称单执行。两端候选结果分别保留，重连核对约束版本和步骤ID后选一个进入正式成果，另一分支可查看，不重复写目标时间线。自动维护成果在失联期间仅本地草稿，不进行不可逆共享提交。此方案允许重复只读计算及费用，需用户可见。

不可幂等外部动作首期不自动执行或接管。Mac本地文件修改也算副作用，失联等待执行权确认，不盲目重做；指定工作区生成不可变新成果除外。任何结果提交须检查暂停/取消/遗忘/约束版本，过期结果不得变成当前事实。取消先在发起端生效；在线且配对的 Mac 会收到经设备身份校验的取消请求并取消同一请求 ID 的 Pi 任务。若取消请求先于聊天到达，Mac 会短暂登记取消意图并阻止 Pi 启动；Mac 离线时仍标为待确认，不能承诺断网状态的远端动作已停止。重连先传播撤销再接续工作。

能力：手机由 Swift Agent Runtime 通过 OpenAI-compatible tool loop 执行本机历史消息、目标和七份核心 Markdown 文件的受限读取；另有按对话隔离的本机持久工作区，允许列出/读取/写入 md/txt/json/csv，单文件不超过 256 KB、每对话最多 80 个/16 MB，旧版缓存会迁入且不自动清理。模型每次最多可提议写入 8 KB；宿主先无副作用预检，再显示完整相对路径、创建/替换状态和正文，用户逐次批准后才写入，并在写前核对目标指纹。拒绝回传模型并阻止写入；取消和 App 重启会废弃待批请求，不恢复执行。活动记录不含正文。工作区不写入长期记忆、资源库、双端同步或 OpenMuse 迁移包。手机模型仍通过用户配置的 API 运行，这不代表模型权重在手机本地。iPhone 另接入 iSH/Alpine ARM64 guest；每条 shell 命令必须逐次批准，最长45秒、输出最多12 KB，guest 只挂载当前对话的 workspace/offloads/browser 可写目录和 attachments 只读快照，并可访问网络、修改私有 rootfs。iSH 与 App 共进程，不宣传为 VM 强隔离；超时停止失败时禁用当前运行环境。Mac Pi 仍只有用户授权目录的只读文本文件工具。浏览器/电脑操作必须由实际能力声明提供，不能按设备名假设可用。远程 API 不直接暴露原始 shell；Mac 在线优先 Pi 的路由不变。native offload、后台续跑和自动双端工作区同步仍未验收。完整手机执行设计和权限边界见 [ON_DEVICE_RUNTIME](ON_DEVICE_RUNTIME.md)。

2026-10-10 Core 实现切片：`TaskExecutionRecord` 与 `TaskCheckpointRecord` 作为独立于界面活动记录的结构化对象，进入本地 SQLite、修订和同步 outbox，也可随含聊天的工作区迁移包导出。领取与恢复使用 `expectedEpoch` 比较交换；任务步结果和恢复指针在一个事务中提交；稳定幂等键重复写入同内容时返回原检查点，冲突内容会拒绝；明确交接要求当前所有者持有最新检查点并递增 epoch，旧 epoch 不能再写入。失联续跑另建分支，保留原运行状态，不宣称原设备已停止。Core 合成测试覆盖领取、检查点、重放、交接、分支和迟到结果拒绝。

2026-10-10 后续实现已将 Mac 委派接入 execution-task owner 交接：iPhone 先同步任务和最新检查点，再将任务按 epoch 转交 Mac；Mac 确认收到后领取并执行，Pi 只读工具步骤写入 Mac 的活动记录与检查点，生成回复后再递增 epoch 把任务交还 iPhone。iPhone 拉取 Mac 检查点并重新领取，才保存最终回复。最终回复中的白名单工具事件仍作为兼容性回传，没有实时进度流。Mac 在模型不可用或执行失败时会在只读边界内归还任务；用户取消在线委派请求时，iPhone 通过独立认证请求通知 Mac，Mac 按配对设备身份限制取消范围，取消对应 Pi 子任务，并处理取消请求早于聊天请求的竞态。设备离线或连接在交接中断开时，不能确认远端状态，也没有自动候选分支、心跳或断线恢复；跨离线设备全局所有权、候选分支选择和外部副作用幂等仍未实现。

2026-10-10 后续实现：每次聊天从 iPhone 开始时建立本机 execution-task；Mac 在线且完成同步后，手机将该任务按 epoch 转交 Mac，Mac 领取任务、提交 Pi 步骤检查点，再把任务交还手机，手机重新领取后保存回复。Mac 不可达时在交接前回退手机模型；交接后若 Mac 明确失败，会归还任务后再尝试手机模型；若网络状态不明，则不启动可能重复的手机执行。App 启动只暂停本机 owner 的遗留运行，活动详情展示任务状态与最近检查点。系统提示列出本轮未提供的网页、邮件、预订、Mac 文件与浏览器工具，要求模型没有工具结果时不得声称已执行。本机双数据库桥接测试覆盖设备同步、epoch 转交、Mac Pi 检查点、交还、手机恢复和迟到 Mac 写入拒绝；远端取消测试覆盖身份隔离与竞态。Mac 构建和 iOS 模拟器 UI 套件通过，但没有任务详情专用 UI 自动化或真实蜂窝设备验证。

2026-10-11 真机补充：旧 `dist/OpenMuse.app` 未包含最新共享工作区身份实现，导致 iPhone 配对时报“Mac尚未提供共享工作区身份”。重建并重新打开 Mac App 后，iPhone 16 Pro 经 Tailscale 完成 App 配对。Mac 本机 `127.0.0.1:4388/health` 与 `8443/openmuse/health` 当前均返回 HTTP 200。首次工作区同步经再次同步后待发送/接收均为0，18项冲突仍待用户选择，双方内容保留。本次未验证蜂窝连接、冲突选择或真实 Mac Pi 任务交接；配对成功不代表任务接管成功。

2026-10-10 Mac Pi 只读文件切片：设置页通过系统文件夹选择器保存本机安全作用域书签；每轮任务只将该目录内深度不超过4、最多200个、总计不超过8 MiB 的 UTF-8 Markdown/TXT/JSON/JSONL/CSV/YAML 文件复制到临时快照，单文件最多128 KiB。Pi 使用随 App 打包的只读扩展，只开放列目录和读文件两个工具，并关闭内置工具、其他扩展、MCP、技能和上下文文件；工具路径拒绝绝对路径、越界、隐藏路径和符号链接。原始文件从不传给 Pi 进程，也不会被写回；每轮快照结束后清理。取消会终止 Pi 子进程，并把未完成的工具记录标成取消。仅在本机写入不含内容正文的 JSONL 工具记录，设置页可查阅/清除。

Core 测试覆盖快照边界、审计记录不含文件内容、Pi 子进程取消、Pi RPC 事件转发、活动/检查点顺序、配对通道事件返回、远端 owner epoch 交接、经身份校验的远程取消、附件二进制双向传输/删除，以及手机工作区写入的预检、逐次批准、拒绝阻断、取消废弃和重启后审批过期；iOS 模拟器 UI 测试验证待批准页显示路径与完整正文并可拒绝。Node 测试覆盖 Mac 只读工具路径与读取限制，并用本地合成 OpenAI-compatible 服务实测 Pi 调用只读工具后继续回复。T54 已真机验证 iPhone 本机只读网页搜索/读取；仍未验证真实文件夹选择授权/撤销的 Mac 界面、Mac 目录写入审批、Mac 浏览器/桌面操作、获批 iSH shell 与 guest DNS/网络命令、真实 iPhone→Mac Pi 实时事件/心跳、Mac 崩溃续跑。T54 不是远程桌面或 guest shell 网络验收。

## 验收

蜂窝连接家中Mac；拒绝错码/撤销设备；服务重启恢复游标；断网后手机继续只读步骤；Mac专属步骤等待；双方同时产出不重复正式目标进度；ACK丢失/重放/乱序；取消失联后再重连；文件未下载/冲突/删除传播。后台可执行机会单独实测，网络连通不代表iOS常驻。


## 2026-10-11 Mac Pi 工具事件短轮询与心跳

Mac 新增配对认证的 `v1/chat-events` 端点。请求受现有 workspace 与 paired-device 身份校验，并携带任务游标；服务仅返回该设备有权查看的任务事件。每个任务最多保留128条事件，单次最多返回8条；响应上限256 KiB，客户端请求超时8秒，空轮询等待后约800毫秒重试。Pi 工具事件以单调序号回传，iPhone 按游标去重，并将当前 Mac owner 执行中的步骤临时显示在活动详情。

Mac 每5秒生成活动心跳。iPhone 连续3次轮询观察不到更新心跳时把活动标为等待/连接不确定；这不表示 Mac 已停止。Mac 仍是活动步骤与检查点的持久写入者；手机端实时展示不直接创建正式步骤，最终同步和 owner 交还继续使用既有协议。结束任务的最终事件也仍进入检查点和工作区同步。

Core bridge 集成测试确认：Pi 回复仍被阻塞时，已产生的工具事件能先到手机；心跳会更新；其他配对设备不能读取该任务事件。尚未在真实 iPhone→Mac Pi 任务中验证轮询、Tailscale 断线后恢复、Mac 崩溃续跑或活动详情 UI 的实时刷新。短轮询与心跳不构成长任务持久运行保证。
