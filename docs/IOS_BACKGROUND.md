# OpenMinis 手机执行与后台专项

日期：2026-10-09。证据级别：官方文档与固定版本源码阅读；没有构建或真机实测。

## 用户要求与当前状态

手机内有小运行环境，数据可 iCloud 同步；Mac 离线时仍希望持续工作。用户要求继续参考 OpenMinis。用户尚未明确接受仅前台执行，也未接受自建云端执行服务器。

不能用这个未决事项阻止当前文档和公开仓库交付；但不能在正式方案中声称已解决全天候执行。

## 上游实际机制

OpenMinis 的 [BackgroundKeepAliveManager.swift](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Agent/Background/BackgroundKeepAliveManager.swift) 同时管理短后台额度、增强后台、后台讲话、音频和定位状态，以及活动显示和中断恢复。

- 普通后台额度通过 UIApplication 的后台任务管理，不是无限执行许可证。
- 增强路线使用 CoreLocation；权限与开关参与有效状态判断。
- 音频路线使用 AVAudioEngine 和循环静音 buffer；受后台讲话开关、活动会话和媒体中断状态控制。
- 代码处理音频会话被回收、媒体中断、重启尝试和前后台切换。
- Live Activity 与本地通知提供状态展示；展示存在不代表后台推理始终执行。

关键源码位置：能力分层在开头 21–45 行，增强状态判断约 91–101 行，静音播放条件约 1157 行，音频缓冲与循环约 1374–1396 行。行号固定到上方 commit，后续版本需复查。

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

该验证不在当前授权范围内运行。先讨论方案；确认开工后，把验证作为最早技术工作，避免核心假设长期悬空。
