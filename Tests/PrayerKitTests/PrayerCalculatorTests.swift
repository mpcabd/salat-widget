import Foundation
import PrayerKit
import Testing

struct ReferenceDay: CustomTestStringConvertible, Sendable {
    let city: String
    let latitude: Double
    let longitude: Double
    let timeZone: String
    let method: CalculationMethod
    let day: CalendarDay
    /// Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha as "HH:mm" local time.
    let times: [String]

    var testDescription: String { "\(city) \(method.rawValue) \(day.year)-\(day.month)-\(day.day)" }
}

/// Reference timetables from the AlAdhan API (api.aladhan.com), an independent implementation.
/// Only methods without official minute offsets are used, so the comparison is about the astronomy.
let referenceDays: [ReferenceDay] = [
    .init(city: "Makkah", latitude: 21.4225, longitude: 39.8262, timeZone: "Asia/Riyadh",
          method: .ummAlQura, day: .init(year: 2026, month: 10, day: 15),
          times: ["05:00", "06:16", "12:06", "15:28", "17:56", "19:26"]),
    .init(city: "New York", latitude: 40.7128, longitude: -74.0060, timeZone: "America/New_York",
          method: .isna, day: .init(year: 2026, month: 6, day: 21),
          times: ["03:45", "05:25", "12:58", "16:58", "20:31", "22:11"]),
    .init(city: "Cairo", latitude: 30.0444, longitude: 31.2357, timeZone: "Africa/Cairo",
          method: .egyptian, day: .init(year: 2026, month: 10, day: 15),
          times: ["05:30", "06:57", "12:41", "15:58", "18:24", "19:42"]),
    .init(city: "Karachi", latitude: 24.8607, longitude: 67.0011, timeZone: "Asia/Karachi",
          method: .karachi, day: .init(year: 2026, month: 10, day: 15),
          times: ["05:14", "06:30", "12:18", "15:38", "18:05", "19:21"]),
    .init(city: "Kuwait City", latitude: 29.3759, longitude: 47.9774, timeZone: "Asia/Kuwait",
          method: .kuwait, day: .init(year: 2026, month: 10, day: 15),
          times: ["04:30", "05:49", "11:34", "14:52", "17:18", "18:35"]),
    .init(city: "Doha", latitude: 25.2854, longitude: 51.5310, timeZone: "Asia/Qatar",
          method: .qatar, day: .init(year: 2026, month: 10, day: 15),
          times: ["04:16", "05:32", "11:20", "14:40", "17:07", "18:37"]),
    .init(city: "Sydney", latitude: -33.8688, longitude: 151.2093, timeZone: "Australia/Sydney",
          method: .muslimWorldLeague, day: .init(year: 2026, month: 12, day: 21),
          times: ["03:56", "05:41", "12:53", "16:38", "20:05", "21:43"]),
]

/// Allowed difference from the reference, to absorb rounding and small algorithm differences.
let toleranceMinutes = 2

@Suite struct ReferenceTimetables {
    @Test(arguments: referenceDays)
    func matchesReference(_ ref: ReferenceDay) {
        let tz = TimeZone(identifier: ref.timeZone)!
        let times = calculator(ref.latitude, ref.longitude, ref.method).times(for: ref.day)
        for (prayer, expected) in zip(Prayer.allCases, ref.times) {
            let diff = clockDifference(localMinutes(times.time(for: prayer), tz), minutes(expected))
            #expect(abs(diff) <= toleranceMinutes, "\(prayer.rawValue): off by \(diff) min from \(expected)")
        }
    }

    @Test func hanafiAsr() {
        let tz = TimeZone(identifier: "Asia/Karachi")!
        let day = CalendarDay(year: 2026, month: 10, day: 15)
        let hanafi = calculator(24.8607, 67.0011, .karachi, madhab: .hanafi).times(for: day)
        let standard = calculator(24.8607, 67.0011, .karachi).times(for: day)
        #expect(abs(clockDifference(localMinutes(hanafi.asr, tz), minutes("16:28"))) <= toleranceMinutes)
        #expect(hanafi.asr > standard.asr)
        #expect(hanafi.fajr == standard.fajr)
        #expect(hanafi.isha == standard.isha)
    }
}

@Suite struct Invariants {
    static let cities: [(String, Double, Double)] = [
        ("Makkah", 21.4225, 39.8262), ("London", 51.5074, -0.1278), ("Jakarta", -6.2088, 106.8456),
        ("Istanbul", 41.0082, 28.9784), ("Stockholm", 59.3293, 18.0686), ("Cape Town", -33.9249, 18.4241),
    ]
    static let days: [CalendarDay] = [
        .init(year: 2026, month: 3, day: 20), .init(year: 2026, month: 6, day: 21), .init(year: 2026, month: 12, day: 21),
    ]

    @Test(arguments: CalculationMethod.allCases)
    func prayersAreInOrder(_ method: CalculationMethod) {
        for (name, lat, lng) in Self.cities {
            for day in Self.days {
                let t = calculator(lat, lng, method).times(for: day)
                #expect(t.ordered == t.ordered.sorted(), "\(name) \(day)")
                #expect(t.imsak < t.fajr, "\(name) \(day)")
                #expect(t.isha < t.midnight, "\(name) \(day)")
                #expect(t.midnight < t.lastThird, "\(name) \(day)")
                #expect(t.dhuhr.timeIntervalSince(t.fajr) < 24 * 3600, "\(name) \(day)")
            }
        }
    }

    @Test(arguments: [10.0, 20.0])
    func imsakPrecedesFajr(_ minutesBefore: Double) {
        let t = calculator(21.4225, 39.8262, .ummAlQura, imsakMinutes: minutesBefore)
            .times(for: .init(year: 2026, month: 10, day: 15))
        #expect(t.fajr.timeIntervalSince(t.imsak) == minutesBefore * 60)
    }

    @Test func manualAdjustmentsShiftByExactMinutes() {
        let day = CalendarDay(year: 2026, month: 10, day: 15)
        let base = calculator(30.0444, 31.2357, .egyptian).times(for: day)
        let adjusted = calculator(30.0444, 31.2357, .egyptian,
                                  adjustments: .init(fajr: 5, sunrise: -2, dhuhr: 1, asr: 0, maghrib: 3, isha: -4))
            .times(for: day)
        #expect(adjusted.fajr.timeIntervalSince(base.fajr) == 5 * 60)
        #expect(adjusted.sunrise.timeIntervalSince(base.sunrise) == -2 * 60)
        #expect(adjusted.dhuhr.timeIntervalSince(base.dhuhr) == 1 * 60)
        #expect(adjusted.asr == base.asr)
        #expect(adjusted.maghrib.timeIntervalSince(base.maghrib) == 3 * 60)
        #expect(adjusted.isha.timeIntervalSince(base.isha) == -4 * 60)
    }

    @Test func timesAreWholeMinutes() {
        let t = calculator(51.5074, -0.1278, .moonsightingCommittee).times(for: .init(year: 2026, month: 6, day: 21))
        for date in t.ordered + [t.midnight, t.lastThird] {
            #expect(date.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) == 0)
        }
    }
}

@Suite struct IshaIntervals {
    @Test func ummAlQuraUsesNinetyMinutesOutsideRamadan() {
        let t = calculator(21.4225, 39.8262, .ummAlQura).times(for: .init(year: 2026, month: 10, day: 15))
        #expect(t.isha.timeIntervalSince(t.maghrib) == 90 * 60)
    }

    @Test func ummAlQuraUsesTwoHoursInRamadan() {
        // 1 March 2026 is 12 Ramadan 1447.
        let t = calculator(21.4225, 39.8262, .ummAlQura).times(for: .init(year: 2026, month: 3, day: 1))
        #expect(t.isha.timeIntervalSince(t.maghrib) == 120 * 60)
    }

    @Test(arguments: [CalculationMethod.qatar, .gulf])
    func otherIntervalMethodsIgnoreRamadan(_ method: CalculationMethod) {
        let t = calculator(25.2854, 51.5310, method).times(for: .init(year: 2026, month: 3, day: 1))
        #expect(t.isha.timeIntervalSince(t.maghrib) == 90 * 60)
    }
}

@Suite struct HighLatitudes {
    /// Tromsø has polar night in December and midnight sun in June.
    @Test(arguments: [CalendarDay(year: 2026, month: 6, day: 21), CalendarDay(year: 2026, month: 12, day: 21)])
    func polarDayAndNightStillProduceTimes(_ day: CalendarDay) {
        let t = calculator(69.6492, 18.9553, .muslimWorldLeague).times(for: day)
        #expect(t.ordered == t.ordered.sorted())
        #expect(t.ordered.allSatisfy { abs($0.timeIntervalSince(day.startDate(in: TimeZone(identifier: "UTC")!))) < 2 * 86400 })
    }

    @Test func fajrAndIshaAreBoundedInNorthernSummer() {
        // At 18° the sun never gets deep enough in Stockholm in June; the high-latitude rule must kick in.
        let t = calculator(59.3293, 18.0686, .muslimWorldLeague).times(for: .init(year: 2026, month: 6, day: 21))
        #expect(t.ordered == t.ordered.sorted())
        #expect(t.sunrise.timeIntervalSince(t.fajr) > 0)
        #expect(t.isha.timeIntervalSince(t.maghrib) > 0)
    }
}
