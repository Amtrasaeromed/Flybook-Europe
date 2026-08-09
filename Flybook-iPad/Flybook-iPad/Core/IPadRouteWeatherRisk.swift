import Foundation
import SwiftUI

private extension Array {
    subscript(routeRiskSafe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum IPadRouteWeatherRisk: Int, Comparable, Sendable {
    case unavailable = -1
    case green = 0
    case blue = 1
    case red = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var color: Color {
        switch self {
        case .unavailable: return .gray
        case .green: return .green
        case .blue: return Color.dashboardBlue
        case .red: return .red
        }
    }
}

@MainActor
final class IPadRouteWeatherRiskViewModel: ObservableObject {
    @Published private(set) var segments = Array(
        repeating: IPadRouteWeatherRisk.unavailable,
        count: 10
    )

    func load(
        waypoints: [Airport],
        start: Date,
        end: Date,
        cruiseAltitudeFeet: Int
    ) async {
        guard waypoints.count >= 2 else {
            segments = Array(repeating: .unavailable, count: 10)
            return
        }
        do {
            segments = try await IPadRouteWeatherRiskService.shared.risks(
                waypoints: waypoints,
                start: start,
                end: end,
                cruiseAltitudeFeet: cruiseAltitudeFeet
            )
        } catch {
            segments = Array(repeating: .unavailable, count: 10)
        }
    }
}

actor IPadRouteWeatherRiskService {
    static let shared = IPadRouteWeatherRiskService()

    private let segmentCount = 10
    private let cacheLifetime: TimeInterval = 30 * 60
    private var cache: [String: (date: Date, risks: [IPadRouteWeatherRisk])] = [:]

    private struct SamplePoint {
        let latitude: Double
        let longitude: Double
        let instant: Date
        let segment: Int
    }

    func risks(
        waypoints: [Airport],
        start: Date,
        end: Date,
        cruiseAltitudeFeet: Int
    ) async throws -> [IPadRouteWeatherRisk] {
        let key = waypoints.map(\.icao).joined(separator: "-")
            + "-\(Int(start.timeIntervalSince1970 / 1800))"
            + "-\(Int(end.timeIntervalSince1970 / 1800))-alt\(cruiseAltitudeFeet)"
        if let cached = cache[key], Date().timeIntervalSince(cached.date) < cacheLifetime {
            return cached.risks
        }

        let samples = corridorSamples(waypoints: waypoints, start: start, end: end)
        let responses = try await fetch(samples)
        guard responses.count == samples.count else { throw RiskError.noData }

        var result = Array(repeating: IPadRouteWeatherRisk.green, count: segmentCount)
        var hasData = Array(repeating: false, count: segmentCount)
        for (sample, response) in zip(samples, responses) {
            guard let hour = response.nearest(to: sample.instant) else { continue }
            hasData[sample.segment] = true
            result[sample.segment] = max(
                result[sample.segment],
                classify(hour, cruiseAltitudeFeet: cruiseAltitudeFeet)
            )
        }
        for index in result.indices where !hasData[index] {
            result[index] = .unavailable
        }
        cache[key] = (Date(), result)
        return result
    }

    private func classify(
        _ hour: RiskHour,
        cruiseAltitudeFeet: Int
    ) -> IPadRouteWeatherRisk {
        var risk = IPadRouteWeatherRisk.green
        var critical = false

        if let visibility = hour.visibilityMeters {
            if visibility < 1_500 { critical = true }
            if visibility < 8_000 { risk = .blue }
        }
        if let rain = hour.precipitationMillimeters {
            if rain > 10 { critical = true }
            if rain >= 2 { risk = .blue }
        }
        if let code = hour.weatherCode, [45, 48, 95, 96, 99].contains(code) {
            critical = true
        }
        if let temperature = hour.temperatureCelsius,
           let dewPoint = hour.dewPointCelsius,
           temperature - dewPoint <= 2,
           (hour.visibilityMeters ?? 10_000) < 8_000 {
            risk = .blue
        }
        if let cape = hour.cape {
            if cape >= 1_000, (hour.precipitationMillimeters ?? 0) > 0 { critical = true }
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
        return hour.isSuitableAloft(around: cruiseAltitudeFeet) ? .blue : .red
    }

    private func corridorSamples(
        waypoints: [Airport],
        start: Date,
        end: Date
    ) -> [SamplePoint] {
        let legs = zip(waypoints, waypoints.dropFirst()).map { first, second in
            (first, second, distanceNM(from: first, to: second))
        }
        let total = max(0.1, legs.reduce(0) { $0 + $1.2 })
        let duration = end.timeIntervalSince(start)

        return (0..<segmentCount).flatMap { segment -> [SamplePoint] in
            let fraction = (Double(segment) + 0.5) / Double(segmentCount)
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
            let center = geographicPoint(from: selected.0, to: selected.1, fraction: legFraction)
            let course = initialBearing(from: selected.0, to: selected.1)
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
            URLQueryItem(name: "latitude", value: samples.map { String(format: "%.4f", $0.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: samples.map { String(format: "%.4f", $0.longitude) }.joined(separator: ",")),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(name: "start_date", value: formatter.string(from: firstInstant)),
            URLQueryItem(name: "end_date", value: formatter.string(from: lastInstant)),
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
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { throw RiskError.noData }
        return try JSONDecoder().decode([RiskAPIResponse].self, from: data)
    }

    private func geographicPoint(
        from: Airport,
        to: Airport,
        fraction: Double
    ) -> (latitude: Double, longitude: Double) {
        (
            from.latitude + (to.latitude - from.latitude) * fraction,
            from.longitude + (to.longitude - from.longitude) * fraction
        )
    }

    private func distanceNM(from: Airport, to: Airport) -> Double {
        let earthRadiusNM = 3_440.065
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLat = (to.latitude - from.latitude) * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return earthRadiusNM * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private func initialBearing(from: Airport, to: Airport) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let delta = (to.longitude - from.longitude) * .pi / 180
        let value = atan2(
            sin(delta) * cos(lat2),
            cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(delta)
        ) * 180 / .pi
        return value < 0 ? value + 360 : value
    }

    private func destinationPoint(
        latitude: Double,
        longitude: Double,
        bearing: Double,
        distanceNM: Double
    ) -> (latitude: Double, longitude: Double) {
        let angular = distanceNM / 3_440.065
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let bearingRadians = bearing * .pi / 180
        let lat2 = asin(
            sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearingRadians)
        )
        let lon2 = lon1 + atan2(
            sin(bearingRadians) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2)
        )
        return (lat2 * 180 / .pi, lon2 * 180 / .pi)
    }

    private enum RiskError: Error { case noData }
}

struct IPadRouteRiskDots: View {
    let risks: [IPadRouteWeatherRisk]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<10, id: \.self) { index in
                let risk = risks.indices.contains(index) ? risks[index] : .unavailable
                Circle()
                    .fill(risk.color)
                    .overlay { Circle().stroke(Color.dashboardNavy.opacity(0.5), lineWidth: 0.7) }
                    .frame(width: 10, height: 10)
                    .accessibilityLabel("Streckenabschnitt \(index + 1)")
            }
        }
        .frame(width: 145, height: 16)
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
            abs(dates[$0].timeIntervalSince(instant)) < abs(dates[$1].timeIntervalSince(instant))
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

    var brokenOvercastThicknessFeet: Double? {
        var longestMeters = 0.0
        var runStart: Double?
        for pair in pressureClouds {
            guard let cover = pair.cover, cover >= 62.5, let height = pair.heightMeters else {
                runStart = nil
                continue
            }
            if runStart == nil { runStart = height }
            if let start = runStart { longestMeters = max(longestMeters, abs(height - start)) }
        }
        return longestMeters > 0 ? longestMeters / 0.3048 : nil
    }

    func isSuitableAloft(around cruiseAltitudeFeet: Int) -> Bool {
        let thunderstorm = weatherCode.map { [95, 96, 99].contains($0) } ?? false
        guard !thunderstorm, (cape ?? 0) < 1_000 else { return false }
        let lower = Double(cruiseAltitudeFeet - 1_000)
        let upper = Double(cruiseAltitudeFeet + 1_000)
        let layer = pressureClouds.compactMap { pair -> Double? in
            guard let height = pair.heightMeters, let cover = pair.cover else { return nil }
            return (lower...upper).contains(height / 0.3048) ? cover : nil
        }
        guard !layer.isEmpty else { return false }
        return (layer.max() ?? 100) <= 50
    }
}

private struct RiskHourly: Decodable {
    let time: [String]
    let temperature2m, dewPoint2m, precipitation: [Double?]
    let weatherCode: [Int?]
    let visibility, cloudCoverLow, cape: [Double?]
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
