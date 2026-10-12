import XCTest
@testable import OpenMuseCore

final class MacAppBridgeStartupTests: XCTestCase {
    #if os(macOS)
    @MainActor
    func testMacAppModelStartsAReachableLoopbackHealthRoute() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenMuse-MacBridgeStartup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = OpenMuseAppModel(
            runtimeOverride: nil,
            workspaceRootOverride: root,
            configurationOverride: ModelConfiguration(),
            startMacBridge: true,
            bridgePortOverride: 0
        )
        defer { model.macBridgeServer.stop() }

        for _ in 0..<100 where !model.macBridgeServer.isRunning {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(model.macBridgeServer.isRunning, model.macBridgeServer.status)

        let port = try XCTUnwrap(model.macBridgeServer.localPort)
        let device = try await MacBridgeClient.check(address: "http://127.0.0.1:\(port)/openmuse")
        XCTAssertEqual(device, "OpenMuse Mac")
    }
    #endif
}
