import Foundation

/// A playable azan. The bundled recordings are listed in `AzanCatalog.swift`.
struct AzanSound: Identifiable, Hashable {
    let id: String
    let nameEN: String
    let nameAR: String
    let fileName: String?
    /// A Fajr azan (with “الصلاة خير من النوم”). Offered only for Fajr.
    let isFajr: Bool
    let credit: String
    let license: String
    let sourceURL: String?

    init(id: String, nameEN: String, nameAR: String, file: String?, fajr: Bool = false,
         credit: String = "", license: String = "", source: String? = nil) {
        self.id = id
        self.nameEN = nameEN
        self.nameAR = nameAR
        self.fileName = file
        self.isFajr = fajr
        self.credit = credit
        self.license = license
        self.sourceURL = source
    }

    static let chimeID = "chime"

    static let chime = AzanSound(id: chimeID, nameEN: "Gentle chime", nameAR: "تنبيه لطيف",
                                 file: nil, credit: "macOS")

    static let builtIn: [AzanSound] = AzanCatalog.recordings + [chime]

    /// Sounds offered for the given prayer: Fajr gets everything, other prayers skip Fajr-only recordings.
    static func choices(fajr: Bool) -> [AzanSound] {
        builtIn.filter { fajr || !$0.isFajr }
    }

    static func defaultID(fajr: Bool) -> String {
        fajr ? AzanCatalog.defaultFajrID : AzanCatalog.defaultID
    }

    static func sound(id: String) -> AzanSound? { builtIn.first { $0.id == id } }

    /// Maps a saved sound ID to one that's still offered for that prayer, so bundled recordings removed
    /// in later versions, and user recordings that were deleted or marked as Fajr, fall back to the default.
    static func validID(_ id: String, fajr: Bool, user: [UserAzan] = []) -> String {
        if choices(fajr: fajr).contains(where: { $0.id == id }) { return id }
        if user.contains(where: { $0.id == id && (fajr || !$0.isFajr) }) { return id }
        return defaultID(fajr: fajr)
    }

    func name(arabic: Bool) -> String { arabic ? nameAR : nameEN }

    var url: URL? {
        guard let fileName else { return nil }
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        return Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Audio")
            ?? Bundle.main.url(forResource: base, withExtension: ext)
    }
}
