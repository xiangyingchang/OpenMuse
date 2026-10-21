import XCTest
@testable import OpenMuseCore

final class MarkdownDocumentDisplaySourceTests: XCTestCase {
    func testHidesMemoryProjectionCommentsAndClaimAnchorsButKeepsReadableClaims() {
        let source = """
        # MEMORY

        ## 当前有效的结构化记忆
        <!-- OPENMUSE_MEMORY_LEDGER_BEGIN -->
        ### 身份与地点
        <a id="claim-1234-abcd"></a>
        <!-- openmuse-memory-claim:1234-ABCD -->
        - 我是今天打的网球（明确表达，2026-10-13；有效期：自 2026-10-13 起；可信度：1.00）
        <!-- OPENMUSE_MEMORY_LEDGER_END -->
        """

        let readable = MarkdownDocumentDisplaySource.readableMarkdown(from: source)

        XCTAssertTrue(readable.contains("# MEMORY"))
        XCTAssertTrue(readable.contains("## 当前有效的结构化记忆"))
        XCTAssertTrue(readable.contains("### 身份与地点"))
        XCTAssertTrue(readable.contains("我是今天打的网球"))
        XCTAssertTrue(readable.contains("可信度：1.00"))
        XCTAssertFalse(readable.contains("OPENMUSE_MEMORY_LEDGER"))
        XCTAssertFalse(readable.contains("openmuse-memory-claim:"))
        XCTAssertFalse(readable.contains("<a id="))
        XCTAssertTrue(source.contains("openmuse-memory-claim:"), "The saved source must remain unchanged.")
    }

    func testJoinsSoftWrappedParagraphsAndKeepsMarkdownBlockBoundaries() {
        let source = """
        第一行是同一段落。
        第二行继续这一段。

        - 第一项
        - 第二项

        | 项目 | 状态 |
        | --- | --- |
        | 记忆 | 已保留 |
        """

        let readable = MarkdownDocumentDisplaySource.readableMarkdown(from: source)

        XCTAssertTrue(readable.contains("第一行是同一段落。 第二行继续这一段。"))
        XCTAssertTrue(readable.contains("- 第一项\n- 第二项"))
        XCTAssertTrue(readable.contains("| 项目 | 状态 |\n| --- | --- |\n| 记忆 | 已保留 |"))
    }

    func testDoesNotHideHTMLCommentsInsideFencedCode() {
        let source = """
        示例：

        ```html
        <!-- this comment is part of the code sample -->
        <a id="claim-example"></a>
        ```
        """

        let readable = MarkdownDocumentDisplaySource.readableMarkdown(from: source)

        XCTAssertTrue(readable.contains("<!-- this comment is part of the code sample -->"))
        XCTAssertTrue(readable.contains("<a id=\"claim-example\"></a>"))
    }

    func testFormatsMemoryClaimProvenanceAsReadableSecondaryMetadata() throws {
        let line = "- 我是今天打的网球（明确表达，2026-10-13；有效期：自2026-10-13起；可信度：1.00；范围：user；类别：identity）"

        let display = try XCTUnwrap(MarkdownDocumentDisplaySource.memoryClaimDisplay(in: line))

        XCTAssertEqual(display.value, "我是今天打的网球")
        XCTAssertEqual(display.metadata, "来源：明确表达 · 记录于 2026-10-13 · 有效期：自2026-10-13起 · 可信度：100%")
        XCTAssertFalse(display.metadata.contains("范围："))
        XCTAssertFalse(display.metadata.contains("类别："))
    }
}
