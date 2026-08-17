import Foundation

struct Airport: Identifiable, Hashable {
    let icao: String
    let name: String
    let countryCode: String
    let timeZoneIdentifier: String
    let latitude: Double
    let longitude: Double
    let elevationFeet: Int
    let distanceFromEDFZ: Int?
    let referenceRunway: String
    let runwayLengthMeters: Int?
    let runwayWidthMeters: Int?
    let runwaySurface: String
    let portOfEntry: String
    let airportFilter: String
    let aipAeroURL: String
    let aipAeroCheckedAt: String

    var id: String { icao }

    var isTechStop: Bool {
        airportFilter.localizedCaseInsensitiveContains("TechStop")
    }

    var runwayDisplay: String {
        guard let runwayLengthMeters else { return referenceRunway }
        return "\(referenceRunway) · \(runwayLengthMeters.formatted()) m"
    }
}

enum AirportCatalog {
    static func load(bundle: Bundle = .main) -> [Airport] {
        guard let url = bundle.url(forResource: "airports", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }

        let rows = CSVParser.parse(text)
        guard let header = rows.first else { return [] }
        let columns = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })

        func value(_ name: String, in row: [String]) -> String {
            guard let index = columns[name], row.indices.contains(index) else { return "" }
            return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var airports: [Airport] = rows.dropFirst().compactMap { row -> Airport? in
            let icao = value("icao", in: row).uppercased()
            guard !icao.isEmpty,
                  let latitude = Double(value("latitude_wgs84", in: row)),
                  let longitude = Double(value("longitude_wgs84", in: row))
            else { return nil }

            return Airport(
                icao: icao,
                name: value("airport_name", in: row),
                countryCode: value("country_code", in: row),
                timeZoneIdentifier: value("timezone_identifier", in: row),
                latitude: latitude,
                longitude: longitude,
                elevationFeet: Int(Double(value("elevation_ft", in: row)) ?? 0),
                distanceFromEDFZ: Int(Double(value("distance_edfz_nm", in: row)) ?? -1) >= 0
                    ? Int(Double(value("distance_edfz_nm", in: row)) ?? 0)
                    : nil,
                referenceRunway: value("reference_runway", in: row),
                runwayLengthMeters: Int(Double(value("runway_length_m", in: row)) ?? -1) >= 0
                    ? Int(Double(value("runway_length_m", in: row)) ?? 0)
                    : nil,
                runwayWidthMeters: Int(Double(value("runway_width_m", in: row)) ?? -1) >= 0
                    ? Int(Double(value("runway_width_m", in: row)) ?? 0)
                    : nil,
                runwaySurface: value("runway_surface", in: row),
                portOfEntry: portOfEntryStatus(
                    operatingNotes: value("operating_notes", in: row),
                    airportNote: value("airport_note", in: row)
                ),
                airportFilter: value("airport_filter", in: row),
                aipAeroURL: value("aip_aero_url", in: row),
                aipAeroCheckedAt: value("aip_aero_checked_at", in: row)
            )
        }

        if !airports.contains(where: { $0.icao == "EDFZ" }) {
            airports.append(Airport.edfz)
        }

        return airports.sorted {
            $0.icao.localizedStandardCompare($1.icao) == .orderedAscending
        }
    }

    private static func portOfEntryStatus(
        operatingNotes: String,
        airportNote: String
    ) -> String {
        let text = operatingNotes + " " + airportNote
        if text.localizedCaseInsensitiveContains("POE: Ja") { return "Ja" }
        if text.localizedCaseInsensitiveContains("POE: Nein") { return "Nein" }
        return "?"
    }
}

extension Airport {
    static let fallbackEDFZ = Airport(
        icao: "EDFZ",
        name: "Mainz-Finthen",
        countryCode: "DE",
        timeZoneIdentifier: "Europe/Berlin",
        latitude: 49.9675,
        longitude: 8.1472,
        elevationFeet: 760,
        distanceFromEDFZ: 0,
        referenceRunway: "07/25",
        runwayLengthMeters: 1_000,
        runwayWidthMeters: 22,
        runwaySurface: "Asphalt",
        portOfEntry: "?",
        airportFilter: "Heimatflugplatz",
        aipAeroURL: "https://aip.aero/de/en/vfr/?EDFZ",
        aipAeroCheckedAt: ""
    )

    fileprivate static let edfz = fallbackEDFZ
}
