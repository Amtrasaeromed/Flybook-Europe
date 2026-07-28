import Foundation

actor RouteWindService {
    static let shared = RouteWindService()

    func wind(
        for destination: Destination,
        plannedInstant: Date,
        altitudeFeet: Int
    ) async throws -> RouteWind {
        guard
            let destinationLatitude = destination.latitude,
            let destinationLongitude = destination.longitude
        else {
            throw RouteWindError.coordinatesMissing
        }

        let midpoint = WindMath.midpoint(
            latitude1: FlightDateTime.edfzLatitude,
            longitude1: FlightDateTime.edfzLongitude,
            latitude2: destinationLatitude,
            longitude2: destinationLongitude
        )

        let course = WindMath.initialBearing(
            latitude1: FlightDateTime.edfzLatitude,
            longitude1: FlightDateTime.edfzLongitude,
            latitude2: destinationLatitude,
            longitude2: destinationLongitude
        )

        let d2Limit = Date().addingTimeInterval(48 * 60 * 60)

        if plannedInstant <= d2Limit {
            do {
                return try await fetch(
                    midpoint: midpoint,
                    course: course,
                    plannedInstant: plannedInstant,
                    altitudeFeet: altitudeFeet,
                    model: "icon_d2"
                )
            } catch {
                return try await fetch(
                    midpoint: midpoint,
                    course: course,
                    plannedInstant: plannedInstant,
                    altitudeFeet: altitudeFeet,
                    model: "icon_eu"
                )
            }
        }

        return try await fetch(
            midpoint: midpoint,
            course: course,
            plannedInstant: plannedInstant,
            altitudeFeet: altitudeFeet,
            model: "icon_eu"
        )
    }

    private func fetch(
        midpoint: (latitude: Double, longitude: Double),
        course: Double,
        plannedInstant: Date,
        altitudeFeet: Int,
        model: String
    ) async throws -> RouteWind {
        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc

        let dayBefore = calendar.date(
            byAdding: .day,
            value: -1,
            to: plannedInstant
        ) ?? plannedInstant

        let dayAfter = calendar.date(
            byAdding: .day,
            value: 1,
            to: plannedInstant
        ) ?? plannedInstant

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = utc
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var components = URLComponents(
            string: "https://api.open-meteo.com/v1/dwd-icon"
        )

        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(midpoint.latitude)),
            URLQueryItem(name: "longitude", value: String(midpoint.longitude)),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(name: "start_date", value: dateFormatter.string(from: dayBefore)),
            URLQueryItem(name: "end_date", value: dateFormatter.string(from: dayAfter)),
            URLQueryItem(name: "models", value: model),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(
                name: "hourly",
                value: [
                    "wind_speed_925hPa",
                    "wind_direction_925hPa",
                    "geopotential_height_925hPa",
                    "wind_speed_850hPa",
                    "wind_direction_850hPa",
                    "geopotential_height_850hPa",
                    "wind_speed_700hPa",
                    "wind_direction_700hPa",
                    "geopotential_height_700hPa"
                ].joined(separator: ",")
            )
        ]

        guard let url = components?.url else {
            throw RouteWindError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            throw RouteWindError.serverError
        }

        let api = try JSONDecoder().decode(
            RouteWindAPIResponse.self,
            from: data
        )

        let parsedTimes = parseTimes(api.hourly.time)

        guard
            let bracket = timeBracket(
                for: plannedInstant,
                parsedTimes: parsedTimes
            )
        else {
            throw RouteWindError.noForecast
        }

        let lower = interpolateAltitude(
            index: bracket.lowerIndex,
            targetHeightMeters: Double(altitudeFeet) * 0.3048,
            hourly: api.hourly
        )

        let upper = interpolateAltitude(
            index: bracket.upperIndex,
            targetHeightMeters: Double(altitudeFeet) * 0.3048,
            hourly: api.hourly
        )

        let sample = interpolateTime(
            lower: lower,
            upper: upper,
            fraction: bracket.fraction
        )

        guard
            let direction = sample.directionDegrees,
            let speed = sample.speedKnots
        else {
            throw RouteWindError.noForecast
        }

        return RouteWind(
            retrievedAt: Date(),
            validTime: plannedInstant,
            midpointLatitude: midpoint.latitude,
            midpointLongitude: midpoint.longitude,
            altitudeFeet: altitudeFeet,
            directionDegrees: direction,
            speedKnots: speed,
            outboundCourseDegrees: course
        )
    }

    private func parseTimes(_ values: [String]) -> [Date?] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return values.map { formatter.date(from: $0) }
    }

    private func timeBracket(
        for target: Date,
        parsedTimes: [Date?]
    ) -> (
        lowerIndex: Int,
        upperIndex: Int,
        fraction: Double
    )? {
        let valid = parsedTimes.enumerated().compactMap {
            index, date -> (Int, Date)? in
            guard let date else { return nil }
            return (index, date)
        }

        guard !valid.isEmpty else { return nil }

        if let first = valid.first, target <= first.1 {
            return (first.0, first.0, 0)
        }

        if let last = valid.last, target >= last.1 {
            return (last.0, last.0, 0)
        }

        for index in 0..<(valid.count - 1) {
            let lower = valid[index]
            let upper = valid[index + 1]

            guard target >= lower.1, target <= upper.1 else {
                continue
            }

            let interval = upper.1.timeIntervalSince(lower.1)
            let fraction = interval > 0
                ? target.timeIntervalSince(lower.1) / interval
                : 0

            return (
                lower.0,
                upper.0,
                max(0, min(1, fraction))
            )
        }

        return nil
    }

    private func interpolateTime(
        lower: WindSample,
        upper: WindSample,
        fraction: Double
    ) -> WindSample {
        guard
            let lowerDirection = lower.directionDegrees,
            let lowerSpeed = lower.speedKnots
        else {
            return upper
        }

        guard
            let upperDirection = upper.directionDegrees,
            let upperSpeed = upper.speedKnots
        else {
            return lower
        }

        let lowerVector = windVector(
            directionDegrees: lowerDirection,
            speedKnots: lowerSpeed
        )

        let upperVector = windVector(
            directionDegrees: upperDirection,
            speedKnots: upperSpeed
        )

        return windSample(
            east:
                lowerVector.east
                + fraction * (upperVector.east - lowerVector.east),
            north:
                lowerVector.north
                + fraction * (upperVector.north - lowerVector.north)
        )
    }

    private func interpolateAltitude(
        index: Int,
        targetHeightMeters: Double,
        hourly: RouteWindHourly
    ) -> WindSample {
        let raw: [(Double?, Double?, Double?)] = [
            (
                value(hourly.geopotentialHeight925, index),
                value(hourly.windSpeed925, index),
                value(hourly.windDirection925, index)
            ),
            (
                value(hourly.geopotentialHeight850, index),
                value(hourly.windSpeed850, index),
                value(hourly.windDirection850, index)
            ),
            (
                value(hourly.geopotentialHeight700, index),
                value(hourly.windSpeed700, index),
                value(hourly.windDirection700, index)
            )
        ]

        let levels = raw.compactMap {
            height, speed, direction -> WindLevel? in
            guard let height, let speed, let direction else {
                return nil
            }
            return WindLevel(
                height: height,
                direction: direction,
                speed: speed
            )
        }
        .sorted { $0.height < $1.height }

        guard !levels.isEmpty else {
            return WindSample(
                directionDegrees: nil,
                speedKnots: nil
            )
        }

        if
            let lower = levels.last(where: {
                $0.height <= targetHeightMeters
            }),
            let upper = levels.first(where: {
                $0.height >= targetHeightMeters
            }),
            upper.height != lower.height
        {
            let fraction =
                (targetHeightMeters - lower.height)
                / (upper.height - lower.height)

            let lowerVector = windVector(
                directionDegrees: lower.direction,
                speedKnots: lower.speed
            )

            let upperVector = windVector(
                directionDegrees: upper.direction,
                speedKnots: upper.speed
            )

            return windSample(
                east:
                    lowerVector.east
                    + fraction
                    * (upperVector.east - lowerVector.east),
                north:
                    lowerVector.north
                    + fraction
                    * (upperVector.north - lowerVector.north)
            )
        }

        guard let nearest = levels.min(by: {
            abs($0.height - targetHeightMeters)
                < abs($1.height - targetHeightMeters)
        }) else {
            return WindSample(
                directionDegrees: nil,
                speedKnots: nil
            )
        }

        return WindSample(
            directionDegrees: nearest.direction,
            speedKnots: nearest.speed
        )
    }

    private func windVector(
        directionDegrees: Double,
        speedKnots: Double
    ) -> (east: Double, north: Double) {
        let radians = directionDegrees * .pi / 180.0
        return (
            east: -speedKnots * sin(radians),
            north: -speedKnots * cos(radians)
        )
    }

    private func windSample(
        east: Double,
        north: Double
    ) -> WindSample {
        let speed = hypot(east, north)

        guard speed > 0.01 else {
            return WindSample(
                directionDegrees: 0,
                speedKnots: 0
            )
        }

        let towardDegrees =
            atan2(east, north) * 180.0 / .pi

        return WindSample(
            directionDegrees: WindMath.normalized(
                towardDegrees + 180.0
            ),
            speedKnots: speed
        )
    }

    private func value<T>(
        _ values: [T?],
        _ index: Int
    ) -> T? {
        values.indices.contains(index)
            ? values[index]
            : nil
    }
}

private struct WindLevel {
    let height: Double
    let direction: Double
    let speed: Double
}

private struct RouteWindAPIResponse: Decodable {
    let hourly: RouteWindHourly
}

private struct RouteWindHourly: Decodable {
    let time: [String]
    let windSpeed925: [Double?]
    let windDirection925: [Double?]
    let geopotentialHeight925: [Double?]
    let windSpeed850: [Double?]
    let windDirection850: [Double?]
    let geopotentialHeight850: [Double?]
    let windSpeed700: [Double?]
    let windDirection700: [Double?]
    let geopotentialHeight700: [Double?]

    enum CodingKeys: String, CodingKey {
        case time
        case windSpeed925 = "wind_speed_925hPa"
        case windDirection925 = "wind_direction_925hPa"
        case geopotentialHeight925 = "geopotential_height_925hPa"
        case windSpeed850 = "wind_speed_850hPa"
        case windDirection850 = "wind_direction_850hPa"
        case geopotentialHeight850 = "geopotential_height_850hPa"
        case windSpeed700 = "wind_speed_700hPa"
        case windDirection700 = "wind_direction_700hPa"
        case geopotentialHeight700 = "geopotential_height_700hPa"
    }
}

enum RouteWindError: LocalizedError {
    case coordinatesMissing
    case invalidURL
    case serverError
    case noForecast

    var errorDescription: String? {
        switch self {
        case .coordinatesMissing:
            return "Koordinaten für die Windberechnung fehlen."
        case .invalidURL:
            return "Die Windabfrage konnte nicht erstellt werden."
        case .serverError:
            return "Der Winddienst ist derzeit nicht erreichbar."
        case .noForecast:
            return "Für diesen Zeitpunkt liegt keine Windprognose in der gewählten Flughöhe vor."
        }
    }
}
