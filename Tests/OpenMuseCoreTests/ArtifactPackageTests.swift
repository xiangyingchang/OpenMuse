import Foundation
import XCTest
import ZIPFoundation
@testable import OpenMuseCore

final class ArtifactPackageTests: XCTestCase {
    func testPackageRoundTripsWebArtifactHistoryAndAssets() throws {
        let previous = ArtifactRecord(
            id: "artifact-travel-1", title: "恩施计划", kind: "web", conversationID: "conversation-1",
            goalID: nil, currentRevision: 1, content: "<main>旧版</main>", status: "ready"
        )
        let current = ArtifactRecord(
            id: previous.id, title: previous.title, kind: "web", conversationID: previous.conversationID,
            goalID: nil, currentRevision: 2, content: "<!doctype html><button>展开</button>", status: "ready",
            sourceMessageIDs: ["message-1"], assumptions: ["日期尚未确定"], expectedDayCount: 7, coveredDayCount: 7
        )
        let package = ArtifactPackage(
            artifact: current,
            history: [previous],
            assets: [ArtifactPackageAsset(id: "asset-image-1", mediaType: "image/png", data: Data([1, 2, 3, 4]))],
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let decoded = try ArtifactPortablePackage.decode(ArtifactPortablePackage.encode(package))

        XCTAssertEqual(decoded.artifact, current)
        XCTAssertEqual(decoded.history, [previous])
        XCTAssertEqual(decoded.assets, package.assets)
        XCTAssertEqual(decoded.exportedAt, package.exportedAt)
    }

    func testPackageRoundTripsNamedTravelPlanAlternativesAndRejectsInvalidSelection() throws {
        let sevenDays = TravelPlanVariantRecord(
            id: "plan-7-days", title: "7天方案", content: "## Day 1\n七天原案\n\n## Day 2\n继续慢行",
            expectedDayCount: 7, coveredDayCount: 2
        )
        let fiveDays = TravelPlanVariantRecord(
            id: "plan-5-days", title: "5天方案", content: "## Day 1\n五天备选\n\n## Day 2\n保留休息",
            expectedDayCount: 5, coveredDayCount: 2
        )
        let artifact = ArtifactRecord(
            id: "artifact-travel-variants", title: "恩施旅行", conversationID: "conversation-trip", goalID: nil,
            content: fiveDays.content, expectedDayCount: 5, coveredDayCount: 2,
            travelPlanVariants: [sevenDays, fiveDays], selectedTravelPlanVariantID: fiveDays.id
        )

        let decoded = try ArtifactPortablePackage.decode(ArtifactPortablePackage.encode(ArtifactPackage(artifact: artifact)))
        XCTAssertEqual(decoded.artifact.travelPlanVariants, [sevenDays, fiveDays])
        XCTAssertEqual(decoded.artifact.selectedTravelPlanVariantID, fiveDays.id)

        var invalid = artifact
        invalid.selectedTravelPlanVariantID = "missing-variant"
        XCTAssertThrowsError(try ArtifactPortablePackage.encode(ArtifactPackage(artifact: invalid)))
    }

    func testLegacyArtifactWithoutVariantFieldsStillDecodes() throws {
        let legacy = Data(#"""
        {"id":"legacy-trip","title":"旧旅行计划","kind":"travel-plan","conversationID":"conversation-1","currentRevision":1,"content":"## Day 1\\n休息\\n\\n## Day 2\\n散步","updatedAt":0}
        """#.utf8)
        let artifact = try JSONDecoder().decode(ArtifactRecord.self, from: legacy)
        XCTAssertEqual(artifact.id, "legacy-trip")
        XCTAssertNil(artifact.travelPlanVariants)
        XCTAssertNil(artifact.selectedTravelPlanVariantID)
    }

    func testPackageRejectsChangedContentEvenWhenZipIsRebuilt() throws {
        let artifact = ArtifactRecord(id: "artifact-1", title: "旅行", conversationID: "conversation-1", goalID: nil, content: "# 第一天\n休息\n\n# 第二天\n散步", status: "draft")
        let data = try ArtifactPortablePackage.encode(ArtifactPackage(artifact: artifact))
        var files = try readZip(data)
        let originalLength = try XCTUnwrap(files["content/plan.md"]).count
        files["content/plan.md"] = Data(repeating: 0x78, count: originalLength)
        let tampered = try makeZip(files)

        XCTAssertThrowsError(try ArtifactPortablePackage.decode(tampered)) { error in
            XCTAssertEqual(error as? ArtifactPackageError, .checksumMismatch)
        }
    }

    func testPackageRejectsPathTraversalBeforeReadingPayload() throws {
        let artifact = ArtifactRecord(id: "artifact-1", title: "旅行", conversationID: "conversation-1", goalID: nil, content: "# 第一天\n休息\n\n# 第二天\n散步", status: "draft")
        var files = try readZip(ArtifactPortablePackage.encode(ArtifactPackage(artifact: artifact)))
        files["../outside.txt"] = Data("private".utf8)

        XCTAssertThrowsError(try ArtifactPortablePackage.decode(makeZip(files))) { error in
            XCTAssertEqual(error as? ArtifactPackageError, .invalidArchive)
        }
    }

    @MainActor
    func testImportPreservesVersionsAndCreatesANewCopyForConflictingIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseArtifactPackageImport-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = ModelConfiguration(provider: .custom, endpoint: "https://artifact-package-import.example/v1", model: "fixture")
        let model = OpenMuseAppModel(runtimeOverride: nil, workspaceRootOverride: root.appendingPathComponent("workspace", isDirectory: true), configurationOverride: configuration, startMacBridge: false)
        let previous = ArtifactRecord(id: "portable-artifact", title: "旅行计划", conversationID: "old-conversation", goalID: nil, currentRevision: 1, content: "旧版", status: "draft")
        let current = ArtifactRecord(id: previous.id, title: previous.title, conversationID: previous.conversationID, goalID: nil, currentRevision: 2, content: "新版本", status: "ready")
        let firstPackage = try ArtifactPortablePackage.encode(ArtifactPackage(artifact: current, history: [previous]))

        let imported = try model.importArtifactPackage(data: firstPackage)
        XCTAssertEqual(imported.id, current.id)
        XCTAssertEqual(imported.content, current.content)
        XCTAssertNotEqual(imported.conversationID, current.conversationID)
        XCTAssertEqual(model.artifactHistory(id: imported.id).count, 2)
        XCTAssertEqual(try model.importArtifactPackage(data: firstPackage).id, imported.id)
        XCTAssertEqual(model.artifacts.count, 1)

        var conflicting = current
        conflicting.content = "另一份独立构件"
        let secondPackage = try ArtifactPortablePackage.encode(ArtifactPackage(artifact: conflicting))
        let copy = try model.importArtifactPackage(data: secondPackage)
        XCTAssertNotEqual(copy.id, imported.id)
        XCTAssertEqual(copy.content, conflicting.content)
        XCTAssertEqual(model.artifacts.count, 2)
    }

    @MainActor
    func testImageAssetsPersistRenderExportImportAndDeleteWithTheArtifact() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseArtifactAssetRoundTrip-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = ModelConfiguration(provider: .custom, endpoint: "https://artifact-assets.example/v1", model: "fixture")
        let source = OpenMuseAppModel(runtimeOverride: nil, workspaceRootOverride: root.appendingPathComponent("source/workspace", isDirectory: true), configurationOverride: configuration, startMacBridge: false)
        let artifact = ArtifactRecord(
            id: "portable-web-artifact", title: "旅行地图", kind: "web", conversationID: "source-conversation",
            goalID: nil, content: "<html><head></head><body><p>路线</p></body></html>", status: "ready"
        )
        let artifactPackage = try ArtifactPortablePackage.encode(ArtifactPackage(artifact: artifact))
        let imported = try source.importArtifactPackage(data: artifactPackage)
        let imageURL = root.appendingPathComponent("map.png")
        let imageData = Data([0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4])
        try imageData.write(to: imageURL)

        try source.addArtifactImages([imageURL], artifactID: imported.id)

        let updated = try XCTUnwrap(source.artifacts.first(where: { $0.id == imported.id }))
        let reference = try XCTUnwrap(updated.assetReferences?.first)
        XCTAssertEqual(updated.currentRevision, 2)
        XCTAssertTrue(updated.content.contains("openmuse-asset://\(reference.id)"))
        XCTAssertTrue(source.renderableArtifactContent(updated).contains("data:image/png;base64,\(imageData.base64EncodedString())"))
        let portable = try source.artifactPortablePackage(id: updated.id)
        XCTAssertEqual(portable.assets, [ArtifactPackageAsset(id: reference.id, mediaType: "image/png", data: imageData)])
        XCTAssertEqual(portable.history.count, 1)

        let destination = OpenMuseAppModel(runtimeOverride: nil, workspaceRootOverride: root.appendingPathComponent("destination/workspace", isDirectory: true), configurationOverride: configuration, startMacBridge: false)
        let copied = try destination.importArtifactPackage(data: ArtifactPortablePackage.encode(portable))
        XCTAssertEqual(copied.assetReferences, updated.assetReferences)
        XCTAssertTrue(destination.renderableArtifactContent(copied).contains("data:image/png;base64,\(imageData.base64EncodedString())"))
        destination.deleteArtifact(id: copied.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("destination/workspace/artifact-assets/\(copied.id)").path))
    }

    private func readZip(_ data: Data) throws -> [String: Data] {
        let archive = try Archive(data: data, accessMode: .read)
        var files: [String: Data] = [:]
        for entry in archive {
            var bytes = Data()
            _ = try archive.extract(entry) { bytes.append($0) }
            files[entry.path] = bytes
        }
        return files
    }

    private func makeZip(_ files: [String: Data]) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseArtifactTest-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .create)
        for (path, bytes) in files.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(bytes.count), compressionMethod: .deflate) { position, size in
                let lower = Int(position)
                let upper = min(lower + size, bytes.count)
                return bytes.subdata(in: lower..<upper)
            }
        }
        return try Data(contentsOf: url)
    }
}
