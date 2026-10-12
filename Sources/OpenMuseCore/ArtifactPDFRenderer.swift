import CoreGraphics
import CoreText
import Foundation

/// Creates a self-contained, non-interactive reading snapshot for a text artifact.
public enum ArtifactPDFRenderer {
    public static func render(title: String, subtitle: String? = nil, body: String) throws -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margins: CGFloat = 52
        let output = NSMutableData()
        var mediaBox = page
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let text = NSMutableAttributedString()
        let titleFont = CTFontCreateWithName("PingFangSC-Semibold" as CFString, 21, nil)
        let bodyFont = CTFontCreateWithName("PingFangSC-Regular" as CFString, 11, nil)
        text.append(NSAttributedString(string: title + "\n", attributes: [Self.fontKey: titleFont]))
        if let subtitle, !subtitle.isEmpty {
            text.append(NSAttributedString(string: subtitle + "\n\n", attributes: [Self.fontKey: bodyFont, Self.foregroundKey: CGColor(gray: 0.38, alpha: 1)]))
        } else {
            text.append(NSAttributedString(string: "\n", attributes: [Self.fontKey: bodyFont]))
        }
        text.append(NSAttributedString(string: body, attributes: [Self.fontKey: bodyFont]))

        let framesetter = CTFramesetterCreateWithAttributedString(text)
        var location = 0
        while location < text.length {
            context.beginPDFPage(nil)
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: 0, y: page.height)
            context.scaleBy(x: 1, y: -1)
            let path = CGMutablePath()
            path.addRect(CGRect(x: margins, y: margins, width: page.width - 2 * margins, height: page.height - 2 * margins))
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.restoreGState()
            context.endPDFPage()
            guard visible.length > 0 else { throw CocoaError(.fileWriteUnknown) }
            location = visible.location + visible.length
        }
        context.closePDF()
        return output as Data
    }

    private static let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
    private static let foregroundKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
}
