import AppKit
import PrayerKit
import ServiceManagement

struct PrayerEvent: Identifiable, Hashable {
    let prayer: Prayer
    let date: Date
    let day: CalendarDay
    var id: String { "\(prayer.rawValue)-\(day.year)-\(day.month)-\(day.day)" }
}

enum LocationState: Equatable {
    case idle, locating, denied, failed
}

/// App-wide state: settings, today's times, the 1-second clock, azan triggering and notification scheduling.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    /// Disabled by the snapshot tool so it never overwrites real settings.
    static var persistenceEnabled = true
    @ObservationIgnored private var frozenNow: Date?

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settingsDidChange(from: oldValue)
        }
    }

    private(set) var now = Date()
    /// Stored (not derived from `now`) so views that only care about the date don't re-render every second.
    private(set) var todayDay: CalendarDay
    private(set) var yesterday: PrayerTimes
    private(set) var today: PrayerTimes
    private(set) var tomorrow: PrayerTimes
    var locationState: LocationState = .idle
    var notificationsAuthorized: Bool?

    let azan = AzanPlayer()
    let notifications = NotificationManager()
    let locationService = LocationService()
    @ObservationIgnored var widget: DesktopWidgetController?
    @ObservationIgnored var windowOpener: ((String) -> Void)?

    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var lastTick = Date()
    @ObservationIgnored private var lastLocationRefresh: Date?
    @ObservationIgnored private var rescheduleWork: DispatchWorkItem?
    @ObservationIgnored private var started = false
    /// True between willSleep and didWake. The app keeps running during maintenance (dark) wakes in that
    /// window, but there's no one to hear an azan and no usable audio output.
    @ObservationIgnored private var systemAsleep = false

    /// Azan is only played if we notice the prayer time within this window (e.g. not hours later after sleep).
    static let lateGrace: TimeInterval = 120

    private init() {
        let s = SettingsPersistence.load()
        settings = s
        let placeholder = PrayerCalculator(coordinates: Coordinates(latitude: 21.4225, longitude: 39.8262),
                                           parameters: CalculationMethod.ummAlQura.parameters)
            .times(for: CalendarDay(date: Date(), timeZone: .current))
        todayDay = placeholder.day
        yesterday = placeholder
        today = placeholder
        tomorrow = placeholder
        recompute()
    }

    // MARK: - Derived

    var L: L10n { L10n(arabic: isArabic) }
    var isArabic: Bool { settings.language.resolved == .arabic }
    var timeZone: TimeZone { settings.location?.timeZone ?? .current }
    var hasLocation: Bool { settings.location != nil }

    var fmt: Fmt {
        Fmt(arabic: isArabic, easternDigits: settings.easternArabicNumerals,
            clock: settings.clockStyle, timeZone: timeZone)
    }

    var calculator: PrayerCalculator {
        PrayerCalculator(
            coordinates: settings.location?.coordinates ?? Coordinates(latitude: 21.4225, longitude: 39.8262),
            parameters: settings.calculationParameters,
            madhab: settings.madhab,
            highLatitudeRule: settings.highLatitudeRule,
            adjustments: settings.adjustments
        )
    }

    func times(for day: CalendarDay) -> PrayerTimes { calculator.times(for: day) }

    var events: [PrayerEvent] {
        [yesterday, today, tomorrow].flatMap { t in
            Prayer.allCases.map { PrayerEvent(prayer: $0, date: t.time(for: $0), day: t.day) }
        }.sorted { $0.date < $1.date }
    }

    var nextEvent: PrayerEvent {
        events.first { $0.date > now } ?? PrayerEvent(prayer: .fajr, date: tomorrow.fajr, day: tomorrow.day)
    }

    /// The obligatory prayer whose time we are currently in (nil between sunrise and Dhuhr).
    var currentEvent: PrayerEvent? {
        guard let last = events.last(where: { $0.date <= now }) else { return nil }
        return last.prayer == .sunrise ? nil : last
    }

    var previousEvent: PrayerEvent? { events.last { $0.date <= now } }

    /// 0...1 progress from the previous event to the next.
    var progressToNext: Double {
        guard let prev = previousEvent else { return 0 }
        let total = nextEvent.date.timeIntervalSince(prev.date)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(prev.date) / total))
    }

    func displayName(_ prayer: Prayer, on date: Date) -> String {
        if prayer == .dhuhr && fmt.isFriday(date) { return L.t("prayer.jumuah") }
        return L.t("prayer.\(prayer.rawValue)")
    }

    func arabicName(_ prayer: Prayer, on date: Date) -> String {
        let ar = L10n(arabic: true)
        if prayer == .dhuhr && fmt.isFriday(date) { return ar.t("prayer.jumuah") }
        return ar.t("prayer.\(prayer.rawValue)")
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        notifications.configure(stopTitle: L.t("azan.stop"))
        notifications.onStopAzan = { [weak self] in self?.azan.stop() }
        startTicker()
        observeSystem()
        if settings.locationMode == .automatic { refreshLocation() }
        Task { await refreshNotificationAuthorization(request: settings.hasCompletedOnboarding) }
        rescheduleNotifications()
        widget = DesktopWidgetController(model: self)
        widget?.sync()
        if !settings.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.open("welcome") }
        }
    }

    func open(_ windowID: String) {
        NSApp.activate(ignoringOtherApps: true)
        windowOpener?(windowID)
    }

    private func startTicker() {
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.systemAsleep = true
                self?.azan.stop()
            }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.systemAsleep = false
                self?.systemChanged(wake: true)
            }
        }
        let nc = NotificationCenter.default
        for name in [Notification.Name.NSSystemTimeZoneDidChange, .NSSystemClockDidChange] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemChanged(wake: false) }
            }
        }
    }

    private func systemChanged(wake: Bool) {
        tick()
        recompute()
        rescheduleNotifications()
        if settings.locationMode == .automatic,
           !wake || (lastLocationRefresh.map { Date().timeIntervalSince($0) > 3600 } ?? true) {
            refreshLocation()
        }
    }

    // MARK: - Clock

    private func tick() {
        let previous = lastTick
        let current = Date()
        lastTick = current
        now = current

        let day = CalendarDay(date: current, timeZone: timeZone)
        if day != todayDay { todayDay = day }
        if todayDay != today.day {
            recompute()
            rescheduleNotifications()
        }

        azan.checkStalled(now: current)

        // Fire every event we crossed since the last tick (normally at most one).
        for event in events where event.date > previous && event.date <= current {
            if current.timeIntervalSince(event.date) <= Self.lateGrace { fire(event) }
        }

        // Re-resolve the location every few hours when automatic (travel).
        if settings.locationMode == .automatic,
           let last = lastLocationRefresh, current.timeIntervalSince(last) > 3 * 3600 {
            refreshLocation()
        }
    }

    private func fire(_ event: PrayerEvent) {
        let pref = settings.preference(for: event.prayer)
        guard pref.azan, event.prayer.isObligatory, !systemAsleep else { return }
        playAzan(for: event.prayer)
    }

    func playAzan(for prayer: Prayer?, preview: Bool = false) {
        azan.play(url: azanURL(for: prayer), volume: settings.azanVolume, fadeIn: settings.azanFadeIn,
                  short: settings.shortAzan, prayer: prayer, preview: preview)
    }

    func azanURL(for prayer: Prayer?) -> URL? {
        let id = prayer == .fajr ? settings.fajrAzanSound : settings.azanSound
        if id == AzanSound.customID, let path = settings.customAzanPath,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if id == AzanSound.chimeID { return nil }
        return (AzanSound.sound(id: id) ?? AzanSound.sound(id: AzanSound.defaultID))?.url
    }

    // MARK: - Recompute

    /// Pins the clock (snapshot tool only).
    func overrideNow(_ date: Date) {
        frozenNow = date
        recompute()
    }

    private var clockNow: Date { frozenNow ?? Date() }

    func recompute() {
        let day = CalendarDay(date: clockNow, timeZone: timeZone)
        if day != todayDay { todayDay = day }
        let calc = calculator
        yesterday = calc.times(for: day.adding(days: -1))
        today = calc.times(for: day)
        tomorrow = calc.times(for: day.adding(days: 1))
        now = clockNow
    }

    private func settingsDidChange(from old: AppSettings) {
        if Self.persistenceEnabled { SettingsPersistence.save(settings) }

        let calcChanged = old.location != settings.location
            || old.method != settings.method || old.madhab != settings.madhab
            || old.highLatitudeRule != settings.highLatitudeRule || old.adjustments != settings.adjustments
            || old.calculationParameters != settings.calculationParameters
        if calcChanged { recompute() }

        if old.locationMode != settings.locationMode, settings.locationMode == .automatic {
            refreshLocation()
        }

        if settings.autoMethod, settings.location?.countryCode != nil,
           old.location?.countryCode != settings.location?.countryCode || !old.autoMethod {
            let recommended = CalculationMethod.recommended(forCountryCode: settings.location?.countryCode)
            if settings.method != recommended { settings.method = recommended }
        }

        if old.language != settings.language {
            notifications.configure(stopTitle: L.t("azan.stop"))
        }

        widget?.sync()
        scheduleNotificationRefresh()
    }

    // MARK: - Location

    func refreshLocation() {
        lastLocationRefresh = Date()
        locationState = .locating
        Task {
            do {
                let loc = try await locationService.currentLocation()
                locationState = .idle
                if settings.locationMode == .automatic { settings.location = loc }
            } catch LocationError.denied {
                locationState = .denied
            } catch {
                locationState = .failed
            }
        }
    }

    // MARK: - Notifications

    func refreshNotificationAuthorization(request: Bool) async {
        if request {
            notificationsAuthorized = await notifications.requestAuthorization()
        } else {
            let status = await notifications.authorizationStatus()
            notificationsAuthorized = status == .authorized || status == .provisional
        }
    }

    private func scheduleNotificationRefresh() {
        rescheduleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rescheduleNotifications() }
        rescheduleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func rescheduleNotifications() {
        guard hasLocation else { notifications.reschedule([]); return }
        let calc = calculator
        let place = settings.location?.name ?? ""
        let f = fmt
        var items: [PendingNotification] = []
        let start = CalendarDay(date: Date(), timeZone: timeZone)
        for offset in 0..<4 {
            let t = calc.times(for: start.adding(days: offset))
            for prayer in Prayer.allCases {
                let pref = settings.preference(for: prayer)
                let date = t.time(for: prayer)
                let name = displayName(prayer, on: date)
                let id = "\(prayer.rawValue)-\(t.day.year)-\(t.day.month)-\(t.day.day)"
                if pref.notify {
                    let body = prayer == .sunrise
                        ? L.t("notif.sunriseBody")
                        : L.t("notif.prayerBody").replacingOccurrences(of: "{prayer}", with: name)
                    items.append(PendingNotification(
                        id: id,
                        title: "\(name) · \(f.time(date))",
                        body: place.isEmpty ? body : "\(body) — \(place)",
                        date: date,
                        playsSound: !(pref.azan && prayer.isObligatory)))
                }
                if pref.reminder, settings.reminderMinutes > 0 {
                    let mins = settings.reminderMinutes
                    items.append(PendingNotification(
                        id: id + "-reminder",
                        title: L.t("notif.reminderTitle")
                            .replacingOccurrences(of: "{prayer}", with: name)
                            .replacingOccurrences(of: "{minutes}", with: f.number(mins)),
                        body: L.t("notif.reminderBody").replacingOccurrences(of: "{time}", with: f.time(date)),
                        date: date.addingTimeInterval(-Double(mins) * 60),
                        playsSound: true))
                }
            }
        }
        notifications.reschedule(items)
    }

    func sendTestNotification() {
        let name = displayName(.asr, on: Date())
        notifications.reschedule([])
        notifications.reschedule([PendingNotification(
            id: "test", title: "\(name) · \(fmt.time(Date().addingTimeInterval(3)))",
            body: L.t("notif.prayerBody").replacingOccurrences(of: "{prayer}", with: name),
            date: Date().addingTimeInterval(3), playsSound: true)])
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.rescheduleNotifications() }
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Salat: launch-at-login change failed: \(error)")
            }
        }
    }
}
