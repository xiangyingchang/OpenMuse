import SwiftUI

private enum EditorPalette {
    static let background = Color(red: 0.055, green: 0.064, blue: 0.078)
    static let panel = Color(red: 0.105, green: 0.119, blue: 0.142)
    static let text = Color(red: 0.94, green: 0.95, blue: 0.98)
    static let subtle = Color(red: 0.57, green: 0.61, blue: 0.68)
    static let blue = Color(red: 0.31, green: 0.51, blue: 0.98)
}

public struct ModelSettingsView: View {
    @ObservedObject private var model: OpenMuseAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var provider: ModelProvider
    @State private var endpoint: String
    @State private var modelID: String
    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var message: String?
    @State private var testSucceeded = false

    public init(model: OpenMuseAppModel) {
        self.model = model
        _provider = State(initialValue: model.modelConfiguration.provider)
        _endpoint = State(initialValue: model.modelConfiguration.endpoint)
        _modelID = State(initialValue: model.modelConfiguration.model)
    }

    private var configuration: ModelConfiguration {
        ModelConfiguration(provider: provider, endpoint: endpoint, model: modelID)
    }

    public var body: some View {
        VStack(spacing: 0) {
            sheetHeader(title: "模型设置", subtitle: "密钥只保存在这台设备的钥匙串。")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("选择模型服务").font(.headline).foregroundStyle(EditorPalette.text)
                        Picker("服务", selection: $provider) {
                            ForEach(ModelProvider.allCases) { item in Text(item.rawValue).tag(item) }
                        }
                        .onChange(of: provider) { old, new in
                            if endpoint == old.defaultEndpoint { endpoint = new.defaultEndpoint }
                            if modelID == old.defaultModel { modelID = new.defaultModel }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("API 地址").font(.caption).foregroundStyle(EditorPalette.subtle)
                            TextField("https://api.example.com/v1", text: $endpoint)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.URL)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("模型名称").font(.caption).foregroundStyle(EditorPalette.subtle)
                            TextField("模型 ID", text: $modelID).textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("API 密钥").font(.caption).foregroundStyle(EditorPalette.subtle)
                                Spacer()
                                if model.hasModelCredential(for: configuration) { Label("此设备已保存", systemImage: "checkmark.shield.fill").font(.caption2).foregroundStyle(.green) }
                            }
                            SecureField(model.hasModelCredential(for: configuration) ? "留空以保留现有密钥" : "粘贴 API 密钥", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                            if model.hasModelCredential(for: configuration) {
                                Button("删除此服务的本机密钥", role: .destructive) {
                                    do { try model.clearModelCredential(for: configuration) }
                                    catch { message = error.localizedDescription; testSucceeded = false }
                                }
                                .font(.caption)
                            }
                        }
                    }
                    .padding(16)
                    .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 8) {
                        Label(model.contextDescription, systemImage: "desktopcomputer")
                            .font(.subheadline.weight(.medium)).foregroundStyle(EditorPalette.text)
                        #if os(macOS)
                        Text("Mac 使用 Pi 建立无工具的模型会话；应用不会通过 Pi 自动运行 shell 命令。")
                        #else
                        Text("iPhone 直接连接所选模型。没有网络时，已保存的聊天和文件仍可查看。")
                        #endif
                        Text("消息和相关记忆会发送给你选择的模型服务以生成回复；OpenMuse 当前没有自建执行服务器。")
                        Text("两台设备之间的认证同步还未接通；现在的内容分别保存在本机。")
                    }
                    .font(.caption)
                    .foregroundStyle(EditorPalette.subtle)
                    .padding(.horizontal, 4)

                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(testSucceeded ? .green : EditorPalette.subtle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 22)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 10) {
                Button("完成") { dismiss() }.buttonStyle(.bordered)
                Spacer()
                Button {
                    Task { await testConnection() }
                } label: {
                    if isTesting { ProgressView().controlSize(.small) } else { Text("保存并测试") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTesting || !configuration.isReady || (apiKey.isEmpty && !model.hasModelCredential(for: configuration)))
            }
            .padding(16)
        }
        .background(EditorPalette.background)
        .frame(minWidth: 360, minHeight: 520)
    }

    @MainActor
    private func testConnection() async {
        isTesting = true
        message = nil
        testSucceeded = false
        do {
            try await model.testModel(configuration: configuration, apiKey: apiKey)
            try model.saveModelSettings(configuration: configuration, apiKey: apiKey)
            apiKey = ""
            testSucceeded = true
            message = "连接成功。模型设置已保存在这台设备。"
        } catch {
            message = error.localizedDescription
        }
        isTesting = false
    }
}

public struct MemoryFilesView: View {
    @ObservedObject private var model: OpenMuseAppModel

    public init(model: OpenMuseAppModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            sheetHeader(title: "身份与记忆", subtitle: "这些文件会和本地记录一起保存，可随时查看和编辑。")
            ScrollView {
                VStack(spacing: 9) {
                    ForEach(model.documents) { document in
                        Button { model.presentedSheet = .document(document) } label: {
                            HStack(spacing: 11) {
                                Image(systemName: document.path == "SOUL.md" ? "sparkles" : "doc.text")
                                    .foregroundStyle(EditorPalette.blue)
                                    .frame(width: 35, height: 35)
                                    .background(EditorPalette.background, in: RoundedRectangle(cornerRadius: 11))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(document.path).font(.subheadline.weight(.semibold)).foregroundStyle(EditorPalette.text)
                                    Text("第 \(document.revision) 版 · UTF-8 Markdown")
                                        .font(.caption).foregroundStyle(EditorPalette.subtle)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(EditorPalette.subtle)
                            }
                            .padding(11)
                            .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 15))
                        }
                        .buttonStyle(.plain)
                    }
                    if let url = model.workspaceURL {
                        Text("本機資料夾：\n\(url.path)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(EditorPalette.subtle)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .background(EditorPalette.background)
        .frame(minWidth: 360, minHeight: 500)
    }
}

public struct WorkspaceDocumentEditor: View {
    @ObservedObject private var model: OpenMuseAppModel
    @Environment(\.dismiss) private var dismiss
    private let document: WorkspaceDocument
    @State private var content: String
    @State private var showRestoreConfirmation = false

    public init(model: OpenMuseAppModel, document: WorkspaceDocument) {
        self.model = model
        self.document = document
        _content = State(initialValue: document.content)
    }

    public var body: some View {
        VStack(spacing: 0) {
            sheetHeader(title: document.path, subtitle: "UTF-8 Markdown · 修订 \(document.revision)")
            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .foregroundStyle(EditorPalette.text)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            HStack {
                if model.previousDocumentRevision(path: document.path) != nil {
                    Button("恢复上个版本") { showRestoreConfirmation = true }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(.bordered)
                Button("保存") { model.saveDocument(document, content: content); dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .background(EditorPalette.background)
        .frame(minWidth: 380, minHeight: 560)
        .confirmationDialog("用上个版本替换当前编辑内容？", isPresented: $showRestoreConfirmation, titleVisibility: .visible) {
            Button("恢复为新版本", role: .destructive) {
                if let previous = model.previousDocumentRevision(path: document.path) {
                    content = previous.content
                    model.saveDocument(document, content: previous.content)
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("旧版本会保留；恢复操作会保存为一条新的修订。")
        }
    }
}

public struct ArtifactEditorView: View {
    @ObservedObject private var model: OpenMuseAppModel
    @Environment(\.dismiss) private var dismiss
    private let artifact: ArtifactRecord
    @State private var content: String
    @State private var showingHistory = false

    public init(model: OpenMuseAppModel, artifact: ArtifactRecord) {
        self.model = model
        self.artifact = artifact
        _content = State(initialValue: artifact.content)
    }

    public var body: some View {
        VStack(spacing: 0) {
            sheetHeader(title: artifact.title, subtitle: "旅行计划草稿 · 第 \(artifact.currentRevision) 版")
            TextEditor(text: $content)
                .font(.system(.body, design: .default))
                .scrollContentBackground(.hidden)
                .foregroundStyle(EditorPalette.text)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            HStack {
                Button("版本历史") { showingHistory = true }.buttonStyle(.bordered)
                Spacer()
                Button("关闭") { dismiss() }.buttonStyle(.bordered)
                Button("保存修改") { model.saveArtifact(artifact, content: content); dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .background(EditorPalette.background)
        .frame(minWidth: 420, minHeight: 580)
        .sheet(isPresented: $showingHistory) { artifactHistoryView }
        .onChange(of: model.artifacts) { _, updated in
            if let latest = updated.first(where: { $0.id == artifact.id }), latest.currentRevision != artifact.currentRevision {
                content = latest.content
            }
        }
    }

    private var artifactHistoryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            sheetHeader(title: "计划版本", subtitle: "选中旧版会载入编辑器；点击“保存修改”后保存为新版本，历史仍然保留。")
            let history = model.artifactHistory(id: artifact.id)
            if history.isEmpty {
                Text("当前还没有历史版本。修改并保存后会开始记录。")
                    .font(.subheadline).foregroundStyle(EditorPalette.subtle).padding(18)
            }
            ForEach(history) { revision in
                Button {
                    showingHistory = false
                    if revision.currentRevision != artifact.currentRevision {
                        content = revision.content
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("第 \(revision.currentRevision) 版").font(.subheadline.weight(.semibold)).foregroundStyle(EditorPalette.text)
                            Text(revision.updatedAt.formatted(date: .numeric, time: .shortened)).font(.caption).foregroundStyle(EditorPalette.subtle)
                        }
                        Spacer()
                        if revision.currentRevision == artifact.currentRevision { Text("当前").font(.caption).foregroundStyle(EditorPalette.blue) }
                        else { Image(systemName: "arrow.uturn.backward").foregroundStyle(EditorPalette.blue) }
                    }
                    .padding(12)
                    .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 4)
        }
        .padding(14)
        .frame(minWidth: 340, minHeight: 330)
        .background(EditorPalette.background)
    }
}

public struct ActivityListView: View {
    @ObservedObject private var model: OpenMuseAppModel

    public init(model: OpenMuseAppModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            sheetHeader(title: "最近活动", subtitle: "显示真实的对话请求状态，不用估算进度。")
            ScrollView {
                VStack(spacing: 10) {
                    if model.activities.isEmpty {
                        Text("还没有活动。聊一个想做的事，它会从这里开始留下记录。")
                            .font(.subheadline).foregroundStyle(EditorPalette.subtle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(17)
                            .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 15))
                    }
                    ForEach(model.activities) { activity in
                        Button { model.openActivity(activity) } label: {
                            HStack(alignment: .top, spacing: 11) {
                                ActivityMark(status: activity.status)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(activity.title).font(.subheadline.weight(.semibold)).foregroundStyle(EditorPalette.text)
                                        Spacer(minLength: 6)
                                        Text(activity.status.localizedActivityStatus).font(.caption2).foregroundStyle(EditorPalette.subtle)
                                    }
                                    Text(activity.stage).font(.caption).foregroundStyle(EditorPalette.subtle).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(activity.updatedAt.formatted(date: .numeric, time: .shortened)).font(.caption2).foregroundStyle(EditorPalette.subtle.opacity(0.75))
                                }
                            }
                            .padding(13)
                            .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 15))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .background(EditorPalette.background)
        .frame(minWidth: 360, minHeight: 440)
    }
}

private struct ActivityMark: View {
    let status: String

    var body: some View {
        ZStack {
            Circle().fill(status == "running" ? EditorPalette.blue.opacity(0.18) : EditorPalette.background)
            if status == "running" { ProgressView().controlSize(.small) }
            else { Image(systemName: status == "completed" ? "checkmark" : status == "failed" ? "exclamationmark" : "pause.fill").font(.caption.weight(.bold)).foregroundStyle(status == "completed" ? .green : EditorPalette.subtle) }
        }
        .frame(width: 32, height: 32)
    }
}

private extension String {
    var localizedActivityStatus: String {
        switch self {
        case "running": "进行中"
        case "completed": "已完成"
        case "failed": "失败"
        case "suspended": "已暂停"
        case "cancelled": "已取消"
        default: self
        }
    }
}

private func sheetHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.system(size: 20, weight: .semibold)).foregroundStyle(EditorPalette.text)
        Text(subtitle).font(.caption).foregroundStyle(EditorPalette.subtle)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 18)
    .padding(.top, 19)
    .padding(.bottom, 15)
}
