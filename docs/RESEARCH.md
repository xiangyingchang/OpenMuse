# 公开资料调研

查阅日期：2026-10-09。范围：官方产品说明、公开仓库 README、许可证、关键源码和 Apple 文档。没有读取用户的 Muse 账户、连接私人服务、构建参考项目或验证其宣传中的全部功能。

## Muse：产品参考

已阅读 [How We Designed Muse](https://introducing.muse.ai/) 与 [How We Built Safety Into Muse](https://security.muse.ai/)，并核对 [连接器文档](https://muse.ai/platform/docs)。官方描述的核心是持续主对话、侧聊、跨对话记忆、定时和事件驱动工作，以及活动、目标、点子与成果界面。

本文从这些原则推导 OpenMuse 的产品建议，不宣称还原闭源内部调度和记忆实现。原文示意图已取得链接；浏览器图片导航超时，因此没有完成逐屏视觉审查或真实 App 操作。最终视觉需另做交互稿和验收。

官方安全文章强调 agent 与权限和凭证边界的分离。对 OpenMuse 的启发是把授权状态做成确定的数据和控件，不仅依赖语言模型自觉。不能声称小团队首版等同其 VM、网络控制和安全体系。

## nanoMuse：完整产品与跨设备参考

[仓库](https://github.com/nano-muse/nanoMuse)，commit `903a8eafdf20b7d9d6f3f78351580993a325e3ee`。

已核对 README、LICENSE、iOS/隐私/本地运行/hub/sentinel 文档，抽查 Python 记忆、合并、目标、权限与 Swift scheduler。源码包含 SQLite 记忆及变更日志、目标和步骤、到期检查、授权记录与撤销；可参考恢复和可见状态。

它的手机部分基于 OpenMinis，桌面路线使用 DeepSeek Harness，不是本项目指定的 Pi。README 中跨设备能力不等于完全无服务器；其登录同步路线涉及 relay。隐私说明还区分模型调用、文本同步和数据控制，因此不能原样套用“所有数据不离设备”。

iOS scheduler 的注释和说明明确把后台执行视为系统授予的机会。对本项目有参考价值，但不能据此保证全天候准时执行。

## OpenMinis：手机内环境参考

[仓库](https://github.com/OpenMinis/OpenMinis)，commit `b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c`。

README 给出 Swift/SwiftUI iOS、iSH/Alpine 小环境、原生工具和自行配置模型路径。已抽查记忆工具及 BackgroundKeepAliveManager；后者组合了音频、定位和生命周期恢复，详见 [后台专项](IOS_BACKGROUND.md)。

这比“手机只是远端客户端”更符合用户修正。小环境与模型推理服务分开看：手机执行工具不等于离线大模型。上游完整构建依赖链较重；没有在本机编译，所以不能给出构建成功、性能或耗电结论。

## Lody iOS：原生交互参考

[仓库](https://github.com/Innei/lody-ios)，commit `e6b3176bbffffdf0dbba89c8ef92d04845423a96`。

核对 README、LICENSE、WebView runtime 文档，以及 DataRuntime 和 SessionBackgroundTasks。技术形态是 React Native/Expo 加较重 Swift 模块；聊天、输入和渲染使用原生能力。它不是纯 SwiftUI App。

可以借鉴 UIKit 消息列表、原生键盘和流式显示、本地显示缓存。Streams/Loro 和离屏 WebView 是服务其既有同步栈的选择，并非本项目使用 iCloud 必须照搬。其短后台额度不构成手机全天候执行。

## Pi：macOS 执行底座

原地址 badlogic/pi-mono 当前重定向到 [earendil-works/pi](https://github.com/earendil-works/pi)，commit `f1b2e77f5b13b2a199b1052cb79c235451afe7d7`。

已读 SDK、models、containerization 和 durable 文档。SDK 可接入会话、工具事件、排队与自定义模型；兼容 endpoint 和本地模型路径可配置。Pi 自身并不提供完整系统权限隔离；项目需要自己的工具边界。pi-durable 明确为实验性 API，需固定版本并验证恢复。

不把“有 SDK”当成已经做成目标、人格和推荐产品；这些是 OpenMuse 自己的产品层。

## 补充参考与命名

[CopilotKit/OpenMuse](https://github.com/CopilotKit/OpenMuse) 已有同名项目，README 描述个人 agent、任务和 rich results，并依赖其服务配置。这里只做 README 级补充阅读，未审查源码或采用其技术。记录名称冲突，当前按用户指定仍用 OpenMuse 工作名。

## 采用建议

| 参考 | 借鉴重点 | 不能直接推导 |
|---|---|---|
| Muse | 主对话、主动性、目标、点子、透明控制 | 闭源算法和公开说明的真实稳定性 |
| nanoMuse | 记忆变化、目标与跨设备状态 | 本项目不用 relay 也自动有相同协作 |
| OpenMinis | 手机环境与原生能力、增强后台 | 稳定全天候、耗电或本产品审核结果 |
| Lody iOS | 原生聊天、输入和缓存 | 必须照搬其 CRDT 或远端 runtime |
| Pi | macOS 模型与工具执行适配 | 自带产品记忆和系统级权限隔离 |

详细版本和抽查路径在 [SOURCES.json](SOURCES.json)。所有未实测项目保留为待验证；阶段建议属于本项目判断，不是上游承诺。

## 2026-10-10 专项补充

新增 [Muse 文件与记忆证据分层](MUSE_MEMORY_RESEARCH.md)：官方资料、用户提供的 SOUL 机制、来源未独立验证的社区归档、nanoMuse Android/Python 实现分别说明。没有发现官方公开完整记忆算法；据此提出原创的 [长期存储方案](MEMORY_STORAGE.md)，不是宣称复制了闭源服务端。
