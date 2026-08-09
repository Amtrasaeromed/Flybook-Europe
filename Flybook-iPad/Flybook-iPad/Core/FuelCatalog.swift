import Foundation

enum FuelAvailabilityStatus: Hashable {
    case available
    case unavailable
    case check

    var label: String {
        switch self {
        case .available: return "JA"
        case .unavailable: return "NEIN"
        case .check: return "PRÜFEN"
        }
    }
}

struct AirportFuelAvailability: Hashable {
    var avgas: FuelAvailabilityStatus = .check
    var ul91: FuelAvailabilityStatus = .check
    var mogas: FuelAvailabilityStatus = .check
    var checkedAt: String?
}

struct AirportFuelCatalog {
    private let values: [String: AirportFuelAvailability]

    func availability(for icao: String) -> AirportFuelAvailability {
        if icao.uppercased() == "EDFZ", values["EDFZ"] == nil {
            return AirportFuelAvailability(
                avgas: .check,
                ul91: .check,
                mogas: .available
            )
        }
        return values[icao.uppercased()] ?? AirportFuelAvailability()
    }

    static func load(bundle: Bundle = .main) -> AirportFuelCatalog {
        guard let url = bundle.url(forResource: "fuels", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return AirportFuelCatalog(values: [:]) }

        let rows = CSVParser.parse(text)
        guard let header = rows.first else { return AirportFuelCatalog(values: [:]) }
        let columns = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })

        func value(_ name: String, in row: [String]) -> String {
            guard let index = columns[name], row.indices.contains(index) else { return "" }
            return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func status(from rawValue: String) -> FuelAvailabilityStatus {
            let normalized = rawValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if normalized.hasPrefix("ja") || normalized == "available" {
                return .available
            }
            if normalized.hasPrefix("nein") || normalized == "unavailable" {
                return .unavailable
            }
            return .check
        }

        var values: [String: AirportFuelAvailability] = [:]
        for row in rows.dropFirst() {
            let icao = value("airport_id", in: row).uppercased()
            guard !icao.isEmpty else { continue }
            let fuelType = value("fuel_type", in: row).uppercased()
            let availability = status(from: value("availability_raw", in: row))
            var airport = values[icao] ?? AirportFuelAvailability()
            let checkedAt = displayDate(value("data_checked_at", in: row))
            if !checkedAt.isEmpty { airport.checkedAt = checkedAt }
            switch fuelType {
            case "AVGAS": airport.avgas = availability
            case "UL91": airport.ul91 = availability
            case "MOGAS_SUPER", "MOGAS": airport.mogas = availability
            default: continue
            }
            values[icao] = airport
        }

        return AirportFuelCatalog(values: values)
    }

    private static func displayDate(_ rawValue: String) -> String {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 3 else { return rawValue }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }
}
