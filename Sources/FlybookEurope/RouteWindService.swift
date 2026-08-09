import Foundation

actor RouteWindService {
    static let shared = RouteWindService()
    private var apiCache:
        [URL: (retrievedAt: Date, responses: [RouteWindAPIResponse])] = [:]
    private let apiCacheLifetime: TimeInterval = 30 * 60
    private var primaryUnavailableUntil: Date?

    func invalidateCaches() async {
        apiCache.removeAll()
        primaryUnavailableUntil = nil
        await GRIBRouteWindBackupService.shared.invalidateCaches()
    }

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
        do {
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
        } catch {
            samples = try await GRIBRouteWindBackupService.shared.samples(
                points: requests,
                altitudeFeet: altitudeFeet
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
        guard !points.isEmpty else {
            throw RouteWindError.noForecast
        }
        if let primaryUnavailableUntil,
           primaryUnavailableUntil > Date() {
            throw RouteWindError.serverError
        }
        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = utc
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var components = URLComponents(
            string: "https://api.open-meteo.com/v1/dwd-icon"
        )
        let firstInstant = points.map(\.instant).min() ?? Date()
        let lastInstant = points.map(\.instant).max() ?? firstInstant

        components?.queryItems = [
            URLQueryItem(
                name: "latitude",
                value: points.map { String($0.latitude) }
                    .joined(separator: ",")
            ),
            URLQueryItem(
                name: "longitude",
                value: points.map { String($0.longitude) }
                    .joined(separator: ",")
            ),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(
                name: "start_date",
                value: dateFormatter.string(from: firstInstant)
            ),
            URLQueryItem(
                name: "end_date",
                value: dateFormatter.string(from: lastInstant)
            ),
            URLQueryItem(name: "models", value: model),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(
                name: "hourly",
                value: [
                    "wind_speed_10m",
                    "wind_direction_10m",
                    "wind_speed_1000hPa",
                    "wind_direction_1000hPa",
                    "geopotential_height_1000hPa",
                    "wind_speed_975hPa",
                    "wind_direction_975hPa",
                    "geopotential_height_975hPa",
                    "wind_speed_950hPa",
                    "wind_direction_950hPa",
                    "geopotential_height_950hPa",
                    "wind_speed_925hPa",
                    "wind_direction_925hPa",
                    "geopotential_height_925hPa",
                    "wind_speed_900hPa",
                    "wind_direction_900hPa",
                    "geopotential_height_900hPa",
                    "wind_speed_850hPa",
                    "wind_direction_850hPa",
                    "geopotential_height_850hPa",
                    "wind_speed_800hPa",
                    "wind_direction_800hPa",
                    "geopotential_height_800hPa",
                    "wind_speed_700hPa",
                    "wind_direction_700hPa",
                    "geopotential_height_700hPa"
                ].joined(separator: ",")
            )
        ]

        guard let url = components?.url else {
            throw RouteWindError.invalidURL
        }

        let apiResponses: [RouteWindAPIResponse]
        if let cached = apiCache[url],
           Date().timeIntervalSince(cached.retrievedAt)
            < apiCacheLifetime
        {
            apiResponses = cached.responses
        } else {
            let (data, response) =
                try await FlightNetwork.data(
                    from: url,
                    priority: .high
                )

            guard let http = response as? HTTPURLResponse else {
                throw RouteWindError.serverError
            }
            if http.statusCode == 429 {
                primaryUnavailableUntil = Date().addingTimeInterval(60 * 60)
                throw RouteWindError.serverError
            }
            guard (200..<300).contains(http.statusCode) else {
                throw RouteWindError.serverError
            }

            let decoder = JSONDecoder()
            if points.count == 1 {
                apiResponses = [try decoder.decode(
                    RouteWindAPIResponse.self,
                    from: data
                )]
            } else {
                apiResponses = try decoder.decode(
                    [RouteWindAPIResponse].self,
                    from: data
                )
            }
            apiCache[url] = (Date(), apiResponses)
        }

        guard apiResponses.count == points.count else {
            throw RouteWindError.noForecast
        }

        return try zip(points, apiResponses).map { point, api in
            try routeWindPoint(
                api: api,
                point: point,
                altitudeFeet: altitudeFeet
            )
        }
    }

    private func routeWindPoint(
        api: RouteWindAPIResponse,
        point: RouteWindRequestPoint,
        altitudeFeet: Int
    ) throws -> RouteWindPoint {
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
                value(hourly.geopotentialHeight1000, index),
                value(hourly.windSpeed1000, index),
                value(hourly.windDirection1000, index)
            ),
            (
                value(hourly.geopotentialHeight975, index),
                value(hourly.windSpeed975, index),
                value(hourly.windDirection975, index)
            ),
            (
                value(hourly.geopotentialHeight950, index),
                value(hourly.windSpeed950, index),
                value(hourly.windDirection950, index)
            ),
            (
                value(hourly.geopotentialHeight925, index),
                value(hourly.windSpeed925, index),
                value(hourly.windDirection925, index)
            ),
            (
                value(hourly.geopotentialHeight900, index),
                value(hourly.windSpeed900, index),
                value(hourly.windDirection900, index)
            ),
            (
                value(hourly.geopotentialHeight850, index),
                value(hourly.windSpeed850, index),
                value(hourly.windDirection850, index)
            ),
            (
                value(hourly.geopotentialHeight800, index),
                value(hourly.windSpeed800, index),
                value(hourly.windDirection800, index)
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
                value(hourly.geopotentialHeight1000, index),
                value(hourly.windSpeed1000, index),
                value(hourly.windDirection1000, index)
            ),
            (
                value(hourly.geopotentialHeight975, index),
                value(hourly.windSpeed975, index),
                value(hourly.windDirection975, index)
            ),
            (
                value(hourly.geopotentialHeight950, index),
                value(hourly.windSpeed950, index),
                value(hourly.windDirection950, index)
            ),
            (
                value(hourly.geopotentialHeight925, index),
                value(hourly.windSpeed925, index),
                value(hourly.windDirection925, index)
            ),
            (
                value(hourly.geopotentialHeight900, index),
                value(hourly.windSpeed900, index),
                value(hourly.windDirection900, index)
            ),
            (
                value(hourly.geopotentialHeight850, index),
                value(hourly.windSpeed850, index),
                value(hourly.windDirection850, index)
            ),
            (
                value(hourly.geopotentialHeight800, index),
                value(hourly.windSpeed800, index),
                value(hourly.windDirection800, index)
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

private actor GRIBRouteWindBackupService {
    static let shared = GRIBRouteWindBackupService()

    private struct GridValue: Sendable {
        let latitude: Double
        let longitude: Double
        let value: Double
        let parameter: String
        let level: Int
    }

    private struct LevelWind {
        let heightMeters: Double
        let eastMetersPerSecond: Double
        let northMetersPerSecond: Double
    }

    private enum GFSGrid: String, CaseIterable {
        case quarterDegree = "gfs_0p25"
        case oneDegree = "gfs_1p00"

        var filterScript: String {
            switch self {
            case .quarterDegree: return "filter_gfs_0p25.pl"
            case .oneDegree: return "filter_gfs_1p00.pl"
            }
        }

        var fileGrid: String {
            switch self {
            case .quarterDegree: return "0p25"
            case .oneDegree: return "1p00"
            }
        }
    }

    private var cache: [String: (Date, [GridValue])] = [:]
    private let cacheLifetime: TimeInterval = 30 * 60

    func invalidateCaches() {
        cache.removeAll()
        dwdCache.removeAll()
    }

    func samples(
        points: [RouteWindRequestPoint],
        altitudeFeet: Int
    ) async throws -> [RouteWindPoint] {
        var lastError: Error = RouteWindError.noForecast
        do {
            let result = try await dwdSamples(
                points: points,
                altitudeFeet: altitudeFeet
            )
            return result
        } catch {
            lastError = error
        }
        for grid in GFSGrid.allCases {
            do {
                let values = try await values(points: points, grid: grid)
                let result = try points.map {
                    try sample(point: $0, altitudeFeet: altitudeFeet, values: values)
                }
                return result
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private var dwdCache: [String: (Date, [[LevelWind]])] = [:]

    private func dwdSamples(
        points: [RouteWindRequestPoint],
        altitudeFeet: Int
    ) async throws -> [RouteWindPoint] {
        guard let first = points.first else { throw RouteWindError.noForecast }
        let run = modelRun(for: first.instant)
        let rawHour = forecastHour(run: run, valid: first.instant)
        guard rawHour <= 120 else { throw RouteWindError.noForecast }
        let forecastHour = rawHour <= 78
            ? rawHour
            : Int((Double(rawHour) / 3).rounded()) * 3
        let coordinates = points.map {
            String(format: "%.3f,%.3f", $0.latitude, $0.longitude)
        }.joined(separator: ";")
        let key = "dwd-\(run.stamp)-\(run.cycle)-\(forecastHour)-\(coordinates)"
        let profiles: [[LevelWind]]
        if let cached = dwdCache[key],
           Date().timeIntervalSince(cached.0) < cacheLifetime {
            profiles = cached.1
        } else {
            profiles = try await downloadDWDProfiles(
                points: points,
                run: run,
                forecastHour: forecastHour
            )
            dwdCache[key] = (Date(), profiles)
        }
        guard profiles.count == points.count else { throw RouteWindError.noForecast }
        return try zip(points, profiles).map { point, levels in
            try routePoint(point: point, altitudeFeet: altitudeFeet, levels: levels)
        }
    }

    private func downloadDWDProfiles(
        points: [RouteWindRequestPoint],
        run: (date: Date, cycle: Int, stamp: String),
        forecastHour: Int
    ) async throws -> [[LevelWind]] {
        let levels = [55, 60, 65, 70]
        var heights = Array(repeating: [Int: Double](), count: points.count)
        var east = Array(repeating: [Int: Double](), count: points.count)
        var north = Array(repeating: [Int: Double](), count: points.count)

        for level in levels {
            for parameter in ["HHL", "U", "V"] {
                let values = try await dwdValues(
                    points: points,
                    run: run,
                    forecastHour: forecastHour,
                    level: level,
                    parameter: parameter
                )
                for index in points.indices {
                    switch parameter {
                    case "HHL": heights[index][level] = values[index]
                    case "U": east[index][level] = values[index]
                    default: north[index][level] = values[index]
                    }
                }
            }
        }

        return points.indices.map { index in
            levels.compactMap { level in
                guard let height = heights[index][level],
                      let u = east[index][level],
                      let v = north[index][level]
                else { return nil }
                return LevelWind(
                    heightMeters: height,
                    eastMetersPerSecond: u,
                    northMetersPerSecond: v
                )
            }.sorted { $0.heightMeters < $1.heightMeters }
        }
    }

    private func dwdValues(
        points: [RouteWindRequestPoint],
        run: (date: Date, cycle: Int, stamp: String),
        forecastHour: Int,
        level: Int,
        parameter: String
    ) async throws -> [Double] {
        let cycle = String(format: "%02d", run.cycle)
        let forecast = String(format: "%03d", forecastHour)
        let directory = parameter.lowercased()
        let timePart = parameter == "HHL" ? "time-invariant" : "model-level"
        let forecastPart = parameter == "HHL" ? "" : "_\(forecast)"
        let name = "icon-eu_europe_regular-lat-lon_\(timePart)_\(run.stamp)\(cycle)\(forecastPart)_\(level)_\(parameter).grib2.bz2"
        guard let url = URL(
            string: "https://opendata.dwd.de/weather/nwp/icon-eu/grib/\(cycle)/\(directory)/\(name)"
        ) else { throw RouteWindError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Flybook-Europe/1.0", forHTTPHeaderField: "User-Agent")
        let (compressed, response) = try await FlightNetwork.data(
            for: request,
            priority: .high
        )
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              compressed.starts(with: Data("BZh".utf8))
        else { throw RouteWindError.serverError }
        let manager = FileManager.default
        let temporaryDirectory = manager.temporaryDirectory
            .appendingPathComponent("flybook-wind", isDirectory: true)
        try manager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let archive = temporaryDirectory.appendingPathComponent(UUID().uuidString + ".grib2.bz2")
        try compressed.write(to: archive, options: .atomic)
        defer { try? manager.removeItem(at: archive) }
        let grib = try runTool(
            executable: "/usr/bin/bunzip2",
            arguments: ["-c", archive.path]
        )
        return try nearestValues(in: grib, points: points)
    }

    private func nearestValues(
        in data: Data,
        points: [RouteWindRequestPoint]
    ) throws -> [Double] {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
            .appendingPathComponent("flybook-wind", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(UUID().uuidString + ".grib2")
        try data.write(to: file, options: .atomic)
        defer { try? manager.removeItem(at: file) }
        let executable = ["/opt/homebrew/bin/grib_get", "/usr/local/bin/grib_get"]
            .first { manager.isExecutableFile(atPath: $0) }
        guard let executable else { throw RouteWindError.noForecast }
        return try points.map { point in
            let output = try runTool(
                executable: executable,
                arguments: [
                    "-l",
                    String(format: "%.5f,%.5f,1", point.latitude, point.longitude),
                    file.path
                ]
            )
            guard let text = String(data: output, encoding: .utf8),
                  let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
            else { throw RouteWindError.noForecast }
            return value
        }
    }

    private func runTool(
        executable: String,
        arguments: [String],
        input: Data? = nil
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = Pipe()
        if let input {
            let pipe = Pipe()
            process.standardInput = pipe
            try process.run()
            pipe.fileHandleForWriting.write(input)
            try pipe.fileHandleForWriting.close()
        } else {
            try process.run()
        }
        let result = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw RouteWindError.noForecast }
        return result
    }

    private func values(
        points: [RouteWindRequestPoint],
        grid: GFSGrid
    ) async throws -> [GridValue] {
        guard let first = points.first else { throw RouteWindError.noForecast }
        let run = modelRun(for: first.instant)
        let hour = forecastHour(run: run, valid: first.instant)
        let bounds = boundsFor(points)
        let key = "\(grid.rawValue)-\(run.stamp)-\(hour)-\(bounds)"
        if let cached = cache[key],
           Date().timeIntervalSince(cached.0) < cacheLifetime {
            return cached.1
        }

        let data = try await download(
            grid: grid,
            run: run,
            forecastHour: hour,
            bounds: bounds
        )
        let parsed = try decodeGRIB(data)
        guard !parsed.isEmpty else { throw RouteWindError.noForecast }
        cache[key] = (Date(), parsed)
        return parsed
    }

    private func modelRun(for validTime: Date) -> (date: Date, cycle: Int, stamp: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let available = Date().addingTimeInterval(-5 * 60 * 60)
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: available)
        let cycle = ((components.hour ?? 0) / 6) * 6
        var runComponents = components
        runComponents.hour = cycle
        runComponents.minute = 0
        runComponents.second = 0
        let date = calendar.date(from: runComponents) ?? available
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return (date, cycle, formatter.string(from: date))
    }

    private func forecastHour(
        run: (date: Date, cycle: Int, stamp: String),
        valid: Date
    ) -> Int {
        min(384, max(0, Int((valid.timeIntervalSince(run.date) / 3600).rounded())))
    }

    private func boundsFor(_ points: [RouteWindRequestPoint]) -> String {
        let lats = points.map(\.latitude)
        let lons = points.map(\.longitude)
        let bottom = (lats.min() ?? 0) - 0.5
        let top = (lats.max() ?? 0) + 0.5
        let left = (lons.min() ?? 0) - 0.5
        let right = (lons.max() ?? 0) + 0.5
        return String(format: "%.2f,%.2f,%.2f,%.2f", left, right, bottom, top)
    }

    private func download(
        grid: GFSGrid,
        run: (date: Date, cycle: Int, stamp: String),
        forecastHour: Int,
        bounds: String
    ) async throws -> Data {
        let parts = bounds.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { throw RouteWindError.invalidURL }
        var components = URLComponents(
            string: "https://nomads.ncep.noaa.gov/cgi-bin/\(grid.filterScript)"
        )
        let cycle = String(format: "%02d", run.cycle)
        let forecast = String(format: "%03d", forecastHour)
        components?.queryItems = [
            URLQueryItem(name: "file", value: "gfs.t\(cycle)z.pgrb2.\(grid.fileGrid).f\(forecast)"),
            URLQueryItem(name: "lev_925_mb", value: "on"),
            URLQueryItem(name: "lev_850_mb", value: "on"),
            URLQueryItem(name: "lev_700_mb", value: "on"),
            URLQueryItem(name: "var_UGRD", value: "on"),
            URLQueryItem(name: "var_VGRD", value: "on"),
            URLQueryItem(name: "var_HGT", value: "on"),
            URLQueryItem(name: "subregion", value: ""),
            URLQueryItem(name: "leftlon", value: String(parts[0])),
            URLQueryItem(name: "rightlon", value: String(parts[1])),
            URLQueryItem(name: "bottomlat", value: String(parts[2])),
            URLQueryItem(name: "toplat", value: String(parts[3])),
            URLQueryItem(name: "dir", value: "/gfs.\(run.stamp)/\(cycle)/atmos")
        ]
        guard let url = components?.url else { throw RouteWindError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Flybook-Europe/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await FlightNetwork.data(
            for: request,
            priority: .high
        )
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.starts(with: Data("GRIB".utf8))
        else { throw RouteWindError.serverError }
        return data
    }

    private func decodeGRIB(_ data: Data) throws -> [GridValue] {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
            .appendingPathComponent("flybook-wind", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(UUID().uuidString + ".grib2")
        try data.write(to: file, options: .atomic)
        defer { try? manager.removeItem(at: file) }

        let candidates = [
            "/opt/homebrew/bin/grib_get_data",
            "/usr/local/bin/grib_get_data"
        ]
        guard let executable = candidates.first(where: manager.isExecutableFile(atPath:))
        else { throw RouteWindError.noForecast }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-p", "shortName,level,typeOfLevel", file.path]
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: result, encoding: .utf8)
        else { throw RouteWindError.noForecast }

        return text.split(whereSeparator: \ .isNewline).dropFirst().compactMap { line in
            let fields = line.split(whereSeparator: \ .isWhitespace)
            guard fields.count >= 6,
                  let latitude = Double(fields[0]),
                  let longitude = Double(fields[1]),
                  let value = Double(fields[2]),
                  let level = Int(fields[4])
            else { return nil }
            return GridValue(
                latitude: latitude,
                longitude: longitude,
                value: value,
                parameter: String(fields[3]),
                level: level
            )
        }
    }

    private func sample(
        point: RouteWindRequestPoint,
        altitudeFeet: Int,
        values: [GridValue]
    ) throws -> RouteWindPoint {
        let levels = [925, 850, 700].compactMap { level -> LevelWind? in
            guard let height = nearest("gh", level, point, values),
                  let east = nearest("u", level, point, values),
                  let north = nearest("v", level, point, values)
            else { return nil }
            return LevelWind(
                heightMeters: height,
                eastMetersPerSecond: east,
                northMetersPerSecond: north
            )
        }.sorted { $0.heightMeters < $1.heightMeters }
        guard !levels.isEmpty else { throw RouteWindError.noForecast }

        return try routePoint(
            point: point,
            altitudeFeet: altitudeFeet,
            levels: levels
        )
    }

    private func routePoint(
        point: RouteWindRequestPoint,
        altitudeFeet: Int,
        levels: [LevelWind]
    ) throws -> RouteWindPoint {
        guard !levels.isEmpty else { throw RouteWindError.noForecast }
        let target = Double(altitudeFeet) * 0.3048
        let pair: (LevelWind, LevelWind)
        if target <= levels[0].heightMeters {
            pair = (levels[0], levels[min(1, levels.count - 1)])
        } else if target >= levels[levels.count - 1].heightMeters {
            pair = (levels[max(0, levels.count - 2)], levels[levels.count - 1])
        } else {
            let upperIndex = levels.firstIndex { $0.heightMeters >= target } ?? 0
            pair = (levels[max(0, upperIndex - 1)], levels[upperIndex])
        }
        let span = max(1, pair.1.heightMeters - pair.0.heightMeters)
        let fraction = min(1, max(0, (target - pair.0.heightMeters) / span))
        let east = pair.0.eastMetersPerSecond
            + (pair.1.eastMetersPerSecond - pair.0.eastMetersPerSecond) * fraction
        let north = pair.0.northMetersPerSecond
            + (pair.1.northMetersPerSecond - pair.0.northMetersPerSecond) * fraction
        let speed = hypot(east, north) * 1.943844
        var direction = atan2(-east, -north) * 180 / .pi
        if direction < 0 { direction += 360 }
        let best = levels.min {
            WindMath.headwindComponent(
                windFromDegrees: vectorDirection(east: $0.eastMetersPerSecond, north: $0.northMetersPerSecond),
                speedKnots: hypot($0.eastMetersPerSecond, $0.northMetersPerSecond) * 1.943844,
                courseDegrees: point.course
            ) < WindMath.headwindComponent(
                windFromDegrees: vectorDirection(east: $1.eastMetersPerSecond, north: $1.northMetersPerSecond),
                speedKnots: hypot($1.eastMetersPerSecond, $1.northMetersPerSecond) * 1.943844,
                courseDegrees: point.course
            )
        }
        return RouteWindPoint(
            direction: direction,
            speed: speed,
            course: point.course,
            bestWindAltitudeFeet: (best?.heightMeters ?? target) / 0.3048
        )
    }

    private func nearest(
        _ parameter: String,
        _ level: Int,
        _ point: RouteWindRequestPoint,
        _ values: [GridValue]
    ) -> Double? {
        values.lazy.filter { $0.parameter == parameter && $0.level == level }.min {
            hypot($0.latitude - point.latitude, $0.longitude - point.longitude)
                < hypot($1.latitude - point.latitude, $1.longitude - point.longitude)
        }?.value
    }

    private func vectorDirection(east: Double, north: Double) -> Double {
        var result = atan2(-east, -north) * 180 / .pi
        if result < 0 { result += 360 }
        return result
    }
}

private struct RouteWindAPIResponse: Decodable {
    let elevation: Double
    let hourly: RouteWindHourly
}

private struct RouteWindHourly: Decodable {
    let time: [String]
    let windSpeed10m: [Double?]
    let windDirection10m: [Double?]
    let windSpeed1000: [Double?]
    let windDirection1000: [Double?]
    let geopotentialHeight1000: [Double?]
    let windSpeed975: [Double?]
    let windDirection975: [Double?]
    let geopotentialHeight975: [Double?]
    let windSpeed950: [Double?]
    let windDirection950: [Double?]
    let geopotentialHeight950: [Double?]
    let windSpeed925: [Double?]
    let windDirection925: [Double?]
    let geopotentialHeight925: [Double?]
    let windSpeed900: [Double?]
    let windDirection900: [Double?]
    let geopotentialHeight900: [Double?]
    let windSpeed850: [Double?]
    let windDirection850: [Double?]
    let geopotentialHeight850: [Double?]
    let windSpeed800: [Double?]
    let windDirection800: [Double?]
    let geopotentialHeight800: [Double?]
    let windSpeed700: [Double?]
    let windDirection700: [Double?]
    let geopotentialHeight700: [Double?]

    enum CodingKeys: String, CodingKey {
        case time
        case windSpeed10m = "wind_speed_10m"
        case windDirection10m = "wind_direction_10m"
        case windSpeed1000 = "wind_speed_1000hPa"
        case windDirection1000 = "wind_direction_1000hPa"
        case geopotentialHeight1000 = "geopotential_height_1000hPa"
        case windSpeed975 = "wind_speed_975hPa"
        case windDirection975 = "wind_direction_975hPa"
        case geopotentialHeight975 = "geopotential_height_975hPa"
        case windSpeed950 = "wind_speed_950hPa"
        case windDirection950 = "wind_direction_950hPa"
        case geopotentialHeight950 = "geopotential_height_950hPa"
        case windSpeed925 = "wind_speed_925hPa"
        case windDirection925 = "wind_direction_925hPa"
        case geopotentialHeight925 = "geopotential_height_925hPa"
        case windSpeed900 = "wind_speed_900hPa"
        case windDirection900 = "wind_direction_900hPa"
        case geopotentialHeight900 = "geopotential_height_900hPa"
        case windSpeed850 = "wind_speed_850hPa"
        case windDirection850 = "wind_direction_850hPa"
        case geopotentialHeight850 = "geopotential_height_850hPa"
        case windSpeed800 = "wind_speed_800hPa"
        case windDirection800 = "wind_direction_800hPa"
        case geopotentialHeight800 = "geopotential_height_800hPa"
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
