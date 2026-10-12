import Foundation

struct GoalCandidate: Equatable {
    var kind: String
    var title: String
    var summary: String
    var stepTitles: [String]
}

enum GoalProgressAction: Equatable {
    case stepCompleted(stepID: String)
    case goalCompleted
}

struct GoalProgressCandidate: Equatable {
    var goalID: String
    var action: GoalProgressAction
}

/// Conservative, deterministic intake rules for user-authored statements.
/// Uncertain language is deliberately left for conversation rather than persisted as fact.
enum IntentCapture {
    static func goalProgressCandidate(from rawText: String, goals: [GoalRecord], conversationID: String) -> GoalProgressCandidate? {
        let text = normalize(rawText)
        let completionPhrases = ["已经完成", "完成了", "完成啦", "做完了", "已经做完", "弄好了", "搞定了", "搞定啦", "做好了", "办好了", "写好了"]
        guard !text.isEmpty,
              containsAny(text, completionPhrases),
              !containsAny(text, ["还没", "没完成", "没有完成", "不算完成", "如果", "假如", "希望", "准备完成", "想完成", "我朋友", "我同事", "我家人", "他已经", "她已经", "他们已经", "别人"]) else { return nil }

        let activeGoals = goals.filter { $0.conversationID == conversationID && $0.status == "进行中" }
        guard !activeGoals.isEmpty else { return nil }
        let explicitScope = containsAny(text, ["这个目标", "这个计划", "这件事", "这趟旅行", "旅行计划", "行程计划"])
        let ordinal = explicitStepOrdinal(in: text)
        let scoped = activeGoals.filter { goal in
            let terms = specificTerms(from: goal.title)
            return terms.contains(where: text.contains) || (activeGoals.count == 1 && (explicitScope || ordinal != nil))
        }
        guard scoped.count == 1, let goal = scoped.first else { return nil }

        let matchingSteps = goal.steps.filter { step in
            specificTerms(from: step.title).contains(where: text.contains)
        }
        if matchingSteps.count == 1, let step = matchingSteps.first {
            guard !step.isComplete else { return nil }
            return GoalProgressCandidate(goalID: goal.id, action: .stepCompleted(stepID: step.id))
        }
        guard matchingSteps.isEmpty else { return nil }

        if let ordinal, goal.steps.indices.contains(ordinal) {
            guard !goal.steps[ordinal].isComplete else { return nil }
            return GoalProgressCandidate(goalID: goal.id, action: .stepCompleted(stepID: goal.steps[ordinal].id))
        }
        if containsAny(text, ["一个步骤", "某一步", "其中一步", "部分完成"]) { return nil }
        guard explicitlyCompletesWholeGoal(text, goal: goal) else { return nil }
        return GoalProgressCandidate(goalID: goal.id, action: .goalCompleted)
    }

    static func referencedActiveGoal(
        from rawText: String,
        goals: [GoalRecord],
        conversationID: String,
        previousAssistantQuestion: String? = nil
    ) -> GoalRecord? {
        let text = normalize(rawText)
        guard !text.isEmpty else { return nil }
        let allActiveGoals = goals.filter { $0.status == "进行中" }
        let activeGoals = goals.filter { $0.conversationID == conversationID && $0.status == "进行中" }
        guard !allActiveGoals.isEmpty else { return nil }
        let contextualReferences = [
            "这个目标", "这个计划", "这件事", "这份计划", "那份计划", "这个行程", "这趟",
            "刚才的计划", "刚才那份", "剩下几天", "剩余几天", "把剩下", "补齐", "补上",
            "继续计划", "继续这份", "旅行计划", "旅游计划", "旅行路线", "行程计划", "行程草案",
            "完整的七日", "完整的七天", "完整七日", "完整七天"
        ]
        let namedMatches = activeGoals.filter { goal in
            specificTerms(from: goal.title).contains(where: text.contains)
        }
        if namedMatches.count == 1 { return namedMatches[0] }
        guard namedMatches.isEmpty else { return nil }

        let namedTravelMatches = allActiveGoals.filter { goal in
            let isTravel = goal.goalKind == "travel" || goal.title.contains("旅行") || goal.title.contains("旅游")
            return isTravel && specificTerms(from: goal.title).contains(where: text.contains) &&
                containsAny(text, ["旅行", "旅游", "行程", "路线", "计划"])
        }
        if namedTravelMatches.count == 1 { return namedTravelMatches[0] }
        guard namedTravelMatches.isEmpty else { return nil }

        guard activeGoals.count == 1, let goal = activeGoals.first else { return nil }
        let isTravel = goal.goalKind == "travel" || goal.title.contains("旅行") || goal.title.contains("旅游")
        if isTravel {
            let knownDestinations = ["恩施", "成都", "大理", "云南", "日本", "京都", "杭州", "新疆"]
            if let mentionedDestination = knownDestinations.first(where: text.contains),
               !specificTerms(from: goal.title).contains(where: { $0.contains(mentionedDestination) }) {
                return nil
            }
        }
        if containsAny(text, contextualReferences) { return goal }
        guard isTravel, let previousAssistantQuestion else {
            return containsAny(text, ["下一步", "继续做", "接着做", "往下做"]) ? goal : nil
        }

        // Answers to the immediately preceding travel-planning question often omit the
        // destination and the words "旅行" or "行程". Attach only a clear answer to a
        // unique active travel goal in the same conversation.
        let question = normalize(previousAssistantQuestion)
        guard containsAny(question, ["?", "？"]),
              !containsAny(text, ["取消旅行", "不去", "先不计划", "不想去了", "不需要旅行", "换个话题", "先不聊这个"]) else { return nil }

        let dateQuestion = containsAny(question, ["日期", "时间", "哪天", "什么时候", "几号", "出发"])
        let partyQuestion = containsAny(question, ["同行", "几个人", "多少人", "和谁", "一个人", "独自", "一起"])
        let paceQuestion = containsAny(question, ["节奏", "步调", "轻松", "紧凑", "不赶", "安排得"])

        let dateAnswer = containsAny(text, ["还没定", "没定", "待定", "未定", "日期是", "时间是", "周末", "下周", "月底", "月出发", "号出发"])
        let partyAnswer = containsAny(text, ["一个人", "独自", "我自己", "自己去", "两个人", "同行", "朋友一起", "家人一起", "和朋友", "和家人", "我们去"])
        let paceAnswer = containsAny(text, ["轻松", "舒适", "慢一点", "慢节奏", "不赶", "紧凑", "慢慢", "节奏", "随意", "松弛", "不要太满", "别太满"])

        return (dateQuestion && dateAnswer) || (partyQuestion && partyAnswer) || (paceQuestion && paceAnswer) ? goal : nil
    }

    static func goalCandidate(from rawText: String) -> GoalCandidate? {
        let text = normalize(rawText)
        guard !text.isEmpty else { return nil }

        // Do not assign another person's plans, hypotheticals, quoted material, or explicit
        // non-intent to the user. These checks are intentionally conservative.
        guard !containsAny(text, ["朋友", "同事", "家人", "他想", "她想", "他们想", "别人", "帮他", "帮她", "替他", "替她", "如果", "假如", "要是", "不想", "不打算", "不准备", "不去", "不需要", "取消", "不考虑"]),
              !text.contains("引用如下") else { return nil }

        // Keep the user's first declarative clause when they end a real intention with a
        // conversational question such as "我想学英语，可以陪我吗？". A bare "我想学英语吗？"
        // remains a question about intent and is not persisted.
        let hasQuestion = text.contains("?") || text.contains("？")
        let firstClause = text.components(separatedBy: CharacterSet(charactersIn: "，,;；?？")).first ?? text
        if hasQuestion && firstClause.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("吗") { return nil }
        let intentText = firstClause

        let casualOuting = containsAny(intentText, ["出去走走", "出去逛逛", "周末出去", "周末出游", "周末短途", "周边游"])
        let travel = casualOuting || containsAny(intentText, ["旅行", "旅游", "行程", "出行", "trip", "itinerary"])
        let goalPhrases = [
            "我想学习", "我想学", "我想练习", "我想完成", "我想实现", "我想建立", "我想开始", "我想做", "我想去", "我想要",
            "我计划", "我打算", "我准备", "我要", "我们想", "我们准备", "我们打算", "我想",
            "帮我制定", "帮我规划", "帮我安排", "帮我准备", "帮我设计", "替我规划", "给我规划", "为我规划",
            "帮忙规划", "帮忙设计", "规划一趟", "设计一趟", "安排一趟", "计划一趟", "制定一份"
        ]
        guard let phrase = goalPhrases.first(where: intentText.contains) else { return nil }

        // Curiosity questions such as "我想知道怎么学英语" are not ongoing intentions.
        let phraseRange = intentText.range(of: phrase)!
        let remainder = String(intentText[phraseRange.upperBound...])
        guard !containsAny(remainder, ["知道", "了解", "问", "听听", "看看"]),
              !remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        if travel {
            if casualOuting, !["恩施", "成都", "大理", "云南", "日本", "京都", "杭州", "新疆"].contains(where: intentText.contains) {
                return GoalCandidate(
                    kind: "travel",
                    title: "准备一次周末轻松出游",
                    summary: "从用户明确表达的短途出游想法创建；具体地点和安排仍待讨论。原始表达：\(rawText)",
                    stepTitles: ["选一个合适的地点和时段", "安排交通与休息时间", "按天气和体力调整计划"]
                )
            }
            let destination = ["恩施", "成都", "大理", "云南", "日本", "京都", "杭州", "新疆"].first(where: intentText.contains) ?? "旅行目的地"
            let isSevenDayPlan = ["7天", "7 天", "七天", "7日", "7 日", "七日"].contains(where: intentText.contains)
            let planSpan = isSevenDayPlan ? " 7 天旅行" : "旅行"
            return GoalCandidate(
                kind: "travel",
                title: "准备一趟\(destination)\(planSpan)计划",
                summary: "从用户明确表达的旅行想法创建；计划与实际预订分开记录。原始表达：\(rawText)",
                stepTitles: ["整理第一版路线", "确认日期、同行人和节奏", "检查交通与住宿选择"]
            )
        }

        let trimmedTitle = remainder
            .trimmingCharacters(in: CharacterSet(charactersIn: " ：:，,。.!！;；"))
            .replacingOccurrences(of: "一个", with: "")
            .replacingOccurrences(of: "一份", with: "")
            .replacingOccurrences(of: "计划", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ：:，,。.!！;；"))
        let title = String((trimmedTitle.isEmpty ? "推进个人计划" : trimmedTitle).prefix(32))
        return GoalCandidate(
            kind: "general",
            title: title,
            summary: "从用户明确表达的个人计划创建；步骤可随讨论调整。原始表达：\(rawText)",
            stepTitles: ["一起明确想要的结果", "拆出适合的第一步", "按进展调整计划"]
        )
    }

    static func travelGoalCandidate(from rawText: String) -> Bool {
        goalCandidate(from: rawText)?.kind == "travel"
    }

    static func explicitMemoryCandidate(from rawText: String) -> String? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              !text.contains("?") && !text.contains("？"),
              !containsAny(text, ["我朋友", "我同事", "我家人", "他说", "她说", "他们说", "别人说", "假如", "如果我", "有人说"]),
              !text.hasPrefix("请问"),
              !text.hasPrefix("你觉得"),
              !containsAny(text, ["我想", "我准备", "我打算", "我计划", "我希望", "我考虑", "我要", "我正在"]) else { return nil }

        let fact: String
        if text.hasPrefix("记住") {
            fact = String(text.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if text.hasPrefix("以后请记得") {
            fact = String(text.dropFirst("以后请记得".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if text.hasPrefix("以后请") {
            fact = String(text.dropFirst("以后请".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if isExplicitCurrentRelocation(text) || [
            "我目前更喜欢", "我现在更喜欢", "我更喜欢", "我喜欢", "我不喜欢", "我偏好", "我通常", "我平时", "我习惯",
            "我叫", "我的名字是", "我名叫", "我住在", "我目前住在", "我现在住在", "我来自", "我常住在", "我居住在", "现居",
            "我的职业是", "我的工作是", "我从事", "我是一名", "我担任", "我是"
        ].contains(where: text.hasPrefix) {
            fact = text
        } else {
            return nil
        }

        guard !fact.isEmpty else { return nil }
        if hasPlannedRelocation(text), !hasExplicitCurrentResidence(text) { return nil }
        return fact.trimmingCharacters(in: CharacterSet(charactersIn: "。.!！;；"))
    }

    static func explicitMemoryCategory(for value: String) -> String {
        let text = normalize(value)
        if containsAny(text, ["我叫", "我的名字是", "我名叫"]) { return "identity" }
        if containsAny(text, ["我住在", "我目前住在", "我现在住在", "我来自", "我常住在", "我居住在", "现居", "搬到", "搬去", "迁到"]) { return "location" }
        if containsAny(text, ["我的职业是", "我的工作是", "我从事", "我是一名", "我担任"]) { return "work" }
        if containsAny(text, ["我通常", "我平时", "我习惯"]) { return "routine" }
        if containsAny(text, ["我喜欢", "我不喜欢", "我更喜欢", "我偏好"]) { return "preference" }
        if containsAny(text, ["我叫", "我的名字是", "我名叫", "我是"]) { return "identity" }
        return "fact"
    }

    private static func isExplicitCurrentRelocation(_ text: String) -> Bool {
        guard text.hasPrefix("我"), containsAny(text, ["搬到", "搬去", "迁到"]),
              !hasPlannedRelocation(text), !containsAny(text, ["朋友", "同事", "家人"]) else {
            return false
        }
        return true
    }

    static func hasExplicitCurrentResidence(_ text: String) -> Bool {
        containsAny(normalize(text), ["我目前住在", "我现在住在", "我住在", "我居住在", "我常住在", "目前居住在", "现在居住在", "目前住在", "现在住在", "现居"])
    }

    static func hasPlannedRelocation(_ text: String) -> Bool {
        containsAny(text, ["搬到", "搬去", "迁到"]) && containsAny(text, ["以后", "将来", "如果", "假如", "要是", "可能", "也许", "或许", "考虑", "计划", "准备", "打算", "想搬", "正在搬"])
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func specificTerms(from value: String) -> [String] {
        var text = normalize(value)
        for generic in ["准备一趟", "一起", "整理", "第一版", "确认", "检查", "安排", "计划", "目标", "旅行", "旅游", "学习", "开始", "完成", "适合的", "按进展", "拆出", "想要", "结果", "和", "与", "的"] {
            text = text.replacingOccurrences(of: generic, with: " ")
        }
        return text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 && !["这个", "已经", "帮我", "第一", "第二", "第三"].contains($0) }
    }

    private static func explicitStepOrdinal(in text: String) -> Int? {
        let ordinals: [(Int, [String])] = [
            (0, ["第一步", "第1步", "第一项", "第1项", "first step"]),
            (1, ["第二步", "第2步", "第二项", "第2项", "second step"]),
            (2, ["第三步", "第3步", "第三项", "第3项", "third step"])
        ]
        let matches = ordinals.filter { _, terms in terms.contains(where: text.contains) }
        return matches.count == 1 ? matches[0].0 : nil
    }

    private static func explicitlyCompletesWholeGoal(_ text: String, goal: GoalRecord) -> Bool {
        let references = specificTerms(from: goal.title) + ["这个目标", "这个计划", "这件事", "整件事", "整个计划", "整体计划", "全部计划", "整趟旅行", "旅行计划", "行程计划"]
        let completionVerbs = ["完成", "搞定", "做完", "做好", "办好"]
        let removableScopeWords = ["已经", "已", "全部", "整体", "整个", "都", "的", "目标", "计划", "旅行", "旅游", "行程"]

        for reference in references where reference.count >= 2 {
            guard let range = text.range(of: reference) else { continue }
            var suffix = String(text[range.upperBound...])
            for word in removableScopeWords {
                suffix = suffix.replacingOccurrences(of: word, with: "")
            }
            if completionVerbs.contains(where: suffix.hasPrefix) { return true }
        }
        return false
    }

    private static func containsAny(_ text: String, _ values: [String]) -> Bool {
        values.contains(where: text.contains)
    }
}
