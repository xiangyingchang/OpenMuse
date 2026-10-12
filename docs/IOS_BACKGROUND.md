# OpenMinis 手机执行与后台专项

日期：2026-10-09。证据级别：官方文档与固定版本源码阅读；没有构建或真机实测。

## 用户要求与当前状态

### 2026-10-11：iSH 集成后的后台边界

用户已选择 iSH/Alpine 作为 iPhone 前台 guest 执行环境；真机 App 已签名安装并启动。该集成没有改变 iOS 后台限制：当前仍依赖系统给予的有限后台机会、保存 checkpoint，并允许下次打开后恢复；不承诺锁屏持续运行、强制退出后重启或准时唤醒。真机 shell 命令尚未验收，见 [T52](ITERATIONS.md)。

手机内有小运行环境，数据可 iCloud 同步；Mac 离线时仍希望持续工作。用户要求继续参考 OpenMinis。用户尚未明确接受仅前台执行，也未接受自建云端执行服务器。

不能用这个未决事项阻止当前文档和公开仓库交付；但不能在正式方案中声称已解决全天候执行。

## 上游实际机制

OpenMinis 的手机运行方式不只是后台保活。iOS 端在 App 内嵌入定制 iSH 内核与 Alpine aarch64 用户空间，Android 端才使用 PRoot；宿主 Agent 通过 tool calls 驱动 shell、会话工作区和原生工具 offload。详见固定快照的 [README](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/README.md)、[iOS 构建说明](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/BUILDING.md)、[iSH 运行摘要](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/docs/specs/ios-sandbox-ish-summary.md) 和 [ISHExecutionCoordinator.swift](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Agent/ISH/ISHExecutionCoordinator.swift)。

其 [BackgroundKeepAliveManager.swift](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Agent/Background/BackgroundKeepAliveManager.swift) 另外管理短后台额度、增强后台、后台讲话、音频和定位状态，以及活动显示和中断恢复。

- 普通后台额度通过 UIApplication 的后台任务管理，不是无限执行许可证。
- 增强路线使用 CoreLocation；权限与开关参与有效状态判断。
- 音频路线使用 AVAudioEngine 和循环静音 buffer；受后台讲话开关、活动会话和媒体中断状态控制。
- 代码处理音频会话被回收、媒体中断、重启尝试和前后台切换。
- Live Activity 与本地通知提供状态展示；展示存在不代表后台推理始终执行。

关键源码位置：能力分层在开头 21–45 行，增强状态判断约 91–101 行，静音播放条件约 1157 行，音频缓冲与循环约 1374–1396 行。行号固定到上方 commit，后续版本需复查。

沙箱执行侧由宿主串接模型工具和命令执行，`ISHExecutionCoordinator` 管理 shell 执行与会话上下文；每会话工作区、附件、offload 输出、browser 数据与共享 memory/skills 是不同挂载位置。原生桥把 guest 命令转到 EventKit、Photos、Vision、通知等框架，但每项能力仍受 iOS 授权与用途限制。Linux 工具目录不等于宿主容器访问权。

nanoMuse 的 [iOS scheduler](https://github.com/nano-muse/nanoMuse/blob/903a8eafdf20b7d9d6f3f78351580993a325e3ee/android/src/ios/NanoMuse/NanoMuseScheduler.swift) 有后台刷新请求、到期检查与打开 App 后补跑。它的 [iOS 说明](https://github.com/nano-muse/nanoMuse/blob/903a8eafdf20b7d9d6f3f78351580993a325e3ee/docs/ios.md) 明确后台刷新取决于 iOS 是否授予时间。

## 能力判断

可以作为延长已开始任务的工程参考；仅凭源码，不能保证锁屏数小时后新任务准时唤醒、用户强制退出后重启、系统回收后持续运行或服务等级。

Apple 的 [后台任务文档](https://developer.apple.com/documentation/BackgroundTasks/refreshing-and-maintaining-your-app-using-background-tasks) 和 [WWDC25 说明](https://developer.apple.com/videos/play/wwdc2025/227/) 需与实际系统版本一同评估。Continued Processing 适用于前台开始的持续工作，也不能直接替代任意时间的全天候 daemon。

[App Review Guidelines 2.5.4](https://developer.apple.com/app-store/review/guidelines/#software-requirements) 要求后台服务用于其预期用途。因此静音音频或定位延长执行对本产品的审核适用性待验证；某个上游已经发布不等于新 App 的相同用法必然通过。没有在此断言 OpenMinis 被拒绝或其机制完全无效。

## 建议的能力分层

1. 前台：手机独立推理与工具执行，Mac 无需在线。
2. 已启动长任务：保存进度，按系统允许机制继续，明确暂停和恢复状态。
3. 计划到期：本地通知由系统处理；需要推理的部分按实际后台运行机会执行。
4. 增强后台：研究 OpenMinis 音频、定位路线的任务条件、耗电、用户知情和分发约束，不默认为确定方案。
5. 无运行机会：保留到期和失败记录，返回前台后补跑；是否接受此产品边界仍待讨论。

## 开工后首个验证关卡

| 场景 | 必须记录 |
|---|---|
| 正常锁屏 5、30、120 分钟 | 实际运行时间、任务是否完成、恢复位置 |
| App 切走、系统回收、用户强制退出 | 已开始任务与新计划任务分别测试 |
| 低电量、低电量模式、热状态 | 成功率、温度与电量变化 |
| 断网后恢复、蜂窝切换 | 重试和结果去重 |
| 来电、音乐播放、语音录制 | 音频恢复与对用户媒体体验的影响 |
| 定位拒绝/撤销、后台刷新关闭 | 能力提示是否真实、是否继续不必要定位 |
| iCloud 同步延迟、Mac 同时在线 | 不产生重复的正式执行或状态覆盖 |

记录 iPhone 型号、iOS 版本、构建模式、权限、触发方式和原始时间线。验收结论分为“已开始长任务延续”与“锁屏后新任务唤醒”。模拟器不能代替这些真机结论。

## 2026-10-10 实施状态更新

D31 已授权实现和必要验证，因此后台能力研究/实现不再等待代码开工授权。提醒仍由本机系统通知呈现；通知是否获准、准时呈现受系统设置影响。身份页的可选每日回顾现会在安静时段结束后向 `BGTaskScheduler` 请求一次 `BGAppRefreshTask`，并在打开 App 时检查漏跑；系统可延迟或不运行，强制退出后也不保证唤醒。任务过期会取消当前回顾请求并留下失败记录，不会将其标成完成。当前没有锁屏准时推理、连续长任务执行、HEARTBEAT 编辑器、目标周期检查或设备真机送达/恢复证据；用户已将实体 iPhone 测试选择为“稍后再测”，设备未连接期间继续其他工作，不把模拟器构建当作后台验收。仍须用真机记录后台刷新权限、锁屏、系统回收、强制退出和断网恢复结果。

## 2026-10-11：端侧 Agent Runtime 校准

之前的实现只把“手机模型请求 + 本机 SQLite”当作完整手机运行环境，遗漏了 OpenMinis iOS 内嵌 iSH/Alpine、tool loop、会话工作区和原生 offload 的分层。本轮新增 [端侧运行时方案](ON_DEVICE_RUNTIME.md)，并把 iOS 本机 runtime 明确为 Swift 宿主、正式结构化工作区、受限工具执行器和后续可插拔 iSH sandbox。当前代码已加入有轮次/参数/输出上限的 OpenAI-compatible tool loop，可搜索历史、读取目标和正式核心文件，也可在按对话隔离、7天清理的临时区读写文本；临时写入不进入长期记忆或共享构件。事件写入活动和任务 checkpoint，正文不记录。此实现不是 Linux sandbox，也未在 DeepSeek 真正 tool call 或 iPhone 真机上验证。

OpenMinis 的 GPL-3.0 主程序依赖 GPL-3.0 iSH fork；OpenMuse 当前许可证为 MIT。集成前要处理许可证兼容和 iOS 构建链，当前不复制 GPL 源码、不改项目许可证。后台部分仍采用本产品真实可说明的 `BGAppRefreshTask` 与检查点；未照搬静音音频/定位保活，因为 OpenMuse 当前没有对应的持续音频/定位产品功能。iSH 接入与后台真机成功率仍是后续验收项。

## 2026-10-11：手机工作区持久化

OpenMinis 的每会话工作区是持久运行状态的一部分。OpenMuse 原先把中间材料放在可能被系统清理的 Caches，并在 7 天后主动删除；现迁到 Application Support，旧版缓存会在第一次打开对应对话时迁移，不再自动按时间删除。对话工作区限定为最多 80 个文件、每文件 256 KB、总计 16 MB，供暂停后重新打开继续读取中间结果。该改动只保留文件，不会让已暂停模型请求自动续跑，也不改变 iOS 的后台额度限制；双端同步和导出暂未接入。iOS 数据保护属性已加入写入尝试，但仍须真机验证锁屏和后台读取行为。
