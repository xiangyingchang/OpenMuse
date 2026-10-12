import Foundation
import XCTest
import ZIPFoundation
@testable import OpenMuseCore

final class WorkspaceBackupTests: XCTestCase {
    func testBackupBundleContainsReadableMemoryAndValidatedRestoreArchive() throws {
        let workspaceDocument = WorkspaceDocument(path: "USER.md", title: "USER", content: "喜欢轻松的旅行。")
        let snapshot = WorkspaceStoreSnapshot(records: [], revisions: [])
        let archive = try WorkspaceArchive.make(from: snapshot, includeConversations: true)
        let portable = try WorkspacePortableArchive.encode(archive)
        let package = try WorkspaceBackupPackage.make(workspaceArchive: portable, documents: [workspaceDocument])

        XCTAssertTrue(package.starts(with: [0x50, 0x4b]))
        XCTAssertEqual(try WorkspaceBackupPackage.workspaceArchive(fromPackage: package), portable)
        XCTAssertNil(try WorkspaceBackupPackage.workspaceArchive(fromPackage: portable), "Legacy portable archives stay directly importable.")
        XCTAssertEqual(try WorkspacePortableArchive.decode(try XCTUnwrap(WorkspaceBackupPackage.workspaceArchive(fromPackage: package))).manifest.recordCount, 0)
        XCTAssertEqual(String(data: try Self.entry("memory/USER.md", in: package), encoding: .utf8), "喜欢轻松的旅行。")

        let readme = try XCTUnwrap(String(data: Self.entry("README.md", in: package), encoding: .utf8))
        XCTAssertTrue(readme.contains("workspace.zip"))
        XCTAssertTrue(readme.contains("USER.md"))
        XCTAssertTrue(readme.contains("聊天记录、活动和任务草稿已包含"))
    }

    func testBackupPackageRejectsInvalidWorkspaceArchive() throws {
        XCTAssertThrowsError(try WorkspaceBackupPackage.make(workspaceArchive: Data("invalid".utf8), documents: []))
    }

    func testDailyScheduleCalculatesNextOccurrenceAndDueState() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let schedule = WorkspaceBackupSchedule(enabled: true, hour: 21, minute: 15)
        let before = date("2026-10-12T20:00:00Z")
        let expected = date("2026-10-12T21:15:00Z")
        XCTAssertEqual(schedule.nextRun(after: before, calendar: calendar), expected)
        XCTAssertFalse(schedule.isDue(at: before, lastCompletedAt: nil, calendar: calendar))
        XCTAssertTrue(schedule.isDue(at: date("2026-10-12T21:16:00Z"), lastCompletedAt: nil, calendar: calendar))
        XCTAssertFalse(schedule.isDue(at: date("2026-10-12T22:00:00Z"), lastCompletedAt: expected, calendar: calendar))
    }

    func testRetentionOnlyRemovesScheduledBackupsAndNeverManualExports() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for name in [
            "OpenMuse-ScheduledBackup-20261010-210000-a.zip",
            "OpenMuse-ScheduledBackup-20261011-210000-b.zip",
            "OpenMuse-ScheduledBackup-20261012-210000-c.zip",
            "OpenMuse-Export-20261010-210000-a.zip",
            "OpenMuse-Backup-20261009-210000-legacy.zip",
            "family-photo.zip"
        ] {
            try Data("test".utf8).write(to: directory.appendingPathComponent(name))
        }

        WorkspaceBackupStorage.pruneBackups(in: directory, keeping: 2)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(remaining.filter { $0.hasPrefix("OpenMuse-ScheduledBackup-") && $0.hasSuffix(".zip") }.count, 2)
        XCTAssertTrue(remaining.contains("OpenMuse-Export-20261010-210000-a.zip"))
        XCTAssertTrue(remaining.contains("OpenMuse-Backup-20261009-210000-legacy.zip"))
        XCTAssertTrue(remaining.contains("family-photo.zip"))
    }

    func testManualExportWriteDoesNotTriggerScheduledRetention() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for day in ["10", "11", "12"] {
            let name = "OpenMuse-ScheduledBackup-202610\(day)-210000-old.zip"
            try Data("old".utf8).write(to: directory.appendingPathComponent(name))
        }

        let url = try WorkspaceBackupStorage.write(
            Data("manual".utf8),
            to: directory,
            date: date("2026-10-13T21:00:00Z"),
            retentionCount: 1,
            kind: .manualExport
        )
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("OpenMuse-Export-"))
        XCTAssertEqual(remaining.filter { $0.hasPrefix("OpenMuse-ScheduledBackup-") }.count, 3)
        XCTAssertEqual(remaining.filter { $0.hasPrefix("OpenMuse-Export-") }.count, 1)

        _ = try WorkspaceBackupStorage.write(
            Data("scheduled".utf8),
            to: directory,
            date: date("2026-10-14T21:00:00Z"),
            retentionCount: 1,
            kind: .scheduled
        )
        let afterScheduledRun = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(afterScheduledRun.filter { $0.hasPrefix("OpenMuse-ScheduledBackup-") }.count, 1)
        XCTAssertEqual(afterScheduledRun.filter { $0.hasPrefix("OpenMuse-Export-") }.count, 1)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private static func entry(_ path: String, in data: Data) throws -> Data {
        let archive = try Archive(data: data, accessMode: .read)
        let entry = try XCTUnwrap(archive[path])
        var result = Data()
        _ = try archive.extract(entry, bufferSize: 16 * 1024) { result.append($0) }
        return result
    }
}
