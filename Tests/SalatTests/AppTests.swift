import Foundation
import PrayerKit
@testable import Salat
import Testing

private let riyadh = TimeZone(identifier: "Asia/Riyadh")!

/// 2026-10-16 05:07:09 in Riyadh (a Friday).
private let fridayMorning = Date(timeIntervalSince1970: 1_792_116_429)

@Suite struct FormattingTests {
    let en = Fmt(arabic: false, easternDigits: true, clock: .twentyFourHour, timeZone: riyadh)
    let ar = Fmt(arabic: true, easternDigits: true, clock: .twentyFourHour, timeZone: riyadh)
    let arLatin = Fmt(arabic: true, easternDigits: false, clock: .twentyFourHour, timeZone: riyadh)

    @Test func digits() {
        #expect(en.number(1234) == "1234")
        #expect(ar.number(1234) == "١٢٣٤")
        #expect(arLatin.number(1234) == "1234")
        #expect(ar.degrees(118.9) == "١١٩°")
    }

    @Test func timeHonoursTimeZoneAndClockStyle() {
        #expect(en.time(fridayMorning) == "05:07")
        #expect(ar.time(fridayMorning) == "٠٥:٠٧")
        #expect(en.timeParts(fridayMorning).period == nil)

        let twelve = Fmt(arabic: false, easternDigits: false, clock: .twelveHour, timeZone: riyadh)
        let parts = twelve.timeParts(fridayMorning)
        #expect(parts.time == "5:07")
        #expect(parts.period != nil)
    }

    @Test func countdowns() {
        #expect(en.clockCountdown(26 * 60 + 43) == "0:26:43")
        #expect(en.clockCountdown(-5) == "0:00:00")
        #expect(en.shortCountdown(83 * 60) == "1h 23m")
        #expect(en.shortCountdown(60 * 60) == "1h")
        #expect(en.shortCountdown(59) == "1m") // rounds up
        #expect(en.shortCountdown(90, seconds: true) == "0:01:30")
        #expect(ar.shortCountdown(83 * 60) == "١ س ٢٣ د")
        #expect(ar.shortCountdown(5 * 60) == "٥ د")
    }

    @Test func fridayAndHijri() {
        #expect(en.isFriday(fridayMorning))
        #expect(!en.isFriday(fridayMorning.addingTimeInterval(86400)))
        #expect(en.hijri(fridayMorning, offsetDays: 0).hasSuffix(" AH"))
        #expect(ar.hijri(fridayMorning, offsetDays: 0).hasSuffix(" هـ"))
        #expect(!en.hijri(fridayMorning, offsetDays: 0, includeYear: false).hasSuffix(" AH"))
        // Jumada al-Ula 1448. No Hijri month is longer than 30 days, so the offset must move the month.
        #expect(en.hijriMonth(fridayMorning, offsetDays: 0) == 5)
        #expect(en.hijriMonth(fridayMorning, offsetDays: 30) != 5)
        #expect(en.hijriMonth(fridayMorning, offsetDays: -30) != 5)
    }
}

@Suite struct SettingsTests {
    @Test func defaults() {
        let s = AppSettings()
        for prayer in Prayer.allCases {
            let pref = s.preference(for: prayer)
            #expect(pref.notify == prayer.isObligatory, "\(prayer)")
            #expect(pref.azan == prayer.isObligatory, "\(prayer)")
            #expect(!pref.reminder, "\(prayer)")
        }
        #expect(s.calculationParameters == CalculationMethod.muslimWorldLeague.parameters)
    }

    @Test func setPreference() {
        var s = AppSettings()
        s.setPreference(PrayerPreference(notify: false, azan: false, reminder: true), for: .asr)
        #expect(s.preference(for: .asr) == PrayerPreference(notify: false, azan: false, reminder: true))
        // Missing entries fall back to the defaults.
        s.preferences = [:]
        #expect(s.preference(for: .fajr) == AppSettings.defaultPreferences["fajr"])
    }

    @Test func customCalculationParameters() {
        var s = AppSettings()
        s.method = .custom
        s.customFajrAngle = 16
        s.customIshaMode = .minutes
        s.customIshaMinutes = 75
        #expect(s.calculationParameters.fajrAngle == 16)
        #expect(s.calculationParameters.isha == .minutes(75))
        s.customIshaMode = .angle
        s.customIshaAngle = 15
        #expect(s.calculationParameters.isha == .angle(15))
    }

    @Test func roundTrip() throws {
        var s = AppSettings()
        s.language = .arabic
        s.method = .dubai
        s.reminderMinutes = 15
        s.widgetOriginX = 120
        s.location = SavedLocation(name: "Riyadh", country: "Saudi Arabia", countryCode: "SA",
                                   coordinates: Coordinates(latitude: 24.71, longitude: 46.67),
                                   timeZoneID: "Asia/Riyadh")
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
    }

    @Test func tolerantDecoding() throws {
        // Unknown keys, wrong types and missing keys must not wipe the rest of the settings.
        let json = #"{"language": "arabic", "reminderMinutes": "oops", "method": "notAMethod", "future": 1}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(s.language == .arabic)
        #expect(s.reminderMinutes == AppSettings().reminderMinutes)
        #expect(s.method == AppSettings().method)
        #expect(s.preferences == AppSettings.defaultPreferences)
    }

    @Test func savedLocation() {
        var loc = SavedLocation(name: "Riyadh", country: "Saudi Arabia", countryCode: "SA",
                                coordinates: Coordinates(latitude: 24.71, longitude: 46.67),
                                timeZoneID: "Asia/Riyadh")
        #expect(loc.displayName == "Riyadh, Saudi Arabia")
        #expect(loc.timeZone == riyadh)
        loc.country = ""
        loc.timeZoneID = "Not/AZone"
        #expect(loc.displayName == "Riyadh")
        #expect(loc.timeZone == .current)
    }

    @Test func explicitLanguageIsNotResolvedFromSystem() {
        #expect(AppLanguage.arabic.resolved == .arabic)
        #expect(AppLanguage.english.resolved == .english)
        #expect(AppLanguage.system.resolved != .system)
    }
}

@Suite struct LocalizationTests {
    @Test func prayerNamesInBothLanguages() {
        let keys = Prayer.allCases.map { "prayer.\($0.rawValue)" } + ["prayer.jumuah"]
        for key in keys {
            let en = L10n(arabic: false).t(key), ar = L10n(arabic: true).t(key)
            #expect(en != key && ar != key && en != ar, "\(key)")
        }
        #expect(L10n(arabic: false).t("prayer.fajr") == "Fajr")
        #expect(L10n(arabic: true).t("prayer.fajr") == "الفجر")
    }
}

@Suite struct AzanSoundTests {
    @Test func catalogue() {
        let ids = AzanSound.builtIn.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(AzanSound.sound(id: AzanSound.defaultID) != nil)
        #expect(AzanSound.sound(id: AzanSound.chimeID)?.fileName == nil)
        #expect(AzanSound.sound(id: "missing") == nil)
        let fakhry = AzanSound.sound(id: "fakhry")!
        #expect(fakhry.name(arabic: false) == fakhry.nameEN)
        #expect(fakhry.name(arabic: true) == fakhry.nameAR)
    }

    @Test func bundledFilesExist() {
        let audio = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Audio")
        for sound in AzanSound.builtIn {
            guard let file = sound.fileName else { continue }
            #expect(FileManager.default.fileExists(atPath: audio.appendingPathComponent(file).path), "\(file)")
        }
    }
}

@Suite struct SkyPhaseTests {
    @Test func phasesFollowTheDay() {
        let t = PrayerCalculator(coordinates: Coordinates(latitude: 24.71, longitude: 46.67),
                                 parameters: CalculationMethod.ummAlQura.parameters)
            .times(for: CalendarDay(year: 2026, month: 10, day: 15))
        func phase(_ d: Date, _ minutes: Double) -> SkyPhase { .at(d.addingTimeInterval(minutes * 60), today: t) }
        #expect(phase(t.fajr, -10) == .night)
        #expect(phase(t.fajr, 1) == .dawn)
        #expect(phase(t.sunrise, 1) == .morning)
        #expect(phase(t.dhuhr, 0) == .midday)
        #expect(phase(t.asr, 1) == .afternoon)
        #expect(phase(t.maghrib, 0) == .sunset)
        #expect(phase(t.maghrib, 20) == .dusk)
        #expect(phase(t.isha, 30) == .night)
    }

    @Test func seededRandomIsDeterministicAndInRange() {
        var a = SeededRandom(seed: 42), b = SeededRandom(seed: 42)
        for _ in 0..<100 {
            let x = a.next()
            #expect(x == b.next())
            #expect((0..<1).contains(x))
        }
    }
}
