import Foundation

struct TravelArtifactDraft: Equatable {
    let dayCount: Int
    let expectedDayCount: Int?
    let coversRequestedDays: Bool
    let assumptions: [String]
}

enum TravelArtifactDraftValidator {
    private static let dayHeadingRegex = try! NSRegularExpression(
        pattern: #"(?im)^[ \t]*(?:>[ \t]*)?(?:#{1,6}[ \t]*)?(?:(?:[-*+•][ \t]*)|(?:[0-9]+[.)、][ \t]*))?(?:\*\*|__)?(?:第[ \t]*([0-9]+|[一二三四五六七八九十]+)[ \t]*天|day[ \t]*([0-9]+)|d[ \t]*([0-9]+))(?=(?:\*\*|__)?(?:$|[ \t]*[:：、.\-—–]|[ \t]+))"#
    )
    private static let assumptionRegex = try! NSRegularExpression(
        pattern: "(?im)^[ \\t]*(?:[-*][ \\t]*)?(?:假设|暂按|暂定|待确认|尚待确认)[：:]?[ \\t]*(.+)$"
    )
    private static let requestedDayCountRegex = try! NSRegularExpression(
        pattern: "(?i)(?<!第)([0-9]{1,2}|[一二三四五六七八九十]+)[ \\t]*(?:天|日|[- ]day)"
    )

    static func parse(_ content: String, expectedDayCount: Int? = nil) -> TravelArtifactDraft? {
        let fullRange = NSRange(content.startIndex..<content.endIndex, in: content)
        let headings = dayHeadingRegex.matches(in: content, range: fullRange)
        let dayIDs = Set(headings.compactMap { match -> String? in
            for group in 1..<match.numberOfRanges {
                let range = match.range(at: group)
                guard range.location != NSNotFound, let swiftRange = Range(range, in: content) else { continue }
                return normalizedDayNumber(String(content[swiftRange]))
            }
            return nil
        })
        guard dayIDs.count >= 2 else { return nil }
        let dayNumbers = Set(dayIDs.compactMap(Int.init))
        let coveredDayNumbers: Set<Int>
        if let expectedDayCount, expectedDayCount > 0 {
            coveredDayNumbers = dayNumbers.intersection(Set(1...expectedDayCount))
        } else {
            coveredDayNumbers = []
        }
        let coveredDayCount = expectedDayCount == nil ? dayIDs.count : coveredDayNumbers.count

        let assumptions = assumptionRegex.matches(in: content, range: fullRange).compactMap { match -> String? in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: content) else { return nil }
            let value = String(content[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        var uniqueAssumptions: [String] = []
        for assumption in assumptions where !uniqueAssumptions.contains(assumption) {
            uniqueAssumptions.append(assumption)
        }
        return TravelArtifactDraft(
            dayCount: coveredDayCount,
            expectedDayCount: expectedDayCount,
            coversRequestedDays: expectedDayCount.map { count in
                count > 0 && coveredDayNumbers.count == count
            } ?? true,
            assumptions: uniqueAssumptions
        )
    }

    static func expectedDayCount(in text: String) -> Int? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = requestedDayCountRegex.matches(in: text, range: range)
        for match in matches.reversed() {
            guard let valueRange = Range(match.range(at: 1), in: text) else { continue }
            if let result = Int(String(text[valueRange])) ?? chineseNumber(String(text[valueRange])) { return result }
        }
        return nil
    }

    private static func normalizedDayNumber(_ raw: String) -> String {
        String(Int(raw) ?? chineseNumber(raw) ?? 0)
    }

    private static func chineseNumber(_ value: String) -> Int? {
        let digits: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        guard !value.isEmpty else { return nil }
        if value == "十" { return 10 }
        guard let tenIndex = value.firstIndex(of: "十") else {
            return value.count == 1 ? value.first.flatMap { digits[$0] } : nil
        }
        let leading = value[..<tenIndex].first.flatMap { digits[$0] } ?? 1
        let afterTen = value.index(after: tenIndex)
        let trailing = afterTen < value.endIndex ? (digits[value[afterTen]] ?? 0) : 0
        return leading * 10 + trailing
    }
}

struct TravelPlanArtifactUpdate: Equatable {
    let artifact: ArtifactRecord
    let draft: TravelArtifactDraft
    let addedAlternative: Bool
    let completesGoalPlan: Bool
}

enum TravelPlanArtifactUpdater {
    static let maximumVariants = 12
    static let maximumVariantContentBytes = 2_000_000

    static func update(
        response: String,
        userRequest: String,
        goalTitleAndSummary: String,
        existing: ArtifactRecord?,
        conversationID: String,
        goalID: String,
        sourceMessageIDs: [String],
        now: Date = .now
    ) -> TravelPlanArtifactUpdate? {
        let goalDayCount = TravelArtifactDraftValidator.expectedDayCount(in: goalTitleAndSummary)
        let requestDayCount = TravelArtifactDraftValidator.expectedDayCount(in: userRequest)
        let existingVariants = existing?.travelPlanVariants ?? []
        let currentVariant: TravelPlanVariantRecord?
        if let existing {
            currentVariant = selectedCurrentVariant(for: existing, variants: existingVariants)
        } else {
            currentVariant = nil
        }
        let expectedDayCount = requestDayCount ?? currentVariant?.expectedDayCount ?? goalDayCount
        guard response.utf8.count <= maximumVariantContentBytes,
              let draft = TravelArtifactDraftValidator.parse(response, expectedDayCount: expectedDayCount) else { return nil }

        var variants = existingVariants
        let existingCurrentIndex: Int?
        if let existing {
            existingCurrentIndex = ensureCurrentVariant(
                for: existing, in: &variants, sourceMessageIDs: existing.sourceMessageIDs ?? [], now: now
            )
            guard variants.count <= maximumVariants,
                  variants.allSatisfy({ $0.content.utf8.count <= maximumVariantContentBytes }) else { return nil }
        } else {
            existingCurrentIndex = nil
        }

        let wantsAlternative = existing != nil && containsAlternativeIntent(userRequest)
        let activePlanIsAlternative = existing != nil
            && currentVariant?.expectedDayCount != nil
            && goalDayCount != nil
            && currentVariant?.expectedDayCount != goalDayCount
        var updated = existing ?? ArtifactRecord(
            title: "旅行计划草稿", conversationID: conversationID, goalID: goalID, content: response,
            status: "draft", sourceMessageIDs: sourceMessageIDs, assumptions: draft.assumptions,
            expectedDayCount: draft.expectedDayCount, coveredDayCount: draft.dayCount
        )
        if existing != nil { updated.currentRevision += 1 }
        updated.content = response
        updated.status = "draft"
        updated.assumptions = draft.assumptions
        updated.expectedDayCount = draft.expectedDayCount
        updated.coveredDayCount = draft.dayCount
        updated.updatedAt = now
        var sources = updated.sourceMessageIDs ?? []
        for sourceMessageID in sourceMessageIDs where !sources.contains(sourceMessageID) { sources.append(sourceMessageID) }
        updated.sourceMessageIDs = sources

        var addedAlternative = false
        if existing != nil {
            guard let currentIndex = existingCurrentIndex else { return nil }
            if wantsAlternative {
                if let identicalIndex = variants.firstIndex(where: { $0.content == response && $0.expectedDayCount == draft.expectedDayCount }) {
                    variants[identicalIndex].sourceMessageIDs = merged(variants[identicalIndex].sourceMessageIDs ?? [], sourceMessageIDs)
                    variants[identicalIndex].updatedAt = now
                    updated.selectedTravelPlanVariantID = variants[identicalIndex].id
                } else {
                    guard variants.count < maximumVariants else { return nil }
                    let variant = makeVariant(content: response, draft: draft, sourceMessageIDs: sourceMessageIDs, now: now)
                    variants.append(variant)
                    updated.selectedTravelPlanVariantID = variant.id
                    addedAlternative = true
                }
            } else {
                variants[currentIndex].title = title(for: draft)
                variants[currentIndex].content = response
                variants[currentIndex].sourceMessageIDs = merged(variants[currentIndex].sourceMessageIDs ?? [], sourceMessageIDs)
                variants[currentIndex].assumptions = draft.assumptions
                variants[currentIndex].expectedDayCount = draft.expectedDayCount
                variants[currentIndex].coveredDayCount = draft.dayCount
                variants[currentIndex].updatedAt = now
                updated.selectedTravelPlanVariantID = variants[currentIndex].id
            }
        } else {
            let variant = makeVariant(content: response, draft: draft, sourceMessageIDs: sourceMessageIDs, now: now)
            variants = [variant]
            updated.selectedTravelPlanVariantID = variant.id
        }
        updated.travelPlanVariants = variants

        let isAlternative = wantsAlternative || activePlanIsAlternative
        let requestMatchesGoal = requestDayCount == nil || requestDayCount == goalDayCount
        return TravelPlanArtifactUpdate(
            artifact: updated,
            draft: draft,
            addedAlternative: addedAlternative,
            completesGoalPlan: draft.coversRequestedDays && !isAlternative && requestMatchesGoal
        )
    }

    private static func selectedCurrentVariant(for artifact: ArtifactRecord, variants: [TravelPlanVariantRecord]) -> TravelPlanVariantRecord? {
        if let selectedID = artifact.selectedTravelPlanVariantID,
           let selected = variants.first(where: { $0.id == selectedID }) { return selected }
        return variants.first(where: { $0.content == artifact.content }) ?? variants.first
    }

    @discardableResult
    private static func ensureCurrentVariant(
        for artifact: ArtifactRecord,
        in variants: inout [TravelPlanVariantRecord],
        sourceMessageIDs: [String],
        now: Date
    ) -> Int {
        if let id = artifact.selectedTravelPlanVariantID,
           let index = variants.firstIndex(where: { $0.id == id }),
           variants[index].content == artifact.content { return index }
        if let index = variants.firstIndex(where: { $0.content == artifact.content }) { return index }
        let draft = TravelArtifactDraftValidator.parse(artifact.content, expectedDayCount: artifact.expectedDayCount)
            ?? TravelArtifactDraft(dayCount: artifact.coveredDayCount ?? 0, expectedDayCount: artifact.expectedDayCount, coversRequestedDays: false, assumptions: artifact.assumptions ?? [])
        let variant = makeVariant(content: artifact.content, draft: draft, sourceMessageIDs: sourceMessageIDs, now: artifact.updatedAt)
        variants.append(variant)
        return variants.count - 1
    }

    private static func makeVariant(content: String, draft: TravelArtifactDraft, sourceMessageIDs: [String], now: Date) -> TravelPlanVariantRecord {
        TravelPlanVariantRecord(
            title: title(for: draft), content: content, sourceMessageIDs: sourceMessageIDs,
            assumptions: draft.assumptions, expectedDayCount: draft.expectedDayCount,
            coveredDayCount: draft.dayCount, updatedAt: now
        )
    }

    private static func title(for draft: TravelArtifactDraft) -> String {
        "\(draft.expectedDayCount ?? draft.dayCount)天方案"
    }

    private static func merged(_ existing: [String], _ additions: [String]) -> [String] {
        var result = existing
        for value in additions where !result.contains(value) { result.append(value) }
        return result
    }

    private static func containsAlternativeIntent(_ request: String) -> Bool {
        let indicators = ["保留", "新增", "备选", "另一个方案", "另一个版本", "另外一套", "另做一份", "再做一个", "再给一个", "选项", "对比", "同时提供"]
        return indicators.contains { request.localizedCaseInsensitiveContains($0) }
    }
}
