import Foundation

actor RouteWindService {
    static let shared = RouteWindService()
    private var apiCache:
        [URL: (retrievedAt: Date, response: RouteWindAPIResponse)] = [:]
    private let apiCacheLifetime: TimeInterval = 10 * 60

    func wind(
        for destination: AirportReference,
        origin: AirportReference,
        plannedStart: Date,
        plannedEnd: Date,
        altitudeFeet: Int,
        isReturn: Bool
    ) async throws -> RouteWind {
        let destinationLatitude = destination.latitude
        let destinationLongitude = destination.longitude

        let outboundCourse = WindMath.initialBearing(
            latitude1: origin.latitude,
            longitude1: origin.longitude,
            latitude2: destinationLatitude,
            longitude2: destinationLongitude
        )

        let start = isReturn
            ? (destinationLatitude, destinationLongitude)
            : (origin.latitude, origin.longitude)
        let end = isReturn
            ? (origin.latitude, origin.longitude)
            : (destinationLatitude, destinationLongitude)
        let fractions = [0.25, 0.5, 0.75]
        let duration = plannedEnd.timeIntervalSince(plannedStart)
        let requests = fractions.map { fraction in
            let point = WindMath.point(
                latitude1: start.0,
                longitude1: start.1,
                latitude2: end.0,
                longitude2: end.1,
                fraction: fraction
            )
            let before = WindMath.point(
                latitude1: start.0,
                longitude1: start.1,
                latitude2: end.0,
                longitude2: end.1,
                fraction: max(0, fraction - 0.01)
            )
            let after = WindMath.point(
                latitude1: start.0,
                longitude1: start.1,
                latitude2: end.0,
                longitude2: end.1,
                fraction: min(1, fraction + 0.01)
            )
            return RouteWindRequestPoint(
                latitude: point.latitude,
                longitude: point.longitude,
                course: WindMath.initialBearing(
                    latitude1: before.latitude,
                    longitude1: before.longitude,
                    latitude2: after.latitude,
                    longitude2: after.longitude
                ),
                instant: plannedStart.addingTimeInterval(
                    duration * fraction
                )
            )
        }

        let d2Limit = Date().addingTimeInterval(48 * 60 * 60)
        let model = requests.allSatisfy { $0.instant <= d2Limit }
            ? "icon_d2"
            : "icon_eu"

        let samples: [RouteWindPoint]
        if model == "icon_d2" {
            do {
                samples = try await fetchPoints(
                    requests,
                    altitudeFeet: altitudeFeet,
                    model: "icon_d2"
                )
            } catch {
                samples = try await fetchPoints(
                    requests,
                    altitudeFeet: altitudeFeet,
                    model: "icon_eu"
                )
            }
        } else {
            samples = try await fetchPoints(
                requests,
                altitudeFeet: altitudeFeet,
                model: "icon_eu"
            )
        }

        let vector = samples.reduce(
            into: (east: 0.0, north: 0.0)
        ) { result, sample in
            let value = windVector(
                directionDegrees: sample.direction,
                speedKnots: sample.speed
            )
            result.east += value.east / Double(samples.count)
            result.north += value.north / Double(samples.count)
        }
        let representative = windSample(
            east: vector.east,
            north: vector.north
        )

        return RouteWind(
            retrievedAt: Date(),
            validTime: plannedStart.addingTimeInterval(duration / 2),
            midpointLatitude: requests[1].latitude,
            midpointLongitude: requests[1].longitude,
            altitudeFeet: altitudeFeet,
            directionDegrees: representative.directionDegrees ?? 0,
            speedKnots: representative.speedKnots ?? 0,
            outboundCourseDegrees: outboundCourse,
            routeIsReturn: isReturn,
            routeHeadwindComponents: samples.map {
                WindMath.headwindComponent(
                    windFromDegrees: $0.direction,
                    speedKnots: $0.speed,
                    courseDegrees: $0.course
                )
            },
            modelBestAltitudeFeetAtPoints:
                samples.map(\.bestWindAltitudeFeet)
        )
    }

    private func fetchPoints(
        _ points: [RouteWindRequestPoint],
        altitudeFeet: Int,
        model: String
    ) async throws -> [RouteWindPoint] {
        try await withThrowingTaskGroup(
            of: (Int, RouteWindPoint).self
        ) { group in
            for (index, point) in points.enumerated() {
                group.addTask {
                    let sample = try await self.fetch(
                        point: point,
                        altitudeFeet: altitudeFeet,
                        model: model
                    )
                    return (index, sample)
                }
            }

            var results: [(Int, RouteWindPoint)] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func fetch(
        point: RouteWindRequestPoint,
        altitudeFeet: Int,
        model: String
    ) async throws -> RouteWindPoint {
        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc

        let dayBefore = calendar.date(
            byAdding: .day,
            value: -1,
            to: point.instant
        ) ?? point.instant

        let dayAfter = calendar.date(
            byAdding: .day,
            value: 1,
            to: point.instant
        ) ?? point.instant

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = utc
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var components = URLComponents(
            string: "https://api.open-meteo.com/v1/dwd-icon"
        )

        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(point.latitude)),
            URLQueryItem(name: "longitude", value: String(point.longitude)),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(name: "start_date", value: dateFormatter.string(from: dayBefore)),
            URLQueryItem(name: "end_date", value: dateFormatter.string(from: dayAfter)),
            URLQueryItem(name: "models", value: model),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(
                name: "hourly",
                value: [
                    "wind_speed_10m",
                    "wind_direction_10m",
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

        let api: RouteWindAPIResponse
        if let cached = apiCache[url],
           Date().timeIntervalSince(cached.retrievedAt)
            < apiCacheLifetime
        {
            api = cached.response
        } else {
            let (data, response) =
                try await URLSession.shared.data(from: url)

            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode)
            else {
                throw RouteWindError.serverError
            }

            api = try JSONDecoder().decode(
                RouteWindAPIResponse.self,
                from: data
            )
            apiCache[url] = (Date(), api)
        }

        let parsedTimes = parseTimes(api.hourly.time)

        guard
            let bracket = timeBracket(
                for: point.instant,
                parsedTimes: parsedTimes
            )
        else {
            throw RouteWindError.noForecast
        }

        let lower = interpolateAltitude(
            index: bracket.lowerIndex,
            targetHeightMeters: Double(altitudeFeet) * 0.3048,
            surfaceHeightMeters: api.elevation + 10,
            hourly: api.hourly
        )

        let upper = interpolateAltitude(
            index: bracket.upperIndex,
            targetHeightMeters: Double(altitudeFeet) * 0.3048,
            surfaceHeightMeters: api.elevation + 10,
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

        return RouteWindPoint(
            direction: direction,
            speed: speed,
            course: point.course,
            bestWindAltitudeFeet: bestModelLevelAltitudeFeet(
                lowerIndex: bracket.lowerIndex,
                upperIndex: bracket.upperIndex,
                fraction: bracket.fraction,
                surfaceHeightMeters: api.elevation + 10,
                course: point.course,
                hourly: api.hourly
            )
        )
    }

    private func bestModelLevelAltitudeFeet(
        lowerIndex: Int,
        upperIndex: Int,
        fraction: Double,
        surfaceHeightMeters: Double,
        course: Double,
        hourly: RouteWindHourly
    ) -> Double {
        let lower = modelLevels(
            index: lowerIndex,
            surfaceHeightMeters: surfaceHeightMeters,
            hourly: hourly
        )
        let upper = modelLevels(
            index: upperIndex,
            surfaceHeightMeters: surfaceHeightMeters,
            hourly: hourly
        )

        let candidates = zip(lower, upper).map {
            lowerLevel,
            upperLevel -> WindLevel in
            let lowerVector = windVector(
                directionDegrees: lowerLevel.direction,
                speedKnots: lowerLevel.speed
            )
            let upperVector = windVector(
                directionDegrees: upperLevel.direction,
                speedKnots: upperLevel.speed
            )
            let sample = windSample(
                east: lowerVector.east
                    + fraction
                    * (upperVector.east - lowerVector.east),
                north: lowerVector.north
                    + fraction
                    * (upperVector.north - lowerVector.north)
            )
            return WindLevel(
                height: lowerLevel.height
                    + fraction
                    * (upperLevel.height - lowerLevel.height),
                direction: sample.directionDegrees
                    ?? lowerLevel.direction,
                speed: sample.speedKnots ?? lowerLevel.speed
            )
        }

        let best = candidates.min {
            WindMath.headwindComponent(
                windFromDegrees: $0.direction,
                speedKnots: $0.speed,
                courseDegrees: course
            )
            < WindMath.headwindComponent(
                windFromDegrees: $1.direction,
                speedKnots: $1.speed,
                courseDegrees: course
            )
        }

        return (best?.height ?? surfaceHeightMeters) / 0.3048
    }

    private func modelLevels(
        index: Int,
        surfaceHeightMeters: Double,
        hourly: RouteWindHourly
    ) -> [WindLevel] {
        [
            (
                surfaceHeightMeters,
                value(hourly.windSpeed10m, index),
                value(hourly.windDirection10m, index)
            ),
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
        .compactMap { height, speed, direction in
            guard let height, let speed, let direction else {
                return nil
            }
            return WindLevel(
                height: height,
                direction: direction,
                speed: speed
            )
        }
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
        surfaceHeightMeters: Double,
        hourly: RouteWindHourly
    ) -> WindSample {
        let raw: [(Double?, Double?, Double?)] = [
            (
                surfaceHeightMeters,
                value(hourly.windSpeed10m, index),
                value(hourly.windDirection10m, index)
            ),
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

private struct RouteWindRequestPoint: Sendable {
    let latitude: Double
    let longitude: Double
    let course: Double
    let instant: Date
}

private struct RouteWindPoint: Sendable {
    let direction: Double
    let speed: Double
    let course: Double
    let bestWindAltitudeFeet: Double
}

private struct RouteWindAPIResponse: Decodable {
    let elevation: Double
    let hourly: RouteWindHourly
}

private struct RouteWindHourly: Decodable {
    let time: [String]
    let windSpeed10m: [Double?]
    let windDirection10m: [Double?]
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
        case windSpeed10m = "wind_speed_10m"
        case windDirection10m = "wind_direction_10m"
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
