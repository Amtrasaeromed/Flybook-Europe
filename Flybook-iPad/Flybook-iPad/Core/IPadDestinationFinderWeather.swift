import Foundation

enum IPadBlueSkyCoverageScope: String, CaseIterable, Identifiable {
    case perDay = "Pro Tag"
    case entirePeriod = "Gesamter Zeitraum"

    var id: String { rawValue }
}

private struct IPadBlueSkyHour: Sendable {
    let instant: Date
    let totalCloudCoverPercent: Double?
}

@MainActor
final class IPadDestinationFinderWeather: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private var hoursByICAO: [String: [IPadBlueSkyHour]] = [:]

    private var loadedFrom: Date?
    private var loadedUntil: Date?

    func load(airports: [Airport], from: Date, until: Date) async {
        guard until >= from else {
            hoursByICAO = [:]
            errorMessage = "Der Wetterzeitraum ist ungültig."
            return
        }
        if loadedFrom == from,
           loadedUntil == until,
           Set(hoursByICAO.keys) == Set(airports.map(\.icao))
        {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var loaded: [String: [IPadBlueSkyHour]] = [:]
        for start in stride(from: 0, to: airports.count, by: 10) {
            guard !Task.isCancelled else { return }
            let end = min(start + 10, airports.count)
            let batch = Array(airports[start..<end])
            do {
                let forecasts = try await Self.fetch(
                    airports: batch,
                    from: from,
                    until: until
                )
                for (airport, forecast) in zip(batch, forecasts) {
                    loaded[airport.icao] = forecast.hours
                }
            } catch {
                errorMessage = "Wetterdaten konnten nicht vollständig geladen werden."
            }
        }

        guard !Task.isCancelled else { return }
        hoursByICAO = loaded
        loadedFrom = from
        loadedUntil = until
    }

    func matches(
        airport: Airport,
        from: Date,
        until: Date,
        minimumCoverage: Double,
        scope: IPadBlueSkyCoverageScope
    ) -> Bool {
        guard let hours = hoursByICAO[airport.icao], !hours.isEmpty else {
            return false
        }
        let selected = hours.filter {
            $0.instant >= from
                && $0.instant <= until
                && Self.isDaylight($0.instant, at: airport)
        }
        guard !selected.isEmpty else { return false }

        if scope == .entirePeriod {
            return Self.coverage(of: selected) >= minimumCoverage
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: airport.timeZoneIdentifier)
            ?? .current
        let grouped = Dictionary(grouping: selected) {
            calendar.startOfDay(for: $0.instant)
        }
        return !grouped.isEmpty && grouped.values.allSatisfy {
            Self.coverage(of: Array($0)) >= minimumCoverage
        }
    }

    private static func coverage(of hours: [IPadBlueSkyHour]) -> Double {
        let matching = hours.filter {
            guard let cloudCover = $0.totalCloudCoverPercent else {
                return false
            }
            return cloudCover <= 50
        }.count
        return Double(matching) / Double(hours.count)
    }

    private static func fetch(
        airports: [Airport],
        from: Date,
        until: Date
    ) async throws -> [Forecast] {
        var lastError: Error = URLError(.badServerResponse)
        for endpoint in ["dwd-icon", "forecast"] {
            do {
                return try await fetch(
                    airports: airports,
                    from: from,
                    until: until,
                    endpoint: endpoint
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func fetch(
        airports: [Airport],
        from: Date,
        until: Date,
        endpoint: String
    ) async throws -> [Forecast] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"

        var components = URLComponents(
            string: "https://api.open-meteo.com/v1/\(endpoint)"
        )
        components?.queryItems = [
            URLQueryItem(
                name: "latitude",
                value: airports.map { String($0.latitude) }.joined(separator: ",")
            ),
            URLQueryItem(
                name: "longitude",
                value: airports.map { String($0.longitude) }.joined(separator: ",")
            ),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: formatter.string(from: from)),
            URLQueryItem(name: "end_date", value: formatter.string(from: until)),
            URLQueryItem(name: "hourly", value: "cloud_cover"),
            URLQueryItem(name: "models", value: "icon_seamless")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        let (data, response) = try await FlightNetwork.openMeteoData(
            from: url,
            priority: .low
        )
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { throw URLError(.badServerResponse) }

        let decoded: [Response]
        if airports.count == 1 {
            decoded = [try JSONDecoder().decode(Response.self, from: data)]
        } else {
            decoded = try JSONDecoder().decode([Response].self, from: data)
        }
        guard decoded.count == airports.count else {
            throw URLError(.cannotParseResponse)
        }
        return decoded.map(Forecast.init)
    }

    private static func isDaylight(_ instant: Date, at airport: Airport) -> Bool {
        guard let bounds = daylightBounds(
            for: instant,
            latitude: airport.latitude,
            longitude: airport.longitude,
            timeZone: TimeZone(identifier: airport.timeZoneIdentifier) ?? .current
        ) else { return false }
        return instant >= bounds.sunrise && instant <= bounds.sunset
    }

    private static func daylightBounds(
        for instant: Date,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone
    ) -> (sunrise: Date, sunset: Date)? {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone
        let parts = localCalendar.dateComponents([.year, .month, .day], from: instant)
        guard let year = parts.year,
              let month = parts.month,
              let day = parts.day
        else { return nil }

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let midnight = utcCalendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day
        )) else { return nil }
        let dayOfYear = localCalendar.ordinality(of: .day, in: .year, for: instant) ?? 1
        guard let sunrise = eventMinutesUTC(
            dayOfYear: dayOfYear,
            latitude: latitude,
            longitude: longitude,
            sunrise: true
        ),
        let sunset = eventMinutesUTC(
            dayOfYear: dayOfYear,
            latitude: latitude,
            longitude: longitude,
            sunrise: false
        ) else { return nil }
        return (
            midnight.addingTimeInterval(sunrise * 60),
            midnight.addingTimeInterval(sunset * 60)
        )
    }

    private static func eventMinutesUTC(
        dayOfYear: Int,
        latitude: Double,
        longitude: Double,
        sunrise: Bool
    ) -> Double? {
        let gamma = 2 * Double.pi / 365 * (Double(dayOfYear) - 1)
        let equationOfTime = 229.18 * (
            0.000075
                + 0.001868 * cos(gamma)
                - 0.032077 * sin(gamma)
                - 0.014615 * cos(2 * gamma)
                - 0.040849 * sin(2 * gamma)
        )
        let declination = 0.006918
            - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma)
            + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma)
            + 0.00148 * sin(3 * gamma)
        let latitudeRadians = latitude * .pi / 180
        let zenithRadians = 90.833 * .pi / 180
        let cosineHourAngle = cos(zenithRadians)
            / (cos(latitudeRadians) * cos(declination))
            - tan(latitudeRadians) * tan(declination)
        guard (-1.0...1.0).contains(cosineHourAngle) else { return nil }
        let hourAngle = acos(cosineHourAngle) * 180 / .pi
        let solarNoon = 720 - 4 * longitude - equationOfTime
        return sunrise ? solarNoon - 4 * hourAngle : solarNoon + 4 * hourAngle
    }

    private struct Forecast {
        let hours: [IPadBlueSkyHour]

        init(_ response: Response) {
            let timeZone = TimeZone(identifier: response.timezone) ?? .current
            let parser = DateFormatter()
            parser.calendar = Calendar(identifier: .gregorian)
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = timeZone
            parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
            hours = response.hourly.time.indices.compactMap { index in
                guard let instant = parser.date(from: response.hourly.time[index])
                else { return nil }
                let cloudCover = response.hourly.cloudCover.indices.contains(index)
                    ? response.hourly.cloudCover[index]
                    : nil
                return IPadBlueSkyHour(
                    instant: instant,
                    totalCloudCoverPercent: cloudCover
                )
            }
        }
    }

    private struct Response: Decodable {
        let timezone: String
        let hourly: Hourly

        struct Hourly: Decodable {
            let time: [String]
            let cloudCover: [Double?]

            enum CodingKeys: String, CodingKey {
                case time
                case cloudCover = "cloud_cover"
            }
        }
    }
}
