import Foundation
import XCTest
@testable import OpenMuseCore

final class ArtifactAssetStoreTests: XCTestCase {
    func testWritesReadsAndDeletesChecksummedImagesByOpaqueIDs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseArtifactAssets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ArtifactAssetStore(rootURL: root)
        let artifactID = "artifact-1"
        let asset = PendingArtifactAsset(id: "image-1", displayName: "route.png", mediaType: "image/png", data: Data([1, 2, 3, 4]))

        let descriptor = try store.write(asset, for: artifactID)

        XCTAssertEqual(try store.data(for: descriptor, artifactID: artifactID), asset.data)
        XCTAssertEqual(try store.write(asset, for: artifactID), descriptor)
        XCTAssertThrowsError(try store.write(PendingArtifactAsset(id: asset.id, displayName: "other.png", mediaType: asset.mediaType, data: Data([9])), for: artifactID)) {
            XCTAssertEqual($0 as? ArtifactAssetStoreError, .conflict)
        }

        let file = root.appendingPathComponent(artifactID).appendingPathComponent(asset.id)
        try Data([9, 8, 7, 6]).write(to: file)
        XCTAssertThrowsError(try store.data(for: descriptor, artifactID: artifactID)) {
            XCTAssertEqual($0 as? ArtifactAssetStoreError, .checksumMismatch)
        }
        try store.removeAll(for: artifactID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(artifactID).path))
    }

    func testImageSelectionUsesAnAllowlistedMIMETypeAndSizeLimit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseArtifactImage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let image = root.appendingPathComponent("map.PNG")
        try Data([1, 2, 3]).write(to: image)

        let pending = try ArtifactAssetStore.prepareFile(at: image)
        XCTAssertEqual(pending.mediaType, "image/png")
        XCTAssertEqual(pending.displayName, "map.PNG")

        let unsupported = root.appendingPathComponent("map.svg")
        try Data("<svg/>".utf8).write(to: unsupported)
        XCTAssertThrowsError(try ArtifactAssetStore.prepareFile(at: unsupported)) {
            XCTAssertEqual($0 as? ArtifactAssetStoreError, .unsupportedType)
        }
    }

    func testAuthenticatedBridgeFileIDKeepsArtifactAndAssetIDsUnambiguous() throws {
        let encoded = try XCTUnwrap(BridgeFileTransferID.artifactAsset(artifactID: "artifact-1", assetID: "image-2"))
        XCTAssertEqual(BridgeFileTransferID.artifactAssetComponents(from: encoded)?.artifactID, "artifact-1")
        XCTAssertEqual(BridgeFileTransferID.artifactAssetComponents(from: encoded)?.assetID, "image-2")
        XCTAssertTrue(BridgeFileTransferID.isValid(encoded))
        XCTAssertFalse(BridgeFileTransferID.isValid("artifact~../outside~image"))
    }
}
