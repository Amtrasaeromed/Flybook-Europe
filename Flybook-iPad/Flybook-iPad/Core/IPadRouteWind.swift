import Foundation

struct IPadRouteWind: Hashable {
    let headwindKnots: Double
    let directionDegrees: Double
    let speedKnots: Double
    let source: String
}

@MainActor
final class IPadRouteWindViewModel: ObservableObject {
    @Published private(set) var wind: IPadRouteWind?

    func load(
        origin: Airport,
        destination: Airport,
        start: Date,
        end: Date,
        altitudeFeet: Int
    ) async {
        wind = try? await IPadRouteWindService.shared.wind(
            origin: origin,
            destination: destination,
            start: start,
            end: end,
            altitudeFeet: altitudeFeet
        )
    }
}

actor IPadRouteWindService {
    static let shared = IPadRouteWindService()
    private var cache: [String: (Date, IPadRouteWind)] = [:]

    func wind(
        origin: Airport,
        destination: Airport,
        start: Date,
        end: Date,
        altitudeFeet: Int
    ) async throws -> IPadRouteWind {
        let key = "\(origin.icao)-\(destination.icao)-\(Int(start.timeIntervalSince1970 / 1800))-\(altitudeFeet)"
        if let cached = cache[key], Date().timeIntervalSince(cached.0) < 30 * 60 {
            return cached.1
        }
        let fractions = [0.25, 0.5, 0.75]
        let duration = end.timeIntervalSince(start)
        let points = fractions.map { fraction in
            let coordinate = geographicPoint(from: origin, to: destination, fraction: fraction)
            return (coordinate, start.addingTimeInterval(duration * fraction))
        }
        let prefersD2 = points.allSatisfy { $0.1 <= Date().addingTimeInterval(48 * 60 * 60) }
        let models = prefersD2 ? ["icon_d2", "icon_eu"] : ["icon_eu"]
        var lastError: Error = WindError.noData
        for model in models {
            for endpoint in ["dwd-icon", "forecast"] {
                do {
                    let result = try await fetch(
                        points: points,
                        origin: origin,
                        destination: destination,
                        altitudeFeet: altitudeFeet,
                        endpoint: endpoint,
                        model: model
                    )
                    cache[key] = (Date(), result)
                    return result
                } catch {
                    lastError = error
                }
            }
        }
        do {
            let result = try await fetchMetNorway(
                points: points,
                origin: origin,
                destination: destination
            )
            cache[key] = (Date(), result)
            return result
        } catch {
            throw lastError
        }
    }

    private func fetchMetNorway(
        points: [((latitude: Double, longitude: Double), Date)],
        origin: Airport,
        destination: Airport
    ) async throws -> IPadRouteWind {
        var values: [(speed: Double, direction: Double)] = []
        let parser = ISO8601DateFormatter()
        for point in points {
            var components = URLComponents(string: "https://api.met.no/weatherapi/locationforecast/2.0/complete")
            components?.queryItems = [
                URLQueryItem(name: "lat", value: String(point.0.latitude)),
                URLQueryItem(name: "lon", value: String(point.0.longitude))
            ]
            guard let url = components?.url else { continue }
            var request = URLRequest(url: url)
            request.setValue("Flybook/1.0 flight-planning-weather-client", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await FlightNetwork.data(for: request, priority: .normal)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
            let decoded = try JSONDecoder().decode(MetResponse.self, from: data)
            guard let nearest = decoded.properties.timeseries.min(by: {
                abs((parser.date(from: $0.time) ?? .distantPast).timeIntervalSince(point.1))
                    < abs((parser.date(from: $1.time) ?? .distantPast).timeIntervalSince(point.1))
            }) else { continue }
            values.append((
                nearest.data.instant.details.windSpeed * 1.943_844,
                nearest.data.instant.details.windFromDirection
            ))
        }
        guard !values.isEmpty else { throw WindError.noData }
        let course = initialBearing(from: origin, to: destination)
        let headwind = values.map {
            $0.speed * cos(($0.direction - course) * .pi / 180)
        }.reduce(0, +) / Double(values.count)
        let east = values.map { -$0.speed * sin($0.direction * .pi / 180) }.reduce(0, +) / Double(values.count)
        let north = values.map { -$0.speed * cos($0.direction * .pi / 180) }.reduce(0, +) / Double(values.count)
        return IPadRouteWind(
            headwindKnots: headwind,
            directionDegrees: (atan2(-east, -north) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360),
            speedKnots: hypot(east, north),
            source: "MET Norway 10 m · Fallback"
        )
    }

    private func fetch(
        points: [((latitude: Double, longitude: Double), Date)],
        origin: Airport,
        destination: Airport,
        altitudeFeet: Int,
        endpoint: String,
        model: String
    ) async throws -> IPadRouteWind {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        var components = URLComponents(string: "https://api.open-meteo.com/v1/\(endpoint)")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: points.map { String($0.0.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: points.map { String($0.0.longitude) }.joined(separator: ",")),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(name: "start_date", value: formatter.string(from: points.map(\.1).min() ?? .now)),
            URLQueryItem(name: "end_date", value: formatter.string(from: points.map(\.1).max() ?? .now)),
            URLQueryItem(name: "models", value: model),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(name: "hourly", value: [
                "wind_speed_925hPa", "wind_direction_925hPa",
                "wind_speed_850hPa", "wind_direction_850hPa",
                "wind_speed_700hPa", "wind_direction_700hPa"
            ].joined(separator: ","))
        ]
        guard let url = components?.url else { throw WindError.noData }
        let (data, response) = try await FlightNetwork.data(from: url, priority: .normal)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WindError.noData
        }
        let decoder = JSONDecoder()
        let responses: [Response]
        if let values = try? decoder.decode([Response].self, from: data) {
            responses = values
        } else {
            responses = [try decoder.decode(Response.self, from: data)]
        }
        guard responses.count == points.count else { throw WindError.noData }
        var componentsVector: [(east: Double, north: Double, headwind: Double)] = []
        let course = initialBearing(from: origin, to: destination)
        for (response, point) in zip(responses, points) {
            guard let sample = response.sample(nearestTo: point.1, altitudeFeet: altitudeFeet) else { continue }
            let radians = sample.direction * .pi / 180
            let east = -sample.speed * sin(radians)
            let north = -sample.speed * cos(radians)
            let headwind = sample.speed * cos((sample.direction - course) * .pi / 180)
            componentsVector.append((east, north, headwind))
        }
        guard !componentsVector.isEmpty else { throw WindError.noData }
        let east = componentsVector.map(\.east).reduce(0, +) / Double(componentsVector.count)
        let north = componentsVector.map(\.north).reduce(0, +) / Double(componentsVector.count)
        let speed = hypot(east, north)
        let direction = (atan2(-east, -north) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let headwind = componentsVector.map(\.headwind).reduce(0, +) / Double(componentsVector.count)
        return IPadRouteWind(
            headwindKnots: headwind,
            directionDegrees: direction,
            speedKnots: speed,
            source: model == "icon_d2" ? "ICON-D2" : "ICON-EU"
        )
    }

    private func geographicPoint(from origin: Airport, to destination: Airport, fraction: Double) -> (latitude: Double, longitude: Double) {
        let lat1 = origin.latitude * .pi / 180, lon1 = origin.longitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180, lon2 = destination.longitude * .pi / 180
        let angular = 2 * asin(sqrt(pow(sin((lat2 - lat1) / 2), 2) + cos(lat1) * cos(lat2) * pow(sin((lon2 - lon1) / 2), 2)))
        guard angular > 0.000_001 else { return (origin.latitude, origin.longitude) }
        let a = sin((1 - fraction) * angular) / sin(angular), b = sin(fraction * angular) / sin(angular)
        let x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2)
        let y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2)
        let z = a * sin(lat1) + b * sin(lat2)
        return (atan2(z, sqrt(x * x + y * y)) * 180 / .pi, atan2(y, x) * 180 / .pi)
    }

    private func initialBearing(from origin: Airport, to destination: Airport) -> Double {
        let lat1 = origin.latitude * .pi / 180, lat2 = destination.latitude * .pi / 180
        let delta = (destination.longitude - origin.longitude) * .pi / 180
        return (atan2(sin(delta) * cos(lat2), cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(delta)) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private enum WindError: Error { case noData }

    private struct Response: Decodable {
        let hourly: Hourly
        func sample(nearestTo date: Date, altitudeFeet: Int) -> (speed: Double, direction: Double)? {
            let parser = DateFormatter()
            parser.calendar = Calendar(identifier: .gregorian)
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = TimeZone(secondsFromGMT: 0)
            parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
            guard let index = hourly.time.indices.min(by: {
                abs((parser.date(from: hourly.time[$0]) ?? .distantPast).timeIntervalSince(date))
                    < abs((parser.date(from: hourly.time[$1]) ?? .distantPast).timeIntervalSince(date))
            }) else { return nil }
            if altitudeFeet <= 4_000 { return pair(hourly.speed925, hourly.direction925, index) }
            if altitudeFeet <= 8_000 { return pair(hourly.speed850, hourly.direction850, index) }
            return pair(hourly.speed700, hourly.direction700, index)
        }
        private func pair(_ speeds: [Double?], _ directions: [Double?], _ index: Int) -> (Double, Double)? {
            guard speeds.indices.contains(index), directions.indices.contains(index),
                  let speed = speeds[index], let direction = directions[index] else { return nil }
            return (speed, direction)
        }
    }

    private struct Hourly: Decodable {
        let time: [String]
        let speed925: [Double?], direction925: [Double?]
        let speed850: [Double?], direction850: [Double?]
        let speed700: [Double?], direction700: [Double?]
        enum CodingKeys: String, CodingKey {
            case time
            case speed925 = "wind_speed_925hPa", direction925 = "wind_direction_925hPa"
            case speed850 = "wind_speed_850hPa", direction850 = "wind_direction_850hPa"
            case speed700 = "wind_speed_700hPa", direction700 = "wind_direction_700hPa"
        }
    }

    private struct MetResponse: Decodable {
        let properties: Properties
        struct Properties: Decodable { let timeseries: [TimeSeries] }
        struct TimeSeries: Decodable { let time: String; let data: WeatherData }
        struct WeatherData: Decodable { let instant: Instant }
        struct Instant: Decodable { let details: Details }
        struct Details: Decodable {
            let windSpeed: Double
            let windFromDirection: Double
            enum CodingKeys: String, CodingKey {
                case windSpeed = "wind_speed"
                case windFromDirection = "wind_from_direction"
            }
        }
    }
}
