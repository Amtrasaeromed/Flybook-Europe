import Foundation
import SwiftUI

enum AlpineFoehnLevel: Int, Comparable {
    case none = 0
    case yellow = 1
    case orange = 2
    case red = 3

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var color: Color {
        switch self {
        case .none: return .clear
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        }
    }

    var title: String {
        switch self {
        case .none: return "Kein Föhnsignal"
        case .yellow: return "Föhntendenz"
        case .orange: return "Föhn wahrscheinlich"
        case .red: return "Starke Föhn-/Lee-Situation"
        }
    }
}

struct AlpineFoehnWarning {
    let level: AlpineFoehnLevel
    let pressureDifferenceHPA: Double
    let flowName: String
    let explanation: String
}

@MainActor
final class AlpineFoehnViewModel: ObservableObject {
    @Published private var northForecast: EDFZForecast?
    @Published private var southForecast: EDFZForecast?
    @Published private(set) var errorMessage: String?

    private let northReference = AirportReference(
        icao: "LSZH-REF", name: "Alpennordseite",
        latitude: 47.3769, longitude: 8.5417,
        elevationFeet: 1416,
        timeZone: TimeZone(identifier: "Europe/Zurich")!
    )
    private let southReference = AirportReference(
        icao: "LSZL-REF", name: "Alpensüdseite",
        latitude: 46.169, longitude: 8.795,
        elevationFeet: 650,
        timeZone: TimeZone(identifier: "Europe/Zurich")!
    )

    func load(
        ifRelevant airports: [AirportReference],
        forceRefresh: Bool = false
    ) async {
        guard airports.contains(where: isNearAlps) else {
            northForecast = nil
            southForecast = nil
            errorMessage = nil
            return
        }
        do {
            async let north = EDFZWeatherService.shared.metNorwayForecast(
                airport: northReference,
                forceRefresh: forceRefresh
            )
            async let south = EDFZWeatherService.shared.metNorwayForecast(
                airport: southReference,
                forceRefresh: forceRefresh
            )
            northForecast = try await north
            southForecast = try await south
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func warning(
        airport: AirportReference,
        instant: Date?,
        localWindKnots: Double?,
        localGustKnots: Double?
    ) -> AlpineFoehnWarning? {
        guard isNearAlps(airport), let instant,
              let northPressure = northForecast?.sample(nearestTo: instant)?.pressureMSLHPA,
              let southPressure = southForecast?.sample(nearestTo: instant)?.pressureMSLHPA
        else { return nil }

        let difference = southPressure - northPressure
        let affectsNorth = difference >= 2 && airport.latitude >= 46.65
        let affectsSouth = difference <= -2 && airport.latitude < 46.85
        guard affectsNorth || affectsSouth else { return nil }

        let magnitude = abs(difference)
        let wind = localWindKnots ?? 0
        let gust = localGustKnots ?? wind

        // Eine Druckdifferenz ist nur ein Föhn-Potenzial. Die farbige
        // Flugplatzwarnung setzt zusätzlich ein lokales Windsignal voraus.
        guard wind >= 8 || gust >= 12 else { return nil }

        var level: AlpineFoehnLevel
        if magnitude >= 6 { level = .red }
        else if magnitude >= 4 { level = .orange }
        else { level = .yellow }

        if gust >= 35 || wind >= 28 { level = .red }
        else if gust >= 25 || wind >= 20 { level = max(level, .orange) }

        let flowName = affectsNorth ? "Südföhn" : "Nordföhn"
        let hazardText: String
        switch level {
        case .none:
            hazardText = "Kein relevantes lokales Signal."
        case .yellow:
            hazardText = "Föhn ist möglich; lokale Windentwicklung und Tal-/Passlage beobachten."
        case .orange:
            hazardText = "Turbulenz, Lee-Effekte und Windscherung sind wahrscheinlich."
        case .red:
            hazardText = "Starke Turbulenz, Lee-Rotoren und Windscherung sind wahrscheinlich."
        }
        let explanation = String(
            format:
                "%@-Signal am Flugplatz. Druckdifferenz Süd−Nord: %+.1f hPa. Lokaler Wind %.0f kt, Böen %.0f kt. %@ Kein automatisches VFR-Go/No-Go: offizielles Flugwetterbriefing, GAFOR/SIGMET und lokale Alpenflug-Minima prüfen.",
            flowName, difference, wind, gust, hazardText
        )
        return AlpineFoehnWarning(
            level: level,
            pressureDifferenceHPA: difference,
            flowName: flowName,
            explanation: explanation
        )
    }

    private func isNearAlps(_ airport: AirportReference) -> Bool {
        let alpineRidge: [(Double, Double)] = [
            (46.20, 6.90),  // Westalpen
            (45.83, 6.86),  // Mont-Blanc-Gruppe
            (46.20, 7.50),  // Wallis
            (46.56, 8.56),  // Gotthard
            (46.70, 9.70),  // Graubünden
            (47.00, 11.30), // Tirol
            (47.30, 13.00), // Salzburger Alpen
            (47.05, 14.50), // östliche Alpen
            (46.65, 15.60)  // Südostalpen
        ]
        let distance = alpineRidge.map {
            distanceKilometers(
                latitude1: airport.latitude,
                longitude1: airport.longitude,
                latitude2: $0.0,
                longitude2: $0.1
            )
        }.min() ?? .infinity
        return distance <= 85
    }

    private func distanceKilometers(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double
    ) -> Double {
        let radius = 6_371.0
        let lat1 = latitude1 * .pi / 180
        let lat2 = latitude2 * .pi / 180
        let deltaLatitude = (latitude2 - latitude1) * .pi / 180
        let deltaLongitude = (longitude2 - longitude1) * .pi / 180
        let a = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
            + cos(lat1) * cos(lat2)
            * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
