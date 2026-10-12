import Foundation

enum MemoryPrivacyPolicy {
    private static let sensitiveTerms = [
        "health & dietary", "health", "medical", "diagnosis", "disease", "illness", "medication", "prescription",
        "allergy", "mental health", "psychiatric", "trauma", "dietary restriction", "disability",
        "financial", "income", "salary", "debt", "bank account", "assets", "savings",
        "健康", "疾病", "病史", "诊断", "治疗", "用药", "药物", "过敏", "饮食", "营养", "心理健康",
        "心理咨询", "抑郁", "焦虑", "精神疾病", "心理创伤", "残疾", "财务", "收入", "工资",
        "债务", "存款", "银行卡", "银行账户", "资产"
    ]

    static func isSensitive(_ text: String) -> Bool {
        let normalized = normalize(text)
        return sensitiveTerms.contains { normalized.contains(normalize($0)) }
    }

    static func explicitlyRequestsRetention(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["记住", "以后请记得", "remember that", "remember this"].contains(where: normalized.hasPrefix)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
    }
}
