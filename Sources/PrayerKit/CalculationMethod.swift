import Adhan
import Foundation

public enum CalculationMethod: String, CaseIterable, Codable, Sendable, Identifiable {
    case muslimWorldLeague
    case isna
    case egyptian
    case ummAlQura
    case karachi
    case dubai
    case gulf
    case kuwait
    case qatar
    case moonsightingCommittee
    case singapore
    case jakim
    case kemenag
    case turkey
    case tehran
    case jafari
    case france
    case russia
    case morocco
    case algeria
    case tunisia
    case custom

    public var id: String { rawValue }

    /// The matching Adhan preset, if Adhan ships one.
    var adhanMethod: Adhan.CalculationMethod? {
        switch self {
        case .muslimWorldLeague: .muslimWorldLeague
        case .isna: .northAmerica
        case .egyptian: .egyptian
        case .ummAlQura: .ummAlQura
        case .karachi: .karachi
        case .dubai: .dubai
        case .kuwait: .kuwait
        case .qatar: .qatar
        case .moonsightingCommittee: .moonsightingCommittee
        case .singapore: .singapore
        case .turkey: .turkey
        case .tehran: .tehran
        default: nil
        }
    }

    /// Parameters for the built-in methods. `.custom` returns MWL angles as a starting point.
    public var parameters: CalculationParameters {
        if let adhanMethod {
            var p = CalculationParameters(adhanPreset: self, adhanMethod)
            // Adhan leaves the Ramadan Isha interval to the caller.
            if self == .ummAlQura { p.ishaRamadanMinutes = 120 }
            return p
        }
        // Methods Adhan has no preset for, built on its `.other` parameters.
        switch self {
        case .gulf:
            return .init(fajrAngle: 19.5, isha: .minutes(90))
        case .jakim, .kemenag:
            return .init(fajrAngle: 20, isha: .angle(18))
        case .jafari:
            return .init(fajrAngle: 16, isha: .angle(14), maghribAngle: 4)
        case .france:
            return .init(fajrAngle: 12, isha: .angle(12))
        case .russia:
            return .init(fajrAngle: 16, isha: .angle(15))
        case .morocco:
            return .init(fajrAngle: 19, isha: .angle(17),
                         methodAdjustments: .init(sunrise: -3, dhuhr: 5, maghrib: 5))
        case .algeria:
            return .init(fajrAngle: 18, isha: .angle(17))
        case .tunisia:
            return .init(fajrAngle: 18, isha: .angle(18))
        default:
            return .init(fajrAngle: 18, isha: .angle(17))
        }
    }

    /// A sensible default method for an ISO 3166-1 alpha-2 country code.
    public static func recommended(forCountryCode code: String?) -> CalculationMethod {
        guard let code = code?.uppercased() else { return .muslimWorldLeague }
        switch code {
        case "SA", "YE": return .ummAlQura
        case "AE": return .dubai
        case "KW": return .kuwait
        case "QA": return .qatar
        case "BH", "OM": return .gulf
        case "EG", "SD", "LY", "SY", "LB", "IQ", "JO", "PS": return .egyptian
        case "PK", "IN", "BD", "AF": return .karachi
        case "US", "CA": return .isna
        case "GB", "IE": return .moonsightingCommittee
        case "SG", "BN": return .singapore
        case "MY": return .jakim
        case "ID": return .kemenag
        case "TR", "AZ": return .turkey
        case "IR": return .tehran
        case "FR", "BE": return .france
        case "RU": return .russia
        case "MA": return .morocco
        case "DZ": return .algeria
        case "TN": return .tunisia
        default: return .muslimWorldLeague
        }
    }
}
