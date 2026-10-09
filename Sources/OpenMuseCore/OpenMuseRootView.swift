import SwiftUI

public struct OpenMuseRootView: View {
    @ObservedObject private var model: OpenMuseAppModel

    public init(model: OpenMuseAppModel) {
        self.model = model
    }

    public var body: some View {
        #if os(macOS)
        macLayout
        #else
        phoneLayout
        #endif
    }

    private var phoneLayout: some View {
        VStack(spacing: 0) {
            topBar
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
                topBar
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
            Button { model.presentedSheet = .activity } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(OpenMusePalette.text)
                    .frame(width: 42, height: 42)
                    .background(OpenMusePalette.panel, in: Circle())
            }
            .accessibilityLabel("最近活动")
            #endif

            Spacer(minLength: 2)
            VStack(spacing: 3) {
                OpenMuseOrb(isActive: model.isSending, size: 34)
                Text("OpenMuse")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OpenMusePalette.text)
                Text(model.activeActivity?.stage ?? "陪你把想做的事慢慢做成")
                    .font(.system(size: 11))
                    .foregroundStyle(OpenMusePalette.subtle)
                    .lineLimit(1)
            }
            .frame(maxWidth: 250)
            Spacer(minLength: 2)
            Button { model.presentedSheet = .settings } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(OpenMusePalette.text)
                    .frame(width: 42, height: 42)
                    .background(OpenMusePalette.panel, in: Circle())
            }
            .accessibilityLabel("模型和应用设置")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(OpenMusePalette.background)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch model.selectedSection {
        case .chat: ChatHomeView(model: model)
        case .goals: GoalsHomeView(model: model)
        case .feed: PlaceholderHomeView(title: "兴趣动态", subtitle: "动态会根据你授权的资料和当前兴趣更新。", symbol: "sparkles", detail: "资料来源连接器还没有启用。这里不会放入虚构的推荐。")
        case .ideas: PlaceholderHomeView(title: "留给你的点子", subtitle: "把了解变成值得尝试的一小步。", symbol: "lightbulb", detail: "点子生成和反馈迭代尚未接入；聊天、目标和已保存的旅行计划可以先用。")
        case .library: LibraryHomeView(model: model)
        }
    }

    private var phoneNavigation: some View {
        HStack(spacing: 4) {
            ForEach(WorkspaceSection.allCases) { section in
                Button { model.selectedSection = section } label: {
                    VStack(spacing: 4) {
                        Image(systemName: section.symbol).font(.system(size: 16, weight: .medium))
                        Text(section.rawValue).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(model.selectedSection == section ? OpenMusePalette.text : OpenMusePalette.subtle)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background {
                        if model.selectedSection == section {
                            RoundedRectangle(cornerRadius: 15).fill(OpenMusePalette.selected)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.rawValue)
            }
        }
        .padding(6)
        .background(OpenMusePalette.navigation, in: Capsule())
        .overlay(Capsule().stroke(OpenMusePalette.border, lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.top, 5)
        .padding(.bottom, 3)
        .background(OpenMusePalette.background)
    }

    @ViewBuilder
    private func sheetContent(_ sheet: OpenMuseSheet) -> some View {
        switch sheet {
        case .settings: ModelSettingsView(model: model)
        case .memories: MemoryFilesView(model: model)
        case .activity: ActivityListView(model: model)
        case .artifact(let artifact): ArtifactEditorView(model: model, artifact: artifact)
        case .document(let document): WorkspaceDocumentEditor(model: model, document: document)
        }
    }
}

private struct ChatHomeView: View {
    @ObservedObject var model: OpenMuseAppModel

    var body: some View {
        VStack(spacing: 0) {
            if let startupError = model.startupError {
                Label(startupError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(OpenMusePalette.warning)
                    .padding(.horizontal, 18).padding(.vertical, 8)
            }
            if let status = model.statusText {
                HStack(spacing: 7) {
                    if model.isSending { ProgressView().controlSize(.small) }
                    Text(status).font(.caption).foregroundStyle(OpenMusePalette.subtle)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18).padding(.vertical, 7)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 17) {
                        if model.messages.isEmpty {
                            welcome
                        }
                        ForEach(model.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        ForEach(model.artifacts.filter { $0.conversationID == model.currentConversationID }) { artifact in
                            Button { model.presentedSheet = .artifact(artifact) } label: {
                                ArtifactCard(artifact: artifact)
                            }
                            .buttonStyle(.plain)
                        }
                        if model.isSending {
                            HStack(spacing: 9) {
                                OpenMuseOrb(isActive: true, size: 22)
                                Text("我在整理思路")
                                    .font(.subheadline).foregroundStyle(OpenMusePalette.subtle)
                                ProgressView().controlSize(.small)
                            }
                            .padding(.leading, 4)
                            .id("working")
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: model.messages.count) { _, _ in
                    if let last = model.messages.last { withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(last.id, anchor: .bottom) } }
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
                Button { Task { await model.send("帮我规划一趟去恩施的 7 天旅行，日期还没定。") } } label: {
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
                .disabled(model.isSending)
                .onSubmit { model.sendDraft() }
            Button { model.sendDraft() } label: {
                Image(systemName: model.isSending ? "hourglass" : "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSending ? OpenMusePalette.subtle : OpenMusePalette.blue, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSending)
            .padding(5)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeading(title: "想做的事", subtitle: "从聊天里发现，和你一起往前推。")
                if model.goals.isEmpty {
                    EmptyPanel(symbol: "target", title: "还没有一起追踪的目标", detail: "聊到你想做的事情时，我会先帮你记下来；你随时可以改或关闭。")
                }
                ForEach(model.goals) { goal in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            Image(systemName: "map.fill").foregroundStyle(OpenMusePalette.blue)
                                .frame(width: 34, height: 34).background(OpenMusePalette.selected, in: RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(goal.title).font(.headline).foregroundStyle(OpenMusePalette.text)
                                Text(goal.summary).font(.caption).foregroundStyle(OpenMusePalette.subtle)
                            }
                            Spacer(minLength: 4)
                            Text(goal.status).font(.caption2).foregroundStyle(OpenMusePalette.subtle)
                        }
                        ProgressView(value: Double(goal.steps.filter(\.isComplete).count), total: Double(max(goal.steps.count, 1)))
                            .tint(OpenMusePalette.blue)
                        ForEach(goal.steps) { step in
                            Button { model.toggleGoalStep(goalID: goal.id, stepID: step.id) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: step.isComplete ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(step.isComplete ? OpenMusePalette.green : OpenMusePalette.subtle)
                                    Text(step.title).foregroundStyle(step.isComplete ? OpenMusePalette.subtle : OpenMusePalette.text)
                                    Spacer()
                                }
                                .font(.subheadline)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.trianglehead.2.clockwise")
                            Text("这是旅行计划，不代表已预订交通或住宿")
                        }
                        .font(.caption2).foregroundStyle(OpenMusePalette.subtle)
                    }
                    .padding(16)
                    .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 19))
                    .overlay(RoundedRectangle(cornerRadius: 19).stroke(OpenMusePalette.border, lineWidth: 1))
                }
            }
            .padding(18)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct LibraryHomeView: View {
    @ObservedObject var model: OpenMuseAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeading(title: "资源库", subtitle: "可以回到聊天继续修改的成果。")
                if model.artifacts.isEmpty {
                    EmptyPanel(symbol: "square.grid.2x2", title: "成果会留在这里", detail: "当我们整理出完整的旅行路线时，它会同时出现在聊天和资源库。")
                }
                ForEach(model.artifacts) { artifact in
                    Button { model.presentedSheet = .artifact(artifact) } label: { ArtifactCard(artifact: artifact) }
                        .buttonStyle(.plain)
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

private struct PlaceholderHomeView: View {
    let title: String
    let subtitle: String
    let symbol: String
    let detail: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeading(title: title, subtitle: subtitle)
                EmptyPanel(symbol: symbol, title: "这一部分还在准备中", detail: detail)
            }
            .padding(18)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct PageHeading: View {
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

private struct EmptyPanel: View {
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

private struct OpenMuseOrb: View {
    let isActive: Bool
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [OpenMusePalette.blue, Color(red: 0.54, green: 0.44, blue: 0.94), Color(red: 0.35, green: 0.72, blue: 0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.white.opacity(isActive ? 0.32 : 0.19)).frame(width: size * 0.4, height: size * 0.25).blur(radius: 3).offset(x: -size * 0.15, y: -size * 0.19)
            if isActive {
                Circle().stroke(.white.opacity(0.55), lineWidth: 1).padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: OpenMusePalette.blue.opacity(isActive ? 0.38 : 0.17), radius: isActive ? 11 : 5, y: 2)
        .accessibilityLabel(isActive ? "正在工作" : "OpenMuse")
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

private enum OpenMusePalette {
    static let background = Color(red: 0.055, green: 0.064, blue: 0.078)
    static let panel = Color(red: 0.105, green: 0.119, blue: 0.142)
    static let navigation = Color(red: 0.09, green: 0.103, blue: 0.123)
    static let selected = Color(red: 0.15, green: 0.19, blue: 0.28)
    static let border = Color.white.opacity(0.07)
    static let text = Color(red: 0.94, green: 0.95, blue: 0.98)
    static let subtle = Color(red: 0.57, green: 0.61, blue: 0.68)
    static let blue = Color(red: 0.31, green: 0.51, blue: 0.98)
    static let green = Color(red: 0.38, green: 0.8, blue: 0.62)
    static let warning = Color(red: 1, green: 0.64, blue: 0.38)
}

#if os(macOS)
private typealias PlatformTextEditor = TextEditor
#endif
