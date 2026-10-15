import Foundation
import PrayerKit
import Testing

@Suite struct CalculationMethods {
    @Test(arguments: [
        (CalculationMethod.muslimWorldLeague, 18.0, TwilightRule.angle(17)),
        (.isna, 15, .angle(15)),
        (.egyptian, 19.5, .angle(17.5)),
        (.ummAlQura, 18.5, .minutes(90)),
        (.karachi, 18, .angle(18)),
        (.dubai, 18.2, .angle(18.2)),
        (.gulf, 19.5, .minutes(90)),
        (.kuwait, 18, .angle(17.5)),
        (.qatar, 18, .minutes(90)),
        (.moonsightingCommittee, 18, .angle(18)),
        (.singapore, 20, .angle(18)),
        (.jakim, 20, .angle(18)),
        (.kemenag, 20, .angle(18)),
        (.turkey, 18, .angle(17)),
        (.tehran, 17.7, .angle(14)),
        (.jafari, 16, .angle(14)),
        (.france, 12, .angle(12)),
        (.russia, 16, .angle(15)),
        (.morocco, 19, .angle(17)),
        (.algeria, 18, .angle(17)),
        (.tunisia, 18, .angle(18)),
    ])
    func publishedAngles(_ method: CalculationMethod, fajr: Double, isha: TwilightRule) {
        #expect(method.parameters.fajrAngle == fajr)
        #expect(method.parameters.isha == isha)
    }

    @Test func officialOffsets() {
        #expect(CalculationMethod.turkey.parameters.methodAdjustments
            == PrayerAdjustments(sunrise: -7, dhuhr: 5, asr: 4, maghrib: 7))
        #expect(CalculationMethod.dubai.parameters.methodAdjustments
            == PrayerAdjustments(sunrise: -3, dhuhr: 3, asr: 3, maghrib: 3))
        #expect(CalculationMethod.morocco.parameters.methodAdjustments
            == PrayerAdjustments(sunrise: -3, dhuhr: 5, maghrib: 5))
        #expect(CalculationMethod.moonsightingCommittee.parameters.methodAdjustments
            == PrayerAdjustments(dhuhr: 5, maghrib: 3))
    }

    @Test func onlyMoonsightingCommitteeUsesSeasonalTwilight() {
        for method in CalculationMethod.allCases {
            #expect(method.parameters.seasonalTwilight == (method == .moonsightingCommittee), "\(method)")
        }
    }

    @Test func onlyUmmAlQuraExtendsIshaInRamadan() {
        for method in CalculationMethod.allCases {
            let expected: Double? = method == .ummAlQura ? 120 : nil
            #expect(method.parameters.ishaRamadanMinutes == expected, "\(method)")
        }
    }

    @Test(arguments: [
        ("SA", CalculationMethod.ummAlQura), ("ae", .dubai), ("EG", .egyptian), ("PK", .karachi),
        ("US", .isna), ("GB", .moonsightingCommittee), ("MY", .jakim), ("ID", .kemenag),
        ("TR", .turkey), ("IR", .tehran), ("FR", .france), ("MA", .morocco), ("SE", .muslimWorldLeague),
    ])
    func recommendedForCountry(_ code: String, _ method: CalculationMethod) {
        #expect(CalculationMethod.recommended(forCountryCode: code) == method)
    }

    @Test func recommendedWithoutCountry() {
        #expect(CalculationMethod.recommended(forCountryCode: nil) == .muslimWorldLeague)
    }
}

@Suite struct QiblaTests {
    @Test(arguments: [
        // Bearings from Adhan's test suite and standard references.
        ("New York", 40.7128, -74.0059, 58.4817),
        ("San Francisco", 37.7749, -122.4194, 18.843),
        ("London", 51.5074, -0.1278, 118.987),
        ("Jakarta", -6.2088, 106.8456, 295.152),
        ("Sydney", -33.8688, 151.2093, 277.4996),
    ])
    func direction(_ city: String, _ lat: Double, _ lng: Double, _ bearing: Double) {
        let q = Qibla.direction(from: Coordinates(latitude: lat, longitude: lng))
        #expect(abs(q - bearing) < 0.1, "\(city): \(q)")
    }

    @Test func distance() {
        #expect(Qibla.distance(from: Qibla.kaaba) < 0.001)
        // New York to Makkah is roughly 10,300 km along a great circle.
        let ny = Qibla.distance(from: Coordinates(latitude: 40.7128, longitude: -74.0060))
        #expect((10_250...10_350).contains(ny), "\(ny)")
    }
}

@Suite struct CalendarDayTests {
    @Test func addingDaysCrossesMonthAndYear() {
        #expect(CalendarDay(year: 2026, month: 12, day: 31).adding(days: 1) == CalendarDay(year: 2027, month: 1, day: 1))
        #expect(CalendarDay(year: 2028, month: 3, day: 1).adding(days: -1) == CalendarDay(year: 2028, month: 2, day: 29))
        #expect(CalendarDay(year: 2026, month: 3, day: 1).adding(days: -1) == CalendarDay(year: 2026, month: 2, day: 28))
    }

    @Test func dependsOnTimeZone() {
        // 2026-10-15 22:30 UTC is already the 16th in Makkah and still the 15th in New York.
        let date = Date(timeIntervalSince1970: 1_792_103_400)
        #expect(CalendarDay(date: date, timeZone: TimeZone(identifier: "Asia/Riyadh")!) == CalendarDay(year: 2026, month: 10, day: 16))
        #expect(CalendarDay(date: date, timeZone: TimeZone(identifier: "America/New_York")!) == CalendarDay(year: 2026, month: 10, day: 15))
    }

    @Test func ordering() {
        #expect(CalendarDay(year: 2026, month: 1, day: 31) < CalendarDay(year: 2026, month: 2, day: 1))
        #expect(CalendarDay(year: 2025, month: 12, day: 31) < CalendarDay(year: 2026, month: 1, day: 1))
    }

    @Test func startDateIsLocalMidnight() {
        let tz = TimeZone(identifier: "Asia/Tokyo")!
        let start = CalendarDay(year: 2026, month: 10, day: 15).startDate(in: tz)
        #expect(localMinutes(start, tz) == 0)
        #expect(CalendarDay(date: start, timeZone: tz) == CalendarDay(year: 2026, month: 10, day: 15))
    }
}
