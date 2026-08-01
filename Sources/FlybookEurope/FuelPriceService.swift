import Foundation

struct FuelPriceRecord: Codable, Hashable {
    var avgas: Double?
    var ul91: Double?
    var mogas: Double?

    init(avgas: Double? = nil, ul91: Double? = nil, mogas: Double? = nil) {
        self.avgas = avgas
        self.ul91 = ul91
        self.mogas = mogas
    }
}

enum FuelPriceSettingsKey {
    static let mainzAvgas = "flybookMainzAvgasPrice"
    static let mainzMogas = "flybookMainzMogasPrice"
}

actor MonthlyFuelPriceService {
    static let shared = MonthlyFuelPriceService()

    private struct Cache: Codable {
        let monthKey: String
        let validationVersion: Int?
        let prices: [String: FuelPriceRecord]
    }

    func prices(
        for icaos: [String],
        seed: [String: FuelPriceRecord]
    ) async -> [String: FuelPriceRecord] {
        let key = currentMonthKey
        if let cache = try? loadCache(),
           cache.monthKey == key,
           cache.validationVersion == 4
        {
            return cache.prices
        }

        let previousCache = try? loadCache()
        var result =
            previousCache?.validationVersion == 4
            ? previousCache?.prices ?? seed
            : seed

        let batchSize = 6
        for start in stride(
            from: 0,
            to: icaos.count,
            by: batchSize
        ) {
            let end = min(start + batchSize, icaos.count)
            let batch = Array(icaos[start..<end])
            let fetchedBatch = await withTaskGroup(
                of: (String, FuelPriceRecord?).self
            ) { group in
                for icao in batch {
                    group.addTask {
                        (
                            icao,
                                try? await self.fetchCommunityPrices(icao: icao)
                        )
                    }
                }
                var values: [(String, FuelPriceRecord?)] = []
                for await value in group {
                    values.append(value)
                }
                return values
            }

            for (icao, fetched) in fetchedBatch {
                guard let fetched else { continue }
                result[icao] = merged(
                    fetched,
                    fallback: result[icao]
                )
            }
        }

        // A partial refresh is still cached. Failed individual sources keep
        // their last verified value and are retried at the next month change.
        try? saveCache(
            Cache(
                monthKey: key,
                validationVersion: 4,
                prices: result
            )
        )
        return result
    }

    private var currentMonthKey: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = DestinationTimeZone.edfz
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    func officialMainzPrices() async -> FuelPriceRecord? {
        guard let url = URL(string: "https://edfz.de/flugplatz/pilot-briefing/treibstoffpreise/") else { return nil }
        guard let html = try? await download(url), !html.isEmpty else { return nil }
        let record = FuelPriceRecord(
            avgas: loosePrice(in: html, labels: ["AVGAS100LL", "AVGAS 100LL"]),
            ul91: loosePrice(in: html, labels: ["UL91"]),
            mogas: loosePrice(in: html, labels: ["Super Plus Aviation", "Super Plus"])
        )
        return record.avgas == nil && record.ul91 == nil && record.mogas == nil ? nil : record
    }

    private func fetchCommunityPrices(icao: String) async throws -> FuelPriceRecord {
        guard icao != "EDFZ" else { throw URLError(.unsupportedURL) }
        let primaryURL = URL(string: "https://spritpreisliste.de/airports/\(icao)")!
        let secondaryURL = URL(string: "https://aviation-fuel-prices.com/airport-info/\(icao)")!
        async let primary = try? download(primaryURL)
        async let secondary = try? download(secondaryURL)
        let (primaryHTML, secondaryHTML) = await (primary, secondary)
        let first = primaryHTML.map(parse) ?? FuelPriceRecord()
        let second = secondaryHTML.map(parse) ?? FuelPriceRecord()
        let record = merged(first, fallback: second)
        guard record.avgas != nil || record.ul91 != nil || record.mogas != nil else {
            throw URLError(.cannotParseResponse)
        }
        return record
    }

    private func download(_ url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8)
        else {
            throw URLError(.badServerResponse)
        }

        return html
    }

    private func parse(_ html: String) -> FuelPriceRecord {
        let text = html
            .replacingOccurrences(
                of: "<[^>]+>",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: "&nbsp;", with: " ")

        return FuelPriceRecord(
            avgas: price(
                in: text,
                labels: ["100 LL Preis", "AVGAS 100 LL"]
            ) ?? loosePrice(in: text, labels: ["AVGAS 100LL", "AVGAS100LL"]),
            ul91: price(
                in: text,
                labels: ["UL91 Preis", "AVGAS UL91"]
            ) ?? loosePrice(in: text, labels: ["UL91"]),
            mogas: price(
                in: text,
                labels: ["Super+ Preis", "MOGAS Preis", "Super Plus"]
            ) ?? loosePrice(in: text, labels: ["MOGAS", "Super+", "Super Plus"])
        )
    }

    private func loosePrice(in text: String, labels: [String]) -> Double? {
        for label in labels {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            let pattern = escaped + #"(?is:.{0,220}?)([0-9]+[,.][0-9]{2,3})\s*(?:€|EUR)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text),
                  let value = Double(text[range].replacingOccurrences(of: ",", with: ".")),
                  (0.5...10).contains(value) else { continue }
            return value
        }
        return nil
    }

    private func price(
        in text: String,
        labels: [String]
    ) -> Double? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DestinationTimeZone.edfz
        let cutoff = calendar.date(
            byAdding: .month,
            value: -3,
            to: Date()
        ) ?? .distantFuture

        for label in labels {
            let escaped = NSRegularExpression.escapedPattern(
                for: label
            )
            let pattern =
                escaped
                + #"(?s:.{0,240}?)([0-9]+[,.][0-9]{2,4})\s*€\s*/\s*l"#
                + #"(?s:.{0,160}?)Stand:\s*([0-9]{2}\.[0-9]{2}\.[0-9]{4})"#
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(
                in: text,
                range: range
            ),
            let valueRange = Range(match.range(at: 1), in: text),
            let dateRange = Range(match.range(at: 2), in: text)
            else { continue }

            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = DestinationTimeZone.edfz
            dateFormatter.dateFormat = "dd.MM.yyyy"
            guard let reportedAt = dateFormatter.date(
                from: String(text[dateRange])
            ),
            reportedAt >= cutoff,
            reportedAt <= Date()
            else { continue }

            return Double(
                text[valueRange]
                    .replacingOccurrences(of: ",", with: ".")
            )
        }
        return nil
    }

    private func merged(
        _ fetched: FuelPriceRecord,
        fallback: FuelPriceRecord?
    ) -> FuelPriceRecord {
        FuelPriceRecord(
            avgas: fetched.avgas ?? fallback?.avgas,
            ul91: fetched.ul91 ?? fallback?.ul91,
            mogas: fetched.mogas ?? fallback?.mogas
        )
    }

    private func cacheURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent("Flybook Europe", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("fuel-prices.json")
    }

    private func loadCache() throws -> Cache {
        let data = try Data(contentsOf: cacheURL())
        return try JSONDecoder().decode(Cache.self, from: data)
    }

    private func saveCache(_ cache: Cache) throws {
        let data = try JSONEncoder().encode(cache)
        try data.write(to: cacheURL(), options: .atomic)
    }
}
