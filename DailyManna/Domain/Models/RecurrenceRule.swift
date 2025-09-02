import Foundation

public struct RecurrenceRule: Codable, Equatable, Hashable {
    public enum Frequency: String, Codable { case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY" }
    public var freq: Frequency
    public var interval: Int
    public var byWeekday: [String]? // ["MO","TU",...]
    public var byMonthDay: [Int]? // [1..31]
    public var bySetPos: [Int]? // e.g., [1] for first, [-1] for last
    public var byMonth: [Int]? // 1..12
    public var time: String? // "HH:mm" local time

    public init(freq: Frequency, interval: Int = 1, byWeekday: [String]? = nil, byMonthDay: [Int]? = nil, bySetPos: [Int]? = nil, byMonth: [Int]? = nil, time: String? = nil) {
        self.freq = freq
        self.interval = max(1, interval)
        self.byWeekday = byWeekday
        self.byMonthDay = byMonthDay
        self.bySetPos = bySetPos
        self.byMonth = byMonth
        self.time = time
    }
}


