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

                    #if os(macOS)
                    MacBridgeHostPanel(model: model)
                    #else
                    iPhoneMacPanel(model: model)
                    #endif

                    VStack(alignment: .leading, spacing: 8) {
                        Label(model.contextDescription, systemImage: "desktopcomputer")
                            .font(.subheadline.weight(.medium)).foregroundStyle(EditorPalette.text)
                        #if os(macOS)
                        Text("Mac 使用 Pi 建立无工具的模型会话；应用不会通过 Pi 自动运行 shell 命令。")
                        #else
                        Text("iPhone 直接连接所选模型。没有网络时，已保存的聊天和文件仍可查看。")
                        #endif
                        Text("配对后，聊天和本轮相关记忆会经过 Tailscale HTTPS 发给 Mac；Pi 使用 Mac 上保存的模型设置。未配对时，iPhone 直接连接这里选择的模型。")
                        Text("目前只转发模型回合；聊天记录、目标、记忆和构件不会同步到 Mac。Mac 的 Pi 工具仍关闭，尚不能读写 Mac 文件或操作浏览器。")
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

#if os(macOS)
private struct MacBridgeHostPanel: View {
    @ObservedObject private var model: OpenMuseAppModel
    @ObservedObject private var server: MacBridgeServer

    init(model: OpenMuseAppModel) {
        self.model = model
        self.server = model.macBridgeServer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("连接家里的 Mac", systemImage: "desktopcomputer.and.arrow.down")
                .font(.headline).foregroundStyle(EditorPalette.text)
            Text(server.status).font(.caption).foregroundStyle(EditorPalette.subtle)
            Text(server.privateRouteStatus)
                .font(.caption).foregroundStyle(server.privateRouteEnabled ? .green : EditorPalette.subtle)
            if let address = server.deviceAddress {
                Text(address)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(EditorPalette.text)
            } else {
                Text("没有找到已登录的 Tailscale。连接后重启 OpenMuse。")
                    .font(.caption).foregroundStyle(EditorPalette.subtle)
            }
            if !server.privateRouteEnabled {
                Button {
                    server.enablePrivateLink()
                } label: {
                    Label("启用 Tailscale 私有连接", systemImage: "lock.shield")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!server.isRunning)
            }
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("一次性配对码").font(.caption).foregroundStyle(EditorPalette.subtle)
                    Text(server.pairingCode).font(.system(.title3, design: .monospaced).weight(.semibold)).tracking(1.5).foregroundStyle(EditorPalette.text)
                }
                Spacer()
                Button("重新生成") { server.rotatePairingCode() }
                    .buttonStyle(.bordered)
            }
            if server.pairedDevices.isEmpty {
                Text("还没有已配对设备。")
                    .font(.caption).foregroundStyle(EditorPalette.subtle)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("已授权设备").font(.caption).foregroundStyle(EditorPalette.subtle)
                    ForEach(server.pairedDevices) { device in
                        HStack(spacing: 8) {
                            Label(device.name, systemImage: "iphone")
                                .font(.caption).foregroundStyle(EditorPalette.text)
                            Spacer()
                            Button("撤销") { server.revokeDevice(id: device.id) }
                                .font(.caption).buttonStyle(.borderless).foregroundStyle(.red)
                        }
                    }
                }
            }
            Text("配对码 5 分钟有效且只能使用一次。配对后 iPhone 会优先把聊天交给这台 Mac 的 Pi。")
                .font(.caption).foregroundStyle(EditorPalette.subtle)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 18))
    }
}
#endif

#if os(iOS)
private struct iPhoneMacPanel: View {
    @ObservedObject private var model: OpenMuseAppModel
    @State private var pairingCode = ""
    @State private var isPairing = false
    @State private var message: String?
    @State private var succeeded = false

    init(model: OpenMuseAppModel) { self.model = model }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("连接家里的 Mac", systemImage: "desktopcomputer.and.arrow.down")
                .font(.headline).foregroundStyle(EditorPalette.text)
            Text("两台设备都需要连接同一个 Tailscale 网络。Mac 上的 OpenMuse 必须保持运行。")
                .font(.caption).foregroundStyle(EditorPalette.subtle)
            TextField("https://你的 Mac Tailscale 地址:8443/openmuse", text: $model.macBridgeAddress)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            HStack(spacing: 8) {
                SecureField("Mac 屏幕上的一次性配对码", text: $pairingCode)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button {
                    Task { await pair() }
                } label: {
                    if isPairing { ProgressView().controlSize(.small) } else { Text("配对") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPairing || model.macBridgeAddress.isEmpty || pairingCode.isEmpty)
            }
            Toggle("Mac 可用时优先通过 Mac 的 Pi 回复", isOn: $model.preferMacWhenAvailable)
                .font(.caption)
                .tint(EditorPalette.blue)
                .onChange(of: model.preferMacWhenAvailable) { _, value in
                    UserDefaults.standard.set(value, forKey: "openmuse.bridge.prefer-mac")
                }
            if model.macBridgePaired {
                HStack {
                    Label("已配对", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                    Spacer()
                    Button("检查连接") { Task { await checkConnection() } }.buttonStyle(.bordered)
                    Button("解除", role: .destructive) {
                        do { try model.disconnectMac(); message = "已解除配对。"; succeeded = true }
                        catch { message = error.localizedDescription; succeeded = false }
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(succeeded ? .green : EditorPalette.subtle)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    @MainActor
    private func pair() async {
        isPairing = true
        message = nil
        succeeded = false
        do {
            try await model.pairWithMac(address: model.macBridgeAddress, code: pairingCode)
            pairingCode = ""
            message = "已安全配对。现在可通过 Mac 的 Pi 对话。"
            succeeded = true
        } catch { message = error.localizedDescription }
        isPairing = false
    }

    @MainActor
    private func checkConnection() async {
        do {
            let device = try await model.checkPairedMac()
            message = "已连接：\(device)"
            succeeded = true
        } catch {
            message = error.localizedDescription
            succeeded = false
        }
    }
}
#endif

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
            ActivityRecordsList(model: model)
        }
        .background(EditorPalette.background)
        .frame(minWidth: 360, minHeight: 440)
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
