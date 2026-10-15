import Foundation
import PrayerKit

/// Locale-aware formatting for times, durations, dates and digits, honouring the in-app language
/// (which may differ from the system language) and the location's time zone.
struct Fmt {
    let arabic: Bool
    let easternDigits: Bool
    let clock: ClockStyle
    let timeZone: TimeZone

    var locale: Locale {
        if arabic {
            return Locale(identifier: easternDigits ? "ar@numbers=arab" : "ar@numbers=latn")
        }
        let region = Locale.current.region?.identifier ?? "US"
        return Locale(identifier: "en_\(region)")
    }

    private var useEasternDigits: Bool { arabic && easternDigits }

    func digits(_ s: String) -> String {
        guard useEasternDigits else { return s }
        let map: [Character: Character] = ["0": "٠", "1": "١", "2": "٢", "3": "٣", "4": "٤",
                                           "5": "٥", "6": "٦", "7": "٧", "8": "٨", "9": "٩"]
        return String(s.map { map[$0] ?? $0 })
    }

    func number(_ n: Int) -> String { digits(String(n)) }

    func number(_ d: Double, fractionDigits: Int) -> String {
        digits(String(format: "%.\(fractionDigits)f", d))
    }

    /// DateFormatter creation is expensive (it opens an ICU formatter), and views format on every tick,
    /// so formatters are cached per format/calendar/locale/time zone.
    private static var formatters: [String: DateFormatter] = [:]
    private static let formattersLock = NSLock()

    private func formatter(_ format: String, calendar: Calendar.Identifier = .gregorian) -> DateFormatter {
        let locale = locale
        let key = "\(format)|\(calendar)|\(locale.identifier)|\(timeZone.identifier)"
        Self.formattersLock.lock()
        defer { Self.formattersLock.unlock() }
        if let f = Self.formatters[key] { return f }
        let f = DateFormatter()
        var cal = Calendar(identifier: calendar)
        cal.timeZone = timeZone
        cal.locale = locale
        f.calendar = cal
        f.locale = locale
        f.timeZone = timeZone
        f.dateFormat = format
        Self.formatters[key] = f
        return f
    }

    private static let systemUses24Hour: Bool = {
        let fmt = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current) ?? "h"
        return !fmt.contains("a")
    }()

    var uses24Hour: Bool {
        switch clock {
        case .twelveHour: return false
        case .twentyFourHour: return true
        case .system: return Self.systemUses24Hour
        }
    }

    func time(_ date: Date) -> String {
        formatter(uses24Hour ? "HH:mm" : "h:mm a").string(from: date)
    }

    /// Time without the AM/PM marker, plus the marker separately (for typographic layouts).
    func timeParts(_ date: Date) -> (time: String, period: String?) {
        if uses24Hour { return (formatter("HH:mm").string(from: date), nil) }
        return (formatter("h:mm").string(from: date), formatter("a").string(from: date))
    }

    func weekdayDate(_ date: Date) -> String {
        formatter(arabic ? "EEEE d MMMM" : "EEEE, d MMMM").string(from: date)
    }

    func shortDate(_ date: Date) -> String {
        formatter(arabic ? "EEE d MMM" : "EEE, d MMM").string(from: date)
    }

    func monthYear(_ date: Date) -> String {
        formatter("LLLL yyyy").string(from: date)
    }

    func hijri(_ date: Date, offsetDays: Int, includeYear: Bool = true) -> String {
        let shifted = date.addingTimeInterval(Double(offsetDays) * 86400)
        let f = formatter(includeYear ? "d MMMM y" : "d MMMM", calendar: .islamicUmmAlQura)
        var s = f.string(from: shifted)
        if includeYear { s += arabic ? " هـ" : " AH" }
        return s
    }

    func hijriMonth(_ date: Date, offsetDays: Int) -> Int {
        var cal = Calendar(identifier: .islamicUmmAlQura)
        cal.timeZone = timeZone
        return cal.component(.month, from: date.addingTimeInterval(Double(offsetDays) * 86400))
    }

    /// "1:23:05" style countdown (always includes hours so "0:26:43" can't be misread).
    func clockCountdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return digits(String(format: "%d:%02d:%02d", h, m, s))
    }

    /// "1h 23m" / "١ س ٢٣ د" style countdown (minute precision, rounded up).
    func shortCountdown(_ interval: TimeInterval, seconds: Bool = false) -> String {
        if seconds { return clockCountdown(interval) }
        let totalMinutes = max(0, Int((interval / 60).rounded(.up)))
        let h = totalMinutes / 60, m = totalMinutes % 60
        let hu = arabic ? "س" : "h", mu = arabic ? "د" : "m"
        if h == 0 { return digits("\(m)") + (arabic ? " " : "") + mu }
        if m == 0 { return digits("\(h)") + (arabic ? " " : "") + hu }
        return arabic ? "\(digits("\(h)")) \(hu) \(digits("\(m)")) \(mu)" : "\(h)\(hu) \(m)\(mu)"
    }

    func isFriday(_ date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.component(.weekday, from: date) == 6
    }

    func degrees(_ value: Double) -> String { digits(String(format: "%.0f", value)) + "°" }
}
