# 回复节奏研究与实现

更新：2026-10-16。用户确认按本研究建议实施；已确认规则见 [D59](DECISIONS.md#2026-10-16-回复流式展示改为合并刷新-d59)，代码与验证见 [T96](ITERATIONS.md#t96)。

## 结论

OpenMuse 目前把模型生成与屏幕展示分开，但屏幕展示按固定速度逐字消费队列。T94 的约 300 个中文字/分钟意味着每个汉字至少等待 200ms，另加句读停顿；答复越长，视觉队列就越长。真实流结束后仍可能看到队列继续播放，因此用户感受到的是额外等待，而不是模型生成时间。

调研到的成熟实现没有把整条回答按固定字数或阅读速度播放。它们保留真实流式，并在模型流、UI 状态更新和短暂淡入之间分层：模型片段可以正常抵达，UI 合并高频更新；小批文本轻微渐显，更新积压时一次提交更大批次；回复完成时立刻显示全部余量。

## 对照

| 实现 | 源码观察 | 对 OpenMuse 的启发 |
|---|---|---|
| OpenMuse，提交 `9c3ceec867bfd67361a8281c6fbb4d9f79cec279` | `StreamPresentationBuffer` 对中文逐字等待 200ms，逗号和句号再增加停顿；快进按钮能排空已到达文本，但平常播放仍按固定速度。 | 问题是消费策略把所有长度和模型速度都视为相同；不能用更高的固定字速解决不同答案的差异。 |
| OpenMinis，提交 `b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c` | Provider 仍通过流式响应发出增量。Android 在消息累积层按答复长度约 200/300/500ms 起步、超长文本逐级放宽 UI 发布间隔；短文的新行加至少 50 个新字符时走快速刷新。仅把最新累计文本放入 UI 状态，工具状态变化立即刷新。Android 新词使用约 350ms 淡入和最多 300ms 批内错开。iOS 同样有分档发布与换行快路径，另用约 450ms 单词淡入；这些节奏是渲染与性能控制，不是模型生成限速。 | 按答案长度、结构和实际积压调整刷新；段落边界可提前给用户可读进展。轻动画用来柔化更新，不应让旧内容排队逐字播完。 |
| nanoMuse，提交 `c33c9e83804d226b689be28d4ebc8a70b798074e` | 仓库说明 Android 客户端基于 OpenMinis 1.13；当前 Android 与 iOS 流实现保留类似的分档 UI 发布、换行快路径与新文本淡入。 | 这是 OpenMinis 方案继续演化后的直接参照；仍是实时流，不是等整条回答生成完再播放。 |
| 本机 Lody iOS App，checkout 提交 `d985749977a6a8e4d4ca0303bbb702c0af1f1feb` | `ChatStream` 将新文本缓冲为增量。正常渲染间隔按尾部规模从 48ms 增至最多 96ms；很小的尾部最多拆约 8 步呈现；新增达到 48 字，或全文超过 1024 UTF-16 单元时，直接提交积压批次。历史与服务端文本始终是权威内容。 | 适合同为 iOS 原生聊天的基础：轻量合并更新、有限的小批显现、积压时追上；不要给每个字符附加固定睡眠。 |
| Vercel AI SDK `useChat` | 默认收到每个流片段时更新 UI；可选 `experimental_throttle` 合并消息状态更新，文档示例为 50ms。 | 主流通用做法也是限制 UI 刷新频率，而不是把模型输出转换成固定阅读速度。 |

## 已确认方案

1. 保留当前真正的模型流式生成。第一段可读文本到达后尽快显示；短回答不等待整条回答结束。
2. 删除“每个中文字固定等待 200ms”的串行消费队列。将网络片段先合并到一个展示缓冲，再按 UI 能稳定处理的短间隔更新。可从本机 Lody 的 48–96ms 合并区间作为 iOS 起点，而不是把它当用户阅读速度。
3. 至少累积 50 个待显示字符且到达换行、已显示回复少于 5,000 字符时，允许提前刷新该批内容。周期刷新每次提交整个当前积压，不把过期小片段串行播放。
4. 模型正常结束或用户快进时，立即提交当前剩余内容并清理展示状态。用户中止请求时继续遵守既有规则，清除未完成回复且不将部分内容保存为正式消息。展示更新不改变已保存回复、工具结果或模型下一轮上下文。
5. 不按 500 字硬切或限制回答长度。Markdown、表格和代码仍由既有渲染器处理，不将整个完成回答拆成额外播放队列。
6. 用短答、长中文段落、表格/代码、工具调用和模型快速/缓慢五类场景比较首字可见时间、流结束后的残余显示时间、UI 更新频率与滚动稳定性，再由真机体验校准刷新间隔。

“模型回复完成后再按段展示”不会改善模型生成首字延迟，还会把完整答案的展示时间叠加在模型耗时之后；只适合必须先获得完整结果才能安全解析或验证的特殊内容，不适合作为普通聊天的默认方案。

## 来源

- OpenMinis Android stream flush 与 UI pacing：[`ChatViewModel.kt`](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/android/app/src/main/java/com/openminis/app/ui/chat/ChatViewModel.kt)、[`StreamingFade.kt`](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/android/app/src/main/java/com/openminis/app/ui/chat/StreamingFade.kt)、[`StreamingMarkdownText.kt`](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/android/app/src/main/java/com/openminis/app/ui/chat/StreamingMarkdownText.kt)。
- OpenMinis iOS SSE 与文字渐显：[`AIChatViewModel+SSEStream.swift`](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Agent/Chat/AIChatViewModel%2BSSEStream.swift)、[`TextFadeAnimator.swift`](https://github.com/OpenMinis/OpenMinis/blob/b4c0661d5631ebab4d1a2e6f3fd4c805d4030a6c/src/ios/Views/Chat/TextFadeAnimator.swift)。
- nanoMuse 中文 README 对 Android 基线的说明，以及当前源码：[`README_zh.md`](https://github.com/nano-muse/nanoMuse/blob/c33c9e83804d226b689be28d4ebc8a70b798074e/docs/readme/README_zh.md)、[`Android ChatViewModel.kt`](https://github.com/nano-muse/nanoMuse/blob/c33c9e83804d226b689be28d4ebc8a70b798074e/android/src/android/app/src/main/java/com/openminis/app/ui/chat/ChatViewModel.kt)、[`iOS SSE stream`](https://github.com/nano-muse/nanoMuse/blob/c33c9e83804d226b689be28d4ebc8a70b798074e/android/src/ios/Agent/Chat/AIChatViewModel%2BSSEStream.swift)。
- 本机 Lody iOS 实现：`/Users/haoshifasheng/Downloads/Github/lody-ios-tailscale/apps/mobile/modules/lody-kit/ios/Chat/ChatStream.swift` 与 `LodyChatView+Transcript.swift`，checkout `d985749977a6a8e4d4ca0303bbb702c0af1f1feb`。
- Vercel AI SDK `useChat` 与 50ms UI 更新节流：[`API reference`](https://ai-sdk.dev/docs/reference/ai-sdk-ui/use-chat)、[`Chatbot UI updates`](https://ai-sdk.dev/docs/ai-sdk-ui/chatbot)。
- OpenAI 流式事件定义：[`Responses API streaming events`](https://platform.openai.com/docs/api-reference/responses-streaming)。
