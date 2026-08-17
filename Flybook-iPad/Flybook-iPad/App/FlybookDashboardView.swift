import SwiftUI
import UIKit

private enum DashboardLayout {
    static let sectionGap: CGFloat = 4
}

struct FlybookDashboardView: View {
    let airports: [Airport]
    private let fuelCatalog = AirportFuelCatalog.load()
    private let fuelPriceCatalog = AirportFuelPriceCatalog.load()
    private let featureCatalog = AirportFeatureCatalog.load()

    @AppStorage("ipad.activeBase") private var activeBase = "LSV Mainz"
    @AppStorage("ipad.activeAircraft") private var activeAircraft = "DEZHS"
    @AppStorage("ipad.activeUser") private var activeUser = "Stephan"
    @AppStorage("ipad.destinationICAO") private var destinationICAO = "EDKA"
    @AppStorage("ipad.unitSystem") private var unitSystem = "EU"

    @State private var outboundDeparture = Date.defaultFlightDeparture
    @State private var returnDeparture = Date.now
        .addingTimeInterval(4 * 60 * 60)
        .roundedToNextQuarterHour
    @State private var showsAirportPicker = false
    @State private var showsMigrationNotice = false
    @State private var includeLandingFees = false
    @State private var includeOvernightParkingFee = false
    @State private var includeCustomsEntryFee = false
    @State private var includeCustomsExitFee = false
    @State private var includeHandlingFee = false
    @State private var includeRefuelLoss = false
    @State private var flightDepartureICAO = "EDFZ"
    @State private var flightArrivalICAO = ""
    @State private var selectedAltitudeFeet = 7_000
    @State private var intermediateStopCount = 0
    @State private var intermediateStop1ICAO = ""
    @State private var intermediateStop2ICAO = ""
    @State private var returnIntermediateStopCount = 0
    @State private var returnIntermediateStop1ICAO = ""
    @State private var returnIntermediateStop2ICAO = ""
    @State private var showsRouteMap = false
    @State private var showsFuelCalculator = false
    @State private var isFlightPlanningExpanded = false
    @State private var fuelPlanStartingLiters = 0.0
    @State private var actualStartingFuelLiters = 0.0
    @State private var actualArrivalOverrides: [Int: Double] = [:]
    @State private var actualDepartureOverrides: [Int: Double] = [:]
    @State private var plannedRefuelOverrides: [Int: Double] = [:]
    @State private var actualRefuelOverrides: [Int: Double] = [:]
    @State private var fuelRefuelAfterLegIndices: Set<Int> = []
    @State private var fuelPlanSignature = ""
    @State private var returnSelectedAltitudeFeet = 6_500
    @State private var isNowWeatherLoading = false
    @State private var selectedPage: IPadDashboardPage = .home
    @StateObject private var routeWeather = IPadRouteWeatherRiskViewModel()
    @StateObject private var airportWeather = IPadWeatherViewModel()
    @StateObject private var routeWindModel = IPadRouteWindViewModel()
    @StateObject private var returnRouteWeather = IPadRouteWeatherRiskViewModel()
    @StateObject private var returnAirportWeather = IPadWeatherViewModel()
    @StateObject private var returnRouteWindModel = IPadRouteWindViewModel()
    @StateObject private var exchangeRateModel = ExchangeRateViewModel()

    private var homeAirport: Airport {
        airports.first(where: { $0.icao == "EDFZ" })
            ?? Airport.fallbackEDFZ
    }

    private var destination: Airport {
        airports.first(where: { $0.icao == destinationICAO })
            ?? airports.first(where: { $0.icao == "EDKA" })
            ?? homeAirport
    }

    private var directRouteDistanceNM: Double {
        FlightGeometry.nauticalMiles(
            from: flightDepartureAirport,
            to: flightArrivalAirport
        )
    }

    private var selectedIntermediateAirports: [Airport] {
        [intermediateStop1ICAO, intermediateStop2ICAO]
            .prefix(intermediateStopCount)
            .compactMap { icao in airports.first { $0.icao == icao } }
    }

    private var selectedReturnIntermediateAirports: [Airport] {
        [returnIntermediateStop1ICAO, returnIntermediateStop2ICAO]
            .prefix(returnIntermediateStopCount)
            .compactMap { icao in airports.first { $0.icao == icao } }
    }

    private var priorityAlternateAirports: [Airport] {
        let excluded = Set(routeWaypoints.map(\.icao))
        return Array(airports
            .filter {
                !excluded.contains($0.icao)
                    && ($0.runwayLengthMeters ?? 0) >= 500
            }
            .sorted {
                let lhs = FlightGeometry.nauticalMiles(
                    from: $0,
                    to: flightArrivalAirport
                )
                let rhs = FlightGeometry.nauticalMiles(
                    from: $1,
                    to: flightArrivalAirport
                )
                if abs(lhs - rhs) > 0.01 { return lhs < rhs }
                return $0.icao < $1.icao
            }
            .prefix(3))
    }

    private var priorityWeatherRequests: [(airport: Airport, instant: Date)] {
        let arrival = outboundDeparture.addingTimeInterval(
            TimeInterval(routeMinutes * 60)
        )
        let stopRequests = selectedIntermediateAirports.enumerated().map {
            index, airport in
            let fraction = Double(index + 1)
                / Double(selectedIntermediateAirports.count + 1)
            return (
                airport: airport,
                instant: outboundDeparture.addingTimeInterval(
                    arrival.timeIntervalSince(outboundDeparture) * fraction
                )
            )
        }
        return stopRequests + priorityAlternateAirports.map {
            (airport: $0, instant: arrival)
        }
    }

    private var routeDistanceNM: Double {
        let selected = selectedIntermediateAirports
        if intermediateStopCount > 0, selected.count == intermediateStopCount {
            let points = [flightDepartureAirport] + selected + [flightArrivalAirport]
            let legMiles = zip(points, points.dropFirst()).reduce(0.0) {
                $0 + FlightGeometry.nauticalMiles(from: $1.0, to: $1.1)
            }
            return legMiles * 1.05 + 10
        }
        let extra: Double = intermediateStopCount == 0 ? 10 : (intermediateStopCount == 1 ? 30 : 50)
        return directRouteDistanceNM * 1.05 + extra
    }

    private var routeBlockMinutes: Int {
        IPadFlightMath.minutes(
            directNM: directRouteDistanceNM,
            stopCount: intermediateStopCount,
            headwindKnots: routeWindModel.wind?.headwindKnots,
            tankStopMinutes: 0,
            altitudeFeet: selectedAltitudeFeet,
            departureElevationFeet: flightDepartureAirport.elevationFeet,
            performance: activeAircraftPerformance,
            trackMilesNM: routeDistanceNM,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes
        )
    }

    private var routeMinutes: Int {
        IPadFlightMath.minutes(
            directNM: directRouteDistanceNM,
            stopCount: intermediateStopCount,
            headwindKnots: routeWindModel.wind?.headwindKnots,
            tankStopMinutes: tankStopMinutes,
            altitudeFeet: selectedAltitudeFeet,
            departureElevationFeet: flightDepartureAirport.elevationFeet,
            performance: activeAircraftPerformance,
            trackMilesNM: routeDistanceNM,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes
        )
    }

    private var etopsLegMinutes: Int {
        IPadFlightMath.perLegMinutes(
            totalMinutes: routeMinutes,
            stopCount: intermediateStopCount,
            tankStopMinutes: tankStopMinutes
        )
    }

    private var activeAircraftPerformance: IPadAircraftPerformance {
        IPadAircraftPerformanceStore.profile(named: activeAircraft)
    }

    private var tankStopMinutes: Int {
        activeETOPSProfileValue(name: "tankStopMinutes", legacyKey: "flybookTankStopMinutes", fallback: 60)
    }

    private var preTakeoffGroundMinutes: Int {
        activeETOPSProfileValue(name: "preTakeoffGroundMinutes", legacyKey: "flybookPreTakeoffGroundMinutes", fallback: 5)
    }

    private var postLandingGroundMinutes: Int {
        activeETOPSProfileValue(name: "postLandingGroundMinutes", legacyKey: "flybookPostLandingGroundMinutes", fallback: 3)
    }

    private var reserveMinutes: Int {
        activeETOPSProfileValue(name: "reserveMinutes", legacyKey: "flybookReserveMinutes", fallback: 45)
    }

    private var runwayPerformanceSafetyMarginPercent: Int {
        activeETOPSProfileValue(
            name: "runwayPerformanceSafetyMarginPercent",
            legacyKey: "flybookRunwayPerformanceSafetyMarginPercent",
            fallback: 0
        )
    }

    private var runwayPerformanceProfile: RunwayPerformanceProfile? {
        let normalized = activeAircraft.uppercased()
        guard ["DEUKS", "DEZHS", "A211"].contains(normalized) else {
            return nil
        }
        return RunwayPerformanceProfile(
            maximumTakeoffWeightKilograms:
                activeAircraftPerformance.maximumTakeoffWeightKilograms,
            takeoffRollMeters: 250,
            takeoffOver50FeetMeters: 430,
            landingRollMeters: 210,
            landingOver50FeetMeters: 500
        )
    }

    private func runwayPerformance(
        airport: Airport,
        sample: EDFZWeatherSample?,
        isDeparture: Bool
    ) -> RunwayPerformanceDisplay? {
        guard let profile = runwayPerformanceProfile,
              let densityAltitude = RunwayPerformance.densityAltitudeFeet(
                elevationFeet: Double(airport.elevationFeet),
                temperatureCelsius: sample?.temperatureCelsius,
                pressureHPA: sample?.pressureMSLHPA
              ) else { return nil }
        let headings = airport.referenceRunway.split(separator: "/")
            .compactMap { Double($0.prefix(2)).map { $0 * 10 } }
        let windSpeed = sample?.windSpeedKnots ?? 0
        let windDirection = sample?.windDirectionDegrees ?? 0
        let headwind = headings.map {
            windSpeed * cos((windDirection - $0) * .pi / 180)
        }.max() ?? 0
        let fuelBurn = CharterMath.actualFuelBurnLiters(
            minutes: routeBlockMinutes,
            consumptionLitersPerHour: activeAircraftPerformance.cruise
                .fuelLitersPerHour(at: Double(selectedAltitudeFeet))
                ?? activeAircraftPerformance.fallbackFuelLitersPerHour
        )
        let weight = isDeparture
            ? profile.maximumTakeoffWeightKilograms
            : max(1, profile.maximumTakeoffWeightKilograms - fuelBurn * 0.72)
        let raw = isDeparture
            ? RunwayPerformance.takeoff(
                profile: profile,
                weightKilograms: weight,
                densityAltitudeFeet: densityAltitude,
                headwindKnots: headwind
            )
            : RunwayPerformance.landing(
                profile: profile,
                weightKilograms: weight,
                densityAltitudeFeet: densityAltitude,
                headwindKnots: headwind
            )
        let result = raw.addingSafetyMargin(
            percent: runwayPerformanceSafetyMarginPercent
        )
        let available = isDeparture
            ? airport.runwayLengthMeters
            : (airport.runwayLDAMeters ?? airport.runwayLengthMeters)
        return RunwayPerformanceDisplay(
            result: result,
            availableMeters: available,
            isDeparture: isDeparture
        )
    }

    private var activeETOPSGreenYellowMinutes: Int {
        activeETOPSProfileValue(
            name: "greenYellowMinutes",
            legacyKey: "etopsGreenYellowMinutes",
            fallback: 105
        )
    }

    private var activeETOPSOrangeRedMinutes: Int {
        let configured = activeETOPSProfileValue(
            name: "orangeRedMinutes",
            legacyKey: "etopsOrangeRedMinutes",
            fallback: 150
        )
        return max(activeETOPSGreenYellowMinutes + 10, configured)
    }

    private func activeETOPSProfileValue(
        name: String,
        legacyKey: String,
        fallback: Int
    ) -> Int {
        let profileDefaults = UserDefaults(suiteName: "de.flybook.europe.user-profiles")
        let profileKey = "etopsProfile.\(activeUser).\(name)"
        if let profileDefaults,
           profileDefaults.object(forKey: profileKey) != nil {
            return profileDefaults.integer(forKey: profileKey)
        }
        if activeUser == "Stephan",
           UserDefaults.standard.object(forKey: legacyKey) != nil {
            return UserDefaults.standard.integer(forKey: legacyKey)
        }
        return fallback
    }

    private var routeMapWaypoints: [IPadRouteMapWaypoint] {
        var result = [
            IPadRouteMapWaypoint(
                title: "\(flightDepartureAirport.icao) · \(flightDepartureAirport.name)",
                latitude: flightDepartureAirport.latitude,
                longitude: flightDepartureAirport.longitude,
                role: .departure
            )
        ]

        for index in 0..<intermediateStopCount {
            let selectedICAO = index == 0 ? intermediateStop1ICAO : intermediateStop2ICAO
            if let airport = airports.first(where: { $0.icao == selectedICAO }) {
                result.append(
                    IPadRouteMapWaypoint(
                        title: "\(airport.icao) · \(airport.name)",
                        latitude: airport.latitude,
                        longitude: airport.longitude,
                        role: .stop
                    )
                )
            } else {
                let fraction = intermediateStopCount == 1
                    ? 0.5
                    : (index == 0 ? 1.0 / 3.0 : 2.0 / 3.0)
                let coordinate = FlightGeometry.intermediateCoordinate(
                    from: flightDepartureAirport,
                    to: flightArrivalAirport,
                    fraction: fraction
                )
                result.append(
                    IPadRouteMapWaypoint(
                        title: "Virtueller Stop \(index + 1)",
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude,
                        role: .virtualStop
                    )
                )
            }
        }

        result.append(
            IPadRouteMapWaypoint(
                title: "\(flightArrivalAirport.icao) · \(flightArrivalAirport.name)",
                latitude: flightArrivalAirport.latitude,
                longitude: flightArrivalAirport.longitude,
                role: .arrival
            )
        )
        return result
    }

    private var altitudeOptions: [Int] {
        FlightAltitudeRules.options(forCourseDegrees: routeCourseDegrees)
    }

    private var routeCourseDegrees: Double {
        let firstLegDestination = selectedIntermediateAirports.first ?? flightArrivalAirport
        return FlightGeometry.initialBearing(
            from: flightDepartureAirport,
            to: firstLegDestination
        )
    }

    private var altitudeRuleKey: String {
        let firstLegICAO = selectedIntermediateAirports.first?.icao ?? flightArrivalAirport.icao
        return "\(flightDepartureAirport.icao)-\(firstLegICAO)"
    }

    private var bestLevelFeet: Int {
        FlightAltitudeRules.recommendedOptions(
            forCourseDegrees: routeCourseDegrees
        ).min {
            abs($0 - 7_000) < abs($1 - 7_000)
        } ?? 2_500
    }

    private var destinationAirports: [Airport] {
        airports.filter { $0.icao != "EDFZ" }
    }

    private var destinationFuel: AirportFuelAvailability {
        fuelCatalog.availability(for: destination.icao)
    }

    private var destinationFuelPrices: AirportFuelPrices {
        fuelPriceCatalog.prices(for: destination.icao)
    }

    private var destinationFeatures: [AirportFeature] {
        featureCatalog.features(for: destination.icao)
    }

    private var flightDepartureAirport: Airport {
        airports.first(where: { $0.icao == flightDepartureICAO.uppercased() })
            ?? homeAirport
    }

    private var flightArrivalAirport: Airport {
        airports.first(where: { $0.icao == flightArrivalICAO.uppercased() })
            ?? destination
    }

    private var charterBlockHours: Double {
        CharterMath.commercialDecimalHours(minutes: routeBlockMinutes)
    }

    private var charterFuelLiters: Int {
        let consumption = activeAircraftPerformance.cruise.fuelLitersPerHour(
            at: Double(selectedAltitudeFeet)
        ) ?? activeAircraftPerformance.fallbackFuelLitersPerHour
        return Int(ceil(CharterMath.actualFuelBurnLiters(
            minutes: routeBlockMinutes,
            consumptionLitersPerHour: consumption
        )))
    }

    private var charterCostEUR: Int {
        let defaults = UserDefaults.standard
        let weekday = (2...6).contains(Calendar.current.component(.weekday, from: outboundDeparture))
        let weekdayEnabled = defaults.object(forKey: "flybookWeekdayDiscountEnabled") == nil
            ? true : defaults.bool(forKey: "flybookWeekdayDiscountEnabled")
        let prepaymentFactor = defaults.bool(forKey: "flybookPrepaymentDiscount15To29Enabled")
            ? 0.75
            : (defaults.bool(forKey: "flybookPrepaymentDiscount30PlusEnabled") ? 0.85 : 1)
        let rate = activeAircraftPerformance.hourlyRateEUR
            * prepaymentFactor
            * (weekday && weekdayEnabled ? 0.95 : 1)
        let vat = defaults.object(forKey: "flybookVATPercent") == nil
            ? 7 : defaults.double(forKey: "flybookVATPercent")
        return Int((CharterMath.commercialCost(
            minutes: routeBlockMinutes,
            hourlyRateEUR: rate
        ) * (1 + max(0, vat) / 100)).rounded())
    }

    private var charterRefuelLossEUR: Int? {
        guard includeRefuelLoss else { return 0 }
        let destinationPrice = destinationFuelPrices.mogas?.eurosPerLiter
            ?? destinationFuelPrices.avgas?.eurosPerLiter
        let homePrice = AirportFuelPriceCatalog.referenceEDFZ.mogas?.eurosPerLiter
            ?? AirportFuelPriceCatalog.referenceEDFZ.avgas?.eurosPerLiter
        return CharterMath.refuelLoss(
            grossPricePerLiter: destinationPrice,
            homeReferencePerLiter: homePrice,
            liters: Double(charterFuelLiters),
            destinationVATPercent: destination.countryCode == "DE" ? 19 : nil,
            isForeign: destination.countryCode != "DE"
        ).map { Int($0.rounded()) }
    }

    private var charterMTOWKilograms: Double {
        runwayPerformanceProfile?.maximumTakeoffWeightKilograms ?? 750
    }

    private var charterHasIncreasedNoiseProtection: Bool {
        activeAircraftPerformance.hasIncreasedNoiseProtection
    }

    private var charterNoiseLevelDBA: Double? {
        activeAircraftPerformance.noiseLevelDBA
    }

    private var charterArrivalDate: Date {
        outboundDeparture.addingTimeInterval(TimeInterval(routeMinutes * 60))
    }

    private var charterLandingFeeQuote: IPadCharterFeeQuote {
        guard includeLandingFees else { return IPadCharterFeeQuote() }
        let quote = AirportLandingFeeCalculator.quote(
            for: routeWaypoints.dropFirst().map(\.icao),
            mtowKilograms: charterMTOWKilograms,
            hasIncreasedNoiseProtection: charterHasIncreasedNoiseProtection,
            noiseLevelDBA: charterNoiseLevelDBA,
            landingDate: charterArrivalDate,
            chfToEURRate: exchangeRateModel.chfToEUR?.euroPerCHF
        )
        return IPadCharterFeeQuote(
            knownTotalEUR: quote.knownTotalEUR,
            unknownICAOs: quote.unknownICAOs
        )
    }

    private func charterFixedFeeQuote(
        airports: [Airport],
        amount: (AirportLandingFeeProfile) -> String?
    ) -> IPadCharterFeeQuote {
        airports.reduce(into: IPadCharterFeeQuote()) { result, airport in
            let profile = AirportLandingFeeStore.profile(for: airport.icao)
            if let fee = AirportLandingFeeCalculator.ancillaryFeeEUR(
                profile: profile,
                amountText: amount(profile),
                count: 1,
                chfToEURRate: exchangeRateModel.chfToEUR?.euroPerCHF
            ) {
                result.knownTotalEUR += fee
            } else {
                result.unknownICAOs.append(airport.icao)
            }
        }
    }

    private var charterOvernightFeeQuote: IPadCharterFeeQuote {
        guard includeOvernightParkingFee else { return IPadCharterFeeQuote() }
        let profile = AirportLandingFeeStore.profile(for: flightArrivalAirport.icao)
        let calculatedNights = CharterMath.overnightCount(
            arrival: charterArrivalDate,
            departure: returnDeparture,
            timeZone: TimeZone(identifier: flightArrivalAirport.timeZoneIdentifier)
                ?? .current
        )
        let nights = max(1, calculatedNights)
        guard let fee = AirportLandingFeeCalculator.ancillaryFeeEUR(
            profile: profile,
            amountText: profile.overnightParkingPerNightEUR,
            weightBands: profile.overnightParkingBands,
            mtowKilograms: charterMTOWKilograms,
            count: nights,
            chfToEURRate: exchangeRateModel.chfToEUR?.euroPerCHF
        ) else {
            return IPadCharterFeeQuote(unknownICAOs: [flightArrivalAirport.icao])
        }
        return IPadCharterFeeQuote(knownTotalEUR: fee)
    }

    private var charterCustomsAirports: CustomsControlAirports {
        CustomsFeeRules.controlAirports(
            routes: [routeWaypoints.map(\.sharedReference)]
        )
    }

    private var charterCustomsFeeQuote: IPadCharterFeeQuote {
        var result = IPadCharterFeeQuote()
        if includeCustomsEntryFee {
            let matches = charterCustomsAirports.entries.compactMap { reference in
                airports.first { $0.icao == reference.icao }
            }
            result += charterFixedFeeQuote(
                airports: matches.isEmpty ? [flightArrivalAirport] : matches,
                amount: { $0.customsClearancePerControlEUR }
            )
        }
        if includeCustomsExitFee {
            let matches = charterCustomsAirports.exits.compactMap { reference in
                airports.first { $0.icao == reference.icao }
            }
            result += charterFixedFeeQuote(
                airports: matches.isEmpty ? [flightDepartureAirport] : matches,
                amount: { $0.customsClearancePerControlEUR }
            )
        }
        return result
    }

    private var charterHandlingFeeQuote: IPadCharterFeeQuote {
        guard includeHandlingFee else { return IPadCharterFeeQuote() }
        return charterFixedFeeQuote(
            airports: Array(routeWaypoints.dropFirst()),
            amount: { $0.handlingPerMovementEUR }
        )
    }

    private var charterAirportFeeQuote: IPadCharterFeeQuote {
        charterLandingFeeQuote
            + charterOvernightFeeQuote
            + charterCustomsFeeQuote
            + charterHandlingFeeQuote
    }

    private var charterHasUnknownFees: Bool {
        charterAirportFeeQuote.hasUnknownFees
            || (includeRefuelLoss && charterRefuelLossEUR == nil)
    }

    private var charterKnownFeesEUR: Int {
        Int((
            charterAirportFeeQuote.knownTotalEUR
                + Double(charterRefuelLossEUR ?? 0)
        ).rounded())
    }

    private var charterTotalEUR: Int {
        charterCostEUR + charterKnownFeesEUR
    }

    private var charterFeeDisplayText: String {
        if charterHasUnknownFees {
            return charterKnownFeesEUR > 0
                ? "\(charterKnownFeesEUR) € + ?"
                : "?"
        }
        return charterKnownFeesEUR > 0 ? "\(charterKnownFeesEUR) €" : "—"
    }

    private var charterFeePointText: String {
        var points: [String] = []
        if includeLandingFees { points.append("Landen") }
        if includeOvernightParkingFee { points.append("Parken") }
        if includeCustomsEntryFee { points.append("Zoll ein") }
        if includeCustomsExitFee { points.append("Zoll aus") }
        if includeHandlingFee { points.append("Handling") }
        if includeRefuelLoss { points.append("Tanken") }
        return points.isEmpty ? "Nur Charter" : points.joined(separator: " · ")
    }

    private var routeWaypoints: [Airport] {
        [flightDepartureAirport] + selectedIntermediateAirports + [flightArrivalAirport]
    }

    private var returnRouteWaypoints: [Airport] {
        [flightArrivalAirport]
            + selectedReturnIntermediateAirports
            + [flightDepartureAirport]
    }

    private var returnRouteCourseDegrees: Double {
        guard returnRouteWaypoints.count >= 2 else { return 0 }
        return FlightGeometry.initialBearing(
            from: returnRouteWaypoints[0],
            to: returnRouteWaypoints[1]
        )
    }

    private var returnAltitudeOptions: [Int] {
        FlightAltitudeRules.options(forCourseDegrees: returnRouteCourseDegrees)
    }

    private var returnBestLevelFeet: Int {
        FlightAltitudeRules.recommendedOptions(
            forCourseDegrees: returnRouteCourseDegrees
        ).min {
            abs($0 - 7_000) < abs($1 - 7_000)
        } ?? 3_500
    }

    private var returnRouteMinutes: Int {
        IPadFlightMath.minutes(
            directNM: directRouteDistanceNM,
            stopCount: returnIntermediateStopCount,
            headwindKnots: returnRouteWindModel.wind?.headwindKnots,
            tankStopMinutes: tankStopMinutes,
            altitudeFeet: returnSelectedAltitudeFeet,
            departureElevationFeet: flightArrivalAirport.elevationFeet,
            performance: activeAircraftPerformance,
            trackMilesNM: returnRouteDistanceNM,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes
        )
    }

    private var returnRouteBlockMinutes: Int {
        IPadFlightMath.minutes(
            directNM: directRouteDistanceNM,
            stopCount: returnIntermediateStopCount,
            headwindKnots: returnRouteWindModel.wind?.headwindKnots,
            tankStopMinutes: 0,
            altitudeFeet: returnSelectedAltitudeFeet,
            departureElevationFeet: flightArrivalAirport.elevationFeet,
            performance: activeAircraftPerformance,
            trackMilesNM: returnRouteDistanceNM,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes
        )
    }

    private var returnRouteDistanceNM: Double {
        let selected = selectedReturnIntermediateAirports
        if returnIntermediateStopCount > 0,
           selected.count == returnIntermediateStopCount {
            let points = [flightArrivalAirport] + selected + [flightDepartureAirport]
            let legMiles = zip(points, points.dropFirst()).reduce(0.0) {
                $0 + FlightGeometry.nauticalMiles(from: $1.0, to: $1.1)
            }
            return legMiles * 1.05 + 10
        }
        let extra: Double = returnIntermediateStopCount == 0
            ? 10
            : (returnIntermediateStopCount == 1 ? 30 : 50)
        return directRouteDistanceNM * 1.05 + extra
    }

    private var fuelConsumptionLitersPerHour: Double {
        activeAircraftPerformance.cruise.fuelLitersPerHour(
            at: Double(selectedAltitudeFeet)
        ) ?? activeAircraftPerformance.fallbackFuelLitersPerHour
    }

    private func fuelLegs(
        waypoints: [Airport],
        totalMinutes: Int,
        idPrefix: String,
        consumptionLitersPerHour: Double
    ) -> [FuelPlanLeg] {
        guard waypoints.count >= 2 else { return [] }
        let distances = zip(waypoints, waypoints.dropFirst()).map {
            FlightGeometry.nauticalMiles(from: $0.0, to: $0.1)
        }
        let totalDistance = distances.reduce(0, +)
        let legCount = distances.count
        var remainingMinutes = max(legCount, totalMinutes)
        return distances.indices.map { index in
            let remainingLegs = distances.count - index - 1
            let minutes: Int
            if index == distances.count - 1 {
                minutes = remainingMinutes
            } else if totalDistance > 0 {
                minutes = min(
                    remainingMinutes - remainingLegs,
                    max(1, Int(round(
                        Double(max(legCount, totalMinutes))
                            * distances[index] / totalDistance
                    )))
                )
            } else {
                minutes = max(1, remainingMinutes / (remainingLegs + 1))
            }
            remainingMinutes -= minutes
            return FuelPlanLeg(
                id: "\(idPrefix)-\(index)-\(waypoints[index].icao)-\(waypoints[index + 1].icao)",
                originICAO: waypoints[index].icao,
                destinationICAO: waypoints[index + 1].icao,
                flightMinutes: minutes,
                consumptionLitersPerHour: consumptionLitersPerHour
            )
        }
    }

    private var fuelPlanOutboundLegs: [FuelPlanLeg] {
        fuelLegs(
            waypoints: routeWaypoints,
            totalMinutes: routeBlockMinutes,
            idPrefix: "hin",
            consumptionLitersPerHour: fuelConsumptionLitersPerHour
        )
    }

    private var fuelPlanLegs: [FuelPlanLeg] {
        let returnConsumption = activeAircraftPerformance.cruise
            .fuelLitersPerHour(at: Double(returnSelectedAltitudeFeet))
            ?? activeAircraftPerformance.fallbackFuelLitersPerHour
        return fuelPlanOutboundLegs + fuelLegs(
            waypoints: returnRouteWaypoints,
            totalMinutes: returnRouteBlockMinutes,
            idPrefix: "rueck",
            consumptionLitersPerHour: returnConsumption
        )
    }

    private var fuelMinimumTemplate: FuelPlanResult {
        FuelPlanCalculator.calculate(
            legs: fuelPlanLegs,
            reserveMinutes: reserveMinutes,
            usableFuelLiters: activeAircraftPerformance.usableFuelLiters,
            startingFuelLiters: 0,
            refuelsByLegIndex: Dictionary(
                uniqueKeysWithValues: fuelRefuelAfterLegIndices.map { ($0, 0) }
            )
        )
    }

    private var effectiveFuelPlanStartLiters: Double {
        fuelPlanStartingLiters > 0
            ? fuelPlanStartingLiters
            : fuelMinimumTemplate.minimumStartingFuelLiters
    }

    private var plannedRefuelsByLegIndex: [Int: Double] {
        var additions = Dictionary(
            uniqueKeysWithValues: fuelRefuelAfterLegIndices.map { ($0, 0.0) }
        )
        for _ in 0...fuelRefuelAfterLegIndices.count {
            let draft = FuelPlanCalculator.calculate(
                legs: fuelPlanLegs,
                reserveMinutes: reserveMinutes,
                usableFuelLiters: activeAircraftPerformance.usableFuelLiters,
                startingFuelLiters: effectiveFuelPlanStartLiters,
                refuelsByLegIndex: additions
            )
            for index in fuelRefuelAfterLegIndices {
                additions[index] = plannedRefuelOverrides[index]
                    ?? draft.minimumRefuelLitersByLegIndex[index]
                    ?? 0
            }
        }
        return additions
    }

    private var compactFuelRefuelIndices: Set<Int> {
        guard fuelPlanOutboundLegs.count > 1 else { return [] }
        return Set(fuelRefuelAfterLegIndices.filter {
            $0 >= 0 && $0 < fuelPlanOutboundLegs.count - 1
        })
    }

    private var compactPlannedRefuelsByLegIndex: [Int: Double] {
        plannedRefuelsByLegIndex.filter {
            compactFuelRefuelIndices.contains($0.key)
        }
    }

    private var compactFuelPlanResult: FuelPlanResult {
        FuelPlanCalculator.calculate(
            legs: fuelPlanOutboundLegs,
            reserveMinutes: reserveMinutes,
            usableFuelLiters: activeAircraftPerformance.usableFuelLiters,
            startingFuelLiters: effectiveFuelPlanStartLiters,
            refuelsByLegIndex: compactPlannedRefuelsByLegIndex
        )
    }

    private var compactFuelActualResult: FuelActualResult {
        FuelActualCalculator.calculate(
            plan: compactFuelPlanResult,
            actualStartingFuelLiters: actualStartingFuelLiters > 0
                ? actualStartingFuelLiters
                : effectiveFuelPlanStartLiters,
            actualArrivalOverridesByLegIndex: actualArrivalOverrides,
            actualDepartureOverridesByLegIndex: actualDepartureOverrides,
            actualRefuelOverridesByLegIndex: actualRefuelOverrides,
            refuelAfterLegIndices: compactFuelRefuelIndices
        )
    }

    private var fuelPlanningStateSignature: String {
        fuelPlanLegs.map {
            "\($0.id):\($0.flightMinutes):\($0.consumptionLitersPerHour)"
        }.joined(separator: "|")
            + "|reserve:\(reserveMinutes)|tank:\(activeAircraftPerformance.usableFuelLiters)"
    }

    private func synchronizeFuelPlanDefaults(force: Bool = false) {
        guard force || fuelPlanSignature != fuelPlanningStateSignature else {
            return
        }
        fuelPlanSignature = fuelPlanningStateSignature
        let destinationIndex = max(0, fuelPlanOutboundLegs.count - 1)
        fuelRefuelAfterLegIndices = fuelPlanLegs.indices.contains(destinationIndex + 1)
            ? [destinationIndex]
            : []
        let template = FuelPlanCalculator.calculate(
            legs: fuelPlanLegs,
            reserveMinutes: reserveMinutes,
            usableFuelLiters: activeAircraftPerformance.usableFuelLiters,
            startingFuelLiters: 0,
            refuelsByLegIndex: Dictionary(
                uniqueKeysWithValues: fuelRefuelAfterLegIndices.map { ($0, 0) }
            )
        )
        fuelPlanStartingLiters = template.minimumStartingFuelLiters
        actualStartingFuelLiters = template.minimumStartingFuelLiters
        actualArrivalOverrides = [:]
        actualDepartureOverrides = [:]
        plannedRefuelOverrides = [:]
        actualRefuelOverrides = [:]
        let outboundArrival = outboundDeparture.addingTimeInterval(
            TimeInterval(routeMinutes * 60)
        )
        if returnDeparture <= outboundArrival {
            returnDeparture = outboundArrival.addingTimeInterval(4 * 60 * 60)
        }
    }

    private var compactFuelDestinationRowIndex: Int? {
        guard !fuelPlanOutboundLegs.isEmpty else { return nil }
        return fuelPlanOutboundLegs.count - 1
    }

    private func actualArrivalBinding(index: Int) -> Binding<Double> {
        Binding(
            get: {
                if let override = actualArrivalOverrides[index] {
                    return override
                }
                guard compactFuelActualResult.rows.indices.contains(index) else {
                    return 0
                }
                return compactFuelActualResult.rows[index].actualArrivalLiters
            },
            set: { value in
                actualArrivalOverrides[index] = floor(max(0, value))
            }
        )
    }

    private var routeWeatherRequestKey: String {
        routeWaypoints.map(\.icao).joined(separator: "-")
            + "-\(Int(outboundDeparture.timeIntervalSince1970 / 900))"
            + "-\(routeMinutes)-\(selectedAltitudeFeet)"
    }

    private var flightDataRequestKey: String {
        "\(flightDepartureAirport.icao)-\(flightArrivalAirport.icao)-\(Int(outboundDeparture.timeIntervalSince1970 / 900))-\(selectedAltitudeFeet)-\(activeAircraft)"
    }

    private var returnFlightDataRequestKey: String {
        returnRouteWaypoints.map(\.icao).joined(separator: "-")
            + "-\(Int(returnDeparture.timeIntervalSince1970 / 900))"
            + "-\(returnRouteMinutes)-\(returnSelectedAltitudeFeet)"
            + "-\(activeAircraft)-\(isFlightPlanningExpanded)"
    }

    var body: some View {
        GeometryReader { geometry in
            let canvasWidth = 820.0
            let canvasHeight = 1_080.0
            let scale = min(
                geometry.size.width / canvasWidth,
                geometry.size.height / canvasHeight
            )

            ZStack {
                Color.dashboardBackground
                    .ignoresSafeArea()

                fixedDashboard
                    .frame(
                        width: canvasWidth,
                        height: canvasHeight,
                        alignment: .top
                    )
                    .scaleEffect(scale)
                    .frame(
                        width: canvasWidth * scale,
                        height: canvasHeight * scale
                    )
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .center
            )
        }
        .sheet(isPresented: $showsAirportPicker) {
            AirportPickerSheet(
                airports: airports.filter { $0.icao != "EDFZ" },
                selectedICAO: $destinationICAO
            )
        }
        .fullScreenCover(isPresented: $showsRouteMap) {
            IPadRouteMapSheet(waypoints: routeMapWaypoints)
        }
        .fullScreenCover(isPresented: $showsFuelCalculator) {
            IPadFuelPlanCalculatorView(
                legs: fuelPlanLegs,
                reserveMinutes: reserveMinutes,
                usableFuelLiters: activeAircraftPerformance.usableFuelLiters,
                aircraftName: activeAircraft,
                planStartingFuelLiters: $fuelPlanStartingLiters,
                actualStartingFuelLiters: $actualStartingFuelLiters,
                actualArrivalOverrides: $actualArrivalOverrides,
                actualDepartureOverrides: $actualDepartureOverrides,
                plannedRefuelOverrides: $plannedRefuelOverrides,
                actualRefuelOverrides: $actualRefuelOverrides,
                refuelAfterLegIndices: $fuelRefuelAfterLegIndices
            )
        }
        .alert("Dieser Bereich folgt", isPresented: $showsMigrationNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Die Oberfläche ist vorbereitet. Die bestehende Flybook-Funktion wird in einem der nächsten Migrationsschritte angebunden.")
        }
        .onAppear {
            if flightArrivalICAO.isEmpty {
                flightArrivalICAO = destination.icao
            }
            normalizeSelectedAltitude()
            synchronizeFuelPlanDefaults()
        }
        .onChange(of: destinationICAO) { _, newValue in
            if flightDepartureICAO == "EDFZ" {
                flightArrivalICAO = newValue
            }
        }
        .onChange(of: altitudeRuleKey) { _, _ in
            normalizeSelectedAltitude()
        }
        .onChange(of: fuelPlanningStateSignature) { _, _ in
            synchronizeFuelPlanDefaults()
        }
        .task(id: routeWeatherRequestKey) {
            await routeWeather.load(
                waypoints: routeWaypoints,
                start: outboundDeparture,
                end: outboundDeparture.addingTimeInterval(TimeInterval(routeMinutes * 60)),
                cruiseAltitudeFeet: selectedAltitudeFeet
            )
        }
        .task {
            await exchangeRateModel.refreshIfNeeded()
        }
        .task(id: flightDataRequestKey) {
            let provisionalEnd = outboundDeparture.addingTimeInterval(TimeInterval(routeMinutes * 60))
            await routeWindModel.load(
                origin: flightDepartureAirport,
                destination: flightArrivalAirport,
                start: outboundDeparture,
                end: provisionalEnd,
                altitudeFeet: selectedAltitudeFeet
            )
            let calculatedEnd = outboundDeparture.addingTimeInterval(TimeInterval(routeMinutes * 60))
            await airportWeather.load(
                departureAirport: flightDepartureAirport,
                arrivalAirport: flightArrivalAirport,
                departure: outboundDeparture,
                arrival: calculatedEnd,
                overviewAirport: destination
            )
        }
        .task(id: returnFlightDataRequestKey) {
            guard isFlightPlanningExpanded else { return }
            if !returnAltitudeOptions.contains(returnSelectedAltitudeFeet) {
                returnSelectedAltitudeFeet = returnAltitudeOptions.min {
                    abs($0 - returnSelectedAltitudeFeet)
                        < abs($1 - returnSelectedAltitudeFeet)
                } ?? returnBestLevelFeet
            }
            let end = returnDeparture.addingTimeInterval(
                TimeInterval(returnRouteMinutes * 60)
            )
            async let wind: Void = returnRouteWindModel.load(
                origin: flightArrivalAirport,
                destination: flightDepartureAirport,
                start: returnDeparture,
                end: end,
                altitudeFeet: returnSelectedAltitudeFeet
            )
            async let weather: Void = returnAirportWeather.load(
                departureAirport: flightArrivalAirport,
                arrivalAirport: flightDepartureAirport,
                departure: returnDeparture,
                arrival: end,
                overviewAirport: flightArrivalAirport
            )
            async let risk: Void = returnRouteWeather.load(
                waypoints: returnRouteWaypoints,
                start: returnDeparture,
                end: end,
                cruiseAltitudeFeet: returnSelectedAltitudeFeet
            )
            _ = await (wind, weather, risk)
        }
    }

    private var fixedDashboard: some View {
        VStack(spacing: 6) {
            Group {
                if selectedPage == .home {
                    homeDashboardContent
                } else {
                    IPadMenuPageView(
                        page: selectedPage,
                        airports: airports,
                        destination: destination,
                        selectedDestinationICAO: $destinationICAO,
                        activeBase: $activeBase,
                        activeAircraft: $activeAircraft,
                        activeUser: $activeUser,
                        plannedDeparture: $outboundDeparture
                    )
                }
            }
            .frame(height: 1014, alignment: .top)
            Spacer(minLength: 0)
            bottomMenuBar
                .frame(height: 54)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var homeDashboardContent: some View {
        VStack(spacing: 6) {
            mainHeader
                .frame(height: 64)
                .zIndex(20)
            featureStrip.frame(height: 32)
            airportInformationRow.frame(height: 104)
            if isFlightPlanningExpanded {
                expandedFlightPlanningContent.frame(height: 796, alignment: .top)
            } else {
                fiveDayOverview.frame(height: 146, alignment: .top)
                oneWayFlightSection.frame(height: 340, alignment: .top)
                intermediateStopSection.frame(height: 52, alignment: .top)
                fuelCalculationSection.frame(height: 176, alignment: .top)
            }
        }
    }

    private func normalizeSelectedAltitude() {
        guard !altitudeOptions.contains(selectedAltitudeFeet) else { return }
        selectedAltitudeFeet = altitudeOptions.min {
            abs($0 - selectedAltitudeFeet) < abs($1 - selectedAltitudeFeet)
        } ?? 2_500
    }

    private var mainHeader: some View {
        ZStack {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Button {
                        showsAirportPicker = true
                    } label: {
                        Text(destination.name.uppercased())
                            .font(.system(size: 27, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.dashboardNavy)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 6) {
                        Text(countryFlag(destination.countryCode))
                        Text("·")
                        HeaderDestinationSearch(
                            airports: airports,
                            selectedICAO: $destinationICAO
                        )
                        Text("·  HÖHE \(destination.elevationFeet.formatted()) FT")
                        Button { showsAirportPicker = true } label: {
                            Image(systemName: "chevron.down").font(.caption.bold())
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.dashboardNavy)
                }
                .frame(width: 330, alignment: .leading)
                .zIndex(30)

                Spacer()

                Button {
                    Task { await refreshNowWeather() }
                } label: {
                    VStack(spacing: 1) {
                        if isNowWeatherLoading {
                            ProgressView()
                                .tint(Color.dashboardBlue)
                                .frame(width: 29, height: 29)
                        } else {
                            Image(systemName: "cloud.sun.fill")
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 29, weight: .bold))
                                .frame(width: 36, height: 36)
                                .background(
                                    Color.gray.opacity(0.12),
                                    in: Circle()
                                )
                        }
                        Text("NOW!")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(Color.dashboardNavy)
                    }
                    .frame(width: 64, height: 64)
                    .background(Color.white, in: Circle())
                    .overlay { Circle().stroke(Color.dashboardBlue, lineWidth: 2) }
                }
                .buttonStyle(.plain)
                .disabled(isNowWeatherLoading)
                .accessibilityLabel("Wetter jetzt vollständig aktualisieren")
            }

            HStack(spacing: 7) {
                HeaderNavigationButton(systemName: "chevron.left") {
                    selectDestination(offset: -1)
                }
                HeaderNavigationButton(
                    systemName: "line.3.horizontal.decrease.circle.fill",
                    highlighted: true
                ) {
                    showsMigrationNotice = true
                }
                HeaderNavigationButton(systemName: "chevron.right") {
                    selectDestination(offset: 1)
                }
            }
            .offset(y: 14)

            Menu {
                ForEach(["DEZHS", "DEUKS", "DETIK"], id: \.self) { aircraft in
                    Button(aircraft) { activeAircraft = aircraft }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "airplane")
                    Text(activeAircraft)
                    Image(systemName: "chevron.down")
                        .font(.caption2.bold())
                }
                .font(.caption.bold())
                .foregroundStyle(Color.dashboardNavy)
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.dashboardBlue.opacity(0.45), lineWidth: 1)
                }
            }
            .offset(x: 154, y: 14)
        }
    }

    private var featureStrip: some View {
        HStack(spacing: 7) {
            ForEach(destinationFeatures.prefix(6)) { feature in
                Label(feature.title, systemImage: feature.symbol)
                    .font(.caption.bold())
                    .foregroundStyle(Color.dashboardNavy)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Color.dashboardBlue.opacity(0.11), in: Capsule())
            }
            if destinationFeatures.isEmpty {
                Text("Keine besonderen Flugplatzmerkmale hinterlegt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .clipped()
    }

    private var airportInformationRow: some View {
        DashboardCard {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("RUNWAY", systemImage: "road.lanes")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(destination.runwayDisplay)
                        .font(.title3.bold())
                        .foregroundStyle(Color.dashboardNavy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(destination.runwaySurface.isEmpty ? "Belag unklar" : destination.runwaySurface)
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.dashboardBlue)
                    HStack(spacing: 8) {
                        Text("POE \(destination.portOfEntry)")
                            .foregroundStyle(
                                destination.portOfEntry == "Ja"
                                    ? Color.green
                                    : Color.secondary
                            )
                        if let url = URL(string: destination.aipAeroURL),
                           !destination.aipAeroURL.isEmpty {
                            Link("AIP:Aero", destination: url)
                                .foregroundStyle(Color.dashboardBlue)
                        }
                    }
                    .font(.caption.bold())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 66)
                FuelStatusCell(
                    title: "AVGAS",
                    status: destinationFuel.avgas,
                    price: destinationFuelPrices.avgas,
                    referencePrice: AirportFuelPriceCatalog.referenceEDFZ.avgas,
                    availabilityCheckedAt: destinationFuel.checkedAt
                )
                Divider().frame(height: 66)
                FuelStatusCell(
                    title: "UL91",
                    status: destinationFuel.ul91,
                    price: destinationFuelPrices.ul91,
                    referencePrice: AirportFuelPriceCatalog.referenceEDFZ.ul91,
                    availabilityCheckedAt: destinationFuel.checkedAt
                )
                Divider().frame(height: 66)
                FuelStatusCell(
                    title: "MOGAS",
                    status: destinationFuel.mogas,
                    price: destinationFuelPrices.mogas,
                    referencePrice: AirportFuelPriceCatalog.referenceEDFZ.mogas,
                    availabilityCheckedAt: destinationFuel.checkedAt
                )
            }
        }
    }

    private var fiveDayOverview: some View {
        VStack(alignment: .leading, spacing: DashboardLayout.sectionGap) {
            HStack {
                SectionTitle(title: "5-TAGES-WETTER", systemName: "cloud.sun")
                Spacer()
                Text(airportWeather.isLoading ? "WETTER WIRD GELADEN" : airportWeather.sourceLabel)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }

            DashboardCard {
                VStack(spacing: 4) {
                    ForecastRiskBar(
                        days: airportWeather.days,
                        kind: .fog
                    )
                    HStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { offset in
                            ForecastPlaceholderTile(
                                date: Calendar.current.date(
                                    byAdding: .day,
                                    value: offset,
                                    to: .now
                                ) ?? .now,
                                weather: airportWeather.days.indices.contains(offset)
                                    ? airportWeather.days[offset] : nil
                            )
                        }
                    }
                    ForecastRiskBar(
                        days: airportWeather.days,
                        kind: .wind
                    )
                }
            }
        }
    }

    private var oneWayFlightSection: some View {
        VStack(alignment: .leading, spacing: DashboardLayout.sectionGap) {
            HStack(spacing: 10) {
                SectionTitle(title: "FLUGPLANUNG", systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .layoutPriority(2)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Text("ABFLUG")
                        .font(.caption.bold())
                        .foregroundStyle(Color.dashboardNavy)
                    DatePicker("Datum", selection: $outboundDeparture, displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 112)
                    DatePicker("Startzeit", selection: $outboundDeparture, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 78)
                    departureTimeStepButton(systemName: "minus", minutes: -15)
                    departureTimeStepButton(systemName: "plus", minutes: 15)
                    departureShortcut("Jetzt") { setDepartureNow() }
                    departureShortcut("Heute") { setDepartureDay(offset: 0) }
                    departureShortcut("Morgen") { setDepartureDay(offset: 1) }
                    Button(action: swapFlightEndpoints) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(Color.dashboardBlue)
                    .accessibilityLabel("Abflug und Ziel umdrehen")
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isFlightPlanningExpanded = true
                        }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .heavy))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(Color.dashboardBlue)
                    .accessibilityLabel("Flugplanung vergrößern")
                }
            }
            .frame(height: 42)
            EditableFlightLegCard(
                airports: airports,
                departureICAO: $flightDepartureICAO,
                arrivalICAO: $flightArrivalICAO,
                departure: $outboundDeparture,
                durationMinutes: routeMinutes,
                etopsLegMinutes: etopsLegMinutes,
                etopsGreenYellowMinutes: activeETOPSGreenYellowMinutes,
                etopsOrangeRedMinutes: activeETOPSOrangeRedMinutes,
                distanceNM: routeDistanceNM,
                selectedAltitudeFeet: $selectedAltitudeFeet,
                altitudeOptions: altitudeOptions,
                courseDegrees: routeCourseDegrees,
                bestLevelFeet: bestLevelFeet,
                departureAirport: flightDepartureAirport,
                arrivalAirport: flightArrivalAirport,
                routeRisks: routeWeather.segments,
                foehnWarning: routeWeather.foehnWarning,
                routeHeadwindKnots: routeWindModel.wind?.headwindKnots,
                departureWeatherSample: airportWeather.departureSample,
                arrivalWeatherSample: airportWeather.arrivalSample,
                departurePerformance: runwayPerformance(
                    airport: flightDepartureAirport,
                    sample: airportWeather.departureSample,
                    isDeparture: true
                ),
                arrivalPerformance: runwayPerformance(
                    airport: flightArrivalAirport,
                    sample: airportWeather.arrivalSample,
                    isDeparture: false
                ),
                onArrivalSelected: { airport in
                    destinationICAO = airport.icao
                }
            )
            .frame(height: 294)
        }
    }

    private var expandedFlightPlanningContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                SectionTitle(
                    title: "FLUGPLANUNG · HIN- UND RÜCKFLUG",
                    systemName: "arrow.left.arrow.right"
                )
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isFlightPlanningExpanded = false
                    }
                } label: {
                    Label(
                        "Verkleinern",
                        systemImage: "arrow.down.right.and.arrow.up.left"
                    )
                    .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color.dashboardBlue)
            }
            .frame(height: 28)

            expandedFlightDateControls(
                title: "HINFLUG",
                date: $outboundDeparture,
                airport: flightDepartureAirport
            )
            .frame(height: 28)

            EditableFlightLegCard(
                airports: airports,
                departureICAO: $flightDepartureICAO,
                arrivalICAO: $flightArrivalICAO,
                departure: $outboundDeparture,
                durationMinutes: routeMinutes,
                etopsLegMinutes: etopsLegMinutes,
                etopsGreenYellowMinutes: activeETOPSGreenYellowMinutes,
                etopsOrangeRedMinutes: activeETOPSOrangeRedMinutes,
                distanceNM: routeDistanceNM,
                selectedAltitudeFeet: $selectedAltitudeFeet,
                altitudeOptions: altitudeOptions,
                courseDegrees: routeCourseDegrees,
                bestLevelFeet: bestLevelFeet,
                departureAirport: flightDepartureAirport,
                arrivalAirport: flightArrivalAirport,
                routeRisks: routeWeather.segments,
                foehnWarning: routeWeather.foehnWarning,
                routeHeadwindKnots: routeWindModel.wind?.headwindKnots,
                departureWeatherSample: airportWeather.departureSample,
                arrivalWeatherSample: airportWeather.arrivalSample,
                departurePerformance: runwayPerformance(
                    airport: flightDepartureAirport,
                    sample: airportWeather.departureSample,
                    isDeparture: true
                ),
                arrivalPerformance: runwayPerformance(
                    airport: flightArrivalAirport,
                    sample: airportWeather.arrivalSample,
                    isDeparture: false
                ),
                onArrivalSelected: { destinationICAO = $0.icao }
            )
            .frame(height: 294)

            intermediateStopSection.frame(height: 52, alignment: .top)

            expandedFlightDateControls(
                title: "RÜCKFLUG",
                date: $returnDeparture,
                airport: flightArrivalAirport
            )
            .frame(height: 28)

            EditableFlightLegCard(
                airports: airports,
                departureICAO: Binding(
                    get: { flightArrivalICAO },
                    set: {
                        flightArrivalICAO = $0
                        destinationICAO = $0
                    }
                ),
                arrivalICAO: Binding(
                    get: { flightDepartureICAO },
                    set: { flightDepartureICAO = $0 }
                ),
                departure: $returnDeparture,
                durationMinutes: returnRouteMinutes,
                etopsLegMinutes: IPadFlightMath.perLegMinutes(
                    totalMinutes: returnRouteMinutes,
                    stopCount: returnIntermediateStopCount,
                    tankStopMinutes: tankStopMinutes
                ),
                etopsGreenYellowMinutes: activeETOPSGreenYellowMinutes,
                etopsOrangeRedMinutes: activeETOPSOrangeRedMinutes,
                distanceNM: returnRouteDistanceNM,
                selectedAltitudeFeet: $returnSelectedAltitudeFeet,
                altitudeOptions: returnAltitudeOptions,
                courseDegrees: returnRouteCourseDegrees,
                bestLevelFeet: returnBestLevelFeet,
                departureAirport: flightArrivalAirport,
                arrivalAirport: flightDepartureAirport,
                routeRisks: returnRouteWeather.segments,
                foehnWarning: returnRouteWeather.foehnWarning,
                routeHeadwindKnots: returnRouteWindModel.wind?.headwindKnots,
                departureWeatherSample: returnAirportWeather.departureSample,
                arrivalWeatherSample: returnAirportWeather.arrivalSample,
                departurePerformance: runwayPerformance(
                    airport: flightArrivalAirport,
                    sample: returnAirportWeather.departureSample,
                    isDeparture: true
                ),
                arrivalPerformance: runwayPerformance(
                    airport: flightDepartureAirport,
                    sample: returnAirportWeather.arrivalSample,
                    isDeparture: false
                ),
                onArrivalSelected: { _ in }
            )
            .frame(height: 294)

            returnIntermediateStopSection.frame(height: 52, alignment: .top)
        }
    }

    private func expandedFlightDateControls(
        title: String,
        date: Binding<Date>,
        airport: Airport
    ) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(Color.dashboardNavy)
                .frame(width: 72, alignment: .leading)
            DatePicker("Datum", selection: date, displayedComponents: .date)
                .labelsHidden()
                .frame(width: 112)
            DatePicker("Startzeit", selection: date, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .frame(width: 78)
            flightTimeStepButton(
                systemName: "minus",
                minutes: -15,
                date: date
            )
            flightTimeStepButton(
                systemName: "plus",
                minutes: 15,
                date: date
            )
            departureShortcut("Jetzt") { date.wrappedValue = Date() }
            departureShortcut("Heute") {
                setFlightDay(date, airport: airport, offset: 0)
            }
            departureShortcut("Morgen") {
                setFlightDay(date, airport: airport, offset: 1)
            }
            Spacer(minLength: 0)
        }
    }

    private func departureShortcut(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .font(.system(size: 10, weight: .bold))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(Color.dashboardBlue)
    }

    private func departureTimeStepButton(systemName: String, minutes: Int) -> some View {
        flightTimeStepButton(
            systemName: systemName,
            minutes: minutes,
            date: $outboundDeparture
        )
    }

    private func flightTimeStepButton(
        systemName: String,
        minutes: Int,
        date: Binding<Date>
    ) -> some View {
        Button {
            date.wrappedValue = Calendar.current.date(
                byAdding: .minute,
                value: minutes,
                to: date.wrappedValue
            ) ?? date.wrappedValue
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.dashboardBlue)
                .frame(width: 27, height: 27)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.dashboardBlue.opacity(0.55), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(minutes < 0 ? "Startzeit 15 Minuten früher" : "Startzeit 15 Minuten später")
    }

    private func setDepartureNow() {
        outboundDeparture = Date()
    }

    private func setDepartureDay(offset: Int) {
        setFlightDay(
            $outboundDeparture,
            airport: flightDepartureAirport,
            offset: offset
        )
    }

    private func setFlightDay(
        _ date: Binding<Date>,
        airport: Airport,
        offset: Int
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: airport.timeZoneIdentifier) ?? .current
        let now = Date()
        guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
              let standard = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
        else { return }
        date.wrappedValue = offset == 0 && standard <= now ? now : standard
    }

    private func swapFlightEndpoints() {
        let previousDeparture = flightDepartureICAO
        flightDepartureICAO = flightArrivalICAO
        flightArrivalICAO = previousDeparture
        if let selected = airports.first(where: {
            $0.icao == flightArrivalICAO
        }) {
            destinationICAO = selected.icao
        }
    }

    @MainActor
    private func refreshNowWeather() async {
        guard !isNowWeatherLoading else { return }
        isNowWeatherLoading = true
        defer { isNowWeatherLoading = false }

        let arrival = outboundDeparture.addingTimeInterval(
            TimeInterval(routeMinutes * 60)
        )

        // Phase 1: the operational endpoints become visible first. These
        // point forecasts use the high-priority ICON-Seamless path.
        await airportWeather.loadCriticalEndpoints(
            departureAirport: flightDepartureAirport,
            arrivalAirport: flightArrivalAirport,
            departure: outboundDeparture,
            arrival: arrival
        )

        // Phase 2: real stops and the three nearest usable alternates warm the
        // same cache before route-wide, substantially larger downloads begin.
        await airportWeather.prefetchCriticalAirports(priorityWeatherRequests)

        // Phase 3: corridor weather and winds deliberately run at low network
        // priority so EDGE reception cannot delay endpoint weather.
        async let wind: Void = routeWindModel.load(
            origin: flightDepartureAirport,
            destination: flightArrivalAirport,
            start: outboundDeparture,
            end: arrival,
            altitudeFeet: selectedAltitudeFeet,
            forceRefresh: true,
            priority: .low
        )
        async let risk: Void = routeWeather.load(
            waypoints: routeWaypoints,
            start: outboundDeparture,
            end: arrival,
            cruiseAltitudeFeet: selectedAltitudeFeet,
            forceRefresh: true
        )
        _ = await (wind, risk)
    }

    private struct AutomaticRoute {
        let stopCount: Int
        let firstICAO: String
        let secondICAO: String
        let routeDistanceNM: Double
    }

    private var automaticRouteCandidates: [Airport] {
        airports.filter {
            $0.isTechStop
                && $0.icao != flightDepartureAirport.icao
                && $0.icao != flightArrivalAirport.icao
                && ($0.runwayLengthMeters ?? 0) > 0
        }
    }

    private func routeDistanceNM(via stops: [Airport]) -> Double {
        let points = [flightDepartureAirport] + stops + [flightArrivalAirport]
        let legs = zip(points, points.dropFirst()).reduce(0.0) {
            $0 + FlightGeometry.nauticalMiles(from: $1.0, to: $1.1)
        }
        return legs * 1.05 + 10
    }

    private func estimatedBlockMinutes(routeDistanceNM: Double, stopCount: Int) -> Int {
        IPadFlightMath.minutes(
            directNM: directRouteDistanceNM,
            stopCount: stopCount,
            headwindKnots: routeWindModel.wind?.headwindKnots,
            tankStopMinutes: 0,
            altitudeFeet: selectedAltitudeFeet,
            departureElevationFeet: flightDepartureAirport.elevationFeet,
            performance: activeAircraftPerformance,
            trackMilesNM: routeDistanceNM,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes
        )
    }

    private func optimizedAutomaticRoute(stopCount: Int) -> AutomaticRoute? {
        guard stopCount > 0 else {
            return AutomaticRoute(
                stopCount: 0,
                firstICAO: "",
                secondICAO: "",
                routeDistanceNM: routeDistanceNM(via: [])
            )
        }

        let candidates = automaticRouteCandidates
        guard !candidates.isEmpty else { return nil }
        let direct = directRouteDistanceNM

        if stopCount == 1 {
            let target = FlightGeometry.intermediateCoordinate(
                from: flightDepartureAirport,
                to: flightArrivalAirport,
                fraction: 0.5
            )
            guard let best = candidates.min(by: { lhs, rhs in
                let lhsRoute = routeDistanceNM(via: [lhs])
                let rhsRoute = routeDistanceNM(via: [rhs])
                let lhsScore = (lhsRoute - direct) * 4
                    + FlightGeometry.nauticalMiles(from: lhs, to: target)
                let rhsScore = (rhsRoute - direct) * 4
                    + FlightGeometry.nauticalMiles(from: rhs, to: target)
                if abs(lhsScore - rhsScore) > 0.01 { return lhsScore < rhsScore }
                return lhs.icao < rhs.icao
            }) else { return nil }
            return AutomaticRoute(
                stopCount: 1,
                firstICAO: best.icao,
                secondICAO: "",
                routeDistanceNM: routeDistanceNM(via: [best])
            )
        }

        let firstTarget = FlightGeometry.intermediateCoordinate(
            from: flightDepartureAirport,
            to: flightArrivalAirport,
            fraction: 1.0 / 3.0
        )
        let secondTarget = FlightGeometry.intermediateCoordinate(
            from: flightDepartureAirport,
            to: flightArrivalAirport,
            fraction: 2.0 / 3.0
        )
        var best: (score: Double, first: Airport, second: Airport, route: Double)?
        for first in candidates {
            for second in candidates where second.icao != first.icao {
                let route = routeDistanceNM(via: [first, second])
                let firstLeg = FlightGeometry.nauticalMiles(from: flightDepartureAirport, to: first)
                let middleLeg = FlightGeometry.nauticalMiles(from: first, to: second)
                let finalLeg = FlightGeometry.nauticalMiles(from: second, to: flightArrivalAirport)
                let idealLeg = (firstLeg + middleLeg + finalLeg) / 3
                let balanceError = abs(firstLeg - idealLeg)
                    + abs(middleLeg - idealLeg)
                    + abs(finalLeg - idealLeg)
                let targetError = FlightGeometry.nauticalMiles(from: first, to: firstTarget)
                    + FlightGeometry.nauticalMiles(from: second, to: secondTarget)
                let score = (route - direct) * 4 + balanceError * 2 + targetError
                if best == nil || score < best!.score {
                    best = (score, first, second, route)
                }
            }
        }
        guard let best else { return nil }
        return AutomaticRoute(
            stopCount: 2,
            firstICAO: best.first.icao,
            secondICAO: best.second.icao,
            routeDistanceNM: best.route
        )
    }

    private func applyAutomaticETOPSRoute() {
        for count in 0...2 {
            guard let route = optimizedAutomaticRoute(stopCount: count) else { continue }
            let block = estimatedBlockMinutes(
                routeDistanceNM: route.routeDistanceNM,
                stopCount: count
            )
            let perLeg = Int((Double(block) / Double(count + 1)).rounded())
            if perLeg < activeETOPSOrangeRedMinutes || count == 2 {
                intermediateStopCount = route.stopCount
                intermediateStop1ICAO = route.firstICAO
                intermediateStop2ICAO = route.secondICAO
                return
            }
        }
    }

    private var intermediateStopSection: some View {
        stopSection(
            count: $intermediateStopCount,
            firstICAO: $intermediateStop1ICAO,
            secondICAO: $intermediateStop2ICAO,
            origin: flightDepartureAirport,
            destination: flightArrivalAirport,
            showsOutboundActions: true
        )
    }

    private var returnIntermediateStopSection: some View {
        stopSection(
            count: $returnIntermediateStopCount,
            firstICAO: $returnIntermediateStop1ICAO,
            secondICAO: $returnIntermediateStop2ICAO,
            origin: flightArrivalAirport,
            destination: flightDepartureAirport,
            showsOutboundActions: false
        )
    }

    private func stopSection(
        count: Binding<Int>,
        firstICAO: Binding<String>,
        secondICAO: Binding<String>,
        origin: Airport,
        destination: Airport,
        showsOutboundActions: Bool
    ) -> some View {
        DashboardCard {
            HStack(spacing: 8) {
                Text("Stops:")
                    .font(.caption.bold())
                    .foregroundStyle(Color.dashboardNavy)

                Picker("Anzahl Zwischenstopps", selection: count) {
                    Text("0").tag(0)
                    Text("1").tag(1)
                    Text("2").tag(2)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 120)

                Group {
                    if count.wrappedValue >= 1 {
                        StopAirportPicker(
                            title: "STOP 1",
                            selection: firstICAO,
                            airports: airports,
                            excluding: [origin.icao, destination.icao]
                                + (count.wrappedValue == 2 ? [secondICAO.wrappedValue] : []),
                            origin: origin,
                            destination: destination,
                            stopCount: count.wrappedValue,
                            stopIndex: 1
                        )
                    } else {
                        Text("Direktflug")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 220, alignment: .leading)

                Group {
                    if count.wrappedValue == 2 {
                            StopAirportPicker(
                                title: "STOP 2",
                                selection: secondICAO,
                                airports: airports,
                                excluding: [origin.icao, destination.icao, firstICAO.wrappedValue],
                                origin: origin,
                                destination: destination,
                                stopCount: count.wrappedValue,
                                stopIndex: 2
                            )
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
                .frame(width: 220, alignment: .leading)

                Spacer(minLength: 0)

                if showsOutboundActions {
                    Button {
                        applyAutomaticETOPSRoute()
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.dashboardBlue)
                            .frame(width: 38, height: 32)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.dashboardBlue.opacity(0.55), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ETOPS-Route automatisch planen")

                    Button {
                        showsRouteMap = true
                    } label: {
                        Image(systemName: "globe.europe.africa.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 32)
                            .background(Color.dashboardBlue, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Streckenkarte öffnen")
                } else {
                    Text("Rückflugroute")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 82, alignment: .trailing)
                }
            }
        }
        .zIndex(12)
    }

    private var fuelCalculationSection: some View {
        VStack(alignment: .leading, spacing: DashboardLayout.sectionGap) {
            HStack {
                SectionTitle(title: "TANKKALKULATION", systemName: "fuelpump.fill")
                Text("\(flightDepartureAirport.icao) → \(flightArrivalAirport.icao)")
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showsFuelCalculator = true
                } label: {
                    Label("Tankrechner öffnen", systemImage: "fuelpump.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color.dashboardBlue)
            }
            .frame(height: 27)

            DashboardCard {
                HStack(alignment: .top, spacing: 8) {
                    compactFuelStatePanel(title: "MINIMUM", tint: .gray) {
                        FuelCompactMetric(
                            title: "T/O",
                            value: compactFuelPlanResult.rows.first.map {
                                "\(Int($0.minimumDepartureLiters)) L"
                            } ?? "—"
                        )
                        FuelCompactMetric(
                            title: "LDG",
                            value: compactFuelPlanResult.rows.last.map {
                                "\(Int($0.minimumArrivalLiters)) L"
                            } ?? "—"
                        )
                    }
                    compactFuelStatePanel(title: "PLAN", tint: Color.dashboardBlue) {
                        FuelCompactMetric(
                            title: "T/O",
                            value: "\(Int(effectiveFuelPlanStartLiters)) L"
                        )
                        FuelCompactMetric(
                            title: "LDG",
                            value: compactFuelPlanResult.rows.last.map {
                                "\(Int($0.plannedArrivalLiters)) L"
                            } ?? "—"
                        )
                    }
                    compactFuelStatePanel(
                        title: "IST",
                        tint: compactFuelActualResult.hasWarning ? .red : .green
                    ) {
                        FuelCompactInput(
                            title: "T/O",
                            value: $actualStartingFuelLiters
                        )
                        if let index = compactFuelDestinationRowIndex {
                            FuelCompactInput(
                                title: "LDG",
                                value: actualArrivalBinding(index: index)
                            )
                        } else {
                            FuelCompactMetric(title: "LDG", value: "—")
                        }
                    }
                }
            }
            .frame(height: 145)
        }
    }

    private func compactFuelStatePanel<Content: View>(
        title: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(tint)
            HStack(spacing: 6) {
                content()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 106, maxHeight: 106)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(0.45), lineWidth: 1)
        }
    }

    private var charterCalculationSection: some View {
        VStack(alignment: .leading, spacing: DashboardLayout.sectionGap) {
            HStack {
                SectionTitle(title: "CHARTERKALKULATION", systemName: "eurosign.circle")
                Spacer()
                Menu {
                    Toggle("Landegebühr", isOn: $includeLandingFees)
                    Toggle("Übernachtungsgebühr", isOn: $includeOvernightParkingFee)
                    Toggle("Zoll Einreise", isOn: $includeCustomsEntryFee)
                    Toggle("Zoll Ausreise", isOn: $includeCustomsExitFee)
                    Toggle("Handling", isOn: $includeHandlingFee)
                    Toggle("Tankkostendifferenz", isOn: $includeRefuelLoss)
                } label: {
                    Label("Kostenpunkte", systemImage: "checklist")
                        .font(.caption.bold())
                        .foregroundStyle(Color.dashboardBlue)
                }
            }
            .frame(height: 27)
            DashboardCard {
                VStack(spacing: 3) {
                HStack {
                    CharterColumnHeader("STRECKE NM")
                    CharterColumnHeader("BLOCKZEIT")
                    CharterColumnHeader("KRAFTSTOFF")
                    CharterColumnHeader("GEBÜHREN")
                    CharterColumnHeader("CHARTER")
                }

                HStack(spacing: 8) {
                    CharterValueBox(value: "\(Int(routeDistanceNM.rounded())) NM")
                    CharterValueBox(value: charterBlockHours.formatted(.number.precision(.fractionLength(1))) + " h")
                    CharterValueBox(value: "\(charterFuelLiters) L", accent: .green)
                    CharterValueBox(value: charterFeeDisplayText)
                    CharterValueBox(value: "\(charterTotalEUR) €")
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("GESAMT HINFLUG")
                            .font(.subheadline.bold())
                        Text(charterFeePointText)
                            .font(.system(size: 8.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.dashboardNavy)
                    Spacer()
                    Text(charterHasUnknownFees
                        ? "\(charterTotalEUR) € + ?"
                        : "\(charterTotalEUR) €")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(Color.dashboardNavy)
                }
                .padding(.horizontal, 4)
                .frame(height: 29)
                }
            }
            .frame(height: 115)
        }
    }

    private var bottomMenuBar: some View {
        HStack(spacing: 0) {
            menuButton(.home, systemName: "house.fill", label: "Hauptseite")
            menuButton(.destinationFinder, systemName: "airplane.arrival", label: "Destination Finder")
            menuButton(.alternates, systemName: "signpost.right.and.left", label: "Alternates")
            menuButton(.reservations, systemName: "calendar.badge.clock", label: "Reservierungen")
            menuButton(.base, systemName: "building.2", label: "Basis")
            menuButton(.aircraft, systemName: "airplane", label: "Flugzeug")
            menuButton(.setup, systemName: "gearshape", label: "Setup")
        }
        .padding(.horizontal, 6)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black.opacity(0.09), lineWidth: 1)
        }
    }

    private func menuButton(
        _ page: IPadDashboardPage,
        systemName: String,
        label: String
    ) -> some View {
        BottomMenuButton(
            systemName: systemName,
            label: label,
            selected: selectedPage == page
        ) {
            selectedPage = page
        }
    }

    private func selectDestination(offset: Int) {
        guard !destinationAirports.isEmpty else { return }
        let current = destinationAirports.firstIndex(where: { $0.icao == destination.icao }) ?? 0
        let next = (current + offset + destinationAirports.count) % destinationAirports.count
        destinationICAO = destinationAirports[next].icao
    }

    private var destinationHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                showsAirportPicker = true
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(destination.name.uppercased())
                        .font(.system(size: 31, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.dashboardNavy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    HStack(spacing: 7) {
                        Text(countryFlag(destination.countryCode))
                        Text("·")
                        Text(destination.icao)
                        Text("·")
                        Text("HÖHE \(destination.elevationFeet.formatted()) FT")
                        Image(systemName: "chevron.down")
                            .font(.caption.bold())
                    }
                    .font(.headline)
                    .foregroundStyle(Color.dashboardNavy)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                showsMigrationNotice = true
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "cloud.sun.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 30, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(Color.gray.opacity(0.12), in: Circle())
                    Text("NOW!")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(Color.dashboardNavy)
                }
                .frame(width: 66, height: 66)
                .background(Color.white, in: Circle())
                .overlay {
                    Circle().stroke(Color.dashboardBlue, lineWidth: 2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Wetter jetzt vollständig aktualisieren")
        }
        .padding(.top, 2)
    }

    private var setupPanel: some View {
        DashboardCard {
            HStack(spacing: 10) {
                CompactSetupPicker(
                    title: "BASIS",
                    icon: "building.2",
                    selection: $activeBase,
                    options: ["LSV Mainz"]
                )
                Divider().frame(height: 42)
                CompactSetupPicker(
                    title: "FLUGZEUG",
                    icon: "airplane",
                    selection: $activeAircraft,
                    options: ["DEZHS", "DEUKS", "DETIK"]
                )
                Divider().frame(height: 42)
                CompactSetupPicker(
                    title: "NUTZER",
                    icon: "person",
                    selection: $activeUser,
                    options: ["Stephan", "Maria"]
                )
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            DashboardIconButton(
                systemName: "airplane.arrival",
                accessibilityLabel: "Destination Finder",
                action: { showsMigrationNotice = true }
            )
            DashboardIconButton(
                systemName: "signpost.right.and.left",
                accessibilityLabel: "Alternates",
                action: { showsMigrationNotice = true }
            )
            DashboardIconButton(
                systemName: "calendar.badge.clock",
                accessibilityLabel: "Reservierungen",
                action: { showsMigrationNotice = true }
            )
            DashboardIconButton(
                systemName: "gearshape",
                accessibilityLabel: "Setup",
                action: { showsMigrationNotice = true }
            )

            Spacer(minLength: 4)

            Picker("Einheitensystem", selection: $unitSystem) {
                Text("🇪🇺").tag("EU")
                Text("🇺🇸").tag("US")
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 118)
            .accessibilityLabel("Einheitensystem")
        }
        .padding(.horizontal, 4)
    }

    private var airportSummary: some View {
        DashboardCard {
            HStack(spacing: 0) {
                SummaryMetric(
                    title: "RUNWAY",
                    value: destination.runwayDisplay,
                    icon: "road.lanes"
                )
                Divider().frame(height: 52)
                SummaryMetric(
                    title: "DISTANZ",
                    value: "\(Int(routeDistanceNM.rounded())) NM",
                    icon: "location"
                )
                Divider().frame(height: 52)
                SummaryMetric(
                    title: "TECHSTOP",
                    value: destination.isTechStop ? "JA" : "–",
                    icon: "fuelpump"
                )
            }
        }
    }

    private var flightPlanningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "FLUGPLANUNG", systemName: "point.topleft.down.to.point.bottomright.curvepath")

            FlightLegCard(
                title: "HINFLUG",
                departureAirport: homeAirport,
                arrivalAirport: destination,
                departure: $outboundDeparture,
                durationMinutes: routeMinutes,
                distanceNM: routeDistanceNM
            )
            .frame(height: 154)
            .clipped()

            FlightLegCard(
                title: "RÜCKFLUG",
                departureAirport: destination,
                arrivalAirport: homeAirport,
                departure: $returnDeparture,
                durationMinutes: routeMinutes,
                distanceNM: routeDistanceNM
            )
            .frame(height: 154)
            .clipped()
        }
    }

    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: "5-TAGES-WETTER", systemName: "cloud.sun")
                Spacer()
                Text("ICON-SEAMLESS · NOCH NICHT VERBUNDEN")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }

            DashboardCard {
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { offset in
                            ForecastPlaceholderTile(
                                date: Calendar.current.date(
                                    byAdding: .day,
                                    value: offset,
                                    to: .now
                                ) ?? .now,
                                weather: nil
                            )
                        }
                    }

                    Divider()

                    HStack {
                        Label("FOG RISK 06–22 UHR", systemImage: "cloud.fog")
                        Spacer()
                        Text("Wetteranbindung folgt")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                }
            }

            DashboardCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("10-TAGES-WETTER")
                            .font(.headline.bold())
                            .foregroundStyle(Color.dashboardNavy)
                        Text("Tagesmittel aus 08 / 14 / 20 Uhr")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "calendar.badge.clock")
                        .font(.title2)
                        .foregroundStyle(Color.dashboardBlue)
                }
            }
        }
    }

    private func countryFlag(_ countryCode: String) -> String {
        countryCode.uppercased().unicodeScalars.compactMap {
            Unicode.Scalar(127_397 + $0.value).map(String.init)
        }.joined()
    }
}

private struct HeaderNavigationButton: View {
    let systemName: String
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 42, height: 38)
                .background(
                    highlighted ? Color.dashboardBlue : Color.dashboardNavy,
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct HeaderDestinationSearch: View {
    let airports: [Airport]
    @Binding var selectedICAO: String

    @State private var query = ""
    @FocusState private var focused: Bool

    private var suggestions: [Airport] {
        guard query.count >= 3 else { return [] }
        return Array(
            airports.filter {
                $0.icao.hasPrefix(query.uppercased())
                    || $0.name.localizedCaseInsensitiveContains(query)
            }.prefix(4)
        )
    }

    var body: some View {
        TextField("ICAO", text: $query)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .font(.subheadline.bold().monospaced())
            .foregroundStyle(Color.dashboardBlue)
            .frame(width: 54)
            .focused($focused)
            .onAppear { query = selectedICAO }
            .onChange(of: selectedICAO) { _, value in
                if !focused { query = value }
            }
            .onChange(of: query) { _, value in
                let normalized = String(value.uppercased().prefix(4))
                if normalized != value {
                    query = normalized
                    return
                }
                if let airport = airports.first(where: { $0.icao == normalized }) {
                    selectedICAO = airport.icao
                }
            }
            .overlay(alignment: .topLeading) {
                if focused, !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions) { airport in
                            Button {
                                query = airport.icao
                                selectedICAO = airport.icao
                                focused = false
                            } label: {
                                Text("\(airport.icao) · \(airport.name)")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.dashboardNavy)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .frame(width: 230, height: 30, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.dashboardBlue.opacity(0.4)) }
                    .shadow(radius: 7)
                    .offset(y: 25)
                    .zIndex(100)
                }
            }
    }
}

private struct FuelStatusCell: View {
    let title: String
    let status: FuelAvailabilityStatus
    let price: FuelPricePoint?
    let referencePrice: FuelPricePoint?
    let availabilityCheckedAt: String?

    private var color: Color {
        switch status {
        case .available: return .green
        case .unavailable: return .red
        case .check: return .orange
        }
    }

    private var priceText: String {
        guard let price else { return "Preis nicht hinterlegt" }
        let formatted = String(format: "%.2f", price.eurosPerLiter)
            .replacingOccurrences(of: ".", with: ",")
        guard let referencePrice else { return "\(formatted) €/L" }
        let delta = price.eurosPerLiter - referencePrice.eurosPerLiter
        let difference = String(format: "%+.2f", delta)
            .replacingOccurrences(of: ".", with: ",")
        return "\(formatted) €/L (\(difference))"
    }

    private var dateText: String {
        "Stand \(price?.checkedAt ?? availabilityCheckedAt ?? "unklar")"
    }

    var body: some View {
        VStack(spacing: 3) {
            Label(title, systemImage: "fuelpump.fill")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                Text(status.label)
                    .font(.subheadline.bold())
                    .foregroundStyle(color)
            }
            Text(priceText)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.dashboardNavy)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(dateText)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CharterColumnHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct StopAirportPicker: View {
    let title: String
    @Binding var selection: String
    let airports: [Airport]
    let excluding: [String]
    let origin: Airport
    let destination: Airport
    let stopCount: Int
    let stopIndex: Int
    @State private var query = ""
    @FocusState private var queryIsFocused: Bool

    private var targetCoordinate: (latitude: Double, longitude: Double) {
        let fraction = stopCount <= 1 ? 0.5 : (stopIndex == 1 ? 1.0 / 3.0 : 2.0 / 3.0)
        return FlightGeometry.intermediateCoordinate(
            from: origin,
            to: destination,
            fraction: fraction
        )
    }

    private var options: [Airport] {
        airports
            .filter { airport in
                !excluding.contains(airport.icao)
                    && (airport.isTechStop || airport.runwayLengthMeters != nil)
            }
            .sorted {
                let lhsDistance = FlightGeometry.nauticalMiles(from: $0, to: targetCoordinate)
                let rhsDistance = FlightGeometry.nauticalMiles(from: $1, to: targetCoordinate)
                if abs(lhsDistance - rhsDistance) > 0.01 { return lhsDistance < rhsDistance }
                return $0.icao < $1.icao
            }
    }

    private var suggestions: [Airport] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return Array(options.filter {
            $0.icao.localizedCaseInsensitiveContains(term)
                || $0.name.localizedCaseInsensitiveContains(term)
        }.prefix(5))
    }

    private var showsSuggestions: Bool {
        queryIsFocused && !query.isEmpty && !suggestions.isEmpty
    }

    private func choose(_ airport: Airport?) {
        selection = airport?.icao ?? ""
        query = airport?.icao ?? ""
        queryIsFocused = false
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    TextField("Virtuell / ICAO", text: $query)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.dashboardNavy)
                        .lineLimit(1)
                        .padding(.leading, 8)
                        .focused($queryIsFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            let normalized = query
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .uppercased()
                            if let exact = options.first(where: { $0.icao == normalized }) {
                                choose(exact)
                            } else if let airport = suggestions.first {
                                choose(airport)
                            }
                        }

                    Menu {
                        Button("Virtuell · Modellroute") { choose(nil) }
                        ForEach(options) { airport in
                            Button("\(airport.icao) · \(airport.name)") {
                                choose(airport)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.dashboardBlue)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 172, height: 28)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.dashboardBlue.opacity(0.45), lineWidth: 1)
                }

                if showsSuggestions {
                    VStack(spacing: 0) {
                        ForEach(suggestions) { airport in
                            Button {
                                choose(airport)
                            } label: {
                                HStack(spacing: 5) {
                                    Text(airport.icao).fontWeight(.heavy)
                                    Text(airport.name)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer(minLength: 0)
                                }
                                .font(.system(size: 10))
                                .foregroundStyle(Color.dashboardNavy)
                                .padding(.horizontal, 8)
                                .frame(width: 205, height: 28)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if airport.id != suggestions.last?.id { Divider() }
                        }
                    }
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Color.dashboardBlue.opacity(0.42), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                    .offset(y: 31)
                    .zIndex(30)
                }
            }
            .frame(width: 172, height: 28, alignment: .topLeading)
        }
        .onAppear { query = selection }
        .onChange(of: selection) { _, newValue in
            if query.uppercased() != newValue.uppercased() { query = newValue }
        }
        .onChange(of: query) { _, newValue in
            let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if normalized.isEmpty {
                selection = ""
            } else if let airport = options.first(where: { $0.icao == normalized }) {
                selection = airport.icao
            }
        }
        .zIndex(showsSuggestions ? 30 : 1)
    }
}

private struct CharterValueBox: View {
    let value: String
    var accent: Color = Color.dashboardNavy

    var body: some View {
        Text(value)
            .font(.headline.bold().monospacedDigit())
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
            .background(Color.dashboardBackground, in: RoundedRectangle(cornerRadius: 12))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct SelectAllFuelField: UIViewRepresentable {
    @Binding var value: Double
    var fontSize: CGFloat = 14

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SelectAllFuelField

        init(_ parent: SelectAllFuelField) {
            self.parent = parent
        }

        @objc func valueChanged(_ field: UITextField) {
            let normalized = (field.text ?? "")
                .replacingOccurrences(of: ",", with: ".")
            if let number = Double(normalized) {
                parent.value = max(0, number)
            }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                textField.selectAll(nil)
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            valueChanged(textField)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .numberPad
        field.textAlignment = .right
        field.font = .monospacedDigitSystemFont(
            ofSize: fontSize,
            weight: .heavy
        )
        field.adjustsFontSizeToFitWidth = true
        field.minimumFontSize = 10
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .editingChanged
        )
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.keyboardType != .numberPad {
            field.keyboardType = .numberPad
            if field.isFirstResponder { field.reloadInputViews() }
        }
        guard !field.isFirstResponder else { return }
        let displayed = String(Int(floor(max(0, value) + 0.000_001)))
        if field.text != displayed { field.text = displayed }
    }
}

private struct FuelCompactMetric: View {
    let title: String
    let value: String
    var accent: Color = Color.dashboardNavy

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 15, weight: .heavy).monospacedDigit())
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.dashboardBlue.opacity(0.55), lineWidth: 1)
        }
    }
}

private struct FuelCompactInput: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                SelectAllFuelField(value: $value, fontSize: 15)
                Text("L")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.dashboardBlue.opacity(0.55), lineWidth: 1)
        }
    }
}

private struct IPadFuelPlanCalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    let legs: [FuelPlanLeg]
    let reserveMinutes: Int
    let usableFuelLiters: Double
    let aircraftName: String
    @Binding var planStartingFuelLiters: Double
    @Binding var actualStartingFuelLiters: Double
    @Binding var actualArrivalOverrides: [Int: Double]
    @Binding var actualDepartureOverrides: [Int: Double]
    @Binding var plannedRefuelOverrides: [Int: Double]
    @Binding var actualRefuelOverrides: [Int: Double]
    @Binding var refuelAfterLegIndices: Set<Int>
    @State private var actualStartWasEdited = false

    private var candidates: [Int] {
        FuelPlanCalculator.refuelCandidateIndices(legs: legs)
    }

    private var template: FuelPlanResult {
        FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: reserveMinutes,
            usableFuelLiters: usableFuelLiters,
            startingFuelLiters: 0,
            refuelsByLegIndex: Dictionary(
                uniqueKeysWithValues: refuelAfterLegIndices.map { ($0, 0) }
            )
        )
    }

    private var effectivePlanStart: Double {
        planStartingFuelLiters > 0
            ? planStartingFuelLiters
            : template.minimumStartingFuelLiters
    }

    private var plannedRefuels: [Int: Double] {
        var additions = Dictionary(
            uniqueKeysWithValues: refuelAfterLegIndices.map { ($0, 0.0) }
        )
        for _ in 0...refuelAfterLegIndices.count {
            let draft = FuelPlanCalculator.calculate(
                legs: legs,
                reserveMinutes: reserveMinutes,
                usableFuelLiters: usableFuelLiters,
                startingFuelLiters: effectivePlanStart,
                refuelsByLegIndex: additions
            )
            for index in refuelAfterLegIndices {
                additions[index] = plannedRefuelOverrides[index]
                    ?? draft.minimumRefuelLitersByLegIndex[index]
                    ?? 0
            }
        }
        return additions
    }

    private var plan: FuelPlanResult {
        FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: reserveMinutes,
            usableFuelLiters: usableFuelLiters,
            startingFuelLiters: effectivePlanStart,
            refuelsByLegIndex: plannedRefuels
        )
    }

    private var actual: FuelActualResult {
        FuelActualCalculator.calculate(
            plan: plan,
            actualStartingFuelLiters: actualStartingFuelLiters,
            actualArrivalOverridesByLegIndex: actualArrivalOverrides,
            actualDepartureOverridesByLegIndex: actualDepartureOverrides,
            actualRefuelOverridesByLegIndex: actualRefuelOverrides,
            refuelAfterLegIndices: refuelAfterLegIndices
        )
    }

    private func actualArrivalBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                if let override = actualArrivalOverrides[index] {
                    return override
                }
                guard actual.rows.indices.contains(index) else { return 0 }
                return actual.rows[index].actualArrivalLiters
            },
            set: { value in
                let normalized = floor(max(0, value))
                actualArrivalOverrides[index] = normalized
                let nextIndex = index + 1
                if refuelAfterLegIndices.contains(index),
                   let measuredDeparture = actualDepartureOverrides[nextIndex] {
                    actualRefuelOverrides[index] = floor(max(
                        0,
                        measuredDeparture - normalized
                    ))
                }
            }
        )
    }

    private func actualDepartureBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                if index == 0 { return actualStartingFuelLiters }
                if let override = actualDepartureOverrides[index] {
                    return override
                }
                guard actual.rows.indices.contains(index) else { return 0 }
                return actual.rows[index].actualDepartureLiters
            },
            set: { value in
                let normalized = floor(max(0, value))
                actualStartWasEdited = true
                if index == 0 {
                    actualStartingFuelLiters = normalized
                } else {
                    actualDepartureOverrides[index] = normalized
                    let previousIndex = index - 1
                    if refuelAfterLegIndices.contains(previousIndex),
                       actual.rows.indices.contains(previousIndex) {
                        actualRefuelOverrides[previousIndex] = floor(max(
                            0,
                            normalized - actual.rows[previousIndex].actualArrivalLiters
                        ))
                    }
                }
            }
        )
    }

    private func plannedRefuelBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { plannedRefuels[index] ?? 0 },
            set: { plannedRefuelOverrides[index] = floor(max(0, $0)) }
        )
    }

    private func actualRefuelBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                actualRefuelOverrides[index]
                    ?? actual.rows[index].actualRefuelAfterArrivalLiters
            },
            set: { value in
                let normalized = floor(max(0, value))
                actualRefuelOverrides[index] = normalized
                let nextIndex = index + 1
                if plan.rows.indices.contains(nextIndex) {
                    actualDepartureOverrides[nextIndex] = floor(max(
                        0,
                        actual.rows[index].actualArrivalLiters + normalized
                    ))
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let isPortraitLayout = geometry.size.width < 850
                ScrollView {
                    VStack(spacing: 12) {
                        fuelHeader(compact: isPortraitLayout)

                        LazyVStack(spacing: 10) {
                            ForEach(Array(plan.rows.enumerated()), id: \.element.id) {
                                index, row in
                                responsiveFuelRow(index: index, row: row)
                                if candidates.contains(index) {
                                    refuelRow(index: index, row: row)
                                }
                            }
                        }

                        HStack {
                            Label(
                                actual.hasWarning
                                    ? "IST-Verlauf unterschreitet Reserve, wird negativ oder überschreitet die Tankkapazität."
                                    : "IST-Verlauf erfüllt die Endreserve.",
                                systemImage: actual.hasWarning
                                    ? "exclamationmark.triangle.fill"
                                    : "checkmark.circle.fill"
                            )
                            .font(.subheadline.bold())
                            .foregroundStyle(actual.hasWarning ? .red : .green)
                            Spacer()
                            Text("IST ENDE  \(Int(actual.finalFuelLiters)) L")
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(Color.dashboardNavy)
                        }
                    }
                    .padding(isPortraitLayout ? 12 : 18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color.dashboardBackground.ignoresSafeArea())
                .scrollDismissesKeyboard(.interactively)
            }
            .onAppear {
                if planStartingFuelLiters <= 0 {
                    planStartingFuelLiters = template.minimumStartingFuelLiters
                }
                if actualStartingFuelLiters <= 0 {
                    actualStartingFuelLiters = effectivePlanStart
                }
            }
            .onChange(of: planStartingFuelLiters) { _, value in
                if !actualStartWasEdited { actualStartingFuelLiters = value }
            }
        }
    }

    @ViewBuilder
    private func fuelHeader(compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("TANKKALKULATOR", systemImage: "fuelpump.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Color.dashboardNavy)
                    Spacer()
                    Button("Schließen") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.dashboardBlue)
                }
                HStack {
                    Text("\(aircraftName) · \(Int(usableFuelLiters)) L nutzbar · Reserve \(reserveMinutes) min")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    minimumPlanButton
                    fullPlanButton
                    resetActualButton
                }
            }
        } else {
            HStack(spacing: 12) {
                Label("TANKKALKULATOR", systemImage: "fuelpump.fill")
                    .font(.system(size: 25, weight: .heavy))
                    .foregroundStyle(Color.dashboardNavy)
                Text("\(aircraftName) · \(Int(usableFuelLiters)) L nutzbar · Reserve \(reserveMinutes) min")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                minimumPlanButton
                fullPlanButton
                resetActualButton
                Button("Schließen") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.dashboardBlue)
            }
        }
    }

    private var resetActualButton: some View {
        Button("IST aus Plan") {
            actualStartWasEdited = false
            actualStartingFuelLiters = effectivePlanStart
            actualArrivalOverrides = [:]
            actualDepartureOverrides = [:]
            actualRefuelOverrides = [:]
        }
        .buttonStyle(.bordered)
    }

    private var minimumPlanButton: some View {
        Button("Plan Minimum") {
            planStartingFuelLiters = template.minimumStartingFuelLiters
            plannedRefuelOverrides = [:]
        }
        .buttonStyle(.bordered)
    }

    private var fullPlanButton: some View {
        Button("Plan Voll") {
            planStartingFuelLiters = usableFuelLiters
            plannedRefuelOverrides = [:]
        }
            .buttonStyle(.bordered)
    }

    private func responsiveFuelRow(
        index: Int,
        row: FuelPlanRow
    ) -> some View {
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(row.leg.originICAO) → \(row.leg.destinationICAO)")
                    .font(.headline.bold().monospaced())
                Spacer()
                Text("\(row.leg.flightMinutes) min")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                fuelStatePanel(title: "MINIMUM", tint: .gray) {
                    compactFuelLine("T/O", row.minimumDepartureLiters)
                    compactFuelLine("LDG", row.minimumArrivalLiters)
                }
                fuelStatePanel(title: "PLAN", tint: Color.dashboardBlue) {
                    if index == 0 {
                        editableFuelLine("T/O", value: $planStartingFuelLiters)
                    } else {
                        compactFuelLine("T/O", row.plannedDepartureLiters)
                    }
                    compactFuelLine("LDG", row.plannedArrivalLiters)
                }
                fuelStatePanel(
                    title: "IST",
                    tint: actual.hasWarning ? .red : .green
                ) {
                    editableFuelLine("T/O", value: actualDepartureBinding(index))
                    HStack(spacing: 5) {
                        Text("LDG").font(.caption.bold())
                        Spacer(minLength: 2)
                        fuelTableInput(actualArrivalBinding(index), width: 82)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.10), lineWidth: 1)
        }
    }

    private func fuelStatePanel<Content: View>(
        title: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider().overlay(tint.opacity(0.7))
            content()
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 116, maxHeight: 116, alignment: .topLeading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(0.55), lineWidth: 1.2)
        }
    }

    private func compactFuelLine(
        _ title: String,
        _ value: Double,
        prefix: String = ""
    ) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.caption.bold())
            Spacer(minLength: 2)
            fuelTableMetric(value, prefix: prefix, width: 82)
        }
        .foregroundStyle(Color.dashboardNavy)
    }

    private func editableFuelLine(
        _ title: String,
        value: Binding<Double>
    ) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.caption.bold())
            Spacer(minLength: 2)
            fuelTableInput(value, width: 82)
        }
    }

    private func refuelRow(index: Int, row: FuelPlanRow) -> some View {
        let enabled = refuelAfterLegIndices.contains(index)
        return HStack(spacing: 10) {
            Button {
                if enabled {
                    refuelAfterLegIndices.remove(index)
                    plannedRefuelOverrides[index] = nil
                    actualRefuelOverrides[index] = nil
                    actualDepartureOverrides[index + 1] = nil
                } else {
                    refuelAfterLegIndices.insert(index)
                }
            } label: {
                Label(
                    enabled ? "TANKEN" : "Tankstopp hinzufügen",
                    systemImage: enabled ? "fuelpump.fill" : "fuelpump"
                )
                .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .tint(enabled ? Color.dashboardBlue : .secondary)
            Text(row.leg.destinationICAO)
                .font(.caption.bold().monospaced())
            if enabled {
                refuelValue(
                    title: "MIN",
                    value: plan.minimumRefuelLitersByLegIndex[index] ?? 0
                )
                refuelInput(
                    title: "PLAN",
                    value: plannedRefuelBinding(index),
                    tint: Color.dashboardBlue
                )
                refuelInput(
                    title: "IST",
                    value: actualRefuelBinding(index),
                    tint: actual.hasWarning ? .red : .green
                )
                Button("Minimum") {
                    plannedRefuelOverrides[index] = floor(max(
                        0,
                        plan.minimumRefuelLitersByLegIndex[index] ?? 0
                    ))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("Voll") {
                    plannedRefuelOverrides[index] = floor(max(
                        0,
                        usableFuelLiters - max(0, row.plannedArrivalLiters)
                    ))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(
            Color.dashboardBlue.opacity(enabled ? 0.10 : 0.035),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.dashboardBlue.opacity(enabled ? 0.45 : 0.12), lineWidth: 1)
        }
    }

    private func refuelValue(title: String, value: Double) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.caption2.weight(.black))
            fuelTableMetric(value, prefix: "+", width: 82)
        }
        .foregroundStyle(Color.dashboardNavy)
    }

    private func refuelInput(
        title: String,
        value: Binding<Double>,
        tint: Color
    ) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.caption2.weight(.black))
                .foregroundStyle(tint)
            fuelTableInput(value, width: 82)
        }
    }

    private func fuelTableInput(
        _ value: Binding<Double>,
        width: CGFloat
    ) -> some View {
        HStack(spacing: 2) {
            SelectAllFuelField(value: value, fontSize: 13)
            Text("L").font(.caption2.bold())
        }
        .padding(.horizontal, 6)
        .frame(width: width, height: 30)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.dashboardBlue.opacity(0.48), lineWidth: 1)
        }
    }

    private func fuelTableMetric(
        _ value: Double,
        prefix: String = "",
        width: CGFloat
    ) -> some View {
        HStack(spacing: 2) {
            Spacer(minLength: 0)
            Text("\(prefix)\(FuelPlanCalculator.roundedLitersForDisplay(value))")
                .font(.system(size: 13, weight: .heavy).monospacedDigit())
            Text("L").font(.caption2.bold())
        }
        .padding(.horizontal, 6)
        .frame(width: width, height: 30)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.dashboardBlue.opacity(0.48), lineWidth: 1)
        }
    }
}

private struct BottomMenuButton: View {
    let systemName: String
    let label: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(selected ? .white : Color.dashboardBlue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    selected ? Color.dashboardBlue : Color.clear,
                    in: RoundedRectangle(cornerRadius: 13)
                )
        }
        .buttonStyle(.plain)
        .padding(5)
        .accessibilityLabel(label)
    }
}

private struct CompactSetupPicker: View {
    let title: String
    let icon: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(Color.dashboardNavy)

            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Color.dashboardNavy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.dashboardBlue)
                .frame(width: 46, height: 40)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.dashboardBlue.opacity(0.45), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(Color.dashboardNavy)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }
}

private struct EditableFlightLegCard: View {
    let airports: [Airport]
    @Binding var departureICAO: String
    @Binding var arrivalICAO: String
    @Binding var departure: Date
    let durationMinutes: Int
    let etopsLegMinutes: Int
    let etopsGreenYellowMinutes: Int
    let etopsOrangeRedMinutes: Int
    let distanceNM: Double
    @Binding var selectedAltitudeFeet: Int
    let altitudeOptions: [Int]
    let courseDegrees: Double
    let bestLevelFeet: Int
    let departureAirport: Airport
    let arrivalAirport: Airport
    let routeRisks: [IPadRouteWeatherRisk]
    let foehnWarning: AlpineFoehnWarning?
    let routeHeadwindKnots: Double?
    let departureWeatherSample: EDFZWeatherSample?
    let arrivalWeatherSample: EDFZWeatherSample?
    let departurePerformance: RunwayPerformanceDisplay?
    let arrivalPerformance: RunwayPerformanceDisplay?
    let onArrivalSelected: (Airport) -> Void

    private var arrival: Date {
        departure.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    private var routeWind: (value: String, color: Color) {
        guard let component = routeHeadwindKnots else {
            return ("Streckenwind lädt", Color.dashboardBlue)
        }
        if component > 0.5 {
            return ("Gegenwind \(Int(component.rounded())) kt", .red)
        }
        if component < -0.5 {
            return ("Rückenwind \(Int(abs(component).rounded())) kt", .green)
        }
        return ("Wind neutral 0 kt", Color.dashboardBlue)
    }

    private var etopsBlockColor: Color {
        let greenYellow = max(30, etopsGreenYellowMinutes)
        let orangeRed = max(greenYellow + 10, etopsOrangeRedMinutes)
        let yellowOrange = greenYellow + (orangeRed - greenYellow) / 2
        if etopsLegMinutes < greenYellow { return .green }
        if etopsLegMinutes < yellowOrange { return .yellow }
        if etopsLegMinutes < orangeRed { return .orange }
        return .red
    }

    var body: some View {
        DashboardCard {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    IPadRouteRiskBars(risks: routeRisks)
                    if let foehnWarning {
                        Label(foehnWarning.flowName, systemImage: "wind")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(foehnWarning.level.color)
                            .help(foehnWarning.explanation)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14)

                ZStack {
                Rectangle()
                    .fill(Color.dashboardNavy.opacity(0.15))
                    .frame(width: 1)
                    .padding(.vertical, -2)

                VStack(spacing: 5) {
                    HStack(spacing: 0) {
                        FlightAirportHalf(
                            title: "ABFLUG",
                            text: $departureICAO,
                            airports: airports,
                            airport: departureAirport,
                            weatherSample: departureWeatherSample,
                            referenceDate: departure,
                            onSelect: { _ in }
                        )
                        FlightAirportHalf(
                            title: "ANKUNFT",
                            text: $arrivalICAO,
                            airports: airports,
                            airport: arrivalAirport,
                            weatherSample: arrivalWeatherSample,
                            referenceDate: arrival,
                            onSelect: onArrivalSelected
                        )
                    }
                    .zIndex(2)

                    Color.clear.frame(height: 58)
                }

                UniformFlightMetricBox(
                    title: "ABFLUG",
                    value: departure.formatted(date: .omitted, time: .shortened)
                )
                .frame(width: 132)
                .offset(x: -306, y: 43)

                UniformFlightMetricBox(
                    title: "ANKUNFT",
                    value: arrival.formatted(date: .omitted, time: .shortened)
                )
                .frame(width: 132)
                .offset(x: 306, y: 43)

                UniformFlightMetricBox(
                    title: "REISEZEIT",
                    value: "\(durationMinutes / 60):\(String(format: "%02d", durationMinutes % 60))",
                    valueColor: Color.dashboardBlue,
                    boxTint: Color.dashboardNavy,
                    solidBackground: true
                )
                .frame(width: 128)
                .offset(y: 43)

                RoundedRectangle(cornerRadius: 3)
                    .fill(etopsBlockColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.dashboardNavy.opacity(0.55), lineWidth: 0.8)
                    }
                    .frame(width: 68, height: 6)
                    .offset(y: 17)
                    .zIndex(5)

                VStack(spacing: 1) {
                    Text("BEST LEVEL")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(altitudeLabel(bestLevelFeet))
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.dashboardNavy)
                }
                .frame(width: 94)
                .offset(x: -111, y: 43)

                let departureWeather = DashboardWeatherPreview.snapshot(
                    for: departureAirport,
                    sample: departureWeatherSample
                )
                Image(systemName: departureWeather.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 25, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(
                        Color.gray.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .offset(x: -208, y: 43)
                    .accessibilityLabel("Abflugwetter")

                Menu {
                    ForEach(altitudeOptions, id: \.self) { altitude in
                        Button {
                            selectedAltitudeFeet = altitude
                        } label: {
                            HStack {
                                Text(altitudeLabel(altitude))
                                    .font(
                                        .system(
                                            size: 13,
                                            weight: FlightAltitudeRules.isRecommended(
                                                altitude,
                                                forCourseDegrees: courseDegrees
                                            ) ? .bold : .regular
                                        )
                                    )
                                if selectedAltitudeFeet == altitude {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    VStack(spacing: 1) {
                        Text("FLUGHÖHE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 3) {
                            Text(altitudeLabel(selectedAltitudeFeet))
                                .font(.system(size: 17, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.dashboardNavy)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 7, weight: .heavy))
                                .foregroundStyle(Color.dashboardNavy.opacity(0.72))
                        }
                    }
                    .frame(width: 94)
                }
                .buttonStyle(.plain)
                .offset(x: 111, y: 43)
                .accessibilityLabel("Flughöhe auswählen")

                let arrivalWeather = DashboardWeatherPreview.snapshot(
                    for: arrivalAirport,
                    sample: arrivalWeatherSample
                )
                Image(systemName: arrivalWeather.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 25, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(
                        Color.gray.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .offset(x: 208, y: 43)
                    .accessibilityLabel("Ankunftswetter")

                Text(routeWind.value)
                    .font(.system(size: 11, weight: .heavy).monospacedDigit())
                    .foregroundStyle(routeWind.color)
                    .lineLimit(1)
                    .frame(width: 128, height: 16)
                    .offset(y: 75)
                    .zIndex(4)
                }
                .frame(height: 170)

                HStack(spacing: 0) {
                    FlightWeatherMetrics(
                        airport: departureAirport,
                        sample: departureWeatherSample,
                        performance: departurePerformance
                    )
                    Divider().frame(height: 42)
                    FlightWeatherMetrics(
                        airport: arrivalAirport,
                        sample: arrivalWeatherSample,
                        performance: arrivalPerformance
                    )
                }
                .frame(height: 70)
            }
        }
    }

    private func altitudeLabel(_ altitude: Int) -> String {
        altitude < 5_000
            ? "\(altitude.formatted(.number.grouping(.automatic))) ft"
            : String(format: "FL%03d", altitude / 100)
    }
}

private struct UniformFlightMetricBox: View {
    let title: String
    let value: String
    var valueColor: Color = Color.dashboardBlue
    var boxTint: Color = Color.dashboardBlue
    var solidBackground = false

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
        .background(solidBackground ? Color.white : boxTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(solidBackground ? Color.dashboardNavy : boxTint.opacity(0.65), lineWidth: solidBackground ? 1.5 : 1)
        }
    }
}

private struct FlightAirportHalf: View {
    let title: String
    @Binding var text: String
    let airports: [Airport]
    let airport: Airport
    let weatherSample: EDFZWeatherSample?
    let referenceDate: Date
    let onSelect: (Airport) -> Void

    private var mirrored: Bool { title == "ANKUNFT" }
    private var weather: DashboardWeatherSnapshot {
        DashboardWeatherPreview.snapshot(for: airport, sample: weatherSample)
    }

    var body: some View {
        ZStack {
            AirportICAOField(
                title: title,
                text: $text,
                airports: airports,
                referenceDate: referenceDate,
                mirrored: mirrored,
                weather: weather,
                onSelect: onSelect
            )
            .frame(maxWidth: .infinity, alignment: mirrored ? .trailing : .leading)

            RunwayRecommendationPanel(
                airport: airport,
                weather: weather,
                mirrored: mirrored
            )
        }
        .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 100)
        .padding(.horizontal, 8)
    }
}

private struct RunwayRecommendationPanel: View {
    let airport: Airport
    let weather: DashboardWeatherSnapshot
    let mirrored: Bool

    private var runwayEnds: [String] {
        airport.referenceRunway
            .split(separator: "/")
            .map { String($0.prefix(2)) }
    }

    private var runwayHeading: Double {
        (Double(runwayEnds.first ?? "") ?? 0) * 10
    }

    private var runwayHeadings: [(label: String, heading: Double)] {
        runwayEnds.compactMap { label in
            guard let number = Double(label) else { return nil }
            return (label, number * 10)
        }
    }

    private var recommendation: (
        label: String,
        heading: Double,
        headwind: Double,
        crosswind: Double,
        crosswindComesFromRight: Bool
    )? {
        runwayHeadings.map { end in
            let difference = shortestAngle(weather.windDirectionDegrees - end.heading) * .pi / 180
            let signedCrosswind = weather.windSpeedKnots * sin(difference)
            return (
                end.label,
                end.heading,
                weather.windSpeedKnots * cos(difference),
                abs(signedCrosswind),
                signedCrosswind > 0
            )
        }.max { $0.headwind < $1.headwind }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.dashboardBackground)
                        .overlay { Circle().stroke(Color.dashboardBlue.opacity(0.22)) }
                    Text("N")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .offset(y: -32)
                    Capsule()
                        .fill(Color.dashboardNavy.opacity(0.82))
                        .frame(width: 64, height: 10)
                        .overlay {
                            Rectangle().fill(Color.white.opacity(0.85)).frame(width: 54, height: 1.5)
                        }
                        .rotationEffect(.degrees(runwayHeading - 90))
                    WindDirectionArrow()
                        .stroke(.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(width: 40, height: 58)
                        .rotationEffect(.degrees(weather.windDirectionDegrees))

                    if runwayEnds.count == 2 {
                        RunwayEndLabel(
                            text: runwayEnds[0],
                            active: recommendation?.label == runwayEnds[0]
                        )
                            .offset(runwayLabelOffset(heading: runwayHeading + 180))
                        RunwayEndLabel(
                            text: runwayEnds[1],
                            active: recommendation?.label == runwayEnds[1]
                        )
                            .offset(runwayLabelOffset(heading: runwayHeading))
                    }
                }
                .frame(width: 82, height: 70)
                HStack(spacing: 8) {
                    Text(headwindText)
                        .foregroundStyle((recommendation?.headwind ?? 0) >= 0 ? .green : .red)
                    Text(crosswindText)
                        .foregroundStyle(.orange)
                }
                .font(.system(size: 12, weight: .heavy).monospacedDigit())
                .frame(width: 132, alignment: .center)
            }

            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "road.lanes")
                    Text(recommendation?.label ?? "—")
                }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.dashboardNavy)
                .frame(height: 18)

                Text(metarWindText)
                    .font(.system(size: 12.5, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Color.dashboardNavy)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(width: 106, height: 40)
                    .background(metarBoxFill, in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(metarBoxBorder, lineWidth: 1.3) }
            }
            .offset(x: mirrored ? -130 : 130, y: -9)
        }
        .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 100)
        .accessibilityLabel("Runway \(airport.referenceRunway), bevorzugt \(recommendation?.label ?? "unbekannt")")
    }

    private func runwayLabelOffset(heading: Double) -> CGSize {
        let radians = (heading - 90) * .pi / 180
        return CGSize(width: cos(radians) * 35, height: sin(radians) * 35)
    }

    private func shortestAngle(_ angle: Double) -> Double {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized > 180 { normalized -= 360 }
        if normalized < -180 { normalized += 360 }
        return normalized
    }

    private var headwindText: String {
        let value = recommendation?.headwind ?? 0
        return value >= 0
            ? "↓ \(Int(value.rounded())) kt"
            : "↑ \(Int(abs(value).rounded())) kt"
    }

    private var crosswindText: String {
        let value = recommendation?.crosswind ?? 0
        guard value >= 0.5 else { return "↔ 0 kt" }
        let arrow = recommendation?.crosswindComesFromRight == true ? "←" : "→"
        return "\(arrow) \(Int(value.rounded())) kt"
    }

    private var metarWindText: String {
        let roundedDirection = (weather.windDirectionDegrees / 10).rounded() * 10
        let normalizedDirection = roundedDirection == 0 && weather.windSpeedKnots > 0
            ? 360 : roundedDirection
        let base = String(
            format: "%03.0f / %02.0f",
            normalizedDirection,
            weather.windSpeedKnots
        )
        return weather.gustKnots.map {
            base + String(format: " G%02d", $0)
        } ?? base
    }

    private var windLimitColor: Color {
        switch crosswindWarning {
        case .none: return .green
        case .yellow: return .orange
        case .red: return .red
        }
    }

    private var crosswindWarning: RunwayCrosswindWarning {
        guard let recommendation else { return .none }
        let gustCrosswind = weather.gustKnots.map { gust in
            guard weather.windSpeedKnots > 0 else { return 0.0 }
            return Double(gust) * recommendation.crosswind
                / weather.windSpeedKnots
        }
        return EDFZRunway.crosswindWarning(for: RunwayWindComponents(
            headwindKnots: recommendation.headwind,
            crosswindKnots: recommendation.crosswind,
            gustCrosswindKnots: gustCrosswind,
            crosswindComesFromRight: recommendation.crosswindComesFromRight
        ))
    }

    private var metarBoxFill: Color {
        switch crosswindWarning {
        case .none: return Color.green.opacity(0.24)
        case .yellow: return Color.orange.opacity(0.32)
        case .red: return Color.red.opacity(0.38)
        }
    }

    private var metarBoxBorder: Color {
        windLimitColor.opacity(0.85)
    }

    private var isNormalWind: Bool {
        crosswindWarning == .none
    }
}

private struct WindDirectionArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.midX
        let top = rect.minY + 4
        let bottom = rect.maxY - 5
        path.move(to: CGPoint(x: x, y: top))
        path.addLine(to: CGPoint(x: x, y: bottom))
        path.move(to: CGPoint(x: x, y: bottom))
        path.addLine(to: CGPoint(x: x - 7, y: bottom - 10))
        path.move(to: CGPoint(x: x, y: bottom))
        path.addLine(to: CGPoint(x: x + 7, y: bottom - 10))
        return path
    }
}

private struct RunwayEndLabel: View {
    let text: String
    let active: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .black).monospacedDigit())
            .foregroundStyle(active ? .white : Color.dashboardNavy)
            .padding(.horizontal, 5)
            .frame(height: 18)
            .background(active ? Color.dashboardBlue : Color.white, in: Capsule())
            .overlay { Capsule().stroke(Color.dashboardBlue.opacity(0.35)) }
    }
}

private enum OperationalStatus {
    case open, closed, unknown

    var tint: Color {
        switch self {
        case .open: return .green
        case .closed: return .red
        case .unknown: return Color.dashboardBlue
        }
    }
}

private struct FlightTimeBox: View {
    let title: String
    @Binding var date: Date
    let status: OperationalStatus

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
            DatePicker(title, selection: $date, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .font(.subheadline.bold().monospacedDigit())
        }
        .frame(width: 84, height: 44)
        .background(status.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(status.tint.opacity(0.65)) }
    }
}

private struct ReadOnlyFlightTimeBox: View {
    let title: String
    let date: Date
    let status: OperationalStatus

    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(Color.dashboardNavy)
        }
        .frame(width: 78, height: 44)
        .background(status.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(status.tint.opacity(0.65)) }
    }
}

private struct AltitudeDisplayBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(Color.dashboardBlue)
        }
        .frame(width: 82, height: 44)
        .background(Color.dashboardBackground, in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct DashboardWeatherSnapshot {
    let category: String
    let temperatureCelsius: Int
    let visibilityKilometers: String
    let clouds: String
    let cloudBaseFeet: String
    let pressureHPA: Int
    let densityAltitudeFeet: Int
    let windDirectionDegrees: Double
    let windSpeedKnots: Double
    let gustKnots: Int?

    var categoryColor: Color {
        switch category {
        case "VFR": return .green
        case "MVFR": return Color.dashboardBlue
        case "IFR": return .red
        default: return .purple
        }
    }

    var symbolName: String {
        switch clouds {
        case "SKC": return "sun.max.fill"
        case "FEW", "SCT": return "cloud.sun.fill"
        case "BKN": return "cloud.fill"
        default: return "cloud.fog.fill"
        }
    }

    var symbolColor: Color {
        switch clouds {
        case "SKC": return .orange
        case "FEW", "SCT": return Color.dashboardBlue
        default: return Color.dashboardNavy.opacity(0.72)
        }
    }
}

private struct RunwayPerformanceDisplay {
    let result: RunwayPerformanceResult
    let availableMeters: Int?
    let isDeparture: Bool

    var rollPercentage: Int? {
        availableMeters.flatMap {
            result.runwayPercentage(availableMeters: $0)
        }
    }

    var fiftyFeetPercentage: Int? {
        guard let availableMeters, availableMeters > 0 else { return nil }
        return Int(ceil(
            Double(result.over50FeetMeters) / Double(availableMeters) * 100
        ))
    }
}

private enum DashboardWeatherPreview {
    static func snapshot(
        for airport: Airport,
        sample: EDFZWeatherSample? = nil
    ) -> DashboardWeatherSnapshot {
        if let sample {
            let temperature = sample.temperatureCelsius ?? 0
            let pressure = sample.pressureMSLHPA ?? 1_013.25
            let densityAltitude = RunwayPerformance.densityAltitudeFeet(
                elevationFeet: Double(airport.elevationFeet),
                temperatureCelsius: temperature,
                pressureHPA: pressure
            ) ?? Double(airport.elevationFeet)
            let cloudCover = sample.lowCloudCoverPercent ?? sample.totalCloudCoverPercent ?? 0
            let clouds: String
            switch cloudCover {
            case ..<12.5: clouds = "SKC"
            case ..<37.5: clouds = "FEW"
            case ..<62.5: clouds = "SCT"
            case ..<87.5: clouds = "BKN"
            default: clouds = "OVC"
            }
            let visibility = sample.visibilityMeters.map {
                $0 >= 9_999 ? "10+" : String(format: "%.1f", $0 / 1_000)
            } ?? "—"
            let base = sample.lowestCloudBaseFeetAGL.map {
                (Int(($0 / 100).rounded()) * 100).formatted(.number.grouping(.automatic))
            } ?? "—"
            return .init(
                category: sample.category.rawValue,
                temperatureCelsius: Int(temperature.rounded()),
                visibilityKilometers: visibility,
                clouds: clouds,
                cloudBaseFeet: base,
                pressureHPA: Int(pressure.rounded()),
                densityAltitudeFeet: Int((densityAltitude / 100).rounded()) * 100,
                windDirectionDegrees: ((sample.windDirectionDegrees ?? 0) / 10).rounded() * 10,
                windSpeedKnots: sample.windSpeedKnots ?? 0,
                gustKnots: sample.windGustKnots.map { Int($0.rounded()) }
            )
        }
        switch airport.icao {
        case "EDFZ":
            return .init(
                category: "VFR", temperatureCelsius: 23, visibilityKilometers: "10+",
                clouds: "FEW", cloudBaseFeet: "4.800", pressureHPA: 1018,
                densityAltitudeFeet: 2_180, windDirectionDegrees: 240,
                windSpeedKnots: 5, gustKnots: nil
            )
        case "EDAX":
            return .init(
                category: "VFR", temperatureCelsius: 21, visibilityKilometers: "10+",
                clouds: "SCT", cloudBaseFeet: "3.900", pressureHPA: 1015,
                densityAltitudeFeet: 1_620, windDirectionDegrees: 260,
                windSpeedKnots: 8, gustKnots: 14
            )
        default:
            return .init(
                category: "MVFR", temperatureCelsius: 19, visibilityKilometers: "8",
                clouds: "BKN", cloudBaseFeet: "2.400", pressureHPA: 1016,
                densityAltitudeFeet: max(1_400, airport.elevationFeet + 1_100),
                windDirectionDegrees: 230, windSpeedKnots: 7, gustKnots: 12
            )
        }
    }
}

private struct FlightCategoryBadge: View {
    let weather: DashboardWeatherSnapshot

    var body: some View {
        Text(weather.category)
            .font(.system(size: 10, weight: .black))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: 48, height: 25)
            .background(weather.categoryColor, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.dashboardNavy.opacity(0.22), lineWidth: 1)
            }
    }
}

private struct FlightWeatherMetrics: View {
    let airport: Airport
    let sample: EDFZWeatherSample?
    let performance: RunwayPerformanceDisplay?

    private var weather: DashboardWeatherSnapshot {
        DashboardWeatherPreview.snapshot(for: airport, sample: sample)
    }

    private var mirrored: Bool {
        performance?.isDeparture == false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            if mirrored {
                performanceGroup
            }
            primaryWeatherColumn
            if !mirrored {
                performanceGroup
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private var primaryWeatherColumn: some View {
        VStack(spacing: 3) {
            WeatherMetricGroup {
                WeatherMetric(title: "QNH", value: "\(weather.pressureHPA)")
                WeatherMetric(title: "TEMP", value: "\(weather.temperatureCelsius) °C")
                densityAltitudeMetric
            }
            WeatherMetricGroup {
                WeatherMetric(title: "WOLKEN", value: weather.clouds)
                WeatherMetric(title: "BASIS", value: "\(weather.cloudBaseFeet) ft")
                WeatherMetric(title: "SICHT", value: "\(weather.visibilityKilometers) km")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var performanceGroup: some View {
        WeatherMetricGroup {
            performanceMetric(isFiftyFeet: false)
            performanceMetric(isFiftyFeet: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var densityAltitudeMetric: some View {
        let high = weather.densityAltitudeFeet >= 5_000
        let elevated = weather.densityAltitudeFeet >= 2_500
        return WeatherMetric(
            title: "DICHTEHÖHE",
            value: "\(weather.densityAltitudeFeet.formatted()) ft",
            valueColor: high ? .white : Color.dashboardNavy,
            backgroundColor: high
                ? Color.red.opacity(0.82)
                : (elevated ? Color.yellow.opacity(0.62) : nil)
        )
    }

    private func performanceMetric(isFiftyFeet: Bool) -> some View {
        let percentage = isFiftyFeet
            ? performance?.fiftyFeetPercentage
            : performance?.rollPercentage
        let meters = isFiftyFeet
            ? performance?.result.over50FeetMeters
            : performance?.result.rollMeters
        let title = isFiftyFeet
            ? "50 FT"
            : (performance?.isDeparture == false ? "LDG ROLL" : "T/O ROLL")
        let color: Color = {
            guard let percentage else { return Color.dashboardNavy }
            if isFiftyFeet { return percentage >= 100 ? .red : Color.dashboardNavy }
            if percentage >= 75 { return .red }
            if percentage >= 50 { return .orange }
            return Color.dashboardNavy
        }()
        return WeatherMetric(
            title: title,
            value: meters.map {
                "\($0)m" + (percentage.map { " (\($0)%)" } ?? "")
            } ?? "—",
            valueColor: color,
            backgroundColor: percentage.map { value in
                if isFiftyFeet { return value >= 100 ? Color.red.opacity(0.14) : nil }
                if value >= 75 { return Color.red.opacity(0.14) }
                if value >= 50 { return Color.orange.opacity(0.20) }
                return nil
            } ?? nil
        )
    }
}

private struct AirportWeatherColumn: View {
    let airport: Airport

    private var weather: DashboardWeatherSnapshot {
        DashboardWeatherPreview.snapshot(for: airport)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(weather.categoryColor).frame(width: 10, height: 10)
                Text(airport.icao).font(.system(size: 17, weight: .bold)).foregroundStyle(Color.dashboardBlue)
                Text(airport.name).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.dashboardNavy).lineLimit(1)
                Text(weather.category)
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(weather.categoryColor)
                Spacer(minLength: 2)
                Image(systemName: weather.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(
                        Color.gray.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 7)
                    )
            }
            HStack(spacing: 5) {
                WeatherMetricGroup {
                    WeatherMetric(title: "QNH", value: "\(weather.pressureHPA)")
                    WeatherMetric(title: "TEMP", value: "\(weather.temperatureCelsius) °C")
                    WeatherMetric(title: "DICHTEHÖHE", value: "\(weather.densityAltitudeFeet.formatted()) ft")
                }
                WeatherMetricGroup {
                    WeatherMetric(title: "WOLKEN", value: weather.clouds)
                    WeatherMetric(title: "BASIS", value: "\(weather.cloudBaseFeet) ft")
                    WeatherMetric(title: "SICHT", value: "\(weather.visibilityKilometers) km")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

private struct WeatherMetricGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.dashboardBlue.opacity(0.38), lineWidth: 1)
        }
    }
}

private struct WeatherMetric: View {
    let title: String
    let value: String
    var valueColor: Color = Color.dashboardNavy
    var backgroundColor: Color? = nil

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 7.8, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(value)
                .font(.system(size: 12.5, weight: .bold).monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .background(
            backgroundColor ?? .clear,
            in: RoundedRectangle(cornerRadius: 4)
        )
    }
}

private struct AirportICAOField: View {
    let title: String
    @Binding var text: String
    let airports: [Airport]
    let referenceDate: Date
    let mirrored: Bool
    let weather: DashboardWeatherSnapshot
    let onSelect: (Airport) -> Void

    @FocusState private var isFocused: Bool

    private var matchingAirports: [Airport] {
        guard text.count >= 3 else { return [] }
        let normalized = text.uppercased()
        return Array(
            airports.filter {
                $0.icao.hasPrefix(normalized)
                    || $0.name.localizedCaseInsensitiveContains(text)
            }.prefix(3)
        )
    }

    private var selectedAirport: Airport? {
        airports.first { $0.icao == text.uppercased() }
    }

    var body: some View {
        VStack(alignment: mirrored ? .trailing : .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                if mirrored {
                    FlightCategoryBadge(weather: weather)
                }
                TextField("ICAO", text: $text)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.dashboardBlue)
                    .multilineTextAlignment(mirrored ? .trailing : .leading)
                    .focused($isFocused)
                    .frame(width: 76)
                    .onChange(of: text) { _, value in
                        let normalized = String(value.uppercased().prefix(4))
                        if normalized != value { text = normalized }
                    }
                if !mirrored {
                    FlightCategoryBadge(weather: weather)
                }
            }
            .frame(maxWidth: .infinity, alignment: mirrored ? .trailing : .leading)
            Text(selectedAirport?.name ?? "Flugplatz wählen")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.dashboardNavy)
                .lineLimit(1)
            Text(DashboardSolarClock.display(for: selectedAirport, on: referenceDate))
                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 142, alignment: mirrored ? .trailing : .leading)
        .overlay(alignment: .topLeading) {
            if isFocused, !matchingAirports.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(matchingAirports) { airport in
                        Button {
                            text = airport.icao
                            onSelect(airport)
                            isFocused = false
                        } label: {
                            Text("\(airport.icao) · \(airport.name)")
                                .font(.caption.bold())
                                .foregroundStyle(Color.dashboardNavy)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .frame(width: 210, height: 30, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.dashboardBlue.opacity(0.35), lineWidth: 1)
                }
                .shadow(radius: 6)
                .offset(y: 66)
                .zIndex(10)
            }
        }
    }
}

private struct PlanningMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(Color.dashboardNavy)
        }
        .frame(width: 58)
    }
}

private struct ForecastRiskBar: View {
    enum Kind { case fog, wind }
    let days: [IPadDailyWeather]
    let kind: Kind

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { dayIndex in
                HStack(spacing: 0) {
                    ForEach(0..<17, id: \.self) { hourIndex in
                        Rectangle()
                            .fill(color(day: dayIndex, hour: hourIndex))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
                .frame(maxWidth: .infinity, minHeight: 5, maxHeight: 5)
            }
        }
    }

    private func color(day: Int, hour: Int) -> Color {
        guard days.indices.contains(day) else { return Color.gray.opacity(0.18) }
        switch kind {
        case .fog:
            guard days[day].hourlyFogRisk.indices.contains(hour),
                  let score = days[day].hourlyFogRisk[hour] else { return Color.gray.opacity(0.18) }
            switch FogRiskModel.classify(score: score) {
            case .low: return .white
            case .raised: return Color(red: 247 / 255, green: 201 / 255, blue: 211 / 255)
            case .high: return Color(red: 230 / 255, green: 74 / 255, blue: 80 / 255)
            case .veryHigh: return Color(red: 142 / 255, green: 77 / 255, blue: 159 / 255)
            }
        case .wind:
            guard days[day].hourlyWindKnots.indices.contains(hour),
                  let wind = days[day].hourlyWindKnots[hour] else { return Color(red: 0.92, green: 0.96, blue: 0.99) }
            switch wind {
            case ...3: return Color(red: 0.78, green: 0.94, blue: 0.80)
            case ...6: return Color(red: 0.39, green: 0.78, blue: 0.47)
            case ...9: return Color(red: 0.10, green: 0.50, blue: 0.22)
            case ...12: return Color(red: 0.69, green: 0.86, blue: 0.98)
            case ...15: return Color(red: 0.31, green: 0.61, blue: 0.88)
            case ...18: return Color(red: 0.08, green: 0.29, blue: 0.66)
            case ...24: return Color(red: 0.97, green: 0.55, blue: 0.45)
            default: return .red
            }
        }
    }
}

private struct FlightLegCard: View {
    let title: String
    let departureAirport: Airport
    let arrivalAirport: Airport
    @Binding var departure: Date
    let durationMinutes: Int
    let distanceNM: Double

    private var arrival: Date {
        departure.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    var body: some View {
        DashboardCard {
            VStack(spacing: 9) {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.headline.bold())
                        .foregroundStyle(Color.dashboardNavy)
                        .frame(width: 92, alignment: .leading)

                    AirportEndpoint(airport: departureAirport, title: "ABFLUG")
                    Image(systemName: "arrow.right")
                        .font(.headline.bold())
                        .foregroundStyle(.secondary)
                    AirportEndpoint(airport: arrivalAirport, title: "ANKUNFT")

                    Button(action: {}) {
                        Image(systemName: "arrow.clockwise")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 34)
                            .background(Color.dashboardBlue, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Flugplatzwetter datenoptimiert aktualisieren")
                }

                Divider()

                HStack(spacing: 10) {
                    DatePicker("Datum", selection: $departure, displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 132)
                    DatePicker("Abflug", selection: $departure, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 92)

                    Spacer()

                    Label("\(durationMinutes / 60):\(String(format: "%02d", durationMinutes % 60)) h", systemImage: "clock")
                    Label("\(Int(distanceNM.rounded())) NM", systemImage: "location")
                    Text("FL070")

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(arrival.formatted(date: .omitted, time: .shortened))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Color.dashboardNavy)
                        Text("ANKUNFT")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption.bold())
                .foregroundStyle(Color.dashboardNavy)
            }
        }
    }
}

private struct AirportEndpoint: View {
    let airport: Airport
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(airport.icao)
                .font(.headline.bold())
                .foregroundStyle(Color.dashboardBlue)
            Text(airport.name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.dashboardNavy)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ForecastPlaceholderTile: View {
    let date: Date
    let weather: IPadDailyWeather?

    var body: some View {
        VStack(spacing: 5) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption.bold())
                .foregroundStyle(Color.dashboardNavy)
            HStack(spacing: 5) {
                ForEach(Array(periodSymbols.enumerated()), id: \.offset) { _, symbol in
                    Image(systemName: symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 20, height: 22)
                        .background(
                            Color.gray.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                }
            }
            Text(temperatureText)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.dashboardBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private var periodSymbols: [String] {
        guard let weather else { return Array(repeating: "questionmark.circle", count: 3) }
        return weather.periodSymbolNames
    }

    private var temperatureText: String {
        guard let low = weather?.minimumTemperature,
              let high = weather?.maximumTemperature else { return "—° / —°" }
        return "\(low)° / \(high)°"
    }
}

private struct SectionTitle: View {
    let title: String
    let systemName: String

    var body: some View {
        Label(title, systemImage: systemName)
            .font(.headline.bold())
            .foregroundStyle(Color.dashboardNavy)
    }
}

private struct DashboardCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.black.opacity(0.09), lineWidth: 1)
            }
    }
}

private enum DashboardSolarClock {
    static func display(for airport: Airport?, on date: Date) -> String {
        guard let airport,
              let sunrise = event(on: date, airport: airport, sunrise: true),
              let sunset = event(on: date, airport: airport, sunrise: false)
        else { return "☀ —  ·  ☾ —" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = TimeZone(identifier: airport.timeZoneIdentifier) ?? .current
        formatter.dateFormat = "HH:mm"
        return "☀ \(formatter.string(from: sunrise))  ·  ☾ \(formatter.string(from: sunset))"
    }

    private static func event(on date: Date, airport: Airport, sunrise: Bool) -> Date? {
        let timeZone = TimeZone(identifier: airport.timeZoneIdentifier) ?? .current
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone
        let day = localCalendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let gamma = 2 * Double.pi / 365 * (Double(day) - 1)
        let equation = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let declination = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let latitude = airport.latitude * .pi / 180
        let zenith = 90.833 * .pi / 180
        let cosineHour = cos(zenith) / (cos(latitude) * cos(declination))
            - tan(latitude) * tan(declination)
        guard (-1.0...1.0).contains(cosineHour) else { return nil }
        let hourAngle = acos(cosineHour) * 180 / .pi
        let noonUTC = 720 - 4 * airport.longitude - equation
        let minutesUTC = sunrise ? noonUTC - 4 * hourAngle : noonUTC + 4 * hourAngle

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = localCalendar.dateComponents([.year, .month, .day], from: date)
        guard let midnight = utcCalendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: parts.year,
            month: parts.month,
            day: parts.day
        )) else { return nil }
        return midnight.addingTimeInterval(minutesUTC * 60)
    }
}

private struct AirportPickerSheet: View {
    let airports: [Airport]
    @Binding var selectedICAO: String

    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var filteredAirports: [Airport] {
        guard !searchText.isEmpty else { return airports }
        return airports.filter {
            $0.icao.localizedCaseInsensitiveContains(searchText)
                || $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredAirports) { airport in
                Button {
                    selectedICAO = airport.icao
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(airport.icao)
                                .font(.headline)
                                .foregroundStyle(Color.dashboardBlue)
                            Text(airport.name)
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        Text(airport.runwayDisplay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Zielflugplatz")
            .searchable(text: $searchText, prompt: "ICAO oder Name")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }
}

enum FlightGeometry {
    static func nauticalMiles(from origin: Airport, to destination: Airport) -> Double {
        let radiusNM = 3_440.065
        let lat1 = origin.latitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let deltaLat = (destination.latitude - origin.latitude) * .pi / 180
        let deltaLon = (destination.longitude - origin.longitude) * .pi / 180
        let value = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2)
            * sin(deltaLon / 2) * sin(deltaLon / 2)
        return radiusNM * 2 * atan2(sqrt(value), sqrt(1 - value))
    }

    static func initialBearing(from origin: Airport, to destination: Airport) -> Double {
        let lat1 = origin.latitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let deltaLongitude = (destination.longitude - origin.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLongitude)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func nauticalMiles(
        from origin: Airport,
        to coordinate: (latitude: Double, longitude: Double)
    ) -> Double {
        let radiusNM = 3_440.065
        let lat1 = origin.latitude * .pi / 180
        let lat2 = coordinate.latitude * .pi / 180
        let deltaLat = (coordinate.latitude - origin.latitude) * .pi / 180
        let deltaLon = (coordinate.longitude - origin.longitude) * .pi / 180
        let value = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return radiusNM * 2 * atan2(sqrt(value), sqrt(max(0, 1 - value)))
    }

    static func intermediateCoordinate(
        from origin: Airport,
        to destination: Airport,
        fraction: Double
    ) -> (latitude: Double, longitude: Double) {
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let lon2 = destination.longitude * .pi / 180
        let angular = 2 * asin(sqrt(
            pow(sin((lat2 - lat1) / 2), 2)
                + cos(lat1) * cos(lat2) * pow(sin((lon2 - lon1) / 2), 2)
        ))
        guard angular > 0.000_001 else { return (origin.latitude, origin.longitude) }
        let a = sin((1 - fraction) * angular) / sin(angular)
        let b = sin(fraction * angular) / sin(angular)
        let x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2)
        let y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2)
        let z = a * sin(lat1) + b * sin(lat2)
        return (
            atan2(z, sqrt(x * x + y * y)) * 180 / .pi,
            atan2(y, x) * 180 / .pi
        )
    }
}

private extension Date {
    static var defaultFlightDeparture: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        return calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: tomorrow
        ) ?? tomorrow
    }

    var roundedToNextQuarterHour: Date {
        let interval: TimeInterval = 15 * 60
        return Date(timeIntervalSince1970: ceil(timeIntervalSince1970 / interval) * interval)
    }
}

private struct IPadCharterFeeQuote {
    var knownTotalEUR = 0.0
    var unknownICAOs: [String] = []

    var hasUnknownFees: Bool { !unknownICAOs.isEmpty }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            knownTotalEUR: lhs.knownTotalEUR + rhs.knownTotalEUR,
            unknownICAOs: lhs.unknownICAOs + rhs.unknownICAOs
        )
    }

    static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }
}

extension Color {
    static let dashboardNavy = Color(red: 0.02, green: 0.18, blue: 0.35)
    static let dashboardBlue = Color(red: 0.18, green: 0.50, blue: 0.83)
    static let dashboardBackground = Color(red: 0.96, green: 0.97, blue: 0.985)
}
