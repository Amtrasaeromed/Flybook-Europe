import Foundation

struct EDFZWeatherSample: Hashable {
    let validTime: Date
    let windDirectionDegrees: Double?
    let windSpeedKnots: Double?
    let windGustKnots: Double?
    let temperatureCelsius: Double?
    let weatherCode: Int?
    let visibilityMeters: Double?
    let ceilingFeetAGL: Double?
    let category: FlightCategory
    let pressureMSLHPA: Double?
}

struct EDFZForecast: Hashable {
    let retrievedAt: Date
    let samples: [EDFZWeatherSample]

    func sample(nearestTo instant: Date?) -> EDFZWeatherSample? {
        guard let instant, !samples.isEmpty else { return nil }
        let nearest = samples.min {
            abs($0.validTime.timeIntervalSince(instant))
                < abs($1.validTime.timeIntervalSince(instant))
        }
        guard let nearest,
              abs(nearest.validTime.timeIntervalSince(instant)) <= 90 * 60
        else { return nil }
        return nearest
    }
}

enum EDFZRunway {
    static func activeRunway(
        windFromDegrees: Double,
        speedKnots: Double
    ) -> String {
        guard speedKnots >= 0.5 else { return "07/25" }
        let difference = angularDifference(
            windFromDegrees,
            250.0
        )
        let component = speedKnots * cos(difference * .pi / 180.0)
        if abs(component) < 0.05 { return "07/25" }
        return component > 0 ? "25" : "07"
    }

    private static func angularDifference(
        _ first: Double,
        _ second: Double
    ) -> Double {
        let raw = abs(
            (first - second)
                .truncatingRemainder(dividingBy: 360.0)
        )
        return min(raw, 360.0 - raw)
    }
}

actor EDFZWeatherService {
    static let shared = EDFZWeatherService()

    func forecast(
        plannedDate: Date,
        airport: AirportReference
    ) async throws -> EDFZForecast {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = airport.timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: plannedDate)

        var components = URLComponents(
            string: "https://api.open-meteo.com/v1/dwd-icon"
        )
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(airport.latitude)),
            URLQueryItem(name: "longitude", value: String(airport.longitude)),
            URLQueryItem(
                name: "timezone",
                value: airport.timeZone.identifier
            ),
            URLQueryItem(name: "start_date", value: day),
            URLQueryItem(name: "end_date", value: day),
            URLQueryItem(name: "models", value: "icon_seamless"),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(
                name: "hourly",
                value: "wind_speed_10m,wind_direction_10m,wind_gusts_10m,temperature_2m,weather_code,visibility,cloud_cover_low,pressure_msl"
            )
        ]
        guard let url = components?.url else {
            throw EDFZWeatherError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { throw EDFZWeatherError.serverError }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let parser = DateFormatter()
        parser.calendar = calendar
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = calendar.timeZone
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let count = decoded.hourly.time.count
        let samples = (0..<count).compactMap { index -> EDFZWeatherSample? in
            guard let time = parser.date(from: decoded.hourly.time[index]) else {
                return nil
            }
            let visibility = value(decoded.hourly.visibility, index)
            let ceiling = estimateCeiling(
                lowCloudPercent: value(
                    decoded.hourly.cloudCoverLow, index
                )
            )
            return EDFZWeatherSample(
                validTime: time,
                windDirectionDegrees: value(decoded.hourly.windDirection10m, index),
                windSpeedKnots: value(decoded.hourly.windSpeed10m, index),
                windGustKnots: value(decoded.hourly.windGusts10m, index),
                temperatureCelsius: value(
                    decoded.hourly.temperature2m, index
                ),
                weatherCode: decoded.hourly.weatherCode.indices.contains(index)
                    ? decoded.hourly.weatherCode[index]
                    : nil,
                visibilityMeters: visibility,
                ceilingFeetAGL: ceiling,
                category: flightCategory(
                    visibilityMeters: visibility,
                    ceilingFeet: ceiling
                ),
                pressureMSLHPA: value(decoded.hourly.pressureMSL, index)
            )
        }
        return EDFZForecast(retrievedAt: Date(), samples: samples)
    }

    private func estimateCeiling(
        lowCloudPercent: Double?
    ) -> Double? {
        guard let lowCloudPercent else { return nil }
        if lowCloudPercent >= 90 { return 800 }
        if lowCloudPercent >= 75 { return 1800 }
        if lowCloudPercent >= 50 { return 3000 }
        return nil
    }

    private func flightCategory(
        visibilityMeters: Double?,
        ceilingFeet: Double?
    ) -> FlightCategory {
        let visibilitySM = visibilityMeters.map { $0 / 1609.344 }
        if ceilingFeet.map({ $0 < 500 }) == true
            || visibilitySM.map({ $0 < 1 }) == true { return .lifr }
        if ceilingFeet.map({ $0 < 1000 }) == true
            || visibilitySM.map({ $0 < 3 }) == true { return .ifr }
        if ceilingFeet.map({ $0 <= 3000 }) == true
            || visibilitySM.map({ $0 <= 5 }) == true { return .mvfr }
        if ceilingFeet != nil || visibilitySM != nil { return .vfr }
        return .unavailable
    }

    private func value(_ values: [Double?], _ index: Int) -> Double? {
        guard values.indices.contains(index) else { return nil }
        return values[index]
    }
}

private struct Response: Decodable {
    let hourly: Hourly
}

private struct Hourly: Decodable {
    let time: [String]
    let windSpeed10m: [Double?]
    let windDirection10m: [Double?]
    let windGusts10m: [Double?]
    let temperature2m: [Double?]
    let weatherCode: [Int?]
    let visibility: [Double?]
    let cloudCoverLow: [Double?]
    let pressureMSL: [Double?]

    enum CodingKeys: String, CodingKey {
        case time
        case windSpeed10m = "wind_speed_10m"
        case windDirection10m = "wind_direction_10m"
        case windGusts10m = "wind_gusts_10m"
        case temperature2m = "temperature_2m"
        case weatherCode = "weather_code"
        case visibility
        case cloudCoverLow = "cloud_cover_low"
        case pressureMSL = "pressure_msl"
    }
}

enum EDFZWeatherError: LocalizedError {
    case invalidURL
    case serverError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Ungültige Wetteradresse."
        case .serverError: return "EDFZ-Wetterdaten sind nicht verfügbar."
        }
    }
}
