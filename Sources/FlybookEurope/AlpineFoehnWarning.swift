import Foundation
import SwiftUI

enum AlpineRegion {
    private static let ridge: [(Double, Double)] = [
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

    static func contains(latitude: Double, longitude: Double) -> Bool {
        ridge.map {
            distanceKilometers(
                latitude1: latitude,
                longitude1: longitude,
                latitude2: $0.0,
                longitude2: $0.1
            )
        }.min() ?? .infinity <= 85
    }

    static func routeCrosses(_ waypoints: [AirportReference]) -> Bool {
        !foehnAxes(along: waypoints).isEmpty
    }

    static func foehnAxes(along waypoints: [AirportReference]) -> Set<AlpineFoehnAxis> {
        guard waypoints.count >= 2 else { return [] }
        var axes: Set<AlpineFoehnAxis> = []
        for (start, end) in zip(waypoints, waypoints.dropFirst()) {
            for step in 0...24 {
                let fraction = Double(step) / 24
                let latitude = start.latitude
                    + (end.latitude - start.latitude) * fraction
                let longitude = start.longitude
                    + (end.longitude - start.longitude) * fraction
                if contains(latitude: latitude, longitude: longitude) {
                    axes.insert(AlpineFoehnAxis.nearest(
                        toLatitude: latitude,
                        longitude: longitude
                    ))
                }
            }
        }
        return axes
    }

    static func distanceKilometers(
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

enum AlpineFoehnAxis: String, CaseIterable, Sendable {
    case west
    case central
    case east

    var title: String {
        switch self {
        case .west: return "Annecy–Aosta"
        case .central: return "Zürich–Lugano"
        case .east: return "Innsbruck–Bozen"
        }
    }

    var northReference: (latitude: Double, longitude: Double) {
        switch self {
        case .west: return (45.8992, 6.1294)
        case .central: return (47.4581, 8.5555)
        case .east: return (47.2692, 11.4041)
        }
    }

    var southReference: (latitude: Double, longitude: Double) {
        switch self {
        case .west: return (45.7370, 7.3201)
        case .central: return (46.0043, 8.9106)
        case .east: return (46.4983, 11.3548)
        }
    }

    static func nearest(toLatitude latitude: Double, longitude: Double) -> Self {
        allCases.min { lhs, rhs in
            lhs.distanceToAxis(latitude: latitude, longitude: longitude)
                < rhs.distanceToAxis(latitude: latitude, longitude: longitude)
        } ?? .central
    }

    func isNorthSide(latitude: Double, longitude: Double) -> Bool {
        distance(
            latitude: latitude,
            longitude: longitude,
            reference: northReference
        ) <= distance(
            latitude: latitude,
            longitude: longitude,
            reference: southReference
        )
    }

    private func distanceToAxis(latitude: Double, longitude: Double) -> Double {
        min(
            distance(
                latitude: latitude,
                longitude: longitude,
                reference: northReference
            ),
            distance(
                latitude: latitude,
                longitude: longitude,
                reference: southReference
            )
        )
    }

    private func distance(
        latitude: Double,
        longitude: Double,
        reference: (latitude: Double, longitude: Double)
    ) -> Double {
        AlpineRegion.distanceKilometers(
            latitude1: latitude,
            longitude1: longitude,
            latitude2: reference.latitude,
            longitude2: reference.longitude
        )
    }
}

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

struct AlpineFoehnPressureSample: Sendable {
    let axis: AlpineFoehnAxis
    let instant: Date
    let pressureDifferenceHPA: Double
}

enum AlpineFoehnEvaluator {
    static func level(forMagnitude magnitude: Double) -> AlpineFoehnLevel {
        if magnitude >= 6 { return .red }
        if magnitude >= 4 { return .orange }
        if magnitude >= 2 { return .yellow }
        return .none
    }

    static func maximumRelevantMagnitude(
        in samples: [AlpineFoehnPressureSample],
        for airport: AirportReference,
        from: Date,
        until: Date
    ) -> Double? {
        guard !samples.isEmpty else { return nil }
        let axis = AlpineFoehnAxis.nearest(
            toLatitude: airport.latitude,
            longitude: airport.longitude
        )
        let airportIsNorth = axis.isNorthSide(
            latitude: airport.latitude,
            longitude: airport.longitude
        )
        return samples.lazy
            .filter {
                $0.axis == axis && $0.instant >= from && $0.instant <= until
            }
            .filter { sample in
                let difference = sample.pressureDifferenceHPA
                return (difference >= 2 && airportIsNorth)
                    || (difference <= -2 && !airportIsNorth)
            }
            .map { abs($0.pressureDifferenceHPA) }
            .max() ?? 0
    }

    static func routeRisk(forMagnitude magnitude: Double) -> RouteWeatherRisk? {
        switch level(forMagnitude: magnitude) {
        case .none: return nil
        case .yellow: return .blue
        case .orange: return .red
        case .red: return .purple
        }
    }

    static func airportMatches(
        samples: [AlpineFoehnPressureSample],
        airport: AirportReference,
        from: Date,
        until: Date,
        maximumExclusive: Double
    ) -> Bool? {
        guard let magnitude = maximumRelevantMagnitude(
            in: samples,
            for: airport,
            from: from,
            until: until
        ) else { return nil }
        return magnitude < maximumExclusive
    }
}

actor AlpineFoehnForecastService {
    static let shared = AlpineFoehnForecastService()

    private struct CacheEntry {
        let retrievedAt: Date
        let samples: [AlpineFoehnPressureSample]
    }

    private struct APIResponse: Decodable {
        let hourly: Hourly

        struct Hourly: Decodable {
            let time: [String]
            let pressureMSL: [Double?]

            enum CodingKeys: String, CodingKey {
                case time
                case pressureMSL = "pressure_msl"
            }
        }
    }

    private let cacheLifetime: TimeInterval = 30 * 60
    private var cache: [String: CacheEntry] = [:]

    func samples(
        from: Date,
        until: Date,
        forceRefresh: Bool = false
    ) async throws -> [AlpineFoehnPressureSample] {
        guard until >= from else { return [] }
        let key = cacheKey(from: from, until: until)
        if !forceRefresh {
            if let cached = cache[key], isFresh(cached) {
                return cached.samples
            }
            if let covering = cache.values.first(where: {
                isFresh($0) && covers($0.samples, from: from, until: until)
            }) {
                return covering.samples
            }
        }

        var lastError: Error?
        for route in ICONSeamlessAccessRoute.allCases {
            do {
                let values = try await download(
                    from: from,
                    until: until,
                    route: route
                )
                cache[key] = CacheEntry(retrievedAt: Date(), samples: values)
                return values
            } catch is CancellationError {
                throw CancellationError()
            } catch is OpenMeteoAccessError {
                throw OpenMeteoAccessError.rateLimited
            } catch {
                lastError = error
            }
        }
        throw lastError ?? URLError(.cannotParseResponse)
    }

    private func download(
        from: Date,
        until: Date,
        route: ICONSeamlessAccessRoute
    ) async throws -> [AlpineFoehnPressureSample] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Zurich")
        formatter.dateFormat = "yyyy-MM-dd"
        let references = AlpineFoehnAxis.allCases.flatMap {
            [$0.northReference, $0.southReference]
        }
        let queryItems = [
            URLQueryItem(
                name: "latitude",
                value: references.map { String($0.latitude) }.joined(separator: ",")
            ),
            URLQueryItem(
                name: "longitude",
                value: references.map { String($0.longitude) }.joined(separator: ",")
            ),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(name: "start_date", value: formatter.string(from: from)),
            URLQueryItem(name: "end_date", value: formatter.string(from: until)),
            URLQueryItem(name: "hourly", value: "pressure_msl")
        ]
        guard let url = route.url(queryItems: queryItems) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await FlightNetwork.openMeteoData(
            from: url,
            priority: .low
        )
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode([APIResponse].self, from: data)
        guard decoded.count == references.count else {
            throw URLError(.cannotParseResponse)
        }

        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return AlpineFoehnAxis.allCases.enumerated().flatMap {
            (axisIndex, axis) -> [AlpineFoehnPressureSample] in
            let north = decoded[axisIndex * 2].hourly
            let south = decoded[axisIndex * 2 + 1].hourly
            let count = [
                north.time.count,
                south.time.count,
                north.pressureMSL.count,
                south.pressureMSL.count
            ].min() ?? 0
            let samples: [AlpineFoehnPressureSample] = (0..<count).compactMap { index in
                guard north.time[index] == south.time[index],
                      let instant = parser.date(from: north.time[index]),
                      let northPressure = north.pressureMSL[index],
                      let southPressure = south.pressureMSL[index]
                else { return nil }
                return AlpineFoehnPressureSample(
                    axis: axis,
                    instant: instant,
                    pressureDifferenceHPA: southPressure - northPressure
                )
            }
            return samples
        }
    }

    private func cacheKey(from: Date, until: Date) -> String {
        "\(Int(from.timeIntervalSince1970 / 3600))-\(Int(until.timeIntervalSince1970 / 3600))"
    }

    private func isFresh(_ entry: CacheEntry) -> Bool {
        Date().timeIntervalSince(entry.retrievedAt) < cacheLifetime
    }

    private func covers(
        _ samples: [AlpineFoehnPressureSample],
        from: Date,
        until: Date
    ) -> Bool {
        AlpineFoehnAxis.allCases.allSatisfy { axis in
            let instants = samples.lazy.filter { $0.axis == axis }.map(\.instant)
            guard let first = instants.min(), let last = instants.max() else {
                return false
            }
            return first <= from && last >= until
        }
    }
}

@MainActor
final class AlpineFoehnViewModel: ObservableObject {
    @Published private var pressureSamples: [AlpineFoehnPressureSample] = []
    @Published private(set) var errorMessage: String?

    func load(
        ifRelevant airports: [AirportReference],
        routes: [[AirportReference]] = [],
        instants: [Date] = [],
        forceRefresh: Bool = false
    ) async {
        guard airports.contains(where: isNearAlps)
                || routes.contains(where: AlpineRegion.routeCrosses)
        else {
            pressureSamples = []
            errorMessage = nil
            return
        }
        let requested = instants.isEmpty ? [Date()] : instants
        guard let first = requested.min(), let last = requested.max() else {
            pressureSamples = []
            return
        }
        do {
            pressureSamples = try await AlpineFoehnForecastService.shared.samples(
                from: first,
                until: last,
                forceRefresh: forceRefresh
            )
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
        guard isNearAlps(airport), let instant else { return nil }
        let axis = AlpineFoehnAxis.nearest(
            toLatitude: airport.latitude,
            longitude: airport.longitude
        )
        guard let difference = pressureDifference(
            nearestTo: instant,
            axis: axis
        )
        else { return nil }

        let airportIsNorth = axis.isNorthSide(
            latitude: airport.latitude,
            longitude: airport.longitude
        )
        let affectsNorth = difference >= 2 && airportIsNorth
        let affectsSouth = difference <= -2 && !airportIsNorth
        guard affectsNorth || affectsSouth else { return nil }

        let magnitude = abs(difference)
        let wind = localWindKnots ?? 0
        let gust = localGustKnots ?? wind

        var level = AlpineFoehnEvaluator.level(forMagnitude: magnitude)

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
                "%@-Signal am Flugplatz über die Achse %@. Druckdifferenz Süd−Nord: %+.1f hPa. Lokaler Wind %.0f kt, Böen %.0f kt. %@ Kein automatisches VFR-Go/No-Go: offizielles Flugwetterbriefing, GAFOR/SIGMET und lokale Alpenflug-Minima prüfen.",
            flowName, axis.title, difference, wind, gust, hazardText
        )
        return AlpineFoehnWarning(
            level: level,
            pressureDifferenceHPA: difference,
            flowName: flowName,
            explanation: explanation
        )
    }

    func routeWarning(
        waypoints: [AirportReference],
        instant: Date
    ) -> AlpineFoehnWarning? {
        guard AlpineRegion.routeCrosses(waypoints) else { return nil }
        let axes = AlpineRegion.foehnAxes(along: waypoints)
        guard let controlling = axes.compactMap({ axis in
            pressureSamples
                .filter { $0.axis == axis }
                .min(by: {
                    abs($0.instant.timeIntervalSince(instant))
                        < abs($1.instant.timeIntervalSince(instant))
                })
        }).max(by: {
            abs($0.pressureDifferenceHPA) < abs($1.pressureDifferenceHPA)
        }), abs(controlling.pressureDifferenceHPA) >= 2 else { return nil }
        let difference = controlling.pressureDifferenceHPA
        let magnitude = abs(difference)
        let level = AlpineFoehnEvaluator.level(forMagnitude: magnitude)
        let flowName = difference >= 0 ? "Südföhn" : "Nordföhn"
        let explanation = String(
            format: "%@-Potenzial auf der Alpenroute, Achse %@. Prognostizierte Druckdifferenz Süd−Nord: %+.1f hPa. Dieser Streckenhinweis gilt auch bei weit vom Alpenraum entfernten Start- oder Zielflugplätzen. Kammwind, GAFOR/SIGMET und offizielles Flugwetterbriefing prüfen.",
            flowName,
            controlling.axis.title,
            difference
        )
        return AlpineFoehnWarning(
            level: level,
            pressureDifferenceHPA: difference,
            flowName: flowName,
            explanation: explanation
        )
    }

    private func pressureDifference(
        nearestTo instant: Date,
        axis: AlpineFoehnAxis
    ) -> Double? {
        guard let sample = pressureSamples.filter({ $0.axis == axis }).min(by: {
            abs($0.instant.timeIntervalSince(instant))
                < abs($1.instant.timeIntervalSince(instant))
        }),
              abs(sample.instant.timeIntervalSince(instant)) <= 90 * 60
        else { return nil }
        return sample.pressureDifferenceHPA
    }

    private func isNearAlps(_ airport: AirportReference) -> Bool {
        AlpineRegion.contains(
            latitude: airport.latitude,
            longitude: airport.longitude
        )
    }
}
