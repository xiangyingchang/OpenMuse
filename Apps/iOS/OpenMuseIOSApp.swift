import BackgroundTasks
import OpenMuseCore
import SwiftUI
import UIKit

@MainActor
final class IOSBackgroundMaintenanceDelegate: NSObject, UIApplicationDelegate {
    static let reviewTaskIdentifier = "org.openmuse.ios.maintenance-review"

    private weak var model: OpenMuseAppModel?
    private var pendingTask: BGAppRefreshTask?
    private var activeRefreshTask: BGAppRefreshTask?
    private var activeOperation: Task<Void, Never>?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.reviewTaskIdentifier, using: .main) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor [weak self] in self?.handle(refreshTask) }
        }
        return true
    }

    func attach(_ model: OpenMuseAppModel) {
        self.model = model
        if let pendingTask {
            self.pendingTask = nil
            handle(pendingTask)
        }
        model.runScheduledWorkspaceBackupIfDue()
        updateSchedule()
    }

    func updateSchedule() {
        guard let model else { return }
        var candidates: [Date] = []
        if model.maintenancePreferences.enabled,
           let nextMaintenance = model.maintenancePreferences.nextBackgroundOpportunity(after: .now) {
            candidates.append(nextMaintenance)
        }
        if let nextBackup = WorkspaceBackupPreferences.loadSchedule().nextRun(after: .now) {
            candidates.append(nextBackup)
        }
        guard let nextRun = candidates.min() else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.reviewTaskIdentifier)
            if let activeRefreshTask {
                activeOperation?.cancel()
                complete(activeRefreshTask, success: false)
            }
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.reviewTaskIdentifier)
        request.earliestBeginDate = nextRun
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // The app still checks on launch; the system may reject or defer refresh requests.
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        guard let model else {
            pendingTask = task
            task.expirationHandler = { [weak self] in
                Task { @MainActor in self?.expirePending(task) }
            }
            return
        }

        activeRefreshTask = task
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.activeOperation?.cancel()
                self?.complete(task, success: false)
            }
        }
        activeOperation = Task { @MainActor [weak self, weak model] in
            guard let self, let model else {
                self?.complete(task, success: false)
                return
            }
            await model.runScheduledMaintenanceIfDue()
            let backupSchedule = WorkspaceBackupPreferences.loadSchedule()
            let backupWasDue = backupSchedule.isDue(
                at: .now,
                lastCompletedAt: WorkspaceBackupPreferences.lastCompletedAt
            )
            let backupSucceeded = !backupWasDue || model.runScheduledWorkspaceBackupIfDue()
            let succeeded = !Task.isCancelled && !model.isRunningMaintenance && backupSucceeded
            self.complete(task, success: succeeded)
            self.activeOperation = nil
            self.updateSchedule()
        }
    }

    private func expirePending(_ task: BGAppRefreshTask) {
        guard pendingTask === task else { return }
        pendingTask = nil
        task.expirationHandler = nil
        task.setTaskCompleted(success: false)
    }

    private func complete(_ task: BGAppRefreshTask, success: Bool) {
        guard activeRefreshTask === task else { return }
        activeRefreshTask = nil
        task.expirationHandler = nil
        task.setTaskCompleted(success: success)
    }
}

@main
struct OpenMuseIOSApp: App {
    @UIApplicationDelegateAdaptor(IOSBackgroundMaintenanceDelegate.self) private var backgroundMaintenance
    #if targetEnvironment(simulator)
    @StateObject private var model: OpenMuseAppModel = {
        let browserRuntime = IOSPhoneBrowserRuntime()
        return OpenMuseAppModel(phoneBrowserRuntime: browserRuntime)
    }()
    #else
    @StateObject private var model: OpenMuseAppModel = {
        let browserRuntime = IOSPhoneBrowserRuntime()
        return OpenMuseAppModel(
            phoneSandboxRuntime: ISHPhoneSandboxRuntime(phoneBrowserRuntime: browserRuntime),
            phoneBrowserRuntime: browserRuntime
        )
    }()
    #endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-openmuse-ish-smoke-test") {
                ISHRuntimeSmokeTestView()
            } else {
                mainView
            }
#else
            mainView
#endif
        }
    }

    private var mainView: some View {
            OpenMuseRootView(model: model)
                .preferredColorScheme(.dark)
                .task {
                    backgroundMaintenance.attach(model)
                    await model.syncWithMac()
                }
                .onChange(of: model.maintenancePreferences) { _, _ in
                    backgroundMaintenance.updateSchedule()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        backgroundMaintenance.attach(model)
                        Task { await model.syncWithMac() }
                    } else if phase == .background {
                        backgroundMaintenance.updateSchedule()
                    }
                }
    }
}

#if DEBUG
/// A fixed-command integration harness for a signed iPhone build. This view is
/// reachable only by a Debug launch argument and never ships in Release builds.
private struct ISHRuntimeSmokeTestView: View {
    @State private var isRunning = false
    @State private var output = "点运行后只会检查 Alpine 和 shell。"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("iSH 真机集成检查")
                .font(.title2.weight(.semibold))
            Text("仅运行已批准的只读环境检查；不会读取正式记忆或写入文件。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(isRunning ? "正在检查…" : "运行 iSH 检查") {
                Task { await runSmokeChecks() }
            }
            .disabled(isRunning)
            .accessibilityIdentifier("ish-smoke-run")

            ScrollView {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("ish-smoke-result")
            }
            .frame(maxHeight: .infinity)
            Spacer(minLength: 0)
        }
        .padding(24)
        .preferredColorScheme(.dark)
    }

    @MainActor
    private func runSmokeChecks() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        var sessionRoot: URL?
        defer {
            if let sessionRoot { try? FileManager.default.removeItem(at: sessionRoot) }
        }

        do {
            let root = try OnDeviceRuntimeFilesystem.applicationSupportRootURL()
            let filesystem = try OnDeviceRuntimeFilesystem(
                rootURL: root,
                conversationID: "ish-device-smoke-\(UUID().uuidString)"
            )
            sessionRoot = filesystem.sessionRootURL
            let mounts = try filesystem.prepareMounts()
            let runtime = ISHPhoneSandboxRuntime()

            let shell = try await runtime.execute(
                command: "uname -a && cat /etc/alpine-release",
                mounts: mounts,
                timeout: 20,
                maximumOutputBytes: PhoneSandboxCommandPolicy.maximumOutputBytes
            )

            output = """
            SHELL_EXIT=\(shell.exitCode) TIMED_OUT=\(shell.timedOut) TRUNCATED=\(shell.outputTruncated)
            \(shell.output)
            """
        } catch {
            output = "ISH_SMOKE_ERROR=\(error.localizedDescription)"
        }
    }
}
#endif
