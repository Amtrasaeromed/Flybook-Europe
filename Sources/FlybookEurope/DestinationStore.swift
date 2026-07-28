import Foundation

private struct DestinationExtra: Decodable {
    let displayName: String?
    let regionLabel: String?
    let latitude: Double?
    let longitude: Double?
    let regionImage: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case regionLabel = "region_label"
        case latitude
        case longitude
        case regionImage = "region_image"
    }
}

@MainActor
final class DestinationStore: ObservableObject {

    private static let expectedDestinationCount = 35

    private let airportElevationFeet: [String: Double] = [
        "EKVJ": 17,
        "EKSS": 1,
        "EKRN": 52,
        "EKSB": 24,
        "EKAE": 3,
        "EDWL": 7,
        "EHAL": 11,
        "EHTX": 2,
        "EHMZ": 6,
        "LKKV": 1989,
        "LKCS": 1417,
        "LFRF": 45,
        "LFGA": 628,
        "LOWS": 1411,
        "LOIJ": 2204,
        "LSZR": 1306,
        "LOIH": 1352,
        "LOWZ": 2470,
        "LOWI": 1907,
        "LJMB": 876,
        "LIPB": 787,
        "LJBL": 1654,
        "LSGS": 1585,
        "LSZL": 650,
        "LIDT": 610,
        "LSZA": 915,
        "LFLP": 1525,
        "LIMW": 1791,
        "LJPZ": 7,
        "LDRI": 278,
        "LDLO": 151,
        "EDHL": 53,
        "EDDV": 171,
        "EDGE": 1101,
        "EDKA": 623,
    ]

    @Published private(set) var destinations: [Destination] = []
    @Published private(set) var loadError: String?
    @Published private(set) var isLoading = true

    init() {
        load()
    }

    private func load() {
        isLoading = true
        loadError = nil

        defer {
            isLoading = false
        }
        guard let csvURL = Bundle.module.url(forResource: "Flybook_Master", withExtension: "csv") else {
            loadError = "Mastertabelle wurde nicht gefunden."
            return
        }

        do {
            let text = try String(contentsOf: csvURL, encoding: .utf8)
            let rows = CSVParser.parse(text)
            guard let header = rows.first else {
                loadError = "Mastertabelle ist leer."
                return
            }

            let extras = loadExtras()

            let column = header.enumerated().reduce(
                into: [String: Int]()
            ) { result, item in
                let cleanedName = item.element
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

                guard !cleanedName.isEmpty else {
                    return
                }

                // Keep the first occurrence. A duplicate
                // column name must never terminate the app.
                if result[cleanedName] == nil {
                    result[cleanedName] = item.offset
                }
            }

            let requiredColumns = [
                "Land",
                "Ziel",
                "ICAO",
                "NM direkt"
            ]

            let missingColumns = requiredColumns.filter {
                column[$0] == nil
            }

            guard missingColumns.isEmpty else {
                loadError =
                    "Mastertabelle: Pflichtspalten fehlen: "
                    + missingColumns.joined(separator: ", ")
                return
            }

            func value(_ row: [String], _ name: String) -> String {
                guard let index = column[name], row.indices.contains(index) else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let parsedDestinations =
                rows.dropFirst().compactMap {
                    row -> Destination? in
                let icao = value(row, "ICAO")
                guard !icao.isEmpty else {
                    return nil
                }
                let extra = extras[icao]
                let rawName = value(row, "Ziel")
                let fallbackName = rawName.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rawName
                let directNM = number(value(row, "NM direkt"))

                return Destination(
                    icao: icao,
                    name: extra?.displayName ?? fallbackName,
                    country: value(row, "Land"),
                    region: extra?.regionLabel ?? value(row, "Wetterregion"),
                    weekendScore: value(row, "Weekend Score"),
                    season: value(row, "Saison"),
                    airportFilter: value(row, "Airport-Filter"),
                    directNM: directNM,
                    runwayM: Int(number(value(row, "Runway m"))),
                    surface: value(row, "Belag"),
                    avgas: value(row, "AVGAS"),
                    ul91: value(row, "UL91"),
                    mogas: value(row, "MOGAS"),
                    ppr: value(row, "PPR"),
                    transfer: value(row, "Transfer"),
                    transferMinutes: Int(number(value(row, "Transfer min"))),
                    bikeDirect: value(row, "Bike direkt"),
                    highlights: value(row, "Highlights"),
                    activities: value(row, "Aktivitäten"),
                    airportNote: value(row, "Airport-Hinweis"),
                    status: value(row, "Status"),
                    airportSource: value(row, "Quelle Airport"),
                    tourismSource: value(row, "Quelle Tourismus"),
                    latitude: extra?.latitude,
                    longitude: extra?.longitude,
                    elevationFeet:
                        airportElevationFeet[icao] ?? 0,
                    regionalImageName: regionalImageName(icao: icao, configuredPath: extra?.regionImage),
                    flightTimes:
                        FlightMath.calculate(
                            directNM: directNM
                        )
                )
            }

            guard !parsedDestinations.isEmpty else {
                let availableHeaders =
                    column.keys.sorted()
                        .joined(separator: ", ")

                loadError =
                    "Mastertabelle enthält keine ladbaren Ziele. "
                    + "Erkannte Spalten: "
                    + availableHeaders
                    + ". Gelesene Datenzeilen: "
                    + "\(max(0, rows.count - 1))."
                destinations = []
                return
            }

            guard parsedDestinations.count == Self.expectedDestinationCount else {
                destinations = []
                loadError =
                    "Mastertabelle: Erwartet wurden "
                    + "\(Self.expectedDestinationCount) Ziele, geladen wurden "
                    + "\(parsedDestinations.count). "
                    + "CSV-Zeilen insgesamt: \(rows.count)."
                return
            }

            destinations = parsedDestinations

        } catch {
            destinations = []
            loadError =
                "Mastertabelle konnte nicht gelesen werden: "
                + error.localizedDescription
        }
    }

    private func loadExtras() -> [String: DestinationExtra] {
        guard let url = Bundle.module.url(forResource: "destination_data", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode([String: DestinationExtra].self, from: data) else {
            return [:]
        }
        return result
    }

    private func number(_ value: String) -> Double {
        Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0.0
    }

    private func regionalImageName(icao: String, configuredPath: String?) -> String {
        guard let configuredPath, !configuredPath.isEmpty else { return icao }
        return URL(fileURLWithPath: configuredPath).deletingPathExtension().lastPathComponent
    }
}
