import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private enum EditorPalette {
    static let background = Color(red: 0.055, green: 0.064, blue: 0.078)
    static let panel = Color(red: 0.105, green: 0.119, blue: 0.142)
    static let text = Color(red: 0.94, green: 0.95, blue: 0.98)
    static let subtle = Color(red: 0.57, green: 0.61, blue: 0.68)
    static let blue = Color(red: 0.31, green: 0.51, blue: 0.98)
}

private struct OpenMuseLegalDocument: Identifiable {
    let id = UUID()
    let title: String
    let contents: String
}

public struct ModelSettingsView: View {
    @ObservedObject private var model: OpenMuseAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var provider: ModelProvider
    @State private var endpoint: String
    @State private var modelID: String
    @State private var supportsToolCalling: Bool
    @State private var supportsStreamingResponses: Bool
    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var message: String?
    @State private var testSucceeded = false
    @State private var legalDocument: OpenMuseLegalDocument?

    public init(model: OpenMuseAppModel) {
        self.model = model
        _provider = State(initialValue: model.modelConfiguration.provider)
        _endpoint = State(initialValue: model.modelConfiguration.endpoint)
        _modelID = State(initialValue: model.modelConfiguration.model)
        _supportsToolCalling = State(initialValue: model.modelConfiguration.supportsToolCalling)
        _supportsStreamingResponses = State(initialValue: model.modelConfiguration.supportsStreamingResponses)
    }

    private var configuration: ModelConfiguration {
        ModelConfiguration(
            provider: provider,
            endpoint: endpoint,
            model: modelID,
            contextWindow: model.modelConfiguration.contextWindow,
            supportsToolCalling: supportsToolCalling,
            supportsStreamingResponses: supportsStreamingResponses
        )
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
                            supportsToolCalling = new.defaultSupportsToolCalling
                            supportsStreamingResponses = new.defaultSupportsStreamingResponses
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
                        Toggle("允许模型调用本机工具", isOn: $supportsToolCalling)
                            .font(.subheadline.weight(.medium))
                            .tint(EditorPalette.blue)
                        Text(toolCallingDescription)
                            .font(.caption)
                            .foregroundStyle(EditorPalette.subtle)
                        #if os(iOS)
                        Toggle("流式显示回复", isOn: $supportsStreamingResponses)
                            .font(.subheadline.weight(.medium))
                            .tint(EditorPalette.blue)
                        Text("关闭工具调用时，使用流式输出让回复逐步显示。启用工具调用时，模型先完成工具步骤，再显示最终回复。")
                            .font(.caption)
                            .foregroundStyle(EditorPalette.subtle)
                        #else
                        Text("Mac 通过 Pi 发送模型请求；回复显示方式由 Pi 管理。")
                            .font(.caption)
                            .foregroundStyle(EditorPalette.subtle)
                        #endif
                        Label("目前支持文本对话与已提取的附件文字；图片理解和语音对话尚未接入。", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(EditorPalette.subtle)
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
                    MacPiReadAccessPanel()
                    #else
                    iPhoneMacPanel(model: model)
                    PhoneSearchSettingsPanel()
                    #endif

                    WorkspaceArchivePanel(model: model)
                    ReferenceConnectionsPanel(model: model)
                    ModelUsagePanel(model: model)
                    openSourceLicensePanel

                    VStack(alignment: .leading, spacing: 8) {
                        Label(model.contextDescription, systemImage: "desktopcomputer")
                            .font(.subheadline.weight(.medium)).foregroundStyle(EditorPalette.text)
                        #if os(macOS)
                        Text("Mac 使用 Pi 回复。只有你在下方选定只读文件夹后，Pi 才能列出和读取其中的常见文本文件；不会运行 shell、修改原文件或控制浏览器。")
                        #else
                        Text("iPhone 直接连接所选模型。没有网络时，已保存的聊天和文件仍可查看。")
                        #endif
                        Text("配对后，聊天和本轮相关记忆会经过 Tailscale HTTPS 发给 Mac；Pi 使用 Mac 上保存的模型设置。未配对时，iPhone 直接连接这里选择的模型。")
                        Text("配对设备可在连接时双向同步本地对话、目标、记忆和构件；断开时各自保留本机资料。冲突会保留两版，可查看后选一版作为新修订。Mac 的 Pi 文件工具只读取你授权文件夹的临时快照，不会修改原文件；浏览器操作尚未接入。")
                    }
                    .font(.caption)
                    .foregroundStyle(EditorPalette.subtle)
                    .padding(.horizontal, 4)

                }
                .padding(.horizontal, 18)
                .padding(.bottom, 22)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(testSucceeded ? .green : EditorPalette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
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
        .sheet(item: $legalDocument) { document in
            NavigationStack {
                ScrollView {
                    Text(document.contents)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(EditorPalette.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                }
                .background(EditorPalette.background)
                .navigationTitle(document.title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { legalDocument = nil }
                    }
                }
            }
            .frame(minWidth: 360, minHeight: 440)
        }
    }

    private var openSourceLicensePanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("开源许可", systemImage: "text.document")
                .font(.headline).foregroundStyle(EditorPalette.text)
            Text("OpenMuse 按 GNU GPL-3.0 发布。iPhone 版包含 iSH 许可、iOS 附加声明及 Alpine 软件包许可清单。")
                .font(.caption).foregroundStyle(EditorPalette.subtle)
            HStack(spacing: 10) {
                Button("查看 GPL-3.0 许可证") {
                    legalDocument = OpenMuseLegalDocument(
                        title: "GPL-3.0",
                        contents: bundledText(named: "LICENSE") ?? "许可证文件暂不可用。"
                    )
                }
                .buttonStyle(.bordered)
                Button("查看第三方声明") {
                    legalDocument = OpenMuseLegalDocument(
                        title: "第三方声明",
                        contents: bundledThirdPartyNotices()
                    )
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func bundledText(named name: String) -> String? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(name),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func bundledThirdPartyNotices() -> String {
        var sections = [bundledText(named: "THIRD_PARTY_NOTICES.md") ?? "第三方声明文件暂不可用。"]
        if let license = bundledText(named: "LICENSE.md") {
            sections.append("## iSH LICENSE.md\n\n\(license)")
        }
        if let license = bundledText(named: "LICENSE.IOS") {
            sections.append("## iSH LICENSE.IOS\n\n\(license)")
        }
        if let packageNotice = bundledText(named: "alpine-package-notices.txt") {
            sections.append("## Alpine Linux 软件包清单及许可证\n\n\(packageNotice)")
        }
        return sections.joined(separator: "\n\n")
    }

    private var toolCallingDescription: String {
        #if os(macOS)
        "关闭后，Pi 不会使用 OpenMuse 提供的文件读取工具；其他内置工具仍由 OpenMuse 禁止。"
        #else
        "关闭后，模型不能请求本机历史、目标和 Agent 工作区工具。兼容接口不支持函数调用时建议关闭。"
        #endif
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

#if os(iOS)
private struct PhoneSearchSettingsPanel: View {
    @AppStorage(PhoneSearchEnginePreferences.primaryDefaultsKey)
    private var primaryEngineRawValue = PhoneSearchEngine.google.rawValue
    @AppStorage(PhoneSearchEnginePreferences.fallbackDefaultsKey)
    private var fallbackEngineRawValue = PhoneSearchEngine.bing.rawValue

    private var primaryEngine: PhoneSearchEngine {
        PhoneSearchEngine(rawValue: primaryEngineRawValue) ?? .google
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("手机搜索", systemImage: "magnifyingglass")
                .font(.headline).foregroundStyle(EditorPalette.text)
            Picker("首选搜索引擎", selection: $primaryEngineRawValue) {
                ForEach(PhoneSearchEngine.allCases) { engine in
                    Text(engine.displayName).tag(engine.rawValue)
                }
            }
            Picker("备用搜索引擎", selection: $fallbackEngineRawValue) {
                Text("不设置").tag("")
                ForEach(PhoneSearchEngine.allCases.filter { $0 != primaryEngine }) { engine in
                    Text(engine.displayName).tag(engine.rawValue)
                }
            }
            Text("先用\(primaryEngine.displayName)。页面无法读取时，再尝试你选择的备用引擎；不设置时会如实报告失败。搜索词会发送给相应搜索服务。")
                .font(.caption).foregroundStyle(EditorPalette.subtle)
        }
        .padding(16)
        .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 18))
        .onChange(of: primaryEngineRawValue) { _, newValue in
            if fallbackEngineRawValue == newValue {
                fallbackEngineRawValue = PhoneSearchEngine.allCases.first(where: { $0.rawValue != newValue })?.rawValue ?? ""
            }
        }
    }
}
#endif

private struct ReferenceConnectionsPanel: View {
    @ObservedObject var model: OpenMuseAppModel
    @State private var notionToken = ""
    @State private var notionQuery = ""
    @State private var notionPages: [NotionPageSummary] = []
    @State private var notionStatus: String?
    @State private var isSearchingNotion = false
    @State private var qqEmailAddress = ""
    @State private var qqAuthorizationCode = ""
    @State private var qqMessages: [QQMailMessage] = []
    @State private var qqStatus: String?
    @State private var isFetchingMail = false
    @State private var pendingReferenceDrafts: [ReferenceDocumentDraft] = []
    @State private var selectedReferenceIDs = Set<String>()
    @State private var showingMarkdownPicker = false
    @State private var documentToForget: ReferenceDocumentRecord?

    private var hasSavedNotionToken: Bool {
        SecureStore.readIntegrationToken(provider: "notion") != nil
    }

    private var effectiveNotionToken: String? {
        let entered = notionToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return entered.isEmpty ? SecureStore.readIntegrationToken(provider: "notion") : entered
    }

    private var savedQQCredentials: QQMailCredentials? {
        guard let token = SecureStore.readIntegrationToken(provider: "qq-mail"),
              let data = Data(base64Encoded: token) else { return nil }
        return try? JSONDecoder().decode(QQMailCredentials.self, from: data)
    }

    private var effectiveQQCredentials: QQMailCredentials? {
        if !qqEmailAddress.isEmpty || !qqAuthorizationCode.isEmpty {
            let entered = QQMailCredentials(emailAddress: qqEmailAddress, authorizationCode: qqAuthorizationCode)
            return entered.isValid ? entered : nil
        }
        return savedQQCredentials
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("只读资料连接", systemImage: "books.vertical")
                .font(.headline).foregroundStyle(EditorPalette.text)
            Text("导入的内容保存在本机资料库，只会在相关问题中作为背景提供给模型。来源内容按不可信资料处理；删除会同步删除标记。")
                .font(.caption).foregroundStyle(EditorPalette.subtle)

            VStack(alignment: .leading, spacing: 8) {
                Text("Notion").font(.subheadline.weight(.semibold)).foregroundStyle(EditorPalette.text)
                Text("在 Notion 创建仅有读取内容权限的内部连接，并把要读取的页面分享给它。密钥仅存本机钥匙串，不会同步。")
                    .font(.caption).foregroundStyle(EditorPalette.subtle)
                SecureField(hasSavedNotionToken ? "粘贴新密钥以替换现有密钥" : "粘贴 Notion 密钥", text: $notionToken)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                HStack {
                    if !notionToken.isEmpty {
                        Button("保存密钥") {
                            do {
                                try SecureStore.saveIntegrationToken(notionToken, provider: "notion")
                                notionToken = ""
                                notionStatus = "Notion 密钥已保存在本机钥匙串。"
                            } catch { notionStatus = "密钥没有保存：\(error.localizedDescription)" }
                        }
                        .buttonStyle(.bordered)
                    }
                    if hasSavedNotionToken {
                        Button("删除本机密钥", role: .destructive) {
                            do {
                                try SecureStore.deleteIntegrationToken(provider: "notion")
                                notionStatus = "已删除本机 Notion 密钥。"
                            } catch { notionStatus = "密钥没有删除：\(error.localizedDescription)" }
                        }
                        .buttonStyle(.borderless)
                    }
                    Spacer()
                    if isSearchingNotion { ProgressView().controlSize(.small) }
                }
                HStack(spacing: 8) {
                    TextField("搜索已分享的 Notion 页面", text: $notionQuery)
                        .textFieldStyle(.roundedBorder)
                    Button("搜索") { Task { await searchNotion() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSearchingNotion || effectiveNotionToken == nil)
                }
                ForEach(notionPages) { page in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(page.title).font(.caption.weight(.medium)).foregroundStyle(EditorPalette.text)
                            Text(page.lastEditedAt?.formatted(date: .abbreviated, time: .shortened) ?? page.url)
                                .font(.caption2).foregroundStyle(EditorPalette.subtle).lineLimit(1)
                        }
                        Spacer(minLength: 3)
                        Button("查看内容") { Task { await previewNotionPage(page) } }
                            .font(.caption).buttonStyle(.bordered)
                            .disabled(isSearchingNotion)
                    }
                    .padding(9)
                    .background(EditorPalette.background, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(12)
            .background(EditorPalette.background, in: RoundedRectangle(cornerRadius: 13))

            if !pendingReferenceDrafts.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Label("导入前预览", systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(EditorPalette.text)
                    Text("核对标题、来源和内容后，再勾选要保留的资料。")
                        .font(.caption).foregroundStyle(EditorPalette.subtle)
                    ForEach(pendingReferenceDrafts, id: \.externalID) { draft in
                        let recordID = ReferenceDocumentRecord.stableID(provider: draft.provider, externalID: draft.externalID)
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: Binding(
                                get: { selectedReferenceIDs.contains(recordID) },
                                set: { isSelected in
                                    if isSelected { selectedReferenceIDs.insert(recordID) }
                                    else { selectedReferenceIDs.remove(recordID) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(draft.title).font(.caption.weight(.semibold)).foregroundStyle(EditorPalette.text)
                                    Text("\(draft.provider) · \(draft.locator ?? "本地文件")")
                                        .font(.caption2).foregroundStyle(EditorPalette.subtle)
                                }
                            }
                            Text(String(draft.content.prefix(600)))
                                .font(.caption).foregroundStyle(EditorPalette.subtle)
                                .fixedSize(horizontal: false, vertical: true)
                            if draft.content.count > 600 {
                                DisclosureGroup("展开完整导入内容") {
                                    Text(draft.content)
                                        .font(.caption2).foregroundStyle(EditorPalette.subtle)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.caption2).foregroundStyle(EditorPalette.subtle)
                            }
                        }
                        .padding(10)
                        .background(EditorPalette.background, in: RoundedRectangle(cornerRadius: 10))
                    }
                    HStack {
                        Button("取消预览") {
                            pendingReferenceDrafts = []
                            selectedReferenceIDs = []
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        Button("导入所选（\(selectedReferenceIDs.count)）") { importSelectedReferences() }
                            .buttonStyle(.borderedProminent)
                            .disabled(selectedReferenceIDs.isEmpty)
                    }
                }
                .padding(12)
                .background(EditorPalette.background, in: RoundedRectangle(cornerRadius: 13))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("QQ 邮箱").font(.subheadline.weight(.semibold)).foregroundStyle(EditorPalette.text)
                Text("只读最近 14 天的收件箱邮件。请在 QQ 邮箱开启 IMAP 并生成 16 位客户端授权码；OpenMuse 不读取密码、不发送、移动、标记或删除邮件。")
                    .font(.caption).foregroundStyle(EditorPalette.subtle)
                TextField("完整 QQ 邮箱地址", text: $qqEmailAddress)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                SecureField("16 位客户端授权码", text: $qqAuthorizationCode)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                HStack {
                    Button("保存只读凭证") { saveQQCredentials() }
                        .buttonStyle(.bordered)
                        .disabled(effectiveQQCredentials == nil || qqAuthorizationCode.isEmpty)
                    if savedQQCredentials != nil {
                        Button("删除本机凭证", role: .destructive) {
                            do {
                                try SecureStore.deleteIntegrationToken(provider: "qq-mail")
                                qqStatus = "已删除本机 QQ 邮箱凭证。"
                                qqMessages = []
                            } catch { qqStatus = "凭证没有删除：\(error.localizedDescription)" }
                        }
                        .buttonStyle(.borderless)
                    }
                    Spacer()
                    if isFetchingMail { ProgressView().controlSize(.small) }
                }
                Button("读取最近 14 天") { Task { await fetchQQMail() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isFetchingMail || effectiveQQCredentials == nil)
                ForEach(qqMessages) { message in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.subject).font(.caption.weight(.semibold)).foregroundStyle(EditorPalette.text)
                        Text("\(message.sender) · \(message.receivedAt ?? "时间未知")")
                            .font(.caption2).foregroundStyle(EditorPalette.subtle).lineLimit(1)
                        if !message.snippet.isEmpty {
                            Text(message.snippet).font(.caption2).foregroundStyle(EditorPalette.subtle).lineLimit(3)
                        }
                        Button("导入这封邮件摘要") { model.importReferenceDocument(message.referenceDraft) }
                            .font(.caption).buttonStyle(.bordered)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(EditorPalette.background, in: RoundedRectangle(cornerRadius: 10))
                }
                if let qqStatus { Text(qqStatus).font(.caption).foregroundStyle(EditorPalette.subtle) }
            }
            .padding(12)
            .background(EditorPalette.background, in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 8) {
                Text("Obsidian").font(.subheadline.weight(.semibold)).foregroundStyle(EditorPalette.text)
                Text("从文件选择器明确选择 Markdown 笔记。OpenMuse 只读取所选文件，不扫描整个 Vault。")
                    .font(.caption).foregroundStyle(EditorPalette.subtle)
                Button { showingMarkdownPicker = true } label: {
                    Label("选择 Markdown 笔记", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(EditorPalette.background, in: RoundedRectangle(cornerRadius: 13))

            if !model.referenceDocuments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("已导入资料（\(model.referenceDocuments.count)）")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(EditorPalette.text)
                    ForEach(model.referenceDocuments) { document in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(document.title).font(.caption.weight(.medium)).foregroundStyle(EditorPalette.text)
                                Text("\(document.provider) · 更新于 \(document.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2).foregroundStyle(EditorPalette.subtle)
                            }
                            Spacer(minLength: 4)
                            Button("忘记", role: .destructive) { documentToForget = document }
                                .font(.caption).buttonStyle(.borderless)
                        }
                        .padding(9)
                        .background(EditorPalette.background, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            if let notionStatus {
                Text(notionStatus).font(.caption).foregroundStyle(EditorPalette.subtle)
            }
            if let status = model.statusText {
                Text(status).font(.caption).foregroundStyle(EditorPalette.subtle)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 18))
        .fileImporter(
            isPresented: $showingMarkdownPicker,
            allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                var drafts: [ReferenceDocumentDraft] = []
                for url in urls {
                    let hasScope = url.startAccessingSecurityScopedResource()
                    defer { if hasScope { url.stopAccessingSecurityScopedResource() } }
                    do { drafts.append(try ObsidianMarkdownImporter.read(url: url)) }
                    catch { notionStatus = error.localizedDescription }
                }
                pendingReferenceDrafts = drafts
                selectedReferenceIDs = Set(drafts.map { ReferenceDocumentRecord.stableID(provider: $0.provider, externalID: $0.externalID) })
            case .failure(let error):
                notionStatus = "没有读取所选笔记：\(error.localizedDescription)"
            }
        }
        .confirmationDialog("忘记这份资料？", isPresented: Binding(
            get: { documentToForget != nil },
            set: { if !$0 { documentToForget = nil } }
        ), titleVisibility: .visible) {
            Button("删除本机资料与来源记录", role: .destructive) {
                if let documentToForget { model.forgetReferenceDocument(id: documentToForget.id) }
                documentToForget = nil
            }
            Button("取消", role: .cancel) { documentToForget = nil }
        } message: {
            Text("原始 Notion 或 Obsidian 内容不会被修改。删除标记会在已配对设备下次同步时清除该副本。")
        }
    }

    @MainActor
    private func searchNotion() async {
        guard let token = effectiveNotionToken else { notionStatus = "请先保存 Notion 只读连接密钥。"; return }
        isSearchingNotion = true
        defer { isSearchingNotion = false }
        do {
            notionPages = try await NotionConnector(token: token).searchPages(query: notionQuery)
            notionStatus = notionPages.isEmpty ? "没有找到已分享的页面。" : "找到 \(notionPages.count) 个页面；选择后才会导入。"
        } catch { notionStatus = error.localizedDescription }
    }

    @MainActor
    private func previewNotionPage(_ page: NotionPageSummary) async {
        guard let token = effectiveNotionToken else { notionStatus = "请先保存 Notion 只读连接密钥。"; return }
        isSearchingNotion = true
        defer { isSearchingNotion = false }
        do {
            let draft = try await NotionConnector(token: token).readPage(page)
            pendingReferenceDrafts = [draft]
            selectedReferenceIDs = [ReferenceDocumentRecord.stableID(provider: draft.provider, externalID: draft.externalID)]
            notionStatus = "已读取「\(page.title)」；检查内容后再选择导入。"
        } catch { notionStatus = error.localizedDescription }
    }

    private func importSelectedReferences() {
        for draft in pendingReferenceDrafts {
            let id = ReferenceDocumentRecord.stableID(provider: draft.provider, externalID: draft.externalID)
            if selectedReferenceIDs.contains(id) { model.importReferenceDocument(draft) }
        }
        pendingReferenceDrafts = []
        selectedReferenceIDs = []
    }

    private func saveQQCredentials() {
        guard let credentials = effectiveQQCredentials, let data = try? JSONEncoder().encode(credentials) else {
            qqStatus = "请检查邮箱地址和 16 位授权码。"
            return
        }
        do {
            try SecureStore.saveIntegrationToken(data.base64EncodedString(), provider: "qq-mail")
            qqEmailAddress = ""
            qqAuthorizationCode = ""
            qqStatus = "QQ 邮箱凭证仅保存在本机钥匙串。"
        } catch { qqStatus = "凭证没有保存：\(error.localizedDescription)" }
    }

    @MainActor
    private func fetchQQMail() async {
        guard let credentials = effectiveQQCredentials else { qqStatus = "请先保存有效的 QQ 邮箱只读凭证。"; return }
        isFetchingMail = true
        defer { isFetchingMail = false }
        do {
            qqMessages = try await QQMailConnector(credentials: credentials).fetchRecentMessages()
            qqStatus = qqMessages.isEmpty ? "最近 14 天没有找到邮件。" : "读取到 \(qqMessages.count) 封摘要；仅在你点击后才导入。"
        } catch { qqStatus = error.localizedDescription }
    }
}

private struct ModelUsagePanel: View {
    @ObservedObject var model: OpenMuseAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("模型用量", systemImage: "chart.bar")
                .font(.headline).foregroundStyle(EditorPalette.text)
            if model.modelUsageRecords.isEmpty {
                Text("模型尚未返回可记录的 token 用量，或还没有完成过真实模型请求。")
                    .font(.caption).foregroundStyle(EditorPalette.subtle)
            } else {
                Text("已记录输入 \(model.recordedInputTokens) · 输出 \(model.recordedOutputTokens) tokens")
                    .font(.subheadline.weight(.medium)).foregroundStyle(EditorPalette.text)
                ForEach(model.modelUsageRecords.prefix(4)) { record in
                    HStack {
                        Text("\(record.provider) · \(record.model)")
                        Spacer()
                        Text("\(record.inputTokens.map { String($0) } ?? "–") / \(record.outputTokens.map { String($0) } ?? "–")")
                    }
                    .font(.caption).foregroundStyle(EditorPalette.subtle)
                }
            }
            Text("这里只显示模型实际返回的 token 数；未配置各服务商的价格，金额不会估算，也不代表所有请求都可计量。")
                .font(.caption2).foregroundStyle(EditorPalette.subtle)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 18))
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
            if model.syncConflictCount > 0 {
                Label("有 \(model.syncConflictCount) 项同步冲突待处理；两版资料均已保留。", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(EditorPalette.subtle)
            }
            if !model.syncConflicts.isEmpty { SyncConflictList(model: model) }
            Text("配对码 5 分钟有效且只能使用一次。iPhone 配对后可以发起共享资料同步，也会优先把聊天交给这台 Mac 的 Pi。")
                .font(.caption).foregroundStyle(EditorPalette.subtle)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct MacPiReadAccessPanel: View {
    @State private var folderName = MacPiReadAccess.authorizedFolderName
    @State private var auditEntries = MacPiReadAccess.recentAuditEntries()
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Mac 文件访问", systemImage: "folder.badge.gearshape")
                .font(.headline).foregroundStyle(EditorPalette.text)
            if let folderName {
                HStack(spacing: 8) {
                    Label("只读授权：\(folderName)", systemImage: "checkmark.shield.fill")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.green)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button("撤销") {
                        MacPiReadAccess.revokeFolderAccess()
                        self.folderName = nil
                        status = "已撤销。当前请求已生成的临时快照会在本轮结束后清理。"
                    }
                    .buttonStyle(.borderless).foregroundStyle(.red)
                }
            } else {
                Text("尚未授权文件夹。选择后，Mac 和已配对 iPhone 发起的 Mac 任务都可以只读其中的资料。")
                    .font(.caption).foregroundStyle(EditorPalette.subtle)
            }
            HStack(spacing: 8) {
                Button {
                    chooseFolder()
                } label: {
                    Label(folderName == nil ? "选择只读文件夹" : "更换文件夹", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                if !auditEntries.isEmpty {
                    Button("刷新记录") { refreshAudit() }.buttonStyle(.bordered)
                }
            }
            Text("每轮只把普通文本文件的临时副本交给 Pi：Markdown、TXT、JSON、JSONL、CSV、YAML。单文件最多 128 KiB，最多 200 个文件、8 MiB；隐藏文件、符号链接、二进制和大文件跳过。快照在回复、失败或取消后删除。")
                .font(.caption).foregroundStyle(EditorPalette.subtle)
            Text("Pi 只可列出和读取；没有 shell、写文件、浏览器或外部副作用工具。记录只保存相对路径、工具名、时间和结果，不记录文件内容。")
                .font(.caption).foregroundStyle(EditorPalette.subtle)
            if let status {
                Text(status).font(.caption).foregroundStyle(EditorPalette.subtle)
            }
            if !auditEntries.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("最近文件工具记录").font(.caption.weight(.semibold)).foregroundStyle(EditorPalette.text)
                    ForEach(auditEntries.prefix(5)) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(auditStatus(entry.status))
                                .frame(width: 44, alignment: .leading)
                            Text(entry.relativePath ?? "授权范围")
                                .lineLimit(1).textSelection(.enabled)
                            Spacer(minLength: 4)
                            Text(entry.createdAt, style: .time)
                        }
                        .font(.caption2).foregroundStyle(EditorPalette.subtle)
                    }
                    Button("清除记录") {
                        MacPiReadAccess.clearAuditLog()
                        auditEntries = []
                    }
                    .font(.caption2).buttonStyle(.borderless)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择 OpenMuse 可只读访问的文件夹"
        panel.prompt = "授权只读"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MacPiReadAccess.authorizeReadOnlyFolder(url)
            folderName = url.lastPathComponent
            status = "已授权。原文件不会被修改；每轮只会把符合限制的文本副本交给 Pi。"
        } catch {
            status = "没有保存授权：\(error.localizedDescription)"
        }
    }

    private func refreshAudit() {
        auditEntries = MacPiReadAccess.recentAuditEntries()
    }

    private func auditStatus(_ value: String) -> String {
        switch value {
        case "started": "读取中"
        case "completed": "已读取"
        case "failed": "失败"
        case "cancelled": "已取消"
        default: value
        }
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
                    Button {
                        Task { await model.syncWithMac() }
                    } label: {
                        if model.isSyncing { ProgressView().controlSize(.small) } else { Text("同步资料") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isSyncing)
                    Button("检查连接") { Task { await checkConnection() } }.buttonStyle(.bordered)
                    Button("解除", role: .destructive) {
                        do { try model.disconnectMac(); message = "已解除配对。"; succeeded = true }
                        catch { message = error.localizedDescription; succeeded = false }
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption)
                Text(model.syncStatus).font(.caption).foregroundStyle(EditorPalette.subtle)
                if model.syncConflictCount > 0 {
                    Label("有 \(model.syncConflictCount) 项冲突，双方版本都已保留。", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(EditorPalette.subtle)
                }
                if !model.syncConflicts.isEmpty { SyncConflictList(model: model) }
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
            message = "已安全配对。可以同步共享资料，并通过 Mac 的 Pi 对话。"
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
    @State private var claimToWithdraw: MemoryClaimRecord?
    @State private var showingWithdrawConfirmation = false
    @State private var claimToForget: MemoryClaimRecord?
    @State private var showingForgetConfirmation = false
    @State private var batchToUndo: MemoryImportBatchRecord?
    @State private var showingBatchUndoConfirmation = false
    @State private var showingChatFilePicker = false
    @State private var showingChatPreview = false
    @State private var chatArchiveCandidates: [ChatArchiveConversation] = []
    @State private var selectedChatSourceIDs: Set<String> = []
    @State private var chatImportError: String?
    @State private var showingChatImportError = false
    @State private var chatImportSummary: String?

    public init(model: OpenMuseAppModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            sheetHeader(title: "身份与记忆", subtitle: "这些文件会和本地记录一起保存，可随时查看和编辑。")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DreamingReviewPanel(model: model)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("当前记忆").font(.headline).foregroundStyle(EditorPalette.text)
                        Text("这里管理同一份结构化记忆；过期或尚未生效的记录仍可在此查看和调整。MEMORY.md 自动维护区只展示当前有效记忆，完整且可迁移；USER.md 是精简画像，GLOBAL.md 是主题索引。明确表达可自动记录，导入或推断先经你确认；编辑同步到同一记录，撤销保留修订，彻底忘记会清除记录。")
                            .font(.caption).foregroundStyle(EditorPalette.subtle)
                            .fixedSize(horizontal: false, vertical: true)
                        let activeClaims = model.memoryClaims.filter { $0.status == "active" }
                        if activeClaims.isEmpty {
                            Text("明确告诉 OpenMuse“记住……”或表达稳定偏好后，记忆会列在这里。外部资料和推断不会自动写成事实。")
                                .font(.caption).foregroundStyle(EditorPalette.subtle)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(13)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 14))
                        } else {
                            ForEach(activeClaims) { claim in
                                MemoryClaimRow(claim: claim, model: model, onWithdraw: {
                                    claimToWithdraw = claim
                                    showingWithdrawConfirmation = true
                                }, onForget: {
                                    claimToForget = claim
                                    showingForgetConfirmation = true
                                })
                            }
                        }
                        let withdrawnCount = model.memoryClaims.filter { $0.status == "withdrawn" }.count
                        if withdrawnCount > 0 {
                            Text("已撤销 \(withdrawnCount) 条记忆；原记录仍保留在结构化修订历史中。")
                                .font(.caption2).foregroundStyle(EditorPalette.subtle)
                        }
                        let supersededClaims = model.memoryClaims.filter { $0.status == "superseded" }
                        if !supersededClaims.isEmpty {
                            DisclosureGroup("已按新说法更新（\(supersededClaims.count) 条，旧来源仍保留）") {
                                ForEach(supersededClaims) { oldClaim in
                                    let currentClaim = model.memoryClaims.first(where: { $0.id == oldClaim.supersededByClaimID })
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("旧说法：\(oldClaim.value)")
                                            .font(.caption).foregroundStyle(EditorPalette.subtle)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(currentClaim.map { "当前采用：\($0.value)" } ?? "当前对应记忆已删除")
                                            .font(.subheadline.weight(.medium)).foregroundStyle(EditorPalette.text)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if let currentClaim {
                                            Text("更新来源：\(currentClaim.sourceText)")
                                                .font(.caption2).foregroundStyle(EditorPalette.subtle)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Button("彻底忘记旧说法") {
                                            claimToForget = oldClaim
                                            showingForgetConfirmation = true
                                        }
                                        .font(.caption)
                                    }
                                    .padding(11)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 12))
                                    .accessibilityIdentifier("superseded-memory-\(oldClaim.id)")
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(EditorPalette.subtle)
                        }
                    }

                    if !model.personaRevisions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("OpenMuse 调整过的协作习惯")
                                .font(.headline).foregroundStyle(EditorPalette.text)
                            ForEach(model.personaRevisions) { revision in
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(revision.habit)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(EditorPalette.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("persona-revision-\(revision.id)")
                                    Text("\(revision.reason) · \(revision.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(EditorPalette.subtle)
                                    Text("来源：\(revision.sourceText)")
                                        .font(.caption2).foregroundStyle(EditorPalette.subtle)
                                        .lineLimit(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if revision.status == "applied" {
                                        Button("撤销这次调整") { model.undoPersonaRefinement(id: revision.id) }
                                            .buttonStyle(.bordered)
                                            .accessibilityIdentifier("persona-revision-undo-\(revision.id)")
                                    } else {
                                        Text("已撤销")
                                            .font(.caption.weight(.medium)).foregroundStyle(EditorPalette.subtle)
                                    }
                                }
                                .padding(13)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }

                    Button {
                        model.presentedSheet = .memoryImport
                    } label: {
                        Label("从其他 AI 导入记忆", systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(13)
                            .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(EditorPalette.text)

                    Button { showingChatFilePicker = true } label: {
                        Label("导入 ChatGPT 聊天记录", systemImage: "text.bubble")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(13)
                            .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(EditorPalette.text)
                    Text("选择 ChatGPT 的 conversations.json 或导出 ZIP。导入前会让你预览并选择对话；历史聊天不会自动写进记忆。")
                        .font(.caption2).foregroundStyle(EditorPalette.subtle)
                    if let chatImportSummary {
                        Text(chatImportSummary).font(.caption).foregroundStyle(EditorPalette.subtle)
                    }

                    if !model.memoryImportBatches.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("导入记录").font(.headline).foregroundStyle(EditorPalette.text)
                            ForEach(model.memoryImportBatches) { batch in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(batch.sourceAI.flatMap { $0.isEmpty ? nil : $0 } ?? "其他 AI")
                                            .font(.subheadline.weight(.medium)).foregroundStyle(EditorPalette.text)
                                        Text("\(batch.createdAt.formatted(date: .abbreviated, time: .omitted)) · \(batch.status == "undone" ? "已撤销" : batch.status == "partially-undone" ? "部分撤销" : "已导入")")
                                            .font(.caption).foregroundStyle(EditorPalette.subtle)
                                    }
                                    Spacer()
                                    if batch.status == "imported" {
                                        Button("整批撤销", role: .destructive) {
                                            batchToUndo = batch
                                            showingBatchUndoConfirmation = true
                                        }
                                            .font(.caption).buttonStyle(.borderless)
                                    }
                                }
                                .padding(11)
                                .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 13))
                            }
                        }
                    }

                    Text("核心文件").font(.headline).foregroundStyle(EditorPalette.text)
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
        .confirmationDialog("撤销这条记忆？", isPresented: $showingWithdrawConfirmation, titleVisibility: .visible) {
            Button("撤销记忆", role: .destructive) {
                if let claimToWithdraw { model.withdrawMemoryClaim(id: claimToWithdraw.id) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("它会从当前记忆中移除，并保留一条可追溯的撤销记录。")
        }
        .confirmationDialog("彻底忘记这条记忆？", isPresented: $showingForgetConfirmation, titleVisibility: .visible) {
            Button("彻底忘记", role: .destructive) {
                if let claimToForget { model.forgetMemoryClaim(id: claimToForget.id) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会从本机结构化记忆、USER.md、MEMORY.md 和 GLOBAL.md 中删除，并在下次同步时从已配对设备删除。原聊天记录仍保留；离线设备需重新连接后才能收到删除。")
        }
        .confirmationDialog("撤销这批导入？", isPresented: $showingBatchUndoConfirmation, titleVisibility: .visible) {
            Button("撤销未修改的条目", role: .destructive) {
                if let batchToUndo { model.undoMemoryImport(batchID: batchToUndo.id) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("你后来手动修改过的条目会保留；撤销结果会记入历史。")
        }
        .fileImporter(isPresented: $showingChatFilePicker, allowedContentTypes: [.json, .zip], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let hasScope = url.startAccessingSecurityScopedResource()
                Task {
                    defer { if hasScope { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let parsed = try await Task.detached(priority: .userInitiated) {
                            try ChatArchiveImporter.parseChatGPTFile(at: url)
                        }.value
                        guard !parsed.isEmpty else { throw ChatArchiveImportError.invalidFormat }
                        chatArchiveCandidates = parsed
                        selectedChatSourceIDs = Set(parsed.map(\.sourceID))
                        showingChatPreview = true
                    } catch {
                        chatImportError = error.localizedDescription
                        showingChatImportError = true
                    }
                }
            case .failure(let error):
                chatImportError = error.localizedDescription
                showingChatImportError = true
            }
        }
        .sheet(isPresented: $showingChatPreview) {
            ChatArchiveImportPreview(
                conversations: chatArchiveCandidates,
                selectedSourceIDs: $selectedChatSourceIDs,
                onImport: {
                    let selected = chatArchiveCandidates.filter { selectedChatSourceIDs.contains($0.sourceID) }
                    model.importChatArchiveConversations(selected)
                    chatImportSummary = model.statusText
                    showingChatPreview = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("聊天记录没有导入", isPresented: $showingChatImportError) {
            Button("好", role: .cancel) { chatImportError = nil }
        } message: {
            Text(chatImportError ?? "请检查所选文件后重试。")
        }
        .background(EditorPalette.background)
        .frame(minWidth: 360, minHeight: 500)
    }
}

private struct ChatArchiveImportPreview: View {
    let conversations: [ChatArchiveConversation]
    @Binding var selectedSourceIDs: Set<String>
    let onImport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("只导入你勾选的对话。历史内容会作为独立聊天保存，不会自动写入长期记忆，也不会在导入时发送给模型。")
                        .font(.footnote)
                        .foregroundStyle(EditorPalette.subtle)
                }
                ForEach(conversations) { conversation in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { selectedSourceIDs.contains(conversation.sourceID) },
                            set: { isSelected in
                                if isSelected { selectedSourceIDs.insert(conversation.sourceID) }
                                else { selectedSourceIDs.remove(conversation.sourceID) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(conversation.title).font(.subheadline.weight(.medium))
                                Text("\(conversation.createdAt.formatted(date: .abbreviated, time: .omitted)) · \(conversation.messages.count) 条消息")
                                    .font(.caption).foregroundStyle(EditorPalette.subtle)
                            }
                        }
                        ForEach(Array(conversation.messages.prefix(2))) { message in
                            Text("\(message.role == .user ? "你" : "AI")：\(message.content.prefix(180))")
                                .font(.caption)
                                .foregroundStyle(EditorPalette.subtle)
                                .lineLimit(3)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("预览聊天记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入所选（\(selectedSourceIDs.count)）", action: onImport)
                        .disabled(selectedSourceIDs.isEmpty)
                }
            }
        }
    }
}

private struct DreamingReviewPanel: View {
    @ObservedObject var model: OpenMuseAppModel
    @State private var showsRecentRuns = false

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { model.maintenancePreferences.enabled },
            set: { model.setScheduledMaintenanceEnabled($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("Dreaming · 记忆整理", systemImage: "sparkles")
                .font(.headline).foregroundStyle(EditorPalette.text)
            Text("回看近期对话，整理值得保留的变化和协作反思。它只提出建议；确认后才会更新记忆或 SOUL.md。")
                .font(.caption).foregroundStyle(EditorPalette.subtle)
                .fixedSize(horizontal: false, vertical: true)
            Text("最多读取最近 7 天、24 条原创对话和相关记忆；内容会发送给当前选择的模型服务。")
                .font(.caption2).foregroundStyle(EditorPalette.subtle)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await model.runDreamingReview() }
            } label: {
                HStack(spacing: 8) {
                    if model.isRunningMaintenance { ProgressView().controlSize(.small) }
                    Text(model.isRunningMaintenance ? "正在回顾…" : "回顾最近对话")
                    Spacer()
                    Image(systemName: "arrow.clockwise")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(EditorPalette.text)
                .padding(12)
                .background(EditorPalette.background, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(model.isRunningMaintenance || !model.hasModelCredential)
            .accessibilityIdentifier("dreaming-review-run")

            Toggle("每天尝试自动回顾一次", isOn: enabledBinding)
                .font(.caption.weight(.medium))
                .tint(EditorPalette.blue)
                .accessibilityIdentifier("dreaming-review-auto-toggle")
            if model.maintenancePreferences.enabled {
                VStack(alignment: .leading, spacing: 10) {
                    Text("计划").font(.subheadline.weight(.semibold)).foregroundStyle(EditorPalette.text)
                    HStack(spacing: 8) {
                        Text("安静时段").foregroundStyle(EditorPalette.subtle)
                        Spacer(minLength: 4)
                        hourMenu(title: "开始", value: model.maintenancePreferences.quietHoursStart, isStart: true)
                        Text("至").foregroundStyle(EditorPalette.subtle)
                        hourMenu(title: "结束", value: model.maintenancePreferences.quietHoursEnd, isStart: false)
                    }
                    .font(.caption)
                    .accessibilityIdentifier("dreaming-quiet-hours")

                    Divider().overlay(EditorPalette.subtle.opacity(0.25))
                    budgetRow(
                        title: "每日请求上限", value: model.maintenancePreferences.maximumRequestsPerDay, unit: "次",
                        range: 1...100, step: 1, accessibilityID: "dreaming-request-budget"
                    ) { model.setMaintenanceBudget(requestsPerDay: $0) }
                    budgetRow(
                        title: "每日 Token 上限", value: model.maintenancePreferences.maximumTokensPerDay, unit: "Token",
                        range: 512...1_000_000, step: 1_000, accessibilityID: "dreaming-token-budget"
                    ) { model.setMaintenanceBudget(tokensPerDay: $0) }
                    budgetRow(
                        title: "单次输出上限", value: model.maintenancePreferences.maximumOutputTokensPerRun, unit: "Token",
                        range: 128...4_096, step: 128, accessibilityID: "dreaming-output-budget"
                    ) { model.setMaintenanceBudget(outputTokensPerRun: $0) }

                    settingsMenuRow(title: "计划时区", identifier: "dreaming-time-zone") {
                        Picker("计划时区", selection: Binding(
                            get: { model.maintenancePreferences.timeZoneIdentifier },
                            set: { model.setMaintenanceTimeZone(identifier: $0) }
                        )) {
                            ForEach(Array(Set([TimeZone.current.identifier, "Asia/Shanghai", "UTC", "America/Los_Angeles", "Europe/London"])).sorted(), id: \.self) { identifier in
                                Text(identifier).tag(identifier)
                            }
                        }
                    }
                    settingsMenuRow(title: "错过计划时", identifier: "dreaming-missed-run-policy") {
                        Picker("错过计划时", selection: Binding(
                            get: { model.maintenancePreferences.missedRunPolicy },
                            set: { model.setMaintenanceMissedRunPolicy($0) }
                        )) {
                            Text("打开 App 后补做").tag("show-on-next-open")
                            Text("跳过当天").tag("skip")
                        }
                    }

                    Text("iOS 后台可能延迟或不运行；失败时会在下次打开 App 后补做。预算写入 HEARTBEAT.md，是本地 Token 估算限额，不是供应商账单上限。")
                        .font(.caption2).foregroundStyle(EditorPalette.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(EditorPalette.background, in: RoundedRectangle(cornerRadius: 13))
                .accessibilityIdentifier("dreaming-plan-settings")
            }

            if let maintenanceStatus = model.maintenanceStatus {
                Text(maintenanceStatus)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(EditorPalette.text)
                    .accessibilityIdentifier("dreaming-review-status")
            }

            if !model.maintenanceRuns.isEmpty {
                DisclosureGroup("最近回顾记录（\(model.maintenanceRuns.count)）", isExpanded: $showsRecentRuns) {
                    ForEach(model.maintenanceRuns.prefix(3)) { run in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(run.status == "completed" ? "回顾完成" : run.status == "failed" ? "回顾失败" : "正在回顾")
                                .font(.caption.weight(.semibold)).foregroundStyle(EditorPalette.text)
                            Text("\(run.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(run.provider) / \(run.model)")
                                .font(.caption2).foregroundStyle(EditorPalette.subtle)
                            if !run.summary.isEmpty {
                                Text(run.summary).font(.caption).foregroundStyle(EditorPalette.subtle)
                            }
                            if let reflection = run.reflection, !reflection.isEmpty {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("协作反思").font(.caption.weight(.semibold)).foregroundStyle(EditorPalette.text)
                                    Text(reflection).font(.caption).foregroundStyle(EditorPalette.text)
                                    ForEach(run.reflectionEvidence ?? [], id: \.sourceMessageID) { evidence in
                                        Text("原话线索：「\(evidence.quote)」")
                                            .font(.caption2).foregroundStyle(EditorPalette.subtle)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Text("反思只供查看，不会自动变成用户事实或进入后续提示词。")
                                        .font(.caption2).foregroundStyle(EditorPalette.subtle)
                                }
                                .padding(.top, 3)
                            }
                            if let failure = run.failureMessage {
                                Text(failure).font(.caption2).foregroundStyle(EditorPalette.subtle)
                            }
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(EditorPalette.background, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(EditorPalette.subtle)
            }

            let pending = model.maintenanceProposals.filter { $0.status == "pending" }
            if !pending.isEmpty {
                Text("等你确认的建议").font(.subheadline.weight(.semibold)).foregroundStyle(EditorPalette.text)
                    .padding(.top, 3)
                ForEach(pending) { proposal in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(kindTitle(proposal.kind)).font(.caption.weight(.semibold)).foregroundStyle(EditorPalette.blue)
                            Spacer()
                            Text("模型自评把握度 \(Int(proposal.confidence * 100))%")
                                .font(.caption2).foregroundStyle(EditorPalette.subtle)
                        }
                        Text(proposal.title).font(.subheadline.weight(.semibold)).foregroundStyle(EditorPalette.text)
                        if let targetGoalID = proposal.targetGoalID,
                           let targetGoal = model.goals.first(where: { $0.id == targetGoalID }) {
                            Text("目标：\(targetGoal.title)").font(.caption).foregroundStyle(EditorPalette.subtle)
                        }
                        if let targetMemoryID = proposal.supersedesMemoryClaimID,
                           let targetMemory = model.memoryClaims.first(where: { $0.id == targetMemoryID }) {
                            Text("当前记忆：「\(targetMemory.value)」")
                                .font(.caption).foregroundStyle(EditorPalette.subtle)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(proposal.content).font(.subheadline).foregroundStyle(EditorPalette.text)
                        Text(proposal.rationale).font(.caption).foregroundStyle(EditorPalette.subtle)
                        if let evidence = proposal.evidence {
                            ForEach(evidence, id: \.sourceMessageID) { item in
                                Text("原话依据：「\(item.quote)」")
                                    .font(.caption).foregroundStyle(EditorPalette.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        let sourceText = model.maintenanceSourceText(for: proposal)
                        if !sourceText.isEmpty {
                            Text("来源：\(sourceText)")
                                .font(.caption2).foregroundStyle(EditorPalette.subtle)
                                .lineLimit(4)
                        }
                        HStack {
                            Button(proposal.kind == "goal-step" ? "加入目标步骤" : proposal.kind == "memory-update" ? "确认更新记忆" : "采纳") {
                                model.reviewMaintenanceProposal(id: proposal.id, accept: true)
                            }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("dreaming-proposal-accept-\(proposal.id)")
                            Button("不采用", role: .destructive) { model.reviewMaintenanceProposal(id: proposal.id, accept: false) }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("dreaming-proposal-reject-\(proposal.id)")
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 14))
                }
            }

            let reviewed = model.maintenanceProposals.filter { $0.status != "pending" }.prefix(4)
            if !reviewed.isEmpty {
                ForEach(Array(reviewed)) { proposal in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: proposal.status == "accepted" ? "checkmark.circle.fill" : proposal.status == "rejected" ? "xmark.circle" : "clock")
                            .foregroundStyle(proposal.status == "accepted" ? .green : EditorPalette.subtle)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(proposal.title).font(.caption.weight(.medium)).foregroundStyle(EditorPalette.text)
                            Text(proposal.status == "accepted" ? "已采纳" : proposal.status == "rejected" ? "未采用" : "来源已过期")
                                .font(.caption2).foregroundStyle(EditorPalette.subtle)
                        }
                        Spacer()
                    }
                    .padding(9)
                    .background(EditorPalette.background, in: RoundedRectangle(cornerRadius: 11))
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func hourMenu(title: String, value: Int, isStart: Bool) -> some View {
        Menu {
            ForEach(0..<24, id: \.self) { hour in
                Button(String(format: "%02d:00", hour)) {
                    let preferences = model.maintenancePreferences
                    model.setMaintenanceQuietHours(start: isStart ? hour : preferences.quietHoursStart, end: isStart ? preferences.quietHoursEnd : hour)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(String(format: "%02d:00", value)).monospacedDigit()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(EditorPalette.blue)
            .frame(minWidth: 70, minHeight: 34)
            .padding(.horizontal, 8)
            .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .accessibilityLabel("安静时段\(title)：\(String(format: "%02d:00", value))")
        .accessibilityIdentifier(isStart ? "dreaming-quiet-start" : "dreaming-quiet-end")
    }

    private func budgetRow(
        title: String,
        value: Int,
        unit: String,
        range: ClosedRange<Int>,
        step: Int,
        accessibilityID: String,
        setValue: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.caption)
                .foregroundStyle(EditorPalette.text)
                .lineLimit(2)
            Spacer(minLength: 2)
            Text("\(value.formatted()) \(unit)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(EditorPalette.subtle)
                .frame(minWidth: 72, alignment: .trailing)
            Stepper(title, value: Binding(get: { value }, set: setValue), in: range, step: step)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier(accessibilityID)
        }
    }

    private func settingsMenuRow<Content: View>(
        title: String,
        identifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).foregroundStyle(EditorPalette.text)
            Spacer(minLength: 4)
            content()
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityIdentifier(identifier)
        }
    }

    private func kindTitle(_ kind: String) -> String {
        switch kind {
        case "fact": "待确认事实"
        case "understanding": "理解假设"
        case "goal-step": "目标下一小步"
        case "memory-update": "记忆可能需要更新"
        default: "协作习惯"
        }
    }
}

private struct MemoryClaimRow: View {
    let claim: MemoryClaimRecord
    @ObservedObject var model: OpenMuseAppModel
    let onWithdraw: () -> Void
    let onForget: () -> Void
    @State private var draft: String
    @State private var isEditing = false
    @State private var isEditingValidity = false
    @State private var hasValidFrom = false
    @State private var hasValidUntil = false
    @State private var validFromDraft: Date
    @State private var validUntilDraft: Date

    init(claim: MemoryClaimRecord, model: OpenMuseAppModel, onWithdraw: @escaping () -> Void, onForget: @escaping () -> Void) {
        self.claim = claim
        self.model = model
        self.onWithdraw = onWithdraw
        self.onForget = onForget
        _draft = State(initialValue: claim.value)
        _hasValidFrom = State(initialValue: claim.validFrom != nil)
        _hasValidUntil = State(initialValue: claim.validUntil != nil)
        _validFromDraft = State(initialValue: claim.validFrom ?? claim.createdAt)
        _validUntilDraft = State(initialValue: claim.validUntil ?? Date.now.addingTimeInterval(365 * 24 * 60 * 60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if isEditing {
                TextField("记忆内容", text: $draft, axis: .vertical)
                    .font(.subheadline).foregroundStyle(EditorPalette.text)
            } else {
                Text(claim.value).font(.subheadline.weight(.medium)).foregroundStyle(EditorPalette.text)
            }
            Text("来源：\(sourceLabel) · “\(claim.sourceText)”")
                .font(.caption).foregroundStyle(EditorPalette.subtle)
                .fixedSize(horizontal: false, vertical: true)
            if claim.isInferred == true { Text("你已确认保留的推断").font(.caption2).foregroundStyle(.orange) }
            if claim.isSensitive == true { Text("敏感记忆：仅因你明确要求或手动选择而保存").font(.caption2).foregroundStyle(.orange) }
            Text(validitySummary)
                .font(.caption2).foregroundStyle(EditorPalette.subtle)
                .accessibilityIdentifier("memory-validity-\(claim.id)")
            if isEditingValidity {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("设定生效日期", isOn: $hasValidFrom)
                        .font(.caption)
                        .accessibilityIdentifier("memory-valid-from-toggle-\(claim.id)")
                    if hasValidFrom {
                        DatePicker("生效日期", selection: $validFromDraft, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .accessibilityIdentifier("memory-valid-from-picker-\(claim.id)")
                    }
                    Toggle("设定截止日期（含当天）", isOn: $hasValidUntil)
                        .font(.caption)
                        .accessibilityIdentifier("memory-valid-until-toggle-\(claim.id)")
                    if hasValidUntil {
                        DatePicker("截止日期", selection: $validUntilDraft, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .accessibilityIdentifier("memory-valid-until-picker-\(claim.id)")
                    }
                    HStack {
                        Button("取消") { cancelValidityEdit() }.font(.caption).buttonStyle(.borderless)
                        Spacer()
                        Button("保存有效期") {
                            model.setMemoryValidity(
                                id: claim.id,
                                validFrom: hasValidFrom ? validFromDraft : nil,
                                validUntil: hasValidUntil ? inclusiveEnd(of: validUntilDraft) : nil
                            )
                            if model.statusText?.hasPrefix("记忆有效期已更新") == true { isEditingValidity = false }
                        }
                        .font(.caption).buttonStyle(.borderless)
                        .accessibilityIdentifier("memory-validity-save-\(claim.id)")
                    }
                }
            }
            if !isEditingValidity {
                HStack {
                    Text(claim.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2).foregroundStyle(EditorPalette.subtle.opacity(0.8))
                    Spacer()
                    if isEditing {
                        Button("取消") { draft = claim.value; isEditing = false }.font(.caption).buttonStyle(.borderless)
                        Button("保存") {
                            model.editMemoryClaim(id: claim.id, value: draft)
                            if model.statusText?.hasPrefix("记忆已修改") == true { isEditing = false }
                        }
                        .font(.caption).buttonStyle(.borderless).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button("编辑") { isEditing = true; draft = claim.value }.font(.caption).buttonStyle(.borderless)
                        Menu {
                            Button("设置有效期", systemImage: "calendar") { beginValidityEdit() }
                            Button("撤销并保留历史", systemImage: "arrow.uturn.backward", action: onWithdraw)
                            Button("彻底忘记", systemImage: "trash", role: .destructive, action: onForget)
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("记忆处理")
                    }
                }
            }
        }
        .padding(12)
        .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 14))
        .onChange(of: claim.value) { _, newValue in draft = newValue }
    }

    private var sourceLabel: String {
        if claim.sourceType == "explicit-user-message" { return "你在聊天中的表达" }
        if claim.sourceType == "user-edit" { return "你手动修订" }
        let sourceAI = model.memoryImportBatches.first(where: { $0.id == claim.importBatchID })?.sourceAI
        return "\(sourceAI.flatMap { $0.isEmpty ? nil : $0 } ?? "其他 AI") 的导入资料"
    }

    private var validitySummary: String {
        let now = Date.now
        let state: String
        if let validFrom = claim.validFrom, now < validFrom {
            state = "尚未生效"
        } else if let validUntil = claim.validUntil, now > validUntil {
            state = "已过期"
        } else {
            state = "当前有效"
        }
        let start = claim.validFrom.map { "自\($0.formatted(date: .abbreviated, time: .omitted))起" }
        let end = claim.validUntil.map { "至\($0.formatted(date: .abbreviated, time: .omitted))" }
        if start == nil && end == nil { return "\(state) · 未设定有效期" }
        return "\(state) · 有效期：\([start, end].compactMap { $0 }.joined(separator: " "))"
    }

    private func inclusiveEnd(of date: Date) -> Date {
        let calendar = Calendar.current
        let startOfSelectedDay = calendar.startOfDay(for: date)
        guard let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfSelectedDay) else { return date }
        return startOfNextDay.addingTimeInterval(-1)
    }

    private func beginValidityEdit() {
        hasValidFrom = claim.validFrom != nil
        hasValidUntil = claim.validUntil != nil
        validFromDraft = claim.validFrom ?? claim.createdAt
        validUntilDraft = claim.validUntil ?? Date.now.addingTimeInterval(365 * 24 * 60 * 60)
        isEditingValidity = true
    }

    private func cancelValidityEdit() {
        hasValidFrom = claim.validFrom != nil
        hasValidUntil = claim.validUntil != nil
        validFromDraft = claim.validFrom ?? claim.createdAt
        validUntilDraft = claim.validUntil ?? Date.now.addingTimeInterval(365 * 24 * 60 * 60)
        isEditingValidity = false
    }
}

public struct MemoryImportView: View {
    @ObservedObject private var model: OpenMuseAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var sourceAI = ""
    @State private var rawText = ""
    @State private var candidates: [MemoryImportCandidate] = []
    @State private var notice: String?
    @State private var copied = false

    private let maximumCharacters = 100_000

    public init(model: OpenMuseAppModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            sheetHeader(title: "导入记忆", subtitle: "先预览，再选择要写入 OpenMuse 的内容。")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if candidates.isEmpty {
                        Text("把提示词发给你常用的 AI，再把回复粘贴回来。OpenMuse 不会直接复制整段回复进记忆。")
                            .font(.subheadline).foregroundStyle(EditorPalette.text)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text("发给其他 AI 的提示词").font(.caption.weight(.semibold)).foregroundStyle(EditorPalette.subtle)
                                Spacer()
                                Button(copied ? "已复制" : "复制") { copyPrompt() }
                                    .font(.caption.weight(.medium)).buttonStyle(.bordered)
                            }
                            ScrollView {
                                Text(model.memoryTransferPrompt.isEmpty ? "提示词暂不可用。请检查 App 安装包中的资源文件。" : model.memoryTransferPrompt)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(EditorPalette.text)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 220)
                        }
                        .padding(13)
                        .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 15))

                        TextField("来源 AI（可选，例如 ChatGPT）", text: $sourceAI)
                            .textFieldStyle(.roundedBorder)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("把回复粘贴到这里").font(.caption.weight(.semibold)).foregroundStyle(EditorPalette.subtle)
                            TextEditor(text: $rawText)
                                .font(.system(.body, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .foregroundStyle(EditorPalette.text)
                                .frame(minHeight: 190)
                                .padding(7)
                                .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 14))
                                .accessibilityLabel("其他 AI 的记忆回复")
                        }
                        if rawText.count > maximumCharacters {
                            Text("内容过长，请控制在 \(maximumCharacters) 个字符以内。")
                                .font(.caption).foregroundStyle(.red)
                        }
                        Button("检查并预览") {
                            candidates = model.memoryImportCandidates(from: rawText)
                            notice = candidates.isEmpty ? "没有识别到 Markdown 条目。原文未保存。" : nil
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || rawText.count > maximumCharacters)

                        Text("健康、财务和推断条目默认不选中。确认后只保存你选中的条目和它们的来源，不保留未选中的内容。历史对话请通过“导入 ChatGPT 聊天记录”单独选择，不会自动转成记忆。")
                            .font(.caption).foregroundStyle(EditorPalette.subtle)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("识别到 \(candidates.count) 条候选。检查每一条；带有 inferred 或敏感信息的内容默认不选中。")
                            .font(.subheadline).foregroundStyle(EditorPalette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(candidates.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(alignment: .top, spacing: 8) {
                                    Toggle("导入", isOn: $candidates[index].isSelected)
                                        .labelsHidden()
                                        .accessibilityLabel("导入第 \(index + 1) 条")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(candidates[index].category).font(.caption.weight(.semibold)).foregroundStyle(EditorPalette.subtle)
                                        TextField("记忆内容", text: $candidates[index].value, axis: .vertical)
                                            .font(.subheadline).foregroundStyle(EditorPalette.text)
                                        if candidates[index].isInferred || candidates[index].isSensitive {
                                            Text([candidates[index].isInferred ? "推断" : nil, candidates[index].isSensitive ? "敏感类别" : nil].compactMap { $0 }.joined(separator: " · "))
                                                .font(.caption2).foregroundStyle(.orange)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 13))
                            }
                        }
                        HStack {
                            Button("返回原文") { candidates = [] }.buttonStyle(.bordered)
                            Spacer()
                            Button("导入所选记忆") {
                                model.acceptMemoryImport(rawText: rawText, sourceAI: sourceAI, candidates: candidates)
                                notice = model.statusText
                                if model.statusText?.hasPrefix("已导入") == true { dismiss() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!candidates.contains(where: { $0.isSelected && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
                        }
                    }

                    if let notice {
                        Text(notice).font(.caption).foregroundStyle(EditorPalette.subtle).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .background(EditorPalette.background)
        .frame(minWidth: 360, minHeight: 560)
    }

    private func copyPrompt() {
        guard !model.memoryTransferPrompt.isEmpty else {
            notice = "提示词资源不可用。"
            return
        }
        #if os(iOS)
        UIPasteboard.general.string = model.memoryTransferPrompt
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.memoryTransferPrompt, forType: .string)
        #endif
        copied = true
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

private struct WorkspaceArchivePanel: View {
    @ObservedObject private var model: OpenMuseAppModel
    @State private var includeConversations = false
    @State private var archiveDocument = WorkspaceArchiveFile(data: Data())
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isShowingImportPreview = false
    @State private var importData: Data?
    @State private var importPreview = ""
    @State private var status: String?

    init(model: OpenMuseAppModel) { self.model = model }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("资料迁移", systemImage: "externaldrive.badge.person.crop")
                .font(.headline).foregroundStyle(EditorPalette.text)
            Text("迁移导出使用 ZIP 目录包，结构化记录存为 JSONL。勾选聊天选项后，才会附带聊天、附件和 Agent 任务草稿；导入会逐项校验，API 密钥不会导出。旧版 JSON 文件仍可导入。")
                .font(.caption).foregroundStyle(EditorPalette.subtle)
            WorkspaceBackupPanel(model: model)
            Toggle("包含聊天记录、活动、AI 迁移原文和任务草稿", isOn: $includeConversations)
                .font(.caption).tint(EditorPalette.blue)
            HStack(spacing: 9) {
                Button("导出资料") {
                    do {
                        archiveDocument = WorkspaceArchiveFile(data: try model.makeWorkspacePortableArchive(includeConversations: includeConversations))
                        isExporting = true
                        status = nil
                    } catch { status = "导出失败：\(error.localizedDescription)" }
                }
                .buttonStyle(.borderedProminent)
                Button("导入迁移文件") { isImporting = true }
                    .buttonStyle(.bordered)
            }
            if let status { Text(status).font(.caption).foregroundStyle(EditorPalette.subtle).textSelection(.enabled) }
            Text("导入不会静默覆盖现有内容；相同内容跳过，不同版本保留为待处理冲突。文件上限 50 MB。")
                .font(.caption2).foregroundStyle(EditorPalette.subtle)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EditorPalette.panel, in: RoundedRectangle(cornerRadius: 18))
        .fileExporter(isPresented: $isExporting, document: archiveDocument, contentType: .zip, defaultFilename: "OpenMuse-migration") { result in
            switch result {
            case .success(let url): status = "迁移文件已保存：\(url.lastPathComponent)"
            case .failure(let error): status = "导出没有完成：\(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json, .zip], allowsMultipleSelection: false) { result in
            do {
                let urls = try result.get()
                guard let url = urls.first else { throw WorkspaceArchiveError.invalidManifest }
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let archive = try WorkspaceArchive.decodePackage(data)
                importData = data
                importPreview = "包含 \(archive.manifest.recordCount) 条记录、\(archive.manifest.revisionCount) 条历史修订和 \(archive.agentWorkspaceFiles.count) 个 Agent 任务草稿。导入将合并到当前工作区；同名不同内容的草稿会另存冲突副本，不覆盖本机文件。"
                isShowingImportPreview = true
                status = nil
            } catch { status = "无法读取迁移文件：\(error.localizedDescription)" }
        }
        .alert("导入预览", isPresented: $isShowingImportPreview) {
            Button("导入并检查冲突") {
                guard let importData else { return }
                do {
                    let report = try model.importWorkspaceArchive(data: importData)
                    status = report.duplicateArchive
                        ? "记录此前已导入；已补回 \(report.importedAgentWorkspaceFiles) 个任务草稿。"
                        : "导入 \(report.importedRecords) 条记录和 \(report.importedAgentWorkspaceFiles) 个任务草稿；保留 \(report.conflicts) 项记录冲突、\(report.preservedAgentWorkspaceConflicts) 个草稿冲突副本。"
                } catch let error as WorkspaceArchiveError {
                    if case .agentWorkspaceRestoreIncomplete = error {
                        status = error.localizedDescription
                    } else {
                        status = "导入失败：\(error.localizedDescription)"
                    }
                } catch { status = "导入失败：\(error.localizedDescription)" }
                self.importData = nil
            }
            Button("取消", role: .cancel) { importData = nil }
        } message: {
            Text(importPreview)
        }
    }
}

private struct WorkspaceArchiveFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .zip] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw WorkspaceArchiveError.invalidManifest }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct SyncConflictList: View {
    @ObservedObject private var model: OpenMuseAppModel

    init(model: OpenMuseAppModel) { self.model = model }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("需要选择保留的版本")
                .font(.caption.weight(.semibold)).foregroundStyle(EditorPalette.text)
            ForEach(model.syncConflicts) { conflict in
                VStack(alignment: .leading, spacing: 9) {
                    Text(conflict.kind == RecordKind.document ? conflict.objectID : conflict.kind)
                        .font(.caption.weight(.medium)).foregroundStyle(EditorPalette.text)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("这台设备 · 第 \(conflict.localRevision) 版")
                            .font(.caption2.weight(.semibold)).foregroundStyle(EditorPalette.subtle)
                        Text(preview(conflict.localPayload, kind: conflict.kind))
                            .font(.caption).foregroundStyle(EditorPalette.text).lineLimit(5).textSelection(.enabled)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("另一台设备 · 第 \(conflict.remoteRevision) 版")
                            .font(.caption2.weight(.semibold)).foregroundStyle(EditorPalette.subtle)
                        Text(preview(conflict.remotePayload, kind: conflict.kind))
                            .font(.caption).foregroundStyle(EditorPalette.text).lineLimit(5).textSelection(.enabled)
                    }
                    HStack(spacing: 8) {
                        Button("保留这台设备的版本") {
                            Task { await model.resolveSyncConflict(id: conflict.id, keepRemote: false) }
                        }
                        .buttonStyle(.bordered)
                        Button("采用另一台设备的版本") {
                            Task { await model.resolveSyncConflict(id: conflict.id, keepRemote: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .font(.caption2)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(EditorPalette.background, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func preview(_ data: Data, kind: String) -> String {
        let decoder = JSONDecoder()
        switch kind {
        case RecordKind.document:
            if let value = try? decoder.decode(WorkspaceDocument.self, from: data) { return "\(value.title)\n\(value.content)" }
        case RecordKind.artifact:
            if let value = try? decoder.decode(ArtifactRecord.self, from: data) { return "\(value.title)\n\(value.content)" }
        case RecordKind.goal:
            if let value = try? decoder.decode(GoalRecord.self, from: data) { return "\(value.title)\n\(value.summary)" }
        case RecordKind.memoryClaim:
            if let value = try? decoder.decode(MemoryClaimRecord.self, from: data) { return value.value }
        case RecordKind.message:
            if let value = try? decoder.decode(MessageRecord.self, from: data) { return value.content }
        default:
            break
        }
        return String(data: data, encoding: .utf8).map { String($0.prefix(700)) } ?? "此版本暂时无法预览。"
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
