import Foundation

struct EDFZWeatherSample: Hashable {
    let validTime: Date
    let windDirectionDegrees: Double?
    let windSpeedKnots: Double?
    let windGustKnots: Double?
    let temperatureCelsius: Double?
    let weatherCode: Int?
    let visibilityMeters: Double?
    let lowCloudCoverPercent: Double?
    let lowestCloudBaseFeetAGL: Double?
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
        for airportICAO: String,
        windFromDegrees: Double,
        speedKnots: Double
    ) -> String? {
        let runways: (
            firstLabel: String,
            firstHeading: Double,
            secondLabel: String,
            secondHeading: Double
        )

        switch airportICAO.uppercased() {
        case "EDFZ", "EDKA", "EDWJ":
            runways = ("07", 70, "25", 250)
        case "EHMZ", "EDMZ":
            runways = ("09", 87, "27", 267)
        default:
            return nil
        }

        guard speedKnots >= 0.5 else {
            return "\(runways.firstLabel)/\(runways.secondLabel)"
        }

        let firstDifference = angularDifference(
            windFromDegrees,
            runways.firstHeading
        )
        let secondDifference = angularDifference(
            windFromDegrees,
            runways.secondHeading
        )
        return firstDifference <= secondDifference
            ? runways.firstLabel
            : runways.secondLabel
    }

    static func activeRunway(
        windFromDegrees: Double,
        speedKnots: Double
    ) -> String {
        activeRunway(
            for: "EDFZ",
            windFromDegrees: windFromDegrees,
            speedKnots: speedKnots
        ) ?? "07/25"
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
        var displayedCalendar = Calendar(identifier: .gregorian)
        displayedCalendar.timeZone = DestinationTimeZone.edfz
        let displayedParts = displayedCalendar.dateComponents(
            [.year, .month, .day],
            from: plannedDate
        )
        guard
            let year = displayedParts.year,
            let month = displayedParts.month,
            let dayOfMonth = displayedParts.day
        else {
            throw EDFZWeatherError.invalidURL
        }
        let startDay = String(
            format: "%04d-%02d-%02d",
            year,
            month,
            dayOfMonth
        )
        let followingDate =
            displayedCalendar.date(
                byAdding: .day,
                value: 1,
                to: plannedDate
            ) ?? plannedDate
        let followingParts = displayedCalendar.dateComponents(
            [.year, .month, .day],
            from: followingDate
        )
        let endDay = String(
            format: "%04d-%02d-%02d",
            followingParts.year ?? year,
            followingParts.month ?? month,
            followingParts.day ?? dayOfMonth
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = airport.timeZone

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
            URLQueryItem(name: "start_date", value: startDay),
            URLQueryItem(name: "end_date", value: endDay),
            URLQueryItem(name: "models", value: "icon_seamless"),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(
                name: "hourly",
                value: "wind_speed_10m,wind_direction_10m,wind_gusts_10m,temperature_2m,dew_point_2m,weather_code,visibility,cloud_cover_low,pressure_msl"
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
            let lowCloudCover = value(
                decoded.hourly.cloudCoverLow, index
            )
            let cloudBase = estimatedCloudBaseFeet(
                temperature: value(
                    decoded.hourly.temperature2m, index
                ),
                dewPoint: value(
                    decoded.hourly.dewPoint2m, index
                )
            )
            let ceiling = estimateCeiling(
                lowCloudPercent: lowCloudCover,
                cloudBaseFeet: cloudBase
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
                lowCloudCoverPercent: lowCloudCover,
                lowestCloudBaseFeetAGL: cloudBase,
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
        lowCloudPercent: Double?,
        cloudBaseFeet: Double?
    ) -> Double? {
        guard let lowCloudPercent,
              lowCloudPercent >= 62.5
        else { return nil }
        // Only BKN/OVC layers define a ceiling. SCT is not a ceiling.
        return cloudBaseFeet
    }

    private func estimatedCloudBaseFeet(
        temperature: Double?,
        dewPoint: Double?
    ) -> Double? {
        guard let temperature, let dewPoint else { return nil }
        return max(0, temperature - dewPoint) * 400
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
    let dewPoint2m: [Double?]
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
        case dewPoint2m = "dew_point_2m"
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
