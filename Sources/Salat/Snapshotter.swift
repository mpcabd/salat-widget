import AppKit
import SwiftUI
import PrayerKit

/// Developer tool: `Salat --snapshot <dir> [--lang ar|en] [--time HH:mm]` renders every screen to PNG
/// without touching the user's saved settings.
@MainActor
enum Snapshotter {
    static func run(arguments: [String]) {
        guard let i = arguments.firstIndex(of: "--snapshot"), i + 1 < arguments.count else { return }
        let dir = URL(fileURLWithPath: arguments[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lang = value(after: "--lang", in: arguments) ?? "en"

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        AppModel.persistenceEnabled = false
        let model = AppModel.shared
        var s = AppSettings()
        s.language = lang == "ar" ? .arabic : .english
        s.locationMode = .manual
        s.autoMethod = false
        s.method = .dubai
        s.showLastThird = true
        s.hasCompletedOnboarding = true
        s.location = SavedLocation(name: "Dubai", country: "United Arab Emirates", countryCode: "AE",
                                   coordinates: Coordinates(latitude: 25.2048, longitude: 55.2708),
                                   timeZoneID: "Asia/Dubai")
        // Sample entries so the "Your recordings" section isn't empty. Their files don't exist; that's fine for a render.
        s.userAzans = lang == "ar"
            ? [UserAzan(id: "user.sample-mosque", name: "أذان مسجد الحي", fileName: "sample.mp3"),
               UserAzan(id: "user.sample-fajr", name: "أذان الفجر — مسجد الحي", fileName: "sample-fajr.mp3", isFajr: true)]
            : [UserAzan(id: "user.sample-mosque", name: "Neighbourhood mosque", fileName: "sample.mp3"),
               UserAzan(id: "user.sample-fajr", name: "Neighbourhood mosque — Fajr", fileName: "sample-fajr.mp3", isFajr: true)]
        s.fajrAzanSound = "user.sample-fajr"
        model.settings = s
        if let t = value(after: "--time", in: arguments) {
            let parts = t.split(separator: ":").compactMap { Int($0) }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "Asia/Dubai")!
            var c = cal.dateComponents([.year, .month, .day], from: Date())
            c.hour = parts[0]; c.minute = parts[1]; c.second = 17
            model.overrideNow(cal.date(from: c)!)
        }

        let suffix = "-\(lang)"
        render(PopoverView().environment(model).background(Color(nsColor: .windowBackgroundColor)), size: nil, to: dir.appendingPathComponent("popover\(suffix).png"))
        for size in WidgetSize.allCases {
            for style in WidgetStyle.allCases {
                render(WidgetView(size: size, style: style).environment(model).padding(12),
                       size: nil, to: dir.appendingPathComponent("widget-\(size.rawValue)-\(style.rawValue)\(suffix).png"))
            }
        }
        render(TimetableView().environment(model).localized(model).background(Color(nsColor: .windowBackgroundColor)), size: nil,
               to: dir.appendingPathComponent("timetable\(suffix).png"))
        render(WelcomeView().environment(model).localized(model).background(Color(nsColor: .windowBackgroundColor)), size: nil,
               to: dir.appendingPathComponent("welcome\(suffix).png"))
        let tabs: [(String, AnyView)] = [
            ("general", AnyView(GeneralSettings())), ("location", AnyView(LocationSettings())),
            ("calculation", AnyView(CalculationSettings())), ("alerts", AnyView(AlertSettings())),
            ("azan", AnyView(AzanSettings())), ("widget", AnyView(WidgetSettings())), ("about", AnyView(AboutView())),
        ]
        for (name, view) in tabs {
            render(view.environment(model).localized(model).frame(width: 600, height: 560)
                    .background(Color(nsColor: .windowBackgroundColor)), size: nil,
                   to: dir.appendingPathComponent("settings-\(name)\(suffix).png"))
        }
        print("Snapshots written to \(dir.path)")
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private static func render<V: View>(_ view: V, size: CGSize?, to url: URL) {
        let host = NSHostingView(rootView: view)
        let fitting = size ?? host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fitting),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(origin: .zero, size: fitting)
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI settle (async layout, images).
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
