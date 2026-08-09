import Foundation

struct FuelPriceRecord: Codable, Hashable {
    var avgas: Double?
    var ul91: Double?
    var mogas: Double?
    var reportedAt: String?

    init(
        avgas: Double? = nil,
        ul91: Double? = nil,
        mogas: Double? = nil,
        reportedAt: String? = nil
    ) {
        self.avgas = avgas
        self.ul91 = ul91
        self.mogas = mogas
        self.reportedAt = reportedAt
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
        let checkedAtByICAO: [String: Date]?
    }

    private let validationVersion = 6
    private let regularCheckInterval: TimeInterval = 24 * 60 * 60

    nonisolated static func cachedPrices(
        seed: [String: FuelPriceRecord]
    ) -> [String: FuelPriceRecord] {
        mergedPrices(
            seed: seed,
            cached: (try? loadCache())?.prices ?? [:]
        )
    }

    func refreshedPriceIfNeeded(
        for rawICAO: String,
        seed: [String: FuelPriceRecord],
        now: Date = Date()
    ) async -> FuelPriceRecord? {
        let icao = rawICAO.uppercased()
        let previousCache = try? Self.loadCache()
        var prices = Self.mergedPrices(
            seed: seed,
            cached: previousCache?.prices ?? [:]
        )
        var checkedAtByICAO = previousCache?.checkedAtByICAO ?? [:]

        if !Self.shouldRefresh(
            lastCheckedAt: checkedAtByICAO[icao],
            now: now,
            maximumAge: regularCheckInterval
        ) {
            return prices[icao]
        }

        let fetched: FuelPriceRecord?
        if icao == "EDFZ" {
            fetched = await officialMainzPrices()
        } else {
            fetched = try? await fetchCommunityPrices(icao: icao)
        }
        if let fetched {
            prices[icao] = merged(fetched, fallback: prices[icao])
        }

        // Auch ein fehlgeschlagener, sparsamer Versuch wird vermerkt. So
        // erzeugt ein zeitweise nicht erreichbarer Anbieter nicht bei jedem
        // Seitenwechsel erneut Datenverkehr; der bekannte Preis bleibt stehen.
        checkedAtByICAO[icao] = now
        try? Self.saveCache(
            Cache(
                monthKey: currentMonthKey,
                validationVersion: validationVersion,
                prices: prices,
                checkedAtByICAO: checkedAtByICAO
            )
        )
        return prices[icao]
    }

    static func mergedPrices(
        seed: [String: FuelPriceRecord],
        cached: [String: FuelPriceRecord]
    ) -> [String: FuelPriceRecord] {
        var result = seed
        for (icao, cachedRecord) in cached {
            let fallback = result[icao]
            result[icao] = FuelPriceRecord(
                avgas: cachedRecord.avgas ?? fallback?.avgas,
                ul91: cachedRecord.ul91 ?? fallback?.ul91,
                mogas: cachedRecord.mogas ?? fallback?.mogas,
                reportedAt: cachedRecord.reportedAt ?? fallback?.reportedAt
            )
        }
        return result
    }

    static func shouldRefresh(
        lastCheckedAt: Date?,
        now: Date,
        maximumAge: TimeInterval
    ) -> Bool {
        guard let lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= maximumAge
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
            mogas: loosePrice(in: html, labels: ["Super Plus Aviation", "Super Plus"]),
            reportedAt: "Stand 13.05.2026"
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
        // aviation-fuel-prices.com publishes the current airport price without
        // the German source's nearby "Stand" field. Keep that source usable,
        // while never accepting an undated loose match from spritpreisliste.de.
        let second = secondaryHTML.map(parseCurrentAirportPage)
            ?? FuelPriceRecord()
        let record = merged(first, fallback: second)
        guard record.avgas != nil || record.ul91 != nil || record.mogas != nil else {
            throw URLError(.cannotParseResponse)
        }
        return record
    }

    private func download(_ url: URL) async throws -> String {
        let (data, response) = try await FlightNetwork.data(
            from: url,
            priority: .low
        )
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

        let avgas = datedPrice(
                in: text,
                labels: ["100 LL Preis", "AVGAS 100 LL"]
            )
        let ul91 = datedPrice(
                in: text,
                labels: ["UL91 Preis", "AVGAS UL91"]
            )
        let mogas = datedPrice(
                in: text,
                labels: ["Super+ Preis", "MOGAS Preis", "Super Plus"]
            )
        return FuelPriceRecord(
            avgas: avgas?.value,
            ul91: ul91?.value,
            mogas: mogas?.value,
            reportedAt:
                avgas?.reportedAt
                ?? ul91?.reportedAt
                ?? mogas?.reportedAt
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

    private func parseCurrentAirportPage(_ html: String) -> FuelPriceRecord {
        let text = html
            .replacingOccurrences(
                of: "<[^>]+>",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: "&nbsp;", with: " ")
        return FuelPriceRecord(
            avgas: loosePrice(in: text, labels: ["AVGAS 100LL", "AVGAS100LL"]),
            ul91: loosePrice(in: text, labels: ["AVGAS UL91", "UL91"]),
            mogas: loosePrice(in: text, labels: ["MOGAS", "Super+", "Super Plus"]),
            reportedAt: "Abruf " + currentDateText
        )
    }

    private struct DatedPrice {
        let value: Double
        let reportedAt: String
    }

    private var currentDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = DestinationTimeZone.edfz
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: Date())
    }

    private func datedPrice(
        in text: String,
        labels: [String]
    ) -> DatedPrice? {
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

            guard let value = Double(
                text[valueRange]
                    .replacingOccurrences(of: ",", with: ".")
            ) else { continue }
            return DatedPrice(
                value: value,
                reportedAt: "Stand " + String(text[dateRange])
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
            mogas: fetched.mogas ?? fallback?.mogas,
            reportedAt:
                fetched.reportedAt ?? fallback?.reportedAt
        )
    }

    nonisolated private static func cacheURL() throws -> URL {
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

    nonisolated private static func loadCache() throws -> Cache {
        let data = try Data(contentsOf: cacheURL())
        return try JSONDecoder().decode(Cache.self, from: data)
    }

    nonisolated private static func saveCache(_ cache: Cache) throws {
        let data = try JSONEncoder().encode(cache)
        try data.write(to: cacheURL(), options: .atomic)
    }
}
