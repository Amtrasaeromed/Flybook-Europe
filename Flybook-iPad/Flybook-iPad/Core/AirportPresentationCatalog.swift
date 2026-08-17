import Foundation

struct FuelPricePoint: Hashable {
    let eurosPerLiter: Double
    let checkedAt: String
}

struct AirportFuelPrices: Hashable {
    var avgas: FuelPricePoint?
    var ul91: FuelPricePoint?
    var mogas: FuelPricePoint?
}

struct AirportFuelPriceCatalog {
    private let values: [String: AirportFuelPrices]

    private struct Candidate {
        let point: FuelPricePoint
        let source: String
        let date: Date?
    }

    static let referenceEDFZ = AirportFuelPrices(
        avgas: FuelPricePoint(eurosPerLiter: 3.03, checkedAt: "13.05.2026"),
        ul91: nil,
        mogas: FuelPricePoint(eurosPerLiter: 2.59, checkedAt: "13.05.2026")
    )

    func prices(for icao: String) -> AirportFuelPrices {
        if icao.uppercased() == "EDFZ" { return Self.referenceEDFZ }
        return values[icao.uppercased()] ?? AirportFuelPrices()
    }

    static func load(bundle: Bundle = .main) -> AirportFuelPriceCatalog {
        guard let url = bundle.url(forResource: "fuel_prices", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return AirportFuelPriceCatalog(values: [:]) }

        let rows = CSVParser.parse(text)
        guard let header = rows.first else { return AirportFuelPriceCatalog(values: [:]) }
        let columns = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })

        func value(_ name: String, in row: [String]) -> String {
            guard let index = columns[name], row.indices.contains(index) else { return "" }
            return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var candidates: [String: [String: [Candidate]]] = [:]
        for row in rows.dropFirst() {
            let icao = value("airport_id", in: row).uppercased()
            let type = value("fuel_type", in: row).uppercased()
            guard !icao.isEmpty,
                  let price = Double(value("price_eur_per_litre", in: row))
            else { continue }

            let checkedAt = value("price_checked_at", in: row)
            let candidate = Candidate(
                point: FuelPricePoint(
                eurosPerLiter: price,
                    checkedAt: displayDate(checkedAt)
                ),
                source: value("source", in: row),
                date: sourceDate(checkedAt)
            )
            switch type {
            case "AVGAS", "UL91", "MOGAS", "MOGAS_SUPER":
                candidates[icao, default: [:]][type, default: []].append(candidate)
            default: continue
            }
        }

        var values: [String: AirportFuelPrices] = [:]
        for (icao, byType) in candidates {
            values[icao] = AirportFuelPrices(
                avgas: preferred(byType["AVGAS", default: []])?.point,
                ul91: preferred(byType["UL91", default: []])?.point,
                mogas: preferred(
                    byType["MOGAS_SUPER", default: []]
                        + byType["MOGAS", default: []]
                )?.point
            )
        }
        return AirportFuelPriceCatalog(values: values)
    }

    private static func preferred(_ rawCandidates: [Candidate]) -> Candidate? {
        let usable = rawCandidates.filter {
            !$0.source.lowercased().contains("aviation-fuel-prices.com")
        }
        guard let newest = usable.max(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }),
              let newestDate = newest.date,
              let cutoff = Calendar(identifier: .gregorian).date(
                byAdding: .day,
                value: -7,
                to: newestDate
              )
        else { return usable.last }

        return usable
            .filter { isAuthoritative($0.source) && ($0.date ?? .distantPast) >= cutoff }
            .max(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) })
            ?? newest
    }

    private static func isAuthoritative(_ source: String) -> Bool {
        let normalized = source.lowercased()
        return !normalized.isEmpty
            && !normalized.contains("aip.aero")
            && !normalized.contains("gat.aerops.com")
            && !normalized.contains("spritpreisliste.de")
            && !normalized.contains("aviation-fuel-prices.com")
    }

    private static func sourceDate(_ rawValue: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rawValue)
    }

    private static func displayDate(_ rawValue: String) -> String {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 3 else { return rawValue.isEmpty ? "unklar" : rawValue }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }
}

struct AirportFeature: Identifiable, Hashable {
    let type: String
    var id: String { type }

    var title: String {
        switch type {
        case "techstop": return "TechStop"
        case "breakfast": return "Frühstück"
        case "city": return "Stadt"
        case "beach": return "Meer"
        case "lake": return "See / Natur"
        case "mountain": return "Berge"
        case "wellness": return "Wellness"
        default: return type.capitalized
        }
    }

    var symbol: String {
        switch type {
        case "techstop": return "fuelpump.fill"
        case "breakfast": return "cup.and.saucer.fill"
        case "city": return "building.2.fill"
        case "beach": return "beach.umbrella.fill"
        case "lake": return "leaf.fill"
        case "mountain": return "mountain.2.fill"
        case "wellness": return "sparkles"
        default: return "star.fill"
        }
    }
}

struct AirportFeatureCatalog {
    private let values: [String: [AirportFeature]]

    func features(for icao: String) -> [AirportFeature] {
        values[icao.uppercased()] ?? []
    }

    static func load(bundle: Bundle = .main) -> AirportFeatureCatalog {
        guard let url = bundle.url(forResource: "features", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return AirportFeatureCatalog(values: [:]) }

        let rows = CSVParser.parse(text)
        guard let header = rows.first else { return AirportFeatureCatalog(values: [:]) }
        let columns = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })

        func value(_ name: String, in row: [String]) -> String {
            guard let index = columns[name], row.indices.contains(index) else { return "" }
            return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var values: [String: [AirportFeature]] = [:]
        for row in rows.dropFirst() {
            let status = value("status_raw", in: row).lowercased()
            guard status.hasPrefix("ja") || status == "available" else { continue }
            let icao = value("airport_id", in: row).uppercased()
            let type = value("feature_type", in: row).lowercased()
            guard !icao.isEmpty, !type.isEmpty else { continue }
            values[icao, default: []].append(AirportFeature(type: type))
        }
        return AirportFeatureCatalog(values: values)
    }
}
