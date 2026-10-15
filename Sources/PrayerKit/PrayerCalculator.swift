import Adhan
import Foundation

/// Computes daily prayer times for a location using the Adhan library.
///
/// Adhan does the astronomy, high-latitude rules, method offsets and rounding. This wrapper adds
/// what Adhan leaves to its callers: imsak, the Ramadan Isha interval, methods it has no preset
/// for, and a fallback for polar day/night.
public struct PrayerCalculator: Sendable {
    public var coordinates: Coordinates
    public var parameters: CalculationParameters
    public var madhab: Madhab
    public var highLatitudeRule: HighLatitudeRule
    public var adjustments: PrayerAdjustments
    public var imsakMinutes: Double

    /// Latitude used as a fallback when the sun never rises or sets (polar day/night).
    static let polarFallbackLatitude = 65.0

    public init(
        coordinates: Coordinates,
        parameters: CalculationParameters,
        madhab: Madhab = .standard,
        highLatitudeRule: HighLatitudeRule = .automatic,
        adjustments: PrayerAdjustments = PrayerAdjustments(),
        imsakMinutes: Double = 10
    ) {
        self.coordinates = coordinates
        self.parameters = parameters
        self.madhab = madhab
        self.highLatitudeRule = highLatitudeRule
        self.adjustments = adjustments
        self.imsakMinutes = imsakMinutes
    }

    public func times(for day: CalendarDay) -> PrayerTimes {
        let params = adhanParameters(for: day)
        // Adhan returns nil when the sun never rises or sets (polar day/night), so retry closer
        // to the equator. Every day has a sunrise and sunset at the equator, so the last try succeeds.
        let fallback = coordinates.latitude >= 0 ? Self.polarFallbackLatitude : -Self.polarFallbackLatitude
        for latitude in [coordinates.latitude, fallback, 0] {
            let c = Adhan.Coordinates(latitude: latitude, longitude: coordinates.longitude)
            if let t = Adhan.PrayerTimes(coordinates: c, date: day.dateComponents, calculationParameters: params),
               let sunnah = Adhan.SunnahTimes(from: t) {
                return PrayerTimes(
                    day: day,
                    imsak: t.fajr.addingTimeInterval(-imsakMinutes * 60),
                    fajr: t.fajr,
                    sunrise: t.sunrise,
                    dhuhr: t.dhuhr,
                    asr: t.asr,
                    maghrib: t.maghrib,
                    isha: t.isha,
                    midnight: sunnah.middleOfTheNight,
                    lastThird: sunnah.lastThirdOfTheNight
                )
            }
        }
        preconditionFailure("Adhan could not compute prayer times at the equator")
    }

    func adhanParameters(for day: CalendarDay) -> Adhan.CalculationParameters {
        var p: Adhan.CalculationParameters
        if let preset = parameters.adhanMethod {
            // Adhan applies the preset's own offsets internally.
            p = preset.params
            p.adjustments = adjustments.adhan
        } else {
            p = Adhan.CalculationMethod.other.params
            p.fajrAngle = parameters.fajrAngle
            p.maghribAngle = parameters.maghribAngle
            p.adjustments = (parameters.methodAdjustments + adjustments).adhan
            switch parameters.isha {
            case .angle(let a): p.ishaAngle = a
            case .minutes(let m): p.ishaInterval = Int(m.rounded())
            }
        }
        if let ramadan = parameters.ishaRamadanMinutes, Self.isRamadan(day) {
            p.ishaInterval = Int(ramadan.rounded())
        }
        p.madhab = madhab.adhan
        p.highLatitudeRule = highLatitudeRule.adhan
        return p
    }

    static func isRamadan(_ day: CalendarDay) -> Bool {
        var greg = Calendar(identifier: .gregorian)
        greg.timeZone = TimeZone(identifier: "UTC")!
        guard let date = greg.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) else {
            return false
        }
        var hijri = Calendar(identifier: .islamicUmmAlQura)
        hijri.timeZone = greg.timeZone
        return hijri.component(.month, from: date) == 9
    }
}

public enum Qibla {
    public static let kaaba = Coordinates(latitude: 21.4224779, longitude: 39.8251832)

    /// Bearing to the Kaaba in degrees clockwise from true north.
    public static func direction(from c: Coordinates) -> Double {
        Adhan.Qibla(coordinates: c.adhan).direction
    }

    /// Great-circle distance to the Kaaba in kilometres (Adhan only provides the bearing).
    public static func distance(from c: Coordinates) -> Double {
        let dLat = (kaaba.latitude - c.latitude) * .pi / 180
        let dLng = (kaaba.longitude - c.longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(c.latitude * .pi / 180) * cos(kaaba.latitude * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return 6371 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
