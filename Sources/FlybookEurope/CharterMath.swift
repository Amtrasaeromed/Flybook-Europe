import Foundation

enum CharterFuelStatus: Equatable {
    case standard
    case sufficient
    case warning
    case critical
}

enum CharterMath {
    static func commercialDecimalHours(minutes: Int) -> Double {
        ceil(Double(max(0, minutes)) / 6.0) / 10.0
    }

    static func commercialCost(minutes: Int, hourlyRateEUR: Double) -> Double {
        commercialDecimalHours(minutes: minutes) * max(0, hourlyRateEUR)
    }

    static func actualFuelBurnLiters(
        minutes: Int,
        consumptionLitersPerHour: Double
    ) -> Double {
        Double(max(0, minutes))
            * max(0, consumptionLitersPerHour)
            / 60
    }

    static func combinedTotalCost(
        charterCostEUR: Double,
        landingFeesEUR: Double,
        includeLandingFees: Bool,
        ancillaryAirportFeesEUR: Double = 0
    ) -> Double {
        max(0, charterCostEUR)
            + (includeLandingFees
                ? max(0, landingFeesEUR)
                : 0)
            + max(0, ancillaryAirportFeesEUR)
    }

    static func overnightCount(
        arrival: Date,
        departure: Date,
        timeZone: TimeZone
    ) -> Int {
        guard departure > arrival else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let arrivalDay = calendar.startOfDay(for: arrival)
        let departureDay = calendar.startOfDay(for: departure)
        return max(
            0,
            calendar.dateComponents(
                [.day],
                from: arrivalDay,
                to: departureDay
            ).day ?? 0
        )
    }

    /// Commercial block time is rounded for every flight separately. Adding
    /// raw minutes first can otherwise make 1.3 h + 1.2 h appear as 2.4 h and
    /// disagree with both the two displayed rows and their charter cost.
    static func commercialTotalDecimalHours(legMinutes: [Int]) -> Double {
        legMinutes.reduce(0) {
            $0 + commercialDecimalHours(minutes: $1)
        }
    }

    static func commercialEquivalentMinutes(legMinutes: [Int]) -> Int {
        Int(round(commercialTotalDecimalHours(legMinutes: legMinutes) * 60))
    }

    static func requiredReserveLiters(
        outboundConsumptionPerHour: Double,
        returnConsumptionPerHour: Double?,
        reserveMinutes: Int,
        outboundReserveIsReused: Bool
    ) -> Double {
        let hours = Double(max(0, reserveMinutes)) / 60
        let outbound = max(0, outboundConsumptionPerHour) * hours
        guard let returnConsumptionPerHour else { return outbound }
        let inbound = max(0, returnConsumptionPerHour) * hours
        return outboundReserveIsReused
            ? max(outbound, inbound)
            : outbound + inbound
    }

    static func suggestedRefuelLiters(
        startingFuelLiters: Double,
        firstLegBlockFuelLiters: Double,
        firstLegRequiredFuelLiters: Double,
        secondLegRequiredFuelLiters: Double,
        remainingFirstLegFuelIsAvailable: Bool,
        safetyRoundingIncrementLiters: Double = 0
    ) -> Double {
        let increment = max(0, safetyRoundingIncrementLiters)
        func roundedUpForSafety(_ liters: Double) -> Double {
            let nonnegativeLiters = max(0, liters)
            guard increment > 0 else { return nonnegativeLiters }
            return ceil(nonnegativeLiters / increment - 0.000_000_001)
                * increment
        }

        let rawFirstLegFuelDeduction = remainingFirstLegFuelIsAvailable
            ? firstLegBlockFuelLiters
            : firstLegRequiredFuelLiters
        let firstLegFuelDeduction = roundedUpForSafety(
            rawFirstLegFuelDeduction
        )
        let remainingAfterFirstLeg = max(
            0,
            startingFuelLiters - firstLegFuelDeduction
        )
        let secondLegFuelRequired = roundedUpForSafety(
            secondLegRequiredFuelLiters
        )
        return roundedUpForSafety(
            max(0, secondLegFuelRequired - remainingAfterFirstLeg)
        )
    }

    static func fuelStatus(
        totalRequiredFuelLiters: Double,
        usableFuelLiters: Double,
        startingFuelLiters: Double,
        estimatedFuelAtTripEndWithoutRefuelLiters: Double,
        refuelEnabled: Bool,
        refuelLiters: Double,
        minimumRequiredRefuelLiters: Double,
        estimatedFuelAtTripEndLiters: Double
    ) -> CharterFuelStatus {
        guard usableFuelLiters > 0 else {
            return totalRequiredFuelLiters > 0 ? .critical : .standard
        }
        if refuelEnabled {
            if refuelLiters + 0.0001 < minimumRequiredRefuelLiters
                || estimatedFuelAtTripEndLiters < -0.0001
            {
                return .critical
            }
            if estimatedFuelAtTripEndLiters <= usableFuelLiters * 0.10 {
                return .warning
            }
            return .sufficient
        }
        guard startingFuelLiters + 0.0001 >= totalRequiredFuelLiters else {
            return .critical
        }
        if estimatedFuelAtTripEndWithoutRefuelLiters
            <= usableFuelLiters * 0.10
        {
            return .warning
        }
        return .sufficient
    }

    static func refuelLoss(
        grossPricePerLiter: Double?,
        homeReferencePerLiter: Double?,
        liters: Double,
        destinationVATPercent: Double?,
        isForeign: Bool
    ) -> Double? {
        guard let grossPricePerLiter, let homeReferencePerLiter else {
            return nil
        }
        guard !isForeign || destinationVATPercent != nil else { return nil }
        let billedLiters = max(0, liters)
        let priceSurcharge = max(
            0,
            grossPricePerLiter - homeReferencePerLiter
        ) * billedLiters

        guard isForeign else { return priceSurcharge }

        // Im Ausland trägt der Nutzer zusätzlich zum Preisaufschlag die im
        // eingegebenen Bruttopreis enthaltene, nicht erstattete lokale MwSt.
        let vatRate = max(0, destinationVATPercent ?? 0) / 100
        let includedVAT = max(0, grossPricePerLiter)
            * vatRate / (1 + vatRate)
            * billedLiters
        return priceSurcharge + includedVAT
    }
}

enum SchengenArea {
    static let countryCodes: Set<String> = [
        "AT", "BE", "BG", "CH", "CZ", "DE", "DK", "EE", "ES", "FI",
        "FR", "GR", "HR", "HU", "IS", "IT", "LI", "LT", "LU", "LV",
        "MT", "NL", "NO", "PL", "PT", "RO", "SE", "SI", "SK"
    ]

    static func contains(countryCode: String) -> Bool {
        countryCodes.contains(
            countryCode
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
        )
    }

    static func crossesBoundary(
        from origin: AirportReference,
        to destination: AirportReference
    ) -> Bool {
        let originCountry = countryCode(for: origin)
        let destinationCountry = countryCode(for: destination)
        guard !originCountry.isEmpty, !destinationCountry.isEmpty else {
            return false
        }
        return contains(countryCode: originCountry)
            != contains(countryCode: destinationCountry)
    }

    static func countryCode(for airport: AirportReference) -> String {
        let explicit = airport.country
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if !explicit.isEmpty { return explicit }

        let icao = airport.icao.uppercased()
        let prefixes: [(String, String)] = [
            ("ED", "DE"), ("LS", "CH"), ("LO", "AT"), ("EB", "BE"),
            ("LF", "FR"), ("EG", "GB"), ("EH", "NL"), ("EK", "DK"),
            ("EN", "NO"), ("ES", "SE"), ("EF", "FI"), ("EI", "IE"),
            ("LK", "CZ"), ("EP", "PL"), ("LZ", "SK"), ("LH", "HU"),
            ("LJ", "SI"), ("LD", "HR"), ("LI", "IT"), ("LE", "ES"),
            ("LP", "PT"), ("LG", "GR"), ("LR", "RO"), ("LB", "BG")
        ]
        return prefixes.first { icao.hasPrefix($0.0) }?.1 ?? ""
    }
}

/// Customs territory is deliberately separate from Schengen. Switzerland
/// participates in Schengen, but not in the EU customs territory.
enum CustomsTerritory {
    private static let euCountryCodes: Set<String> = [
        "AT", "BE", "BG", "CY", "CZ", "DE", "DK", "EE", "ES", "FI",
        "FR", "GR", "HR", "HU", "IE", "IT", "LT", "LU", "LV", "MT",
        "NL", "PL", "PT", "RO", "SE", "SI", "SK"
    ]

    static func identifier(countryCode: String) -> String {
        let normalized = countryCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if euCountryCodes.contains(normalized) { return "EU" }
        // Liechtenstein forms one customs territory with Switzerland.
        if normalized == "CH" || normalized == "LI" { return "CH-LI" }
        return normalized
    }

    static func crossesBoundary(
        from origin: AirportReference,
        to destination: AirportReference
    ) -> Bool {
        let originCountry = SchengenArea.countryCode(for: origin)
        let destinationCountry = SchengenArea.countryCode(for: destination)
        guard !originCountry.isEmpty, !destinationCountry.isEmpty else {
            return false
        }
        return identifier(countryCode: originCountry)
            != identifier(countryCode: destinationCountry)
    }
}

struct CustomsControlCounts: Equatable {
    let entry: Int
    let exit: Int
}

struct CustomsControlAirports {
    let entries: [AirportReference]
    let exits: [AirportReference]
}

enum CustomsFeeRules {
    static func controlAirports(
        routes: [[AirportReference]]
    ) -> CustomsControlAirports {
        var entries: [AirportReference] = []
        var exits: [AirportReference] = []

        for route in routes {
            for (origin, destination) in zip(route, route.dropFirst())
            where CustomsTerritory.crossesBoundary(
                from: origin,
                to: destination
            ) {
                exits.append(origin)
                entries.append(destination)
            }
        }
        return CustomsControlAirports(entries: entries, exits: exits)
    }

    /// Counts customs events at the airport that owns the fee schedule.
    /// Arrival at that airport is an entry, departure from it is an exit.
    static func controls(
        at airportICAO: String,
        routes: [[AirportReference]]
    ) -> CustomsControlCounts {
        let normalizedICAO = airportICAO.uppercased()
        let airports = controlAirports(routes: routes)
        return CustomsControlCounts(
            entry: airports.entries.filter {
                $0.icao.uppercased() == normalizedICAO
            }.count,
            exit: airports.exits.filter {
                $0.icao.uppercased() == normalizedICAO
            }.count
        )
    }
}
