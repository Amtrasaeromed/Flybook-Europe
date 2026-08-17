import Foundation

enum FlightCategory: String, Codable, Hashable {
    case vfr = "VFR"
    case mvfr = "MVFR"
    case ifr = "IFR"
    case lifr = "LIFR"
    case unavailable = "N/A"

    var severity: Int {
        switch self {
        case .vfr: return 1
        case .mvfr: return 2
        case .ifr: return 3
        case .lifr: return 4
        case .unavailable: return 0
        }
    }
}

struct AirportReference: Identifiable, Hashable {
    var id: String { icao }
    let icao: String
    let name: String
    let latitude: Double
    let longitude: Double
    let elevationFeet: Double
    let timeZone: TimeZone
    var referenceRunway: String? = nil
    var country: String = ""
}

enum DestinationTimeZone {
    static let edfz = TimeZone(identifier: "Europe/Berlin")!
}

extension Airport {
    var sharedReference: AirportReference {
        AirportReference(
            icao: icao,
            name: name,
            latitude: latitude,
            longitude: longitude,
            elevationFeet: Double(elevationFeet),
            timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current,
            referenceRunway: referenceRunway,
            country: countryCode
        )
    }
}
