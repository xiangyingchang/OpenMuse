import Foundation

/// The small, stable command contract exposed by the iPhone iSH guest.
/// AlarmKit itself stays in the iOS app target; this parser is platform-neutral
/// so command validation can be covered by the Core test suite.
public enum PhoneAlarmCommand: Equatable, Sendable {
    case set(time: Date, label: String)
    case repeatAlarm(hour: Int, minute: Int, weekdays: [Int], label: String)
    case timer(seconds: Int, label: String)
    case list
    case cancel(UUID?)

    public enum ParseError: Error, LocalizedError, Equatable {
        case invalidUsage(String)
        case invalidTime(String)
        case invalidDuration(String)
        case invalidLabel
        case invalidIdentifier(String)

        public var errorDescription: String? {
            switch self {
            case .invalidUsage(let detail): detail
            case .invalidTime(let detail): detail
            case .invalidDuration(let detail): detail
            case .invalidLabel: "标签不能为空，且不能超过 120 个字符。"
            case .invalidIdentifier(let value): "闹钟 ID 无效：\(value)"
            }
        }
    }

    public static let usage = """
    用法：
      openmuse-alarm set --time 07:30 --label '起床'
      openmuse-alarm set --time 2026-10-13T07:30:00+08:00 --label '出发'
      openmuse-alarm set --time 08:00 --repeat daily --label '吃药'
      openmuse-alarm timer --duration 5m --label '煮茶'
      openmuse-alarm list
      openmuse-alarm cancel <UUID|all>

    --time 使用本机时区；HH:mm 表示下一次该时间。日期时间支持 YYYY-MM-DDTHH:mm[:ss]，可省略时区（按本机时区解释）或带 Z/±HH:mm。
    --repeat 支持 daily、weekdays、weekends。计时器时长支持秒数或 1h30m 格式，最长 24 小时。
    """

    public static func parse(
        arguments: [String],
        now: Date = .now,
        timeZone: TimeZone = .current
    ) throws -> PhoneAlarmCommand {
        guard let action = arguments.first else {
            throw ParseError.invalidUsage(usage)
        }

        if action == "--help" || action == "-h" || action == "help" {
            throw ParseError.invalidUsage(usage)
        }

        switch action {
        case "list":
            guard arguments.count == 1 else { throw ParseError.invalidUsage("list 不接受其他参数。") }
            return .list
        case "cancel":
            guard arguments.count == 2 else { throw ParseError.invalidUsage("用法：openmuse-alarm cancel <UUID|all>") }
            if arguments[1].lowercased() == "all" { return .cancel(nil) }
            guard let id = UUID(uuidString: arguments[1]) else {
                throw ParseError.invalidIdentifier(arguments[1])
            }
            return .cancel(id)
        case "set":
            let options = try parseOptions(Array(arguments.dropFirst()), allowed: ["--time", "--label", "--repeat"])
            guard let rawTime = options["--time"] else {
                throw ParseError.invalidUsage("设置闹钟需要 --time HH:mm 或完整日期时间。")
            }
            let label = try validatedLabel(options["--label"] ?? "OpenMuse 闹钟")
            let repeatName = options["--repeat"]?.lowercased()
            if let repeatName, repeatName != "daily", repeatName != "weekdays", repeatName != "weekends" {
                throw ParseError.invalidUsage("--repeat 只支持 daily、weekdays 或 weekends。")
            }
            if let repeatName {
                guard let time = parseClockTime(rawTime) else {
                    throw ParseError.invalidTime("重复闹钟的 --time 必须是 HH:mm。")
                }
                let weekdays: [Int]
                switch repeatName {
                case "daily": weekdays = [1, 2, 3, 4, 5, 6, 7]
                case "weekdays": weekdays = [2, 3, 4, 5, 6]
                default: weekdays = [1, 7]
                }
                return .repeatAlarm(hour: time.hour, minute: time.minute, weekdays: weekdays, label: label)
            }
            return .set(time: try parseDate(rawTime, now: now, timeZone: timeZone), label: label)
        case "timer":
            let options = try parseOptions(Array(arguments.dropFirst()), allowed: ["--duration", "--label"])
            guard let rawDuration = options["--duration"] else {
                throw ParseError.invalidUsage("设置计时器需要 --duration，例如 300、5m 或 1h30m。")
            }
            return .timer(seconds: try parseDuration(rawDuration), label: try validatedLabel(options["--label"] ?? "OpenMuse 计时器"))
        default:
            throw ParseError.invalidUsage(usage)
        }
    }

    private static func parseOptions(_ arguments: [String], allowed: Set<String>) throws -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard allowed.contains(key), index + 1 < arguments.count else {
                throw ParseError.invalidUsage("未知或缺少值的参数：\(key)")
            }
            guard result[key] == nil else { throw ParseError.invalidUsage("参数不能重复：\(key)") }
            result[key] = arguments[index + 1]
            index += 2
        }
        return result
    }

    private static func validatedLabel(_ value: String) throws -> String {
        let label = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.count <= 120, !label.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw ParseError.invalidLabel
        }
        return label
    }

    private static func parseClockTime(_ value: String) -> (hour: Int, minute: Int)? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    private static func parseDate(_ value: String, now: Date, timeZone: TimeZone) throws -> Date {
        if let time = parseClockTime(value) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let today = calendar.dateComponents([.year, .month, .day], from: now)
            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = timeZone
            components.year = today.year
            components.month = today.month
            components.day = today.day
            components.hour = time.hour
            components.minute = time.minute
            components.second = 0
            guard var candidate = calendar.date(from: components), matches(candidate, time: time, calendar: calendar) else {
                throw ParseError.invalidTime("本机时区在该日期没有这个时间：\(value)")
            }
            if candidate <= now {
                guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: candidate) else {
                    throw ParseError.invalidTime("无法计算下一次闹钟时间。")
                }
                candidate = tomorrow
                guard matches(candidate, time: time, calendar: calendar) else {
                    throw ParseError.invalidTime("本机时区在下一次日期没有这个时间：\(value)")
                }
            }
            return candidate
        }

        guard let parts = dateParts(value) else {
            throw ParseError.invalidTime("时间格式无效：\(value)。使用 HH:mm 或 YYYY-MM-DDTHH:mm[:ss][Z|±HH:mm]。")
        }
        let date: Date?
        if parts.hasTimeZone {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: normalizedISO8601(value))
        } else {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = timeZone
            components.year = parts.year
            components.month = parts.month
            components.day = parts.day
            components.hour = parts.hour
            components.minute = parts.minute
            components.second = parts.second
            date = calendar.date(from: components).flatMap { matches($0, parts: parts, calendar: calendar) ? $0 : nil }
        }
        guard let date, date > now else {
            throw ParseError.invalidTime("闹钟时间必须是有效的未来时间：\(value)")
        }
        return date
    }

    private static func parseDuration(_ value: String) throws -> Int {
        if let seconds = Int(value), seconds > 0, seconds <= 86_400 { return seconds }
        let pattern = #"^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.range.length == value.utf16.count else {
            throw ParseError.invalidDuration("时长格式无效：\(value)。使用秒数或 1h30m。")
        }
        func number(_ group: Int) -> Int? {
            guard match.range(at: group).location != NSNotFound,
                  let range = Range(match.range(at: group), in: value) else { return 0 }
            return Int(value[range])
        }
        guard let hours = number(1), let minutes = number(2), let remainder = number(3),
              (0...24).contains(hours), (0...1_440).contains(minutes), (0...86_400).contains(remainder) else {
            throw ParseError.invalidDuration("计时器时长必须大于 0 且不超过 24 小时。")
        }
        let seconds = hours * 3_600 + minutes * 60 + remainder
        guard seconds > 0, seconds <= 86_400 else { throw ParseError.invalidDuration("计时器时长必须大于 0 且不超过 24 小时。") }
        return seconds
    }

    private struct DateParts {
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
        let second: Int
        let hasTimeZone: Bool
    }

    private static func dateParts(_ value: String) -> DateParts? {
        let pattern = #"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?(Z|[+-]\d{2}:?\d{2})?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.range.length == value.utf16.count else { return nil }
        func integer(_ group: Int) -> Int? {
            guard let range = Range(match.range(at: group), in: value) else { return nil }
            return Int(value[range])
        }
        let second = integer(6) ?? 0
        guard let year = integer(1), let month = integer(2), let day = integer(3),
              let hour = integer(4), let minute = integer(5),
              (1...12).contains(month), (1...31).contains(day), (0...23).contains(hour),
              (0...59).contains(minute), (0...59).contains(second) else { return nil }
        return DateParts(year: year, month: month, day: day, hour: hour, minute: minute,
                         second: second, hasTimeZone: match.range(at: 7).location != NSNotFound)
    }

    private static func normalizedISO8601(_ value: String) -> String {
        guard let timeZoneRange = value.range(of: #"(?:Z|[+-]\d{2}:?\d{2})$"#, options: .regularExpression) else { return value }
        var suffix = String(value[timeZoneRange])
        if suffix != "Z", !suffix.contains(":") {
            let colon = suffix.index(suffix.startIndex, offsetBy: 3)
            suffix = String(suffix[..<colon]) + ":" + String(suffix[colon...])
        }
        let dateAndTime = String(value[..<timeZoneRange.lowerBound])
        let hasSeconds = dateAndTime.range(of: #"[T ]\d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil
        return dateAndTime + (hasSeconds ? "" : ":00") + suffix
    }

    private static func matches(_ date: Date, time: (hour: Int, minute: Int), calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return components.hour == time.hour && components.minute == time.minute
    }

    private static func matches(_ date: Date, parts: DateParts, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return components.year == parts.year && components.month == parts.month && components.day == parts.day
            && components.hour == parts.hour && components.minute == parts.minute && components.second == parts.second
    }
}
