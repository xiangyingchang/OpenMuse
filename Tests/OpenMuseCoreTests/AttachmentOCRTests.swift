import CoreGraphics
import CoreText
import Foundation
import PDFKit
import XCTest
@testable import OpenMuseCore

final class AttachmentOCRTests: XCTestCase {
    func testScannedPDFPageIsRecognizedLocallyWhenItHasNoTextLayer() throws {
        let pdfData = try makeImageOnlyPDF(text: "OPENMUSE TRIP PLAN")
        let document = try XCTUnwrap(PDFDocument(data: pdfData))
        XCTAssertNil(document.page(at: 0)?.string)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenMuseScannedPDF-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try AttachmentStore(rootURL: directory)
        let record = try store.importData(
            pdfData,
            displayName: "scan.pdf",
            mediaType: "application/pdf",
            conversationID: "conversation-1",
            messageID: "message-1"
        )

        let extracted = try store.extractedText(for: record)
        XCTAssertTrue(extracted.uppercased().contains("OPENMUSE"), "OCR should recover text from a scanned PDF page: \(extracted)")
        XCTAssertTrue(extracted.uppercased().contains("TRIP"), "OCR should retain multiple words from the scanned page: \(extracted)")
    }

    func testScannedPDFOCRReportsWhenItReachesThePageLimit() throws {
        let pdfData = try makeImageOnlyPDF(text: nil, pageCount: AttachmentStore.maximumPDFPagesForOCR + 1)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenMuseScannedPDFLimit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try AttachmentStore(rootURL: directory)
        let record = try store.importData(
            pdfData,
            displayName: "blank-scan.pdf",
            mediaType: "application/pdf",
            conversationID: "conversation-1",
            messageID: "message-1"
        )

        let extracted = try store.extractedText(for: record)
        XCTAssertTrue(extracted.contains("仅覆盖前 20 个无文本页面"))
    }

    private func makeImageOnlyPDF(text: String?, pageCount: Int = 1) throws -> Data {
        let imageWidth = 1_800
        let imageHeight = 2_400
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let bitmap = try XCTUnwrap(CGContext(
            data: nil,
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        if let text {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 100, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            bitmap.textPosition = CGPoint(x: 120, y: imageHeight / 2)
            CTLineDraw(line, bitmap)
        }
        let image = try XCTUnwrap(bitmap.makeImage())

        let pdfURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenMuseScannedFixture-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(url: pdfURL as CFURL))
        let pdf = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for _ in 0..<pageCount {
            pdf.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)
            pdf.draw(image, in: mediaBox)
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return try Data(contentsOf: pdfURL)
    }
}
