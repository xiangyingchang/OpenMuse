# 构件协议与运行方案 v1

2026-10-10。以下为制定的实现基线；Muse旅游网页仅提供交互启发，不直接复用其网页与素材。

## 数据与版本

Artifact：artifactId、kind(document/web)、title、conversationId、goalIds、currentRevisionId、status、createdAt。Revision：revisionId、parentIds、sourceMessageIds、assumptions、files(hash/size/type)、dataSchemaVersion、previewRef、createdByAttemptId。manifest与UTF-8内容/JSON数据、附件形成可迁移包；路径只允许相对路径，拒绝越界/符号链接逃逸。

状态：draft → generating → validating → ready；失败为failed，原ready版本仍可打开。用户明确要成果、接受点子并产生成果或已有构件修改时进入资源库；普通短回答不自动堆构件。聊天卡与资源库引用同一artifactId，生成中有占位和最新说明，ready才可宣称交付。

“保留七天，新增五天”在同一构件的数据中形成两个命名方案，改变天数不是覆写原版本。每次成功修改新建不可变修订；只在校验通过后切currentRevision。历史可预览、恢复（新增恢复修订，不改旧版本）。同基线并发修改先保留两分支，用户选择/合并；审批和旅行事实不随方案自动成立。

## 显示与权限

原生正文渲染Markdown；交互网页使用WKWebView载入本地包，临时非持久网站数据，不运行服务端代码、远程脚本、任意npm安装或宿主shell。静态HTML/CSS和包内JS；CSP默认禁外联脚本、frame、表单、网络与顶层导航；使用自定义资源scheme并限制到该构件目录，禁共享文件任意访问。实现必须做绕过测试，不能以“用了WebView”当已隔离。

Web内容无宿主工具桥。需要修改/检索时用户回到关联聊天提出请求，由agent生成下一修订；不在网页里直接调用邮箱、Pi或供应商密钥。外链由原生确认后系统浏览器打开。图片由agent检索/下载并保存出处，网页渲染不自动请求第三方跟踪资源。无网络时已下载构件可打开，未下载附件显示占位。

交互状态（切换标签等）默认页面内临时保存；表单若需持久化，只能走后续专门的带schema数据通道，首轮不开放。这是明确一期边界，不伪装所有Muse任意Web应用均已支持。

## 导出与验收

导出Markdown/JSON用于结构资料，网页以含manifest/本地资产的ZIP迁移；PDF为阅读快照（无交互），分享由用户发起。包验证大小/文件类型/引用/校验和，不接受ZIP路径穿越。凭证不在包里。彻底删除覆盖历史、缩略图和附件（共享附件按引用清理）。

七/五天/差异切换、假设标记；生成失败不损坏旧成果；编辑历史恢复；Mac断开手机打开缓存；两端冲突；导出新设备重建；恶意脚本不得读宿主文件、请求网络或工具；取消和遗忘期间返回结果不复活。通过这些才算构件能力交付。
