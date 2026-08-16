import Compression
import Foundation

/// Kostenlose, direkt vom DWD geladene Punktprognose. MOSMIX wird nur als
/// letzte Reserve verwendet; deshalb genuegen kleine Einzelstationsdateien
/// statt des mehr als 80 MB grossen Gesamtarchivs.
actor DWDMOSMIXService {
    static let shared = DWDMOSMIXService()

    private struct Station {
        let id: String
        let icao: String?
        let latitude: Double
        let longitude: Double
    }

    private struct CachedFile: Codable {
        let retrievedAt: Date
        let data: Data
    }

    private let forecastLifetime: TimeInterval = 6 * 60 * 60
    private let catalogLifetime: TimeInterval = 30 * 24 * 60 * 60
    private var files: [String: CachedFile] = [:]
    private var didLoadFiles = false
    private var stations: [Station]?
    private var stationCatalogTask: Task<Data, Error>?

    func forecast(airport: AirportReference) async throws -> EDFZForecast {
        loadFilesIfNeeded()
        let stationList = try await loadStations()
        guard let station = Self.nearestStation(
            to: airport,
            in: stationList
        ) else { throw MOSMIXError.noNearbyStation }

        let key = "forecast-\(station.id)"
        let archive: Data
        let retrievedAt: Date
        if let cached = files[key],
           Date().timeIntervalSince(cached.retrievedAt) < forecastLifetime {
            archive = cached.data
            retrievedAt = cached.retrievedAt
        } else {
            guard let url = URL(string:
                "https://opendata.dwd.de/weather/local_forecasts/mos/"
                + "MOSMIX_L/single_stations/\(station.id)/kml/"
                + "MOSMIX_L_LATEST_\(station.id).kmz"
            ) else { throw MOSMIXError.invalidData }
            let (data, response) = try await FlightNetwork.data(
                from: url,
                priority: .low
            )
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode)
            else { throw MOSMIXError.serverError }
            archive = data
            retrievedAt = Date()
            files[key] = CachedFile(retrievedAt: retrievedAt, data: data)
            saveFiles()
        }

        let kml = try Self.firstFile(inKMZ: archive)
        return try Self.parseKML(kml, retrievedAt: retrievedAt)
    }

    private func loadStations() async throws -> [Station] {
        if let stations { return stations }
        let key = "station-catalog"
        let catalog: Data
        if let cached = files[key],
           Date().timeIntervalSince(cached.retrievedAt) < catalogLifetime {
            catalog = cached.data
        } else if let task = stationCatalogTask {
            catalog = try await task.value
        } else {
            let task = Task { try await Self.downloadStationCatalog() }
            stationCatalogTask = task
            do {
                catalog = try await task.value
                stationCatalogTask = nil
                files[key] = CachedFile(retrievedAt: Date(), data: catalog)
                saveFiles()
            } catch {
                stationCatalogTask = nil
                throw error
            }
        }
        let parsed = Self.parseStationCatalog(catalog)
        guard !parsed.isEmpty else { throw MOSMIXError.invalidData }
        stations = parsed
        return parsed
    }

    private static func downloadStationCatalog() async throws -> Data {
        var components = URLComponents(string:
            "https://www.dwd.de/DE/leistungen/met_verfahren_mosmix/"
            + "mosmix_stationskatalog.cfg"
        )
        components?.queryItems = [
            URLQueryItem(name: "view", value: "nasPublication"),
            URLQueryItem(name: "nn", value: "16102")
        ]
        guard let url = components?.url else {
            throw MOSMIXError.invalidData
        }
        var request = URLRequest(url: url)
        request.setValue(FlightNetwork.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await FlightNetwork.data(
            for: request,
            priority: .low
        )
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { throw MOSMIXError.serverError }
        return data
    }

    private static func parseStationCatalog(_ data: Data) -> [Station] {
        guard let text = String(data: data, encoding: .isoLatin1)
                ?? String(data: data, encoding: .utf8)
        else { return [] }
        return text.split(whereSeparator: \Character.isNewline).compactMap {
            line -> Station? in
            let fields = line.split(whereSeparator: \Character.isWhitespace)
            guard fields.count >= 6,
                  let latitude = Double(fields[fields.count - 3]),
                  let longitude = Double(fields[fields.count - 2])
            else { return nil }
            let rawICAO = String(fields[1])
            return Station(
                id: String(fields[0]),
                icao: rawICAO == "----" ? nil : rawICAO,
                latitude: latitude,
                longitude: longitude
            )
        }
    }

    private static func nearestStation(
        to airport: AirportReference,
        in stations: [Station]
    ) -> Station? {
        if let exact = stations.first(where: {
            $0.icao?.caseInsensitiveCompare(airport.icao) == .orderedSame
        }) { return exact }
        guard let nearest = stations.min(by: {
            distanceNM(from: airport, to: $0)
                < distanceNM(from: airport, to: $1)
        }), distanceNM(from: airport, to: nearest) <= 75
        else { return nil }
        return nearest
    }

    private static func distanceNM(
        from airport: AirportReference,
        to station: Station
    ) -> Double {
        let lat1 = airport.latitude * .pi / 180
        let lat2 = station.latitude * .pi / 180
        let dLat = (station.latitude - airport.latitude) * .pi / 180
        let dLon = (station.longitude - airport.longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * 3440.065 * atan2(sqrt(a), sqrt(1 - a))
    }

    static func firstFile(inKMZ archive: Data) throws -> Data {
        guard archive.count >= 22,
              let end = (0...(archive.count - 4)).reversed().first(where: {
                  uint32(archive, at: $0) == 0x0605_4b50
              })
        else { throw MOSMIXError.invalidData }
        let central = Int(uint32(archive, at: end + 16))
        guard central + 46 <= archive.count,
              uint32(archive, at: central) == 0x0201_4b50
        else { throw MOSMIXError.invalidData }
        let method = uint16(archive, at: central + 10)
        let compressedSize = Int(uint32(archive, at: central + 20))
        let uncompressedSize = Int(uint32(archive, at: central + 24))
        let local = Int(uint32(archive, at: central + 42))
        guard local + 30 <= archive.count,
              uint32(archive, at: local) == 0x0403_4b50
        else { throw MOSMIXError.invalidData }
        let payloadStart = local + 30
            + Int(uint16(archive, at: local + 26))
            + Int(uint16(archive, at: local + 28))
        guard compressedSize > 0, uncompressedSize > 0,
              payloadStart + compressedSize <= archive.count
        else { throw MOSMIXError.invalidData }
        if method == 0 {
            return archive.subdata(
                in: payloadStart..<(payloadStart + compressedSize)
            )
        }
        guard method == 8 else { throw MOSMIXError.invalidData }
        var result = Data(count: uncompressedSize)
        let decoded = result.withUnsafeMutableBytes { destination in
            archive.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!,
                    uncompressedSize,
                    source.bindMemory(to: UInt8.self).baseAddress! + payloadStart,
                    compressedSize,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decoded == uncompressedSize else {
            throw MOSMIXError.invalidData
        }
        return result
    }

    static func parseKML(
        _ data: Data,
        retrievedAt: Date
    ) throws -> EDFZForecast {
        let delegate = MOSMIXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), !delegate.timeSteps.isEmpty else {
            throw MOSMIXError.invalidData
        }
        let values = delegate.values
        let samples = delegate.timeSteps.indices.map { index in
            let temperature = value(values["TTT"], index).map { $0 - 273.15 }
            let dewPoint = value(values["Td"], index).map { $0 - 273.15 }
            let lowCloud = value(values["Nl"], index)
            let cloudBase: Double?
            if let temperature, let dewPoint {
                cloudBase = max(0, temperature - dewPoint) * 400
            } else {
                cloudBase = nil
            }
            let ceiling = lowCloud.flatMap { cover in
                cover >= 62.5 ? cloudBase : nil
            }
            let visibility = value(values["VV"], index)
            return EDFZWeatherSample(
                validTime: delegate.timeSteps[index],
                windDirectionDegrees: value(values["DD"], index),
                windSpeedKnots: value(values["FF"], index).map { $0 * 1.943_844 },
                windGustKnots: value(values["FX1"], index).map { $0 * 1.943_844 },
                temperatureCelsius: temperature,
                dewPointCelsius: dewPoint,
                weatherCode: value(values["ww"], index).map { Int($0.rounded()) },
                visibilityMeters: visibility,
                lowCloudCoverPercent: lowCloud,
                totalCloudCoverPercent: value(values["N"], index),
                lowestCloudBaseFeetAGL: cloudBase,
                ceilingFeetAGL: ceiling,
                category: category(visibility: visibility, ceiling: ceiling),
                pressureMSLHPA: value(values["PPPP"], index).map { $0 / 100 }
            )
        }
        return EDFZForecast(
            retrievedAt: retrievedAt,
            samples: samples,
            source: .mosmix
        )
    }

    private static func value(_ values: [Double?]?, _ index: Int) -> Double? {
        guard let values, values.indices.contains(index) else { return nil }
        return values[index]
    }

    private static func category(
        visibility: Double?,
        ceiling: Double?
    ) -> FlightCategory {
        let miles = visibility.map { $0 / 1609.344 }
        if ceiling.map({ $0 < 500 }) == true || miles.map({ $0 < 1 }) == true {
            return .lifr
        }
        if ceiling.map({ $0 < 1000 }) == true || miles.map({ $0 < 3 }) == true {
            return .ifr
        }
        if ceiling.map({ $0 <= 3000 }) == true || miles.map({ $0 <= 5 }) == true {
            return .mvfr
        }
        return ceiling != nil || miles != nil ? .vfr : .unavailable
    }

    private static func uint16(_ data: Data, at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(uint16(data, at: offset))
            | UInt32(uint16(data, at: offset + 2)) << 16
    }

    private func loadFilesIfNeeded() {
        guard !didLoadFiles else { return }
        didLoadFiles = true
        guard let data = try? Data(contentsOf: cacheURL()),
              let saved = try? JSONDecoder().decode(
                  [String: CachedFile].self,
                  from: data
              )
        else { return }
        files = saved
    }

    private func saveFiles() {
        guard let data = try? JSONEncoder().encode(files) else { return }
        try? data.write(to: cacheURL(), options: .atomic)
    }

    private func cacheURL() -> URL {
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
        return directory.appendingPathComponent("dwd-mosmix.json")
    }
}

private final class MOSMIXParserDelegate: NSObject, XMLParserDelegate {
    var timeSteps: [Date] = []
    var values: [String: [Double?]] = [:]
    private var currentElement = ""
    private var currentForecast: String?
    private var text = ""
    private let dateParser: ISO8601DateFormatter = {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser
    }()

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        text = ""
        if elementName.hasSuffix("Forecast") {
            currentForecast = attributeDict["dwd:elementName"]
                ?? attributeDict["elementName"]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName.hasSuffix("TimeStep") {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = dateParser.date(from: value)
                ?? ISO8601DateFormatter().date(from: value) {
                timeSteps.append(date)
            }
        } else if elementName.hasSuffix("value"), let currentForecast {
            values[currentForecast] = text
                .split(whereSeparator: \Character.isWhitespace)
                .map { token in
                    token == "-" ? nil : Double(token)
                }
        } else if elementName.hasSuffix("Forecast") {
            currentForecast = nil
        }
        currentElement = ""
        text = ""
    }
}

enum MOSMIXError: Error {
    case invalidData
    case serverError
    case noNearbyStation
}
