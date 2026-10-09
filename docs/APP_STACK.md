# iOS 与 macOS 技术选型建议

日期：2026-10-10。状态：明确推荐，待用户确认；没有构建、原型或真机性能证据。本轮把早期框架比较收敛成默认路线。

## 推荐组合

| 层 | iOS | macOS |
|---|---|---|
| 界面 | Swift + SwiftUI 页面，UIKit 聊天列表与输入 | Swift + SwiftUI 页面，必要时 AppKit |
| 执行控制 | 原生 Swift agent 控制、模型与工具适配 | 固定版本 Pi，由独立 Node 子进程包装 |
| 辅助工具环境 | 参考 OpenMinis 的 iSH 集成；具体复用边界待验证 | Pi 工具经宿主权限与指定工作区访问本机 |
| 产品状态 | 共用 Swift 数据协议与存储模块 | 同一协议和模块，Pi 会话不作为唯一产品状态 |
| 数据 | 本地 SQLite；Markdown 通过统一版本事务编辑 | 同样本地 SQLite 与文件协议 |
| 同步 | CloudKit 私有记录为首选候选，附件候选 iCloud Drive | 使用相同同步协议，不共享活跃数据库文件 |
| 凭证 | Keychain，默认不随普通文件同步 | Keychain，经受控适配向执行环境提供能力 |

CloudKit 方案尚受开发者账号、签名 entitlement、配额和真实设备验证约束。SQLite 包装库、最低 OS、Pi 通信模式和嵌入库版本不在没有验证前任意锁死。

## 如何参考 Lody

已核对上游 HEAD 仍为 e6b3176bbffffdf0dbba89c8ef92d04845423a96。

- [LodyChatView.swift](https://github.com/Innei/lody-ios/blob/e6b3176bbffffdf0dbba89c8ef92d04845423a96/apps/mobile/modules/lody-kit/ios/Chat/LodyChatView.swift) 的开头显示 UIKit UICollectionView 与 Expo 原生事件桥接。
- [ChatComposerView.swift](https://github.com/Innei/lody-ios/blob/e6b3176bbffffdf0dbba89c8ef92d04845423a96/apps/mobile/modules/lody-kit/ios/Chat/ChatComposerView.swift) 显示原生输入、草稿和队列状态结构。
- [NativeChat.tsx](https://github.com/Innei/lody-ios/blob/e6b3176bbffffdf0dbba89c8ef92d04845423a96/apps/mobile/modules/lody-kit/src/chat/NativeChat.tsx) 显示 JS 到原生视图的消息与输入属性桥接。

本次只查相关文件片段，未审计全部代码。研究启发是把长聊天、滚动锚点、流式文本、文本选择、键盘、输入和附件交互作为原生验收重点。可以借鉴 MarkdownView/Litext 类渲染方式，但具体依赖要另查许可证和兼容性。

Lody 的 RN/Expo 壳适合其迭代方式；OpenMuse 当前只有 Apple 双端且原生执行能力较多，因此推荐原生 Swift 作为默认。若未来要支持 Android/网页或现成组件复用显著节省成本，可重新评估 RN。直接搬移 Lody Swift 文件仍涉及 AGPL，不能因使用 Swift 就绕过许可证。

## Pi 和手机执行的边界

Mac 用 Pi 负责模型回合与工具事件；产品层负责人格、记忆、目标、维护运行和成果。通过版本化 RuntimeAdapter 传递命令、事件与取消，验证 Pi 可用接口后选择 RPC 或自有 SDK 包装；不能把任意 stdout 当可靠协议。进程重启、重复事件与工具失败不能丢产品状态。

iPhone 首选原生控制模型请求与任务，Linux 小环境执行脚本和文件工具。不会把 React Native 的 JS 运行时等同于可运行 Pi 的 Node 环境。Pi 在手机小环境中运行仍只是备选实验。

代价是双端执行适配器不同，需要同一组行为合约验收模型切换、工具失败、取消、目标状态和记忆提交。共用 Swift 状态层与跨运行时 JSON 协议，避免两份独立产品逻辑。跨平台 UI 复用减少，但权限、后台与 Apple 数据路径更集中。

## Muse 交互研究

产品交互初期直接以 Muse 的信息结构和操作流程为基准：连续聊天、侧聊、头像活动入口、目标、兴趣动态/点子、可编辑记忆与成果卡。具体导航、手势、过渡和编辑方式待实际查看后修订；不把纸面调研当作视觉验收。

用户已授权连接手机后使用 iPhone-use 查看 Muse。调研以页面导航和查看为主，记录入口、状态、手势、键盘与成果形态；发送测试对话、编辑记忆、开关任务或改变账号状态需有对应授权。真实页面可能包含私人内容，截图和原始观察留本地，不发布到公共库。

2026-10-10 已完成主要页面观察，以及单独授权的旅行、浏览器和构件工作流观察，见 [交互档案](muse-research/IOS_INTERACTIONS_2026-10-10.md)。尚未验证全部动作、首次引导或 OpenMuse 原型；双端原生 Swift 仍是待确认推荐。执行默认已调整为 Mac 在线 Pi 优先、离线手机接手，详见 ARCHITECTURE.md。

## 开工后的首批关卡

1. 同一合成旅行对话的长列表、流式输出、插话、键盘和草稿恢复。
2. 手机小环境构建、原生工具桥、独立模型请求与实际后台边界。
3. Mac Pi 进程启动、取消、恢复及权限边界。
4. 双端记忆修订、文件编辑、iCloud 冲突与导出迁移。
5. 实际模型和中国直连环境验收。

这些是未来验证范围，仍需完成方案确认与开工授权。原生路线是当前推荐，不写成用户已批准。

## 2026-10-10实现基线补充

界面按UI_SPEC和本地Muse证据；连接Tailscale，首轮RUNTIME_PROTOCOL直接同步本地记录/附件，iCloud按D28后接。Pi适配/小环境路径、供应商端点与依赖需在K01–K07固定和验证；不改Lody现有服务。原生Swift仍为本项目制定推荐，未把参考其本地RN客户端解释为必须复制RN。
