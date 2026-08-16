import Foundation

enum PlanningCeilingSource: String, Codable, Hashable {
    case dwdICOND2 = "DWD ICON-D2"
    case dwdICONEU = "DWD ICON-EU"
    case unavailable = "Keine direkte Ceiling"
}

struct DWDICONCeilingValue: Equatable {
    let feetAGL: Double
    let source: PlanningCeilingSource
}

actor DWDICONCeilingService {
    static let shared = DWDICONCeilingService()

    enum Model: String, CaseIterable {
        case iconD2
        case iconEU

        var source: PlanningCeilingSource {
            switch self {
            case .iconD2: return .dwdICOND2
            case .iconEU: return .dwdICONEU
            }
        }

        var maximumForecastHour: Int {
            switch self {
            case .iconD2: return 48
            case .iconEU: return 120
            }
        }

        var publicationDelay: TimeInterval {
            switch self {
            case .iconD2: return 2 * 60 * 60
            case .iconEU: return 3 * 60 * 60
            }
        }

        func normalizedForecastHour(_ hour: Int) -> Int {
            guard self == .iconEU, hour > 78 else { return hour }
            return Int((Double(hour) / 3).rounded()) * 3
        }

        func covers(latitude: Double, longitude: Double) -> Bool {
            switch self {
            case .iconD2:
                return (43...58.5).contains(latitude)
                    && (-4...21).contains(longitude)
            case .iconEU:
                return (29.5...70.5).contains(latitude)
                    && (-23.5...62.5).contains(longitude)
            }
        }
    }

    struct Candidate: Equatable {
        let model: Model
        let runDate: Date
        let cycle: Int
        let stamp: String
        let forecastHour: Int

        var url: URL? {
            let cycleText = String(format: "%02d", cycle)
            let forecastText = String(format: "%03d", forecastHour)
            let fileName: String
            let modelDirectory: String
            switch model {
            case .iconD2:
                modelDirectory = "icon-d2"
                fileName = "icon-d2_germany_regular-lat-lon_single-level_"
                    + "\(stamp)\(cycleText)_\(forecastText)_2d_ceiling.grib2.bz2"
            case .iconEU:
                modelDirectory = "icon-eu"
                fileName = "icon-eu_europe_regular-lat-lon_single-level_"
                    + "\(stamp)\(cycleText)_\(forecastText)_CEILING.grib2.bz2"
            }
            return URL(string:
                "https://opendata.dwd.de/weather/nwp/\(modelDirectory)/grib/"
                    + "\(cycleText)/ceiling/\(fileName)"
            )
        }
    }

#if os(macOS)
    private var gribCache: [URL: Data] = [:]
    private var gribCacheOrder: [URL] = []
    private let maximumCachedFiles = 12
#endif

    func ceiling(
        latitude: Double,
        longitude: Double,
        validTime: Date,
        now: Date = Date()
    ) async -> DWDICONCeilingValue? {
#if os(macOS)
        guard let executable = gribGetExecutable() else { return nil }
        for candidate in Self.candidates(validTime: validTime, now: now) {
            guard candidate.model.covers(
                latitude: latitude,
                longitude: longitude
            ) else { continue }
            guard let url = candidate.url else { continue }
            do {
                let grib = try await gribData(from: url)
                let metersAGL = try nearestValue(
                    in: grib,
                    latitude: latitude,
                    longitude: longitude,
                    executable: executable
                )
                guard metersAGL.isFinite, metersAGL >= 0 else { continue }
                return DWDICONCeilingValue(
                    feetAGL: metersAGL * 3.280_84,
                    source: candidate.model.source
                )
            } catch {
                continue
            }
        }
        return nil
#else
        // iPadOS kann die komprimierten GRIB2-Dateien ohne gebündelten
        // ecCodes-Decoder nicht sicher auswerten. Es wird deshalb bewusst
        // keine lokale Ceiling-Schätzung als direkter DWD-Wert ausgegeben.
        return nil
#endif
    }

    static func candidates(validTime: Date, now: Date) -> [Candidate] {
        Model.allCases.flatMap { model in
            candidateRuns(model: model, validTime: validTime, now: now)
        }
    }

    private static func candidateRuns(
        model: Model,
        validTime: Date,
        now: Date
    ) -> [Candidate] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let available = now.addingTimeInterval(-model.publicationDelay)
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour],
            from: available
        )
        let latestCycle = ((parts.hour ?? 0) / 3) * 3
        var runParts = parts
        runParts.hour = latestCycle
        runParts.minute = 0
        runParts.second = 0
        guard let latestRun = calendar.date(from: runParts) else { return [] }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"

        return (0..<4).compactMap { offset in
            guard let run = calendar.date(
                byAdding: .hour,
                value: -(offset * 3),
                to: latestRun
            ) else { return nil }
            let rawHour = Int((validTime.timeIntervalSince(run) / 3600).rounded())
            let forecastHour = model.normalizedForecastHour(rawHour)
            guard forecastHour >= 0,
                  forecastHour <= model.maximumForecastHour
            else { return nil }
            return Candidate(
                model: model,
                runDate: run,
                cycle: calendar.component(.hour, from: run),
                stamp: formatter.string(from: run),
                forecastHour: forecastHour
            )
        }
    }

#if os(macOS)
    private func gribData(from url: URL) async throws -> Data {
        if let cached = gribCache[url] { return cached }
        var request = URLRequest(url: url)
        request.setValue("Flybook-Europe/1.0", forHTTPHeaderField: "User-Agent")
        let (compressed, response) = try await FlightNetwork.data(
            for: request,
            priority: .high
        )
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              compressed.starts(with: Data("BZh".utf8))
        else { throw EDFZWeatherError.serverError }

        let manager = FileManager.default
        let directory = manager.temporaryDirectory
            .appendingPathComponent("flybook-ceiling", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let archive = directory
            .appendingPathComponent(UUID().uuidString + ".grib2.bz2")
        try compressed.write(to: archive, options: .atomic)
        defer { try? manager.removeItem(at: archive) }
        let grib = try runTool(
            executable: "/usr/bin/bunzip2",
            arguments: ["-c", archive.path]
        )
        cache(grib, for: url)
        return grib
    }

    private func cache(_ data: Data, for url: URL) {
        gribCache[url] = data
        gribCacheOrder.removeAll { $0 == url }
        gribCacheOrder.append(url)
        while gribCacheOrder.count > maximumCachedFiles {
            let oldest = gribCacheOrder.removeFirst()
            gribCache[oldest] = nil
        }
    }

    private func nearestValue(
        in data: Data,
        latitude: Double,
        longitude: Double,
        executable: String
    ) throws -> Double {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
            .appendingPathComponent("flybook-ceiling", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(UUID().uuidString + ".grib2")
        try data.write(to: file, options: .atomic)
        defer { try? manager.removeItem(at: file) }
        let output = try runTool(
            executable: executable,
            arguments: [
                "-l",
                String(format: "%.5f,%.5f,1", latitude, longitude),
                file.path
            ]
        )
        guard let text = String(data: output, encoding: .utf8),
              let value = Double(
                text.trimmingCharacters(in: .whitespacesAndNewlines)
              )
        else { throw EDFZWeatherError.noForecast }
        return value
    }

    private func gribGetExecutable() -> String? {
        let manager = FileManager.default
        return ["/opt/homebrew/bin/grib_get", "/usr/local/bin/grib_get"]
            .first { manager.isExecutableFile(atPath: $0) }
    }

    private func runTool(executable: String, arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw EDFZWeatherError.noForecast
        }
        return result
    }
#endif
}
