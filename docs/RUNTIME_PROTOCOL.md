# 双端连接、同步与接管协议 v1

2026-10-10。Tailscale路线由用户确定；以下具体协议是本轮设计基线，未经设备验证。独立OpenMuse服务，不复用现有Lody端口、Token或运行状态。

## 连接

首轮使用独立Tailscale客户端：手机、Mac进入同一tailnet，Mac服务监听loopback，经Tailscale Serve发布HTTPS入口。连接界面填写/扫描地址、一次性配对码；Mac本地确认新设备，换取可撤销的设备凭证保存在Keychain。配对码五分钟有效、一次使用，尝试限流；网络身份不替代应用授权。初始状态校验协议版本、workspaceId、设备与工具能力。WebSocket传事件，REST补快照和附件；游标过期重取快照。

一期不把服务发布为公网Funnel。用户选择Tailscale不等于授权修改本机现有入口。Tailscale提供组网/可能的中继，不运行我们的agent。手机其他VPN可能影响路由，须在实际蜂窝与Wi-Fi上验证；不可达时手机独立用。参考[官方Serve说明](https://tailscale.com/docs/features/tailscale-serve)，查阅2026-10-10。

本地Lody参考：SELF_HOSTED的loopback+Serve+配对；bridge/src/config.mjs的项目范围；server.mjs的Bearer认证/bootstrap；mobile/src/local/bridge.ts的HTTPS/WebSocket和连接状态。当前HEAD为2ebdcdbce7d43cae00770c295c020a832d404960，工作区有未提交修改，不能把所读文件全部归于该commit；具体哈希保存在本地研究manifest。仅借鉴协议，不复制私有代码或其凭证；未启动/重启/修改Lody或Tailscale。

## 首轮已实现的连接切片（2026-10-10）

Mac App 打开时，OpenMuse 服务绑定 `127.0.0.1:4388`；iPhone 不直接访问局域网端口。Mac 设置页可为独立的 Tailscale Serve 入口启用 HTTPS `8443`、`/openmuse`，转发到该 loopback 服务。现有 `443` 路由不复用；8443 已有配置时拒绝覆盖；设置代码会比较其他端口路由，只有确认既有路由保持一致才报告成功。此专用端口通过 Serve 建立，不调用 Funnel。Tailscale Serve 可把本机服务限定在同一 tailnet，Funnel 才会把服务发布到公网；具体端口和 path 仍须用真实客户端验证。[Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve) 与 [Serve CLI](https://tailscale.com/docs/reference/tailscale-cli/serve)，查阅2026-10-10。

配对码由 Mac 生成，8位、5分钟有效、成功一次后失效，最多尝试5次。配对凭证由两端分别存入钥匙串；Mac 端可以撤销已配对设备。iPhone 连接时校验 HTTPS 端点；远程主机限定为 Tailscale `.ts.net` 域名，本地 HTTP 仅用于 loopback 测试。请求正文限长并限制消息角色。Mac 服务只在 App 运行期间可用。

当前桥接只把本轮聊天和相关资料交给 Mac 上配置的 Pi 模型；iPhone 本地保存对话。Mac不可达时，若iPhone配置了模型就回退到手机，否则明确报错。桥接不传输消息历史、目标、记忆修订、构件或附件，也不提供取消、文件/浏览器工具、检查点、后台常驻或完整任务接管。不能把“聊天已经由Mac回复”说成“Pi已操作电脑”。本地服务的配对、一次性码、重启后凭证继续有效、撤销拒绝和远程明文地址拒绝通过合成测试。

2026-10-10 补充验收：本机 `/health` 返回200；Mac 上普通 `curl`、绕过代理的 `curl`、强制解析到 tailnet IP 的 `curl` 访问 Tailscale HTTPS 8443 都返回200，证书校验结果为0；443既有根路由仍指向本地4387，Funnel仅保留在443。OpenMuse 的 Swift `URLSession` 对相同 HTTPS 地址自测失败并报告 SecureTransport `-9816`。Apple 将此码定义为 `errSSLClosedNoNotify`，即服务端关闭会话但未发送关闭通知；它本身不代表证书校验失败。[Apple 错误码说明](https://developer.apple.com/documentation/security/errsslclosednonotify)。关闭系统HTTP/SOCKS代理也不改变结果，因此当前根因未定位。Mac 的对照测试不能证明 iPhone 桥接可用；iPhone 尚未连入该 tailnet，仍须实测 DNS、HTTPS、配对和聊天。公开问题[#19147](https://github.com/tailscale/tailscale/issues/19147)有 iPhone 上 `.ts.net` Serve HTTPS失败的报告；其中一位贡献者把一组案例归因为第三方DNS/DoH影响，也有仍未解决的相似报告。此为社区报告而非本项目故障根因证据。不要用HTTP、关闭TLS校验或更改现有VPN/DNS配置来掩盖失败。

2026-10-10 后续客户端修复：排查后发现显式设置多个 `HTTPEnable/HTTPSEnable/SOCKSEnable = 0` 代理标志会导致 `URLSession` 自连接失败；将 `connectionProxyDictionary` 设为空字典后，同一路由的 `URLSession` 健康检查返回 HTTP 200，Tailscale 私有 HTTPS Serve 路由测试通过。T14 的客户端失败描述保留为修复前记录。以上只验证 Mac 访问自身路由；iPhone 仍离线，跨设备验收未完成。`swift test` 本轮 17 项通过、0 失败、0 跳过，详见 [ITERATIONS](ITERATIONS.md)。

## 数据同步：一期本地为主

iCloud可后接（用户允许）。两端SQLite+工作区，连接Mac时通过相同认证通道交换不可变变更和内容寻址附件；Mac断开后均可本地提交，重连合并。同步操作与任务执行分离，手机同步不依赖Pi运行。Mac离线而两端不能连接时，不承诺变更即时互达；在已同步资料上工作，标明待同步。手动迁移包是备用，不替代自动合并。

事件信封：schemaVersion、eventId(UUID)、workspaceId、deviceId、deviceSeq、objectId、baseRevision、parentRevisionIds、kind、payloadHash、payload、createdAt。服务持久化后ACK；相同eventId同内容重复ACK，不同内容拒绝。每设备连续序号与缺口补拉，不把单个时间戳当共同游标。会话消息、事实、文档、目标、计划、构件、反馈共用协议；凭证不进同步。

合并：同基线并发编辑保留双方；明确纠正压过未确认推断；相互矛盾的两条明确事实进入待核对。自由Markdown保留冲突副本；用户选择后新增修订。删除标记优先于旧重放，详见POLICIES。附件先上传暂存、校验hash/大小再提交引用；未下载给占位，失败重试不产生成功成果。内容块默认1MiB，单附件试用上限25MiB，较大资料提供手动导入；参数可调整。

## 执行

Task：taskId、goalId、conversationId、constraintRevision、requiredCapabilities、status、runEpoch、ownerDeviceId、lastCommittedCheckpointId。Attempt/Step：attemptId、stepId、idempotencyKey、inputRevision、effectClass、status、outputRefs。状态为queued/running/waiting_user/waiting_device/suspended/completed/failed/cancelled。

手机发起任务先落本地；Mac连通且接受任务时明确确认owner与epoch，再执行。心跳建议10秒，连续30秒无响应标为连接不确定，仅表示失联，不证明Mac已停。每个有意义工具步骤后保存输入版本、工具结果、可携带附件与下一步；ACK丢失靠稳定ID查询，不重复发送新任务。

接管分两种：①双方连通：旧端停止并提交检查点、释放执行权；新端确认后递增epoch运行。②失联：手机可从检查点开启只读/可重建步骤的分支尝试；Mac可能仍在运行，不能声称单执行。两端候选结果分别保留，重连核对约束版本和步骤ID后选一个进入正式成果，另一分支可查看，不重复写目标时间线。自动维护成果在失联期间仅本地草稿，不进行不可逆共享提交。此方案允许重复只读计算及费用，需用户可见。

不可幂等外部动作首期不自动执行或接管。Mac本地文件修改也算副作用，失联等待执行权确认，不盲目重做；指定工作区生成不可变新成果除外。任何结果提交须检查暂停/取消/遗忘/约束版本，过期结果不得变成当前事实。取消先本地生效，离线远端标待确认；不能承诺远端工具立刻停。重连先传播撤销再接续工作。

能力：手机文字模型、检索、已缓存资料与批准的文件工具；Mac增加Pi、授权本地文件与电脑工具。具体工具集由capabilities报告，不能按设备名假设有浏览器。请求与取消只针对批准工作区和任务，不把原始shell直接暴露为远程API。

## 验收

蜂窝连接家中Mac；拒绝错码/撤销设备；服务重启恢复游标；断网后手机继续只读步骤；Mac专属步骤等待；双方同时产出不重复正式目标进度；ACK丢失/重放/乱序；取消失联后再重连；文件未下载/冲突/删除传播。后台可执行机会单独实测，网络连通不代表iOS常驻。
