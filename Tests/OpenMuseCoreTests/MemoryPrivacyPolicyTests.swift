import XCTest
@testable import OpenMuseCore

final class MemoryPrivacyPolicyTests: XCTestCase {
    func testExplicitSensitiveTermsAreRecognizedWithoutFlaggingOrdinaryInterests() {
        XCTAssertTrue(MemoryPrivacyPolicy.isSensitive("我喜欢低糖饮食"))
        XCTAssertTrue(MemoryPrivacyPolicy.isSensitive("Health & dietary: nut allergy"))
        XCTAssertTrue(MemoryPrivacyPolicy.isSensitive("salary and debt details"))
        XCTAssertFalse(MemoryPrivacyPolicy.isSensitive("我喜欢自然摄影和轻松旅行"))
        XCTAssertFalse(MemoryPrivacyPolicy.isSensitive("我对心理学和金融科技感兴趣"))
    }

    func testLegacyMemoryClaimWithoutSensitivityFieldStillDecodes() throws {
        let data = Data(#"{"id":"legacy-claim","value":"我喜欢慢节奏旅行","category":"preference","scope":"user","confidence":1,"sourceType":"explicit-user-message","sourceID":"message-1","sourceText":"我喜欢慢节奏旅行","status":"active","createdAt":0,"updatedAt":0}"#.utf8)

        let decoded = try JSONDecoder().decode(MemoryClaimRecord.self, from: data)

        XCTAssertEqual(decoded.id, "legacy-claim")
        XCTAssertNil(decoded.isSensitive)
        XCTAssertNil(decoded.validFrom)
        XCTAssertNil(decoded.validUntil)
    }

    func testOnlyClearRememberPhrasingCountsAsSensitiveMemoryOptIn() {
        XCTAssertTrue(MemoryPrivacyPolicy.explicitlyRequestsRetention("记住我对花生过敏"))
        XCTAssertTrue(MemoryPrivacyPolicy.explicitlyRequestsRetention("以后请记得我的药物过敏"))
        XCTAssertFalse(MemoryPrivacyPolicy.explicitlyRequestsRetention("我对花生过敏"))
        XCTAssertFalse(MemoryPrivacyPolicy.explicitlyRequestsRetention("以后请不要主动提我的健康信息"))
        XCTAssertFalse(MemoryPrivacyPolicy.explicitlyRequestsRetention("我最近在做治疗"))
    }
}
