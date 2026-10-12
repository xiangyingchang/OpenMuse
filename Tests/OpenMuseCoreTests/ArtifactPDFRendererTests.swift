import Foundation
import PDFKit
import XCTest
@testable import OpenMuseCore

final class ArtifactPDFRendererTests: XCTestCase {
    func testReadingSnapshotIsAValidMultipagePDFWithChineseText() throws {
        let body = Array(repeating: "第1天：抵达恩施，入住后在市区轻松散步。", count: 180).joined(separator: "\n\n")
        let data = try ArtifactPDFRenderer.render(title: "恩施七日旅行", subtitle: "旅行计划 · 第 2 版 · 覆盖 4/7 天", body: body)
        XCTAssertTrue(data.starts(with: Data("%PDF-".utf8)))
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        XCTAssertTrue(pdf.string?.contains("恩施七日旅行") == true)
        XCTAssertTrue(pdf.string?.contains("第1天") == true)
    }
}
