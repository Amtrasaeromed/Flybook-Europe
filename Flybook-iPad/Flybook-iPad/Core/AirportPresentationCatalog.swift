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

        var values: [String: AirportFuelPrices] = [:]
        for row in rows.dropFirst() {
            let icao = value("airport_id", in: row).uppercased()
            let type = value("fuel_type", in: row).uppercased()
            guard !icao.isEmpty,
                  let price = Double(value("price_eur_per_litre", in: row))
            else { continue }

            let point = FuelPricePoint(
                eurosPerLiter: price,
                checkedAt: displayDate(value("price_checked_at", in: row))
            )
            var airport = values[icao] ?? AirportFuelPrices()
            switch type {
            case "AVGAS": airport.avgas = point
            case "UL91": airport.ul91 = point
            case "MOGAS", "MOGAS_SUPER": airport.mogas = point
            default: continue
            }
            values[icao] = airport
        }
        return AirportFuelPriceCatalog(values: values)
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
