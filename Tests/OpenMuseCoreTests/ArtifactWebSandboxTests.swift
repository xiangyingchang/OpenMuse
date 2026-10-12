import XCTest
@testable import OpenMuseCore

final class ArtifactWebSandboxTests: XCTestCase {
    func testWebArtifactWrapperBlocksNetworkFormsFramesAndTopLevelNavigation() {
        let wrapped = ArtifactWebSandbox.wrappedHTML("<a href=\"https://example.com\">外链</a><img src=\"https://example.com/pixel.png\"><form action=\"https://example.com\"></form>")

        XCTAssertTrue(wrapped.contains("default-src 'none'"))
        XCTAssertTrue(wrapped.contains("connect-src 'none'"))
        XCTAssertTrue(wrapped.contains("form-action 'none'"))
        XCTAssertTrue(wrapped.contains("frame-src 'none'"))
        XCTAssertFalse(wrapped.contains("<iframe"))
        XCTAssertTrue(wrapped.contains("https://example.com"))
    }

    func testWrapperInsertsCSPBeforeArtifactScripts() throws {
        let wrapped = ArtifactWebSandbox.wrappedHTML("<!doctype html><html><head><script>window.loaded = true;</script></head><body>内容</body></html>")

        let policyIndex = try XCTUnwrap(wrapped.range(of: "Content-Security-Policy")).lowerBound
        let scriptIndex = try XCTUnwrap(wrapped.range(of: "<script>")).lowerBound
        XCTAssertLessThan(policyIndex, scriptIndex)
        XCTAssertTrue(wrapped.contains("default-src 'none'"))
    }

    func testExternalLinkApprovalAcceptsOnlyCredentialFreeWebURLs() throws {
        XCTAssertEqual(
            ArtifactWebSandbox.validatedExternalURL(URL(string: "https://example.com/travel"))?.absoluteString,
            "https://example.com/travel"
        )
        XCTAssertEqual(
            ArtifactWebSandbox.validatedExternalURL(URL(string: "http://example.com"))?.host,
            "example.com"
        )
        XCTAssertNil(ArtifactWebSandbox.validatedExternalURL(URL(string: "javascript:alert(1)")))
        XCTAssertNil(ArtifactWebSandbox.validatedExternalURL(URL(string: "file:///etc/passwd")))
        XCTAssertNil(ArtifactWebSandbox.validatedExternalURL(URL(string: "https://user:secret@example.com")))
        XCTAssertNil(ArtifactWebSandbox.validatedExternalURL(URL(string: "https:///missing-host")))
    }
}
