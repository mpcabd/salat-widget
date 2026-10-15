import SwiftUI
import PrayerKit
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, location, calculation, alerts, azan, widget, about
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .location: return "location"
        case .calculation: return "function"
        case .alerts: return "bell.badge"
        case .azan: return "speaker.wave.2"
        case .widget: return "rectangle.on.rectangle"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: SettingsTab = .general

    var body: some View {
        let L = model.L
        TabView(selection: $tab) {
            ForEach(SettingsTab.allCases) { t in
                content(for: t)
                    .tabItem { Label(L.t("tab.\(t.rawValue)"), systemImage: t.symbol) }
                    .tag(t)
            }
        }
        .frame(width: 600, height: 560)
        .navigationTitle(L.t("settings.title"))
    }

    @ViewBuilder
    private func content(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettings()
        case .location: LocationSettings()
        case .calculation: CalculationSettings()
        case .alerts: AlertSettings()
        case .azan: AzanSettings()
        case .widget: WidgetSettings()
        case .about: AboutView()
        }
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = false

    var body: some View {
        @Bindable var model = model
        let L = model.L
        Form {
            Section(L.t("general.language")) {
                Picker(L.t("general.language"), selection: $model.settings.language) {
                    Text(L.t("language.system")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("العربية").tag(AppLanguage.arabic)
                }
                if model.isArabic {
                    Toggle(L.t("general.easternNumerals"), isOn: $model.settings.easternArabicNumerals)
                }
                Picker(L.t("general.clock"), selection: $model.settings.clockStyle) {
                    Text(L.t("clock.system")).tag(ClockStyle.system)
                    Text(L.t("clock.12")).tag(ClockStyle.twelveHour)
                    Text(L.t("clock.24")).tag(ClockStyle.twentyFourHour)
                }
            }

            Section(L.t("general.menuBar")) {
                Picker(L.t("general.menuBarStyle"), selection: $model.settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { s in
                        Text(L.t("menubar.\(s.rawValue)")).tag(s)
                    }
                }
                Toggle(L.t("general.menuBarSeconds"), isOn: $model.settings.menuBarSeconds)
                    .disabled(model.settings.menuBarStyle == .iconOnly || model.settings.menuBarStyle == .nameAndTime)
            }

            Section(L.t("general.display")) {
                Stepper(value: $model.settings.hijriOffset, in: -3...3) {
                    LabeledContent(L.t("general.hijriOffset")) {
                        Text(model.fmt.hijri(model.todayDay.startDate(in: model.timeZone).addingTimeInterval(43200), offsetDays: model.settings.hijriOffset))
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(L.t("general.showImsak"), isOn: $model.settings.showImsak)
                Toggle(L.t("general.showMidnight"), isOn: $model.settings.showMidnight)
                Toggle(L.t("general.showLastThird"), isOn: $model.settings.showLastThird)
            }

            Section {
                Toggle(L.t("general.launchAtLogin"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        if model.launchAtLogin != v { model.launchAtLogin = v }
                    }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = model.launchAtLogin }
    }
}

// MARK: - Location

struct LocationSettings: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [SavedLocation] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var manualLat = ""
    @State private var manualLng = ""
    @State private var manualTZ = TimeZone.current.identifier

    var body: some View {
        @Bindable var model = model
        let L = model.L
        let fmt = model.fmt
        Form {
            Section {
                Picker(L.t("location.mode"), selection: $model.settings.locationMode) {
                    Text(L.t("location.automatic")).tag(LocationMode.automatic)
                    Text(L.t("location.manual")).tag(LocationMode.manual)
                }
                .pickerStyle(.segmented)

                if let loc = model.settings.location {
                    LabeledContent(L.t("location.current")) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(loc.displayName).fontWeight(.medium)
                            Text("\(fmt.number(loc.coordinates.latitude, fractionDigits: 4)), \(fmt.number(loc.coordinates.longitude, fractionDigits: 4)) · \(loc.timeZoneID)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    let q = Qibla.direction(from: loc.coordinates)
                    LabeledContent(L.t("qibla")) {
                        HStack(spacing: 8) {
                            QiblaDial(bearing: q).frame(width: 34, height: 34)
                            VStack(alignment: .trailing) {
                                Text("\(fmt.degrees(q)) \(L.t(compassKey(q)))")
                                Text(L.t("qibla.distance").replacingOccurrences(
                                    of: "{km}", with: fmt.number(Int(Qibla.distance(from: loc.coordinates)))))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text(L.t("location.none")).foregroundStyle(.secondary)
                }

                if model.settings.locationMode == .automatic {
                    HStack {
                        Button(L.t("location.update")) { model.refreshLocation() }
                        switch model.locationState {
                        case .locating: ProgressView().controlSize(.small)
                        case .denied: Text(L.t("location.denied")).font(.caption).foregroundStyle(.red)
                        case .failed: Text(L.t("location.failed")).font(.caption).foregroundStyle(.orange)
                        case .idle: EmptyView()
                        }
                        Spacer()
                        if model.locationState == .denied {
                            Button(L.t("location.openPrivacy")) {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                            }
                        }
                    }
                }
            }

            if model.settings.locationMode == .manual {
                Section(L.t("location.search")) {
                    HStack {
                        TextField(L.t("location.searchPlaceholder"), text: $query)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { search() }
                            .onChange(of: query) { _, _ in debounceSearch() }
                        if searching { ProgressView().controlSize(.small) }
                    }
                    ForEach(results, id: \.self) { r in
                        Button {
                            model.settings.location = r
                            results = []
                            query = ""
                        } label: {
                            HStack {
                                Image(systemName: "mappin.circle.fill").foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading) {
                                    Text(r.name)
                                    if let c = r.country, !c.isEmpty {
                                        Text(c).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(r.timeZoneID).font(.caption).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section(L.t("location.coordinates")) {
                    TextField(L.t("location.latitude"), text: $manualLat)
                    TextField(L.t("location.longitude"), text: $manualLng)
                    Picker(L.t("location.timezone"), selection: $manualTZ) {
                        ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                    }
                    Button(L.t("location.applyCoordinates")) {
                        guard let lat = Double(manualLat.replacingOccurrences(of: ",", with: ".")),
                              let lng = Double(manualLng.replacingOccurrences(of: ",", with: ".")),
                              abs(lat) <= 90, abs(lng) <= 180 else { return }
                        model.settings.location = SavedLocation(
                            name: String(format: "%.3f, %.3f", lat, lng), country: nil, countryCode: nil,
                            coordinates: Coordinates(latitude: lat, longitude: lng), timeZoneID: manualTZ)
                    }
                    .disabled(Double(manualLat) == nil || Double(manualLng) == nil)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if let loc = model.settings.location {
                manualLat = String(format: "%.4f", loc.coordinates.latitude)
                manualLng = String(format: "%.4f", loc.coordinates.longitude)
                manualTZ = loc.timeZoneID
            }
        }
    }

    private func debounceSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            search()
        }
    }

    private func search() {
        let q = query
        searching = true
        Task {
            let r = await LocationService.search(q)
            if q == query { results = r }
            searching = false
        }
    }

    private func compassKey(_ deg: Double) -> String {
        let dirs = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
        return "compass." + dirs[Int((deg + 22.5) / 45) % 8]
    }
}

struct QiblaDial: View {
    let bearing: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1)
            Text("N").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
                .offset(y: -11)
            Image(systemName: "location.north.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .rotationEffect(.degrees(bearing))
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - Calculation

struct CalculationSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let L = model.L
        let fmt = model.fmt
        Form {
            Section(L.t("calc.method")) {
                Toggle(L.t("calc.autoMethod"), isOn: $model.settings.autoMethod)
                Picker(L.t("calc.method"), selection: $model.settings.method) {
                    ForEach(CalculationMethod.allCases) { m in
                        Text(L.t("method.\(m.rawValue)")).tag(m)
                    }
                }
                .disabled(model.settings.autoMethod)
                Text(methodSummary(model.settings.calculationParameters))
                    .font(.caption).foregroundStyle(.secondary)

                if model.settings.method == .custom {
                    Stepper(value: $model.settings.customFajrAngle, in: 10...22, step: 0.5) {
                        LabeledContent(L.t("calc.fajrAngle"), value: fmt.number(model.settings.customFajrAngle, fractionDigits: 1) + "°")
                    }
                    Picker(L.t("calc.ishaRule"), selection: $model.settings.customIshaMode) {
                        Text(L.t("calc.ishaByAngle")).tag(CustomIshaMode.angle)
                        Text(L.t("calc.ishaByMinutes")).tag(CustomIshaMode.minutes)
                    }
                    if model.settings.customIshaMode == .angle {
                        Stepper(value: $model.settings.customIshaAngle, in: 10...22, step: 0.5) {
                            LabeledContent(L.t("calc.ishaAngle"), value: fmt.number(model.settings.customIshaAngle, fractionDigits: 1) + "°")
                        }
                    } else {
                        Stepper(value: $model.settings.customIshaMinutes, in: 30...180, step: 5) {
                            LabeledContent(L.t("calc.ishaMinutes"), value: fmt.number(Int(model.settings.customIshaMinutes)))
                        }
                    }
                }
            }

            Section(L.t("calc.juristic")) {
                Picker(L.t("calc.asr"), selection: $model.settings.madhab) {
                    Text(L.t("madhab.standard")).tag(Madhab.standard)
                    Text(L.t("madhab.hanafi")).tag(Madhab.hanafi)
                }
                Picker(L.t("calc.highLat"), selection: $model.settings.highLatitudeRule) {
                    ForEach(HighLatitudeRule.allCases) { r in
                        Text(L.t("highlat.\(r.rawValue)")).tag(r)
                    }
                }
                Text(L.t("calc.highLatHelp")).font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(Prayer.allCases) { p in
                    let v = model.settings.adjustments[p]
                    HStack {
                        Label(L.t("prayer.\(p.rawValue)"), systemImage: p.symbol)
                        Spacer()
                        Text(v == 0 ? "—" : (v > 0 ? "+" : "−") + fmt.number(abs(v)) + " " + L.t("unit.min"))
                            .monospacedDigit()
                            .foregroundStyle(v == 0 ? .secondary : .primary)
                        Stepper("", value: Binding(
                            get: { model.settings.adjustments[p] },
                            set: { model.settings.adjustments[p] = $0 }), in: -30...30)
                            .labelsHidden()
                    }
                }
                Button(L.t("calc.resetAdjustments")) { model.settings.adjustments = PrayerAdjustments() }
                    .disabled(model.settings.adjustments == PrayerAdjustments())
            } header: {
                Text(L.t("calc.adjustments"))
            } footer: {
                Text(L.t("calc.adjustmentsHelp")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func methodSummary(_ p: CalculationParameters) -> String {
        let L = model.L, fmt = model.fmt
        var parts = ["\(L.t("prayer.fajr")) \(fmt.number(p.fajrAngle, fractionDigits: p.fajrAngle.rounded() == p.fajrAngle ? 0 : 1))°"]
        switch p.isha {
        case .angle(let a):
            parts.append("\(L.t("prayer.isha")) \(fmt.number(a, fractionDigits: a.rounded() == a ? 0 : 1))°")
        case .minutes(let m):
            parts.append("\(L.t("prayer.isha")) \(L.t("calc.minutesAfterMaghrib").replacingOccurrences(of: "{m}", with: fmt.number(Int(m))))")
        }
        if let a = p.maghribAngle {
            parts.append("\(L.t("prayer.maghrib")) \(fmt.number(a, fractionDigits: 1))°")
        }
        if p.seasonalTwilight { parts.append(L.t("calc.seasonal")) }
        let offsets = Prayer.allCases.compactMap { pr -> String? in
            let m = p.methodAdjustments[pr]
            return m == 0 ? nil : "\(L.t("prayer.\(pr.rawValue)")) \(m > 0 ? "+" : "−")\(fmt.number(abs(m)))"
        }
        if !offsets.isEmpty { parts.append(L.t("calc.methodOffsets") + " " + offsets.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Alerts

struct AlertSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let L = model.L
        Form {
            Section {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow {
                        Text(L.t("alerts.prayer")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(L.t("alerts.notification")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .gridColumnAlignment(.center)
                        Text(L.t("alerts.azan")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .gridColumnAlignment(.center)
                        Text(L.t("alerts.reminder")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .gridColumnAlignment(.center)
                    }
                    Divider()
                    ForEach(Prayer.allCases) { p in
                        GridRow {
                            Label(L.t("prayer.\(p.rawValue)"), systemImage: p.symbol)
                            Toggle("", isOn: binding(p, \.notify)).labelsHidden()
                            if p.isObligatory {
                                Toggle("", isOn: binding(p, \.azan)).labelsHidden()
                            } else {
                                Text("—").foregroundStyle(.tertiary)
                            }
                            Toggle("", isOn: binding(p, \.reminder)).labelsHidden()
                        }
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.vertical, 4)

                HStack {
                    Button(L.t("alerts.allOn")) { setAll(true) }
                    Button(L.t("alerts.allOff")) { setAll(false) }
                }
            } header: {
                Text(L.t("alerts.perPrayer"))
            }

            Section {
                Stepper(value: $model.settings.reminderMinutes, in: 1...60) {
                    LabeledContent(L.t("alerts.reminderBefore"),
                                   value: "\(model.fmt.number(model.settings.reminderMinutes)) \(L.t("unit.min"))")
                }
            }

            Section(L.t("alerts.permission")) {
                HStack {
                    switch model.notificationsAuthorized {
                    case .some(true):
                        Label(L.t("alerts.permissionGranted"), systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    case .some(false):
                        Label(L.t("alerts.permissionDenied"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    case .none:
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    if model.notificationsAuthorized == false {
                        Button(L.t("alerts.request")) {
                            Task { await model.refreshNotificationAuthorization(request: true) }
                        }
                        Button(L.t("alerts.openSettings")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                        }
                    }
                    Button(L.t("alerts.test")) { model.sendTestNotification() }
                }
            }
        }
        .formStyle(.grouped)
        .task { await model.refreshNotificationAuthorization(request: false) }
    }

    private func binding(_ p: Prayer, _ kp: WritableKeyPath<PrayerPreference, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings.preference(for: p)[keyPath: kp] },
            set: { v in
                var pref = model.settings.preference(for: p)
                pref[keyPath: kp] = v
                model.settings.setPreference(pref, for: p)
            })
    }

    private func setAll(_ on: Bool) {
        for p in Prayer.allCases where p.isObligatory {
            model.settings.setPreference(PrayerPreference(notify: on, azan: on, reminder: model.settings.preference(for: p).reminder), for: p)
        }
    }
}

// MARK: - Azan

struct AzanSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let L = model.L
        Form {
            Section(L.t("azan.sound")) {
                soundPicker(L.t("azan.defaultSound"), selection: $model.settings.azanSound, prayer: .dhuhr)
                soundPicker(L.t("azan.fajrSound"), selection: $model.settings.fajrAzanSound, prayer: .fajr)

                LabeledContent(L.t("azan.customFile")) {
                    HStack {
                        Text(model.settings.customAzanPath.map { ($0 as NSString).lastPathComponent } ?? L.t("azan.noFile"))
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button(L.t("azan.choose")) { chooseFile() }
                    }
                }
            }

            Section(L.t("azan.playback")) {
                LabeledContent(L.t("azan.volume")) {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $model.settings.azanVolume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 260)
                }
                Toggle(L.t("azan.fadeIn"), isOn: $model.settings.azanFadeIn)
                Toggle(L.t("azan.short"), isOn: $model.settings.shortAzan)
                Text(L.t("azan.shortHelp")).font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button {
                        if model.azan.isPlaying { model.azan.stop() } else { model.playAzan(for: .dhuhr) }
                    } label: {
                        Label(model.azan.isPlaying ? L.t("azan.stop") : L.t("azan.testFull"),
                              systemImage: model.azan.isPlaying ? "stop.fill" : "play.fill")
                    }
                    Spacer()
                }
                Text(L.t("azan.note")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func soundPicker(_ title: String, selection: Binding<String>, prayer: Prayer) -> some View {
        let L = model.L
        return HStack {
            Picker(title, selection: selection) {
                ForEach(AzanSound.builtIn) { s in
                    Text(s.name(arabic: model.isArabic)).tag(s.id)
                }
                if model.settings.customAzanPath != nil {
                    Divider()
                    Text(L.t("azan.custom")).tag(AzanSound.customID)
                }
            }
            Button {
                if model.azan.isPlaying && model.azan.isPreview && model.azan.playingPrayer == prayer {
                    model.azan.stop()
                } else {
                    model.playAzan(for: prayer, preview: true)
                }
            } label: {
                Image(systemName: model.azan.isPlaying && model.azan.isPreview && model.azan.playingPrayer == prayer
                      ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help(L.t("azan.preview"))
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            // Copy into Application Support so the file keeps working if the original moves.
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Salat", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent("custom-azan." + url.pathExtension)
            try? FileManager.default.removeItem(at: dest)
            let path = (try? FileManager.default.copyItem(at: url, to: dest)) != nil ? dest.path : url.path
            model.settings.customAzanPath = path
            model.settings.azanSound = AzanSound.customID
        }
    }
}

// MARK: - Widget

struct WidgetSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let L = model.L
        Form {
            Section {
                Toggle(L.t("widget.enable"), isOn: $model.settings.widgetEnabled)
                Picker(L.t("widget.size"), selection: $model.settings.widgetSize) {
                    ForEach(WidgetSize.allCases) { Text(L.t("widget.size.\($0.rawValue)")).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker(L.t("widget.style"), selection: $model.settings.widgetStyle) {
                    ForEach(WidgetStyle.allCases) { Text(L.t("widget.style.\($0.rawValue)")).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(L.t("widget.floating"), isOn: $model.settings.widgetFloating)
                Text(L.t("widget.help")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L.t("widget.preview")) {
                HStack {
                    Spacer()
                    WidgetView(size: model.settings.widgetSize, style: model.settings.widgetStyle)
                        .environment(model)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

struct AboutView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let L = model.L
        ScrollView {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 96, height: 96)
                Text(L.t("app.name")).font(.title.bold())
                Text(L.t("about.tagline")).foregroundStyle(.secondary)
                Text("\(L.t("about.version")) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.caption).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("about.credits")).font(.headline)
                    ForEach(AzanSound.builtIn.filter { $0.fileName != nil }) { s in
                        HStack(alignment: .firstTextBaseline) {
                            Text("•")
                            VStack(alignment: .leading) {
                                Text(s.name(arabic: model.isArabic)).fontWeight(.medium)
                                HStack(spacing: 4) {
                                    Text("\(s.credit) — \(s.license)")
                                    if let src = s.sourceURL, let url = URL(string: src) {
                                        Link(L.t("about.source"), destination: url)
                                    }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text(L.t("about.calcNote")).font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                }
                .frame(maxWidth: 460, alignment: .leading)
                .padding()
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}
