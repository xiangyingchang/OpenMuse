import SwiftUI

struct NavigationDrawerView: View {
    @ObservedObject var model: OpenMuseAppModel
    let onClose: () -> Void
    @State private var query = ""

    private var visibleConversations: [ConversationRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return model.conversations }
        return model.conversations.filter { $0.title.localizedCaseInsensitiveContains(needle) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("OpenMuse").font(.system(size: 21, weight: .semibold)).foregroundStyle(OpenMusePalette.text)
                Spacer()
                Button {
                    model.presentedSheet = .settings
                    onClose()
                } label: {
                    Image(systemName: "gearshape").frame(width: 42, height: 42)
                }
                .accessibilityLabel("设置")
                Button(action: onClose) {
                    Image(systemName: "xmark").frame(width: 42, height: 42)
                }
                .accessibilityLabel("关闭侧栏")
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(OpenMusePalette.text)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("选项卡").font(.caption.weight(.semibold)).foregroundStyle(OpenMusePalette.subtle)
                        }
                        ForEach(WorkspaceSection.allCases) { section in
                            Button {
                                model.presentedArtifact = nil
                                model.selectedSection = section
                                onClose()
                            } label: {
                                Label(section.rawValue, systemImage: section.symbol)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(model.selectedSection == section && model.presentedArtifact == nil ? OpenMusePalette.text : OpenMusePalette.subtle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .frame(height: 44)
                                    .background {
                                        if model.selectedSection == section && model.presentedArtifact == nil {
                                            RoundedRectangle(cornerRadius: 13).fill(OpenMusePalette.selected)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    conversationGroup("聊天", values: visibleConversations.filter { $0.parentConversationID == nil })
                    conversationGroup("旁聊", values: visibleConversations.filter { $0.parentConversationID != nil })
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }

            Divider().overlay(OpenMusePalette.border)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(OpenMusePalette.subtle)
                TextField("搜索对话", text: $query)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .accessibilityLabel("搜索对话")
                Menu {
                    Button("新对话", systemImage: "square.and.pencil") {
                        model.beginNewConversation()
                        onClose()
                    }
                    Button("新建旁聊", systemImage: "bubble.left.and.bubble.right") {
                        model.beginSideConversation()
                        onClose()
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(OpenMusePalette.text)
                        .frame(width: 42, height: 42)
                        .background(OpenMusePalette.selected, in: Circle())
                }
                .accessibilityLabel("新建对话")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(OpenMusePalette.panel.ignoresSafeArea())
        .overlay(alignment: .trailing) { Rectangle().fill(OpenMusePalette.border).frame(width: 1) }
    }

    @ViewBuilder
    private func conversationGroup(_ title: String, values: [ConversationRecord]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(OpenMusePalette.subtle)
            if values.isEmpty {
                Text(title == "旁聊" ? "复杂的事情可以开一个旁聊，主聊会留在原处。" : "新对话会显示在这里。")
                    .font(.caption).foregroundStyle(OpenMusePalette.subtle.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                ForEach(values) { conversation in
                    Button {
                        model.openConversation(conversation.id)
                        onClose()
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: conversation.parentConversationID == nil ? "bubble.left" : "arrow.turn.down.right")
                                .foregroundStyle(OpenMusePalette.subtle)
                                .frame(width: 21)
                            Text(conversation.title == "新对话" && conversation.parentConversationID != nil ? "新旁聊" : conversation.title)
                                .font(.subheadline)
                                .foregroundStyle(OpenMusePalette.text)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if conversation.id == model.currentConversationID {
                                Circle().fill(OpenMusePalette.blue).frame(width: 7, height: 7)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private enum CompanionPanelTab: String, CaseIterable, Identifiable {
    case activity = "活动"
    case approvals = "批准"
    case computer = "桌面端"
    case recent = "近期"
    case identity = "身份"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .activity: "list.bullet"
        case .approvals: "checkmark.shield"
        case .computer: "desktopcomputer"
        case .recent: "clock"
        case .identity: "person.crop.circle"
        }
    }
}

struct CompanionPanelView: View {
    @ObservedObject var model: OpenMuseAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: CompanionPanelTab = .activity

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 42, height: 42)
                }
                .accessibilityLabel("关闭陪伴者面板")
                Spacer()
                ShareLink(item: "OpenMuse：陪你把想做的事慢慢做成。") {
                    Image(systemName: "square.and.arrow.up").frame(width: 42, height: 42)
                }
                .accessibilityLabel("分享 OpenMuse")
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(OpenMusePalette.text)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            OpenMuseOrb(isActive: model.isSending, size: 82).padding(.top, 8)
            Text("OpenMuse").font(.system(size: 25, weight: .semibold)).foregroundStyle(OpenMusePalette.text).padding(.top, 7)
            Label(statusText, systemImage: statusSymbol)
                .font(.subheadline).foregroundStyle(model.isSending ? OpenMusePalette.blue : OpenMusePalette.subtle)
                .padding(.top, 4)

            HStack(spacing: 4) {
                ForEach(CompanionPanelTab.allCases) { tab in
                    Button { selectedTab = tab } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(selectedTab == tab ? OpenMusePalette.text : OpenMusePalette.subtle)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background {
                                if selectedTab == tab { Capsule().fill(OpenMusePalette.selected) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.rawValue)
                }
            }
            .padding(5)
            .background(OpenMusePalette.navigation, in: Capsule())
            .overlay(Capsule().stroke(OpenMusePalette.border, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.top, 19)
            .padding(.bottom, 14)

            ScrollView {
                Group {
                    switch selectedTab {
                    case .activity:
                        ActivityRecordsList(model: model)
                    case .approvals:
                        EmptyPanel(symbol: "checkmark.shield", title: "没有待处理的批准", detail: "需要你确认的操作会显示在这里。OpenMuse 当前不会替你发送邮件、支付或执行未经确认的外部操作。")
                            .padding(.horizontal, 18)
                    case .computer:
                        VStack(alignment: .leading, spacing: 12) {
                            PageHeading(title: "桌面端", subtitle: model.macBridgePaired ? "已配对家里的 Mac" : "iPhone 可独立使用；连接 Mac 后可优先交给它处理。")
                            HStack(spacing: 10) {
                                Image(systemName: "desktopcomputer").foregroundStyle(OpenMusePalette.blue)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(model.macBridgePaired ? "已配对 Mac" : "尚未连接 Mac").foregroundStyle(OpenMusePalette.text)
                                    Text(model.contextDescription).font(.caption).foregroundStyle(OpenMusePalette.subtle)
                                }
                                Spacer()
                                Image(systemName: model.macBridgePaired ? "checkmark.circle.fill" : "wifi.slash")
                                    .foregroundStyle(model.macBridgePaired ? OpenMusePalette.green : OpenMusePalette.subtle)
                            }
                            .padding(15)
                            .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 16))
                            Button("连接与设备设置") { model.presentedSheet = .settings }
                                .buttonStyle(.borderedProminent)
                            EmptyPanel(symbol: "globe", title: "浏览器控制尚未接入", detail: "连接 Mac 目前只代理模型对话。此处不会显示虚构的远程桌面或浏览器画面。")
                        }
                        .padding(.horizontal, 18)
                    case .recent:
                        EmptyPanel(symbol: "clock", title: "还没有定时任务", detail: "定时提醒和周期任务能力尚未接入。准备好后，计划、暂停和补跑状态会在这里显示。")
                            .padding(.horizontal, 18)
                    case .identity:
                        MemoryFilesView(model: model)
                    }
                }
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
            }
        }
        .background(OpenMusePalette.background)
        .presentationDragIndicator(.visible)
    }

    private var statusText: String {
        if model.isSending { return model.activeActivity?.stage ?? "正在回复" }
        if let statusText = model.statusText { return statusText }
        if model.macBridgePaired { return "已配对家里的 Mac" }
        return "iPhone 独立模式"
    }

    private var statusSymbol: String {
        if model.isSending { return "sparkles" }
        return model.macBridgePaired ? "bolt.fill" : "iphone"
    }
}

struct ActivityRecordsList: View {
    @ObservedObject var model: OpenMuseAppModel
    @State private var selectedActivity: ActivityRecord?

    private var dayGroups: [(Date, [ActivityRecord])] {
        let groups = Dictionary(grouping: model.activities) { Calendar.current.startOfDay(for: $0.createdAt) }
        return groups.keys.sorted(by: >).map { day in
            (day, (groups[day] ?? []).sorted { $0.updatedAt > $1.updatedAt })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.activities.isEmpty {
                EmptyPanel(symbol: "list.bullet", title: "还没有活动", detail: "聊一个想做的事，它会从这里开始留下记录。")
            }
            ForEach(dayGroups, id: \.0) { group in
                let day = group.0
                let activities = group.1
                VStack(alignment: .leading, spacing: 8) {
                    Text(dayLabel(day)).font(.headline).foregroundStyle(OpenMusePalette.text)
                    ForEach(activities) { activity in
                        Button { selectedActivity = activity } label: {
                            HStack(alignment: .top, spacing: 12) {
                                ActivityStatusMark(status: activity.status)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(activity.title).font(.subheadline.weight(.semibold)).foregroundStyle(OpenMusePalette.text)
                                    Text(activity.stage).font(.caption).foregroundStyle(OpenMusePalette.subtle).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(activity.updatedAt.formatted(date: .omitted, time: .shortened))
                                        .font(.caption2).foregroundStyle(OpenMusePalette.subtle.opacity(0.75))
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(OpenMusePalette.subtle)
                            }
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .sheet(item: $selectedActivity) { activity in
            ActivityDetailSheet(model: model, initialActivity: activity)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今天" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: .now), calendar.isDate(day, inSameDayAs: yesterday) { return "昨天" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct ActivityStatusMark: View {
    let status: String

    var body: some View {
        ZStack {
            Circle().fill(OpenMusePalette.selected)
            if status == "running" { ProgressView().controlSize(.small) }
            else {
                Image(systemName: status == "completed" ? "checkmark" : status == "failed" ? "exclamationmark" : "pause.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(status == "completed" ? OpenMusePalette.green : OpenMusePalette.subtle)
            }
        }
        .frame(width: 34, height: 34)
    }
}

private struct ActivityDetailSheet: View {
    @ObservedObject var model: OpenMuseAppModel
    @Environment(\.dismiss) private var dismiss
    let initialActivity: ActivityRecord

    private var activity: ActivityRecord {
        model.activities.first(where: { $0.id == initialActivity.id }) ?? initialActivity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(statusLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(OpenMusePalette.selected, in: RoundedRectangle(cornerRadius: 8))
                    Text(activity.title).font(.title3.weight(.semibold)).foregroundStyle(OpenMusePalette.text)
                    Text(activity.stage).font(.subheadline).foregroundStyle(OpenMusePalette.subtle)
                    Text(activity.updatedAt.formatted(date: .numeric, time: .shortened))
                        .font(.caption).foregroundStyle(OpenMusePalette.subtle)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 42, height: 42) }
                    .buttonStyle(.bordered).accessibilityLabel("关闭活动详情")
            }
            Divider()
            if let steps = activity.steps, !steps.isEmpty {
                ScrollView {
                    ActivityTimeline(steps: steps)
                }
                .frame(maxHeight: 390)
            } else {
                Label("这项活动没有细分执行记录，只显示已保存的最新状态。", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(OpenMusePalette.subtle)
            }
            Spacer(minLength: 0)
            Button {
                model.openActivity(activity)
                dismiss()
            } label: {
                Label("继续这段对话", systemImage: "bubble.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OpenMusePalette.panel)
    }

    private var statusLabel: String {
        switch activity.status {
        case "running": "进行中"
        case "completed": "已完成"
        case "failed": "失败"
        case "suspended": "已暂停"
        case "cancelled": "已取消"
        default: activity.status
        }
    }
}

private struct ActivityTimeline: View {
    let steps: [ActivityStepRecord]

    private var groups: [(String, [ActivityStepRecord])] {
        let grouped = Dictionary(grouping: steps, by: \.group)
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(groups, id: \.0) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(groupLabel(group.0)).font(.caption.weight(.semibold)).foregroundStyle(OpenMusePalette.text)
                    ForEach(Array(group.1.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 11) {
                            VStack(spacing: 0) {
                                stepMark(step.status)
                                if index < group.1.count - 1 {
                                    Rectangle().fill(OpenMusePalette.border).frame(width: 1, height: 25)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).font(.subheadline.weight(.medium)).foregroundStyle(OpenMusePalette.text)
                                Text(step.detail).font(.caption).foregroundStyle(OpenMusePalette.subtle).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func groupLabel(_ group: String) -> String {
        switch group {
        case "MAIN": "OpenMuse 正在为你处理"
        default: group
        }
    }

    @ViewBuilder
    private func stepMark(_ status: String) -> some View {
        if status == "running" {
            ProgressView().controlSize(.small).frame(width: 24, height: 24)
        } else {
            Image(systemName: status == "completed" ? "checkmark.circle.fill" : status == "failed" ? "xmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(status == "completed" ? OpenMusePalette.green : status == "failed" ? OpenMusePalette.warning : OpenMusePalette.subtle)
                .frame(width: 24, height: 24)
        }
    }
}

struct FeedHomeView: View {
    @ObservedObject var model: OpenMuseAppModel
    @AppStorage("openmuse.feed.instruction") private var instruction = "根据我最近在准备的旅行，分享我可能感兴趣的路线灵感和地方故事。"
    @State private var isEditing = false
    @State private var draft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeading(title: "动态", subtitle: "按照你的兴趣，慢慢发现值得了解的内容。")
                if isEditing {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("你希望看到什么？").font(.subheadline.weight(.semibold)).foregroundStyle(OpenMusePalette.text)
                        TextEditor(text: $draft)
                            .frame(minHeight: 105)
                            .scrollContentBackground(.hidden)
                            .padding(9)
                            .background(OpenMusePalette.background, in: RoundedRectangle(cornerRadius: 14))
                        HStack {
                            Button("取消") { isEditing = false; draft = instruction }.buttonStyle(.bordered)
                            Spacer()
                            Button("保存") {
                                let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !clean.isEmpty { instruction = clean }
                                isEditing = false
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(15)
                    .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 18))
                } else {
                    Button {
                        draft = instruction
                        isEditing = true
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text(instruction).font(.subheadline).foregroundStyle(OpenMusePalette.text).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "slider.horizontal.3").foregroundStyle(OpenMusePalette.subtle)
                        }
                        .padding(14)
                        .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("编辑动态兴趣指令")
                }
                EmptyPanel(symbol: "sparkles", title: "还没有新的动态", detail: "兴趣推荐和内容来源尚未接入。OpenMuse 不会用虚构内容填满这里；连接器启用后，推荐会说明来源和推荐理由。")
            }
            .padding(18)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .onAppear { if draft.isEmpty { draft = instruction } }
    }
}

private struct GoalIdea: Identifiable {
    let goal: GoalRecord
    var id: String { goal.id }
    var title: String { "为「\(goal.title)」整理一份轻松的下一步清单" }
    var detail: String { "把目前还没确认的事收拢起来，之后可以边聊边调整。" }
}

struct IdeasHomeView: View {
    @ObservedObject var model: OpenMuseAppModel
    @State private var selectedIdea: GoalIdea?
    @State private var hiddenIDs: Set<String> = []

    private var ideas: [GoalIdea] {
        model.goals
            .filter { $0.status != "已完成" && $0.status != "已关闭" && !hiddenIDs.contains($0.id) }
            .map { GoalIdea(goal: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeading(title: "点子", subtitle: "从你正在做的事里，找一个值得尝试的小步。")
                if ideas.isEmpty {
                    EmptyPanel(symbol: "lightbulb", title: "暂时没有新点子", detail: "当我们一起追踪目标后，我会从已有的事情里找可尝试的下一步。点子开始前会先说明能得到什么，由你决定要不要继续。")
                }
                ForEach(ideas) { idea in
                    Button { selectedIdea = idea } label: {
                        HStack(alignment: .top, spacing: 13) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 19)).foregroundStyle(OpenMusePalette.blue)
                                .frame(width: 34, height: 34)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(idea.title).font(.headline).foregroundStyle(OpenMusePalette.text).frame(maxWidth: .infinity, alignment: .leading)
                                Text(idea.detail).font(.subheadline).foregroundStyle(OpenMusePalette.subtle).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(OpenMusePalette.subtle).padding(.top, 5)
                        }
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("暂时不看", systemImage: "eye.slash") { hiddenIDs.insert(idea.id) }
                    }
                    if idea.id != ideas.last?.id { Divider().overlay(OpenMusePalette.border) }
                }
            }
            .padding(18)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $selectedIdea) { idea in
            IdeaDetailSheet(idea: idea) {
                model.beginSideConversation(parentConversationID: idea.goal.conversationID)
                model.draft = "帮我为「\(idea.goal.title)」整理一份轻松、可调整的下一步清单。只依据已有信息；不确定的事情先问我。"
                model.sendDraft()
                selectedIdea = nil
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct IdeaDetailSheet: View {
    let idea: GoalIdea
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(idea.title).font(.title3.weight(.semibold)).foregroundStyle(OpenMusePalette.text)
            Text(idea.detail).font(.body).foregroundStyle(OpenMusePalette.subtle)
            Divider()
            Text("开始后会") .font(.headline).foregroundStyle(OpenMusePalette.text)
            Label("新建一段关联当前目标的旁聊", systemImage: "bubble.left.and.bubble.right")
            Label("先给出可调整的清单，不会自动完成外部操作", systemImage: "checkmark.shield")
                .font(.subheadline).foregroundStyle(OpenMusePalette.subtle)
            Spacer(minLength: 4)
            Button(action: onStart) {
                Label("开始吧", systemImage: "sparkles")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OpenMusePalette.panel)
    }
}

struct ArtifactPreviewView: View {
    @ObservedObject var model: OpenMuseAppModel
    let artifact: ArtifactRecord
    @State private var showingHistory = false

    private var currentArtifact: ArtifactRecord {
        model.artifacts.first(where: { $0.id == artifact.id }) ?? artifact
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { model.presentedArtifact = nil } label: {
                    Image(systemName: "chevron.left").frame(width: 42, height: 42)
                }
                .buttonStyle(.plain).accessibilityLabel("返回")
                Spacer(minLength: 0)
                Text(currentArtifact.title).font(.headline).foregroundStyle(OpenMusePalette.text).lineLimit(1)
                Spacer(minLength: 0)
                Menu {
                    Button("编辑正文", systemImage: "pencil") { model.presentedSheet = .artifact(currentArtifact) }
                    Button("版本历史", systemImage: "clock.arrow.circlepath") { showingHistory = true }
                    ShareLink(item: currentArtifact.content) { Label("分享正文", systemImage: "square.and.arrow.up") }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 42, height: 42)
                }
                .accessibilityLabel("构件操作")
            }
            .foregroundStyle(OpenMusePalette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(OpenMusePalette.panel)

            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.richtext").foregroundStyle(OpenMusePalette.blue)
                        Text("第 \(currentArtifact.currentRevision) 版 · 旅行计划草稿")
                            .font(.caption).foregroundStyle(OpenMusePalette.subtle)
                    }
                    MarkdownContentView(content: currentArtifact.content)
                }
                .padding(20)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(OpenMusePalette.background)
        .sheet(isPresented: $showingHistory) {
            ArtifactHistoryPanel(model: model, artifact: currentArtifact)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct MarkdownContentView: View {
    let content: String
    private var lines: [String] { content.components(separatedBy: .newlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(lines.enumerated()), id: \.offset) { item in
                let index = item.offset
                let line = item.element
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    EmptyView()
                } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    table(at: index)
                } else if line.hasPrefix("### ") {
                    markdownText(String(line.dropFirst(4))).font(.headline).foregroundStyle(OpenMusePalette.text)
                } else if line.hasPrefix("## ") {
                    markdownText(String(line.dropFirst(3))).font(.title3.weight(.semibold)).foregroundStyle(OpenMusePalette.text)
                } else if line.hasPrefix("# ") {
                    markdownText(String(line.dropFirst(2))).font(.title2.weight(.bold)).foregroundStyle(OpenMusePalette.text)
                } else if line.hasPrefix("- ") || line.hasPrefix("• ") {
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(OpenMusePalette.blue).frame(width: 5, height: 5).padding(.top, 8)
                        markdownText(String(line.dropFirst(2))).font(.body).foregroundStyle(OpenMusePalette.text)
                    }
                } else {
                    markdownText(line).font(.body).foregroundStyle(OpenMusePalette.text)
                }
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func table(at index: Int) -> some View {
        if index == 0 || !lines[index - 1].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
            let rows = tableRows(startingAt: index)
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, cells in
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                                markdownText(cell)
                                    .font(rowIndex == 0 ? .caption.weight(.semibold) : .caption)
                                    .foregroundStyle(OpenMusePalette.text)
                                    .frame(width: 150, alignment: .leading)
                                    .padding(10)
                            }
                        }
                        .background(rowIndex == 0 ? OpenMusePalette.selected : OpenMusePalette.panel)
                        Divider().overlay(OpenMusePalette.border)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 13))
            }
            .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 13))
        }
    }

    private func tableRows(startingAt index: Int) -> [[String]] {
        var rows: [[String]] = []
        for line in lines.dropFirst(index) {
            let clean = line.trimmingCharacters(in: .whitespaces)
            guard clean.hasPrefix("|") else { break }
            let cells = clean.split(separator: "|", omittingEmptySubsequences: false)
                .dropFirst().dropLast().map { String($0).trimmingCharacters(in: .whitespaces) }
            if !cells.isEmpty && !cells.allSatisfy({ $0.replacingOccurrences(of: ":", with: "").allSatisfy({ $0 == "-" }) }) {
                rows.append(cells)
            }
        }
        return rows
    }

    private func markdownText(_ value: String) -> Text {
        if let parsed = try? AttributedString(markdown: value) { return Text(parsed) }
        return Text(value)
    }
}

private struct ArtifactHistoryPanel: View {
    @ObservedObject var model: OpenMuseAppModel
    @Environment(\.dismiss) private var dismiss
    let artifact: ArtifactRecord
    @State private var pendingRestore: ArtifactRecord?
    @State private var showingRestoreConfirmation = false

    private var history: [ArtifactRecord] { model.artifactHistory(id: artifact.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("版本历史").font(.title3.weight(.semibold)).foregroundStyle(OpenMusePalette.text)
            Text("恢复旧版会另存为新版本，原记录仍然保留。")
                .font(.caption).foregroundStyle(OpenMusePalette.subtle)
            if history.isEmpty {
                EmptyPanel(symbol: "clock.arrow.circlepath", title: "还没有历史版本", detail: "修改并保存后会开始记录版本。")
            } else {
                ScrollView {
                    ForEach(history) { revision in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("第 \(revision.currentRevision) 版")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(OpenMusePalette.text)
                                Text(revision.updatedAt.formatted(date: .numeric, time: .shortened))
                                    .font(.caption).foregroundStyle(OpenMusePalette.subtle)
                            }
                            Spacer()
                            if revision.currentRevision == artifact.currentRevision {
                                Text("当前").font(.caption).foregroundStyle(OpenMusePalette.blue)
                            } else {
                                Button("恢复") { pendingRestore = revision; showingRestoreConfirmation = true }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding(12)
                        .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 13))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(OpenMusePalette.background)
        .confirmationDialog("把这个版本恢复为最新版本？", isPresented: $showingRestoreConfirmation, titleVisibility: .visible) {
            Button("恢复为新版本") {
                if let pendingRestore { model.restoreArtifact(pendingRestore); dismiss() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前版本和历史版本都会保留。")
        }
    }
}
