import Foundation
import XCTest
@testable import OpenMuseCore

final class QQMailConnectorTests: XCTestCase {
    func testQQMailUsesReadOnlyCommandsAndImportsBoundedPlainTextSnippet() async throws {
        let transport = FixtureIMAPTransport()
        let credentials = QQMailCredentials(emailAddress: "muse-test@qq.com", authorizationCode: "0123456789abcdef")
        let messages: [QQMailMessage]
        do {
            messages = try await QQMailConnector(credentials: credentials, transport: transport).fetchRecentMessages(daysBack: 14, limit: 5)
        } catch {
            XCTFail("fetch failed after commands: \(await transport.recordedCommands()); \(error)")
            throw error
        }
        let commands = await transport.recordedCommands()

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.subject, "恩施旅行计划")
        XCTAssertEqual(messages.first?.sender, "旅伴 <friend@example.com>")
        XCTAssertEqual(messages.first?.snippet, "Hello OpenMuse")
        XCTAssertTrue(messages.first?.id.contains("qq:") == true)
        XCTAssertTrue(commands.contains { $0.contains("EXAMINE INBOX") })
        XCTAssertTrue(commands.contains { $0.contains("UID SEARCH SINCE") })
        XCTAssertTrue(commands.contains { $0.contains("BODY.PEEK[TEXT]<0.2048>") })
        XCTAssertTrue(commands.contains { $0.contains("BODY.PEEK[HEADER.FIELDS") })
        XCTAssertTrue(commands.contains { $0.hasSuffix("LOGOUT") })
        XCTAssertTrue(commands.allSatisfy {
            let uppercased = $0.uppercased()
            return !uppercased.contains(" STORE ") && !uppercased.contains(" DELETE ") &&
                !uppercased.contains(" MOVE ") && !uppercased.contains(" APPEND ") && !uppercased.contains(" SMTP ")
        })

        let imported = messages[0].referenceDraft
        XCTAssertEqual(imported.provider, "qq-mail")
        XCTAssertTrue(imported.content.contains("邮件摘录"))
        XCTAssertTrue(imported.content.contains("Hello OpenMuse"))
        XCTAssertTrue(imported.content.utf8.count < 4_000)
    }

    func testQQMailRequiresClientAuthorizationCodeAndLimitsRequestedRange() async throws {
        XCTAssertFalse(QQMailCredentials(emailAddress: "user@qq.com", authorizationCode: "password").isValid)
        XCTAssertFalse(QQMailCredentials(emailAddress: "user@qq.com", authorizationCode: "0123456789abcde\n").isValid)

        let transport = FixtureIMAPTransport()
        let connector = QQMailConnector(
            credentials: QQMailCredentials(emailAddress: "user@qq.com", authorizationCode: "0123456789abcdef"),
            transport: transport
        )
        _ = try await connector.fetchRecentMessages(daysBack: 365, limit: 5_000)
        let commands = await transport.recordedCommands()
        XCTAssertTrue(commands.contains { $0.contains("UID SEARCH SINCE") })
        XCTAssertEqual(commands.filter { $0.contains("BODY.PEEK[TEXT]") }.count, 1)
    }

    func testIMAPLiteralReaderAndMIMEHeaderDecoding() throws {
        let headers = "Subject: =?UTF-8?B?5peF6KGM?=\r\nFrom: =?UTF-8?Q?=E5=BC=A0=E4=B8=89?= <a@example.com>\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n"
        let body = "=E6=AF=8F=E5=A4=A9=E7=95=99=E4=B8=80=E7=82=B9=E8=87=AA=E7=94=B1=E6=97=B6=E9=97=B4"
        let raw = imapFetchResponse(literal: Data(headers.utf8), tag: "OM0003")
        let parsedHeaders = IMAPMailParser.headers(try IMAPResponseParser.firstLiteral(raw))
        XCTAssertEqual(IMAPMailParser.decodeHeader(parsedHeaders["subject"] ?? ""), "旅行")
        XCTAssertEqual(IMAPMailParser.decodeHeader(parsedHeaders["from"] ?? ""), "张三 <a@example.com>")
        let snippet = IMAPMailParser.plainTextSnippet(Data(body.utf8), headers: parsedHeaders, limit: 2_048)
        XCTAssertEqual(snippet, "每天留一点自由时间")
        XCTAssertEqual(IMAPResponseParser.finalStatus(raw), "OK")
    }

    func testIMAPMultipartAlternativePrefersDecodedPlainText() throws {
        let headers = ["content-type": "multipart/alternative; boundary=\"alt-42\""]
        let body = """
        --alt-42
        Content-Type: text/html; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        <p>HTML copy should not be selected.</p>
        --alt-42
        Content-Type: text/plain; charset="utf-8"
        Content-Transfer-Encoding: quoted-printable

        =E6=AF=8F=E5=A4=A9=E4=BF=9D=E7=95=99=E8=87=AA=E7=94=B1=E6=97=B6=E9=97=B4
        --alt-42--
        """

        XCTAssertEqual(
            IMAPMailParser.plainTextSnippet(Data(body.utf8), headers: headers, limit: 2_048),
            "每天保留自由时间"
        )
    }

    func testIMAPNestedMultipartSkipsTextAttachmentAndDecodesGB18030Base64() throws {
        let headers = ["content-type": "multipart/mixed; boundary=outer"]
        let body = """
        --outer
        Content-Type: text/plain; charset=utf-8
        Content-Disposition: attachment; filename="notes.txt"

        不要导入附件内容。
        --outer
        Content-Type: multipart/alternative; boundary="inner"

        --inner
        Content-Type: text/html; charset=utf-8

        <p>HTML alternative</p>
        --inner
        Content-Type: text/plain; charset=gb18030
        Content-Transfer-Encoding: base64

        w7/M7MLD0NA=
        --inner--
        --outer--
        """

        XCTAssertEqual(
            IMAPMailParser.plainTextSnippet(Data(body.utf8), headers: headers, limit: 2_048),
            "每天旅行"
        )
    }

    func testIMAPMultipartPlainTextHonorsOutputLimitAndDoesNotFallBackToAttachment() throws {
        let headers = ["content-type": "multipart/mixed; boundary=x"]
        let attachmentOnly = """
        --x
        Content-Type: text/plain
        Content-Disposition: attachment; filename="body.txt"

        private attachment
        --x--
        """
        XCTAssertTrue(IMAPMailParser.plainTextSnippet(Data(attachmentOnly.utf8), headers: headers, limit: 2_048).contains("未找到可安全读取的纯文本正文"))

        let plainHeaders = ["content-type": "text/plain; charset=utf-8"]
        XCTAssertEqual(IMAPMailParser.plainTextSnippet(Data("abcdef".utf8), headers: plainHeaders, limit: 4), "abcd")
    }

    func testIMAPMultipartParserStopsAtNestingLimit() throws {
        var entity = "Content-Type: text/plain; charset=utf-8\n\n正文不应越过递归限制。"
        for level in 0..<10 {
            entity = "--b\(level)\nContent-Type: multipart/mixed; boundary=b\(level)\n\n\(entity)\n--b\(level)--"
        }
        let snippet = IMAPMailParser.plainTextSnippet(
            Data(entity.utf8), headers: ["content-type": "multipart/mixed; boundary=b9"], limit: 2_048
        )
        XCTAssertTrue(snippet.contains("未找到可安全读取的纯文本正文"))
        XCTAssertFalse(snippet.contains("正文不应越过递归限制"))
    }

    private func imapFetchResponse(literal: Data, tag: String) -> Data {
        var response = Data("* 1 FETCH (UID 101 BODY[HEADER.FIELDS] {\(literal.count)}\r\n".utf8)
        response.append(literal)
        response.append(Data("\r\n)\r\n\(tag) OK FETCH completed\r\n".utf8))
        return response
    }
}

private actor FixtureIMAPTransport: IMAPCommandTransport {
    private var commands: [String] = []
    private var tagNumber = 0

    func connect() async throws -> Data { Data("* OK QQ Mail IMAP ready\r\n".utf8) }

    func command(_ command: String) async throws -> Data {
        commands.append(command)
        tagNumber += 1
        let tag = String(format: "OM%04d", tagNumber)
        let body = command
        if body.hasPrefix("LOGIN ") { return Data("\(tag) OK LOGIN completed\r\n".utf8) }
        if body == "EXAMINE INBOX" { return Data("* OK [UIDVALIDITY 9001] UIDs valid\r\n\(tag) OK [READ-ONLY] EXAMINE completed\r\n".utf8) }
        if body.hasPrefix("UID SEARCH") { return Data("* SEARCH 102\r\n\(tag) OK SEARCH completed\r\n".utf8) }
        if body.contains("BODY.PEEK[HEADER.FIELDS") {
            let headers = "From: =?UTF-8?B?5peF5Ly0?= <friend@example.com>\r\nSubject: =?UTF-8?B?5oGp5pa95peF6KGM6K6h5YiS?=\r\nDate: Sat, 10 Oct 2026 12:00:00 +0800\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n"
            return Self.fetchResponse(literal: Data(headers.utf8), uid: 102, tag: tag)
        }
        if body.contains("BODY.PEEK[TEXT]") {
            return Self.fetchResponse(literal: Data("Hello=20OpenMuse".utf8), uid: 102, tag: tag)
        }
        if body == "LOGOUT" { return Data("* BYE Logging out\r\n\(tag) OK LOGOUT completed\r\n".utf8) }
        throw QQMailConnectorError.invalidResponse
    }

    func close() async {}
    func recordedCommands() -> [String] { commands }

    private static func fetchResponse(literal: Data, uid: UInt32, tag: String) -> Data {
        var response = Data("* 1 FETCH (UID \(uid) BODY[SECTION] {\(literal.count)}\r\n".utf8)
        response.append(literal)
        response.append(Data("\r\n)\r\n\(tag) OK FETCH completed\r\n".utf8))
        return response
    }
}
