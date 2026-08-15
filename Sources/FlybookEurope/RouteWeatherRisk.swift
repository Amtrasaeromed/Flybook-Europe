import Foundation
import SwiftUI

private extension Array {
    subscript(routeRiskSafe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum RouteWeatherRisk: Int, Codable, Comparable, Sendable {
    case unavailable = -1
    case green = 0
    case blue = 1
    case red = 2
    case purple = 3

    static func < (lhs: RouteWeatherRisk, rhs: RouteWeatherRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var color: Color {
        switch self {
        case .unavailable: return Color.gray
        case .green: return .green
        case .blue: return FlybookColor.blue
        case .red: return .red
        case .purple: return .purple
        }
    }

    var title: String {
        switch self {
        case .unavailable: return "Keine ausreichenden Routendaten"
        case .green: return "Routenwetter unkritisch"
        case .blue: return "Routenwetter marginal"
        case .red: return "Routenwetter kritisch"
        case .purple: return "Routenwetter sehr kritisch"
        }
    }
}

struct RouteWeatherSegmentAssessment: Equatable, Sendable {
    let risk: RouteWeatherRisk
    let isAlpine: Bool
    let controllingTerrainFeetMSL: Double?
    let ceilingClearanceFeet: Double?
    let visibilityMeters: Double?
    let precipitationMillimeters: Double?
    let explanation: String

    static let unavailable = RouteWeatherSegmentAssessment(
        risk: .unavailable,
        isAlpine: false,
        controllingTerrainFeetMSL: nil,
        ceilingClearanceFeet: nil,
        visibilityMeters: nil,
        precipitationMillimeters: nil,
        explanation: "Keine ausreichenden Routendaten"
    )
}

enum AlpineRouteWeatherEvaluator {
    static func assess(
        baseRisk: RouteWeatherRisk,
        isAlpine: Bool,
        controllingTerrainFeetMSL: Double?,
        ceilingClearanceFeet: Double?,
        visibilityMeters: Double?,
        precipitationMillimeters: Double?
    ) -> RouteWeatherSegmentAssessment {
        guard isAlpine else {
            return RouteWeatherSegmentAssessment(
                risk: baseRisk,
                isAlpine: false,
                controllingTerrainFeetMSL: controllingTerrainFeetMSL,
                ceilingClearanceFeet: ceilingClearanceFeet,
                visibilityMeters: visibilityMeters,
                precipitationMillimeters: precipitationMillimeters,
                explanation: baseRisk.title
            )
        }

        var risk = baseRisk
        var explanation = "Alpenkorridor ohne zusätzliches Warnsignal"
        let precipitation = precipitationMillimeters ?? 0

        if let visibilityMeters {
            if visibilityMeters < 5_000 {
                risk = .purple
                explanation = String(
                    format: "Alpenroute nicht ausreichend sichtbar: %.1f km",
                    visibilityMeters / 1_000
                )
            } else if visibilityMeters < 8_000 {
                risk = max(risk, .red)
                explanation = String(
                    format: "Alpensicht kritisch: %.1f km",
                    visibilityMeters / 1_000
                )
            } else if visibilityMeters < 10_000 {
                risk = max(risk, .blue)
                explanation = String(
                    format: "Alpensicht eingeschränkt: %.1f km",
                    visibilityMeters / 1_000
                )
            }
        }

        if let clearance = ceilingClearanceFeet {
            if clearance < 1_000 {
                risk = .purple
                explanation = String(
                    format: "Alpenroute geschlossen: nur %.0f ft Wolkenabstand über Gelände/Pass",
                    max(0, clearance)
                )
            } else if clearance < 2_000 {
                risk = max(risk, .red)
                explanation = String(
                    format: "Alpenkorridor kritisch: nur %.0f ft über Gelände/Pass",
                    clearance
                )
            } else if clearance < 5_000 {
                risk = max(risk, .blue)
                explanation = String(
                    format: "Alpenkorridor eingeschränkt: %.0f ft über Gelände/Pass",
                    clearance
                )
            }

            if precipitation >= 0.1 {
                if clearance < 2_000 {
                    risk = .purple
                    explanation = String(
                        format: "Alpenroute geschlossen: Niederschlag und nur %.0f ft über Gelände/Pass",
                        clearance
                    )
                } else if clearance < 5_000 {
                    risk = max(risk, .red)
                    explanation = String(
                        format: "Alpenroute kritisch: Niederschlag bei %.0f ft Geländefreiheit",
                        clearance
                    )
                } else {
                    risk = max(risk, .blue)
                    explanation = "Niederschlag im Alpenkorridor"
                }
            }
        } else if precipitation >= 2 {
            risk = max(risk, .red)
            explanation = "Niederschlag im Alpenkorridor; Wolkenabstand zum Gelände unbekannt"
        } else if precipitation >= 0.1 {
            risk = max(risk, .blue)
            explanation = "Niederschlag im Alpenkorridor"
        }

        return RouteWeatherSegmentAssessment(
            risk: risk,
            isAlpine: true,
            controllingTerrainFeetMSL: controllingTerrainFeetMSL,
            ceilingClearanceFeet: ceilingClearanceFeet,
            visibilityMeters: visibilityMeters,
            precipitationMillimeters: precipitationMillimeters,
            explanation: explanation
        )
    }
}

@MainActor
final class RouteWeatherRiskViewModel: ObservableObject {
    @Published private(set) var assessments = Array(
        repeating: RouteWeatherSegmentAssessment.unavailable,
        count: 6
    )

    var segments: [RouteWeatherRisk] { assessments.map(\.risk) }

    func load(
        waypoints: [AirportReference],
        start: Date,
        end: Date,
        cruiseAltitudeFeet: Int,
        forceRefresh: Bool = false
    ) async {
        guard waypoints.count >= 2 else {
            assessments = Array(repeating: .unavailable, count: 6)
            return
        }
        do {
            assessments = try await RouteWeatherRiskService.shared.assessments(
                waypoints: waypoints,
                start: start,
                end: end,
                cruiseAltitudeFeet: cruiseAltitudeFeet,
                forceRefresh: forceRefresh
            )
        } catch {
            assessments = Array(repeating: .unavailable, count: 6)
        }
    }
}

actor RouteWeatherRiskService {
    static let shared = RouteWeatherRiskService()
    private let cacheLifetime: TimeInterval = 30 * 60
    private var cache: [String: (Date, [RouteWeatherSegmentAssessment])] = [:]

    private struct SamplePoint {
        let latitude: Double
        let longitude: Double
        let instant: Date
        let segment: Int
    }

    func risks(
        waypoints: [AirportReference],
        start: Date,
        end: Date,
        cruiseAltitudeFeet: Int,
        forceRefresh: Bool
    ) async throws -> [RouteWeatherRisk] {
        try await assessments(
            waypoints: waypoints,
            start: start,
            end: end,
            cruiseAltitudeFeet: cruiseAltitudeFeet,
            forceRefresh: forceRefresh
        ).map(\.risk)
    }

    /// Low-cost route screening for the Destination Finder. It deliberately
    /// performs no network request and represents each route sixth by the
    /// nearest fresh airport forecast from the shared ICON mesh.
    func cachedRisks(
        waypoints: [AirportReference],
        start: Date,
        end: Date,
        cruiseAltitudeFeet: Int
    ) async -> [RouteWeatherRisk] {
        let samples = corridorSamples(
            waypoints: waypoints,
            start: start,
            end: end
        )
        var result = Array(
            repeating: RouteWeatherRisk.unavailable,
            count: 6
        )
        for segment in result.indices {
            guard let center = samples.first(where: {
                $0.segment == segment
            }),
                  let cached = await DestinationFinderWeatherCache.shared
                    .cachedHour(
                        nearestToLatitude: center.latitude,
                        longitude: center.longitude,
                        instant: center.instant
                    )
            else { continue }
            result[segment] = assessment(
                RiskHour(cached: cached),
                sample: center,
                sampleTerrainFeetMSL: nil,
                controllingTerrainFeetMSL: nil,
                cruiseAltitudeFeet: cruiseAltitudeFeet
            ).risk
        }
        return result
    }

    func assessments(
        waypoints: [AirportReference],
        start: Date,
        end: Date,
        cruiseAltitudeFeet: Int,
        forceRefresh: Bool
    ) async throws -> [RouteWeatherSegmentAssessment] {
        let key = cacheKey(
            waypoints: waypoints,
            start: start,
            end: end,
            cruiseAltitudeFeet: cruiseAltitudeFeet
        )
        if !forceRefresh,
           let cached = cache[key],
           Date().timeIntervalSince(cached.0) < cacheLifetime {
            return cached.1
        }
        let samples = corridorSamples(waypoints: waypoints, start: start, end: end)
        var result = Array(
            repeating: RouteWeatherSegmentAssessment(
                risk: .green,
                isAlpine: false,
                controllingTerrainFeetMSL: nil,
                ceilingClearanceFeet: nil,
                visibilityMeters: nil,
                precipitationMillimeters: nil,
                explanation: RouteWeatherRisk.green.title
            ),
            count: 6
        )
        var hasData = Array(repeating: false, count: 6)
        do {
            let responses = try await fetch(samples)
            guard responses.count == samples.count else { throw RiskError.noData }
            let forecastPoints = zip(samples, responses).compactMap {
                sample, response -> (SamplePoint, RiskHour, Double?)? in
                guard let hour = response.nearest(to: sample.instant) else {
                    return nil
                }
                return (
                    sample,
                    hour,
                    response.elevation.map { $0 / 0.3048 }
                )
            }
            for segment in 0..<6 {
                let points = forecastPoints.filter { $0.0.segment == segment }
                guard !points.isEmpty else { continue }
                let controllingTerrain = points.compactMap { $0.2 }.max()
                let segmentAssessments = points.map { sample, hour, terrain in
                    assessment(
                        hour,
                        sample: sample,
                        sampleTerrainFeetMSL: terrain,
                        controllingTerrainFeetMSL: controllingTerrain,
                        cruiseAltitudeFeet: cruiseAltitudeFeet
                    )
                }
                guard let worst = segmentAssessments.max(by: assessmentIsLess)
                else { continue }
                hasData[segment] = true
                result[segment] = worst
            }
        } catch {
            // The global forecast endpoint may throttle large corridor batches.
            // Reuse the app-wide 30-minute airport cache instead of showing an
            // entirely unknown route. One center sample represents each sixth.
            for (index, sample) in samples.enumerated()
            where index.isMultiple(of: 3) {
                guard let cached = await DestinationFinderWeatherCache.shared.cachedHour(
                    nearestToLatitude: sample.latitude,
                    longitude: sample.longitude,
                    instant: sample.instant
                ) else { continue }
                let hour = RiskHour(cached: cached)
                hasData[sample.segment] = true
                result[sample.segment] = assessment(
                    hour,
                    sample: sample,
                    sampleTerrainFeetMSL: nil,
                    controllingTerrainFeetMSL: nil,
                    cruiseAltitudeFeet: cruiseAltitudeFeet
                )
            }
        }
        for index in result.indices where !hasData[index] {
            result[index] = .unavailable
        }
        if hasData.contains(false) {
            let fallback = await fetchMETFallback(samples)
            for (segment, risk) in fallback where !hasData[segment] {
                let center = samples.first(where: { $0.segment == segment })
                let alpine = center.map {
                    AlpineRegion.contains(
                        latitude: $0.latitude,
                        longitude: $0.longitude
                    )
                } ?? false
                result[segment] = RouteWeatherSegmentAssessment(
                    risk: risk,
                    isAlpine: alpine,
                    controllingTerrainFeetMSL: nil,
                    ceilingClearanceFeet: nil,
                    visibilityMeters: nil,
                    precipitationMillimeters: nil,
                    explanation: alpine
                        ? "Alpenkorridor nur mit Ersatzwetterdaten bewertet"
                        : risk.title
                )
                hasData[segment] = true
            }
        }
        if AlpineRegion.routeCrosses(waypoints),
           let foehnSamples = try? await AlpineFoehnForecastService.shared
            .samples(from: start, until: end, forceRefresh: forceRefresh)
        {
            for index in result.indices {
                let axes = Set<AlpineFoehnAxis>(samples.compactMap { sample in
                    guard sample.segment == index,
                          AlpineRegion.contains(
                            latitude: sample.latitude,
                            longitude: sample.longitude
                          ) else { return nil }
                    return AlpineFoehnAxis.nearest(
                        toLatitude: sample.latitude,
                        longitude: sample.longitude
                    )
                })
                guard !axes.isEmpty,
                      let controlling = foehnSamples
                        .filter({
                            axes.contains($0.axis)
                                && $0.instant >= start
                                && $0.instant <= end
                        })
                        .max(by: {
                            abs($0.pressureDifferenceHPA)
                                < abs($1.pressureDifferenceHPA)
                        }),
                      let foehnRisk = AlpineFoehnEvaluator.routeRisk(
                        forMagnitude: abs(controlling.pressureDifferenceHPA)
                      )
                else { continue }
                let difference = controlling.pressureDifferenceHPA
                let flowName = difference >= 0 ? "Südföhn" : "Nordföhn"
                let current = result[index]
                result[index] = RouteWeatherSegmentAssessment(
                    risk: max(current.risk, foehnRisk),
                    isAlpine: true,
                    controllingTerrainFeetMSL:
                        current.controllingTerrainFeetMSL,
                    ceilingClearanceFeet: current.ceilingClearanceFeet,
                    visibilityMeters: current.visibilityMeters,
                    precipitationMillimeters:
                        current.precipitationMillimeters,
                    explanation: String(
                        format: "%@ im Alpenkorridor, Achse %@: Süd−Nord %+.1f hPa. %@",
                        flowName,
                        controlling.axis.title,
                        difference,
                        current.explanation
                    )
                )
            }
        }
        cache[key] = (Date(), result)
        return result
    }

    private func assessmentIsLess(
        _ lhs: RouteWeatherSegmentAssessment,
        _ rhs: RouteWeatherSegmentAssessment
    ) -> Bool {
        if lhs.risk != rhs.risk { return lhs.risk < rhs.risk }
        return (lhs.ceilingClearanceFeet ?? .infinity)
            > (rhs.ceilingClearanceFeet ?? .infinity)
    }

    private func assessment(
        _ hour: RiskHour,
        sample: SamplePoint,
        sampleTerrainFeetMSL: Double?,
        controllingTerrainFeetMSL: Double?,
        cruiseAltitudeFeet: Int
    ) -> RouteWeatherSegmentAssessment {
        let baseRisk = classify(
            hour,
            cruiseAltitudeFeet: cruiseAltitudeFeet
        )
        let clearance = hour.estimatedCeilingBaseFeetAGL.map { baseAGL in
            guard let sampleTerrainFeetMSL,
                  let controllingTerrainFeetMSL
            else { return baseAGL }
            return sampleTerrainFeetMSL + baseAGL
                - controllingTerrainFeetMSL
        }
        return AlpineRouteWeatherEvaluator.assess(
            baseRisk: baseRisk,
            isAlpine: AlpineRegion.contains(
                latitude: sample.latitude,
                longitude: sample.longitude
            ),
            controllingTerrainFeetMSL: controllingTerrainFeetMSL,
            ceilingClearanceFeet: clearance,
            visibilityMeters: hour.visibilityMeters,
            precipitationMillimeters: hour.precipitationMillimeters
        )
    }

    private func classify(
        _ hour: RiskHour,
        cruiseAltitudeFeet: Int
    ) -> RouteWeatherRisk {
        var risk = RouteWeatherRisk.green
        var critical = false
        var veryCritical = false

        if let visibility = hour.visibilityMeters {
            if visibility < 1_500 {
                critical = true
                veryCritical = true
            }
            if visibility < 8_000 { risk = .blue }
        }
        if let rain = hour.precipitationMillimeters {
            if rain > 10 { critical = true }
            if rain >= 2 { risk = .blue }
        }
        if let code = hour.weatherCode {
            if [45, 48, 95, 96, 99].contains(code) { critical = true }
            if [95, 96, 99].contains(code) { veryCritical = true }
        }
        if let temperature = hour.temperatureCelsius,
           let dewPoint = hour.dewPointCelsius,
           temperature - dewPoint <= 2,
           (hour.visibilityMeters ?? 10_000) < 8_000 {
            risk = .blue
        }
        if let cape = hour.cape {
            if cape >= 1_000,
               (hour.precipitationMillimeters ?? 0) > 0 {
                critical = true
            }
            if cape >= 500 { risk = .blue }
        }

        if let baseFeetAGL = hour.estimatedCeilingBaseFeetAGL {
            if baseFeetAGL < 1_000 { critical = true }
            if baseFeetAGL < 500 { veryCritical = true }
            if baseFeetAGL <= 2_500 { risk = .blue }
        }

        if let thickness = hour.brokenOvercastThicknessFeet {
            if thickness >= 6_000 { critical = true }
            if thickness >= 4_000 { risk = .blue }
        }
        guard critical else { return risk }

        // A critical surface layer may be overflown, but it remains operationally
        // relevant for diversion and landing. Therefore red can improve only to blue.
        return hour.isSuitableAloft(around: cruiseAltitudeFeet)
            ? .blue
            : (veryCritical ? .purple : .red)
    }

    private func corridorSamples(
        waypoints: [AirportReference],
        start: Date,
        end: Date
    ) -> [SamplePoint] {
        let legs = zip(waypoints, waypoints.dropFirst()).map { first, second in
            (first, second, AirportDistance.nauticalMiles(from: first, to: second))
        }
        let total = max(0.1, legs.reduce(0) { $0 + $1.2 })
        let duration = end.timeIntervalSince(start)
        return (0..<6).flatMap { segment -> [SamplePoint] in
            let fraction = (Double(segment) + 0.5) / 6
            let distance = total * fraction
            var traversed = 0.0
            var selected = legs[legs.count - 1]
            for leg in legs {
                if traversed + leg.2 >= distance {
                    selected = leg
                    break
                }
                traversed += leg.2
            }
            let legFraction = min(1, max(0, (distance - traversed) / max(0.1, selected.2)))
            let center = geographicPoint(
                from: selected.0,
                to: selected.1,
                fraction: legFraction
            )
            let course = AirportBearing.initial(from: selected.0, to: selected.1)
            let instant = start.addingTimeInterval(duration * fraction)
            return [0.0, -5.0, 5.0].map { offset in
                let coordinate = offset == 0
                    ? center
                    : destinationPoint(
                        latitude: center.latitude,
                        longitude: center.longitude,
                        bearing: course + (offset < 0 ? -90 : 90),
                        distanceNM: abs(offset)
                    )
                return SamplePoint(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    instant: instant,
                    segment: segment
                )
            }
        }
    }

    private func geographicPoint(
        from: AirportReference,
        to: AirportReference,
        fraction: Double
    ) -> (latitude: Double, longitude: Double) {
        let lat = from.latitude + (to.latitude - from.latitude) * fraction
        let lon = from.longitude + (to.longitude - from.longitude) * fraction
        return (lat, lon)
    }

    private func destinationPoint(
        latitude: Double,
        longitude: Double,
        bearing: Double,
        distanceNM: Double
    ) -> (latitude: Double, longitude: Double) {
        let angular = distanceNM / 3440.065
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let bearingRadians = bearing * .pi / 180
        let lat2 = asin(
            sin(lat1) * cos(angular)
                + cos(lat1) * sin(angular) * cos(bearingRadians)
        )
        let lon2 = lon1 + atan2(
            sin(bearingRadians) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2)
        )
        return (lat2 * 180 / .pi, lon2 * 180 / .pi)
    }

    private func fetch(_ samples: [SamplePoint]) async throws -> [RiskAPIResponse] {
        guard let firstInstant = samples.map(\.instant).min(),
              let lastInstant = samples.map(\.instant).max()
        else { throw RiskError.noData }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: samples.map { String($0.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: samples.map { String($0.longitude) }.joined(separator: ",")),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(
                name: "start_date",
                value: formatter.string(from: firstInstant)
            ),
            URLQueryItem(
                name: "end_date",
                value: formatter.string(from: lastInstant)
            ),
            URLQueryItem(name: "hourly", value: [
                "temperature_2m", "dew_point_2m", "precipitation", "weather_code",
                "visibility", "cloud_cover_low", "cape",
                "cloud_cover_1000hPa", "geopotential_height_1000hPa",
                "cloud_cover_975hPa", "geopotential_height_975hPa",
                "cloud_cover_950hPa", "geopotential_height_950hPa",
                "cloud_cover_925hPa", "geopotential_height_925hPa",
                "cloud_cover_900hPa", "geopotential_height_900hPa",
                "cloud_cover_850hPa", "geopotential_height_850hPa",
                "cloud_cover_800hPa", "geopotential_height_800hPa",
                "cloud_cover_700hPa", "geopotential_height_700hPa"
            ].joined(separator: ","))
        ]
        guard let url = components?.url else { throw RiskError.noData }
        let (data, response) = try await FlightNetwork.openMeteoData(
            from: url,
            priority: .low
        )
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { throw RiskError.noData }
        return try JSONDecoder().decode([RiskAPIResponse].self, from: data)
    }

    private func fetchMETFallback(
        _ samples: [SamplePoint]
    ) async -> [Int: RouteWeatherRisk] {
        var result: [Int: RouteWeatherRisk] = [:]
        for (index, sample) in samples.enumerated()
        where index.isMultiple(of: 3) {
            guard var components = URLComponents(
                string: "https://api.met.no/weatherapi/locationforecast/2.0/compact"
            ) else { continue }
            components.queryItems = [
                URLQueryItem(name: "lat", value: String(format: "%.4f", sample.latitude)),
                URLQueryItem(name: "lon", value: String(format: "%.4f", sample.longitude))
            ]
            guard let url = components.url else { continue }
            do {
                let data = try await FlightNetwork.metNorwayData(
                    from: url,
                    priority: .low
                )
                guard let decoded = try? JSONDecoder().decode(METResponse.self, from: data),
                      let point = decoded.properties.timeseries.min(by: {
                          abs($0.instant.timeIntervalSince(sample.instant))
                              < abs($1.instant.timeIntervalSince(sample.instant))
                      }),
                      abs(point.instant.timeIntervalSince(sample.instant)) <= 2 * 60 * 60
                else { continue }
                result[sample.segment] = point.risk
            } catch { continue }
        }
        return result
    }

    private func cacheKey(
        waypoints: [AirportReference],
        start: Date,
        end: Date,
        cruiseAltitudeFeet: Int
    ) -> String {
        waypoints.map(\.icao).joined(separator: "-")
            + "-\(Int(start.timeIntervalSince1970 / 1800))"
            + "-\(Int(end.timeIntervalSince1970 / 1800))"
            + "-alt\(cruiseAltitudeFeet)"
    }

    private enum RiskError: Error { case noData }
}

private struct METResponse: Decodable {
    let properties: Properties
    struct Properties: Decodable { let timeseries: [Point] }

    struct Point: Decodable {
        let time: String
        let data: DataBlock

        var instant: Date {
            ISO8601DateFormatter().date(from: time) ?? .distantPast
        }

        var risk: RouteWeatherRisk {
            let details = data.instant.details
            let precipitation = data.next1Hours?.details.precipitationAmount ?? 0
            let fog = details.fogAreaFraction ?? 0
            let thunder = details.thunderstormProbability ?? 0
            if precipitation > 10 || fog >= 50 || thunder >= 30 { return .red }
            if precipitation >= 2 || fog >= 10 || thunder >= 10
                || (details.cloudAreaFractionLow ?? 0) >= 62.5 {
                return .blue
            }
            return .green
        }

        enum CodingKeys: String, CodingKey {
            case time, data
        }
    }

    struct DataBlock: Decodable {
        let instant: Instant
        let next1Hours: NextHours?
        enum CodingKeys: String, CodingKey {
            case instant
            case next1Hours = "next_1_hours"
        }
    }
    struct Instant: Decodable { let details: Details }
    struct NextHours: Decodable { let details: PrecipitationDetails }
    struct PrecipitationDetails: Decodable {
        let precipitationAmount: Double?
        enum CodingKeys: String, CodingKey {
            case precipitationAmount = "precipitation_amount"
        }
    }
    struct Details: Decodable {
        let fogAreaFraction: Double?
        let cloudAreaFractionLow: Double?
        let thunderstormProbability: Double?
        enum CodingKeys: String, CodingKey {
            case fogAreaFraction = "fog_area_fraction"
            case cloudAreaFractionLow = "cloud_area_fraction_low"
            case thunderstormProbability = "probability_of_thunder"
        }
    }
}

private enum AirportBearing {
    static func initial(from: AirportReference, to: AirportReference) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let delta = (to.longitude - from.longitude) * .pi / 180
        let y = sin(delta) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(delta)
        let value = atan2(y, x) * 180 / .pi
        return value < 0 ? value + 360 : value
    }
}

private struct RiskAPIResponse: Decodable {
    let hourly: RiskHourly
    let elevation: Double?

    func nearest(to instant: Date) -> RiskHour? {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let dates = hourly.time.compactMap(parser.date(from:))
        guard let index = dates.indices.min(by: {
            abs(dates[$0].timeIntervalSince(instant))
                < abs(dates[$1].timeIntervalSince(instant))
        }) else { return nil }
        return RiskHour(hourly: hourly, index: index)
    }
}

private struct RiskHour {
    let temperatureCelsius: Double?
    let dewPointCelsius: Double?
    let precipitationMillimeters: Double?
    let weatherCode: Int?
    let visibilityMeters: Double?
    let lowCloudCoverPercent: Double?
    let cape: Double?
    let pressureClouds: [(cover: Double?, heightMeters: Double?)]

    init(hourly: RiskHourly, index: Int) {
        temperatureCelsius = hourly.temperature2m[routeRiskSafe: index] ?? nil
        dewPointCelsius = hourly.dewPoint2m[routeRiskSafe: index] ?? nil
        precipitationMillimeters = hourly.precipitation[routeRiskSafe: index] ?? nil
        weatherCode = hourly.weatherCode[routeRiskSafe: index] ?? nil
        visibilityMeters = hourly.visibility[routeRiskSafe: index] ?? nil
        lowCloudCoverPercent = hourly.cloudCoverLow[routeRiskSafe: index] ?? nil
        cape = hourly.cape[routeRiskSafe: index] ?? nil
        pressureClouds = zip(hourly.pressureCloudCover, hourly.pressureHeight).map {
            ($0[routeRiskSafe: index] ?? nil, $1[routeRiskSafe: index] ?? nil)
        }
    }

    init(cached hour: DestinationFinderWeatherHour) {
        temperatureCelsius = hour.temperatureCelsius
        dewPointCelsius = hour.dewPointCelsius
        precipitationMillimeters = hour.precipitationMillimeters
        weatherCode = nil
        visibilityMeters = hour.visibilityMeters
        lowCloudCoverPercent = hour.lowCloudCoverPercent
        cape = nil
        pressureClouds = []
    }

    var estimatedCeilingBaseFeetAGL: Double? {
        guard (lowCloudCoverPercent ?? 0) >= 62.5,
              let temperatureCelsius,
              let dewPointCelsius
        else { return nil }
        return max(0, (temperatureCelsius - dewPointCelsius) * 400)
    }

    var brokenOvercastThicknessFeet: Double? {
        var longestMeters = 0.0
        var runStart: Double?
        for pair in pressureClouds {
            guard let cover = pair.cover, cover >= 62.5,
                  let height = pair.heightMeters else {
                runStart = nil
                continue
            }
            if runStart == nil { runStart = height }
            if let start = runStart {
                longestMeters = max(longestMeters, abs(height - start))
            }
        }
        return longestMeters > 0 ? longestMeters / 0.3048 : nil
    }

    func isSuitableAloft(around cruiseAltitudeFeet: Int) -> Bool {
        let thunderstormCode = weatherCode.map { [95, 96, 99].contains($0) } ?? false
        guard !thunderstormCode, (cape ?? 0) < 1_000 else { return false }

        let lower = Double(cruiseAltitudeFeet - 1_000)
        let upper = Double(cruiseAltitudeFeet + 1_000)
        let layer = pressureClouds.compactMap { pair -> Double? in
            guard let heightMeters = pair.heightMeters,
                  let cover = pair.cover else { return nil }
            let heightFeet = heightMeters / 0.3048
            return (lower...upper).contains(heightFeet) ? cover : nil
        }
        guard !layer.isEmpty else { return false }
        return (layer.max() ?? 100) <= 50
    }
}

private struct RiskHourly: Decodable {
    let time: [String]
    let temperature2m: [Double?]
    let dewPoint2m: [Double?]
    let precipitation: [Double?]
    let weatherCode: [Int?]
    let visibility: [Double?]
    let cloudCoverLow: [Double?]
    let cape: [Double?]
    let cloud1000, height1000, cloud975, height975, cloud950, height950: [Double?]
    let cloud925, height925, cloud900, height900, cloud850, height850: [Double?]
    let cloud800, height800, cloud700, height700: [Double?]

    var pressureCloudCover: [[Double?]] {
        [cloud1000, cloud975, cloud950, cloud925, cloud900, cloud850, cloud800, cloud700]
    }
    var pressureHeight: [[Double?]] {
        [height1000, height975, height950, height925, height900, height850, height800, height700]
    }

    enum CodingKeys: String, CodingKey {
        case time, precipitation, visibility, cape
        case temperature2m = "temperature_2m"
        case dewPoint2m = "dew_point_2m"
        case weatherCode = "weather_code"
        case cloudCoverLow = "cloud_cover_low"
        case cloud1000 = "cloud_cover_1000hPa", height1000 = "geopotential_height_1000hPa"
        case cloud975 = "cloud_cover_975hPa", height975 = "geopotential_height_975hPa"
        case cloud950 = "cloud_cover_950hPa", height950 = "geopotential_height_950hPa"
        case cloud925 = "cloud_cover_925hPa", height925 = "geopotential_height_925hPa"
        case cloud900 = "cloud_cover_900hPa", height900 = "geopotential_height_900hPa"
        case cloud850 = "cloud_cover_850hPa", height850 = "geopotential_height_850hPa"
        case cloud800 = "cloud_cover_800hPa", height800 = "geopotential_height_800hPa"
        case cloud700 = "cloud_cover_700hPa", height700 = "geopotential_height_700hPa"
    }
}

struct RouteRiskDots: View {
    let assessments: [RouteWeatherSegmentAssessment]

    private var hasAlpineSegment: Bool {
        assessments.contains(where: \.isAlpine)
    }

    private var alpineHelp: String {
        assessments
            .filter(\.isAlpine)
            .max { $0.risk < $1.risk }?
            .explanation
            ?? "Alpenkorridor wird geländebezogen bewertet"
    }

    var body: some View {
        HStack(spacing: 5) {
            if hasAlpineSegment {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)
                    .help(alpineHelp)
            }
            ForEach(0..<6, id: \.self) { index in
                let assessment = assessments.indices.contains(index)
                    ? assessments[index]
                    : .unavailable
                let risk = assessment.risk
                Circle()
                    .fill(risk.color)
                    .overlay(Circle().stroke(FlybookColor.navy.opacity(0.55), lineWidth: 0.8))
                    .shadow(color: risk.color.opacity(0.35), radius: 1.5)
                    .frame(width: 11, height: 11)
                    .help(
                        "Teilstrecke \(index + 1): \(assessment.explanation)"
                    )
            }
        }
        .frame(width: 100, height: 14)
    }
}
