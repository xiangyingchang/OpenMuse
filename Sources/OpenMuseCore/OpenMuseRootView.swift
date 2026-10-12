import Combine
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

public struct OpenMuseRootView: View {
    @ObservedObject private var model: OpenMuseAppModel
    @State private var isDrawerOpen = false
    @State private var isKeyboardPresented = false

    public init(model: OpenMuseAppModel) {
        self.model = model
    }

    private var topBarActionOffset: CGFloat {
        #if os(iOS)
        return -23
        #else
        return 0
        #endif
    }

    public var body: some View {
        Group {
        #if os(macOS)
        macLayout
        #else
        GeometryReader { geometry in
            let drawerWidth = min(geometry.size.width * 0.82, 360)
            ZStack(alignment: .leading) {
                phoneLayout
                    .scaleEffect(isDrawerOpen ? 0.96 : 1, anchor: .leading)
                    .offset(x: isDrawerOpen ? drawerWidth * 0.84 : 0)
                    .disabled(isDrawerOpen)
                    .overlay {
                        if isDrawerOpen {
                            Color.black.opacity(0.42)
                                .ignoresSafeArea()
                                .onTapGesture { closeDrawer() }
                        }
                    }
                if isDrawerOpen {
                    NavigationDrawerView(model: model, onClose: closeDrawer)
                        .frame(width: drawerWidth, height: geometry.size.height)
                        .transition(.move(edge: .leading))
                        .zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.black.ignoresSafeArea())
            .animation(.spring(response: 0.34, dampingFraction: 0.88), value: isDrawerOpen)
        }
        #endif
        }
        .onAppear { model.runScheduledWorkspaceBackupIfDue() }
        #if os(macOS)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            model.runScheduledWorkspaceBackupIfDue()
        }
        #endif
    }

    private var phoneLayout: some View {
        VStack(spacing: 0) {
            if model.selectedSection == .chat, model.presentedArtifact == nil {
                ZStack(alignment: .top) {
                    sectionContent
                    topBar
                        .zIndex(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if model.presentedArtifact == nil { topBar }
                sectionContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !isKeyboardPresented {
                phoneNavigation
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(OpenMusePalette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.18), value: isKeyboardPresented)
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardPresented = false
        }
        #endif
        .sheet(item: $model.presentedSheet) { sheet in
            if case .companion = sheet {
                CompanionPanelView(model: model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(0)
                    .presentationBackground(OpenMusePalette.background)
            } else {
                sheetContent(sheet)
            }
        }
    }

    #if os(macOS)
    private var macLayout: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 11) {
                    OpenMuseOrb(isActive: model.isSending, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OpenMuse").font(.headline)
                        Text(model.activeActivity?.stage ?? "在这里陪你")
                            .font(.caption).foregroundStyle(OpenMusePalette.subtle)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 20)
                Button { model.beginNewConversation() } label: {
                    Label("新对话", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 10)
                List(selection: $model.selectedSection) {
                    ForEach(WorkspaceSection.allCases) { section in
                        Label(section.rawValue, systemImage: section.symbol).tag(section)
                    }
                }
                .scrollContentBackground(.hidden)
                Spacer(minLength: 4)
                Button { model.presentedSheet = .memories } label: {
                    Label("身份与记忆", systemImage: "person.crop.circle")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                Button { model.presentedSheet = .settings } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(minWidth: 210)
            .background(OpenMusePalette.panel)
        } detail: {
            VStack(spacing: 0) {
                if model.presentedArtifact == nil { topBar }
                sectionContent
            }
            .background(OpenMusePalette.background)
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $model.presentedSheet, content: sheetContent)
    }
    #endif

    private var topBar: some View {
        HStack(spacing: 10) {
            #if os(iOS)
            Button { withAnimation { isDrawerOpen = true } } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(OpenMusePalette.text)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().fill(Color.white.opacity(0.05)))
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.7))
                    .offset(y: topBarActionOffset)
            }
            .accessibilityLabel("打开侧栏")
            #endif

            Spacer(minLength: 2)
            Button { model.presentedSheet = .companion } label: {
                #if os(iOS)
                VStack(spacing: -2) {
                    OpenMuseOrb(isActive: model.isSending, size: 64)
                    Text("OpenMuse")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OpenMusePalette.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().fill(Color.white.opacity(0.06)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.7))
                        .shadow(color: .black.opacity(0.22), radius: 4, y: 1)
                        .zIndex(1)
                    if model.isSending {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9, weight: .semibold))
                            Text(model.activeActivity?.stage ?? "正在回复")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .foregroundStyle(OpenMusePalette.text.opacity(0.9))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .shadow(color: .black.opacity(0.9), radius: 3, y: 1)
                        .accessibilityIdentifier("openmuse-reply-status")
                    }
                }
                .frame(maxWidth: 220)
                .fixedSize(horizontal: true, vertical: false)
                #else
                VStack(spacing: 3) {
                    OpenMuseOrb(isActive: model.isSending, size: 38)
                    Text("OpenMuse")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OpenMusePalette.text)
                    if let status = model.activeActivity?.stage ?? model.statusText {
                        Text(status)
                            .font(.system(size: 11))
                            .foregroundStyle(OpenMusePalette.subtle)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 250)
                #endif
            }
            .buttonStyle(.plain)
            .accessibilityLabel("OpenMuse，查看活动、设备与身份")
            Spacer(minLength: 2)
            Menu {
                if model.selectedSection == .chat {
                    Button("新对话", systemImage: "square.and.pencil") { model.beginNewConversation() }
                    Button("新建旁聊", systemImage: "bubble.left.and.bubble.right") { model.beginSideConversation() }
                    Divider()
                }
                Button("最近活动", systemImage: "clock") { model.presentedSheet = .activity }
                Button("模型与连接设置", systemImage: "slider.horizontal.3") { model.presentedSheet = .settings }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(OpenMusePalette.text)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().fill(Color.white.opacity(0.05)))
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.7))
                    .offset(y: topBarActionOffset)
            }
            .accessibilityLabel("更多操作")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.clear)
    }

    @ViewBuilder
    private var sectionContent: some View {
        ZStack {
            Group {
                switch model.selectedSection {
                case .chat: ChatHomeView(model: model)
                case .goals: GoalsHomeView(model: model)
                case .feed: FeedHomeView(model: model)
                case .ideas: IdeasHomeView(model: model)
                case .library: LibraryHomeView(model: model)
                }
            }
            .opacity(model.presentedArtifact == nil ? 1 : 0)
            .allowsHitTesting(model.presentedArtifact == nil)
            if let artifact = model.presentedArtifact {
                ArtifactPreviewView(model: model, artifact: artifact)
                    .transition(.opacity)
            }
        }
    }

    private var phoneNavigation: some View {
        HStack(spacing: 4) {
            ForEach(WorkspaceSection.allCases) { section in
                Button {
                    model.presentedArtifact = nil
                    model.selectedSection = section
                } label: {
                    Image(systemName: section.symbol)
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(OpenMusePalette.text.opacity(model.selectedSection == section ? 1 : 0.82))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background {
                            if model.selectedSection == section {
                                Capsule()
                                    .fill(Color.black.opacity(0.48))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.7))
                                    .padding(.horizontal, -3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.rawValue)
            }
        }
        .padding(6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(OpenMusePalette.navigation.opacity(0.66)))
        }
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
        .padding(.horizontal, 20)
        .padding(.top, 5)
        .padding(.bottom, 5)
        .background(OpenMusePalette.background.opacity(0.82))
        .accessibilityIdentifier("phone-tab-navigation")
    }

    @ViewBuilder
    private func sheetContent(_ sheet: OpenMuseSheet) -> some View {
        switch sheet {
        case .companion: CompanionPanelView(model: model)
        case .settings: ModelSettingsView(model: model)
        case .memories: MemoryFilesView(model: model)
        case .activity: ActivityListView(model: model)
        case .memoryImport: MemoryImportView(model: model)
        case .artifact(let artifact): ArtifactEditorView(model: model, artifact: artifact)
        case .document(let document): WorkspaceDocumentEditor(model: model, document: document)
        }
    }

    private func closeDrawer() {
        withAnimation { isDrawerOpen = false }
    }
}

private struct ChatHomeView: View {
    @ObservedObject var model: OpenMuseAppModel
    @State private var showScrollToLatest = false

    var body: some View {
        VStack(spacing: 0) {
            if let startupError = model.startupError {
                Label(startupError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(OpenMusePalette.warning)
                    .padding(.horizontal, 18).padding(.vertical, 8)
            }
            GeometryReader { scrollGeometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 17) {
                            if model.messages.isEmpty {
                                welcome.frame(minHeight: scrollGeometry.size.height, alignment: .center)
                            }
                            ForEach(model.messages) { message in
                                MessageBubble(message: message, model: model)
                                    .id(message.id)
                            }
                            if !model.liveResponse.isEmpty {
                                MessageBubble(message: MessageRecord(
                                    id: "live-response-\(model.currentConversationID)",
                                    conversationID: model.currentConversationID,
                                    role: .assistant,
                                    content: model.liveResponse,
                                    status: "streaming"
                                ), model: model)
                                .id("live-response")
                            }
                            ForEach(model.artifacts.filter { $0.conversationID == model.currentConversationID }) { artifact in
                                Button { model.openArtifact(artifact) } label: {
                                    ArtifactCard(artifact: artifact)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("artifact-\(artifact.id)")
                            }
                            if model.isSending && model.liveResponse.isEmpty {
                                HStack(spacing: 9) {
                                    OpenMuseOrb(isActive: true, size: 22)
                                    Text(model.activeActivity?.stage ?? "我在整理思路")
                                        .font(.subheadline).foregroundStyle(OpenMusePalette.subtle)
                                    ProgressView().controlSize(.small)
                                }
                                .padding(.leading, 4)
                                .id("working")
                            }
                            Color.clear.frame(height: 1).id("chat-bottom")
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, model.messages.isEmpty ? 20 : 112)
                        .padding(.bottom, 20)
                        .frame(maxWidth: 780)
                        .frame(maxWidth: .infinity)
                    }
                    .defaultScrollAnchor(.bottom)
                    .simultaneousGesture(DragGesture(minimumDistance: 10).onEnded { value in
                        if value.translation.height > 18 {
                            showScrollToLatest = true
                        } else if value.translation.height < -18 {
                            showScrollToLatest = false
                        }
                    })
                    .onChange(of: model.messages.count) { _, _ in
                        guard !showScrollToLatest else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("chat-bottom", anchor: .bottom) }
                    }
                    .onChange(of: model.liveResponse) { _, _ in
                        guard !showScrollToLatest else { return }
                        proxy.scrollTo("chat-bottom", anchor: .bottom)
                    }
                    .onChange(of: model.currentConversationID) { _, _ in
                        showScrollToLatest = false
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("chat-bottom", anchor: .bottom) }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if showScrollToLatest {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("chat-bottom", anchor: .bottom) }
                                showScrollToLatest = false
                            } label: {
                                Label("回到最新", systemImage: "arrow.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(OpenMusePalette.blue, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 18)
                            .padding(.bottom, 14)
                        }
                    }
                }
            }
            if !model.isModelReady {
                Button { model.presentedSheet = .settings } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "key.horizontal")
                        Text("先连接一个模型，就可以开始聊天")
                        Spacer()
                        Text("设置").fontWeight(.semibold)
                    }
                    .font(.caption)
                    .foregroundStyle(OpenMusePalette.text)
                    .padding(12)
                    .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
            }
            ChatComposer(model: model)
        }
        .background(OpenMusePalette.background)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                OpenMuseOrb(isActive: false, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("嗨，我是 OpenMuse。")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(OpenMusePalette.text)
                    Text("不用先想好全部细节，我们可以边聊边安排。")
                        .font(.subheadline).foregroundStyle(OpenMusePalette.subtle)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("可以从一趟旅行开始")
                    .font(.caption.weight(.semibold)).foregroundStyle(OpenMusePalette.subtle)
                Button {
                    model.draft = "帮我规划一趟去恩施的 7 天旅行，日期还没定。"
                    model.sendDraft()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "map.fill").foregroundStyle(OpenMusePalette.blue)
                        Text("帮我规划一趟去恩施的 7 天旅行").foregroundStyle(OpenMusePalette.text)
                        Spacer()
                        Image(systemName: "arrow.up.right").foregroundStyle(OpenMusePalette.subtle)
                    }
                    .font(.subheadline)
                    .padding(14)
                    .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 17))
                    .overlay(RoundedRectangle(cornerRadius: 17).stroke(OpenMusePalette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(17)
        .background(OpenMusePalette.panel.opacity(0.55), in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct MessageBubble: View {
    let message: MessageRecord
    @ObservedObject var model: OpenMuseAppModel
    @State private var attachmentToDelete: AttachmentRecord?

    @ViewBuilder
    private var attachments: some View {
        let records = model.attachmentRecords(for: message)
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(records) { record in
                    HStack(spacing: 8) {
                        if let url = model.attachmentURL(id: record.id) {
                            ShareLink(item: url) {
                                Label(record.displayName, systemImage: record.mediaType == "application/pdf" ? "doc.richtext" : "doc.text")
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                            }
                            .accessibilityIdentifier("message-attachment-\(record.id)")
                        } else {
                            Label("\(record.displayName) · 本机文件缺失", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(OpenMusePalette.warning)
                        }
                        Button(role: .destructive) {
                            attachmentToDelete = record
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(OpenMusePalette.subtle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除附件 \(record.displayName)")
                        .accessibilityIdentifier("delete-attachment-\(record.id)")
                    }
                }
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if message.role == .assistant { OpenMuseOrb(isActive: false, size: 23).padding(.top, 2) }
            if message.role == .assistant {
                VStack(alignment: .leading, spacing: 5) {
                    Text(message.status == "failed" ? "这次没有完成" : "OpenMuse")
                        .font(.caption2.weight(.semibold)).foregroundStyle(message.status == "failed" ? OpenMusePalette.warning : OpenMusePalette.subtle)
                    Group {
                        if message.status == "failed" {
                            Text(message.content)
                                .font(.system(size: 15))
                                .foregroundStyle(OpenMusePalette.warning)
                                .textSelection(.enabled)
                        } else {
                            MarkdownContentView(content: message.content, bodyFont: .system(size: 15), lineSpacing: 5)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    attachments
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 13)
                .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 18))
                Spacer(minLength: 20)
            } else {
                Spacer(minLength: 45)
                VStack(alignment: .leading, spacing: 7) {
                    if !message.content.isEmpty {
                        Text(message.content)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                    }
                    attachments
                        .tint(.white)
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 14)
                .background(OpenMusePalette.blue, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .frame(maxWidth: .infinity)
        .confirmationDialog(
            "删除这个附件？",
            isPresented: Binding(
                get: { attachmentToDelete != nil },
                set: { if !$0 { attachmentToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除附件", role: .destructive) {
                if let record = attachmentToDelete { model.forgetAttachment(id: record.id) }
                attachmentToDelete = nil
            }
            Button("取消", role: .cancel) { attachmentToDelete = nil }
        } message: {
            Text("OpenMuse 会删除本机原件和消息引用；已连接设备收到同步后也会清除副本。聊天正文仍保留。")
        }
    }
}

private struct ChatComposer: View {
    @ObservedObject var model: OpenMuseAppModel
    @State private var isImportingAttachments = false
    @State private var isChoosingResource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !model.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(model.pendingAttachments) { item in
                            HStack(spacing: 5) {
                                Image(systemName: item.mediaType == "application/pdf" ? "doc.richtext" : "doc.text")
                                Text(item.displayName).lineLimit(1)
                                Button { model.removePendingAttachment(id: item.id) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("移除附件 \(item.displayName)")
                            }
                            .font(.caption)
                            .foregroundStyle(OpenMusePalette.text)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(OpenMusePalette.background, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                }
            }
            HStack(alignment: .center, spacing: 8) {
                Button { isChoosingResource = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(OpenMusePalette.subtle)
                        .frame(width: 36, height: 38)
                }
                .buttonStyle(.plain)
                .disabled(model.isSending)
                .accessibilityLabel("打开资源库")
                .accessibilityIdentifier("chat-add-attachment")
                .confirmationDialog("资源库", isPresented: $isChoosingResource, titleVisibility: .visible) {
                    Button { isImportingAttachments = true } label: {
                        Label("添加文件", systemImage: "doc.badge.plus")
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("目前支持 TXT、Markdown 和 PDF 文件。")
                }
                TextField("说说你在想什么…", text: $model.draft, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 11)
                    .onSubmit { model.sendDraft() }
                    .accessibilityIdentifier("chat-composer-input")
                if model.isSending {
                    #if os(iOS)
                    Button { model.cancelCurrentResponse() } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(OpenMusePalette.blue, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("停止回复")
                    .padding(5)
                    #else
                    ProgressView().controlSize(.small).frame(width: 38, height: 38).padding(5)
                    #endif
                } else {
                    Button { model.sendDraft() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.pendingAttachments.isEmpty ? OpenMusePalette.subtle : OpenMusePalette.blue, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.pendingAttachments.isEmpty)
                    .accessibilityLabel("发送")
                    .padding(5)
                }
            }
        }
        .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(OpenMusePalette.border, lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
        .fileImporter(
            isPresented: $isImportingAttachments,
            allowedContentTypes: [.plainText, UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText, .pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): model.queueAttachments(at: urls)
            case .failure: break
            }
        }
    }
}

private struct GoalsHomeView: View {
    @ObservedObject var model: OpenMuseAppModel
    @State private var expandedGoalIDs: Set<String> = []
    @State private var expandedHistoryIDs: Set<String> = []
    @State private var goalHistoryByID: [String: [GoalRecord]] = [:]
    @State private var selectedReminderGoal: GoalRecord?
    @State private var reminderDate = Date().addingTimeInterval(3_600)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeading(title: "目标", subtitle: "从聊天里发现，和你一起往前推。")
                if model.goals.isEmpty {
                    EmptyPanel(symbol: "target", title: "还没有一起追踪的目标", detail: "聊到你想做的事情时，我会先帮你记下来；你随时可以改或关闭。")
                }
                let tracked = model.goals.filter { $0.status == "进行中" }
                if !tracked.isEmpty {
                    Label("追踪中", systemImage: "circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(OpenMusePalette.green)
                    ForEach(tracked) { goal in goalRow(goal) }
                }
                let paused = model.goals.filter { $0.status == "已暂停" }
                if !paused.isEmpty {
                    Label("已暂停（不会主动推进）", systemImage: "pause.circle")
                        .font(.caption.weight(.semibold)).foregroundStyle(OpenMusePalette.subtle)
                    ForEach(paused) { goal in goalRow(goal) }
                }
                let finished = model.goals.filter { $0.status == "已完成" || $0.status == "已关闭" }
                if !finished.isEmpty {
                    DisclosureGroup("已完成与已关闭（\(finished.count)）") {
                        ForEach(finished) { goal in goalRow(goal) }
                    }
                    .foregroundStyle(OpenMusePalette.subtle)
                }
            }
            .padding(18)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $selectedReminderGoal) { goal in
            GoalReminderEditorSheet(goal: goal, dueAt: $reminderDate) { dueAt in
                Task { await model.scheduleGoalReminder(goalID: goal.id, dueAt: dueAt) }
            }
        }
    }

    @ViewBuilder
    private func goalRow(_ goal: GoalRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    if expandedGoalIDs.contains(goal.id) { expandedGoalIDs.remove(goal.id) }
                    else { expandedGoalIDs.insert(goal.id) }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Image(systemName: expandedGoalIDs.contains(goal.id) ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.bold)).foregroundStyle(OpenMusePalette.subtle)
                            Text(goal.title).font(.headline).foregroundStyle(OpenMusePalette.text)
                        }
                        Text(goal.summary).font(.caption).foregroundStyle(OpenMusePalette.subtle)
                        Text("\(goal.steps.filter(\.isComplete).count) / \(goal.steps.count) 项完成")
                            .font(.caption2).foregroundStyle(OpenMusePalette.subtle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Menu {
                    if goal.status == "已完成" || goal.status == "已关闭" {
                        Button("重新追踪") { model.setGoalStatus(goalID: goal.id, status: "进行中") }
                    } else if goal.status == "已暂停" {
                        Button("恢复追踪") { model.setGoalStatus(goalID: goal.id, status: "进行中") }
                        Button("标记完成") { model.setGoalStatus(goalID: goal.id, status: "已完成") }
                        Button("关闭追踪") { model.setGoalStatus(goalID: goal.id, status: "已关闭") }
                    } else {
                        Button("暂停追踪") { model.setGoalStatus(goalID: goal.id, status: "已暂停") }
                        Button("标记完成") { model.setGoalStatus(goalID: goal.id, status: "已完成") }
                        Button("关闭追踪") { model.setGoalStatus(goalID: goal.id, status: "已关闭") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(OpenMusePalette.subtle)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("目标操作")
            }
            if expandedGoalIDs.contains(goal.id) {
                Divider().overlay(OpenMusePalette.border)
                ForEach(goal.steps) { step in
                    Button { model.toggleGoalStep(goalID: goal.id, stepID: step.id) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: step.isComplete ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(step.isComplete ? OpenMusePalette.green : OpenMusePalette.subtle)
                            Text(step.title).foregroundStyle(step.isComplete ? OpenMusePalette.subtle : OpenMusePalette.text)
                            Spacer(minLength: 0)
                        }
                        .font(.subheadline)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                let progressEvents = model.goalProgressEvents.filter { $0.goalID == goal.id }.sorted { $0.createdAt > $1.createdAt }
                if !progressEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle")
                            Text("进展记录").accessibilityIdentifier("goal-progress-heading")
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(OpenMusePalette.subtle)
                        ForEach(progressEvents.prefix(5)) { event in
                            let source = model.goalProgressSourceMessage(for: event)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(event.stepID.flatMap { stepID in goal.steps.first(where: { $0.id == stepID })?.title } ?? "目标已完成")
                                        .font(.subheadline.weight(.medium)).foregroundStyle(OpenMusePalette.text)
                                    Spacer(minLength: 8)
                                    Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2).foregroundStyle(OpenMusePalette.subtle)
                                }
                                if let source {
                                    Text(source.role == .assistant ? "来自 OpenMuse 保存的计划" : "来自你在聊天中的表达")
                                        .font(.caption2.weight(.medium)).foregroundStyle(OpenMusePalette.subtle)
                                    Text(source.content.trimmingCharacters(in: .whitespacesAndNewlines))
                                        .font(.caption).foregroundStyle(OpenMusePalette.subtle).lineLimit(3)
                                } else {
                                    Text("来源消息目前不可用。")
                                        .font(.caption).foregroundStyle(OpenMusePalette.subtle)
                                }
                                Button("查看对话") { model.openGoalProgressSource(event) }
                                    .font(.caption.weight(.medium)).foregroundStyle(OpenMusePalette.blue)
                                    .accessibilityIdentifier("goal-progress-open-\(event.id)")
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(OpenMusePalette.background, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.top, 3)
                }
                Button {
                    if expandedHistoryIDs.contains(goal.id) {
                        expandedHistoryIDs.remove(goal.id)
                    } else {
                        goalHistoryByID[goal.id] = model.goalHistory(id: goal.id)
                        expandedHistoryIDs.insert(goal.id)
                    }
                } label: {
                    Label(expandedHistoryIDs.contains(goal.id) ? "收起进度记录" : "查看进度记录", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(OpenMusePalette.blue)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("goal-history-\(goal.id)")
                if expandedHistoryIDs.contains(goal.id) {
                    let history = goalHistoryByID[goal.id] ?? []
                    if history.isEmpty {
                        Text("这个目标还没有可查看的修订记录。")
                            .font(.caption).foregroundStyle(OpenMusePalette.subtle)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(history.enumerated()), id: \.element.id) { index, revision in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("第\(index + 1)版 · \(revision.status) · \(revision.steps.filter(\.isComplete).count)/\(revision.steps.count) 项完成")
                                        .font(.caption.weight(.medium)).foregroundStyle(OpenMusePalette.text)
                                    Text(revision.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2).foregroundStyle(OpenMusePalette.subtle)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.leading, 8)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("目标进度修订历史")
                    }
                }
                if goal.status == "进行中" {
                    Button {
                        reminderDate = Date().addingTimeInterval(3_600)
                        selectedReminderGoal = goal
                    } label: {
                        Label("设置提醒", systemImage: "bell.badge")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(OpenMusePalette.blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("goal-reminder-\(goal.id)")
                }
                Text("这是计划进度，不代表已预订交通或住宿。")
                    .font(.caption2).foregroundStyle(OpenMusePalette.subtle)
            }
        }
        .padding(16)
        .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(OpenMusePalette.border, lineWidth: 1))
        .onAppear { if goal.status == "进行中" { expandedGoalIDs.insert(goal.id) } }
    }
}

private struct GoalReminderEditorSheet: View {
    let goal: GoalRecord
    @Binding var dueAt: Date
    let onSave: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("提醒目标") {
                    Text(goal.title).foregroundStyle(OpenMusePalette.text)
                    DatePicker("提醒时间", selection: $dueAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                }
                Section {
                    Text("这会安排一条本机系统提醒。锁屏时不会调用模型；到时间后打开 OpenMuse，再决定是否继续。")
                        .font(.footnote)
                        .foregroundStyle(OpenMusePalette.subtle)
                }
            }
            .navigationTitle("设置提醒")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(dueAt)
                        dismiss()
                    }
                    .accessibilityIdentifier("save-goal-reminder")
                }
            }
        }
        .tint(OpenMusePalette.blue)
    }
}

private struct LibraryHomeView: View {
    @ObservedObject var model: OpenMuseAppModel
    @State private var selectedKind = "构件"
    @State private var artifactToDelete: ArtifactRecord?
    @State private var showingDeleteConfirmation = false
    @State private var isImportingArtifactPackage = false
    @State private var importNotice = ""
    @State private var showingImportNotice = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    PageHeading(title: "资源库", subtitle: "可以回到聊天继续修改的成果。")
                    Button { isImportingArtifactPackage = true } label: {
                        Image(systemName: "square.and.arrow.down")
                            .frame(width: 42, height: 42)
                            .background(OpenMusePalette.panel, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("导入构件包")
                    .accessibilityIdentifier("import-artifact-package")
                }
                Picker("资源类型", selection: $selectedKind) {
                    Text("构件").tag("构件")
                    Text("影音内容").tag("影音内容")
                }
                .pickerStyle(.segmented)
                if selectedKind == "构件" && model.artifacts.isEmpty {
                    EmptyPanel(symbol: "square.grid.2x2", title: "成果会留在这里", detail: "当我们整理出完整的旅行路线时，它会同时出现在聊天和资源库。")
                }
                if selectedKind == "构件" {
                    ForEach(model.artifacts) { artifact in
                        Button { model.openArtifact(artifact) } label: { ArtifactCard(artifact: artifact) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("artifact-\(artifact.id)")
                            .contextMenu {
                                ShareLink(item: artifact.content) { Label("分享文字内容", systemImage: "square.and.arrow.up") }
                                Button("打开构件", systemImage: "arrow.up.right.square") { model.openArtifact(artifact) }
                                Divider()
                                Button("永久删除构件…", systemImage: "trash", role: .destructive) {
                                    artifactToDelete = artifact
                                    showingDeleteConfirmation = true
                                }
                            }
                    }
                } else {
                    EmptyPanel(symbol: "photo.on.rectangle.angled", title: "还没有影音内容", detail: "OpenMuse 目前尚未接入媒体采集或生成。连接器启用后，已保存的图片、视频和音频会显示在这里。")
                }
            }
            .padding(18)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("永久删除这个构件？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("永久删除", role: .destructive) {
                if let artifactToDelete { model.deleteArtifact(id: artifactToDelete.id) }
                artifactToDelete = nil
            }
            Button("取消", role: .cancel) { artifactToDelete = nil }
        } message: {
            Text("当前版本和所有历史版本都会删除，并同步到已连接的设备。这个操作无法撤销。")
        }
        .fileImporter(isPresented: $isImportingArtifactPackage, allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
            do {
                let urls = try result.get()
                guard let url = urls.first else { throw CocoaError(.fileReadNoSuchFile) }
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? Int.max
                guard fileSize <= ArtifactPortablePackage.maximumBytes else {
                    throw ArtifactPackageError.tooLarge
                }
                let imported = try model.importArtifactPackage(data: Data(contentsOf: url))
                importNotice = "“\(imported.title)”已加入资源库。"
            } catch {
                importNotice = "没有导入构件：\(error.localizedDescription)"
            }
            showingImportNotice = true
        }
        .alert("构件包", isPresented: $showingImportNotice) {
            Button("好", role: .cancel) {}
        } message: {
            Text(importNotice)
        }
    }
}

private struct ArtifactCard: View {
    let artifact: ArtifactRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(OpenMusePalette.blue)
                .frame(width: 42, height: 42)
                .background(OpenMusePalette.selected, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(artifact.title).font(.subheadline.weight(.semibold)).foregroundStyle(OpenMusePalette.text)
                Text("第 \(artifact.currentRevision) 版 · \(artifact.travelProgressLabel)")
                    .font(.caption).foregroundStyle(OpenMusePalette.subtle)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(OpenMusePalette.subtle)
        }
        .padding(13)
        .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(OpenMusePalette.border, lineWidth: 1))
    }
}

extension ArtifactRecord {
    var travelProgressLabel: String {
        let activeVariant = travelPlanVariants?.first(where: { $0.id == selectedTravelPlanVariantID })
        let coveredDays = activeVariant?.coveredDayCount ?? coveredDayCount
        let expectedDays = activeVariant?.expectedDayCount ?? expectedDayCount
        guard let coveredDays, coveredDays > 0 else { return "旅行计划草稿" }
        let progress: String
        guard let expectedDays, expectedDays > 0 else {
            progress = "已整理 \(coveredDays) 天"
            if let variants = travelPlanVariants, variants.count > 1 { return "\(variants.count) 个方案 · \(progress)" }
            return progress
        }
        if coveredDays >= expectedDays {
            progress = "已覆盖全部 \(expectedDays) 天"
        } else {
            progress = "当前覆盖 \(coveredDays)/\(expectedDays) 天"
        }
        if let variants = travelPlanVariants, variants.count > 1 { return "\(variants.count) 个方案 · \(progress)" }
        return progress
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 24, weight: .semibold)).foregroundStyle(OpenMusePalette.text)
            Text(subtitle).font(.subheadline).foregroundStyle(OpenMusePalette.subtle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 3)
    }
}

struct EmptyPanel: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(OpenMusePalette.blue)
            Text(title).font(.headline).foregroundStyle(OpenMusePalette.text)
            Text(detail).font(.subheadline).foregroundStyle(OpenMusePalette.subtle).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(OpenMusePalette.border, lineWidth: 1))
    }
}

struct OpenMuseOrb: View {
    let isActive: Bool
    var size: CGFloat = 32
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 0.93, green: 0.91, blue: 1), Color(red: 0.78, green: 0.85, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.white.opacity(0.3)).frame(width: size * 0.68, height: size * 0.68).blur(radius: size * 0.09).offset(x: -size * 0.12, y: -size * 0.18)
            HStack(spacing: size * 0.18) {
                Circle().fill(Color(red: 0.20, green: 0.22, blue: 0.30))
                Circle().fill(Color(red: 0.20, green: 0.22, blue: 0.30))
            }
            .frame(width: size * 0.25, height: size * 0.075)
            .offset(y: -size * 0.035)
            HStack(spacing: size * 0.24) {
                Circle().fill(Color.pink.opacity(0.42)).frame(width: size * 0.11, height: size * 0.065).blur(radius: size * 0.035)
                Circle().fill(Color.pink.opacity(0.42)).frame(width: size * 0.11, height: size * 0.065).blur(radius: size * 0.035)
            }
            .offset(y: size * 0.075)
            Capsule().fill(Color(red: 0.34, green: 0.30, blue: 0.38))
                .frame(width: size * 0.12, height: max(1, size * 0.035))
                .offset(y: size * 0.09)
            if isActive {
                Circle().stroke(OpenMusePalette.blue.opacity(0.8), lineWidth: max(1, size * 0.035))
                    .padding(size * 0.08)
                    .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.18 : 0.88))
                    .opacity(reduceMotion ? 0.8 : (isPulsing ? 0.18 : 0.9))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .scaleEffect(isActive && !reduceMotion && isPulsing ? 1.025 : 1)
        .shadow(color: OpenMusePalette.blue.opacity(isActive ? 0.38 : 0.14), radius: isActive ? 11 : 5, y: 2)
        .accessibilityLabel(isActive ? "正在工作" : "OpenMuse")
        .animation(isActive && !reduceMotion ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .easeOut(duration: 0.18), value: isPulsing)
        .onAppear { isPulsing = isActive && !reduceMotion }
        .onChange(of: isActive) { _, active in isPulsing = active && !reduceMotion }
        .onChange(of: reduceMotion) { _, reduced in isPulsing = isActive && !reduced }
    }
}

enum OpenMusePalette {
    static let background = Color.black
    static let panel = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let navigation = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let selected = Color(red: 0.18, green: 0.18, blue: 0.19)
    static let border = Color.white.opacity(0.07)
    static let text = Color(red: 0.94, green: 0.95, blue: 0.98)
    static let subtle = Color(red: 0.57, green: 0.61, blue: 0.68)
    static let blue = Color(red: 0.10, green: 0.55, blue: 1)
    static let green = Color(red: 0.38, green: 0.8, blue: 0.62)
    static let warning = Color(red: 1, green: 0.64, blue: 0.38)
}

#if os(macOS)
private typealias PlatformTextEditor = TextEditor
#endif
