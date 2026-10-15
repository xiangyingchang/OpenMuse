import XCTest
@testable import OpenMuseCore

@MainActor
final class DreamingReviewTests: XCTestCase {
    func testLegacyMaintenanceProposalDecodesWithoutGoalReference() throws {
        let legacy = Data(#"{"id":"old-proposal","runID":"old-run","kind":"fact","title":"旅行偏好","content":"慢慢旅行","rationale":"用户明确表达。","sourceMessageIDs":["source-1"],"confidence":0.8,"status":"pending","createdAt":0,"updatedAt":0}"#.utf8)
        let decoded = try JSONDecoder().decode(MaintenanceProposalRecord.self, from: legacy)
        XCTAssertNil(decoded.targetGoalID)
        XCTAssertNil(decoded.evidence)
        XCTAssertTrue(decoded.isValid)
    }

    func testLegacyEvidenceDecodesWithoutFullSourceDigest() throws {
        let legacy = Data(#"{"id":"old-evidence-proposal","runID":"old-evidence-run","kind":"fact","title":"旅行偏好","content":"慢慢旅行","rationale":"用户明确表达。","sourceMessageIDs":["source-1"],"evidence":[{"sourceMessageID":"source-1","quote":"我喜欢旅行慢一点。"}],"confidence":0.8,"status":"pending","createdAt":0,"updatedAt":0}"#.utf8)
        let decoded = try JSONDecoder().decode(MaintenanceProposalRecord.self, from: legacy)
        let evidence = try XCTUnwrap(decoded.evidence?.first)
        XCTAssertNil(evidence.sourceContentDigest)
        XCTAssertTrue(decoded.isValid, "Existing proposals without source snapshots remain readable and retain quote-only validation.")
    }

    func testLegacyMaintenanceRunDecodesWithoutDreamingReflection() throws {
        let legacy = Data(#"{"id":"old-run","kind":"dreaming","status":"completed","sourceMessageIDs":["source-1"],"inputDigest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","summary":"回顾完成","provider":"DeepSeek","model":"deepseek-chat","attemptCount":1,"startedAt":0}"#.utf8)
        let decoded = try JSONDecoder().decode(MaintenanceRunRecord.self, from: legacy)
        XCTAssertNil(decoded.reflection)
        XCTAssertNil(decoded.reflectionEvidence)
        XCTAssertTrue(decoded.isValid)
    }

    func testDreamingReflectionRequiresVerbatimUserEvidence() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let conversation = ConversationRecord(id: "reflection-chat", title: "旅行")
        let source = MessageRecord(
            id: "reflection-source", conversationID: conversation.id, role: .user,
            content: "下次旅行别排太满，先给我轻松版。", createdAt: now
        )
        let validResponse = #"{"summary":"回顾完成。","reflection":"我会先提供轻松、留白更多的旅行方案。","reflectionEvidence":[{"sourceMessageID":"reflection-source","quote":"下次旅行别排太满，先给我轻松版。"}],"proposals":[]}"#
        let result = try DreamingReview.parse(validResponse, runID: "reflection-run", allowedSourceMessages: [source], now: now)
        XCTAssertEqual(result.reflection, "我会先提供轻松、留白更多的旅行方案。")
        XCTAssertEqual(result.reflectionEvidence?.first?.quote, source.content)
        XCTAssertEqual(result.reflectionEvidence?.first?.sourceContentDigest, SourceRecord.digest(source.content))

        let persistedRun = MaintenanceRunRecord(
            id: "reflection-run-record", sourceMessageIDs: [source.id], inputDigest: String(repeating: "c", count: 64),
            summary: "回顾完成", reflection: result.reflection, reflectionEvidence: result.reflectionEvidence,
            provider: "DeepSeek", model: "deepseek-chat"
        )
        XCTAssertTrue(persistedRun.isValid)
        var mismatchedRun = persistedRun
        mismatchedRun.reflectionEvidence = [MaintenanceEvidence(sourceMessageID: "other-source", quote: source.content)]
        XCTAssertFalse(mismatchedRun.isValid, "Reflection evidence must refer to a message recorded by the same run.")

        let invalidResponse = #"{"summary":"回顾完成。","reflection":"用户喜欢昂贵酒店。","reflectionEvidence":[{"sourceMessageID":"reflection-source","quote":"用户喜欢昂贵酒店。"}],"proposals":[]}"#
        let rejected = try DreamingReview.parse(invalidResponse, runID: "ungrounded-reflection", allowedSourceMessages: [source], now: now)
        XCTAssertNil(rejected.reflection, "A reflection with invented or inexact evidence must not persist.")
        XCTAssertNil(rejected.reflectionEvidence)
    }

    func testMaintenanceProposalRequiresOneUniqueEvidenceItemPerSource() {
        let evidence = MaintenanceEvidence(sourceMessageID: "source-1", quote: "我喜欢旅行慢一点。")
        var proposal = MaintenanceProposalRecord(
            id: "proposal", runID: "run", kind: "fact", title: "旅行偏好", content: "慢慢旅行",
            rationale: "用户明确表达。", sourceMessageIDs: ["source-1"], evidence: [evidence], confidence: 0.8
        )
        XCTAssertTrue(proposal.isValid)

        proposal.evidence = [evidence, evidence]
        XCTAssertFalse(proposal.isValid, "Duplicate quotes must not appear as separate source evidence.")

        proposal.evidence = [evidence]
        proposal.sourceMessageIDs = ["source-1", "source-1"]
        XCTAssertFalse(proposal.isValid, "Source IDs must be unique so each quote maps to one source.")
    }

    func testReviewRejectsImportedChatsAndUnknownOrAssistantOnlySources() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let own = ConversationRecord(id: "own", title: "旅行")
        let imported = ConversationRecord(id: "imported", title: "旧聊天", importedFrom: "ChatGPT", importedSourceID: "old-chat")
        let user = MessageRecord(id: "user-source", conversationID: own.id, role: .user, content: "我偏好轻松的旅行。", createdAt: now.addingTimeInterval(-100))
        let assistant = MessageRecord(id: "assistant-source", conversationID: own.id, role: .assistant, content: "下次可以安排慢一点。", createdAt: now.addingTimeInterval(-90))
        let importedMessage = MessageRecord(id: "imported-source", conversationID: imported.id, role: .user, content: "旧的个人资料。", createdAt: now.addingTimeInterval(-80))
        let eligible = DreamingReview.eligibleMessages([user, assistant, importedMessage], conversations: [own, imported], now: now)
        XCTAssertEqual(eligible.map(\.id), [user.id, assistant.id])

        let response = """
        {"summary":"可以先确认旅行节奏。","proposals":[
          {"kind":"understanding","title":"旅行节奏","content":"用户可能更喜欢轻松的旅行节奏。","rationale":"近期对话中有直接表达。","sourceMessageIDs":["user-source"],"evidence":[{"sourceMessageID":"user-source","quote":"我偏好轻松的旅行。"}],"confidence":0.8},
          {"kind":"fact","title":"旧资料","content":"用户喜欢某个城市。","rationale":"模型推测。","sourceMessageIDs":["invented-source"],"confidence":0.9},
          {"kind":"fact","title":"助手推测","content":"用户不喜欢早起。","rationale":"来自助手建议。","sourceMessageIDs":["assistant-source"],"confidence":0.9}
        ]}
        """
        let parsed = try DreamingReview.parse(response, runID: "run-1", allowedSourceMessages: eligible, now: now)
        XCTAssertEqual(parsed.proposals.count, 1)
        XCTAssertEqual(parsed.proposals.first?.sourceMessageIDs, [user.id])
        let evidence = try XCTUnwrap(parsed.proposals.first?.evidence?.first)
        XCTAssertEqual(evidence.sourceMessageID, user.id)
        XCTAssertEqual(evidence.quote, "我偏好轻松的旅行。")
        XCTAssertEqual(evidence.sourceContentDigest, SourceRecord.digest(user.content))
        XCTAssertEqual(parsed.proposals.first?.status, "pending")
    }

    func testReviewRequiresExactQuotedUserEvidenceForEverySource() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let conversation = ConversationRecord(id: "quoted-evidence-chat", title: "旅行")
        let user = MessageRecord(id: "quoted-user", conversationID: conversation.id, role: .user, content: "我喜欢旅行留一点休息时间。", createdAt: now)
        let assistant = MessageRecord(id: "quoted-assistant", conversationID: conversation.id, role: .assistant, content: "下次可以安排慢一点。", createdAt: now.addingTimeInterval(1))
        let response = """
        {"summary":"用户希望旅行不要太赶。","proposals":[
          {"kind":"fact","title":"旅行节奏","content":"旅行计划应留出休息时间。","rationale":"用户明确提到旅行中需要留出休息时间。","sourceMessageIDs":["quoted-user"],"evidence":[{"sourceMessageID":"quoted-user","quote":"我喜欢旅行留一点休息时间。"}],"confidence":0.9},
          {"kind":"fact","title":"伪造的引文","content":"用户喜欢在家休息。","rationale":"这句话来自用户。","sourceMessageIDs":["quoted-user"],"evidence":[{"sourceMessageID":"quoted-user","quote":"我喜欢宅在家里。"}],"confidence":0.9},
          {"kind":"fact","title":"引用助手内容","content":"用户不喜欢早起。","rationale":"对话里有依据。","sourceMessageIDs":["quoted-assistant"],"evidence":[{"sourceMessageID":"quoted-assistant","quote":"下次可以安排慢一点。"}],"confidence":0.9},
          {"kind":"fact","title":"没有引文","content":"旅行计划应留出休息时间。","rationale":"用户明确表达。","sourceMessageIDs":["quoted-user"],"confidence":0.9},
          {"kind":"fact","title":"错误来源映射","content":"旅行计划应留出休息时间。","rationale":"用户明确表达。","sourceMessageIDs":["quoted-user"],"evidence":[{"sourceMessageID":"quoted-user","quote":"下次可以安排慢一点。"}],"confidence":0.9}
        ]}
        """

        let parsed = try DreamingReview.parse(response, runID: "quoted-evidence-run", allowedSourceMessages: [user, assistant], now: now)
        XCTAssertEqual(parsed.proposals.map(\.title), ["旅行节奏"])
        XCTAssertEqual(parsed.proposals.first?.evidence?.map(\.quote), ["我喜欢旅行留一点休息时间。"])
    }

    func testDreamingRetrievesOnlyTheExplicitlyChangingMemoryCategoryWithoutKeywordOverlap() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let source = MessageRecord(
            id: "work-change-source", conversationID: "work-change-chat", role: .user,
            content: "我换了工作，现在负责海外市场。", createdAt: now
        )
        let oldWork = MemoryClaimRecord(
            id: "old-product-role", value: "我是产品经理", category: "identity", scope: "user",
            sourceType: "explicit-user-message", sourceID: "old-role-source", sourceText: "我是产品经理。",
            isInferred: false, isSensitive: false, updatedAt: now.addingTimeInterval(-30 * 86_400)
        )
        let unrelatedPreference = MemoryClaimRecord(
            id: "unrelated-travel-preference", value: "我喜欢慢节奏旅行", category: "preference", scope: "user",
            sourceType: "explicit-user-message", sourceID: "old-preference-source", sourceText: "我喜欢慢节奏旅行。",
            isInferred: false, isSensitive: false, updatedAt: now.addingTimeInterval(-30 * 86_400)
        )

        let prompt = try XCTUnwrap(DreamingReview.promptMessages(
            for: [source], confirmedMemories: [oldWork, unrelatedPreference], asOf: now
        ).first?.content)
        XCTAssertTrue(prompt.contains(oldWork.id), "A direct work change should recall the current work-related claim even without shared words.")
        XCTAssertFalse(prompt.contains(unrelatedPreference.id), "A work change must not expose an unrelated preference.")

        let response = """
        {"summary":"用户的工作方向已有变化。","proposals":[
          {"kind":"memory-update","title":"工作方向更新","content":"用户目前负责海外市场。","rationale":"用户明确表示更换了工作并说明了新的职责。","sourceMessageIDs":["work-change-source"],"evidence":[{"sourceMessageID":"work-change-source","quote":"我换了工作，现在负责海外市场。"}],"supersedesMemoryClaimID":"old-product-role","confidence":0.86}
        ]}
        """
        let parsed = try DreamingReview.parse(
            response, runID: "work-change-run", allowedSourceMessages: [source],
            allowedMemoryClaims: [oldWork, unrelatedPreference], now: now
        )
        XCTAssertEqual(parsed.proposals.map(\.supersedesMemoryClaimID), [oldWork.id])

        let thirdPartySource = MessageRecord(
            id: "third-party-work-source", conversationID: "work-change-chat", role: .user,
            content: "我朋友换了工作，现在负责海外市场。", createdAt: now
        )
        let thirdPartyPrompt = try XCTUnwrap(DreamingReview.promptMessages(
            for: [thirdPartySource], confirmedMemories: [oldWork], asOf: now
        ).first?.content)
        XCTAssertFalse(thirdPartyPrompt.contains(oldWork.id), "A third-party change must not trigger retrieval of the user's work profile.")

        let nameChangeSource = MessageRecord(
            id: "name-change-source", conversationID: "identity-change-chat", role: .user,
            content: "我现在改名叫李雷。", createdAt: now
        )
        let oldName = MemoryClaimRecord(
            id: "old-user-name", value: "我叫王小明", category: "identity", scope: "user",
            sourceType: "explicit-user-message", sourceID: "old-name-source", sourceText: "我叫王小明。",
            isInferred: false, isSensitive: false, updatedAt: now.addingTimeInterval(-30 * 86_400)
        )
        let oldRole = MemoryClaimRecord(
            id: "old-user-role", value: "我是产品经理", category: "identity", scope: "user",
            sourceType: "explicit-user-message", sourceID: "old-role-source", sourceText: "我是产品经理。",
            isInferred: false, isSensitive: false, updatedAt: now.addingTimeInterval(-30 * 86_400)
        )
        let nameChangePrompt = try XCTUnwrap(DreamingReview.promptMessages(
            for: [nameChangeSource], confirmedMemories: [oldName, oldRole], asOf: now
        ).first?.content)
        XCTAssertTrue(nameChangePrompt.contains(oldName.id), "A name change should recall the prior name without shared terms.")
        XCTAssertFalse(nameChangePrompt.contains(oldRole.id), "A name change must not disclose an unrelated occupation claim in the identity category.")
    }

    func testMemoryUpdateRequiresARelevantCurrentExplicitClaimAndExactUserEvidence() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let source = MessageRecord(
            id: "memory-update-source", conversationID: "memory-update-chat", role: .user,
            content: "我最近想调整旅行计划，不用每天都留很多休息时间，可以多安排一两个地方。",
            createdAt: now.addingTimeInterval(-60)
        )
        let explicit = MemoryClaimRecord(
            id: "memory-update-explicit", value: "旅行计划要留出休息时间", category: "preference", scope: "user",
            sourceType: "explicit-user-message", sourceID: "old-travel-source", sourceText: "旅行计划要留出休息时间。",
            isInferred: false, isSensitive: false, validFrom: now.addingTimeInterval(-30 * 86_400), updatedAt: now.addingTimeInterval(-86_400)
        )
        let inferred = MemoryClaimRecord(
            id: "memory-update-inferred", value: "旅行时可能喜欢早起", sourceID: "inferred-source", sourceText: "可能喜欢早起。", isInferred: true
        )
        let sensitive = MemoryClaimRecord(
            id: "memory-update-sensitive", value: "旅行时需要携带药物", category: "health", sourceID: "private-source",
            sourceText: "旅行时要带药物。", isSensitive: true
        )
        let expired = MemoryClaimRecord(
            id: "memory-update-expired", value: "旅行只安排室内活动", sourceID: "expired-source",
            sourceText: "旅行只安排室内活动。", validUntil: now.addingTimeInterval(-1)
        )
        let global = MemoryClaimRecord(
            id: "memory-update-global", value: "旅行计划要留出休息时间", scope: "global", sourceID: "global-source",
            sourceText: "旅行计划要留出休息时间。"
        )
        let unrelated = MemoryClaimRecord(
            id: "memory-update-unrelated", value: "在家工作时喜欢安静环境", sourceID: "unrelated-source",
            sourceText: "我在家工作时喜欢安静环境。"
        )
        let memories = [explicit, inferred, sensitive, expired, global, unrelated]
        let prompt = try XCTUnwrap(DreamingReview.promptMessages(for: [source], confirmedMemories: memories, asOf: now).first?.content)
        XCTAssertTrue(prompt.contains(explicit.id))
        for excluded in [inferred.id, sensitive.id, expired.id, global.id, unrelated.id] {
            XCTAssertFalse(prompt.contains(excluded), "Ineligible memory \(excluded) must not enter the model prompt.")
        }

        let response = """
        {"summary":"旅行偏好可能变化。","proposals":[
          {"kind":"memory-update","title":"旅行节奏可能变化","content":"旅行计划可以多安排一两个地方，不必每天留很多休息时间。","rationale":"用户明确说想调整既有旅行偏好。","sourceMessageIDs":["memory-update-source"],"evidence":[{"sourceMessageID":"memory-update-source","quote":"不用每天都留很多休息时间，可以多安排一两个地方"}],"supersedesMemoryClaimID":"memory-update-explicit","confidence":0.84},
          {"kind":"memory-update","title":"更新推断记忆","content":"旅行时喜欢早起。","rationale":"用户这次聊到旅行。","sourceMessageIDs":["memory-update-source"],"evidence":[{"sourceMessageID":"memory-update-source","quote":"我最近想调整旅行计划"}],"supersedesMemoryClaimID":"memory-update-inferred","confidence":0.8},
          {"kind":"memory-update","title":"更新敏感记忆","content":"旅行时不需要携带药物。","rationale":"用户提到旅行计划。","sourceMessageIDs":["memory-update-source"],"evidence":[{"sourceMessageID":"memory-update-source","quote":"我最近想调整旅行计划"}],"supersedesMemoryClaimID":"memory-update-sensitive","confidence":0.8},
          {"kind":"memory-update","title":"更新过期记忆","content":"旅行时可以安排户外活动。","rationale":"用户提到旅行计划。","sourceMessageIDs":["memory-update-source"],"evidence":[{"sourceMessageID":"memory-update-source","quote":"我最近想调整旅行计划"}],"supersedesMemoryClaimID":"memory-update-expired","confidence":0.8},
          {"kind":"memory-update","title":"更新不存在的记忆","content":"旅行计划可以灵活调整。","rationale":"用户提到旅行计划。","sourceMessageIDs":["memory-update-source"],"evidence":[{"sourceMessageID":"memory-update-source","quote":"我最近想调整旅行计划"}],"supersedesMemoryClaimID":"unknown-memory","confidence":0.8},
          {"kind":"memory-update","title":"更新未提供给模型的记忆","content":"在家工作时也喜欢热闹环境。","rationale":"用户谈到旅行计划。","sourceMessageIDs":["memory-update-source"],"evidence":[{"sourceMessageID":"memory-update-source","quote":"我最近想调整旅行计划"}],"supersedesMemoryClaimID":"memory-update-unrelated","confidence":0.8},
          {"kind":"fact","title":"越权指定旧记忆","content":"用户要多安排景点。","rationale":"来源明确。","sourceMessageIDs":["memory-update-source"],"evidence":[{"sourceMessageID":"memory-update-source","quote":"可以多安排一两个地方"}],"supersedesMemoryClaimID":"memory-update-explicit","confidence":0.8}
        ]}
        """
        let parsed = try DreamingReview.parse(
            response, runID: "memory-update-run", allowedSourceMessages: [source], allowedMemoryClaims: memories, now: now
        )
        let proposal = try XCTUnwrap(parsed.proposals.first)
        XCTAssertEqual(parsed.proposals.count, 1)
        XCTAssertEqual(proposal.kind, "memory-update")
        XCTAssertEqual(proposal.supersedesMemoryClaimID, explicit.id)
        XCTAssertEqual(proposal.supersedesMemoryClaimUpdatedAt, explicit.updatedAt)
        XCTAssertEqual(proposal.evidence?.first?.quote, "不用每天都留很多休息时间，可以多安排一两个地方")
        XCTAssertEqual(proposal.evidence?.first?.sourceContentDigest, SourceRecord.digest(source.content))
    }

    func testDreamingGoalStepRequiresAnActiveGoalAndSameConversationUserSource() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let active = GoalRecord(
            id: "active-trip-goal", conversationID: "trip-conversation", title: "恩施旅行", summary: "慢慢准备", status: "进行中",
            steps: [GoalStep(id: "route-step", title: "整理路线"), GoalStep(id: "private-step", title: "记录用药")]
        )
        let paused = GoalRecord(
            id: "paused-study-goal", conversationID: "study-conversation", title: "英语学习", summary: "每周练习", status: "已暂停",
            steps: [GoalStep(title: "选择材料")]
        )
        let tripSource = MessageRecord(id: "trip-source", conversationID: active.conversationID, role: .user, content: "我想先挑两三个轻松的景点。", createdAt: now)
        let foreignSource = MessageRecord(id: "study-source", conversationID: paused.conversationID, role: .user, content: "我想找英语材料。", createdAt: now)
        let response = """
        {"summary":"旅行可以先挑少量景点。","proposals":[
          {"kind":"goal-step","title":"先选两个备选景点","content":"挑出两处想去的景点，再看交通是否顺路。","rationale":"用户在旅行对话中希望先挑少量景点。","sourceMessageIDs":["trip-source"],"evidence":[{"sourceMessageID":"trip-source","quote":"我想先挑两三个轻松的景点。"}],"targetGoalID":"active-trip-goal","confidence":0.82},
          {"kind":"goal-step","title":"串用其他对话","content":"安排英语练习。","rationale":"错误来源。","sourceMessageIDs":["study-source"],"targetGoalID":"active-trip-goal","confidence":0.9},
          {"kind":"goal-step","title":"为暂停目标建议","content":"每天练习十分钟。","rationale":"目标已暂停。","sourceMessageIDs":["study-source"],"targetGoalID":"paused-study-goal","confidence":0.9}
        ]}
        """

        let prompt = try XCTUnwrap(DreamingReview.promptMessages(for: [tripSource, foreignSource], confirmedMemories: [], activeGoals: [active, paused]).first?.content)
        XCTAssertTrue(prompt.contains(active.id))
        XCTAssertFalse(prompt.contains(paused.id))
        XCTAssertFalse(prompt.contains("用药"), "Sensitive unfinished goal steps must not be sent in the dreaming context.")

        let parsed = try DreamingReview.parse(
            response, runID: "goal-step-review", allowedSourceMessages: [tripSource, foreignSource], allowedGoals: [active, paused], now: now
        )
        XCTAssertEqual(parsed.proposals.map(\.targetGoalID), [active.id])
        XCTAssertEqual(parsed.proposals.first?.kind, "goal-step")
    }

    func testGoalStepSuggestionIsNotAppliedUntilAcceptedAndThenAppendsOneRevision() async throws {
        let maintenancePreferencesKey = "openmuse.maintenance.preferences"
        let savedMaintenancePreferences = UserDefaults.standard.object(forKey: maintenancePreferencesKey)
        UserDefaults.standard.removeObject(forKey: maintenancePreferencesKey)
        defer {
            if let savedMaintenancePreferences {
                UserDefaults.standard.set(savedMaintenancePreferences, forKey: maintenancePreferencesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: maintenancePreferencesKey)
            }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseGoalStepReview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceURL = root.appendingPathComponent("workspace", isDirectory: true)
        let store = try SQLiteStore(path: root.appendingPathComponent("OpenMuse.sqlite"))
        let conversation = ConversationRecord(id: "goal-step-conversation", title: "恩施旅行")
        let source = MessageRecord(id: "goal-step-user-message", conversationID: conversation.id, role: .user, content: "先挑几个轻松的景点，之后再看交通。", createdAt: .now.addingTimeInterval(-120))
        let goal = GoalRecord(
            id: "dreaming-travel-goal", conversationID: conversation.id, title: "恩施旅行", summary: "准备一份轻松的旅行计划",
            sourceMessageID: source.id, sourceText: source.content, status: "进行中", steps: [GoalStep(id: "existing-trip-step", title: "确认旅行天数")]
        )
        try store.save(conversation, kind: RecordKind.conversation, id: conversation.id)
        try store.save(source, kind: RecordKind.message, id: source.id)
        try store.save(goal, kind: RecordKind.goal, id: goal.id, appendRevision: true)

        let configuration = ModelConfiguration(provider: .custom, endpoint: "https://goal-step-review.fixture/v1", model: "fixture")
        try SecureStore.saveAPIKey("openmuse-goal-step-test", for: configuration)
        defer { try? SecureStore.deleteAPIKey(for: configuration) }
        let runtime = ScriptedRuntime(response: """
        {"summary":"旅行计划可以先挑少量景点。","proposals":[
          {"kind":"goal-step","title":"挑选少量备选景点","content":"挑出两处想去的景点，再核对交通是否顺路。","rationale":"用户明确提出先挑几个轻松的景点。","sourceMessageIDs":["goal-step-user-message"],"evidence":[{"sourceMessageID":"goal-step-user-message","quote":"先挑几个轻松的景点，之后再看交通。"}],"targetGoalID":"dreaming-travel-goal","confidence":0.87}
        ]}
        """)
        let model = OpenMuseAppModel(runtimeOverride: runtime, workspaceRootOverride: workspaceURL, configurationOverride: configuration, startMacBridge: false)

        await model.runDreamingReview()

        XCTAssertEqual(model.maintenanceProposals.count, 1)
        XCTAssertEqual(model.goals.first?.steps.count, 1, "The model must not mutate a goal before the user accepts the suggestion.")
        let proposal = try XCTUnwrap(model.maintenanceProposals.first)
        XCTAssertEqual(proposal.targetGoalID, goal.id)
        model.reviewMaintenanceProposal(id: proposal.id, accept: true)

        let updatedGoal = try XCTUnwrap(model.goals.first(where: { $0.id == goal.id }))
        XCTAssertEqual(updatedGoal.steps.count, 2)
        XCTAssertEqual(updatedGoal.steps.last?.title, proposal.content)
        XCTAssertEqual(updatedGoal.status, "进行中")
        XCTAssertEqual(model.maintenanceProposals.first?.status, "accepted")
        XCTAssertEqual(model.maintenanceProposals.first?.acceptedRecordID, updatedGoal.steps.last?.id)
        XCTAssertEqual(try store.revisions(GoalRecord.self, kind: RecordKind.goal, objectID: goal.id).count, 2)
        XCTAssertTrue(model.statusText?.contains("没有创建提醒或执行外部操作") == true)

        let replica = try SQLiteStore(path: root.appendingPathComponent("replica.sqlite"))
        try replica.adoptWorkspaceID(store.workspaceID)
        let syncPage = try store.syncEvents(after: [], workspaceID: store.workspaceID)
        _ = try replica.applyRemoteSyncEvents(syncPage.events, workspaceID: store.workspaceID)
        XCTAssertEqual(try replica.load(GoalRecord.self, kind: RecordKind.goal).first(where: { $0.id == goal.id })?.steps.count, 2)
        XCTAssertEqual(try replica.load(MaintenanceProposalRecord.self, kind: RecordKind.maintenanceProposal).first(where: { $0.id == proposal.id })?.status, "accepted")
    }

    func testSensitiveMessagesAndClaimsAreExcludedFromDreaming() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let conversation = ConversationRecord(id: "privacy-review", title: "旅行")
        let safe = MessageRecord(id: "safe-review-message", conversationID: conversation.id, role: .user, content: "我喜欢旅行留一点休息时间。", createdAt: now.addingTimeInterval(-30))
        let sensitive = MessageRecord(id: "sensitive-review-message", conversationID: conversation.id, role: .user, content: "我最近在治疗焦虑，也对花生过敏。", createdAt: now.addingTimeInterval(-20))
        let eligible = DreamingReview.eligibleMessages([safe, sensitive], conversations: [conversation], now: now)

        XCTAssertEqual(eligible.map(\.id), [safe.id])
        let sensitiveMemory = MemoryClaimRecord(
            id: "sensitive-confirmed-memory", value: "我对青霉素过敏", category: "health", sourceID: "old-source", sourceText: "记住我对青霉素过敏", isSensitive: true
        )
        let prompt = try XCTUnwrap(DreamingReview.promptMessages(for: [safe, sensitive], confirmedMemories: [sensitiveMemory]).first?.content)
        XCTAssertTrue(prompt.contains(safe.id))
        XCTAssertFalse(prompt.contains(sensitive.id))
        XCTAssertFalse(prompt.contains("青霉素"))

        let response = """
        {"summary":"近期偏好","proposals":[
          {"kind":"fact","title":"旅行偏好","content":"旅行中喜欢保留休息时间。","rationale":"用户明确表达。","sourceMessageIDs":["safe-review-message"],"evidence":[{"sourceMessageID":"safe-review-message","quote":"我喜欢旅行留一点休息时间。"}],"confidence":0.9},
          {"kind":"fact","title":"健康信息","content":"用户对花生过敏。","rationale":"用户说过。","sourceMessageIDs":["safe-review-message"],"evidence":[{"sourceMessageID":"safe-review-message","quote":"我喜欢旅行留一点休息时间。"}],"confidence":0.9},
          {"kind":"understanding","title":"旅行计划","content":"用户希望旅行计划留白。","rationale":"从对话中理解。","sourceMessageIDs":["sensitive-review-message"],"evidence":[{"sourceMessageID":"sensitive-review-message","quote":"我最近在治疗焦虑，也对花生过敏。"}],"confidence":0.8}
        ]}
        """
        let parsed = try DreamingReview.parse(response, runID: "privacy-run", allowedSourceMessages: [safe, sensitive], now: now)
        XCTAssertEqual(parsed.proposals.map(\.title), ["旅行偏好"])

        let privateOutput = """
        {"summary":"用户对花生过敏，但旅行喜欢慢一点。","proposals":[
          {"kind":"fact","title":"旅行节奏","content":"旅行中喜欢保留休息时间。","rationale":"用户明确表达。","sourceMessageIDs":["safe-review-message"],"evidence":[{"sourceMessageID":"safe-review-message","quote":"我喜欢旅行留一点休息时间。"}],"confidence":0.9},
          {"kind":"fact","title":"过敏信息","content":"用户对花生过敏。","rationale":"用户明确表达。","sourceMessageIDs":["safe-review-message"],"evidence":[{"sourceMessageID":"safe-review-message","quote":"我喜欢旅行留一点休息时间。"}],"confidence":0.9}
        ]}
        """
        let safeOutput = try DreamingReview.parse(privateOutput, runID: "privacy-output-run", allowedSourceMessages: [safe], now: now)
        XCTAssertEqual(safeOutput.summary, "", "A sensitive model summary must not be persisted.")
        XCTAssertEqual(safeOutput.proposals.map(\.title), ["旅行节奏"], "Sensitive proposal fields must be rejected together.")
    }

    func testInputDigestIncludesTheExactSanitizedModelContext() {
        let source = MessageRecord(id: "digest-source", conversationID: "digest-chat", role: .user, content: "我喜欢慢慢旅行。")
        let base = [TranscriptMessage(role: "system", content: DreamingReview.systemPrompt)]
        let first = DreamingReview.inputDigest(messages: [source], context: base + [TranscriptMessage(role: "user", content: "已确认记忆：[]")])
        let changed = DreamingReview.inputDigest(messages: [source], context: base + [TranscriptMessage(role: "user", content: "已确认记忆：[旅行偏好]")])
        XCTAssertEqual(first.count, 64)
        XCTAssertNotEqual(first, changed, "The digest must change when the actual prompt context changes.")
        XCTAssertFalse(first.contains("旅行"), "Only a digest, not prompt content, is stored in the run record.")
    }

    func testModelReviewPersistsProposalsAndOnlyAppliesAfterUserDecision() async throws {
        let maintenancePreferencesKey = "openmuse.maintenance.preferences"
        let savedMaintenancePreferences = UserDefaults.standard.object(forKey: maintenancePreferencesKey)
        UserDefaults.standard.removeObject(forKey: maintenancePreferencesKey)
        defer {
            if let savedMaintenancePreferences {
                UserDefaults.standard.set(savedMaintenancePreferences, forKey: maintenancePreferencesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: maintenancePreferencesKey)
            }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseDreaming-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceURL = root.appendingPathComponent("workspace", isDirectory: true)
        let store = try SQLiteStore(path: root.appendingPathComponent("OpenMuse.sqlite"))
        let conversation = ConversationRecord(id: "dreaming-conversation", title: "旅行想法")
        let first = MessageRecord(id: "dreaming-source-one", conversationID: conversation.id, role: .user, content: "我喜欢旅行别排太满，想留点休息时间。", createdAt: .now.addingTimeInterval(-400))
        let second = MessageRecord(id: "dreaming-source-two", conversationID: conversation.id, role: .user, content: "下次规划时也先给我一个轻松版。", createdAt: .now.addingTimeInterval(-200))
        try store.save(conversation, kind: RecordKind.conversation, id: conversation.id)
        try store.save(first, kind: RecordKind.message, id: first.id)
        try store.save(second, kind: RecordKind.message, id: second.id)

        let config = ModelConfiguration(provider: .custom, endpoint: "https://dreaming-fixture.example/v1", model: "fixture")
        try SecureStore.saveAPIKey("openmuse-dreaming-test", for: config)
        defer { try? SecureStore.deleteAPIKey(for: config) }
        let runtime = ScriptedRuntime(response: """
        {"summary":"用户希望旅行节奏松一些，并偏好先看到轻松方案。","proposals":[
          {"kind":"fact","title":"旅行节奏偏好","content":"旅行计划应留出休息时间，不要排得太满。","rationale":"用户在两条近期消息中都明确提到旅行节奏。","sourceMessageIDs":["dreaming-source-one","dreaming-source-two"],"evidence":[{"sourceMessageID":"dreaming-source-one","quote":"我喜欢旅行别排太满，想留点休息时间。"},{"sourceMessageID":"dreaming-source-two","quote":"下次规划时也先给我一个轻松版。"}],"confidence":0.91},
          {"kind":"collaboration-habit","title":"先给轻松方案","content":"规划旅行时先提供节奏轻松的版本，并说明仍待确认的安排。","rationale":"用户明确要求先看到轻松版。","sourceMessageIDs":["dreaming-source-two"],"evidence":[{"sourceMessageID":"dreaming-source-two","quote":"下次规划时也先给我一个轻松版。"}],"confidence":0.86}
        ]}
        """)
        let model = OpenMuseAppModel(runtimeOverride: runtime, workspaceRootOverride: workspaceURL, configurationOverride: config, startMacBridge: false)

        XCTAssertFalse(model.isRunningMaintenance, "A new model must not begin an automatic review before the test requests one.")
        await model.runDreamingReview()

        XCTAssertNotNil(model.maintenanceStatus, "A review attempt must expose its result or the reason it stopped.")
        XCTAssertEqual(model.maintenanceRuns.first?.status, "completed", "Review status: \(model.maintenanceStatus ?? "<nil>")")
        XCTAssertEqual(model.maintenanceRuns.first?.sourceMessageIDs.count, 2)
        XCTAssertEqual(model.maintenanceProposals.count, 2)
        XCTAssertTrue(model.maintenanceProposals.allSatisfy { $0.evidence?.count == $0.sourceMessageIDs.count })
        XCTAssertTrue(model.memoryClaims.isEmpty, "A model review must not apply memory changes automatically.")
        XCTAssertEqual(try store.pendingSyncEvents().filter { $0.kind == RecordKind.maintenanceProposal }.count, 2)

        let fact = try XCTUnwrap(model.maintenanceProposals.first(where: { $0.kind == "fact" }))
        model.reviewMaintenanceProposal(id: fact.id, accept: true)
        XCTAssertEqual(model.memoryClaims.first?.sourceType, "dreaming-approved")
        let acceptedClaim = try XCTUnwrap(model.memoryClaims.first)
        XCTAssertEqual(model.sources.first(where: { $0.id == acceptedClaim.sourceRecordID })?.sourceType, "conversation-message")
        XCTAssertTrue(try XCTUnwrap(model.documents.first(where: { $0.path == "USER.md" })).content.contains("不要排得太满"))

        let habit = try XCTUnwrap(model.maintenanceProposals.first(where: { $0.kind == "collaboration-habit" }))
        model.reviewMaintenanceProposal(id: habit.id, accept: true)
        XCTAssertTrue(try XCTUnwrap(model.documents.first(where: { $0.path == "SOUL.md" })).content.contains("先提供节奏轻松的版本"))
        XCTAssertEqual(model.maintenanceProposals.first(where: { $0.id == habit.id })?.status, "accepted")

        await model.runDreamingReview()
        XCTAssertTrue(model.maintenanceStatus?.contains("已经完成") == true)

        let reopened = OpenMuseAppModel(runtimeOverride: runtime, workspaceRootOverride: workspaceURL, configurationOverride: config, startMacBridge: false)
        XCTAssertEqual(reopened.maintenanceRuns.first?.status, "completed")
        XCTAssertEqual(Set(reopened.maintenanceProposals.map(\.status)), ["accepted"])
        XCTAssertEqual(reopened.memoryClaims.first?.category, "fact")
        XCTAssertTrue(reopened.maintenanceProposals.allSatisfy { $0.evidence?.count == $0.sourceMessageIDs.count })
        XCTAssertTrue(reopened.documents.first(where: { $0.path == "SOUL.md" })?.content.contains("先提供节奏轻松的版本") == true)
    }

    func testDreamingRejectsResponsesThatRepeatInternalPromptMarkers() async throws {
        let preferencesKey = "openmuse.maintenance.preferences"
        let savedPreferences = UserDefaults.standard.object(forKey: preferencesKey)
        UserDefaults.standard.removeObject(forKey: preferencesKey)
        defer {
            if let savedPreferences {
                UserDefaults.standard.set(savedPreferences, forKey: preferencesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: preferencesKey)
            }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseDreamingLeak-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceURL = root.appendingPathComponent("workspace", isDirectory: true)
        let store = try SQLiteStore(path: root.appendingPathComponent("OpenMuse.sqlite"))
        let conversation = ConversationRecord(id: "dreaming-leak-conversation", title: "天气")
        let message = MessageRecord(
            id: "dreaming-leak-source",
            conversationID: conversation.id,
            role: .user,
            content: "帮我看看广州明天的天气。",
            createdAt: .now.addingTimeInterval(-60)
        )
        try store.save(conversation, kind: RecordKind.conversation, id: conversation.id)
        try store.save(message, kind: RecordKind.message, id: message.id)

        let configuration = ModelConfiguration(provider: .custom, endpoint: "https://dreaming-leak-fixture.example/v1", model: "fixture")
        try SecureStore.saveAPIKey("openmuse-dreaming-leak-test", for: configuration)
        defer { try? SecureStore.deleteAPIKey(for: configuration) }
        let runtime = ScriptedRuntime(response: #"{"summary":"<openmuse-reference-data>","proposals":[]}"#)
        let model = OpenMuseAppModel(
            runtimeOverride: runtime,
            workspaceRootOverride: workspaceURL,
            configurationOverride: configuration,
            startMacBridge: false
        )

        await model.runDreamingReview()

        XCTAssertEqual(model.maintenanceRuns.first?.status, "failed")
        XCTAssertEqual(model.maintenanceRuns.first?.failureMessage, ModelRuntimeError.internalContextLeak.localizedDescription)
        XCTAssertTrue(model.maintenanceProposals.isEmpty)
        XCTAssertTrue(model.memoryClaims.isEmpty)
        XCTAssertFalse(model.maintenanceStatus?.contains("<openmuse-reference-data>") == true)
    }

    func testProposalBecomesStaleWhenItsQuotedSourceChangesBeforeAcceptance() async throws {
        let maintenancePreferencesKey = "openmuse.maintenance.preferences"
        let savedMaintenancePreferences = UserDefaults.standard.object(forKey: maintenancePreferencesKey)
        UserDefaults.standard.removeObject(forKey: maintenancePreferencesKey)
        defer {
            if let savedMaintenancePreferences {
                UserDefaults.standard.set(savedMaintenancePreferences, forKey: maintenancePreferencesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: maintenancePreferencesKey)
            }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseDreamingEvidenceStale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(path: root.appendingPathComponent("OpenMuse.sqlite"))
        let workspaceURL = root.appendingPathComponent("workspace", isDirectory: true)
        let conversation = ConversationRecord(id: "evidence-stale-chat", title: "旅行")
        let source = MessageRecord(id: "evidence-stale-source", conversationID: conversation.id, role: .user, content: "我喜欢旅行保留休息时间。", createdAt: .now.addingTimeInterval(-60))
        try store.save(conversation, kind: RecordKind.conversation, id: conversation.id)
        try store.save(source, kind: RecordKind.message, id: source.id)

        let config = ModelConfiguration(provider: .custom, endpoint: "https://dreaming-evidence-stale.fixture/v1", model: "fixture")
        try SecureStore.saveAPIKey("openmuse-dreaming-evidence-stale-test", for: config)
        defer { try? SecureStore.deleteAPIKey(for: config) }
        let runtime = ScriptedRuntime(response: """
        {"summary":"用户旅行时喜欢留出休息时间。","proposals":[
          {"kind":"fact","title":"旅行节奏","content":"旅行计划应留出休息时间。","rationale":"用户明确提到旅行时要保留休息时间。","sourceMessageIDs":["evidence-stale-source"],"evidence":[{"sourceMessageID":"evidence-stale-source","quote":"我喜欢旅行保留休息时间。"}],"confidence":0.9}
        ]}
        """)
        let model = OpenMuseAppModel(runtimeOverride: runtime, workspaceRootOverride: workspaceURL, configurationOverride: config, startMacBridge: false)
        await model.runDreamingReview()
        let proposal = try XCTUnwrap(model.maintenanceProposals.first)

        var editedSource = source
        editedSource.content += " 之后我又补充：这周想多走几个地方。"
        try store.save(editedSource, kind: RecordKind.message, id: editedSource.id, appendRevision: true)
        model.reviewMaintenanceProposal(id: proposal.id, accept: true)

        XCTAssertEqual(model.maintenanceProposals.first?.status, "stale")
        XCTAssertTrue(model.memoryClaims.isEmpty, "Changed source text must invalidate the proposal instead of writing a claim.")
        XCTAssertTrue(model.statusText?.contains("原话依据已变化") == true)
    }

    func testAcceptedMemoryUpdatePreservesOldClaimAndRebuildsCurrentUserProjection() async throws {
        let preferencesKey = "openmuse.maintenance.preferences"
        let savedPreferences = UserDefaults.standard.object(forKey: preferencesKey)
        UserDefaults.standard.removeObject(forKey: preferencesKey)
        defer {
            if let savedPreferences { UserDefaults.standard.set(savedPreferences, forKey: preferencesKey) }
            else { UserDefaults.standard.removeObject(forKey: preferencesKey) }
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseMemoryUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceURL = root.appendingPathComponent("workspace", isDirectory: true)
        let store = try SQLiteStore(path: root.appendingPathComponent("OpenMuse.sqlite"))
        let conversation = ConversationRecord(id: "memory-update-conversation", title: "旅行计划")
        let oldSource = MessageRecord(
            id: "memory-update-old-source", conversationID: conversation.id, role: .user,
            content: "旅行计划要留出足够休息时间。", createdAt: .now.addingTimeInterval(-30 * 86_400)
        )
        let recentSource = MessageRecord(
            id: "memory-update-recent-source", conversationID: conversation.id, role: .user,
            content: "我最近想调整旅行计划，不用每天都留很多休息时间，可以多安排一两个地方。",
            createdAt: .now.addingTimeInterval(-60)
        )
        let oldClaim = MemoryClaimRecord(
            id: "memory-update-old-claim", value: "旅行计划要留出足够休息时间", category: "preference", scope: "user",
            sourceType: "explicit-user-message", sourceID: oldSource.id, sourceText: oldSource.content,
            isInferred: false, isSensitive: false, validFrom: oldSource.createdAt,
            createdAt: oldSource.createdAt, updatedAt: oldSource.createdAt
        )
        try store.save(conversation, kind: RecordKind.conversation, id: conversation.id)
        try store.save(oldSource, kind: RecordKind.message, id: oldSource.id)
        try store.save(recentSource, kind: RecordKind.message, id: recentSource.id)
        try store.save(oldClaim, kind: RecordKind.memoryClaim, id: oldClaim.id, appendRevision: true)

        let configuration = ModelConfiguration(provider: .custom, endpoint: "https://memory-update.fixture/v1", model: "fixture")
        try SecureStore.saveAPIKey("openmuse-memory-update-test", for: configuration)
        defer { try? SecureStore.deleteAPIKey(for: configuration) }
        let runtime = ScriptedRuntime(response: """
        {"summary":"旅行节奏偏好可能发生变化。","proposals":[
          {"kind":"memory-update","title":"旅行节奏偏好可能变化","content":"旅行计划可以多安排一两个地方，不必每天留很多休息时间。","rationale":"用户明确说想调整既有旅行计划。","sourceMessageIDs":["memory-update-recent-source"],"evidence":[{"sourceMessageID":"memory-update-recent-source","quote":"不用每天都留很多休息时间，可以多安排一两个地方"}],"supersedesMemoryClaimID":"memory-update-old-claim","confidence":0.86}
        ]}
        """)
        let model = OpenMuseAppModel(
            runtimeOverride: runtime, workspaceRootOverride: workspaceURL,
            configurationOverride: configuration, startMacBridge: false
        )

        XCTAssertTrue(try XCTUnwrap(model.documents.first(where: { $0.path == "USER.md" })).content.contains(oldClaim.value))
        await model.runDreamingReview()

        let proposal = try XCTUnwrap(model.maintenanceProposals.first)
        XCTAssertEqual(proposal.kind, "memory-update")
        XCTAssertEqual(proposal.status, "pending")
        XCTAssertEqual(model.memoryClaims.first(where: { $0.id == oldClaim.id })?.status, "active")
        XCTAssertEqual(try store.load(MemoryClaimRecord.self, kind: RecordKind.memoryClaim).count, 1, "The review must not update memory before acceptance.")

        model.reviewMaintenanceProposal(id: proposal.id, accept: true)

        let persistedClaims = try store.load(MemoryClaimRecord.self, kind: RecordKind.memoryClaim)
        let superseded = try XCTUnwrap(persistedClaims.first(where: { $0.id == oldClaim.id }))
        let updated = try XCTUnwrap(persistedClaims.first(where: { $0.sourceType == "dreaming-approved-update" }))
        let acceptedProposal = try XCTUnwrap(try store.load(MaintenanceProposalRecord.self, kind: RecordKind.maintenanceProposal).first)
        XCTAssertEqual(superseded.status, "superseded")
        XCTAssertEqual(superseded.supersededByClaimID, updated.id)
        XCTAssertEqual(superseded.validUntil, recentSource.createdAt)
        XCTAssertEqual(updated.status, "active")
        XCTAssertEqual(updated.sourceType, "dreaming-approved-update")
        XCTAssertEqual(updated.sourceID, recentSource.id)
        XCTAssertEqual(updated.sourceText, recentSource.content)
        XCTAssertEqual(updated.validFrom, recentSource.createdAt)
        XCTAssertTrue(updated.isInferred == true, "The model's paraphrase remains labeled as inferred even after its source is reviewed.")
        XCTAssertEqual(try store.revisions(MemoryClaimRecord.self, kind: RecordKind.memoryClaim, objectID: oldClaim.id).count, 2)
        XCTAssertEqual(try store.revisions(MemoryClaimRecord.self, kind: RecordKind.memoryClaim, objectID: updated.id).count, 1)
        XCTAssertEqual(acceptedProposal.status, "accepted")
        XCTAssertEqual(acceptedProposal.acceptedRecordID, updated.id)
        XCTAssertEqual(try store.load(SourceRecord.self, kind: RecordKind.source).first?.externalID, recentSource.id)
        let userProjection = try XCTUnwrap(model.documents.first(where: { $0.path == "USER.md" })).content
        XCTAssertTrue(userProjection.contains(updated.value))
        XCTAssertFalse(userProjection.contains(oldClaim.value), "The current USER.md projection must not retain the superseded value.")

        let reopenedStore = try SQLiteStore(path: root.appendingPathComponent("OpenMuse.sqlite"))
        XCTAssertEqual(reopenedStore.workspaceID, store.workspaceID)
        XCTAssertEqual(try reopenedStore.load(MemoryClaimRecord.self, kind: RecordKind.memoryClaim).count, 2)
        XCTAssertEqual(try reopenedStore.load(MemoryClaimRecord.self, kind: RecordKind.memoryClaim).first(where: { $0.id == oldClaim.id })?.status, "superseded")
        XCTAssertEqual(try reopenedStore.load(MaintenanceProposalRecord.self, kind: RecordKind.maintenanceProposal).first?.acceptedRecordID, updated.id)
    }

    func testMemoryUpdateBecomesStaleIfTargetClaimChangesAfterReview() async throws {
        let preferencesKey = "openmuse.maintenance.preferences"
        let savedPreferences = UserDefaults.standard.object(forKey: preferencesKey)
        UserDefaults.standard.removeObject(forKey: preferencesKey)
        defer {
            if let savedPreferences { UserDefaults.standard.set(savedPreferences, forKey: preferencesKey) }
            else { UserDefaults.standard.removeObject(forKey: preferencesKey) }
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseMemoryUpdateStale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceURL = root.appendingPathComponent("workspace", isDirectory: true)
        let store = try SQLiteStore(path: root.appendingPathComponent("OpenMuse.sqlite"))
        let conversation = ConversationRecord(id: "memory-update-stale-conversation", title: "旅行计划")
        let recentSource = MessageRecord(
            id: "memory-update-stale-source", conversationID: conversation.id, role: .user,
            content: "我最近想调整旅行计划，不用每天都留很多休息时间，可以多安排一两个地方。",
            createdAt: .now.addingTimeInterval(-60)
        )
        let oldClaim = MemoryClaimRecord(
            id: "memory-update-stale-claim", value: "旅行计划要留出足够休息时间", category: "preference", scope: "user",
            sourceType: "explicit-user-message", sourceID: "old-travel-source", sourceText: "旅行计划要留出足够休息时间。",
            isInferred: false, isSensitive: false, validFrom: .now.addingTimeInterval(-30 * 86_400),
            createdAt: .now.addingTimeInterval(-30 * 86_400), updatedAt: .now.addingTimeInterval(-30 * 86_400)
        )
        try store.save(conversation, kind: RecordKind.conversation, id: conversation.id)
        try store.save(recentSource, kind: RecordKind.message, id: recentSource.id)
        try store.save(oldClaim, kind: RecordKind.memoryClaim, id: oldClaim.id, appendRevision: true)

        let configuration = ModelConfiguration(provider: .custom, endpoint: "https://memory-update-stale.fixture/v1", model: "fixture")
        try SecureStore.saveAPIKey("openmuse-memory-update-stale-test", for: configuration)
        defer { try? SecureStore.deleteAPIKey(for: configuration) }
        let runtime = ScriptedRuntime(response: """
        {"summary":"旅行节奏偏好可能发生变化。","proposals":[
          {"kind":"memory-update","title":"旅行节奏偏好可能变化","content":"旅行计划可以多安排一两个地方，不必每天留很多休息时间。","rationale":"用户明确说想调整既有旅行计划。","sourceMessageIDs":["memory-update-stale-source"],"evidence":[{"sourceMessageID":"memory-update-stale-source","quote":"不用每天都留很多休息时间，可以多安排一两个地方"}],"supersedesMemoryClaimID":"memory-update-stale-claim","confidence":0.86}
        ]}
        """)
        let model = OpenMuseAppModel(
            runtimeOverride: runtime, workspaceRootOverride: workspaceURL,
            configurationOverride: configuration, startMacBridge: false
        )
        await model.runDreamingReview()
        let proposal = try XCTUnwrap(model.maintenanceProposals.first)

        var concurrentlyUpdated = oldClaim
        concurrentlyUpdated.value = "旅行计划要多安排景点，不再坚持留出休息时间"
        concurrentlyUpdated.updatedAt = .now.addingTimeInterval(1)
        try store.save(concurrentlyUpdated, kind: RecordKind.memoryClaim, id: concurrentlyUpdated.id, appendRevision: true)
        model.reviewMaintenanceProposal(id: proposal.id, accept: true)

        XCTAssertEqual(model.maintenanceProposals.first?.status, "stale")
        let persistedClaims = try store.load(MemoryClaimRecord.self, kind: RecordKind.memoryClaim)
        XCTAssertEqual(persistedClaims.count, 1)
        XCTAssertEqual(persistedClaims.first?.value, concurrentlyUpdated.value)
        XCTAssertEqual(persistedClaims.first?.status, "active")
        XCTAssertTrue(model.statusText?.contains("旧记忆、来源或原话依据已变化") == true)
    }

    func testAutomaticReviewRequiresOptInAndHonorsQuietHours() throws {
        let calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var utc = calendar
        utc.timeZone = timeZone
        let date = utc.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 23))!
        XCTAssertFalse(MaintenancePreferences(enabled: false).allowsRun(at: date, calendar: utc))
        XCTAssertFalse(MaintenancePreferences(enabled: true, quietHoursStart: 22, quietHoursEnd: 8).allowsRun(at: date, calendar: utc))
        XCTAssertTrue(MaintenancePreferences(enabled: true, quietHoursStart: 22, quietHoursEnd: 8).allowsRun(at: date.addingTimeInterval(10 * 60 * 60), calendar: utc))
        XCTAssertNil(MaintenancePreferences(enabled: false).nextBackgroundOpportunity(after: date, calendar: utc))
        XCTAssertEqual(
            MaintenancePreferences(enabled: true, quietHoursStart: 22, quietHoursEnd: 8).nextBackgroundOpportunity(after: date, calendar: utc),
            utc.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 8))
        )
        let earlyMorning = utc.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 2))!
        XCTAssertEqual(
            MaintenancePreferences(enabled: true, quietHoursStart: 22, quietHoursEnd: 8).nextBackgroundOpportunity(after: earlyMorning, calendar: utc),
            utc.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 8))
        )
    }

    func testReviewTokenBudgetStopsBeforeCallingTheModel() async throws {
        let maintenancePreferencesKey = "openmuse.maintenance.preferences"
        let savedMaintenancePreferences = UserDefaults.standard.object(forKey: maintenancePreferencesKey)
        UserDefaults.standard.removeObject(forKey: maintenancePreferencesKey)
        defer {
            if let savedMaintenancePreferences {
                UserDefaults.standard.set(savedMaintenancePreferences, forKey: maintenancePreferencesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: maintenancePreferencesKey)
            }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseDreamingBudget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(path: root.appendingPathComponent("OpenMuse.sqlite"))
        let conversation = ConversationRecord(id: "budget-conversation", title: "旅行")
        let source = MessageRecord(id: "budget-source", conversationID: conversation.id, role: .user, content: "我想慢慢安排一趟旅行。", createdAt: .now.addingTimeInterval(-60))
        try store.save(conversation, kind: RecordKind.conversation, id: conversation.id)
        try store.save(source, kind: RecordKind.message, id: source.id)
        let configuration = ModelConfiguration(provider: .custom, endpoint: "https://budget-fixture.example/v1", model: "fixture")
        try SecureStore.saveAPIKey("openmuse-budget-test", for: configuration)
        defer { try? SecureStore.deleteAPIKey(for: configuration) }
        let counter = ReviewRequestCounter()
        let model = OpenMuseAppModel(
            runtimeOverride: CountingReviewRuntime(counter: counter),
            workspaceRootOverride: root.appendingPathComponent("workspace", isDirectory: true),
            configurationOverride: configuration,
            startMacBridge: false
        )
        model.setMaintenanceBudget(tokensPerDay: 512, outputTokensPerRun: 4_096)

        await model.runDreamingReview()

        let requestCount = await counter.count()
        XCTAssertEqual(requestCount, 0)
        XCTAssertTrue(model.maintenanceStatus?.contains("超过 HEARTBEAT") == true)
        XCTAssertTrue(model.maintenanceRuns.isEmpty)
    }

    func testReviewRecordsAreOmittedFromArchiveWithoutChats() throws {
        let run = MaintenanceRunRecord(
            id: "run-private", sourceMessageIDs: ["message-private"], inputDigest: String(repeating: "a", count: 64),
            summary: "回顾完成", reflection: "我会先给旅行方案留出更多休息时间。",
            reflectionEvidence: [MaintenanceEvidence(sourceMessageID: "message-private", quote: "旅行不要排太满。")],
            provider: "DeepSeek", model: "deepseek-chat"
        )
        let proposal = MaintenanceProposalRecord(id: "proposal-private", runID: run.id, kind: "understanding", title: "假设", content: "内容", rationale: "原因", sourceMessageIDs: ["message-private"], confidence: 0.5)
        let encoder = JSONEncoder()
        let snapshot = WorkspaceStoreSnapshot(
            records: [
                WorkspaceRecordSnapshot(kind: RecordKind.maintenanceRun, recordID: run.id, revision: 1, payload: try encoder.encode(run), createdAt: run.startedAt, updatedAt: run.startedAt),
                WorkspaceRecordSnapshot(kind: RecordKind.maintenanceProposal, recordID: proposal.id, revision: 1, payload: try encoder.encode(proposal), createdAt: proposal.createdAt, updatedAt: proposal.updatedAt)
            ],
            revisions: [], conflicts: []
        )
        let archive = try WorkspaceArchive.make(from: snapshot, includeConversations: false)
        XCTAssertTrue(archive.payload.records.isEmpty)
        XCTAssertTrue(archive.manifest.omittedKinds.contains(RecordKind.maintenanceProposal))
        XCTAssertTrue(archive.manifest.omittedKinds.contains(RecordKind.maintenanceRun))
        let fullArchive = try WorkspaceArchive.make(from: snapshot, includeConversations: true)
        let archivedRun = try XCTUnwrap(fullArchive.payload.records.first(where: { $0.recordID == run.id }))
        let decodedRun = try JSONDecoder().decode(MaintenanceRunRecord.self, from: archivedRun.payload)
        XCTAssertEqual(decodedRun.reflection, run.reflection)
        XCTAssertEqual(decodedRun.reflectionEvidence, run.reflectionEvidence)
    }

    func testForgettingApprovedMemoryAtomicallyDeletesItsDerivedReview() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMuseDreamingForget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceURL = root.appendingPathComponent("workspace", isDirectory: true)
        let store = try SQLiteStore(path: root.appendingPathComponent("OpenMuse.sqlite"))
        let conversation = ConversationRecord(id: "forget-conversation", title: "记忆来源")
        let source = MessageRecord(id: "forget-source-message", conversationID: conversation.id, role: .user, content: "我更喜欢慢节奏旅行。")
        let claim = MemoryClaimRecord(id: "forget-dream-claim", value: "更喜欢慢节奏旅行", sourceType: "dreaming-approved", sourceID: source.id, sourceText: source.content, isInferred: true)
        let run = MaintenanceRunRecord(
            id: "forget-dream-run", status: "completed", sourceMessageIDs: [source.id],
            inputDigest: String(repeating: "b", count: 64), summary: "回顾完成",
            reflection: "我会优先安排慢节奏旅行。",
            reflectionEvidence: [MaintenanceEvidence(sourceMessageID: source.id, quote: source.content)],
            provider: "DeepSeek", model: "deepseek-chat", finishedAt: .now
        )
        let proposal = MaintenanceProposalRecord(id: "forget-dream-proposal", runID: run.id, kind: "fact", title: "旅行节奏", content: claim.value, rationale: "用户有明确表达。", sourceMessageIDs: [source.id], confidence: 0.9, status: "accepted", acceptedRecordID: claim.id)
        try store.save(conversation, kind: RecordKind.conversation, id: conversation.id)
        try store.save(source, kind: RecordKind.message, id: source.id)
        try store.save(claim, kind: RecordKind.memoryClaim, id: claim.id, appendRevision: true)
        try store.save(run, kind: RecordKind.maintenanceRun, id: run.id, appendRevision: true)
        try store.save(proposal, kind: RecordKind.maintenanceProposal, id: proposal.id, appendRevision: true)
        let model = OpenMuseAppModel(runtimeOverride: ScriptedRuntime(response: "{}"), workspaceRootOverride: workspaceURL, configurationOverride: ModelConfiguration(), startMacBridge: false)

        model.forgetMemoryClaim(id: claim.id)

        XCTAssertTrue(try store.load(MemoryClaimRecord.self, kind: RecordKind.memoryClaim).isEmpty)
        XCTAssertTrue(try store.load(MaintenanceRunRecord.self, kind: RecordKind.maintenanceRun).isEmpty)
        XCTAssertTrue(try store.load(MaintenanceProposalRecord.self, kind: RecordKind.maintenanceProposal).isEmpty)
        let tombstones = try store.load(DeletionTombstoneRecord.self, kind: RecordKind.deletionTombstone)
        XCTAssertEqual(Set(tombstones.map(\.recordKind)), [RecordKind.memoryClaim, RecordKind.maintenanceRun, RecordKind.maintenanceProposal])
        let userFile = try XCTUnwrap(try WorkspaceFiles(store: store, rootURL: workspaceURL).document(path: "USER.md"))
        XCTAssertFalse(userFile.content.contains(claim.value))
        let pendingSyncPayload = String(decoding: try JSONEncoder().encode(store.pendingSyncEvents()), as: UTF8.self)
        XCTAssertFalse(pendingSyncPayload.contains(claim.value))
        XCTAssertFalse(pendingSyncPayload.contains("我会优先安排慢节奏旅行。"))
    }
}

private actor ReviewRequestCounter {
    private var value = 0
    func increment() { value += 1 }
    func count() -> Int { value }
}

private struct CountingReviewRuntime: ModelRuntime {
    let counter: ReviewRequestCounter

    func reply(systemPrompt: String, messages: [TranscriptMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        await counter.increment()
        return #"{"summary":"done","proposals":[]}"#
    }
}

private struct ScriptedRuntime: ModelRuntime {
    let response: String

    func reply(systemPrompt: String, messages: [TranscriptMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        XCTAssertTrue(systemPrompt.contains("不得调用工具"))
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.role, "user")
        return response
    }
}
