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

private struct CSVTable {
    let name: String
    let rows: [[String: String]]
}

@MainActor
final class DestinationStore: ObservableObject {
    private static let schemaVersion = "1.2"
    private static let expectedDestinationCount = 134
    private static let bundledSeedPrices: [String: FuelPriceRecord] = [
        "EDFZ": FuelPriceRecord(
            avgas: 3.03,
            ul91: nil,
            mogas: 2.59,
            reportedAt: "Stand 13.05.2026"
        )
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
        defer { isLoading = false }

        do {
            let airports = try readTable("airports")
            let destinationRows = try readTable("destinations")
            let features = try readTable("features")
            let services = try readTable("services")
            let fuels = try readTable("fuels")
            let fuelPrices = try readTable("fuel_prices")
            let techstops = try readTable("techstops")

            try validateSchema([
                airports,
                destinationRows,
                features,
                services,
                fuels,
                fuelPrices,
                techstops
            ])

            let destinationByID = Dictionary(
                uniqueKeysWithValues: destinationRows.rows.compactMap { row in
                    let id = row["airport_id", default: ""]
                    return id.isEmpty ? nil : (id, row)
                }
            )
            let techstopByID = Dictionary(
                uniqueKeysWithValues: techstops.rows.compactMap { row in
                    let id = row["airport_id", default: ""]
                    return id.isEmpty ? nil : (id, row)
                }
            )
            let featuresByAirport = Dictionary(grouping: features.rows) {
                $0["airport_id", default: ""]
            }
            let servicesByAirport = Dictionary(grouping: services.rows) {
                $0["airport_id", default: ""]
            }
            let fuelsByAirport = Dictionary(grouping: fuels.rows) {
                $0["airport_id", default: ""]
            }
            let pricesByAirport = Dictionary(grouping: fuelPrices.rows) {
                $0["airport_id", default: ""]
            }
            let extras = loadExtras()

            var parsed = try airports.rows.map { airport -> Destination in
                let airportID = airport["airport_id", default: ""]
                guard !airportID.isEmpty else {
                    throw DataLoadError.missingRequiredValue(
                        table: "airports",
                        id: "<unbekannt>",
                        field: "airport_id"
                    )
                }
                let airportFeatures = featuresByAirport[airportID, default: []]
                let importedFeatureSet = destinationFeatures(rows: airportFeatures)
                guard destinationByID[airportID] != nil
                        || techstopByID[airportID] != nil
                        || !importedFeatureSet.isEmpty
                else {
                    throw DataLoadError.unclassifiedAirport(airportID)
                }
                guard let directNM = optionalDouble(airport["distance_edfz_nm", default: ""]) else {
                    throw DataLoadError.missingRequiredValue(
                        table: "airports",
                        id: airportID,
                        field: "distance_edfz_nm"
                    )
                }
                guard let elevationFeet = optionalDouble(airport["elevation_ft", default: ""]) else {
                    throw DataLoadError.missingRequiredValue(
                        table: "airports",
                        id: airportID,
                        field: "elevation_ft"
                    )
                }
                guard let runwayLength = optionalInt(airport["runway_length_m", default: ""]),
                      runwayLength > 0 else {
                    throw DataLoadError.missingRequiredValue(
                        table: "airports",
                        id: airportID,
                        field: "runway_length_m"
                    )
                }
                guard let runwayLDA = optionalInt(airport["runway_lda_m", default: ""]),
                      runwayLDA > 0 else {
                    throw DataLoadError.missingRequiredValue(
                        table: "airports",
                        id: airportID,
                        field: "runway_lda_m"
                    )
                }
                let timeZoneIdentifier = airport["timezone_identifier", default: ""]
                guard !timeZoneIdentifier.isEmpty,
                      TimeZone(identifier: timeZoneIdentifier) != nil else {
                    throw DataLoadError.missingRequiredValue(
                        table: "airports",
                        id: airportID,
                        field: "timezone_identifier"
                    )
                }

                let destinationRow = destinationByID[airportID] ?? [:]
                let techstopRow = techstopByID[airportID] ?? [:]
                let extra = extras[airportID]
                let airportServices = servicesByAirport[airportID, default: []]
                let airportFuels = fuelsByAirport[airportID, default: []]
                let airportPrices = pricesByAirport[airportID, default: []]
                var featureSet = importedFeatureSet
                if !techstopRow.isEmpty { featureSet.insert(.techStop) }

                return Destination(
                    icao: airport["icao", default: airportID],
                    name: extra?.displayName
                        ?? nonEmpty(
                            destinationRow["destination_name", default: ""],
                            airport["airport_name", default: ""],
                            airportID
                        ),
                    country: airport["country_code", default: ""],
                    timeZoneIdentifier: timeZoneIdentifier,
                    region: extra?.regionLabel
                        ?? nonEmpty(
                            destinationRow["weather_region", default: ""],
                            techstopRow["region", default: ""]
                        ),
                    weekendScore: nonEmpty(
                        destinationRow["tourism_score", default: ""],
                        techstopRow["techstop_score", default: ""]
                    ),
                    season: destinationRow["season", default: ""],
                    airportFilter: nonEmpty(
                        destinationRow["airport_filter", default: ""],
                        airport["airport_filter", default: ""],
                        featureSet.contains(.techStop) ? "TechStop" : "",
                        featureSet.contains(.breakfast) ? "Frühstück" : ""
                    ),
                    features: featureSet,
                    directNM: directNM,
                    referenceRunway: airport["reference_runway", default: ""],
                    runwayM: runwayLength,
                    runwayWidthM: optionalInt(airport["runway_width_m", default: ""]),
                    runwayLDAM: runwayLDA,
                    surface: airport["runway_surface", default: ""],
                    grassOnly: isAffirmative(airport["grass_only_raw", default: ""]),
                    avgas: fuelAvailability("AVGAS", fuelRows: airportFuels, priceRows: airportPrices),
                    ul91: fuelAvailability("UL91", fuelRows: airportFuels, priceRows: airportPrices),
                    mogas: fuelAvailability("MOGAS_SUPER", fuelRows: airportFuels, priceRows: airportPrices),
                    fuelDetails: fuelDetails(rows: airportFuels),
                    avgasPricePerLiterEUR: price("AVGAS", rows: airportPrices),
                    ul91PricePerLiterEUR: price("UL91", rows: airportPrices),
                    mogasPricePerLiterEUR: price("MOGAS_SUPER", rows: airportPrices),
                    fuelPriceReportedAt: priceReportedAt(rows: airportPrices),
                    ppr: nonEmpty(
                        airport["ppr_status", default: ""],
                        airport["ppr_ga_access", default: ""],
                        techstopRow["ppr_operational_notes", default: ""]
                    ),
                    portOfEntry: portOfEntryStatus(airport: airport),
                    transfer: nonEmpty(
                        destinationRow["transfer_default", default: ""],
                        airport["transfer_default", default: ""]
                    ),
                    transferMinutes: optionalInt(nonEmpty(
                        destinationRow["transfer_minutes", default: ""],
                        destinationRow["best_access_minutes", default: ""],
                        airport["transfer_minutes", default: ""]
                    )) ?? 0,
                    bikeDirect: serviceAvailability("bicycle", rows: airportServices),
                    rentalCarDirect: serviceAvailability("rental_car", rows: airportServices),
                    app2DriveDirect: serviceAvailability("app2drive", rows: airportServices),
                    restaurantDirect: serviceAvailability("restaurant", rows: airportServices),
                    restaurantName: serviceValue(
                        "restaurant",
                        field: "provider_name",
                        rows: airportServices
                    ),
                    restaurantDescription: serviceValue(
                        "restaurant",
                        field: "description",
                        rows: airportServices
                    ),
                    restaurantOpeningHours: serviceValue(
                        "restaurant",
                        field: "opening_hours",
                        rows: airportServices
                    ),
                    restaurantNotes: serviceValue(
                        "restaurant",
                        field: "notes",
                        rows: airportServices
                    ),
                    restaurantSource: serviceValue(
                        "restaurant",
                        field: "source_primary",
                        rows: airportServices
                    ),
                    restaurantDataCheckedAt: serviceValue(
                        "restaurant",
                        field: "data_checked_at",
                        rows: airportServices
                    ),
                    accessFeatures: destinationAccessFeatures(
                        rows: airportFeatures
                    ),
                    highlights: highlights(
                        destination: destinationRow,
                        techstop: techstopRow,
                        features: airportFeatures
                    ),
                    activities: activities(
                        features: featureSet,
                        services: airportServices
                    ),
                    airportNote: airportNote(airport: airport, techstop: techstopRow),
                    status: nonEmpty(
                        airport["verification_status", default: ""],
                        destinationRow["tourism_confidence", default: ""],
                        techstopRow["confidence", default: ""]
                    ),
                    airportSource: nonEmpty(
                        airport["source_airport", default: ""],
                        techstopRow["source_airport", default: ""]
                    ),
                    tourismSource: nonEmpty(
                        destinationRow["source_tourism", default: ""],
                        techstopRow["source_airport", default: ""]
                    ),
                    latitude: optionalDouble(airport["latitude_wgs84", default: ""])
                        ?? extra?.latitude,
                    longitude: optionalDouble(airport["longitude_wgs84", default: ""])
                        ?? extra?.longitude,
                    elevationFeet: elevationFeet,
                    regionalImageName: regionalImageName(
                        icao: airportID,
                        configuredPath: extra?.regionImage
                    )
                )
            }

            guard parsed.count == Self.expectedDestinationCount else {
                throw DataLoadError.invalidCount(
                    expected: Self.expectedDestinationCount,
                    actual: parsed.count
                )
            }

            if !parsed.contains(where: { $0.icao == "EDFZ" }) {
                parsed.append(mainzDestination)
            }

            destinations = parsed.sorted { first, second in
                let firstDistance = AirportDistance.nauticalMiles(from: .edfz, to: first)
                let secondDistance = AirportDistance.nauticalMiles(from: .edfz, to: second)
                if abs(firstDistance - secondDistance) < 0.01 {
                    return first.icao < second.icao
                }
                return firstDistance < secondDistance
            }

            applyFuelPrices(
                MonthlyFuelPriceService.cachedPrices(seed: fuelPriceSeed)
            )

            // Der lokale Preis-Cache wird nach dem synchronen Stammdatenimport
            // ohne Netzverkehr eingeblendet. Online wird spaeter nur der
            // jeweils betrachtete Flugplatz und hoechstens taeglich geprueft.
        } catch {
            destinations = []
            loadError = "Flybook-Daten konnten nicht geladen werden: \(error.localizedDescription)"
        }
    }

    private func readTable(_ name: String) throws -> CSVTable {
        guard let url = Bundle.module.url(forResource: name, withExtension: "csv") else {
            throw DataLoadError.missingFile("\(name).csv")
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let parsed = CSVParser.parse(text)
        guard let rawHeader = parsed.first else {
            throw DataLoadError.emptyFile("\(name).csv")
        }
        let header = rawHeader.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let rows = parsed.dropFirst().compactMap { values -> [String: String]? in
            var row: [String: String] = [:]
            for (index, key) in header.enumerated() where !key.isEmpty {
                row[key] = values.indices.contains(index)
                    ? values[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
            }
            return row.values.allSatisfy(\.isEmpty) ? nil : row
        }
        return CSVTable(name: name, rows: rows)
    }

    private func validateSchema(_ tables: [CSVTable]) throws {
        for table in tables {
            let versions = Set(table.rows.compactMap { row -> String? in
                let version = row["schema_version", default: ""]
                return version.isEmpty ? nil : version
            })
            guard versions.isEmpty || versions == Set([Self.schemaVersion]) else {
                throw DataLoadError.unsupportedSchema(
                    table: table.name,
                    versions: versions.sorted().joined(separator: ", ")
                )
            }
        }
    }

    private func destinationFeatures(rows: [[String: String]]) -> Set<DestinationFeature> {
        Set(rows.compactMap { row in
            guard isAffirmative(row["status_raw", default: ""]) else { return nil }
            return DestinationFeature(rawValue: row["feature_type", default: ""])
        })
    }

    private func destinationAccessFeatures(
        rows: [[String: String]]
    ) -> [DestinationAccessFeature] {
        let supported: Set<DestinationFeature> = [
            .beachSea, .lakeNature, .mountainHiking
        ]
        return rows.compactMap { row in
            guard isAffirmative(row["status_raw", default: ""]),
                  let feature = DestinationFeature(
                    rawValue: row["feature_type", default: ""]
                  ),
                  supported.contains(feature)
            else { return nil }

            let targetName = nonEmpty(
                row["verified_target_name", default: ""],
                row["feature_name", default: ""]
            )
            guard !targetName.isEmpty else { return nil }
            return DestinationAccessFeature(
                feature: feature,
                targetName: targetName,
                distanceKilometers: optionalDouble(
                    row["distance_km", default: ""]
                ),
                recommendedMode: nonEmpty(
                    row["recommended_mode", default: ""],
                    row["access_mode", default: ""]
                ),
                recommendedMinutes: optionalInt(nonEmpty(
                    row["recommended_minutes", default: ""],
                    row["access_minutes", default: ""]
                ))
            )
        }.sorted { $0.feature.rawValue < $1.feature.rawValue }
    }

    private func fuelAvailability(
        _ type: String,
        fuelRows: [[String: String]],
        priceRows: [[String: String]]
    ) -> String {
        if price(type, rows: priceRows) != nil { return "Ja" }

        guard let row = fuelRows.first(where: { $0["fuel_type"] == type }) else {
            return "?"
        }
        let raw = row["availability_raw", default: ""]
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if raw == "nein"
            || raw.hasPrefix("nein ")
            || raw.contains("nicht verfugbar")
            || raw == "no"
        {
            return "Nein"
        }
        if raw == "ja"
            || raw.hasPrefix("ja ")
            || raw == "yes"
            || raw == "available"
            || raw == "verfügbar"
        {
            return "Ja"
        }
        return "?"
    }

    private func price(_ type: String, rows: [[String: String]]) -> Double? {
        rows.first(where: { $0["fuel_type"] == type }).flatMap {
            optionalDouble($0["price_eur_per_litre", default: ""])
        }
    }

    private func fuelDetails(rows: [[String: String]]) -> String {
        rows.compactMap { row in
            let availability = row["availability_raw", default: ""]
                .folding(
                    options: [.diacriticInsensitive, .caseInsensitive],
                    locale: .current
                )
            guard availability == "ja"
                    || availability == "yes"
                    || availability == "available"
            else { return nil }
            let grade = nonEmpty(
                row["grade_or_detail", default: ""],
                row["fuel_type", default: ""]
            )
            let facility = row["other_fuels_raw", default: ""]
            return facility.isEmpty ? grade : "\(grade): \(facility)"
        }
        .joined(separator: "\n")
    }

    private func priceReportedAt(rows: [[String: String]]) -> String? {
        let dates = rows.map { $0["price_checked_at", default: ""] }.filter { !$0.isEmpty }
        guard let newest = dates.sorted().last else { return nil }
        return "Stand \(newest)"
    }

    private func serviceAvailability(_ type: String, rows: [[String: String]]) -> String {
        rows.first(where: { $0["service_type"] == type })?["availability_raw"] ?? ""
    }

    private func portOfEntryStatus(airport: [String: String]) -> String {
        let text = [
            airport["operating_notes", default: ""],
            airport["airport_note", default: ""]
        ].joined(separator: " ")
        if text.localizedCaseInsensitiveContains("POE: Ja") { return "Ja" }
        if text.localizedCaseInsensitiveContains("POE: Nein") { return "Nein" }
        return "?"
    }

    private func serviceValue(
        _ type: String,
        field: String,
        rows: [[String: String]]
    ) -> String {
        rows.first(where: { $0["service_type"] == type })?[field] ?? ""
    }

    private func highlights(
        destination: [String: String],
        techstop: [String: String],
        features: [[String: String]]
    ) -> String {
        var values: [String] = []
        let best = destination["best_highlight", default: ""]
        let bestType = destination["best_highlight_type", default: ""]
        let activeFeatures = destinationFeatures(rows: features)
        if !best.isEmpty,
           let requiredFeature = feature(forHighlightType: bestType)
        {
            if activeFeatures.contains(requiredFeature) {
                values.append(best)
            }
        } else if !best.isEmpty {
            values.append(best)
        }
        for feature in features where isAffirmative(feature["status_raw", default: ""]) {
            let name = feature["feature_name", default: ""]
            if !name.isEmpty && !values.contains(name) { values.append(name) }
        }
        let techstopSummary = techstop["techstop_summary", default: ""]
        if !techstopSummary.isEmpty && !values.contains(techstopSummary) {
            values.append(techstopSummary)
        }
        return values.prefix(4).joined(separator: " · ")
    }

    private func feature(
        forHighlightType value: String
    ) -> DestinationFeature? {
        let normalized = value.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: .current
        )
        if normalized.contains("strand") || normalized.contains("meer") { return .beachSea }
        if normalized.contains("see") || normalized.contains("natur") { return .lakeNature }
        if normalized.contains("berg") || normalized.contains("wander") { return .mountainHiking }
        if normalized.contains("wellness") || normalized.contains("auszeit") { return .wellness }
        if normalized.contains("stadt") || normalized.contains("kultur") { return .city }
        if normalized.contains("fruhstuck") { return .breakfast }
        if normalized.contains("techstop") { return .techStop }
        return nil
    }

    private func activities(
        features: Set<DestinationFeature>,
        services: [[String: String]]
    ) -> String {
        var values = DestinationFeature.allCases
            .filter(features.contains)
            .map(\.title)
        if services.contains(where: {
            $0["service_type"] == "bicycle" && isAffirmative($0["availability_raw", default: ""])
        }) {
            values.append("Fahrrad")
        }
        return values.joined(separator: " · ")
    }

    private func airportNote(
        airport: [String: String],
        techstop: [String: String]
    ) -> String {
        [
            airport["airport_note", default: ""],
            airport["operating_notes", default: ""],
            airport["infrastructure_note", default: ""],
            airport["data_conflict", default: ""],
            techstop["risks_disadvantages", default: ""]
        ]
        .filter { !$0.isEmpty }
        .reduce(into: [String]()) { result, value in
            if !result.contains(value) { result.append(value) }
        }
        .joined(separator: " | ")
    }

    private func isAffirmative(_ value: String) -> Bool {
        let normalized = value.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: .current
        )
        return normalized == "ja"
            || normalized.hasPrefix("ja ")
            || normalized.hasPrefix("ja–")
            || normalized.hasPrefix("ja-")
            || normalized == "true"
            || normalized == "available"
    }

    private func nonEmpty(_ values: String...) -> String {
        values.first(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) ?? ""
    }

    private func optionalDouble(_ value: String) -> Double? {
        let normalized = value
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func optionalInt(_ value: String) -> Int? {
        guard let result = optionalDouble(value) else { return nil }
        return Int(result)
    }

    func refreshFuelPriceIfNeeded(for rawICAO: String) async {
        let icao = rawICAO.uppercased()
        guard destinations.contains(where: { $0.icao == icao }) else { return }
        guard let price = await MonthlyFuelPriceService.shared.refreshedPriceIfNeeded(
            for: icao,
            seed: fuelPriceSeed
        ) else { return }
        applyFuelPrices([icao: price])
    }

    private var fuelPriceSeed: [String: FuelPriceRecord] {
        let bundledPrices = Dictionary(uniqueKeysWithValues: destinations.map { destination in
            (
                destination.icao,
                FuelPriceRecord(
                    avgas: destination.avgasPricePerLiterEUR,
                    ul91: destination.ul91PricePerLiterEUR,
                    mogas: destination.mogasPricePerLiterEUR,
                    reportedAt: destination.fuelPriceReportedAt
                )
            )
        })
        return Self.bundledSeedPrices.merging(bundledPrices) { bundled, imported in
            FuelPriceRecord(
                avgas: imported.avgas ?? bundled.avgas,
                ul91: imported.ul91 ?? bundled.ul91,
                mogas: imported.mogas ?? bundled.mogas,
                reportedAt: imported.reportedAt ?? bundled.reportedAt
            )
        }
    }

    private func applyFuelPrices(
        _ verifiedPrices: [String: FuelPriceRecord]
    ) {
        var updated = destinations
        for index in updated.indices {
            guard let imported = verifiedPrices[updated[index].icao] else { continue }
            updated[index].avgasPricePerLiterEUR = imported.avgas
                ?? updated[index].avgasPricePerLiterEUR
            updated[index].ul91PricePerLiterEUR = imported.ul91
                ?? updated[index].ul91PricePerLiterEUR
            updated[index].mogasPricePerLiterEUR = imported.mogas
                ?? updated[index].mogasPricePerLiterEUR
            if updated[index].avgasPricePerLiterEUR != nil {
                updated[index].avgas = "Ja"
            }
            if updated[index].ul91PricePerLiterEUR != nil {
                updated[index].ul91 = "Ja"
            }
            if updated[index].mogasPricePerLiterEUR != nil {
                updated[index].mogas = "Ja"
            }
            updated[index].fuelPriceReportedAt = imported.reportedAt
                ?? updated[index].fuelPriceReportedAt
        }
        destinations = updated

        if let mainz = verifiedPrices["EDFZ"] {
            if let avgas = mainz.avgas {
                UserDefaults.standard.set(avgas, forKey: FuelPriceSettingsKey.mainzAvgas)
            }
            if let mogas = mainz.mogas {
                UserDefaults.standard.set(mogas, forKey: FuelPriceSettingsKey.mainzMogas)
            }
        }
    }

    private var mainzDestination: Destination {
        Destination(
            icao: "EDFZ",
            name: "Mainz-Finthen",
            country: "DE",
            timeZoneIdentifier: "Europe/Berlin",
            region: "Rheinhessen",
            weekendScore: "",
            season: "Ganzjährig",
            airportFilter: "Heimatflugplatz",
            features: [],
            directNM: 0,
            referenceRunway: "07/25",
            runwayM: 1000,
            runwayWidthM: 22,
            runwayLDAM: 1000,
            surface: "Asphalt",
            grassOnly: false,
            avgas: "prüfen",
            ul91: "prüfen",
            mogas: "Ja",
            avgasPricePerLiterEUR: Self.bundledSeedPrices["EDFZ"]?.avgas,
            ul91PricePerLiterEUR: Self.bundledSeedPrices["EDFZ"]?.ul91,
            mogasPricePerLiterEUR: Self.bundledSeedPrices["EDFZ"]?.mogas,
            fuelPriceReportedAt: Self.bundledSeedPrices["EDFZ"]?.reportedAt,
            ppr: "Nein",
            portOfEntry: "?",
            transfer: "Mainz / Rheinhessen",
            transferMinutes: 20,
            bikeDirect: "Nein",
            rentalCarDirect: "Nein",
            app2DriveDirect: "Nein",
            restaurantDirect: "",
            restaurantName: "",
            restaurantDescription: "",
            restaurantOpeningHours: "",
            restaurantNotes: "",
            restaurantSource: "",
            restaurantDataCheckedAt: "",
            highlights: "Mainz · Rheinhessen · Rhein",
            activities: "Rundflug · Stadt · Weinregion",
            airportNote: "Mainz-Finthen ist als Heimatflugplatz separat und zusätzlich auswählbar.",
            status: "Heimatflugplatz",
            airportSource: "",
            tourismSource: "",
            latitude: AirportReference.edfz.latitude,
            longitude: AirportReference.edfz.longitude,
            elevationFeet: AirportReference.edfz.elevationFeet,
            regionalImageName: "EDFZ"
        )
    }

    private func loadExtras() -> [String: DestinationExtra] {
        guard let url = Bundle.module.url(forResource: "destination_data", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode([String: DestinationExtra].self, from: data)
        else { return [:] }
        return result
    }

    private func regionalImageName(icao: String, configuredPath: String?) -> String {
        guard let configuredPath, !configuredPath.isEmpty else { return icao }
        return URL(fileURLWithPath: configuredPath).deletingPathExtension().lastPathComponent
    }
}

private enum DataLoadError: LocalizedError {
    case missingFile(String)
    case emptyFile(String)
    case unsupportedSchema(table: String, versions: String)
    case invalidCount(expected: Int, actual: Int)
    case missingRequiredValue(table: String, id: String, field: String)
    case unclassifiedAirport(String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let name):
            return "Datendatei \(name) fehlt."
        case .emptyFile(let name):
            return "Datendatei \(name) ist leer."
        case .unsupportedSchema(let table, let versions):
            return "\(table).csv verwendet eine nicht unterstützte Schema-Version: \(versions)."
        case .invalidCount(let expected, let actual):
            return "Erwartet wurden \(expected) gleichberechtigte Ziele, geladen wurden \(actual)."
        case .missingRequiredValue(let table, let id, let field):
            return "Pflichtwert \(field) fehlt in \(table).csv für \(id)."
        case .unclassifiedAirport(let id):
            return "\(id) besitzt weder Ziel- noch TechStop-Detaildaten."
        }
    }
}
