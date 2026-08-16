import Foundation

enum ICONSeamlessAccessRoute: String, CaseIterable, Codable, Hashable {
    case dedicatedDWD = "dwd-icon"
    case genericForecast = "forecast"

    var endpoint: String {
        "https://api.open-meteo.com/v1/\(rawValue)"
    }

    func url(queryItems: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: endpoint)
        components?.queryItems = queryItems + [
            URLQueryItem(name: "models", value: "icon_seamless")
        ]
        return components?.url
    }
}

enum EDFZForecastSource: Codable, Hashable {
    case iconSeamless(ICONSeamlessAccessRoute)
    case bestMatch
    case metNorway
    case mosmix

    var isICONSeamless: Bool {
        if case .iconSeamless = self { return true }
        return false
    }
}

struct EDFZWeatherSample: Codable, Hashable {
    let validTime: Date
    let windDirectionDegrees: Double?
    let windSpeedKnots: Double?
    let windGustKnots: Double?
    let temperatureCelsius: Double?
    let dewPointCelsius: Double?
    let weatherCode: Int?
    let visibilityMeters: Double?
    let lowCloudCoverPercent: Double?
    let totalCloudCoverPercent: Double?
    let lowestCloudBaseFeetAGL: Double?
    let ceilingFeetAGL: Double?
    var ceilingSource: PlanningCeilingSource? = nil
    let category: FlightCategory
    let pressureMSLHPA: Double?
}

struct EDFZForecast: Codable, Hashable {
    let retrievedAt: Date
    let samples: [EDFZWeatherSample]
    let source: EDFZForecastSource

    func sample(nearestTo instant: Date?) -> EDFZWeatherSample? {
        guard let instant, !samples.isEmpty else { return nil }
        let nearest = samples.min {
            abs($0.validTime.timeIntervalSince(instant))
                < abs($1.validTime.timeIntervalSince(instant))
        }
        guard let nearest else { return nil }
        let distance = abs(nearest.validTime.timeIntervalSince(instant))
        if distance <= 90 * 60 { return nearest }

        // MET Norway becomes three- or six-hourly later in its forecast.
        // Accept half of the local model cadence so a valid sparse forecast
        // is not incorrectly presented as missing.
        let neighborSpacing = samples
            .filter { $0.validTime != nearest.validTime }
            .map { abs($0.validTime.timeIntervalSince(nearest.validTime)) }
            .min() ?? 0
        let sparseTolerance = min(3 * 60 * 60, neighborSpacing / 2 + 10 * 60)
        guard neighborSpacing >= 3 * 60 * 60,
              distance <= sparseTolerance
        else { return nil }
        return nearest
    }
}

enum RunwayCrosswindWarning: Int, Comparable {
    case none = 0
    case yellow = 1
    case red = 2

    static func < (
        lhs: RunwayCrosswindWarning,
        rhs: RunwayCrosswindWarning
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct RunwayWindComponents {
    let headwindKnots: Double
    let crosswindKnots: Double
    let gustCrosswindKnots: Double?
    let crosswindComesFromRight: Bool
}

enum EDFZRunway {
    static func crosswindWarning(
        for components: RunwayWindComponents?
    ) -> RunwayCrosswindWarning {
        guard let components else { return .none }
        let displayedSteadyCrosswind = components.crosswindKnots.rounded()
        let displayedGustCrosswind = (components.gustCrosswindKnots ?? 0).rounded()
        if displayedSteadyCrosswind > 15 || displayedGustCrosswind > 30 {
            return .red
        }
        if displayedSteadyCrosswind >= 10 || displayedGustCrosswind > 15 {
            return .yellow
        }
        return .none
    }

    static func activeRunway(
        for airportICAO: String,
        referenceRunway: String? = nil,
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
            guard let parsed = runwayPair(from: referenceRunway) else {
                return nil
            }
            runways = parsed
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

    static func crosswindWarning(
        for airportICAO: String,
        runway: String?,
        referenceRunway: String? = nil,
        windFromDegrees: Double?,
        steadyWindKnots: Double?,
        gustKnots: Double?
    ) -> RunwayCrosswindWarning {
        guard
            let runway,
            let runwayHeading = heading(
                for: airportICAO,
                runway: runway,
                referenceRunway: referenceRunway
            ),
            let windFromDegrees,
            let steadyWindKnots
        else {
            return .none
        }

        let angleRadians = angularDifference(
            windFromDegrees,
            runwayHeading
        ) * .pi / 180.0
        let crosswindFactor = abs(sin(angleRadians))
        let steadyCrosswind = steadyWindKnots * crosswindFactor
        let gustCrosswind = gustKnots.map {
            $0 * crosswindFactor
        }
        // Use the same whole-knot values that are shown in the runway popover.
        // Otherwise, for example, 9.6 kt is displayed as 10 kt while the runway
        // recommendation would incorrectly remain green.
        let displayedSteadyCrosswind = steadyCrosswind.rounded()
        let displayedGustCrosswind = (gustCrosswind ?? 0).rounded()

        return crosswindWarning(for: RunwayWindComponents(
            headwindKnots: 0,
            crosswindKnots: displayedSteadyCrosswind,
            gustCrosswindKnots: gustKnots == nil ? nil : displayedGustCrosswind,
            crosswindComesFromRight: false
        ))
    }

    static func windComponents(
        for airportICAO: String,
        runway: String?,
        referenceRunway: String? = nil,
        windFromDegrees: Double?,
        speedKnots: Double?,
        gustKnots: Double? = nil
    ) -> RunwayWindComponents? {
        guard
            let runway,
            let runwayHeading = heading(
                for: airportICAO,
                runway: runway,
                referenceRunway: referenceRunway
            ),
            let windFromDegrees,
            let speedKnots
        else { return nil }

        let signedDifference = signedAngularDifference(
            windFromDegrees,
            runwayHeading
        )
        let angleRadians = signedDifference * .pi / 180.0
        let signedCrosswind = speedKnots * sin(angleRadians)
        return RunwayWindComponents(
            headwindKnots: speedKnots * cos(angleRadians),
            crosswindKnots: abs(signedCrosswind),
            gustCrosswindKnots: gustKnots.map {
                abs($0 * sin(angleRadians))
            },
            crosswindComesFromRight: signedCrosswind > 0
        )
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

    private static func signedAngularDifference(
        _ first: Double,
        _ second: Double
    ) -> Double {
        var difference = (first - second)
            .truncatingRemainder(dividingBy: 360)
        if difference > 180 { difference -= 360 }
        if difference < -180 { difference += 360 }
        return difference
    }

    private static func heading(
        for airportICAO: String,
        runway: String,
        referenceRunway: String? = nil
    ) -> Double? {
        switch (airportICAO.uppercased(), runway) {
        case ("EDFZ", "07"), ("EDKA", "07"), ("EDWJ", "07"):
            return 70
        case ("EDFZ", "25"), ("EDKA", "25"), ("EDWJ", "25"):
            return 250
        case ("EHMZ", "09"), ("EDMZ", "09"):
            return 87
        case ("EHMZ", "27"), ("EDMZ", "27"):
            return 267
        default:
            return runwayHeading(from: runway)
        }
    }

    private static func runwayPair(
        from referenceRunway: String?
    ) -> (
        firstLabel: String,
        firstHeading: Double,
        secondLabel: String,
        secondHeading: Double
    )? {
        guard let labels = referenceRunway?
            .split(separator: "/")
            .map(String.init),
              labels.count == 2,
              let firstHeading = runwayHeading(from: labels[0]),
              let secondHeading = runwayHeading(from: labels[1])
        else { return nil }
        return (labels[0], firstHeading, labels[1], secondHeading)
    }

    private static func runwayHeading(from label: String) -> Double? {
        let digits = label.prefix { $0.isNumber }
        guard let number = Double(digits), (1...36).contains(number) else {
            return nil
        }
        return number == 36 ? 360 : number * 10
    }
}

actor EDFZWeatherService {
    static let shared = EDFZWeatherService()
    private struct MetNorwayDiskEntry: Codable {
        let data: Data
        let retrievedAt: Date
        let expiresAt: Date
        let lastModified: String?
    }

    private let primaryCacheLifetime: TimeInterval = 30 * 60
    private let backupRetryLifetime: TimeInterval = 5 * 60
    private let staleSeamlessFallbackLifetime: TimeInterval = 3 * 60 * 60
    private var forecastCache: [String: (Date, EDFZForecast)] = [:]
    private var forecastDiskCache: [String: EDFZForecast] = [:]
    private var didLoadForecastDiskCache = false
    private var metNorwayCache: [String: (Date, EDFZForecast)] = [:]
    private var metNorwayDiskCache: [String: MetNorwayDiskEntry] = [:]
    private var didLoadMetNorwayDiskCache = false
    private var forecastTasks: [String: Task<EDFZForecast, Error>] = [:]
    private var metNorwayTasks: [String: Task<EDFZForecast, Error>] = [:]

    func forecast(
        plannedDate: Date,
        airport: AirportReference,
        forceRefresh: Bool = false
    ) async throws -> EDFZForecast {
        loadForecastDiskCacheIfNeeded()
        let cacheKey = forecastKey(
            plannedDate: plannedDate,
            airport: airport
        )
        let previousForecast = forecastCache[cacheKey]?.1
            ?? forecastDiskCache[cacheKey]
        if !forceRefresh,
           let cached = previousForecast,
           Date().timeIntervalSince(cached.retrievedAt)
                < cacheLifetime(for: cached) {
            if let sample = cached.sample(nearestTo: plannedDate),
               (sample.lowCloudCoverPercent ?? 0) >= 62.5,
               sample.ceilingFeetAGL == nil {
                let enriched = await applyingDirectCeiling(
                    to: cached,
                    plannedDate: plannedDate,
                    airport: airport
                )
                forecastCache[cacheKey] = (Date(), enriched)
                forecastDiskCache[cacheKey] = enriched
                saveForecastDiskCache()
                return enriched
            }
            return cached
        }
        // Mehrere ViewModels zeigen oft denselben Platz (z. B. EDFZ auf Hin-
        // und Rueckflug). Sie teilen sich exakt einen laufenden Download.
        if let running = forecastTasks[cacheKey] {
            return try await running.value
        }
        let task = Task {
            let downloaded = try await self.downloadForecast(
                plannedDate: plannedDate,
                airport: airport,
                forceRefresh: forceRefresh,
                staleSeamlessForecast: previousForecast
            )
            return await self.applyingDirectCeiling(
                to: downloaded,
                plannedDate: plannedDate,
                airport: airport
            )
        }
        forecastTasks[cacheKey] = task
        do {
            let result = try await task.value
            forecastTasks[cacheKey] = nil
            forecastCache[cacheKey] = (Date(), result)
            forecastDiskCache[cacheKey] = result
            saveForecastDiskCache()
            return result
        } catch {
            forecastTasks[cacheKey] = nil
            throw error
        }
    }

    private func forecastKey(
        plannedDate: Date,
        airport: AirportReference
    ) -> String {
        var displayedCalendar = Calendar(identifier: .gregorian)
        displayedCalendar.timeZone = DestinationTimeZone.edfz
        let displayedParts = displayedCalendar.dateComponents(
            [.year, .month, .day, .hour],
            from: plannedDate
        )
        let year = displayedParts.year ?? 0
        let month = displayedParts.month ?? 0
        let dayOfMonth = displayedParts.day ?? 0
        let hour = displayedParts.hour ?? 0
        let startDay = String(
            format: "%04d-%02d-%02d",
            year,
            month,
            dayOfMonth
        )
        return "\(airport.icao)-\(startDay)-"
            + "\(String(format: "%02d", hour))-direct-ceiling-v2"
    }

    private func applyingDirectCeiling(
        to forecast: EDFZForecast,
        plannedDate: Date,
        airport: AirportReference
    ) async -> EDFZForecast {
        guard let target = forecast.sample(nearestTo: plannedDate),
              (target.lowCloudCoverPercent ?? 0) >= 62.5
        else { return forecast }
        var resolved = await DWDICONCeilingService.shared.ceiling(
            latitude: airport.latitude,
            longitude: airport.longitude,
            validTime: plannedDate
        )
        if resolved == nil,
           let mosmix = try? await DWDMOSMIXService.shared.forecast(
                airport: airport
           ),
           let mosmixCeiling = mosmix.sample(
                nearestTo: plannedDate
           )?.ceilingFeetAGL {
            resolved = DWDICONCeilingValue(
                feetAGL: mosmixCeiling,
                source: .dwdMOSMIX
            )
        }
        guard let resolved else { return forecast }
        let samples = forecast.samples.map { sample in
            guard sample.validTime == target.validTime else { return sample }
            let ceiling = resolved.feetAGL
            return EDFZWeatherSample(
                validTime: sample.validTime,
                windDirectionDegrees: sample.windDirectionDegrees,
                windSpeedKnots: sample.windSpeedKnots,
                windGustKnots: sample.windGustKnots,
                temperatureCelsius: sample.temperatureCelsius,
                dewPointCelsius: sample.dewPointCelsius,
                weatherCode: sample.weatherCode,
                visibilityMeters: sample.visibilityMeters,
                lowCloudCoverPercent: sample.lowCloudCoverPercent,
                totalCloudCoverPercent: sample.totalCloudCoverPercent,
                lowestCloudBaseFeetAGL: ceiling,
                ceilingFeetAGL: ceiling,
                ceilingSource: resolved.source,
                category: flightCategory(
                    visibilityMeters: sample.visibilityMeters,
                    ceilingFeet: ceiling
                ),
                pressureMSLHPA: sample.pressureMSLHPA
            )
        }
        return EDFZForecast(
            retrievedAt: forecast.retrievedAt,
            samples: samples,
            source: forecast.source
        )
    }

    private func cacheLifetime(for forecast: EDFZForecast) -> TimeInterval {
        forecast.source.isICONSeamless
            ? primaryCacheLifetime
            : backupRetryLifetime
    }

    private func loadForecastDiskCacheIfNeeded() {
        guard !didLoadForecastDiskCache else { return }
        didLoadForecastDiskCache = true
        guard let data = try? Data(contentsOf: forecastDiskCacheURL()),
              let saved = try? JSONDecoder().decode(
                  [String: EDFZForecast].self,
                  from: data
              )
        else { return }
        let oldestUsefulDate = Date().addingTimeInterval(
            -staleSeamlessFallbackLifetime
        )
        forecastDiskCache = saved.filter {
            $0.value.retrievedAt >= oldestUsefulDate
        }
    }

    private func saveForecastDiskCache() {
        guard let data = try? JSONEncoder().encode(forecastDiskCache) else {
            return
        }
        try? data.write(to: forecastDiskCacheURL(), options: .atomic)
    }

    private func forecastDiskCacheURL() -> URL {
        weatherCacheDirectory().appendingPathComponent("planning-weather.json")
    }

    private func weatherCacheDirectory() -> URL {
        let root = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let directory = root
            .appendingPathComponent("Flybook Europe", isDirectory: true)
            .appendingPathComponent("WeatherCache", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func downloadForecast(
        plannedDate: Date,
        airport: AirportReference,
        forceRefresh: Bool,
        staleSeamlessForecast: EDFZForecast?
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

        let queryItems = [
            URLQueryItem(name: "latitude", value: String(airport.latitude)),
            URLQueryItem(name: "longitude", value: String(airport.longitude)),
            URLQueryItem(
                name: "timezone",
                value: airport.timeZone.identifier
            ),
            URLQueryItem(name: "start_date", value: startDay),
            URLQueryItem(name: "end_date", value: endDay),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(
                name: "hourly",
                value: "wind_speed_10m,wind_direction_10m,wind_gusts_10m,temperature_2m,dew_point_2m,weather_code,visibility,cloud_cover,cloud_cover_low,pressure_msl"
            )
        ]

        for route in ICONSeamlessAccessRoute.allCases {
            do {
                return try await downloadICONForecast(
                    route: route,
                    queryItems: queryItems,
                    airport: airport
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Der zweite Open-Meteo-Zugangsweg wird nur versucht, wenn
                // der vorrangige DWD-ICON-Endpunkt keine nutzbaren
                // Seamless-Daten liefert. Erst danach folgt ein Fremdmodell.
                continue
            }
        }

        if let staleSeamlessForecast,
           staleSeamlessForecast.source.isICONSeamless,
           Date().timeIntervalSince(staleSeamlessForecast.retrievedAt)
                < staleSeamlessFallbackLifetime {
            return staleSeamlessForecast
        }

        do {
            var components = URLComponents(
                string: "https://api.open-meteo.com/v1/forecast"
            )
            components?.queryItems = queryItems
            guard let url = components?.url else {
                throw EDFZWeatherError.invalidURL
            }
            return try await downloadOpenMeteoForecast(
                url: url,
                source: .bestMatch,
                airport: airport
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Best Match darf erst nach allen Seamless-Reserven zum Zug
            // kommen. MET Norway bleibt der letzte, fremde Provider.
        }

        do {
            return try await metNorwayForecast(
                airport: airport,
                forceRefresh: forceRefresh
            )
        } catch {
            return try await DWDMOSMIXService.shared.forecast(airport: airport)
        }
    }

    private func downloadICONForecast(
        route: ICONSeamlessAccessRoute,
        queryItems: [URLQueryItem],
        airport: AirportReference
    ) async throws -> EDFZForecast {
        guard let url = route.url(queryItems: queryItems) else {
            throw EDFZWeatherError.invalidURL
        }
        return try await downloadOpenMeteoForecast(
            url: url,
            source: .iconSeamless(route),
            airport: airport
        )
    }

    private func downloadOpenMeteoForecast(
        url: URL,
        source: EDFZForecastSource,
        airport: AirportReference
    ) async throws -> EDFZForecast {
        let (data, response) = try await FlightNetwork.openMeteoData(
            from: url,
            priority: .high
        )
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { throw EDFZWeatherError.serverError }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = airport.timeZone
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
            return EDFZWeatherSample(
                validTime: time,
                windDirectionDegrees: value(decoded.hourly.windDirection10m, index),
                windSpeedKnots: value(decoded.hourly.windSpeed10m, index),
                windGustKnots: value(decoded.hourly.windGusts10m, index),
                temperatureCelsius: value(
                    decoded.hourly.temperature2m, index
                ),
                dewPointCelsius: value(
                    decoded.hourly.dewPoint2m, index
                ),
                weatherCode: decoded.hourly.weatherCode.indices.contains(index)
                    ? decoded.hourly.weatherCode[index]
                    : nil,
                visibilityMeters: visibility,
                lowCloudCoverPercent: lowCloudCover,
                totalCloudCoverPercent: value(
                    decoded.hourly.cloudCover, index
                ),
                lowestCloudBaseFeetAGL: nil,
                ceilingFeetAGL: nil,
                category: flightCategory(
                    visibilityMeters: visibility,
                    ceilingFeet: nil
                ),
                pressureMSLHPA: value(decoded.hourly.pressureMSL, index)
            )
        }
        guard samples.contains(where: { sample in
            sample.windSpeedKnots != nil
                || sample.temperatureCelsius != nil
                || sample.visibilityMeters != nil
                || sample.lowCloudCoverPercent != nil
        }) else {
            throw EDFZWeatherError.noForecast
        }
        let result = EDFZForecast(
            retrievedAt: Date(),
            samples: samples,
            source: source
        )
        return result
    }

    func metNorwayForecast(
        airport: AirportReference,
        forceRefresh: Bool = false
    ) async throws -> EDFZForecast {
        loadMetNorwayDiskCacheIfNeeded()
        if !forceRefresh,
           let cached = metNorwayCache[airport.icao],
           Date().timeIntervalSince(cached.0) < primaryCacheLifetime {
            return cached.1
        }
        if !forceRefresh,
           let cached = metNorwayDiskCache[airport.icao],
           cached.expiresAt > Date(),
           let forecast = try? decodeMetNorwayForecast(
               data: cached.data,
               retrievedAt: cached.retrievedAt
           ) {
            metNorwayCache[airport.icao] = (cached.retrievedAt, forecast)
            return forecast
        }
        if let running = metNorwayTasks[airport.icao] {
            return try await running.value
        }
        let task = Task {
            try await self.downloadMetNorwayForecast(airport: airport)
        }
        metNorwayTasks[airport.icao] = task
        do {
            let result = try await task.value
            metNorwayTasks[airport.icao] = nil
            metNorwayCache[airport.icao] = (Date(), result)
            return result
        } catch {
            metNorwayTasks[airport.icao] = nil
            throw error
        }
    }

    private func downloadMetNorwayForecast(
        airport: AirportReference
    ) async throws -> EDFZForecast {
        var components = URLComponents(
            string: "https://api.met.no/weatherapi/locationforecast/2.0/compact"
        )
        components?.queryItems = [
            URLQueryItem(
                name: "lat",
                value: String(format: "%.4f", airport.latitude)
            ),
            URLQueryItem(
                name: "lon",
                value: String(format: "%.4f", airport.longitude)
            )
        ]
        guard let url = components?.url else {
            throw EDFZWeatherError.invalidURL
        }
        let previous = metNorwayDiskCache[airport.icao]
        let data = try await FlightNetwork.metNorwayData(
            from: url,
            priority: .high
        )
        let now = Date()
        let entry = MetNorwayDiskEntry(
            data: data,
            retrievedAt: previous?.data == data
                ? previous?.retrievedAt ?? now
                : now,
            expiresAt: now.addingTimeInterval(primaryCacheLifetime),
            lastModified: previous?.lastModified
        )
        metNorwayDiskCache[airport.icao] = entry
        saveMetNorwayDiskCache()

        return try decodeMetNorwayForecast(
            data: data,
            retrievedAt: entry.retrievedAt
        )
    }

    private func decodeMetNorwayForecast(
        data: Data,
        retrievedAt: Date
    ) throws -> EDFZForecast {
        let decoded = try JSONDecoder().decode(
            MetNorwayResponse.self,
            from: data
        )
        let parser = ISO8601DateFormatter()
        let samples = decoded.properties.timeseries.compactMap {
            entry -> EDFZWeatherSample? in
            guard let time = parser.date(from: entry.time) else { return nil }
            let details = entry.data.instant.details
            // MET Norway provides hourly symbols only for the near term. Later
            // forecast entries use six- or twelve-hour summaries instead.
            let symbol = entry.data.next1Hours?.summary.symbolCode
                ?? entry.data.next6Hours?.summary.symbolCode
                ?? entry.data.next12Hours?.summary.symbolCode
                ?? ""
            let lowCloud = details.cloudAreaFractionLow
                ?? details.cloudAreaFraction
            let dewPoint = details.airTemperature.flatMap { temperature in
                details.relativeHumidity.map {
                    temperature - max(0, 100 - $0) / 5
                }
            }
            let visibility = estimatedVisibilityMeters(symbol: symbol)
            return EDFZWeatherSample(
                validTime: time,
                windDirectionDegrees: details.windFromDirection,
                windSpeedKnots: details.windSpeed.map { $0 * 1.943_844 },
                windGustKnots: details.windSpeedOfGust.map { $0 * 1.943_844 },
                temperatureCelsius: details.airTemperature,
                dewPointCelsius: dewPoint,
                weatherCode: weatherCode(symbol: symbol),
                visibilityMeters: visibility,
                lowCloudCoverPercent: lowCloud,
                totalCloudCoverPercent: details.cloudAreaFraction,
                lowestCloudBaseFeetAGL: nil,
                ceilingFeetAGL: nil,
                category: flightCategory(
                    visibilityMeters: visibility,
                    ceilingFeet: nil
                ),
                pressureMSLHPA: details.airPressureAtSeaLevel
            )
        }
        guard !samples.isEmpty else { throw EDFZWeatherError.serverError }
        return EDFZForecast(
            retrievedAt: retrievedAt,
            samples: samples,
            source: .metNorway
        )
    }

    private func loadMetNorwayDiskCacheIfNeeded() {
        guard !didLoadMetNorwayDiskCache else { return }
        didLoadMetNorwayDiskCache = true
        guard let data = try? Data(contentsOf: metNorwayDiskCacheURL()),
              let saved = try? JSONDecoder().decode(
                  [String: MetNorwayDiskEntry].self,
                  from: data
              )
        else { return }
        let oldestUsefulDate = Date().addingTimeInterval(-24 * 60 * 60)
        metNorwayDiskCache = saved.filter {
            $0.value.expiresAt >= oldestUsefulDate
        }
    }

    private func saveMetNorwayDiskCache() {
        guard let data = try? JSONEncoder().encode(metNorwayDiskCache) else {
            return
        }
        try? data.write(to: metNorwayDiskCacheURL(), options: .atomic)
    }

    private func metNorwayDiskCacheURL() -> URL {
        weatherCacheDirectory().appendingPathComponent("met-norway.json")
    }


    private func estimatedVisibilityMeters(symbol: String) -> Double {
        if symbol.contains("fog") { return 1_000 }
        if symbol.contains("heavyrain") || symbol.contains("heavysnow") {
            return 4_000
        }
        if symbol.contains("rain") || symbol.contains("snow") {
            return 7_000
        }
        return 10_000
    }

    private func weatherCode(symbol: String) -> Int? {
        if symbol.contains("thunder") { return 95 }
        if symbol.contains("snow") { return 71 }
        if symbol.contains("sleet") { return 67 }
        if symbol.contains("rain") { return 61 }
        if symbol.contains("fog") { return 45 }
        if symbol.contains("partlycloudy") { return 2 }
        if symbol.contains("cloudy") { return 3 }
        if symbol.contains("fair") { return 1 }
        if symbol.contains("clearsky") { return 0 }
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

private struct MetNorwayResponse: Decodable {
    let properties: Properties

    struct Properties: Decodable {
        let timeseries: [TimeSeries]
    }

    struct TimeSeries: Decodable {
        let time: String
        let data: WeatherData
    }

    struct WeatherData: Decodable {
        let instant: Instant
        let next1Hours: NextHours?
        let next6Hours: NextHours?
        let next12Hours: NextHours?

        enum CodingKeys: String, CodingKey {
            case instant
            case next1Hours = "next_1_hours"
            case next6Hours = "next_6_hours"
            case next12Hours = "next_12_hours"
        }
    }

    struct Instant: Decodable {
        let details: Details
    }

    struct Details: Decodable {
        let airPressureAtSeaLevel: Double?
        let airTemperature: Double?
        let cloudAreaFraction: Double?
        let cloudAreaFractionLow: Double?
        let relativeHumidity: Double?
        let windFromDirection: Double?
        let windSpeed: Double?
        let windSpeedOfGust: Double?

        enum CodingKeys: String, CodingKey {
            case airPressureAtSeaLevel = "air_pressure_at_sea_level"
            case airTemperature = "air_temperature"
            case cloudAreaFraction = "cloud_area_fraction"
            case cloudAreaFractionLow = "cloud_area_fraction_low"
            case relativeHumidity = "relative_humidity"
            case windFromDirection = "wind_from_direction"
            case windSpeed = "wind_speed"
            case windSpeedOfGust = "wind_speed_of_gust"
        }
    }

    struct NextHours: Decodable {
        let summary: Summary
    }

    struct Summary: Decodable {
        let symbolCode: String

        enum CodingKeys: String, CodingKey {
            case symbolCode = "symbol_code"
        }
    }
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
    let cloudCover: [Double?]
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
        case cloudCover = "cloud_cover"
        case cloudCoverLow = "cloud_cover_low"
        case pressureMSL = "pressure_msl"
    }
}

enum EDFZWeatherError: LocalizedError {
    case invalidURL
    case serverError
    case noForecast

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Ungültige Wetteradresse."
        case .serverError: return "EDFZ-Wetterdaten sind nicht verfügbar."
        case .noForecast: return "Keine nutzbaren Wetterdaten verfügbar."
        }
    }
}
