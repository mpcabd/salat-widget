import Foundation
import PrayerKit

/// Minutes after local midnight of `date` in `timeZone`.
func localMinutes(_ date: Date, _ timeZone: TimeZone) -> Int {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = timeZone
    let c = cal.dateComponents([.hour, .minute], from: date)
    return c.hour! * 60 + c.minute!
}

/// Parses "HH:mm" into minutes after midnight.
func minutes(_ hhmm: String) -> Int {
    let parts = hhmm.split(separator: ":").map { Int($0)! }
    return parts[0] * 60 + parts[1]
}

/// Signed difference in minutes between two clock times, wrapping around midnight.
func clockDifference(_ a: Int, _ b: Int) -> Int {
    (a - b + 720 + 1440) % 1440 - 720
}

func calculator(
    _ latitude: Double, _ longitude: Double,
    _ method: CalculationMethod,
    madhab: Madhab = .standard,
    adjustments: PrayerAdjustments = PrayerAdjustments(),
    imsakMinutes: Double = 10
) -> PrayerCalculator {
    PrayerCalculator(
        coordinates: Coordinates(latitude: latitude, longitude: longitude),
        parameters: method.parameters,
        madhab: madhab,
        adjustments: adjustments,
        imsakMinutes: imsakMinutes
    )
}

extension PrayerTimes {
    /// The five prayers and sunrise, in the order they occur.
    var ordered: [Date] { Prayer.allCases.map { time(for: $0) } }
}
