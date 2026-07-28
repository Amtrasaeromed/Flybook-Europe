import Foundation

struct EDFZWeatherSample: Hashable {
    let validTime: Date
    let windDirectionDegrees: Double?
    let windSpeedKnots: Double?
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

    private let latitude = 49.9675
    private let longitude = 8.1472

    func forecast(plannedDate: Date) async throws -> EDFZForecast {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
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
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "Europe/Berlin"),
            URLQueryItem(name: "start_date", value: day),
            URLQueryItem(name: "end_date", value: day),
            URLQueryItem(name: "models", value: "icon_d2"),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(
                name: "hourly",
                value: "wind_speed_10m,wind_direction_10m,pressure_msl"
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
            return EDFZWeatherSample(
                validTime: time,
                windDirectionDegrees: value(decoded.hourly.windDirection10m, index),
                windSpeedKnots: value(decoded.hourly.windSpeed10m, index),
                pressureMSLHPA: value(decoded.hourly.pressureMSL, index)
            )
        }
        return EDFZForecast(retrievedAt: Date(), samples: samples)
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
    let pressureMSL: [Double?]

    enum CodingKeys: String, CodingKey {
        case time
        case windSpeed10m = "wind_speed_10m"
        case windDirection10m = "wind_direction_10m"
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
