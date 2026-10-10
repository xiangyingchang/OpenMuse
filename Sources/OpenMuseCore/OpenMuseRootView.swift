import SwiftUI

public struct OpenMuseRootView: View {
    @ObservedObject private var model: OpenMuseAppModel
    @State private var isDrawerOpen = false

    public init(model: OpenMuseAppModel) {
        self.model = model
    }

    public var body: some View {
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

    private var phoneLayout: some View {
        VStack(spacing: 0) {
            if model.presentedArtifact == nil { topBar }
            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            phoneNavigation
        }
        .background(OpenMusePalette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(item: $model.presentedSheet, content: sheetContent)
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
                    .background(OpenMusePalette.panel, in: Circle())
            }
            .accessibilityLabel("打开侧栏")
            #endif

            Spacer(minLength: 2)
            Button { model.presentedSheet = .companion } label: {
                VStack(spacing: 3) {
                    OpenMuseOrb(isActive: model.isSending, size: 38)
                    Text("OpenMuse")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OpenMusePalette.text)
                    Text(model.activeActivity?.stage ?? model.statusText ?? "陪你把想做的事慢慢做成")
                        .font(.system(size: 11))
                        .foregroundStyle(OpenMusePalette.subtle)
                        .lineLimit(1)
                }
                .frame(maxWidth: 250)
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
                    .background(OpenMusePalette.panel, in: Circle())
            }
            .accessibilityLabel("更多操作")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(OpenMusePalette.background)
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
                        .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(model.selectedSection == section ? OpenMusePalette.text : OpenMusePalette.subtle)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background {
                        if model.selectedSection == section {
                            Capsule().fill(OpenMusePalette.selected)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.rawValue)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().fill(OpenMusePalette.navigation.opacity(0.66)))
        .overlay(Capsule().stroke(OpenMusePalette.border, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 5)
        .padding(.bottom, 5)
        .background(OpenMusePalette.background.opacity(0.82))
    }

    @ViewBuilder
    private func sheetContent(_ sheet: OpenMuseSheet) -> some View {
        switch sheet {
        case .companion: CompanionPanelView(model: model)
        case .settings: ModelSettingsView(model: model)
        case .memories: MemoryFilesView(model: model)
        case .activity: ActivityListView(model: model)
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
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            ForEach(model.artifacts.filter { $0.conversationID == model.currentConversationID }) { artifact in
                                Button { model.openArtifact(artifact) } label: {
                                    ArtifactCard(artifact: artifact)
                                }
                                .buttonStyle(.plain)
                            }
                            if model.isSending {
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
                        .padding(.vertical, 20)
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

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if message.role == .assistant { OpenMuseOrb(isActive: false, size: 23).padding(.top, 2) }
            if message.role == .assistant {
                VStack(alignment: .leading, spacing: 5) {
                    Text(message.status == "failed" ? "这次没有完成" : "OpenMuse")
                        .font(.caption2.weight(.semibold)).foregroundStyle(message.status == "failed" ? OpenMusePalette.warning : OpenMusePalette.subtle)
                    Text(message.content)
                        .font(.system(size: 15))
                        .foregroundStyle(message.status == "failed" ? OpenMusePalette.warning : OpenMusePalette.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 13)
                .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 18))
                Spacer(minLength: 20)
            } else {
                Spacer(minLength: 45)
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 14)
                    .background(OpenMusePalette.blue, in: RoundedRectangle(cornerRadius: 18))
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ChatComposer: View {
    @ObservedObject var model: OpenMuseAppModel

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            TextField("说说你在想什么…", text: $model.draft, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.vertical, 11)
                .padding(.leading, 14)
                .onSubmit { model.sendDraft() }
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
                        .background(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? OpenMusePalette.subtle : OpenMusePalette.blue, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(5)
            }
        }
        .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(OpenMusePalette.border, lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
    }
}

private struct GoalsHomeView: View {
    @ObservedObject var model: OpenMuseAppModel
    @State private var expandedGoalIDs: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeading(title: "目标", subtitle: "从聊天里发现，和你一起往前推。")
                if model.goals.isEmpty {
                    EmptyPanel(symbol: "target", title: "还没有一起追踪的目标", detail: "聊到你想做的事情时，我会先帮你记下来；你随时可以改或关闭。")
                }
                let tracked = model.goals.filter { $0.status != "已完成" && $0.status != "已关闭" }
                if !tracked.isEmpty {
                    Label("追踪中", systemImage: "circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(OpenMusePalette.green)
                    ForEach(tracked) { goal in goalRow(goal) }
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
                    } else {
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
                Text("这是计划进度，不代表已预订交通或住宿。")
                    .font(.caption2).foregroundStyle(OpenMusePalette.subtle)
            }
        }
        .padding(16)
        .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(OpenMusePalette.border, lineWidth: 1))
        .onAppear { if goal.status != "已完成" && goal.status != "已关闭" { expandedGoalIDs.insert(goal.id) } }
    }
}

private struct LibraryHomeView: View {
    @ObservedObject var model: OpenMuseAppModel
    @State private var selectedKind = "构件"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeading(title: "资源库", subtitle: "可以回到聊天继续修改的成果。")
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
                            .contextMenu {
                                ShareLink(item: artifact.content) { Label("分享文字内容", systemImage: "square.and.arrow.up") }
                                Button("打开构件", systemImage: "arrow.up.right.square") { model.openArtifact(artifact) }
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
                Text("旅行计划 · 第 \(artifact.currentRevision) 版")
                    .font(.caption).foregroundStyle(OpenMusePalette.subtle)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(OpenMusePalette.subtle)
        }
        .padding(13)
        .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(OpenMusePalette.border, lineWidth: 1))
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
                    .scaleEffect(reduceMotion ? 1 : 1.08)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isActive)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: OpenMusePalette.blue.opacity(isActive ? 0.38 : 0.14), radius: isActive ? 11 : 5, y: 2)
        .accessibilityLabel(isActive ? "正在工作" : "OpenMuse")
        .animation(.easeInOut(duration: 0.2), value: isActive)
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
