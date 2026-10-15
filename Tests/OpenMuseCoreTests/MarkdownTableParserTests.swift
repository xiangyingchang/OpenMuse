import XCTest
@testable import OpenMuseCore

final class MarkdownTableParserTests: XCTestCase {
    func testParsesMarkdownRowsWithoutOptionalOuterPipes() throws {
        let lines = [
            "前言",
            "项目 | 完整说明 | 日期",
            "--- | --- | ---",
            "路线 | 从广州出发，第一天先到恩施市区，再按天气决定后续安排 | 周五",
            "正文结束"
        ]

        let block = try XCTUnwrap(MarkdownTableParser.parse(lines: lines, startingAt: 1))
        XCTAssertEqual(block.table.rows, [
            ["项目", "完整说明", "日期"],
            ["路线", "从广州出发，第一天先到恩施市区，再按天气决定后续安排", "周五"]
        ])
        XCTAssertEqual(block.table.columnCount, 3)
        XCTAssertEqual(block.lastLineIndex, 3)
    }

    func testParsesLeadingAndTrailingPipesAndKeepsEscapedOrCodePipesInCells() throws {
        let lines = [
            "| 名称 | 表达式 |",
            "| --- | --- |",
            "| 纵向拉 | `x|y` 与 a\\|b |"
        ]

        let block = try XCTUnwrap(MarkdownTableParser.parse(lines: lines, startingAt: 0))
        XCTAssertEqual(block.table.rows, [
            ["名称", "表达式"],
            ["纵向拉", "`x|y` 与 a|b"]
        ])
    }

    func testPadsShortRowsWithoutDroppingTheLastColumn() throws {
        let lines = [
            "| A | B | C |",
            "| --- | --- | --- |",
            "| 1 | 2 |",
            "| 3 | 4 | 5 |"
        ]

        let block = try XCTUnwrap(MarkdownTableParser.parse(lines: lines, startingAt: 0))
        XCTAssertEqual(block.table.rows, [
            ["A", "B", "C"],
            ["1", "2", ""],
            ["3", "4", "5"]
        ])
    }

    func testDoesNotTreatAHeadingFollowedByHorizontalRuleAsATable() {
        XCTAssertNil(MarkdownTableParser.parse(lines: ["训练记录", "---", "下一段"], startingAt: 0))
    }
}
