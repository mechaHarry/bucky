import Foundation

struct Countdown: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var targetDate: Date

    init(id: UUID = UUID(), name: String, targetDate: Date) {
        self.id = id
        self.name = name
        self.targetDate = targetDate
    }
}

struct CountdownRemaining: Equatable, Hashable {
    let days: Int
    let hours: Int
    let minutes: Int
    let seconds: Int
    let milliseconds: Int

    static let zero = Self(days: 0, hours: 0, minutes: 0, seconds: 0, milliseconds: 0)

    init(days: Int, hours: Int, minutes: Int, seconds: Int, milliseconds: Int) {
        self.days = days
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.milliseconds = milliseconds
    }

    init(until targetDate: Date, now: Date) {
        let rawInterval = targetDate.timeIntervalSince(now)
        let interval = rawInterval.isNaN ? 0 : max(0, rawInterval)
        let maximumMilliseconds = Double(Int.max / 2)
        let totalMilliseconds = Int(min(interval * 1_000, maximumMilliseconds).rounded(.down))
        let millisecondsPerSecond = 1_000
        let millisecondsPerMinute = millisecondsPerSecond * 60
        let millisecondsPerHour = millisecondsPerMinute * 60
        let millisecondsPerDay = millisecondsPerHour * 24

        var remainder = totalMilliseconds
        days = remainder / millisecondsPerDay
        remainder %= millisecondsPerDay
        hours = remainder / millisecondsPerHour
        remainder %= millisecondsPerHour
        minutes = remainder / millisecondsPerMinute
        remainder %= millisecondsPerMinute
        seconds = remainder / millisecondsPerSecond
        milliseconds = remainder % millisecondsPerSecond
    }

    var displayString: String {
        "\(days)d \(String(format: "%02d", hours))h \(String(format: "%02d", minutes))m "
            + "\(String(format: "%02d", seconds))s \(String(format: "%03d", milliseconds))ms"
    }
}
