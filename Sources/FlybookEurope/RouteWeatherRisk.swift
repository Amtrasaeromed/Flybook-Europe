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

    static func < (lhs: RouteWeatherRisk, rhs: RouteWeatherRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var color: Color {
        switch self {
        case .unavailable: return Color.gray
        case .green: return .green
        case .blue: return FlybookColor.blue
        case .red: return .red
        }
    }

    var title: String {
        switch self {
        case .unavailable: return "Keine ausreichenden Routendaten"
        case .green: return "Routenwetter unkritisch"
        case .blue: return "Routenwetter marginal"
        case .red: return "Routenwetter kritisch"
        }
    }
}

@MainActor
final class RouteWeatherRiskViewModel: ObservableObject {
    @Published private(set) var segments = Array(
        repeating: RouteWeatherRisk.unavailable,
        count: 6
    )

    func load(
        waypoints: [AirportReference],
        start: Date,
        end: Date,
        cruiseAltitudeFeet: Int,
        forceRefresh: Bool = false
    ) async {
        guard waypoints.count >= 2 else {
            segments = Array(repeating: .unavailable, count: 6)
            return
        }
        do {
            segments = try await RouteWeatherRiskService.shared.risks(
                waypoints: waypoints,
                start: start,
                end: end,
                cruiseAltitudeFeet: cruiseAltitudeFeet,
                forceRefresh: forceRefresh
            )
        } catch {
            segments = Array(repeating: .unavailable, count: 6)
        }
    }
}

actor RouteWeatherRiskService {
    static let shared = RouteWeatherRiskService()
    private let cacheLifetime: TimeInterval = 30 * 60
    private var cache: [String: (Date, [RouteWeatherRisk])] = [:]

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
        var result = Array(repeating: RouteWeatherRisk.green, count: 6)
        var hasData = Array(repeating: false, count: 6)
        do {
            let responses = try await fetch(samples)
            guard responses.count == samples.count else { throw RiskError.noData }
            for (sample, response) in zip(samples, responses) {
                guard let hour = response.nearest(to: sample.instant) else { continue }
                hasData[sample.segment] = true
                result[sample.segment] = max(
                    result[sample.segment],
                    classify(hour, cruiseAltitudeFeet: cruiseAltitudeFeet)
                )
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
                result[sample.segment] = classify(
                    hour,
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
                result[segment] = risk
                hasData[segment] = true
            }
        }
        cache[key] = (Date(), result)
        return result
    }

    private func classify(
        _ hour: RiskHour,
        cruiseAltitudeFeet: Int
    ) -> RouteWeatherRisk {
        var risk = RouteWeatherRisk.green
        var critical = false

        if let visibility = hour.visibilityMeters {
            if visibility < 1_500 { critical = true }
            if visibility < 8_000 { risk = .blue }
        }
        if let rain = hour.precipitationMillimeters {
            if rain > 10 { critical = true }
            if rain >= 2 { risk = .blue }
        }
        if let code = hour.weatherCode {
            if [45, 48, 95, 96, 99].contains(code) { critical = true }
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

        if (hour.lowCloudCoverPercent ?? 0) >= 62.5,
           let temperature = hour.temperatureCelsius,
           let dewPoint = hour.dewPointCelsius {
            let baseFeetAGL = max(0, (temperature - dewPoint) * 400)
            if baseFeetAGL < 1_000 { critical = true }
            if baseFeetAGL <= 2_500 { risk = .blue }
        }

        if let thickness = hour.brokenOvercastThicknessFeet {
            if thickness >= 6_000 { critical = true }
            if thickness >= 4_000 { risk = .blue }
        }
        guard critical else { return risk }

        // A critical surface layer may be overflown, but it remains operationally
        // relevant for diversion and landing. Therefore red can improve only to blue.
        return hour.isSuitableAloft(around: cruiseAltitudeFeet) ? .blue : .red
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
        let (data, response) = try await FlightNetwork.data(
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
            var request = URLRequest(url: url)
            request.setValue(
                "FlybookEurope/1.0 aviation-weather-planner",
                forHTTPHeaderField: "User-Agent"
            )
            do {
                let (data, response) = try await FlightNetwork.data(
                    for: request,
                    priority: .low
                )
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let decoded = try? JSONDecoder().decode(METResponse.self, from: data),
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
    let risks: [RouteWeatherRisk]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<6, id: \.self) { index in
                let risk = risks.indices.contains(index) ? risks[index] : .unavailable
                Circle()
                    .fill(risk.color)
                    .overlay(Circle().stroke(FlybookColor.navy.opacity(0.55), lineWidth: 0.8))
                    .shadow(color: risk.color.opacity(0.35), radius: 1.5)
                    .frame(width: 11, height: 11)
                    .help("Teilstrecke \(index + 1): \(risk.title)")
            }
        }
        .frame(width: 100, height: 14)
    }
}
