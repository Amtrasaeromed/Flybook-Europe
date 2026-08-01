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

    private static let expectedDestinationCount = 39
    private static let fuelPrices: [String: FuelPriceRecord] = [
        // Offizielle Bruttopreise, gültig ab 13.05.2026.
        "EDFZ": FuelPriceRecord(
            avgas: 3.03,
            ul91: nil,
            mogas: 2.59
        ),
        "EHMZ": FuelPriceRecord(avgas: 3.25, ul91: nil, mogas: 1.83)
    ]

    private let airportElevationFeet: [String: Double] = [
        "EDFZ": 760,
        "EKVJ": 17,
        "EKSS": 1,
        "EKRN": 52,
        "EKSB": 24,
        "EKAE": 3,
        "EDWL": 7,
        "EDWJ": 8,
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
        "EDXH": 8,
        "LIPV": 13,
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

            var parsedDestinations =
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
                let fuelPrices = Self.fuelPrices[icao]

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
                    avgasPricePerLiterEUR: fuelPrices?.avgas,
                    ul91PricePerLiterEUR: fuelPrices?.ul91,
                    mogasPricePerLiterEUR: fuelPrices?.mogas,
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

            if !parsedDestinations.contains(where: { $0.icao == "EDFZ" }) {
                parsedDestinations.append(mainzDestination)
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

            destinations = parsedDestinations.sorted { first, second in
                let firstDistance = AirportDistance.nauticalMiles(
                    from: .edfz,
                    to: first
                )
                let secondDistance = AirportDistance.nauticalMiles(
                    from: .edfz,
                    to: second
                )

                if abs(firstDistance - secondDistance) < 0.01 {
                    return first.icao < second.icao
                }
                return firstDistance < secondDistance
            }
            Task {
                await refreshMonthlyFuelPrices()
            }

        } catch {
            destinations = []
            loadError =
                "Mastertabelle konnte nicht gelesen werden: "
                + error.localizedDescription
        }
    }

    private func refreshMonthlyFuelPrices() async {
        let prices = await MonthlyFuelPriceService.shared.prices(
            for: destinations.map(\.icao).filter { $0 != "EDFZ" },
            seed: Self.fuelPrices
        )
        var verifiedPrices = prices
        verifiedPrices["EDFZ"] = await MonthlyFuelPriceService.shared.officialMainzPrices()
            ?? FuelPriceRecord(avgas: 3.03, ul91: nil, mogas: 2.59)
        var updated = destinations
        for index in updated.indices {
            guard let price = verifiedPrices[updated[index].icao] else {
                continue
            }
            updated[index].avgasPricePerLiterEUR = price.avgas
            updated[index].ul91PricePerLiterEUR = price.ul91
            updated[index].mogasPricePerLiterEUR = price.mogas
        }
        destinations = updated

        if let mainz = verifiedPrices["EDFZ"] {
            if let avgas = mainz.avgas {
                UserDefaults.standard.set(
                    avgas,
                    forKey: FuelPriceSettingsKey.mainzAvgas
                )
            }
            if let mogas = mainz.mogas {
                UserDefaults.standard.set(
                    mogas,
                    forKey: FuelPriceSettingsKey.mainzMogas
                )
            }
        }
    }

    private var mainzDestination: Destination {
        Destination(
            icao: "EDFZ",
            name: "Mainz-Finthen",
            country: "DE",
            region: "Rheinhessen",
            weekendScore: "",
            season: "Ganzjährig",
            airportFilter: "Heimatflugplatz",
            directNM: 0,
            runwayM: 1000,
            surface: "Asphalt",
            avgas: "prüfen",
            ul91: "prüfen",
            mogas: "Ja",
            avgasPricePerLiterEUR:
                Self.fuelPrices["EDFZ"]?.avgas,
            ul91PricePerLiterEUR:
                Self.fuelPrices["EDFZ"]?.ul91,
            mogasPricePerLiterEUR:
                Self.fuelPrices["EDFZ"]?.mogas,
            ppr: "Nein",
            transfer: "Mainz / Rheinhessen",
            transferMinutes: 20,
            bikeDirect: "Nein",
            highlights: "Mainz · Rheinhessen · Rhein",
            activities: "Rundflug · Stadt · Weinregion",
            airportNote: "Mainz-Finthen ist als Ziel und für Rundflüge ab EDFZ auswählbar.",
            status: "Heimatflugplatz",
            airportSource: "",
            tourismSource: "",
            latitude: AirportReference.edfz.latitude,
            longitude: AirportReference.edfz.longitude,
            elevationFeet: AirportReference.edfz.elevationFeet,
            regionalImageName: "EDFZ",
            flightTimes: FlightMath.calculate(directNM: 0)
        )
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
