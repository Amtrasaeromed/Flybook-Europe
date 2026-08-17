import Foundation

enum SparseForecastTimeline {
    static func nearestIndex(
        in localHours: [Int],
        to targetHour: Int,
        maximumDistanceHours: Int = 3
    ) -> Int? {
        guard let index = localHours.indices.min(by: {
            abs(localHours[$0] - targetHour)
                < abs(localHours[$1] - targetHour)
        }),
        abs(localHours[index] - targetHour) <= maximumDistanceHours
        else { return nil }
        return index
    }

    static func sample(
        in samples: [EDFZWeatherSample],
        nearestToLocalHour targetHour: Int,
        calendar: Calendar
    ) -> EDFZWeatherSample? {
        let localHours = samples.map {
            calendar.component(.hour, from: $0.validTime)
        }
        guard let index = nearestIndex(in: localHours, to: targetHour) else {
            return nil
        }
        return samples[index]
    }
}

actor WeatherService {
    static let shared = WeatherService()

    private let cacheLifetime: TimeInterval = 30 * 60
    private let staleSeamlessFallbackLifetime: TimeInterval = 3 * 60 * 60

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

        let cachedWeather = try? loadCache(icao: destination.icao)
        if !forceRefresh,
           let cached = cachedWeather,
           Date().timeIntervalSince(cached.retrievedAt) < cacheLifetime,
           cacheContainsFogRisk(cached),
           cacheHasTenDayForecast(cached),
           cacheCovers(cached, targetInstants: targetInstants)
        {
            return removingPastDailyForecast(
                from: cached,
                destination: destination
            )
        }

        // ICON Seamless verbindet D2, ICON-EU und ICON Global und bleibt fuer
        // alle von DWD abgedeckten Tage vorrangig. Fuer die vollstaendige
        // 10-Tage-Ansicht wird die Langfristquelle nur zum Verlaengern genutzt.
        let iconWeather = await fetchICONSeamlessWeather(
            destination: destination,
            latitude: latitude,
            longitude: longitude,
            targetInstants: targetInstants
        )
        let downloadedWeather: DestinationWeather
        if let iconWeather,
           cacheHasTenDayForecast(iconWeather),
           cacheCovers(iconWeather, targetInstants: targetInstants) {
            downloadedWeather = iconWeather
        } else if let cachedWeather,
                  isICONSeamless(cachedWeather),
                  Date().timeIntervalSince(cachedWeather.retrievedAt)
                    < staleSeamlessFallbackLifetime,
                  cacheContainsFogRisk(cachedWeather),
                  cacheHasTenDayForecast(cachedWeather),
                  cacheCovers(
                    cachedWeather,
                    targetInstants: targetInstants
                  ) {
            // Beide Live-Routen wurden bereits versucht. Ein noch zum
            // dreistuendigen Modellzyklus passender Seamless-Stand bleibt
            // vor Best Match oder einem Fremdmodell die bessere Reserve.
            downloadedWeather = cachedWeather
        } else {
            do {
                let bestMatch = try await fetch(
                    destination: destination,
                    latitude: latitude,
                    longitude: longitude,
                    endpoint: "forecast",
                    model: nil,
                    modelLabel: "Best Match",
                    forecastDays: 10,
                    targetInstants: targetInstants
                )
                downloadedWeather = mergeWeather(
                    icon: iconWeather,
                    fallback: bestMatch
                )
            } catch {
                if let cached = cachedWeather,
                   cacheHasTenDayForecast(cached),
                   cacheCovers(cached, targetInstants: targetInstants) {
                    downloadedWeather = mergeWeather(
                        icon: iconWeather,
                        fallback: cached
                    )
                } else {
                    let airport = AirportReference(
                        icao: destination.icao,
                        name: destination.name,
                        latitude: latitude,
                        longitude: longitude,
                        elevationFeet: destination.elevationFeet,
                        timeZone: TimeZone(
                            identifier: destination.timeZoneIdentifier
                        ) ?? .current,
                        referenceRunway: destination.referenceRunway
                    )
                    let fallback: EDFZForecast
                    do {
                        fallback = try await EDFZWeatherService.shared
                            .metNorwayForecast(airport: airport)
                    } catch {
                        fallback = try await DWDMOSMIXService.shared
                            .forecast(airport: airport)
                    }
                    let metWeather = metNorwayWeather(
                        fallback,
                        destination: destination,
                        targetInstants: targetInstants
                    )
                    downloadedWeather = mergeWeather(
                        icon: iconWeather,
                        fallback: metWeather
                    )
                }
            }
        }

        let currentForecast = removingPastDailyForecast(
            from: downloadedWeather,
            destination: destination
        )
        try saveCache(currentForecast)
        return currentForecast
    }

    private func fetchICONSeamlessWeather(
        destination: Destination,
        latitude: Double,
        longitude: Double,
        targetInstants: [Date]
    ) async -> DestinationWeather? {
        for route in ICONSeamlessAccessRoute.allCases {
            do {
                return try await fetch(
                    destination: destination,
                    latitude: latitude,
                    longitude: longitude,
                    endpoint: route.rawValue,
                    model: "icon_seamless",
                    modelLabel: "ICON Seamless",
                    forecastDays: 8,
                    targetInstants: targetInstants
                )
            } catch is CancellationError {
                return nil
            } catch {
                continue
            }
        }
        return nil
    }

    private func isICONSeamless(_ weather: DestinationWeather) -> Bool {
        let labels = weather.days.map(\.model)
            + weather.dailyForecast.prefix(5).map(\.model)
        return !labels.isEmpty
            && labels.allSatisfy { $0.contains("ICON Seamless") }
    }

    /// Forecast providers and the on-disk fallback can still contain the
    /// previous day shortly after midnight. Daily cards must always start on
    /// the airport's current local calendar day, independently of the user's
    /// timezone and of cache age.
    private func removingPastDailyForecast(
        from weather: DestinationWeather,
        destination: Destination,
        now: Date = Date()
    ) -> DestinationWeather {
        let timeZone = TimeZone(identifier: weather.timezone)
            ?? TimeZone(identifier: destination.timeZoneIdentifier)
            ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: now)

        return DestinationWeather(
            icao: weather.icao,
            retrievedAt: weather.retrievedAt,
            timezone: weather.timezone,
            days: weather.days,
            dailyForecast: weather.dailyForecast.filter {
                $0.localDate >= today
            }
        )
    }

    private func metNorwayWeather(
        _ forecast: EDFZForecast,
        destination: Destination,
        targetInstants: [Date]
    ) -> DestinationWeather {
        let sourceLabel = forecast.source == .mosmix
            ? "DWD MOSMIX"
            : "MET Norway"
        let timeZone = TimeZone(
            identifier: destination.timeZoneIdentifier
        ) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HH:mm"

        let grouped = Dictionary(grouping: forecast.samples) {
            dateFormatter.string(from: $0.validTime)
        }
        let sortedDates = grouped.keys.sorted()

        func nearestSample(to instant: Date) -> EDFZWeatherSample? {
            forecast.samples.min {
                abs($0.validTime.timeIntervalSince(instant))
                    < abs($1.validTime.timeIntervalSince(instant))
            }
        }

        func sample(on date: String, nearHour hour: Int) -> EDFZWeatherSample? {
            grouped[date]?.min {
                abs(calendar.component(.hour, from: $0.validTime) - hour)
                    < abs(calendar.component(.hour, from: $1.validTime) - hour)
            }
        }

        func worstCategory(_ samples: [EDFZWeatherSample]) -> FlightCategory? {
            samples.map(\.category).max { $0.severity < $1.severity }
        }

        func fogRiskScore(for sample: EDFZWeatherSample) -> Int? {
            guard let temperature = sample.temperatureCelsius,
                  let dewPoint = sample.dewPointCelsius,
                  let wind = sample.windSpeedKnots,
                  let visibility = sample.visibilityMeters,
                  let lowCloud = sample.lowCloudCoverPercent
            else { return nil }

            let solar = SolarCalculator.events(
                forLocalDayContaining: sample.validTime,
                latitude: destination.latitude ?? 0,
                longitude: destination.longitude ?? 0,
                timeZone: timeZone
            )
            let isNight = solar.map {
                sample.validTime < $0.sunrise || sample.validTime >= $0.sunset
            } ?? false
            return FogRiskModel.calculate(FogRiskInput(
                temperatureC: temperature,
                dewPointC: dewPoint,
                windKt: wind,
                visibilityKm: visibility / 1_000,
                lowCloudPercent: lowCloud,
                ceilingFt: FogRiskModel.ceilingFeet(
                    observed: sample.ceilingFeetAGL,
                    temperatureC: temperature,
                    dewPointC: dewPoint,
                    lowCloudPercent: lowCloud
                ),
                lowLevelRHPercent: nil,
                totalCloudPercent: sample.totalCloudCoverPercent ?? 0,
                rainLast6HoursMM: 0,
                isNight: isNight,
                isValley: false
            ))?.score
        }

        let days = Array(targetInstants.prefix(2)).enumerated().compactMap {
            offset, instant -> ForecastDay? in
            guard let sample = nearestSample(to: instant),
                  abs(sample.validTime.timeIntervalSince(instant)) <= 3 * 60 * 60
            else { return nil }
            let dateKey = dateFormatter.string(from: instant)
            let solar = SolarCalculator.events(
                forLocalDayContaining: instant,
                latitude: destination.latitude ?? 0,
                longitude: destination.longitude ?? 0,
                timeZone: timeZone
            )
            return ForecastDay(
                localDate: dateKey,
                displayDay: offset == 0 ? "LANDUNG HINFLUG" : "START RÜCKFLUG",
                localTime: timeFormatter.string(from: instant) + " LCL",
                model: sourceLabel,
                temperatureCelsius: sample.temperatureCelsius,
                weatherCode: sample.weatherCode,
                visibilityMeters: sample.visibilityMeters,
                lowCloudCoverPercent: sample.lowCloudCoverPercent,
                lowestCloudBaseFeetAGL: sample.lowestCloudBaseFeetAGL,
                ceilingFeetAGL: sample.ceilingFeetAGL,
                precipitationProbability: nil,
                pressureMSLHPA: sample.pressureMSLHPA,
                windGustKnots: sample.windGustKnots,
                surfaceWind: WindSample(
                    directionDegrees: sample.windDirectionDegrees,
                    speedKnots: sample.windSpeedKnots
                ),
                upperWind: WindSample(directionDegrees: nil, speedKnots: nil),
                sunrise: solar.map { timeFormatter.string(from: $0.sunrise) },
                sunset: solar.map { timeFormatter.string(from: $0.sunset) },
                category: sample.category
            )
        }

        let daily = Array(sortedDates.prefix(10)).map { date in
            let samples = grouped[date] ?? []
            let morning = sample(on: date, nearHour: 8)
            let midday = sample(on: date, nearHour: 14)
            let evening = sample(on: date, nearHour: 20)
            let hourlyWind: [Double?] = DailyWeatherTimeline.hours.map { hour in
                SparseForecastTimeline.sample(
                    in: samples,
                    nearestToLocalHour: hour,
                    calendar: calendar
                )?.windSpeedKnots
            }
            let hourlyFogRisk: [Int?] = DailyWeatherTimeline.hours.map { hour in
                guard let sample = SparseForecastTimeline.sample(
                    in: samples,
                    nearestToLocalHour: hour,
                    calendar: calendar
                ) else { return nil }
                return fogRiskScore(for: sample)
            }
            return DailyForecast(
                localDate: date,
                weatherCode: midday?.weatherCode ?? samples.first?.weatherCode,
                morningWeatherCode: morning?.weatherCode,
                middayWeatherCode: midday?.weatherCode,
                eveningWeatherCode: evening?.weatherCode,
                morningCategory: morning?.category,
                middayCategory: midday?.category,
                eveningCategory: evening?.category,
                minimumTemperatureCelsius: samples.compactMap(\.temperatureCelsius).min(),
                maximumTemperatureCelsius: samples.compactMap(\.temperatureCelsius).max(),
                maximumSurfaceWindKnots: samples.compactMap(\.windSpeedKnots).max(),
                maximumWindGustKnots: samples.compactMap(\.windGustKnots).max(),
                hourlySurfaceWindKnots: hourlyWind,
                hourlyFogRiskScores: hourlyFogRisk,
                model: sourceLabel
            )
        }

        return DestinationWeather(
            icao: destination.icao,
            retrievedAt: Date(),
            timezone: timeZone.identifier,
            days: days,
            dailyForecast: daily
        )
    }

    private func mergedDailyForecast(
        d2: DestinationWeather?,
        eu: DestinationWeather?,
        seamless: DestinationWeather?,
        extended: DestinationWeather
    ) -> [DailyForecast] {
        let d2ByDate = dailyByDate(d2)
        let euByDate = dailyByDate(eu)
        let seamlessByDate = dailyByDate(seamless)

        return Array(extended.dailyForecast.prefix(10))
            .map { extendedDay in
                let date = extendedDay.localDate
                var mergedDay = extendedDay

                if let seamlessDay = seamlessByDate[date] {
                    mergedDay = completeDailyForecast(
                        preferred: seamlessDay,
                        fallback: mergedDay
                    )
                }

                if let euDay = euByDate[date] {
                    mergedDay = completeDailyForecast(
                        preferred: euDay,
                        fallback: mergedDay
                    )
                }

                if let d2Day = d2ByDate[date] {
                    mergedDay = completeDailyForecast(
                        preferred: d2Day,
                        fallback: mergedDay
                    )
                }

                return mergedDay
            }
    }

    private func completeDailyForecast(
        preferred: DailyForecast,
        fallback: DailyForecast
    ) -> DailyForecast {
        let preferredWind = preferred.hourlySurfaceWindKnots
        let fallbackWind = fallback.hourlySurfaceWindKnots
        let mergedWind = mergeHourlyValues(
            preferred: preferredWind,
            fallback: fallbackWind
        )
        let mergedFogRisk = mergeHourlyRiskScores(
            preferred: preferred.hourlyFogRiskScores,
            fallback: fallback.hourlyFogRiskScores
        )

        let preferredHasAnyHourlyData =
            hasAnyValue(preferredWind)
            || hasAnyRiskValue(preferred.hourlyFogRiskScores)
        let preferredHasFullDay = hasFullHourlyCoverage(preferredWind)

        return DailyForecast(
            localDate: preferred.localDate,
            weatherCode:
                preferredHasFullDay
                ? (preferred.weatherCode ?? fallback.weatherCode)
                : fallback.weatherCode ?? preferred.weatherCode,
            morningWeatherCode:
                preferredValueForHour(
                    preferred.morningWeatherCode,
                    hourlyValues: preferredWind,
                    hourIndex: 2
                ) ?? fallback.morningWeatherCode,
            middayWeatherCode:
                preferredValueForHour(
                    preferred.middayWeatherCode,
                    hourlyValues: preferredWind,
                    hourIndex: 8
                ) ?? fallback.middayWeatherCode,
            eveningWeatherCode:
                preferredValueForHour(
                    preferred.eveningWeatherCode,
                    hourlyValues: preferredWind,
                    hourIndex: 14
                ) ?? fallback.eveningWeatherCode,
            morningCategory:
                preferredCategory(
                    preferred.morningCategory,
                    hourlyValues: preferredWind,
                    indices: 0..<5
                ) ?? fallback.morningCategory,
            middayCategory:
                preferredCategory(
                    preferred.middayCategory,
                    hourlyValues: preferredWind,
                    indices: 5..<11
                ) ?? fallback.middayCategory,
            eveningCategory:
                preferredCategory(
                    preferred.eveningCategory,
                    hourlyValues: preferredWind,
                    indices: 11..<17
                ) ?? fallback.eveningCategory,
            minimumTemperatureCelsius:
                preferredHasFullDay
                ? (preferred.minimumTemperatureCelsius
                    ?? fallback.minimumTemperatureCelsius)
                : fallback.minimumTemperatureCelsius
                    ?? preferred.minimumTemperatureCelsius,
            maximumTemperatureCelsius:
                preferredHasFullDay
                ? (preferred.maximumTemperatureCelsius
                    ?? fallback.maximumTemperatureCelsius)
                : fallback.maximumTemperatureCelsius
                    ?? preferred.maximumTemperatureCelsius,
            maximumSurfaceWindKnots:
                mergedWind?.compactMap { $0 }.max()
                ?? maxOptional(
                    preferred.maximumSurfaceWindKnots,
                    fallback.maximumSurfaceWindKnots
                ),
            maximumWindGustKnots:
                maxOptional(
                    preferred.maximumWindGustKnots,
                    fallback.maximumWindGustKnots
                ),
            hourlySurfaceWindKnots: mergedWind,
            hourlyFogRiskScores: mergedFogRisk,
            model: mergedModelLabel(
                preferred: preferred,
                fallback: fallback,
                preferredContributed: preferredHasAnyHourlyData
            )
        )
    }

    private func mergeHourlyValues(
        preferred: [Double?]?,
        fallback: [Double?]?
    ) -> [Double?]? {
        guard preferred != nil || fallback != nil else {
            return nil
        }

        let count = max(preferred?.count ?? 0, fallback?.count ?? 0)
        return (0..<count).map { index in
            value(preferred, at: index) ?? value(fallback, at: index)
        }
    }

    private func value(
        _ values: [Double?]?,
        at index: Int
    ) -> Double? {
        guard
            let values,
            values.indices.contains(index)
        else {
            return nil
        }
        return values[index]
    }

    private func mergeHourlyRiskScores(
        preferred: [Int?]?,
        fallback: [Int?]?
    ) -> [Int?]? {
        guard preferred != nil || fallback != nil else { return nil }
        let count = max(preferred?.count ?? 0, fallback?.count ?? 0)
        return (0..<count).map { index in
            riskValue(preferred, at: index) ?? riskValue(fallback, at: index)
        }
    }

    private func riskValue(_ values: [Int?]?, at index: Int) -> Int? {
        guard let values, values.indices.contains(index) else { return nil }
        return values[index]
    }

    private func hasAnyValue(_ values: [Double?]?) -> Bool {
        values?.contains { $0 != nil } == true
    }

    private func hasAnyRiskValue(_ values: [Int?]?) -> Bool {
        values?.contains { $0 != nil } == true
    }

    private func hasFullHourlyCoverage(_ values: [Double?]?) -> Bool {
        guard let values, values.count >= DailyWeatherTimeline.hours.count else {
            return false
        }
        return values.prefix(DailyWeatherTimeline.hours.count)
            .allSatisfy { $0 != nil }
    }

    private func preferredValueForHour<T>(
        _ preferred: T?,
        hourlyValues: [Double?]?,
        hourIndex: Int
    ) -> T? {
        guard value(hourlyValues, at: hourIndex) != nil else {
            return nil
        }
        return preferred
    }

    private func preferredCategory(
        _ preferred: FlightCategory?,
        hourlyValues: [Double?]?,
        indices: Range<Int>
    ) -> FlightCategory? {
        guard
            let preferred,
            preferred != .unavailable,
            indices.allSatisfy({ value(hourlyValues, at: $0) != nil })
        else {
            return nil
        }
        return preferred
    }

    private func maxOptional(
        _ first: Double?,
        _ second: Double?
    ) -> Double? {
        switch (first, second) {
        case let (first?, second?):
            return max(first, second)
        case let (first?, nil):
            return first
        case let (nil, second?):
            return second
        case (nil, nil):
            return nil
        }
    }

    private func mergedModelLabel(
        preferred: DailyForecast,
        fallback: DailyForecast,
        preferredContributed: Bool
    ) -> String {
        guard preferredContributed else {
            return fallback.model
        }

        let preferredWind = preferred.hourlySurfaceWindKnots
        let fallbackWind = fallback.hourlySurfaceWindKnots
        let fallbackContributed = (0..<max(
            preferredWind?.count ?? 0,
            fallbackWind?.count ?? 0
        )).contains { index in
            value(preferredWind, at: index) == nil
                && value(fallbackWind, at: index) != nil
        }

        if fallbackContributed {
            return "\(preferred.model) → \(fallback.model)"
        }
        return preferred.model
    }

    private func dailyByDate(
        _ weather: DestinationWeather?
    ) -> [String: DailyForecast] {
        Dictionary(
            uniqueKeysWithValues:
                (weather?.dailyForecast ?? []).map {
                    ($0.localDate, $0)
                }
        )
    }

    private func mergeWeather(
        icon: DestinationWeather?,
        fallback: DestinationWeather
    ) -> DestinationWeather {
        let iconDaysByLabel = Dictionary(
            uniqueKeysWithValues:
                (icon?.days ?? []).map {
                    ($0.displayDay, $0)
                }
        )

        let fallbackDaysByLabel = Dictionary(
            uniqueKeysWithValues:
                fallback.days.map {
                    ($0.displayDay, $0)
                }
        )

        let labels = [
            "LANDUNG HINFLUG",
            "START RÜCKFLUG"
        ]

        let mergedDays = labels.compactMap {
            label -> ForecastDay? in

                if let iconDay = iconDaysByLabel[label] {
                    return iconDay
                }

                return fallbackDaysByLabel[label]
            }

        let iconDailyByDate = Dictionary(
            uniqueKeysWithValues:
                (icon?.dailyForecast ?? []).map {
                    ($0.localDate, $0)
                }
        )

        let mergedDaily = Array(
            fallback.dailyForecast.prefix(10)
        ).map { fallbackDay in
            guard let iconDay = iconDailyByDate[fallbackDay.localDate] else {
                return fallbackDay
            }
            return completeDailyForecast(
                preferred: iconDay,
                fallback: fallbackDay
            )
        }

        return DestinationWeather(
            icao: fallback.icao,
            retrievedAt: Date(),
            timezone: fallback.timezone,
            days: mergedDays,
            dailyForecast: mergedDaily
        )
    }

    private func fetch(
        destination: Destination,
        latitude: Double,
        longitude: Double,
        endpoint: String,
        model: String?,
        modelLabel: String,
        forecastDays: Int,
        targetInstants: [Date]
    ) async throws -> DestinationWeather {
        var components = URLComponents(
            string: "https://api.open-meteo.com/v1/\(endpoint)"
        )

        var queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(
                name: "forecast_days",
                value: String(forecastDays)
            ),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(
                name: "hourly",
                value: [
                    "temperature_2m",
                    "dew_point_2m",
                    "precipitation_probability",
                    "precipitation",
                    "weather_code",
                    "visibility",
                    "cloud_cover",
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
        if let model {
            queryItems.append(
                URLQueryItem(name: "models", value: model)
            )
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw WeatherError.invalidURL
        }

        let (data, response) = try await FlightNetwork.openMeteoData(
            from: url,
            priority: .low
        )

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

        let forecastDays: [ForecastDay] =
            selectedInstants.enumerated().compactMap {
            offset,
            targetInstant -> ForecastDay? in

            guard
                let index = nearestIndex(
                    target: targetInstant,
                    values: parsedTimes,
                    maximumDistance: 90 * 60
                ),
                hasForecastData(api.hourly, at: index)
            else {
                return nil
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

            let cloudBase = estimatedCloudBaseFeet(
                temperature: optionalValue(
                    api.hourly.temperature2m,
                    at: index
                ),
                dewPoint: optionalValue(
                    api.hourly.dewPoint2m,
                    at: index
                )
            )

            let ceiling = estimateCeiling(
                lowCloudPercent: lowCloudCover,
                cloudBaseFeet: cloudBase
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
                lowCloudCoverPercent: lowCloudCover,
                lowestCloudBaseFeetAGL: cloudBase,
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
            api.daily.time.indices.prefix(15)
        ).map { index in
            let localDate = api.daily.time[index]
            let maximumSurfaceWindKnots = api.hourly.time.indices
                .filter {
                    api.hourly.time[$0].hasPrefix(localDate)
                }
                .compactMap {
                    optionalValue(
                        api.hourly.windSpeed10m,
                        at: $0
                    )
                }
                .max()
            let maximumWindGustKnots = api.hourly.time.indices
                .filter {
                    api.hourly.time[$0].hasPrefix(localDate)
                }
                .compactMap {
                    optionalValue(
                        api.hourly.windGusts10m,
                        at: $0
                    )
                }
                .max()

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

            let hourlySurfaceWindKnots: [Double?] =
                DailyWeatherTimeline.hours.map { hour in
                let timestamp = String(
                    format: "%@T%02d:00",
                    localDate,
                    hour
                )
                guard let hourlyIndex = api.hourly.time.firstIndex(
                    of: timestamp
                ) else {
                    return nil
                }
                return optionalValue(
                    api.hourly.windSpeed10m,
                    at: hourlyIndex
                )
            }

            let dailySunrise = optionalValue(api.daily.sunrise, at: index)
                .flatMap { dateTimeParser.date(from: $0) }
            let dailySunset = optionalValue(api.daily.sunset, at: index)
                .flatMap { dateTimeParser.date(from: $0) }

            let hourlyFogRiskScores: [Int?] =
                DailyWeatherTimeline.hours.map { hour in
                    let timestamp = String(
                        format: "%@T%02d:00",
                        localDate,
                        hour
                    )
                    guard let hourlyIndex = api.hourly.time.firstIndex(
                        of: timestamp
                    ),
                    let temperature = optionalValue(
                        api.hourly.temperature2m,
                        at: hourlyIndex
                    ),
                    let dewPoint = optionalValue(
                        api.hourly.dewPoint2m,
                        at: hourlyIndex
                    ),
                    let wind = optionalValue(
                        api.hourly.windSpeed10m,
                        at: hourlyIndex
                    ),
                    let visibility = optionalValue(
                        api.hourly.visibility,
                        at: hourlyIndex
                    ),
                    let lowCloud = optionalValue(
                        api.hourly.cloudCoverLow,
                        at: hourlyIndex
                    ) else { return nil }

                    let cloudBase = estimatedCloudBaseFeet(
                        temperature: temperature,
                        dewPoint: dewPoint
                    )
                    let ceiling = estimateCeiling(
                        lowCloudPercent: lowCloud,
                        cloudBaseFeet: cloudBase
                    ) ?? 10_000
                    let rainStartIndex = max(0, hourlyIndex - 5)
                    let rainLast6Hours = (rainStartIndex...hourlyIndex)
                        .compactMap {
                            optionalValue(api.hourly.precipitation, at: $0)
                        }
                        .reduce(0, +)
                    let instant = parsedTimes[hourlyIndex]
                    let isNight = instant.map { value in
                        guard let sunrise = dailySunrise,
                              let sunset = dailySunset else { return false }
                        return value < sunrise || value >= sunset
                    } ?? false

                    return FogRiskModel.calculate(FogRiskInput(
                        temperatureC: temperature,
                        dewPointC: dewPoint,
                        windKt: wind,
                        visibilityKm: visibility / 1_000,
                        lowCloudPercent: lowCloud,
                        ceilingFt: ceiling,
                        lowLevelRHPercent: nil,
                        totalCloudPercent: optionalValue(
                            api.hourly.cloudCover,
                            at: hourlyIndex
                        ) ?? 0,
                        rainLast6HoursMM: rainLast6Hours,
                        isNight: isNight,
                        isValley: false
                    ))?.score
                }

            func category(at hourlyIndex: Int) -> FlightCategory {
                let lowCloudCover = optionalValue(
                    api.hourly.cloudCoverLow,
                    at: hourlyIndex
                )
                let cloudBase = estimatedCloudBaseFeet(
                    temperature: optionalValue(
                        api.hourly.temperature2m,
                        at: hourlyIndex
                    ),
                    dewPoint: optionalValue(
                        api.hourly.dewPoint2m,
                        at: hourlyIndex
                    )
                )
                return flightCategory(
                    visibilityMeters: optionalValue(
                        api.hourly.visibility,
                        at: hourlyIndex
                    ),
                    ceilingFeet: estimateCeiling(
                        lowCloudPercent: lowCloudCover,
                        cloudBaseFeet: cloudBase
                    )
                )
            }

            func worstCategory(in hours: Range<Int>) -> FlightCategory {
                let categories = hours.compactMap { hour -> FlightCategory? in
                    let timestamp = String(
                        format: "%@T%02d:00",
                        localDate,
                        hour
                    )
                    guard let hourlyIndex = api.hourly.time.firstIndex(
                        of: timestamp
                    ) else {
                        return nil
                    }
                    return category(at: hourlyIndex)
                }

                return categories.max {
                    $0.severity < $1.severity
                } ?? .unavailable
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
                morningCategory:
                    worstCategory(in: 5..<11),
                middayCategory:
                    worstCategory(in: 11..<17),
                eveningCategory:
                    worstCategory(in: 17..<23),
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
                maximumSurfaceWindKnots:
                    maximumSurfaceWindKnots,
                maximumWindGustKnots:
                    maximumWindGustKnots,
                hourlySurfaceWindKnots:
                    hourlySurfaceWindKnots,
                hourlyFogRiskScores:
                    hourlyFogRiskScores,
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
        values: [Date?],
        maximumDistance: TimeInterval
    ) -> Int? {
        guard
            let nearest = values.enumerated()
                .compactMap({ index, value
                    -> (index: Int, distance: TimeInterval)? in
                    guard let value else {
                        return nil
                    }
                    return (
                        index: index,
                        distance: abs(value.timeIntervalSince(target))
                    )
                })
                .min(by: { first, second in
                    first.distance < second.distance
                }),
            nearest.distance <= maximumDistance
        else {
            return nil
        }

        return nearest.index
    }

    private func hasForecastData(
        _ hourly: Hourly,
        at index: Int
    ) -> Bool {
        optionalValue(hourly.temperature2m, at: index) != nil
            || optionalValue(hourly.weatherCode, at: index) != nil
            || optionalValue(hourly.visibility, at: index) != nil
            || optionalValue(hourly.windSpeed10m, at: index) != nil
            || optionalValue(hourly.windGusts10m, at: index) != nil
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
        lowCloudPercent: Double?,
        cloudBaseFeet: Double?
    ) -> Double? {
        guard let lowCloudPercent,
              lowCloudPercent >= 62.5
        else {
            return nil
        }

        // In METAR terms only BKN and OVC constitute a ceiling.
        // FEW and SCT must never drive an MVFR/IFR category.
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

    private func cacheCovers(
        _ weather: DestinationWeather,
        targetInstants: [Date]
    ) -> Bool {
        guard !targetInstants.isEmpty else { return true }
        let zone = TimeZone(identifier: weather.timezone)
            ?? TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        // DailyForecast contains only the overview tiles. It is not enough
        // for flight planning, which needs wind, pressure, visibility and
        // cloud data from ForecastDay. Treating a daily tile as cache
        // coverage previously suppressed the MET Norway fallback and left
        // the planning cards at N/A.
        let available = Set(weather.days.map(\.localDate))
        return targetInstants.allSatisfy {
            available.contains(formatter.string(from: $0))
        }
    }

    private func cacheContainsFogRisk(_ weather: DestinationWeather) -> Bool {
        let days = Array(weather.dailyForecast.prefix(5))
        guard days.count == 5 else { return false }
        return days.allSatisfy { day in
            guard let scores = day.hourlyFogRiskScores,
                  scores.count >= DailyWeatherTimeline.hours.count
            else { return false }
            return scores
                .prefix(DailyWeatherTimeline.hours.count)
                .allSatisfy { $0 != nil }
        }
    }

    private func cacheHasTenDayForecast(
        _ weather: DestinationWeather
    ) -> Bool {
        weather.dailyForecast.count >= 10
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
    let dewPoint2m: [Double?]
    let precipitationProbability: [Double?]
    let precipitation: [Double?]
    let weatherCode: [Int?]
    let visibility: [Double?]
    let cloudCover: [Double?]
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
        case dewPoint2m = "dew_point_2m"
        case precipitationProbability = "precipitation_probability"
        case precipitation
        case weatherCode = "weather_code"
        case visibility
        case cloudCover = "cloud_cover"
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
