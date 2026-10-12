import SwiftUI
import UniformTypeIdentifiers

/// Backup and restore controls live beside the existing data migration controls.
public struct WorkspaceBackupPanel: View {
    @ObservedObject private var model: OpenMuseAppModel
    @State private var schedule = WorkspaceBackupPreferences.loadSchedule()
    @State private var backupTime = Date()
    @State private var folderName = WorkspaceBackupPreferences.selectedFolderName
    @State private var lastResult = WorkspaceBackupPreferences.lastResult
    @State private var isSelectingFolder = false
    @State private var isImporting = false
    @State private var isShowingImportPreview = false
    @State private var importData: Data?
    @State private var importPreview = ""
    @State private var status: String?
    @State private var isRunningBackup = false

    public init(model: OpenMuseAppModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("备份与恢复", systemImage: "externaldrive.badge.timemachine")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("重要资料应能随时备份和导出。完整备份是未加密的 ZIP，包含聊天、附件、任务草稿、结构化记录，以及 USER.md、SOUL.md 等工作区 Markdown 文件；可由你选择交给其他 AI 读取。手动导出会单独保留，不受定时备份清理影响。API 密钥、模型端点设置、iSH 系统目录、浏览器会话和本机闹钟/计时器不会导出。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("选择备份文件夹") { isSelectingFolder = true }
                .buttonStyle(.bordered)
            Text(folderName.map { "备份位置：\($0)" } ?? "尚未选择文件夹。可在文件选择器中选 iCloud Drive 的文件夹。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Toggle("每天自动备份完整资料", isOn: Binding(
                get: { schedule.enabled },
                set: { schedule.enabled = $0; saveSchedule() }
            ))
            .tint(.blue)
            .disabled(folderName == nil)
            if folderName == nil {
                Text("先选择一个备份文件夹，才能启用自动备份或立即导出。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if schedule.enabled {
                DatePicker("计划时间", selection: $backupTime, displayedComponents: .hourAndMinute)
                    .onChange(of: backupTime) { _, _ in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: backupTime)
                        schedule.hour = parts.hour ?? schedule.hour
                        schedule.minute = parts.minute ?? schedule.minute
                        saveSchedule()
                    }
                Stepper("保留最近 \(schedule.retentionCount) 份", value: Binding(
                    get: { schedule.retentionCount },
                    set: { schedule.retentionCount = $0; saveSchedule() }
                ), in: 1...30)
                .font(.caption)
            }

            HStack(spacing: 8) {
                Button(isRunningBackup ? "正在备份…" : "立即备份 / 导出") { createBackup() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunningBackup || folderName == nil)
                Button("从备份导入") { isImporting = true }
                    .buttonStyle(.bordered)
            }

            if let lastResult {
                Text(lastResult).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("iPhone 定时备份由 iOS 后台调度，系统可能延迟；打开 App 时会补查。Mac 端在 App 运行期间补查。定时功能不是精确闹钟。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .onAppear(perform: refreshState)
        .fileImporter(isPresented: $isSelectingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            do {
                guard let folder = try result.get().first else { throw WorkspaceBackupError.destinationUnavailable }
                let hasAccess = folder.startAccessingSecurityScopedResource()
                defer { if hasAccess { folder.stopAccessingSecurityScopedResource() } }
                try WorkspaceBackupPreferences.saveFolder(folder)
                folderName = folder.lastPathComponent
                status = "备份文件夹已保存。之后的手动和定时备份会写入这里。"
            } catch { status = "无法保存备份文件夹：\(error.localizedDescription)" }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data, .json, .zip], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { throw WorkspaceArchiveError.invalidManifest }
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                guard let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                    throw WorkspaceBackupError.packageSizeUnavailable
                }
                guard fileSize >= 0, fileSize <= WorkspaceBackupPackage.maximumPackageBytes else {
                    throw WorkspaceArchiveError.tooLarge
                }
                let selectedData = try Data(contentsOf: url, options: .mappedIfSafe)
                guard selectedData.count <= WorkspaceBackupPackage.maximumPackageBytes else {
                    throw WorkspaceArchiveError.tooLarge
                }
                let archiveData = try WorkspaceBackupPackage.workspaceArchive(fromPackage: selectedData) ?? selectedData
                let archive = try WorkspaceArchive.decodePackage(archiveData)
                importData = archiveData
                importPreview = "包含 \(archive.manifest.recordCount) 条记录、\(archive.manifest.revisionCount) 条历史修订和 \(archive.agentWorkspaceFiles.count) 个 Agent 任务草稿。导入会合并到当前工作区，不会静默覆盖。"
                isShowingImportPreview = true
                status = nil
            } catch { status = "无法读取备份：\(error.localizedDescription)" }
        }
        .alert("导入预览", isPresented: $isShowingImportPreview) {
            Button("导入并检查冲突") {
                guard let importData else { return }
                do {
                    let report = try model.importWorkspaceArchive(data: importData)
                    status = report.duplicateArchive
                        ? "这份备份此前已导入；已补回 \(report.importedAgentWorkspaceFiles) 个任务草稿。" + report.cleanupSummary
                        : "已导入 \(report.importedRecords) 条记录；保留 \(report.conflicts) 项冲突。" + report.cleanupSummary
                } catch { status = "导入失败：\(error.localizedDescription)" }
                self.importData = nil
            }
            Button("取消", role: .cancel) { importData = nil }
        } message: {
            Text(importPreview)
        }
    }

    private func refreshState() {
        schedule = WorkspaceBackupPreferences.loadSchedule()
        backupTime = Calendar.current.date(from: DateComponents(hour: schedule.hour, minute: schedule.minute)) ?? .now
        folderName = WorkspaceBackupPreferences.selectedFolderName
        lastResult = WorkspaceBackupPreferences.lastResult
    }

    private func saveSchedule() {
        WorkspaceBackupPreferences.saveSchedule(schedule)
    }

    private func createBackup() {
        guard !isRunningBackup else { return }
        isRunningBackup = true
        defer { isRunningBackup = false }
        do {
            let url = try model.createWorkspaceBackup(retentionCount: schedule.retentionCount)
            let result = "最近一次备份：\(url.lastPathComponent)"
            lastResult = result
            status = "完整备份已保存到 \(folderName ?? "所选文件夹")。"
        } catch {
            WorkspaceBackupPreferences.recordFailure("最近一次备份失败：\(error.localizedDescription)")
            lastResult = WorkspaceBackupPreferences.lastResult
            status = error.localizedDescription
        }
    }
}
