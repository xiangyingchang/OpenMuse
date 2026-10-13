import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private enum ArtifactExportTypes {
    static let markdown = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    static let pdf = UTType.pdf
    static let zip = UTType.zip
}

struct NavigationDrawerView: View {
    @ObservedObject var model: OpenMuseAppModel
    let onClose: () -> Void
    @State private var query = ""
    @State private var pendingDeleteConversation: ConversationRecord?
    @State private var isDeleteConfirmationPresented = false

    private var visibleConversations: [ConversationRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let available = model.conversations.filter { $0.isPrimary != true && $0.isArchived != true }
        guard !needle.isEmpty else { return available }
        return available.filter { $0.title.localizedCaseInsensitiveContains(needle) }
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
                        ForEach(WorkspaceSection.drawerSections) { section in
                            Button {
                                if section == .chat { model.beginNewConversation() }
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
                            .accessibilityIdentifier(section.accessibilityIdentifier)
                        }
                    }

                    conversationGroup("旁聊", values: visibleConversations.filter { $0.parentConversationID != nil })
                    let importedConversations = visibleConversations.filter { $0.importedFrom != nil && $0.parentConversationID == nil }
                    if !importedConversations.isEmpty {
                        conversationGroup("导入的聊天", values: importedConversations)
                    }
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
                Button {
                    let primaryID = model.conversations.first(where: { $0.isPrimary == true && $0.isArchived != true })?.id
                    model.beginSideConversation(parentConversationID: primaryID)
                    onClose()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(OpenMusePalette.text)
                        .frame(width: 42, height: 42)
                        .background(OpenMusePalette.selected, in: Circle())
                }
                .accessibilityLabel("新建旁聊")
                .accessibilityIdentifier("start-side-conversation")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(OpenMusePalette.panel.ignoresSafeArea())
        .overlay(alignment: .trailing) { Rectangle().fill(OpenMusePalette.border).frame(width: 1) }
        .confirmationDialog(
            "删除这个旁聊？",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("删除旁聊", role: .destructive) {
                if let pendingDeleteConversation {
                    _ = model.deleteSideConversation(id: pendingDeleteConversation.id)
                }
                pendingDeleteConversation = nil
            }
            Button("取消", role: .cancel) { pendingDeleteConversation = nil }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("navigation-drawer")
    }

    private var deleteConfirmationMessage: String {
        guard let pendingDeleteConversation else {
            return "聊天记录和附件会删除；活动、目标、成果和已确认记忆会保留。"
        }
        let title = pendingDeleteConversation.title == "新对话" ? "这个旁聊" : "“\(pendingDeleteConversation.title)”"
        return "\(title)的聊天记录和附件会删除；活动、目标、成果和已确认记忆会保留。"
    }

    @ViewBuilder
    private func conversationGroup(_ title: String, values: [ConversationRecord]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(OpenMusePalette.subtle)
            if values.isEmpty {
                Text(title == "旁聊" ? "你发起的旁聊会显示在这里。" : "没有符合搜索条件的聊天。")
                    .font(.caption).foregroundStyle(OpenMusePalette.subtle.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                ForEach(values) { conversation in
                    HStack(spacing: 2) {
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
                                    .accessibilityIdentifier("conversation-title-\(conversation.id)")
                                if let importedFrom = conversation.importedFrom {
                                    Text(importedFrom)
                                        .font(.caption2)
                                        .foregroundStyle(OpenMusePalette.subtle)
                                }
                                Spacer(minLength: 0)
                                if conversation.id == model.currentConversationID {
                                    Circle().fill(OpenMusePalette.blue).frame(width: 7, height: 7)
                                }
                            }
                            .padding(.leading, 10)
                            .frame(height: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(conversation.title == "新对话" && conversation.parentConversationID != nil ? "新旁聊" : conversation.title)
                        .accessibilityIdentifier("conversation-row-\(conversation.id)")
                        .accessibilityValue(conversation.id == model.currentConversationID ? "当前对话" : "未选中")

                        if conversation.parentConversationID != nil,
                           conversation.importedFrom == nil,
                           conversation.importedSourceID == nil {
                            Menu {
                                Button("删除旁聊", systemImage: "trash", role: .destructive) {
                                    pendingDeleteConversation = conversation
                                    isDeleteConfirmationPresented = true
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(OpenMusePalette.subtle)
                                    .frame(width: 36, height: 40)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("旁聊操作：\(conversation.title)")
                            .accessibilityIdentifier("delete-side-conversation-\(conversation.id)")
                        }
                    }
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
    var showsSheetActions = true
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: CompanionPanelTab = .activity

    var body: some View {
        VStack(spacing: 0) {
            OpenMuseOrb(isActive: model.isSending, size: 86).padding(.top, 12)
            Text("OpenMuse").font(.system(size: 25, weight: .semibold)).foregroundStyle(OpenMusePalette.text).padding(.top, 14)
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
                            .frame(height: 40)
                            .background {
                                if selectedTab == tab { Capsule().fill(OpenMusePalette.selected) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.rawValue)
                }
            }
            .padding(4)
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
                        if model.pendingToolApprovals.isEmpty {
                            EmptyPanel(symbol: "checkmark.shield", title: "没有待处理的批准", detail: "正式工作区写入需要逐次确认。iSH 隔离运行与公开网页只读查询不会逐条打断。")
                                .padding(.horizontal, 18)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(model.pendingToolApprovals) { request in
                                    ToolApprovalCard(
                                        request: request,
                                        onApprove: { model.approveToolAction(id: request.id) },
                                        onReject: { model.rejectToolAction(id: request.id) }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                        }
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
                        GoalRemindersList(model: model)
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
        .background(OpenMusePalette.background.ignoresSafeArea())
        .accessibilityIdentifier("companion-page")
        .overlay(alignment: .top) {
            if showsSheetActions {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").frame(width: 40, height: 40)
                            .background(OpenMusePalette.panel, in: Circle())
                            .overlay(Circle().stroke(OpenMusePalette.border, lineWidth: 1))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("关闭陪伴者面板")
                    Spacer()
                    ShareLink(item: "OpenMuse") {
                        Image(systemName: "square.and.arrow.up").frame(width: 40, height: 40)
                            .background(OpenMusePalette.panel, in: Circle())
                            .overlay(Circle().stroke(OpenMusePalette.border, lineWidth: 1))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("分享 OpenMuse")
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(OpenMusePalette.text)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .onAppear {
            if !model.pendingToolApprovals.isEmpty { selectedTab = .approvals }
        }
        .onChange(of: model.pendingToolApprovals.count) { _, count in
            if count > 0 { selectedTab = .approvals }
        }
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

private struct ToolApprovalCard: View {
    let request: ModelToolApprovalRequest
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.badge.arrow.up")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(OpenMusePalette.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("请求写入本机工作区")
                        .font(.headline)
                        .foregroundStyle(OpenMusePalette.text)
                    Text("仅限当前对话；不会修改长期记忆或共享资料。")
                        .font(.caption)
                        .foregroundStyle(OpenMusePalette.subtle)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("目标文件")
                    .font(.caption.weight(.semibold)).foregroundStyle(OpenMusePalette.subtle)
                Text(request.path)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(OpenMusePalette.text)
                    .textSelection(.enabled)
                Text(request.replacesExistingFile
                     ? "将替换现有文件（\(request.existingFileByteCount) 字节）"
                     : "将新建文件")
                    .font(.caption)
                    .foregroundStyle(request.replacesExistingFile ? OpenMusePalette.warning : OpenMusePalette.subtle)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("完整正文预览")
                        .font(.caption.weight(.semibold)).foregroundStyle(OpenMusePalette.subtle)
                    Spacer()
                    Text("\(request.byteCount) 字节").font(.caption2).foregroundStyle(OpenMusePalette.subtle)
                }
                ScrollView {
                    Text(request.content)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(OpenMusePalette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(maxHeight: 220)
                .background(OpenMusePalette.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(OpenMusePalette.border, lineWidth: 1))
            }

            HStack(spacing: 10) {
                Button("拒绝", role: .destructive, action: onReject)
                    .accessibilityIdentifier("reject-tool-approval-\(request.id)")
                Spacer(minLength: 0)
                Button("允许本次写入", action: onApprove)
                    .buttonStyle(.borderedProminent)
                    .tint(OpenMusePalette.blue)
                    .accessibilityIdentifier("approve-tool-approval-\(request.id)")
            }
        }
        .padding(14)
        .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(OpenMusePalette.border, lineWidth: 1))
    }
}

private struct GoalRemindersList: View {
    @ObservedObject var model: OpenMuseAppModel

    private var activeReminders: [ScheduleRecord] {
        model.schedules.filter { !["completed", "cancelled"].contains($0.status) }
    }

    private var finishedReminders: [ScheduleRecord] {
        model.schedules.filter { ["completed", "cancelled"].contains($0.status) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeading(title: "近期提醒", subtitle: "只在约定时间提醒你回来看看，不会在锁屏时运行模型。")
            if activeReminders.isEmpty {
                EmptyPanel(symbol: "bell", title: "还没有目标提醒", detail: "在进行中的目标里选择“设置提醒”，约定一个回来继续的时间。")
            } else {
                ForEach(activeReminders) { reminder in reminderCard(reminder) }
            }
            if !finishedReminders.isEmpty {
                DisclosureGroup("已完成与已取消（\(finishedReminders.count)）") {
                    ForEach(finishedReminders) { reminder in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reminder.title).font(.subheadline.weight(.medium))
                            Text("\(reminder.dueAt.formatted(date: .abbreviated, time: .shortened)) · \(reminder.status == "completed" ? "已完成" : "已取消")")
                                .font(.caption).foregroundStyle(OpenMusePalette.subtle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(OpenMusePalette.subtle)
            }
        }
        .onAppear { model.refreshDueSchedules() }
    }

    private func reminderCard(_ reminder: ScheduleRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: reminder.status == "paused" ? "pause.circle" : reminder.status == "due" ? "bell.badge.fill" : "bell")
                    .foregroundStyle(reminder.status == "due" ? Color.orange : OpenMusePalette.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(reminder.title).font(.headline).foregroundStyle(OpenMusePalette.text)
                    Text("\(reminder.dueAt.formatted(date: .abbreviated, time: .shortened)) · \(statusLabel(reminder.status))")
                        .font(.caption).foregroundStyle(OpenMusePalette.subtle)
                    Text(notificationDescription(reminder.notificationStatus))
                        .font(.caption2).foregroundStyle(OpenMusePalette.subtle)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                if reminder.status == "scheduled" {
                    Button("暂停") { Task { await model.setScheduleStatus(id: reminder.id, status: "paused") } }
                        .accessibilityIdentifier("pause-reminder-\(reminder.id)")
                } else if reminder.status == "paused", reminder.dueAt > .now {
                    Button("恢复") { Task { await model.setScheduleStatus(id: reminder.id, status: "scheduled") } }
                        .accessibilityIdentifier("resume-reminder-\(reminder.id)")
                }
                Button("一起看看") { model.continueGoalFromReminder(id: reminder.id) }
                    .fontWeight(.medium)
                    .accessibilityIdentifier("continue-reminder-\(reminder.id)")
                Spacer(minLength: 0)
                Button("取消提醒", role: .destructive) {
                    Task { await model.setScheduleStatus(id: reminder.id, status: "cancelled") }
                }
                .font(.caption)
                .accessibilityIdentifier("cancel-reminder-\(reminder.id)")
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
        .padding(14)
        .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(OpenMusePalette.border, lineWidth: 1))
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "scheduled": "待提醒"
        case "due": "已到时间，等待你查看"
        case "paused": "已暂停"
        default: status
        }
    }

    private func notificationDescription(_ status: String) -> String {
        switch status {
        case "scheduled": "系统通知已登记；到时间后请打开 OpenMuse。"
        case "permission-denied": "系统通知未获准；打开 App 时仍会检查是否已到期。"
        case "unavailable": "系统未能安排通知；打开 App 时仍会检查是否已到期。"
        case "due-on-open": "提醒已到时间；打开后可继续，不会自动发送消息。"
        case "paused": "提醒已暂停。"
        case "cancelled": "提醒已取消。"
        default: "本地提醒状态：\(status)。"
        }
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
                .presentationDetents([.large])
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

    private var executionTask: TaskExecutionRecord? {
        model.executionTasks.first(where: { $0.id == activity.id })
    }

    private var latestCheckpoint: TaskCheckpointRecord? {
        model.executionCheckpoints
            .filter { $0.taskID == activity.id }
            .max { $0.sequence < $1.sequence }
    }

    private var toolOperationsByStepID: [String: ActivityOperationRecord] {
        model.activityOperations(for: activity.id).reduce(into: [:]) { result, operation in
            result[operation.stepID] = operation
        }
    }

    /// The operation record is the durable source of tool detail. If a task
    /// summary was not saved or arrived later during device sync, still show
    /// the operation instead of hiding it because its summary step is absent.
    private var timelineSteps: [ActivityStepRecord] {
        var steps = activity.steps ?? []
        let existingStepIDs = Set(steps.map(\.id))
        let orphanedOperations = model.activityOperations(for: activity.id)
            .filter { !existingStepIDs.contains($0.stepID) }
        for operation in orphanedOperations {
            steps.append(ActivityStepRecord(
                id: operation.stepID,
                group: operation.group,
                title: operation.title,
                detail: operation.safeSummary ?? "这次操作已单独保存；展开可查看调用和结果。",
                status: activityStepStatus(for: operation.status),
                updatedAt: operation.updatedAt
            ))
        }
        return steps
    }

    private func activityStepStatus(for operationStatus: String) -> String {
        switch operationStatus {
        case "started", "running", "approved": "running"
        case "awaiting-approval": "awaiting-approval"
        case "completed": "completed"
        case "timed-out", "failed": "failed"
        case "denied": "denied"
        case "cancelled": "cancelled"
        case "suspended": "suspended"
        default: "pending"
        }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let executionTask {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Label("执行记录", systemImage: "arrow.clockwise.circle")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(executionStatusLabel(executionTask.status))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(OpenMusePalette.subtle)
                            }
                            Text(executionTask.lastCheckpointSequence > 0
                                 ? "已保存 \(executionTask.lastCheckpointSequence) 个检查点；重开后仍可查看原对话与进度。"
                                 : "执行还没有保存检查点。")
                                .font(.caption).foregroundStyle(OpenMusePalette.subtle)
                            if let latestCheckpoint {
                                Text("最近保存：\(checkpointTitle(latestCheckpoint.stepID))")
                                    .font(.caption).foregroundStyle(OpenMusePalette.subtle)
                            }
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("execution-task-progress")
                    }
                    if !timelineSteps.isEmpty {
                        ActivityTimeline(
                            steps: timelineSteps,
                            operationsByStepID: toolOperationsByStepID,
                            onStopCurrentResponse: model.isSending && model.activeActivity?.id == activity.id
                                ? { model.cancelCurrentResponse() }
                                : nil
                        )
                    } else {
                        Label("这项活动没有细分执行记录，只显示已保存的最新状态。", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(OpenMusePalette.subtle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("activity-details-scroll")
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
        case "waiting_approval": "等待你确认"
        case "completed": "已完成"
        case "failed": "失败"
        case "suspended": "已暂停"
        case "cancelled": "已取消"
        default: activity.status
        }
    }

    private func executionStatusLabel(_ status: String) -> String {
        switch status {
        case "queued": "等待执行"
        case "running": "进行中"
        case "waiting_user": "等待你继续"
        case "waiting_device": "等待设备"
        case "suspended": "已暂停"
        case "completed": "已完成"
        case "failed": "执行失败"
        case "cancelled": "已取消"
        default: status
        }
    }

    private func checkpointTitle(_ stepID: String) -> String {
        switch stepID {
        case "context-loaded": "已读取相关资料"
        case "reply-saved": "已保存本轮回复"
        default: stepID
        }
    }
}

private struct ActivityTimeline: View {
    let steps: [ActivityStepRecord]
    let operationsByStepID: [String: ActivityOperationRecord]
    let onStopCurrentResponse: (() -> Void)?

    private var groups: [(String, [ActivityStepRecord])] {
        var grouped: [String: [ActivityStepRecord]] = [:]
        var order: [String] = []
        for step in steps {
            if grouped[step.group] == nil { order.append(step.group) }
            grouped[step.group, default: []].append(step)
        }
        return order.map { ($0, grouped[$0] ?? []) }
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
                                if let operation = operationsByStepID[step.id] {
                                    ActivityOperationDetailView(
                                        operation: operation,
                                        onStopCurrentResponse: isRunning(operation.status) ? onStopCurrentResponse : nil
                                    )
                                        .padding(.top, 5)
                                }
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
        case "PHONE": "本机操作"
        case "MAC": "Mac 操作"
        default: group
        }
    }

    private func isRunning(_ status: String) -> Bool {
        ["started", "running", "approved"].contains(status)
    }

    @ViewBuilder
    private func stepMark(_ status: String) -> some View {
        if status == "running" {
            ProgressView().controlSize(.small).frame(width: 24, height: 24)
        } else if status == "awaiting-approval" {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(OpenMusePalette.blue)
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: status == "completed" ? "checkmark.circle.fill" : ["failed", "denied"].contains(status) ? "xmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(status == "completed" ? OpenMusePalette.green : ["failed", "denied"].contains(status) ? OpenMusePalette.warning : OpenMusePalette.subtle)
                .frame(width: 24, height: 24)
        }
    }
}

private struct ActivityOperationDetailView: View {
    let operation: ActivityOperationRecord
    let onStopCurrentResponse: (() -> Void)?
    @State private var isExpanded = false
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                Text(statusLabel)
                    .foregroundStyle(statusColor)
                Spacer(minLength: 8)
                if let duration = operation.duration {
                    Text("用时 \(durationLabel(duration))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(OpenMusePalette.subtle)
                } else if ["started", "running", "approved"].contains(operation.status) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("用时 \(durationLabel(max(0, context.date.timeIntervalSince(operation.startedAt))))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(OpenMusePalette.subtle)
                    }
                }
                if let onStopCurrentResponse {
                    Button(action: onStopCurrentResponse) {
                        Image(systemName: "stop.fill")
                            .font(.caption2.weight(.bold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("停止本轮回复")
                    .help("停止本轮回复")
                }
            }
            .font(.caption.weight(.medium))

            if let safeSummary = operation.safeSummary, !safeSummary.isEmpty {
                Text(safeSummary)
                    .font(.caption)
                    .foregroundStyle(OpenMusePalette.subtle)
                    .textSelection(.enabled)
            }

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    ActivityOperationField(title: "工具", value: operation.toolName)
                    if let toolCallID = operation.toolCallID, !toolCallID.isEmpty {
                        ActivityOperationField(title: "调用编号", value: toolCallID)
                    }
                    ActivityOperationField(title: "执行设备", value: operation.group == "MAC" ? "Mac" : "iPhone")
                    if let relativePath = operation.relativePath, !relativePath.isEmpty {
                        ActivityOperationField(title: "文件", value: relativePath)
                    }
                    if let inputJSON = operation.inputJSON {
                        ActivityOperationField(title: "调用参数", value: inputJSON, code: true)
                    } else {
                        ActivityOperationField(title: "调用参数", value: "没有收到参数记录。")
                    }
                    if let outputText = operation.outputText {
                        ActivityOperationField(title: "返回结果", value: outputText, code: true)
                    } else if operation.errorText == nil {
                        ActivityOperationField(
                            title: "返回结果",
                            value: isOperationRunning ? "操作仍在执行，尚未收到返回内容。" : "本次没有可显示的文本返回。"
                        )
                    }
                    if let errorText = operation.errorText {
                        ActivityOperationField(title: "错误", value: errorText, code: true, isError: true)
                    }
                    HStack(spacing: 5) {
                        Text("开始：\(operation.startedAt.formatted(date: .omitted, time: .standard))")
                        if let finishedAt = operation.finishedAt {
                            Text("· 结束：\(finishedAt.formatted(date: .omitted, time: .standard))")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(OpenMusePalette.subtle)

                    Button(action: copyDetails) {
                        Label(didCopy ? "已复制" : "复制操作详情", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(didCopy ? "已复制操作详情" : "复制操作详情")
                    .accessibilityIdentifier("activity-operation-copy-\(operation.stepID)")
                }
                .padding(.top, 9)
            } label: {
                Label(isExpanded ? "收起操作详情" : "查看调用参数和返回结果", systemImage: "terminal")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(OpenMusePalette.text)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(OpenMusePalette.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity-operation-\(operation.stepID)")
    }

    private var statusLabel: String {
        switch operation.status {
        case "started", "running", "approved": "正在执行"
        case "awaiting-approval": "等待确认"
        case "completed": "已完成"
        case "timed-out": "已超时"
        case "denied": "已拒绝"
        case "failed": "执行失败"
        case "cancelled": "已取消"
        default: operation.status
        }
    }

    private var isOperationRunning: Bool {
        ["started", "running", "approved", "awaiting-approval"].contains(operation.status)
    }

    private var statusSymbol: String {
        switch operation.status {
        case "started", "running", "approved": "arrow.trianglehead.2.clockwise.rotate.90"
        case "completed": "checkmark.circle.fill"
        case "failed", "timed-out": "xmark.circle.fill"
        case "denied": "hand.raised.fill"
        case "cancelled": "pause.circle.fill"
        default: "circle"
        }
    }

    private var statusColor: Color {
        switch operation.status {
        case "completed": OpenMusePalette.green
        case "failed", "timed-out": OpenMusePalette.warning
        case "denied": OpenMusePalette.blue
        default: OpenMusePalette.subtle
        }
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        if duration < 60 { return String(format: "%.1f 秒", duration) }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes) 分 \(seconds) 秒"
    }

    private func copyDetails() {
        var parts = [
            "操作：\(operation.title)",
            "工具：\(operation.toolName)",
            "执行设备：\(operation.group == "MAC" ? "Mac" : "iPhone")",
            "状态：\(statusLabel)",
            "开始：\(operation.startedAt.formatted(date: .numeric, time: .standard))"
        ]
        if let toolCallID = operation.toolCallID { parts.append("调用编号：\(toolCallID)") }
        if let finishedAt = operation.finishedAt {
            parts.append("结束：\(finishedAt.formatted(date: .numeric, time: .standard))")
        }
        if let duration = operation.duration {
            parts.append("耗时：\(durationLabel(duration))")
        }
        if let relativePath = operation.relativePath { parts.append("文件：\(relativePath)") }
        if let safeSummary = operation.safeSummary { parts.append("来源：\(safeSummary)") }
        if let inputJSON = operation.inputJSON { parts.append("调用参数：\n\(inputJSON)") }
        if let outputText = operation.outputText { parts.append("返回结果：\n\(outputText)") }
        else if operation.errorText == nil {
            parts.append("返回结果：\n\(isOperationRunning ? "操作仍在执行，尚未收到返回内容。" : "本次没有可显示的文本返回。")")
        }
        if let errorText = operation.errorText { parts.append("错误：\n\(errorText)") }
        #if os(iOS)
        UIPasteboard.general.string = parts.joined(separator: "\n\n")
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(parts.joined(separator: "\n\n"), forType: .string)
        #endif
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { didCopy = false }
    }
}

private struct ActivityOperationField: View {
    let title: String
    let value: String
    var code = false
    var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isError ? OpenMusePalette.warning : OpenMusePalette.subtle)
            if code {
                ScrollView(.vertical) {
                        Text(ActivityToolDetailPolicy.display(value))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(isError ? OpenMusePalette.warning : OpenMusePalette.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .background(OpenMusePalette.panel.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
            } else {
                Text(value)
                    .font(.caption)
                    .foregroundStyle(isError ? OpenMusePalette.warning : OpenMusePalette.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct FeedHomeView: View {
    @ObservedObject var model: OpenMuseAppModel
    @Environment(\.openURL) private var openURL
    @AppStorage("OpenMuse.DisplayFeedImages") private var displayFeedImages = false
    @State private var isEditing = false
    @State private var draft = ""
    @State private var sourceURL = ""
    @State private var showingHiddenFeedItems = false

    private var visibleItems: [FeedItemRecord] {
        model.feedItems
            .filter { item in model.feedFeedback.first(where: { $0.itemID == item.id })?.action != "not-interested" }
            .sorted { left, right in
                let leftLater = model.feedFeedback.first(where: { $0.itemID == left.id })?.action == "later"
                let rightLater = model.feedFeedback.first(where: { $0.itemID == right.id })?.action == "later"
                if leftLater != rightLater { return !leftLater }
                let leftScore = model.feedRelevanceScore(left)
                let rightScore = model.feedRelevanceScore(right)
                if leftScore != rightScore { return leftScore > rightScore }
                return (left.publishedAt ?? left.fetchedAt) > (right.publishedAt ?? right.fetchedAt)
            }
    }

    private var hiddenItems: [FeedItemRecord] {
        model.feedItems
            .filter { item in model.feedFeedback.first(where: { $0.itemID == item.id })?.action == "not-interested" }
            .sorted { ($0.publishedAt ?? $0.fetchedAt) > ($1.publishedAt ?? $1.fetchedAt) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    PageHeading(title: "动态", subtitle: "从你选择的来源里，慢慢发现值得了解的内容。")
                    Spacer(minLength: 0)
                    Button {
                        Task { await model.refreshFeeds() }
                    } label: {
                        if model.isRefreshingFeeds { ProgressView().frame(width: 38, height: 38) }
                        else { Image(systemName: "arrow.clockwise").frame(width: 38, height: 38) }
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRefreshingFeeds || !model.feedSources.contains(where: \.isEnabled))
                    .accessibilityLabel("刷新动态来源")
                }
                if isEditing {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("你希望看到什么？").font(.subheadline.weight(.semibold)).foregroundStyle(OpenMusePalette.text)
                        TextEditor(text: $draft)
                            .frame(minHeight: 105)
                            .scrollContentBackground(.hidden)
                            .padding(9)
                            .background(OpenMusePalette.background, in: RoundedRectangle(cornerRadius: 14))
                        HStack {
                            Button("取消") { isEditing = false; draft = model.feedInstruction }.buttonStyle(.bordered)
                            Spacer()
                            Button("保存") {
                                let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !clean.isEmpty { model.saveFeedInstruction(clean) }
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
                        draft = model.feedInstruction
                        isEditing = true
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("兴趣说明").font(.caption.weight(.semibold)).foregroundStyle(OpenMusePalette.subtle)
                                Text(model.feedInstruction).font(.subheadline).foregroundStyle(OpenMusePalette.text).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Image(systemName: "slider.horizontal.3").foregroundStyle(OpenMusePalette.subtle)
                        }
                        .padding(14)
                        .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("编辑动态兴趣指令")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("添加 RSS 或 Atom 来源").font(.subheadline.weight(.semibold)).foregroundStyle(OpenMusePalette.text)
                    HStack(spacing: 8) {
                        sourceAddressField
                        Button("添加") {
                            let value = sourceURL
                            sourceURL = ""
                            Task { await model.addFeedSource(value) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isRefreshingFeeds)
                    }
                    Text("只读取你添加的公开 HTTPS 订阅；原文链接和来源时间会保留。没有来源时不会显示虚构内容。")
                        .font(.caption).foregroundStyle(OpenMusePalette.subtle)
                    Toggle("显示文章图片", isOn: $displayFeedImages)
                        .font(.caption)
                    Text("开启后，加载配图时可能连接图片托管服务；关闭时只读取订阅文本。")
                        .font(.caption2).foregroundStyle(OpenMusePalette.subtle)
                }
                .padding(14)
                .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 16))

                if !model.feedSources.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("来源").font(.subheadline.weight(.semibold)).foregroundStyle(OpenMusePalette.text)
                        ForEach(model.feedSources) { source in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.title).font(.subheadline.weight(.medium)).foregroundStyle(OpenMusePalette.text)
                                    Text(source.lastError ?? source.url).font(.caption).foregroundStyle(source.lastError == nil ? OpenMusePalette.subtle : OpenMusePalette.warning).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Toggle("更新", isOn: Binding(
                                    get: { source.isEnabled },
                                    set: { model.setFeedSourceEnabled(id: source.id, enabled: $0) }
                                ))
                                .labelsHidden()
                                .accessibilityLabel("更新来源：\(source.title)")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if visibleItems.isEmpty {
                    EmptyPanel(
                        symbol: "sparkles",
                        title: model.feedSources.isEmpty ? "还没有新的动态" : "来源里暂时没有可显示的内容",
                        detail: model.feedSources.isEmpty
                            ? "添加一个你信任的 RSS 或 Atom 地址后，这里会显示真实文章；你也可以直接在聊天里继续讨论。"
                            : "刷新后会读取来源更新。打不开的来源会保留在来源列表里并显示原因。"
                    )
                }

                ForEach(visibleItems) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        if displayFeedImages,
                           let rawImageURL = item.imageURL,
                           let imageURL = URL(string: rawImageURL),
                           imageURL.scheme?.lowercased() == "https" {
                            AsyncImage(url: imageURL) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else if phase.error != nil {
                                    Rectangle().fill(OpenMusePalette.selected)
                                        .overlay(Image(systemName: "photo").foregroundStyle(OpenMusePalette.subtle))
                                } else {
                                    Rectangle().fill(OpenMusePalette.selected)
                                        .overlay(ProgressView())
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 176)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                            .accessibilityLabel("文章配图")
                        }
                        Text(item.title).font(.headline).foregroundStyle(OpenMusePalette.text)
                        HStack(spacing: 7) {
                            Text(item.sourceTitle)
                            Text("·")
                            Text(item.publishedAt?.formatted(date: .abbreviated, time: .omitted) ?? "来源未提供时间")
                        }
                        .font(.caption).foregroundStyle(OpenMusePalette.subtle)
                        if !item.summary.isEmpty {
                            Text(item.summary).font(.subheadline).foregroundStyle(OpenMusePalette.subtle).lineLimit(5)
                        }
                        Text(model.feedRecommendationReason(item))
                            .font(.caption2).foregroundStyle(OpenMusePalette.subtle)
                        if let action = model.feedFeedback.first(where: { $0.itemID == item.id })?.action {
                            Text(action == "later" ? "已放到稍后" : action == "discussed" ? "已在旁聊中继续" : "")
                                .font(.caption2).foregroundStyle(OpenMusePalette.blue)
                        }
                        HStack(spacing: 12) {
                            Button("继续聊", systemImage: "bubble.left.and.bubble.right") { model.discussFeedItem(item) }
                                .buttonStyle(.borderedProminent)
                            if let url = URL(string: item.url) {
                                Button("查看原文", systemImage: "arrow.up.right") { openURL(url) }.buttonStyle(.bordered)
                            }
                            Menu {
                                Button("稍后看", systemImage: "clock") { model.setFeedFeedback(itemID: item.id, action: "later") }
                                Button("不感兴趣", systemImage: "hand.thumbsdown") { model.setFeedFeedback(itemID: item.id, action: "not-interested") }
                                if model.feedFeedback.first(where: { $0.itemID == item.id })?.action != nil {
                                    Button("撤销反馈", systemImage: "arrow.uturn.backward") { model.setFeedFeedback(itemID: item.id, action: nil) }
                                }
                            } label: {
                                Image(systemName: "ellipsis").frame(width: 36, height: 36)
                            }
                            .accessibilityLabel("动态操作")
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(15)
                    .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 17))
                }

                if !hiddenItems.isEmpty {
                    DisclosureGroup(isExpanded: $showingHiddenFeedItems) {
                        ForEach(hiddenItems) { item in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.subheadline.weight(.medium)).foregroundStyle(OpenMusePalette.text)
                                    Text(item.sourceTitle).font(.caption).foregroundStyle(OpenMusePalette.subtle)
                                }
                                Spacer()
                                Button("恢复") { model.setFeedFeedback(itemID: item.id, action: nil) }
                                    .font(.caption.weight(.medium))
                                    .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 6)
                        }
                    } label: {
                        Label("已隐藏的动态（\(hiddenItems.count)）", systemImage: "eye.slash")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(OpenMusePalette.subtle)
                    }
                    .tint(OpenMusePalette.blue)
                    .padding(13)
                    .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(18)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if draft.isEmpty { draft = model.feedInstruction }
            if model.feedItems.isEmpty && !model.feedSources.isEmpty { Task { await model.refreshFeeds() } }
        }
    }

    private var sourceAddressField: some View {
        #if os(iOS)
        TextField("https://example.com/feed.xml", text: $sourceURL)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
        #else
        TextField("https://example.com/feed.xml", text: $sourceURL)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
        #endif
    }
}

private struct GoalIdea: Identifiable {
    let goal: GoalRecord
    let feedback: IdeaFeedbackRecord?
    var id: String { goal.id }
    var title: String { "为「\(goal.title)」整理一份轻松的下一步清单" }
    var detail: String { "把目前还没确认的事收拢起来，之后可以边聊边调整。" }
}

struct IdeasHomeView: View {
    @ObservedObject var model: OpenMuseAppModel
    @State private var selectedIdea: GoalIdea?
    @State private var showingSkippedIdeas = false

    private var ideas: [GoalIdea] {
        model.goals
            .filter { $0.status != "已完成" && $0.status != "已关闭" }
            .compactMap { goal in
                let feedback = model.ideaFeedback.first(where: { $0.goalID == goal.id })
                guard !["accepted", "rewritten", "not-interested", "dismissed"].contains(feedback?.action ?? "") else { return nil }
                return GoalIdea(goal: goal, feedback: feedback)
            }
            .sorted { ($0.feedback?.action == "later" ? 1 : 0) < ($1.feedback?.action == "later" ? 1 : 0) }
    }

    private var skippedIdeas: [GoalIdea] {
        model.goals
            .filter { $0.status != "已完成" && $0.status != "已关闭" }
            .compactMap { goal in
            guard let feedback = model.ideaFeedback.first(where: { $0.goalID == goal.id }),
                  ["not-interested", "dismissed"].contains(feedback.action) else { return nil }
            return GoalIdea(goal: goal, feedback: feedback)
            }
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
                                if idea.feedback?.action == "later" {
                                    Text("已放到稍后").font(.caption2).foregroundStyle(OpenMusePalette.blue)
                                }
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(OpenMusePalette.subtle).padding(.top, 5)
                        }
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("稍后再说", systemImage: "clock") { model.setIdeaFeedback(goalID: idea.goal.id, action: "later") }
                        Button("不合适", systemImage: "hand.thumbsdown") { model.setIdeaFeedback(goalID: idea.goal.id, action: "not-interested") }
                    }
                    if idea.id != ideas.last?.id { Divider().overlay(OpenMusePalette.border) }
                }
                if !skippedIdeas.isEmpty {
                    DisclosureGroup(isExpanded: $showingSkippedIdeas) {
                        ForEach(skippedIdeas) { idea in
                            HStack(spacing: 10) {
                                Text(idea.goal.title).font(.subheadline).foregroundStyle(OpenMusePalette.text)
                                Spacer()
                                Button("撤销跳过") { model.setIdeaFeedback(goalID: idea.goal.id, action: "later") }
                                    .font(.caption.weight(.medium))
                                    .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 6)
                        }
                    } label: {
                        Label("已跳过的点子（\(skippedIdeas.count)）", systemImage: "eye.slash")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(OpenMusePalette.subtle)
                    }
                    .tint(OpenMusePalette.blue)
                    .padding(13)
                    .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(18)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $selectedIdea) { idea in
            IdeaDetailSheet(idea: idea, onStart: { rewrite in
                let instruction = rewrite?.trimmingCharacters(in: .whitespacesAndNewlines)
                model.setIdeaFeedback(goalID: idea.goal.id, action: instruction?.isEmpty == false ? "rewritten" : "accepted", note: instruction)
                model.beginSideConversation(parentConversationID: idea.goal.conversationID)
                if let instruction, !instruction.isEmpty {
                    model.draft = "请继续当前目标「\(idea.goal.title)」，把下一步调整为「\(instruction)」。基于已有信息给我一个轻松、可调整的方案；不确定的事情先问我。"
                } else {
                    model.draft = "帮我为「\(idea.goal.title)」整理一份轻松、可调整的下一步清单。只依据已有信息；不确定的事情先问我。"
                }
                model.sendDraft()
                selectedIdea = nil
            }, onLater: {
                model.setIdeaFeedback(goalID: idea.goal.id, action: "later")
                selectedIdea = nil
            }, onNotSuitable: {
                model.setIdeaFeedback(goalID: idea.goal.id, action: "not-interested")
                selectedIdea = nil
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct IdeaDetailSheet: View {
    let idea: GoalIdea
    let onStart: (String?) -> Void
    let onLater: () -> Void
    let onNotSuitable: () -> Void
    @State private var rewrite = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(idea.title).font(.title3.weight(.semibold)).foregroundStyle(OpenMusePalette.text)
            Text(idea.detail).font(.body).foregroundStyle(OpenMusePalette.subtle)
            Divider()
            Text("开始后会") .font(.headline).foregroundStyle(OpenMusePalette.text)
            Label("新建一段关联当前目标的旁聊", systemImage: "bubble.left.and.bubble.right")
            Label("先给出可调整的清单，不会自动完成外部操作", systemImage: "checkmark.shield")
                .font(.subheadline).foregroundStyle(OpenMusePalette.subtle)
            TextField("想换成什么方向？（可选）", text: $rewrite, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            Spacer(minLength: 4)
            HStack {
                Button("稍后", action: onLater).buttonStyle(.bordered)
                Button("不合适", action: onNotSuitable).buttonStyle(.bordered)
                Spacer()
                Button("开始吧") { onStart(nil) }.buttonStyle(.borderedProminent)
            }
            if !rewrite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("按改写方向开始") { onStart(rewrite) }
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OpenMusePalette.panel)
    }
}

struct ArtifactPreviewView: View {
    @ObservedObject var model: OpenMuseAppModel
    let artifact: ArtifactRecord
    @State private var selectedTravelPlanVariantID = ""
    @State private var showingHistory = false
    @State private var isExporting = false
    @State private var exportDocument = ArtifactExportDocument(data: Data())
    @State private var exportContentType: UTType = ArtifactExportTypes.markdown
    @State private var exportFilename = "OpenMuse-artifact"
    @State private var exportError: String?
    @State private var showingExportError = false
    @State private var showingDeleteConfirmation = false
    @State private var showingAssetImporter = false

    private var currentArtifact: ArtifactRecord {
        let stored = model.artifacts.first(where: { $0.id == artifact.id }) ?? artifact
        guard let variants = stored.travelPlanVariants, !variants.isEmpty else { return stored }
        let selectedID = selectedTravelPlanVariantID.isEmpty
            ? (stored.selectedTravelPlanVariantID ?? variants[0].id)
            : selectedTravelPlanVariantID
        guard let variant = variants.first(where: { $0.id == selectedID }) else { return stored }
        var displayed = stored
        displayed.content = variant.content
        displayed.sourceMessageIDs = variant.sourceMessageIDs ?? stored.sourceMessageIDs
        displayed.assumptions = variant.assumptions
        displayed.expectedDayCount = variant.expectedDayCount
        displayed.coveredDayCount = variant.coveredDayCount
        displayed.selectedTravelPlanVariantID = variant.id
        return displayed
    }

    private var travelPlanVariants: [TravelPlanVariantRecord] {
        currentArtifact.travelPlanVariants ?? []
    }

    private var variantDifferenceText: String {
        guard let selected = travelPlanVariants.first(where: { $0.id == currentArtifact.selectedTravelPlanVariantID }) else { return "" }
        let otherDayCounts = travelPlanVariants
            .filter { $0.id != selected.id }
            .compactMap { $0.expectedDayCount ?? $0.coveredDayCount }
        guard !otherDayCounts.isEmpty else { return "" }
        let selectedDays = selected.expectedDayCount ?? selected.coveredDayCount ?? 0
        let differences = Array(Set(otherDayCounts.map { abs(selectedDays - $0) })).sorted().map { "相差 \($0) 天" }
        return "另有 \(otherDayCounts.map { "\($0)天" }.joined(separator: "、")) 方案（\(differences.joined(separator: "、"))）；切换查看不会覆盖其他方案。"
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
                    if currentArtifact.kind == "web" {
                        Button("添加图片素材…", systemImage: "photo") { showingAssetImporter = true }
                    }
                    ShareLink(item: currentArtifact.content) { Label("分享正文", systemImage: "square.and.arrow.up") }
                    Divider()
                    Button("导出 Markdown", systemImage: "doc.text") {
                        beginExport(content: currentArtifact.content, type: ArtifactExportTypes.markdown, title: currentArtifact.title)
                    }
                    Button("导出 PDF 阅读版", systemImage: "doc.richtext") {
                        do {
                            var sections = [currentArtifact.content]
                            if let assumptions = currentArtifact.assumptions, !assumptions.isEmpty {
                                sections.insert("待确认\n" + assumptions.map { "• \($0)" }.joined(separator: "\n") + "\n", at: 0)
                            }
                            let subtitle = currentArtifact.expectedDayCount.map { "旅行计划 · 第 \(currentArtifact.currentRevision) 版 · 覆盖 \(currentArtifact.coveredDayCount ?? 0)/\($0) 天" }
                                ?? "OpenMuse · 第 \(currentArtifact.currentRevision) 版"
                            let data = try ArtifactPDFRenderer.render(title: currentArtifact.title, subtitle: subtitle, body: sections.joined(separator: "\n\n"))
                            beginExport(data: data, type: ArtifactExportTypes.pdf, title: currentArtifact.title)
                        } catch {
                            exportError = error.localizedDescription
                            showingExportError = true
                        }
                    }
                    Button("导出 JSON", systemImage: "curlybraces") {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        encoder.dateEncodingStrategy = .iso8601
                        do {
                            let data = try encoder.encode(currentArtifact)
                            beginExport(data: data, type: .json, title: currentArtifact.title)
                        } catch {
                            exportError = error.localizedDescription
                            showingExportError = true
                        }
                    }
                    Button("导出构件包", systemImage: "shippingbox") {
                        do {
                            let package = try model.artifactPortablePackage(id: currentArtifact.id)
                            let data = try ArtifactPortablePackage.encode(package)
                            beginExport(data: data, type: ArtifactExportTypes.zip, title: currentArtifact.title + "-OpenMuse")
                        } catch {
                            exportError = error.localizedDescription
                            showingExportError = true
                        }
                    }
                    Divider()
                    Button("永久删除构件…", systemImage: "trash", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
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
                        Image(systemName: currentArtifact.kind == "web" ? "safari" : "doc.richtext").foregroundStyle(OpenMusePalette.blue)
                        Text("第 \(currentArtifact.currentRevision) 版 · \(currentArtifact.kind == "web" ? "交互网页" : "旅行计划草稿")")
                            .font(.caption).foregroundStyle(OpenMusePalette.subtle)
                    }
                    if travelPlanVariants.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("旅行方案", systemImage: "arrow.left.arrow.right")
                                .font(.subheadline.weight(.semibold))
                            Picker("旅行方案", selection: $selectedTravelPlanVariantID) {
                                ForEach(travelPlanVariants) { variant in
                                    Text(variant.title).tag(variant.id)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("artifact-variant-picker")
                            Text(variantDifferenceText)
                                .font(.caption)
                                .foregroundStyle(OpenMusePalette.subtle)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("artifact-variant-difference")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(15)
                        .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(OpenMusePalette.border, lineWidth: 1))
                    }
                    if let expectedDays = currentArtifact.expectedDayCount, expectedDays > 0 {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                Label("行程覆盖", systemImage: "map")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(currentArtifact.coveredDayCount ?? 0) / \(expectedDays) 天")
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                                    .accessibilityIdentifier("artifact-coverage-days")
                            }
                            ProgressView(value: min(Double(currentArtifact.coveredDayCount ?? 0), Double(expectedDays)), total: Double(expectedDays))
                                .tint(OpenMusePalette.blue)
                            HStack {
                                Text(currentArtifact.travelProgressLabel)
                                Spacer()
                                if let sourceCount = currentArtifact.sourceMessageIDs?.count, sourceCount > 0 {
                                    Text("参考 \(sourceCount) 条对话消息")
                                        .accessibilityIdentifier("artifact-source-count")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(OpenMusePalette.subtle)
                        }
                        .padding(15)
                        .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(OpenMusePalette.border, lineWidth: 1))
                    }
                    if let assumptions = currentArtifact.assumptions, !assumptions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("待确认", systemImage: "questionmark.circle")
                                .font(.subheadline.weight(.semibold))
                            ForEach(Array(assumptions.enumerated()), id: \.offset) { index, assumption in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(OpenMusePalette.subtle).frame(width: 5, height: 5).padding(.top, 7)
                                    Text(assumption)
                                        .font(.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("artifact-assumption-\(index)")
                                }
                                .foregroundStyle(OpenMusePalette.text)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(15)
                        .background(OpenMusePalette.panel, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(OpenMusePalette.border, lineWidth: 1))
                    }
                    if currentArtifact.kind == "web" {
                        ArtifactWebSandboxView(html: model.renderableArtifactContent(currentArtifact))
                            .frame(minHeight: 620)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(OpenMusePalette.border, lineWidth: 1))
                    } else {
                        MarkdownContentView(content: currentArtifact.content)
                    }
                }
                .padding(20)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(OpenMusePalette.background)
        .onAppear {
            if selectedTravelPlanVariantID.isEmpty {
                selectedTravelPlanVariantID = artifact.selectedTravelPlanVariantID
                    ?? artifact.travelPlanVariants?.first?.id
                    ?? ""
            }
        }
        .sheet(isPresented: $showingHistory) {
            ArtifactHistoryPanel(model: model, artifact: currentArtifact)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fileExporter(isPresented: $isExporting, document: exportDocument, contentType: exportContentType, defaultFilename: exportFilename) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
                showingExportError = true
            }
        }
        .fileImporter(isPresented: $showingAssetImporter, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            do {
                try model.addArtifactImages(result.get(), artifactID: currentArtifact.id)
            } catch {
                exportError = error.localizedDescription
                showingExportError = true
            }
        }
        .alert("构件没有导出", isPresented: $showingExportError) {
            Button("好", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "请稍后重试。")
        }
        .confirmationDialog("永久删除这个构件？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("永久删除", role: .destructive) { model.deleteArtifact(id: currentArtifact.id) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前版本和所有历史版本都会删除，并同步到已连接的设备。这个操作无法撤销。")
        }
    }

    private func beginExport(content: String, type: UTType, title: String) {
        beginExport(data: Data(content.utf8), type: type, title: title)
    }

    private func beginExport(data: Data, type: UTType, title: String) {
        exportDocument = ArtifactExportDocument(data: data)
        exportContentType = type
        exportFilename = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        isExporting = true
    }
}

private struct ArtifactExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [ArtifactExportTypes.markdown, .json, ArtifactExportTypes.pdf, ArtifactExportTypes.zip] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct MarkdownContentView: View {
    let content: String
    var bodyFont: Font = .body
    var lineSpacing: CGFloat = 12
    private var lines: [String] { content.components(separatedBy: .newlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: lineSpacing) {
            ForEach(Array(lines.enumerated()), id: \.offset) { item in
                let index = item.offset
                let line = item.element
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    EmptyView()
                } else if ["---", "***", "___"].contains(line.trimmingCharacters(in: .whitespaces)) {
                    Rectangle().fill(OpenMusePalette.border).frame(height: 1)
                } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    table(at: index)
                } else if line.hasPrefix("### ") {
                    markdownText(String(line.dropFirst(4))).font(bodyFont.weight(.semibold)).foregroundStyle(OpenMusePalette.text)
                } else if line.hasPrefix("## ") {
                    markdownText(String(line.dropFirst(3))).font(.title3.weight(.semibold)).foregroundStyle(OpenMusePalette.text)
                } else if line.hasPrefix("# ") {
                    markdownText(String(line.dropFirst(2))).font(.title2.weight(.bold)).foregroundStyle(OpenMusePalette.text)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(OpenMusePalette.blue).frame(width: 5, height: 5).padding(.top, 8)
                        markdownText(String(line.dropFirst(2))).font(bodyFont).foregroundStyle(OpenMusePalette.text)
                    }
                } else if let numberedItem = numberedListItem(in: line) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(numberedItem.marker).font(bodyFont.weight(.medium)).foregroundStyle(OpenMusePalette.blue)
                        markdownText(numberedItem.content).font(bodyFont).foregroundStyle(OpenMusePalette.text)
                    }
                } else {
                    markdownText(line).font(bodyFont).foregroundStyle(OpenMusePalette.text)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func numberedListItem(in line: String) -> (marker: String, content: String)? {
        guard let delimiter = line.firstIndex(where: { $0 == "." || $0 == ")" || $0 == "、" }),
              line[..<delimiter].allSatisfy(\.isNumber),
              line.index(after: delimiter) < line.endIndex,
              line[line.index(after: delimiter)].isWhitespace else { return nil }
        return (String(line[...delimiter]), String(line[line.index(after: delimiter)...]).trimmingCharacters(in: .whitespaces))
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
