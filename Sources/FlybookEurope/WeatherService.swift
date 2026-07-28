import Foundation

actor WeatherService {
    static let shared = WeatherService()

    private let cacheLifetime: TimeInterval = 6 * 60 * 60

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    func weather(
        for destination: Destination,
        targetInstants: [Date],
        forceRefresh: Bool = false
    ) async throws -> DestinationWeather {
        guard
            let latitude = destination.latitude,
            let longitude = destination.longitude
        else {
            throw WeatherError.coordinatesMissing
        }

        let now = Date()
        let d2Limit = now.addingTimeInterval(
            48 * 60 * 60
        )

        let nearInstants = targetInstants.filter {
            $0 <= d2Limit
        }

        async let euRequest = fetch(
            destination: destination,
            latitude: latitude,
            longitude: longitude,
            model: "icon_eu",
            modelLabel: "ICON-EU",
            targetInstants: targetInstants
        )

        async let seamlessRequest = fetch(
            destination: destination,
            latitude: latitude,
            longitude: longitude,
            model: "icon_seamless",
            modelLabel: "ICON Seamless",
            targetInstants: targetInstants
        )

        let d2Weather: DestinationWeather?

        if nearInstants.isEmpty {
            d2Weather = nil
        } else {
            d2Weather = try? await fetch(
                destination: destination,
                latitude: latitude,
                longitude: longitude,
                model: "icon_d2",
                modelLabel: "ICON-D2",
                targetInstants: nearInstants
            )
        }

        let euWeather = try await euRequest
        let seamlessWeather = try await seamlessRequest

        var merged = mergeWeather(
            d2: d2Weather,
            eu: euWeather,
            targetInstants: targetInstants,
            d2Limit: d2Limit
        )

        merged = DestinationWeather(
            icao: merged.icao,
            retrievedAt: Date(),
            timezone: merged.timezone,
            days: merged.days,
            dailyForecast:
                normalizedFiveDayForecast(
                    seamlessWeather.dailyForecast
                )
        )

        try saveCache(merged)
        return merged
    }

    private func normalizedFiveDayForecast(
        _ source: [DailyForecast]
    ) -> [DailyForecast] {
        Array(source.prefix(5))
    }

    private func mergeWeather(
        d2: DestinationWeather?,
        eu: DestinationWeather,
        targetInstants: [Date],
        d2Limit: Date
    ) -> DestinationWeather {
        let d2DaysByLabel = Dictionary(
            uniqueKeysWithValues:
                (d2?.days ?? []).map {
                    ($0.displayDay, $0)
                }
        )

        let euDaysByLabel = Dictionary(
            uniqueKeysWithValues:
                eu.days.map {
                    ($0.displayDay, $0)
                }
        )

        let labels = [
            "LANDUNG HINFLUG",
            "START RÜCKFLUG"
        ]

        let mergedDays = labels.enumerated()
            .compactMap {
                index,
                label -> ForecastDay? in

                let instant = targetInstants.indices
                    .contains(index)
                    ? targetInstants[index]
                    : .distantFuture

                if
                    instant <= d2Limit,
                    let d2Day = d2DaysByLabel[label]
                {
                    return d2Day
                }

                return euDaysByLabel[label]
            }

        let d2DailyByDate = Dictionary(
            uniqueKeysWithValues:
                (d2?.dailyForecast ?? []).map {
                    ($0.localDate, $0)
                }
        )

        let euCalendar =
            Calendar(identifier: .gregorian)

        let formatter = DateFormatter()
        formatter.locale =
            Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let mergedDaily = Array(
            eu.dailyForecast.prefix(5)
        ).map { euDay in
            guard
                let date = formatter.date(
                    from: euDay.localDate
                )
            else {
                return euDay
            }

            let dayEnd =
                euCalendar.date(
                    bySettingHour: 23,
                    minute: 59,
                    second: 59,
                    of: date
                ) ?? date

            if
                dayEnd <= d2Limit,
                let d2Day =
                    d2DailyByDate[euDay.localDate]
            {
                return d2Day
            }

            return euDay
        }

        return DestinationWeather(
            icao: eu.icao,
            retrievedAt: Date(),
            timezone: eu.timezone,
            days: mergedDays,
            dailyForecast: mergedDaily
        )
    }

    private func fetch(
        destination: Destination,
        latitude: Double,
        longitude: Double,
        model: String,
        modelLabel: String,
        targetInstants: [Date]
    ) async throws -> DestinationWeather {
        var components = URLComponents(
            string: "https://api.open-meteo.com/v1/dwd-icon"
        )

        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "8"),
            URLQueryItem(name: "models", value: model),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(
                name: "hourly",
                value: [
                    "temperature_2m",
                    "precipitation_probability",
                    "weather_code",
                    "visibility",
                    "cloud_cover_low",
                    "pressure_msl",
                    "wind_gusts_10m",
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
            ),
            URLQueryItem(
                name: "daily",
                value: [
                    "sunrise",
                    "sunset",
                    "weather_code",
                    "temperature_2m_max",
                    "temperature_2m_min"
                ].joined(separator: ",")
            )
        ]

        guard let url = components?.url else {
            throw WeatherError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw WeatherError.serverError
        }

        let apiResponse = try JSONDecoder().decode(
            APIResponse.self,
            from: data
        )

        return try transform(
            api: apiResponse,
            destination: destination,
            modelLabel: modelLabel,
            targetInstants: targetInstants
        )
    }

    private func transform(
        api: APIResponse,
        destination: Destination,
        modelLabel: String,
        targetInstants: [Date]
    ) throws -> DestinationWeather {
        let timezone = TimeZone(identifier: api.timezone) ?? .current

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        let dateTimeParser = DateFormatter()
        dateTimeParser.calendar = calendar
        dateTimeParser.locale = Locale(identifier: "en_US_POSIX")
        dateTimeParser.timeZone = timezone
        dateTimeParser.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timezone
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = timezone
        timeFormatter.dateFormat = "HH:mm"

        let parsedTimes: [Date?] = api.hourly.time.map {
            dateTimeParser.date(from: $0)
        }

        let selectedInstants = Array(targetInstants.prefix(2))

        let forecastDays: [ForecastDay] = try selectedInstants.enumerated().map {
            offset,
            targetInstant in

            guard let index = nearestIndex(
                target: targetInstant,
                values: parsedTimes
            ) else {
                throw WeatherError.forecastTimeMissing
            }

            let targetDate = targetInstant

            let visibility = optionalValue(
                api.hourly.visibility,
                at: index
            )

            let lowCloudCover = optionalValue(
                api.hourly.cloudCoverLow,
                at: index
            )

            let ceiling = estimateCeiling(
                lowCloudPercent: lowCloudCover
            )

            let dateKey = dateFormatter.string(from: targetDate)
            let dailyIndex = api.daily.time.firstIndex(of: dateKey)

            let sunrise = dailyIndex
                .flatMap { optionalValue(api.daily.sunrise, at: $0) }
                .flatMap { dateTimeParser.date(from: $0) }
                .map { timeFormatter.string(from: $0) }

            let sunset = dailyIndex
                .flatMap { optionalValue(api.daily.sunset, at: $0) }
                .flatMap { dateTimeParser.date(from: $0) }
                .map { timeFormatter.string(from: $0) }

            return ForecastDay(
                localDate: dateKey,
                displayDay: offset == 0
                    ? "LANDUNG HINFLUG"
                    : "START RÜCKFLUG",
                localTime: timeFormatter.string(from: targetInstant) + " LCL",
                model: modelLabel,
                temperatureCelsius: optionalValue(
                    api.hourly.temperature2m,
                    at: index
                ),
                weatherCode: optionalValue(
                    api.hourly.weatherCode,
                    at: index
                ),
                visibilityMeters: visibility,
                ceilingFeetAGL: ceiling,
                precipitationProbability: optionalValue(
                    api.hourly.precipitationProbability,
                    at: index
                ),
                pressureMSLHPA: optionalValue(
                    api.hourly.pressureMSL,
                    at: index
                ),
                windGustKnots: optionalValue(
                    api.hourly.windGusts10m,
                    at: index
                ),
                surfaceWind: WindSample(
                    directionDegrees: optionalValue(
                        api.hourly.windDirection10m,
                        at: index
                    ),
                    speedKnots: optionalValue(
                        api.hourly.windSpeed10m,
                        at: index
                    )
                ),
                upperWind: interpolateUpperWind(
                    index: index,
                    targetHeightMeters: api.elevation + 1524.0,
                    hourly: api.hourly
                ),
                sunrise: sunrise,
                sunset: sunset,
                category: flightCategory(
                    visibilityMeters: visibility,
                    ceilingFeet: ceiling
                )
            )
        }

        let dailyForecast = Array(
            api.daily.time.indices.prefix(5)
        ).map { index in
            let localDate = api.daily.time[index]

            func weatherCode(at hour: Int) -> Int? {
                let timestamp = String(
                    format: "%@T%02d:00",
                    localDate,
                    hour
                )
                guard
                    let hourlyIndex =
                        api.hourly.time.firstIndex(
                            of: timestamp
                        )
                else {
                    return nil
                }

                return optionalValue(
                    api.hourly.weatherCode,
                    at: hourlyIndex
                )
            }

            return DailyForecast(
                localDate: localDate,
                weatherCode: optionalValue(
                    api.daily.weatherCode,
                    at: index
                ),
                morningWeatherCode:
                    weatherCode(at: 8),
                middayWeatherCode:
                    weatherCode(at: 14),
                eveningWeatherCode:
                    weatherCode(at: 20),
                minimumTemperatureCelsius:
                    optionalValue(
                        api.daily.temperature2mMin,
                        at: index
                    ),
                maximumTemperatureCelsius:
                    optionalValue(
                        api.daily.temperature2mMax,
                        at: index
                    ),
                model: modelLabel
            )
        }

        return DestinationWeather(
            icao: destination.icao,
            retrievedAt: Date(),
            timezone: api.timezone,
            days: forecastDays,
            dailyForecast: dailyForecast
        )
    }

    private func nearestIndex(
        target: Date,
        values: [Date?]
    ) -> Int? {
        values.enumerated()
            .compactMap { index, value -> (index: Int, distance: TimeInterval)? in
                guard let value else {
                    return nil
                }

                return (
                    index: index,
                    distance: abs(value.timeIntervalSince(target))
                )
            }
            .min { first, second in
                first.distance < second.distance
            }?
            .index
    }

    private func interpolateUpperWind(
        index: Int,
        targetHeightMeters: Double,
        hourly: Hourly
    ) -> WindSample {
        let rawLevels: [(Double?, Double?, Double?)] = [
            (
                optionalValue(hourly.geopotentialHeight925, at: index),
                optionalValue(hourly.windSpeed925, at: index),
                optionalValue(hourly.windDirection925, at: index)
            ),
            (
                optionalValue(hourly.geopotentialHeight850, at: index),
                optionalValue(hourly.windSpeed850, at: index),
                optionalValue(hourly.windDirection850, at: index)
            ),
            (
                optionalValue(hourly.geopotentialHeight700, at: index),
                optionalValue(hourly.windSpeed700, at: index),
                optionalValue(hourly.windDirection700, at: index)
            )
        ]

        let levels: [WindLevel] = rawLevels.compactMap { level in
            guard
                let height = level.0,
                let speed = level.1,
                let direction = level.2
            else {
                return nil
            }

            return WindLevel(
                height: height,
                speed: speed,
                direction: direction
            )
        }
        .sorted { first, second in
            first.height < second.height
        }

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

            return WindSample(
                directionDegrees: interpolateDirection(
                    from: lower.direction,
                    to: upper.direction,
                    fraction: fraction
                ),
                speedKnots:
                    lower.speed
                    + fraction * (upper.speed - lower.speed)
            )
        }

        let nearest = levels.min { first, second in
            abs(first.height - targetHeightMeters)
                < abs(second.height - targetHeightMeters)
        }

        return WindSample(
            directionDegrees: nearest?.direction,
            speedKnots: nearest?.speed
        )
    }

    private func interpolateDirection(
        from start: Double,
        to end: Double,
        fraction: Double
    ) -> Double {
        let delta =
            ((end - start + 540.0)
                .truncatingRemainder(dividingBy: 360.0))
            - 180.0

        return
            (start + fraction * delta + 360.0)
            .truncatingRemainder(dividingBy: 360.0)
    }

    private func estimateCeiling(
        lowCloudPercent: Double?
    ) -> Double? {
        guard let lowCloudPercent else {
            return nil
        }

        if lowCloudPercent >= 90.0 {
            return 800.0
        }

        if lowCloudPercent >= 75.0 {
            return 1800.0
        }

        if lowCloudPercent >= 50.0 {
            return 3000.0
        }

        return nil
    }

    private func flightCategory(
        visibilityMeters: Double?,
        ceilingFeet: Double?
    ) -> FlightCategory {
        let visibilityStatuteMiles = visibilityMeters.map {
            $0 / 1609.344
        }

        if let ceilingFeet, ceilingFeet < 500.0 {
            return .lifr
        }

        if let visibilityStatuteMiles,
           visibilityStatuteMiles < 1.0 {
            return .lifr
        }

        if let ceilingFeet, ceilingFeet < 1000.0 {
            return .ifr
        }

        if let visibilityStatuteMiles,
           visibilityStatuteMiles < 3.0 {
            return .ifr
        }

        if let ceilingFeet, ceilingFeet <= 3000.0 {
            return .mvfr
        }

        if let visibilityStatuteMiles,
           visibilityStatuteMiles <= 5.0 {
            return .mvfr
        }

        if ceilingFeet != nil || visibilityStatuteMiles != nil {
            return .vfr
        }

        return .unavailable
    }

    private func optionalValue<T>(
        _ values: [T?],
        at index: Int
    ) -> T? {
        guard values.indices.contains(index) else {
            return nil
        }

        return values[index]
    }

    private func cacheURL(
        icao: String
    ) throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let directory = applicationSupport
            .appendingPathComponent(
                "Flybook Europe",
                isDirectory: true
            )
            .appendingPathComponent(
                "WeatherCache",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return directory.appendingPathComponent(
            "\(icao).json"
        )
    }

    private func loadCache(
        icao: String
    ) throws -> DestinationWeather {
        let data = try Data(
            contentsOf: cacheURL(icao: icao)
        )

        return try decoder.decode(
            DestinationWeather.self,
            from: data
        )
    }

    private func saveCache(
        _ weather: DestinationWeather
    ) throws {
        let data = try encoder.encode(weather)

        try data.write(
            to: cacheURL(icao: weather.icao),
            options: .atomic
        )
    }
}

private struct WindLevel {
    let height: Double
    let speed: Double
    let direction: Double
}

enum WeatherError: LocalizedError {
    case coordinatesMissing
    case invalidURL
    case serverError
    case forecastTimeMissing

    var errorDescription: String? {
        switch self {
        case .coordinatesMissing:
            return "Für diesen Flugplatz fehlen noch Koordinaten."

        case .invalidURL:
            return "Die Wetterabfrage konnte nicht erstellt werden."

        case .serverError:
            return "Der Wetterdienst hat keine gültige Antwort geliefert."

        case .forecastTimeMissing:
            return "12:00 Uhr Ortszeit wurde in der Vorhersage nicht gefunden."
        }
    }
}

private struct APIResponse: Decodable {
    let elevation: Double
    let timezone: String
    let hourly: Hourly
    let daily: Daily
}

private struct Hourly: Decodable {
    let time: [String]
    let temperature2m: [Double?]
    let precipitationProbability: [Double?]
    let weatherCode: [Int?]
    let visibility: [Double?]
    let cloudCoverLow: [Double?]
    let pressureMSL: [Double?]
    let windGusts10m: [Double?]
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
        case temperature2m = "temperature_2m"
        case precipitationProbability = "precipitation_probability"
        case weatherCode = "weather_code"
        case visibility
        case cloudCoverLow = "cloud_cover_low"
        case pressureMSL = "pressure_msl"
        case windGusts10m = "wind_gusts_10m"
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

private struct Daily: Decodable {
    let time: [String]
    let sunrise: [String?]
    let sunset: [String?]
    let weatherCode: [Int?]
    let temperature2mMax: [Double?]
    let temperature2mMin: [Double?]

    enum CodingKeys: String, CodingKey {
        case time
        case sunrise
        case sunset
        case weatherCode = "weather_code"
        case temperature2mMax = "temperature_2m_max"
        case temperature2mMin = "temperature_2m_min"
    }
}

