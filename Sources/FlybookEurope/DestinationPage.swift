import SwiftUI
import AppKit

enum TimeDisplayMode: String, CaseIterable, Identifiable {
    case local
    case utc

    var id: String { rawValue }
}

enum FlightPlanningMode: String, CaseIterable, Identifiable {
    case roundTrip = "Hin-/Rückflug"
    case multiStop = "Multi-Stop"

    var id: String { rawValue }
}

private enum StartingFuelPreset {
    case full
    case minimum
    case manual
}

struct DestinationPage: View {
    let destination: Destination
    let availableDestinations: [Destination]
    let destinationPickerDestinations: [Destination]
    @Binding var destinationFilterIsActive: Bool
    let destinationFilterIsAvailable: Bool
    let availableOrigins: [AirportReference]
    @Binding var selectedDestinationIndex: Int
    @Binding var plannedMainDestinationArrival: Date?
    @State private var selectedOriginICAO = "EDFZ"
    @State private var landingVoucherRevision = 0
    @AppStorage(LandingVoucherBook.settingKey)
    private var landingVoucherBookEnabled = false
    @State private var outboundDestinationICAO = ""
    @State private var mainDestinationICAO = ""
    @State private var returnOriginICAO = ""
    @State private var returnDestinationICAO = "EDFZ"
    @State private var isRouteReversed = false
    @StateObject private var weatherModel = WeatherViewModel()
    @StateObject private var outboundRouteWindModel = RouteWindViewModel()
    @StateObject private var returnRouteWindModel = RouteWindViewModel()
    @StateObject private var outboundRouteRiskModel = RouteWeatherRiskViewModel()
    @StateObject private var returnRouteRiskModel = RouteWeatherRiskViewModel()
    @StateObject private var outboundEDFZWeatherModel = EDFZWeatherViewModel()
    @StateObject private var returnEDFZWeatherModel = EDFZWeatherViewModel()
    @StateObject private var intermediateWeatherModel = EDFZWeatherViewModel()
    @StateObject private var destinationAirportWeatherModel =
        EDFZWeatherViewModel()
    @StateObject private var destinationReturnWeatherModel =
        EDFZWeatherViewModel()
    @StateObject private var alpineFoehnModel = AlpineFoehnViewModel()
    @State private var outboundFlightDate =
        Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
    @State private var returnFlightDate =
        Calendar.current.date(
            byAdding: .day,
            value: 2,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
    @State private var outboundStartText = "09:00"
    @State private var desiredHomeArrivalText = "17:00"
    @State private var multiStopDepartureText = ""
    @State private var outboundStops = 0
    @State private var returnStops = 0
    @State private var outboundStop1ICAO = ""
    @State private var outboundStop2ICAO = ""
    @State private var returnStop1ICAO = ""
    @State private var returnStop2ICAO = ""
    @State private var cachedRouteAirportOptions: [AirportReference] = []
    @State private var outboundStopsManuallySet = false
    @State private var returnStopsManuallySet = false
    @State private var outboundTrackMilesOverride: Double?
    @State private var returnTrackMilesOverride: Double?
    @State private var outboundFlightAltitudeFeet = FlightAltitudeRules.defaultFeet
    @State private var returnFlightAltitudeFeet = FlightAltitudeRules.defaultFeet
    @State private var timeDisplayMode: TimeDisplayMode = .local
    @State private var showsRestaurantHours = false
    @State private var flightPlanningMode = FlightPlanningMode.roundTrip
    @State private var isOneWay = true
    @State private var outboundReserveNotConsumed = false
    @State private var reserveToggleMustNotEnableRefuel = false
    @State private var refuelAtDestination = false
    @State private var includeLandingFeesInTotal = false
    @State private var isLiveWeatherLoading = false
    @State private var refuelLiters = 70.0
    @State private var manualRefuelPrice: Double?
    @State private var selectedRefuelFuelRaw = AircraftFuelType.mogas.rawValue
    @State private var startingFuelLiters = 1.0
    @State private var startingFuelPreset = StartingFuelPreset.full
    @State private var intermediateICAO = "EDFZ"
    @AppStorage(CalculationSettingsKey.reservationFromTimestamp)
    private var reservationFromTimestamp = Date().timeIntervalSince1970
    @AppStorage(CalculationSettingsKey.reservationUntilTimestamp)
    private var reservationUntilTimestamp =
        Date().addingTimeInterval(12 * 60 * 60).timeIntervalSince1970
    @AppStorage(CalculationSettingsKey.calculatedBlockMinutes)
    private var storedCalculatedBlockMinutes = 0

    @AppStorage(CalculationSettingsKey.tankStopMinutes)
    private var tankStopMinutes =
        CalculationSettings.defaultTankStopMinutes

    @AppStorage(CalculationSettingsKey.vatPercent)
    private var vatPercent =
        CalculationSettings.defaultVATPercent

    @AppStorage(CalculationSettingsKey.preTakeoffGroundMinutes)
    private var preTakeoffGroundMinutes =
        CalculationSettings.defaultPreTakeoffGroundMinutes

    @AppStorage(CalculationSettingsKey.postLandingGroundMinutes)
    private var postLandingGroundMinutes =
        CalculationSettings.defaultPostLandingGroundMinutes

    @AppStorage(CalculationSettingsKey.fuelDisplayUnit)
    private var fuelDisplayUnitRaw = FuelDisplayUnit.liters.rawValue
    @AppStorage(FuelPriceSettingsKey.mainzAvgas)
    private var mainzAvgasPrice = 3.03
    @AppStorage(FuelPriceSettingsKey.mainzMogas)
    private var mainzMogasPrice = 2.59

    private var fuelDisplayUnit: FuelDisplayUnit {
        FuelDisplayUnit(rawValue: fuelDisplayUnitRaw) ?? .liters
    }

    private var preferredFuel: AircraftFuelType {
        AircraftProfileStore.preferredFuel(for: selectedAircraft)
    }

    private var selectedRefuelFuel: AircraftFuelType {
        AircraftFuelType(rawValue: selectedRefuelFuelRaw) ?? preferredFuel
    }

    private func price(_ fuel: AircraftFuelType, at airport: Destination) -> Double? {
        switch fuel { case .avgas: return airport.avgasPricePerLiterEUR; case .ul91: return airport.ul91PricePerLiterEUR; case .ul94: return nil; case .mogas: return airport.mogasPricePerLiterEUR }
    }

    private var refuelAirport: Destination {
        let arrivalICAO = firstLegDestination.icao
        return availableDestinations.first { $0.icao == arrivalICAO }
            ?? destination
    }

    private var destinationFuelPrice: Double? {
        manualRefuelPrice ?? price(selectedRefuelFuel, at: refuelAirport)
    }

    private var activeBase: FlybookBase {
        FlybookBase(rawValue: activeBaseRaw) ?? .lsvMainz
    }

    private var homeAirportICAO: String {
        BaseProfileStore.profile(for: activeBase).homeAirportICAO
    }

    private func homePrice(_ fuel: AircraftFuelType) -> Double? {
        if homeAirportICAO == "EDFZ" {
            switch fuel { case .avgas: return mainzAvgasPrice; case .ul91, .ul94: return nil; case .mogas: return mainzMogasPrice }
        }
        guard let airport = availableDestinations.first(where: { $0.icao == homeAirportICAO }) else { return nil }
        return price(fuel, at: airport)
    }

    private var homeReferencePrice: Double? {
        // Referenz bleibt der im Flugzeugprofil benannte Kraftstoff am
        // aktiven Heimatflugplatz – unabhängig vom am Ziel gewählten Sprit.
        homePrice(preferredFuel)
    }

    private var destinationVATPercent: Double? {
        let code = refuelAirport.country.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return ["DE":19,"DEUTSCHLAND":19,"NL":21,"NIEDERLANDE":21,"DK":25,"DÄNEMARK":25,"CZ":21,"TSCHECHIEN":21,"FR":20,"FRANKREICH":20,"AT":20,"ÖSTERREICH":20,"CH":8.1,"SCHWEIZ":8.1,"SI":22,"SLOWENIEN":22,"HR":25,"KROATIEN":25,"IT":22,"ITALIEN":22][code]
    }

    private var refuelLossEUR: Double? {
        guard refuelAtDestination else { return 0 }
        let foreign = !["DE", "DEUTSCHLAND"].contains(refuelAirport.country.uppercased())
        return CharterMath.refuelLoss(
            grossPricePerLiter: destinationFuelPrice,
            homeReferencePerLiter: homeReferencePrice,
            liters: refuelLiters,
            destinationVATPercent: destinationVATPercent,
            isForeign: foreign
        )
    }

    @AppStorage(AircraftSettingsKey.selectedAircraft)
    private var selectedAircraftRaw =
        AircraftType.a211.rawValue

    @AppStorage(BaseSettingsKey.activeBase)
    private var activeBaseRaw = FlybookBase.lsvMainz.rawValue

    @AppStorage(ETOPSSettingsKey.activeUser)
    private var activeUserRaw =
        FlybookUser.stephan.rawValue

    @AppStorage(ETOPSSettingsKey.greenYellowMinutes)
    private var etopsGreenYellowMinutes =
        ETOPSScale.defaultGreenYellowMinutes

    @AppStorage(ETOPSSettingsKey.orangeRedMinutes)
    private var etopsOrangeRedMinutes =
        ETOPSScale.defaultOrangeRedMinutes

    private var selectedOrigin: AirportReference {
        allRouteAirportOptions.first {
            $0.icao.caseInsensitiveCompare(selectedOriginICAO)
                == .orderedSame
        } ?? .edfz
    }

    private var routeDirectNM: Double {
        AirportDistance.nauticalMiles(
            from: planningOrigin,
            to: planningDestination
        )
    }

    private var destinationReference: AirportReference {
        AirportReference(
            icao: destination.icao,
            name: destination.name,
            latitude: destination.latitude ?? 0,
            longitude: destination.longitude ?? 0,
            elevationFeet: destination.elevationFeet,
            timeZone: DestinationTimeZone.value(
                for: destination,
                weatherTimeZone: weatherModel.weather?.timezone
            ),
            referenceRunway: destination.referenceRunway
        )
    }

    private var planningOrigin: AirportReference {
        selectedOrigin
    }

    private var planningDestination: AirportReference {
        if flightPlanningMode == .roundTrip {
            return destinationReference
        }
        return allRouteAirportOptions.first {
            $0.icao == outboundDestinationICAO
        } ?? destinationReference
    }

    private var planningOriginSelection: Binding<String> {
        Binding(
            get: { planningOrigin.icao },
            set: { newICAO in
                selectedOriginICAO = newICAO
                isRouteReversed = false
            }
        )
    }

    private var planningDestinationSelection: Binding<String> {
        Binding(
            get: { planningDestination.icao },
            set: { newICAO in
                if flightPlanningMode == .roundTrip {
                    outboundDestinationICAO = ""
                    if let index = availableDestinations.firstIndex(where: {
                        $0.icao == newICAO
                    }) {
                        selectedDestinationIndex = index
                    }
                } else {
                    outboundDestinationICAO = newICAO
                }
            }
        )
    }

    private var mainDestination: AirportReference {
        allRouteAirportOptions.first { $0.icao == mainDestinationICAO }
            ?? destinationReference
    }

    private var returnOriginSelection: Binding<String> {
        Binding(
            get: { planningDestination.icao },
            set: { planningDestinationSelection.wrappedValue = $0 }
        )
    }

    private var returnDestinationSelection: Binding<String> {
        Binding(
            get: { secondLegDestination.icao },
            set: { newICAO in
                if flightPlanningMode == .multiStop {
                    if let index = availableDestinations.firstIndex(where: {
                        $0.icao == newICAO
                    }) {
                        selectedDestinationIndex = index
                    }
                } else {
                    returnDestinationICAO = newICAO
                }
            }
        )
    }

    private var destinationPickerOptions: [AirportReference] {
        var result: [AirportReference]
        if destinationFilterIsActive {
            result = isRouteReversed ? [selectedOrigin] : []
        } else {
            result = availableOrigins
        }
        for airport in destinationPickerDestinations {
            guard let latitude = airport.latitude,
                  let longitude = airport.longitude,
                  !result.contains(where: { $0.icao == airport.icao })
            else { continue }
            result.append(
                AirportReference(
                    icao: airport.icao,
                    name: airport.name,
                    latitude: latitude,
                    longitude: longitude,
                    elevationFeet: airport.elevationFeet,
                    timeZone: DestinationTimeZone.value(
                        for: airport,
                        weatherTimeZone: nil
                    )
                )
            )
        }
        return result
    }

    private var planningAirportOptions: [AirportReference] {
        var airports = availableOrigins
        if !airports.contains(where: {
            $0.icao.caseInsensitiveCompare(destinationReference.icao)
                == .orderedSame
        }) {
            airports.append(destinationReference)
        }
        return airports
    }

    private var allRouteAirportOptions: [AirportReference] {
        if !cachedRouteAirportOptions.isEmpty {
            return cachedRouteAirportOptions
        }
        return makeRouteAirportOptions()
    }

    private func makeRouteAirportOptions() -> [AirportReference] {
        var result: [AirportReference] = []
        for destination in availableDestinations {
            guard let latitude = destination.latitude,
                  let longitude = destination.longitude,
                  !result.contains(where: { $0.icao == destination.icao })
            else { continue }
            result.append(
                AirportReference(
                    icao: destination.icao,
                    name: destination.name,
                    latitude: latitude,
                    longitude: longitude,
                    elevationFeet: destination.elevationFeet,
                    timeZone: DestinationTimeZone.value(
                        for: destination,
                        weatherTimeZone: nil
                    ),
                    referenceRunway: destination.referenceRunway
                )
            )
        }
        for origin in availableOrigins where !result.contains(where: {
            $0.icao == origin.icao
        }) {
            result.append(origin)
        }
        return result.sorted { $0.icao < $1.icao }
    }

    private func selectedStops(
        count: Int,
        firstICAO: String,
        secondICAO: String
    ) -> [AirportReference] {
        let selectedICAOs = [firstICAO, secondICAO].prefix(max(0, min(2, count)))
        return selectedICAOs.compactMap { icao in
            guard !icao.isEmpty else { return nil }
            return allRouteAirportOptions.first { $0.icao == icao }
        }
    }

    private var outboundSelectedStopAirports: [AirportReference] {
        selectedStops(
            count: outboundStops,
            firstICAO: outboundStop1ICAO,
            secondICAO: outboundStop2ICAO
        )
    }

    private var returnSelectedStopAirports: [AirportReference] {
        selectedStops(
            count: returnStops,
            firstICAO: returnStop1ICAO,
            secondICAO: returnStop2ICAO
        )
    }

    private var outboundLandingFeeQuote: AirportLandingFeeQuote {
        landingFeeQuote(
            for: outboundSelectedStopAirports + [firstLegDestination],
            on: outboundFlightDate
        )
    }

    private var returnLandingFeeQuote: AirportLandingFeeQuote {
        landingFeeQuote(
            for: returnSelectedStopAirports + [secondLegDestination],
            on: returnFlightDate
        )
    }

    private func landingFeeQuote(
        for landingAirports: [AirportReference],
        on landingDate: Date
    ) -> AirportLandingFeeQuote {
        AirportLandingFeeCalculator.quote(
            for: landingAirports.map(\.icao),
            mtowKilograms: AircraftProfileStore.mtowKilograms(
                for: selectedAircraft
            ),
            hasIncreasedNoiseProtection:
                AircraftProfileStore.hasIncreasedNoiseProtection(
                    for: selectedAircraft
                ),
            landingDate: landingDate,
            landingVoucherBookEnabled: landingVoucherBookEnabled
        )
    }

    private var outboundRouteRiskWaypoints: [AirportReference] {
        [planningOrigin] + outboundSelectedStopAirports + [firstLegDestination]
    }

    private var returnRouteRiskWaypoints: [AirportReference] {
        [secondLegOrigin] + returnSelectedStopAirports + [secondLegDestination]
    }

    private var mapRouteWaypoints: [DestinationMapWaypoint] {
        var airports = [planningOrigin]
            + outboundSelectedStopAirports
            + [firstLegDestination]
        if !isOneWay {
            airports += returnSelectedStopAirports + [secondLegDestination]
        }
        let finalDestinationICAO = flightPlanningMode == .multiStop
            ? secondLegDestination.icao
            : planningDestination.icao
        return airports.map { airport in
            DestinationMapWaypoint(
                latitude: airport.latitude,
                longitude: airport.longitude,
                title: "\(airport.icao) · \(airport.name)",
                isDestination: airport.icao == finalDestinationICAO
            )
        }
    }

    private var intermediateAirport: AirportReference {
        availableOrigins.first {
            $0.icao == intermediateICAO
        } ?? planningDestination
    }

    private var firstLegDestination: AirportReference {
        planningDestination
    }

    private var secondLegOrigin: AirportReference {
        planningDestination
    }

    private var secondLegDestination: AirportReference {
        if flightPlanningMode == .multiStop {
            return destinationReference
        }
        return allRouteAirportOptions.first { $0.icao == returnDestinationICAO }
            ?? selectedOrigin
    }

    private var outboundDirectNM: Double {
        FlightMath.directMiles(
            along: [planningOrigin]
                + outboundSelectedStopAirports
                + [firstLegDestination]
        )
    }

    private var returnDirectNM: Double {
        FlightMath.directMiles(
            along: [secondLegOrigin]
                + returnSelectedStopAirports
                + [secondLegDestination]
        )
    }

    private var calculatedOutboundTrackMiles: Double {
        FlightMath.routeMiles(directNM: outboundDirectNM, stopCount: outboundStops)
    }

    private var calculatedReturnTrackMiles: Double {
        FlightMath.routeMiles(directNM: returnDirectNM, stopCount: returnStops)
    }

    private var outboundTrackMiles: Double {
        outboundTrackMilesOverride ?? calculatedOutboundTrackMiles
    }

    private var returnTrackMiles: Double {
        returnTrackMilesOverride ?? calculatedReturnTrackMiles
    }

    private var outboundTrackMilesBinding: Binding<Double> {
        Binding(
            get: { outboundTrackMiles },
            set: { outboundTrackMilesOverride = max(0, $0) }
        )
    }

    private var returnTrackMilesBinding: Binding<Double> {
        Binding(
            get: { returnTrackMiles },
            set: { returnTrackMilesOverride = max(0, $0) }
        )
    }

    private var outboundCourseDegrees: Double {
        return WindMath.initialBearing(
            latitude1: planningOrigin.latitude,
            longitude1: planningOrigin.longitude,
            latitude2: firstLegDestination.latitude,
            longitude2: firstLegDestination.longitude
        )
    }

    private var outboundAltitudeOptions: [Int] {
        semicircularAltitudeOptions(
            courseDegrees: outboundCourseDegrees
        )
    }

    private var returnAltitudeOptions: [Int] {
        semicircularAltitudeOptions(
            courseDegrees: returnCourseDegrees
        )
    }

    private var returnCourseDegrees: Double {
        return WindMath.initialBearing(
            latitude1: secondLegOrigin.latitude,
            longitude1: secondLegOrigin.longitude,
            latitude2: secondLegDestination.latitude,
            longitude2: secondLegDestination.longitude
        )
    }

    private func semicircularAltitudeOptions(
        courseDegrees: Double
    ) -> [Int] {
        FlightAltitudeRules.options(
            forCourseDegrees: courseDegrees
        )
    }

    private var selectedAircraft: AircraftType {
        AircraftType(rawValue: selectedAircraftRaw)
            ?? .a211
    }

    private var aircraftForActiveBase: [AircraftType] {
        AircraftProfileStore.aircraft(for: activeBase)
    }

    private var hourlyRateEUR: Double {
        AircraftProfileStore.hourlyRate(
            for: selectedAircraft
        )
    }

    private var cruiseGroundSpeedKnots: Double {
        // Nur Sicherheitswert für noch unvollständige TAS-Tabellen.
        selectedAircraft.defaultCruiseGroundSpeedKnots
    }

    private var outboundFuelConsumptionPerHour: Double {
        AircraftProfileStore.fuelConsumption(
            for: selectedAircraft,
            atPressureAltitudeFeet: Double(outboundFlightAltitudeFeet)
        )
    }

    private var returnFuelConsumptionPerHour: Double {
        AircraftProfileStore.fuelConsumption(
            for: selectedAircraft,
            atPressureAltitudeFeet: Double(returnFlightAltitudeFeet)
        )
    }

    private var averageFuelConsumptionPerHour: Double {
        let outboundMinutes = Double(outboundCalculatedBlockMinutes)
        let returnMinutes = isOneWay
            ? 0
            : Double(returnCalculatedBlockMinutes)
        let total = outboundMinutes + returnMinutes
        guard total > 0 else { return outboundFuelConsumptionPerHour }
        return (
            outboundMinutes * outboundFuelConsumptionPerHour
            + returnMinutes * returnFuelConsumptionPerHour
        ) / total
    }

    private var usableFuel: Double {
        AircraftProfileStore.usableFuel(
            for: selectedAircraft
        )
    }

    private var climbPerformance: ClimbPerformance {
        AircraftProfileStore.climbPerformance(for: selectedAircraft)
    }

    private var cruisePerformance: CruisePerformance {
        AircraftProfileStore.cruisePerformance(for: selectedAircraft)
    }

    private var alternateSixtyFivePercentCruisePerformance: CruisePerformance {
        AircraftProfileStore.cruisePerformance(
            for: selectedAircraft,
            powerPercent: 65
        )
    }

    private var alternateCruiseSpeedAt1500FeetKnots: Double {
        alternateSixtyFivePercentCruisePerformance
            .tasKnots(atPressureAltitudeFeet: 1500)
            ?? selectedAircraft.defaultCruiseGroundSpeedKnots
    }

    private var alternateFuelAt1500FeetLitersPerHour: Double {
        alternateSixtyFivePercentCruisePerformance
            .fuelConsumptionPerHour(atPressureAltitudeFeet: 1500)
            ?? selectedAircraft.defaultFuelConsumptionPerHour
    }

    private var nearestAlternateAirports: [AlternateAirport] {
        AlternateAirport.nearestAirports(
            for: destination,
            availableDestinations: availableDestinations,
            cruiseSpeedKnots: alternateCruiseSpeedAt1500FeetKnots,
            fuelConsumptionLitersPerHour:
                alternateFuelAt1500FeetLitersPerHour
        )
    }

    @AppStorage(CalculationSettingsKey.weekdayDiscountEnabled)
    private var weekdayDiscountEnabled =
        CalculationSettings.defaultWeekdayDiscountEnabled

    @AppStorage(CalculationSettingsKey.reserveMinutes)
    private var reserveMinutes =
        CalculationSettings.defaultReserveMinutes

    @AppStorage(
        CalculationSettingsKey.prepaymentDiscount15To29Enabled
    )
    private var prepaymentDiscount15To29Enabled =
        CalculationSettings
            .defaultPrepaymentDiscount15To29Enabled

    @AppStorage(
        CalculationSettingsKey.prepaymentDiscount30PlusEnabled
    )
    private var prepaymentDiscount30PlusEnabled =
        CalculationSettings
            .defaultPrepaymentDiscount30PlusEnabled

    var body: some View {
        let _ = landingVoucherRevision
        GeometryReader { geometry in
            let scale = min(
                geometry.size.width / 1800.0,
                geometry.size.height / 1200.0
            )

            pageContent
                .frame(width: 1800, height: 1200)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(
                    width: 1800 * scale,
                    height: 1200 * scale,
                    alignment: .topLeading
                )
                .position(
                    x: geometry.size.width / 2.0,
                    y: geometry.size.height / 2.0
                )
        }
        .background(FlybookColor.background)
        .onReceive(NotificationCenter.default.publisher(for: LandingVoucherBook.didRefreshNotification)) { _ in
            landingVoucherRevision += 1
        }
        .id(selectedAircraftRaw)
        .task(id: weatherTaskID) {
            guard await weatherLoadMayProceed(afterMilliseconds: 800) else {
                return
            }
            await weatherModel.load(
                destination: destination,
                targetInstants: weatherTargetInstants,
                forceRefresh: false
            )
        }
        .task(id: outboundWindTaskID) {
            guard await weatherLoadMayProceed(afterMilliseconds: 250) else {
                return
            }
            await outboundRouteWindModel.load(
                destination: firstLegDestination,
                origin: planningOrigin,
                plannedStart: outboundStartInstant,
                plannedEnd: outboundArrivalInstantForWeather,
                altitudeOptions: outboundAltitudeOptions,
                selectedAltitudeFeet:
                    outboundFlightAltitudeFeet,
                isReturn: false,
                directNM: outboundDirectNM,
                trackMilesNM: outboundTrackMiles,
                stopCount: outboundStops,
                tankStopMinutes: tankStopMinutes,
                fallbackCruiseSpeedKnots: cruiseGroundSpeedKnots,
                departurePressureAltitudeFeet: planningOrigin.elevationFeet,
                climbPerformance: climbPerformance,
                cruisePerformance: cruisePerformance
            )
        }
        .task(id: returnWindTaskID) {
            guard await weatherLoadMayProceed(afterMilliseconds: 250) else {
                return
            }
            await returnRouteWindModel.load(
                destination: secondLegDestination,
                origin: secondLegOrigin,
                plannedStart: returnDepartureInstantForWeather,
                plannedEnd: returnArrivalInstant,
                altitudeOptions: returnAltitudeOptions,
                selectedAltitudeFeet:
                    returnFlightAltitudeFeet,
                isReturn: false,
                directNM: returnDirectNM,
                trackMilesNM: returnTrackMiles,
                stopCount: returnStops,
                tankStopMinutes: tankStopMinutes,
                fallbackCruiseSpeedKnots: cruiseGroundSpeedKnots,
                departurePressureAltitudeFeet: secondLegOrigin.elevationFeet,
                climbPerformance: climbPerformance,
                cruisePerformance: cruisePerformance
            )
        }
        .task(id: outboundRouteRiskTaskID) {
            guard await weatherLoadMayProceed(afterMilliseconds: 1_000) else {
                return
            }
            await outboundRouteRiskModel.load(
                waypoints: outboundRouteRiskWaypoints,
                start: outboundStartInstant,
                end: outboundArrivalInstantForWeather,
                cruiseAltitudeFeet: outboundFlightAltitudeFeet
            )
        }
        .task(id: returnRouteRiskTaskID) {
            guard await weatherLoadMayProceed(afterMilliseconds: 1_000) else {
                return
            }
            await returnRouteRiskModel.load(
                waypoints: returnRouteRiskWaypoints,
                start: returnDepartureInstantForWeather,
                end: returnArrivalInstant,
                cruiseAltitudeFeet: returnFlightAltitudeFeet
            )
        }
        .task(id: planningAirportWeatherTaskID) {
            guard await weatherLoadMayProceed(afterMilliseconds: 80) else {
                return
            }
            await refreshPlanningAirportWeather(forceRefresh: false)
        }
        .task(id: alpineFoehnTaskID) {
            guard await weatherLoadMayProceed(afterMilliseconds: 1_200) else {
                return
            }
            await alpineFoehnModel.load(ifRelevant: alpineRelevantAirports)
        }
        .onChange(of: outboundRouteWindModel.wind) { wind in
            guard let wind else { return }
            if !outboundStopsManuallySet {
                outboundStops = max(
                    outboundStops,
                    recommendedStopCount(
                        headwindKnots: wind.outboundHeadwindKnots,
                        directNM: outboundDirectNM,
                        climbDeparturePressureAltitudeFeet: planningOrigin.elevationFeet,
                        climbTargetPressureAltitudeFeet: Double(outboundFlightAltitudeFeet)
                    )
                )
            }
        }
        .onChange(of: returnRouteWindModel.wind) { wind in
            guard let wind else { return }
            if !returnStopsManuallySet {
                returnStops = max(
                    returnStops,
                    recommendedStopCount(
                        headwindKnots: wind.outboundHeadwindKnots,
                        directNM: returnDirectNM,
                        climbDeparturePressureAltitudeFeet: secondLegOrigin.elevationFeet,
                        climbTargetPressureAltitudeFeet: Double(returnFlightAltitudeFeet)
                    )
                )
            }
        }
        .onChange(of: outboundFlightAltitudeFeet) { altitude in
            outboundRouteWindModel.selectAltitude(altitude)
        }
        .onChange(of: returnFlightAltitudeFeet) { altitude in
            returnRouteWindModel.selectAltitude(altitude)
        }
        .onChange(of: outboundRouteWindModel.bestLevelFeet) { bestLevel in
            guard let bestLevel else { return }
            outboundFlightAltitudeFeet = nearestAltitude(
                to: bestLevel,
                in: outboundAltitudeOptions
            )
        }
        .onChange(of: returnRouteWindModel.bestLevelFeet) { bestLevel in
            guard let bestLevel else { return }
            returnFlightAltitudeFeet = nearestAltitude(
                to: bestLevel,
                in: returnAltitudeOptions
            )
        }
        .onChange(of: etopsGreenYellowMinutes) { _ in
            applyAutomaticStopSelection()
        }
        .onChange(of: etopsOrangeRedMinutes) { _ in
            applyAutomaticStopSelection()
        }
        .onChange(of: destination.icao) { _ in
            mainDestinationICAO = destination.icao
            if flightPlanningMode == .roundTrip {
                outboundDestinationICAO = ""
                returnOriginICAO = destination.icao
            }
            if flightPlanningMode == .multiStop {
                returnDestinationICAO = destination.icao
            }
            resetRefuelEntry()
            resetAutomaticStops()
            normalizeFlightAltitudes()
            if flightPlanningMode == .roundTrip {
                desiredHomeArrivalText = standardArrivalText(
                    on: returnFlightDate
                )
            }
        }
        .onChange(of: selectedOriginICAO) { _ in
            resetRefuelEntry()
            normalizeFlightAltitudes()
            if flightPlanningMode == .roundTrip {
                desiredHomeArrivalText = standardArrivalText(
                    on: returnFlightDate
                )
            }
        }
        .onChange(of: returnDestinationICAO) { _ in
            returnTrackMilesOverride = nil
            if flightPlanningMode == .roundTrip {
                desiredHomeArrivalText = standardArrivalText(
                    on: returnFlightDate
                )
            }
        }
        .onChange(of: returnOriginICAO) { _ in
            returnTrackMilesOverride = nil
        }
        .onChange(of: outboundDestinationICAO) { newICAO in
            returnOriginICAO = newICAO.isEmpty
                ? destinationReference.icao
                : newICAO
            outboundTrackMilesOverride = nil
            returnTrackMilesOverride = nil
        }
        .onChange(of: isRouteReversed) { _ in
            resetRefuelEntry()
            resetAutomaticStops()
            normalizeFlightAltitudes()
            if flightPlanningMode == .roundTrip {
                desiredHomeArrivalText = standardArrivalText(
                    on: returnFlightDate
                )
            }
        }
        .onChange(of: flightPlanningMode) { mode in
            resetRefuelEntry()
            if mode == .roundTrip {
                let today =
                    Calendar.current.startOfDay(for: Date())
                outboundFlightDate =
                    Calendar.current.date(
                        byAdding: .day,
                        value: 1,
                        to: today
                    ) ?? today
                returnFlightDate =
                    Calendar.current.date(
                        byAdding: .day,
                        value: 2,
                        to: today
                    ) ?? today
                outboundStartText = "09:00"
                desiredHomeArrivalText = standardArrivalText(
                    on: returnFlightDate
                )
            }
            if mode == .multiStop,
               intermediateICAO == planningOrigin.icao
                || intermediateICAO == destination.icao
            {
                intermediateICAO =
                    availableOrigins.first {
                        $0.icao != planningOrigin.icao
                            && $0.icao != destination.icao
                    }?.icao ?? intermediateICAO
            }
            resetAutomaticStops()
            outboundTrackMilesOverride = nil
            returnTrackMilesOverride = nil
            normalizeFlightAltitudes()
        }
        .onChange(of: intermediateICAO) { _ in
            resetRefuelEntry()
            guard flightPlanningMode == .multiStop else { return }
            resetAutomaticStops()
            outboundTrackMilesOverride = nil
            returnTrackMilesOverride = nil
            normalizeFlightAltitudes()
        }
        .onChange(of: outboundFlightDate) { _ in
            outboundStops = 0
            outboundStopsManuallySet = false
            outboundTrackMilesOverride = nil
        }
        .onChange(of: returnFlightDate) { _ in
            returnStops = 0
            returnStopsManuallySet = false
            returnTrackMilesOverride = nil
        }
        .onChange(of: outboundStops) { _ in
            outboundTrackMilesOverride = nil
        }
        .onChange(of: returnStops) { _ in
            returnTrackMilesOverride = nil
        }
        .onChange(of: outboundStop1ICAO) { _ in
            outboundTrackMilesOverride = nil
        }
        .onChange(of: outboundStop2ICAO) { _ in
            outboundTrackMilesOverride = nil
        }
        .onChange(of: returnStop1ICAO) { _ in
            returnTrackMilesOverride = nil
        }
        .onChange(of: returnStop2ICAO) { _ in
            returnTrackMilesOverride = nil
        }
        .onChange(of: totalCommercialBlockMinutes) { _ in
            storedCalculatedBlockMinutes = commercialEquivalentBlockMinutes
        }
        .onChange(of: totalRequiredFuelForRoute) { _ in
            let suppressAutomaticActivation =
                reserveToggleMustNotEnableRefuel
            reserveToggleMustNotEnableRefuel = false
            if refuelAtDestination {
                selectSuggestedRefuelAmount()
            }
            if routeExceedsUsableFuel && !suppressAutomaticActivation {
                refuelAtDestination = true
                selectSuggestedRefuelAmount()
            }
        }
        .onChange(of: outboundRequiredFuel) { _ in
            updateAutomaticStartingFuel()
        }
        .onChange(of: usableFuel) { _ in
            updateAutomaticStartingFuel()
            if routeExceedsUsableFuel {
                refuelAtDestination = true
                selectSuggestedRefuelAmount()
            }
        }
        .onChange(of: startingFuelLiters) { _ in
            if refuelAtDestination {
                selectSuggestedRefuelAmount()
            }
        }
        .onChange(of: outboundStartInstant) { _ in
            synchronizeReservationWindow()
        }
        .onChange(of: selectedAircraftRaw) { _ in
            resetRefuelEntry()
        }
        .onChange(of: reservationArrivalInstant) { _ in
            synchronizeReservationWindow()
        }
        .onChange(of: plannedMainDestinationArrivalInstant) { instant in
            plannedMainDestinationArrival = instant
        }
        .onAppear {
            if cachedRouteAirportOptions.isEmpty {
                cachedRouteAirportOptions = makeRouteAirportOptions()
            }
            if mainDestinationICAO.isEmpty {
                mainDestinationICAO = destination.icao
            }
            if returnOriginICAO.isEmpty {
                returnOriginICAO = planningDestination.icao
            }
            outboundStartText = "09:00"
            if flightPlanningMode == .roundTrip {
                desiredHomeArrivalText = standardArrivalText(
                    on: returnFlightDate
                )
            }
            normalizeFlightAltitudes()
            storedCalculatedBlockMinutes = commercialEquivalentBlockMinutes
            selectFullStartingFuel()
            if routeExceedsUsableFuel {
                refuelAtDestination = true
                selectSuggestedRefuelAmount()
            }
            synchronizeReservationWindow()
            plannedMainDestinationArrival =
                plannedMainDestinationArrivalInstant
        }
    }

    private func resetRefuelEntry() {
        refuelAtDestination = routeExceedsUsableFuel
        refuelLiters = 0
        manualRefuelPrice = nil
        selectedRefuelFuelRaw = preferredFuel.rawValue
        selectFullStartingFuel()
        if refuelAtDestination {
            selectSuggestedRefuelAmount()
        }
    }

    private var outboundStopsBinding: Binding<Int> {
        Binding(
            get: { outboundStops },
            set: {
                outboundStops = $0
                outboundStopsManuallySet = true
            }
        )
    }

    private var returnStopsBinding: Binding<Int> {
        Binding(
            get: { returnStops },
            set: {
                returnStops = $0
                returnStopsManuallySet = true
            }
        )
    }

    private func resetAutomaticStops() {
        outboundStops = 0
        returnStops = 0
        outboundStopsManuallySet = false
        returnStopsManuallySet = false
    }

    private func normalizeFlightAltitudes() {
        outboundFlightAltitudeFeet = nearestAltitude(
            to: outboundFlightAltitudeFeet,
            in: outboundAltitudeOptions
        )
        returnFlightAltitudeFeet = nearestAltitude(
            to: returnFlightAltitudeFeet,
            in: returnAltitudeOptions
        )
    }

    private func nearestAltitude(
        to current: Int,
        in options: [Int]
    ) -> Int {
        FlightAltitudeRules.nearest(
            to: current,
            in: options
        )
    }

    private func recommendedStopCount(
        headwindKnots: Double,
        directNM: Double,
        climbDeparturePressureAltitudeFeet: Double,
        climbTargetPressureAltitudeFeet: Double
    ) -> Int {
        for stopCount in 0...2 {
            let legMinutes =
                FlightMath.adjustedPerLegMinutes(
                    directNM: directNM,
                    stopCount: stopCount,
                    headwindKnots: headwindKnots,
                    tankStopMinutes: tankStopMinutes,
                    cruiseGroundSpeedKnots:
                        cruiseGroundSpeedKnots,
                    climbDeparturePressureAltitudeFeet: climbDeparturePressureAltitudeFeet,
                    climbTargetPressureAltitudeFeet: climbTargetPressureAltitudeFeet,
                    climbPerformance: climbPerformance,
                    cruisePerformance: cruisePerformance,
                    preTakeoffGroundMinutes: preTakeoffGroundMinutes,
                    postLandingGroundMinutes: postLandingGroundMinutes
                )

            if !ETOPSScale.isRed(
                travelMinutes: legMinutes,
                greenYellow: etopsGreenYellowMinutes,
                orangeRed: etopsOrangeRedMinutes
            ) {
                return stopCount
            }
        }

        return 2
    }

    private func applyAutomaticStopSelection() {
        if !outboundStopsManuallySet,
           let wind = outboundRouteWindModel.wind {
            outboundStops = max(
                outboundStops,
                recommendedStopCount(
                    headwindKnots: wind.outboundHeadwindKnots,
                    directNM: outboundDirectNM,
                    climbDeparturePressureAltitudeFeet: planningOrigin.elevationFeet,
                    climbTargetPressureAltitudeFeet: Double(outboundFlightAltitudeFeet)
                )
            )
        }
        if !returnStopsManuallySet,
           let wind = returnRouteWindModel.wind {
            returnStops = max(
                returnStops,
                recommendedStopCount(
                    headwindKnots: wind.outboundHeadwindKnots,
                    directNM: returnDirectNM,
                    climbDeparturePressureAltitudeFeet: secondLegOrigin.elevationFeet,
                    climbTargetPressureAltitudeFeet: Double(returnFlightAltitudeFeet)
                )
            )
        }
    }

    private var outboundWindTaskID: String {
        windTaskID(
            prefix: "out-wind",
            anchor: outboundStartInstant,
            stopCount: outboundStops
        )
    }

    private var returnWindTaskID: String {
        windTaskID(
            prefix: "ret-wind",
            anchor: returnArrivalInstant,
            stopCount: returnStops
        )
    }

    private var outboundRouteRiskTaskID: String {
        "risk-out-" + outboundRouteRiskWaypoints.map(\.icao).joined(separator: "-")
            + "-\(Int(outboundStartInstant.timeIntervalSince1970 / 1800))"
            + "-\(Int(outboundArrivalInstantForWeather.timeIntervalSince1970 / 1800))"
            + "-alt\(outboundFlightAltitudeFeet)"
    }

    private var returnRouteRiskTaskID: String {
        "risk-ret-" + returnRouteRiskWaypoints.map(\.icao).joined(separator: "-")
            + "-\(Int(returnDepartureInstantForWeather.timeIntervalSince1970 / 1800))"
            + "-\(Int(returnArrivalInstant.timeIntervalSince1970 / 1800))"
            + "-alt\(returnFlightAltitudeFeet)"
    }

    private var planningAirportWeatherTaskID: String {
        let route = [
            planningOrigin.icao,
            firstLegDestination.icao,
            secondLegOrigin.icao,
            secondLegDestination.icao,
            flightPlanningMode == .multiStop
                ? intermediateAirport.icao
                : "direct"
        ].joined(separator: "-")
        return dateTaskID(
            prefix: "planning-\(flightPlanningMode.rawValue)-\(route)",
            date: outboundFlightDate
        )
        + "-"
        + dateTaskID(prefix: "return-\(route)", date: returnFlightDate)
    }

    private var weatherTaskID: String {
        let stamps = weatherTargetInstants.map { String(Int($0.timeIntervalSince1970 / 1800)) }
        return ([destination.icao] + stamps).joined(separator: "-")
    }

    private var alpineRelevantAirports: [AirportReference] {
        [
            planningOrigin,
            firstLegDestination,
            secondLegOrigin,
            secondLegDestination
        ]
    }

    private var alpineFoehnTaskID: String {
        "foehn-" + alpineRelevantAirports.map(\.icao).joined(separator: "-")
    }

    /// Kurze Aenderungen an Datum, Uhrzeit oder Route werden gebuendelt. So
    /// startet beim Tippen/Scrollen nur der letzte fachlich relevante Abruf.
    private func weatherLoadMayProceed(
        afterMilliseconds milliseconds: UInt64
    ) async -> Bool {
        do {
            try await Task.sleep(
                nanoseconds: milliseconds * 1_000_000
            )
        } catch {
            return false
        }
        return !Task.isCancelled
    }

    private func dateTaskID(prefix: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(prefix)-\(destination.icao)-\(formatter.string(from: date))"
    }

    private func windTaskID(
        prefix: String,
        anchor: Date,
        stopCount: Int
    ) -> String {
        let anchorBucket =
            Int(anchor.timeIntervalSince1970 / 300)
        let trackMiles = prefix.hasPrefix("out")
            ? outboundTrackMiles
            : returnTrackMiles

        return
            "\(prefix)-\(destination.icao)-"
            + "\(anchorBucket)-\(stopCount)-"
            + selectedAircraftRaw
            + "-\(planningOrigin.icao)-\(planningDestination.icao)"
            + "-\(flightPlanningMode.rawValue)"
            + "-\(intermediateICAO)"
            + "-M\(trackMiles)"
            + "-P\(cruisePerformance.powerPercent)"
            + "-T\(cruisePerformance.tasAt1000Feet)"
            + "-\(cruisePerformance.tasAt5000Feet)"
            + "-\(cruisePerformance.tasAt10000Feet)"
            + "-C\(climbPerformance.timeAt1000FeetMinutes)"
            + "-\(climbPerformance.timeAt5000FeetMinutes)"
            + "-\(climbPerformance.timeAt10000FeetMinutes)"
    }

    private var displayTimeZone: TimeZone {
        timeDisplayMode == .utc
            ? TimeZone(secondsFromGMT: 0)!
            : planningOrigin.timeZone
    }

    private var outboundTravelMinutesForWeather: Int {
        FlightMath.adjustedMinutes(
            directNM: outboundDirectNM,
            stopCount: outboundStops,
            headwindKnots: outboundRouteWindModel.wind?.outboundHeadwindKnots,
            tankStopMinutes: tankStopMinutes,
            cruiseGroundSpeedKnots:
                cruiseGroundSpeedKnots,
            climbDeparturePressureAltitudeFeet: planningOrigin.elevationFeet,
            climbTargetPressureAltitudeFeet: Double(outboundFlightAltitudeFeet),
            climbPerformance: climbPerformance,
            cruisePerformance: cruisePerformance,
            trackMilesNM: outboundTrackMiles,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes
        )
    }

    private var returnTravelMinutesForWeather: Int {
        FlightMath.adjustedMinutes(
            directNM: returnDirectNM,
            stopCount: returnStops,
            headwindKnots:
                returnRouteWindModel.wind?
                    .outboundHeadwindKnots,
            tankStopMinutes: tankStopMinutes,
            cruiseGroundSpeedKnots:
                cruiseGroundSpeedKnots,
            climbDeparturePressureAltitudeFeet: secondLegOrigin.elevationFeet,
            climbTargetPressureAltitudeFeet: Double(returnFlightAltitudeFeet),
            climbPerformance: climbPerformance,
            cruisePerformance: cruisePerformance,
            trackMilesNM: returnTrackMiles,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes
        )
    }

    private var totalCalculatedBlockMinutes: Int {
        outboundCalculatedBlockMinutes
            + (isOneWay ? 0 : returnCalculatedBlockMinutes)
    }

    private var totalCommercialBlockMinutesByLeg: [Int] {
        isOneWay
            ? [outboundCalculatedBlockMinutes]
            : [outboundCalculatedBlockMinutes, returnCalculatedBlockMinutes]
    }

    private var totalCommercialBlockMinutes: Double {
        CharterMath.commercialTotalDecimalHours(
            legMinutes: totalCommercialBlockMinutesByLeg
        ) * 60
    }

    private var commercialEquivalentBlockMinutes: Int {
        CharterMath.commercialEquivalentMinutes(
            legMinutes: totalCommercialBlockMinutesByLeg
        )
    }

    private var outboundCalculatedBlockMinutes: Int {
        FlightMath.adjustedBlockMinutes(
            directNM: outboundDirectNM,
            stopCount: outboundStops,
            headwindKnots:
                outboundRouteWindModel.wind?.outboundHeadwindKnots,
            cruiseGroundSpeedKnots: cruiseGroundSpeedKnots,
            climbDeparturePressureAltitudeFeet:
                planningOrigin.elevationFeet,
            climbTargetPressureAltitudeFeet:
                Double(outboundFlightAltitudeFeet),
            climbPerformance: climbPerformance,
            cruisePerformance: cruisePerformance,
            trackMilesNM: outboundTrackMiles,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes
        )
    }

    private var returnCalculatedBlockMinutes: Int {
        FlightMath.adjustedBlockMinutes(
            directNM: returnDirectNM,
            stopCount: returnStops,
            headwindKnots:
                returnRouteWindModel.wind?.outboundHeadwindKnots,
            cruiseGroundSpeedKnots: cruiseGroundSpeedKnots,
            climbDeparturePressureAltitudeFeet:
                secondLegOrigin.elevationFeet,
            climbTargetPressureAltitudeFeet:
                Double(returnFlightAltitudeFeet),
            climbPerformance: climbPerformance,
            cruisePerformance: cruisePerformance,
            trackMilesNM: returnTrackMiles,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes
        )
    }

    private var reserveFuelPerLeg: Double {
        outboundFuelConsumptionPerHour * Double(reserveMinutes) / 60.0
    }

    private var outboundBlockFuel: Double {
        Double(outboundCalculatedBlockMinutes)
            * outboundFuelConsumptionPerHour / 60.0
    }

    private var outboundRequiredFuel: Double {
        outboundBlockFuel + reserveFuelPerLeg
    }

    private var secondLegFullRequiredFuel: Double {
        guard !isOneWay else { return 0 }
        let blockFuel =
            Double(returnCalculatedBlockMinutes)
            * returnFuelConsumptionPerHour / 60.0
        let returnReserve = returnFuelConsumptionPerHour
            * Double(reserveMinutes) / 60.0
        return blockFuel + returnReserve
    }

    private var totalRequiredFuelForRoute: Double {
        let blockFuel = outboundBlockFuel
            + (isOneWay ? 0 : Double(returnCalculatedBlockMinutes)
                * returnFuelConsumptionPerHour / 60.0)
        let reserves = CharterMath.requiredReserveLiters(
            outboundConsumptionPerHour: outboundFuelConsumptionPerHour,
            returnConsumptionPerHour:
                isOneWay ? nil : returnFuelConsumptionPerHour,
            reserveMinutes: reserveMinutes,
            outboundReserveIsReused:
                !isOneWay && outboundReserveNotConsumed
        )
        return blockFuel + reserves
    }

    private var routeExceedsUsableFuel: Bool {
        usableFuel > 0 && totalRequiredFuelForRoute > usableFuel
    }

    private var refuelAtDestinationBinding: Binding<Bool> {
        Binding(
            get: { refuelAtDestination },
            set: { isEnabled in
                refuelAtDestination = isEnabled
                if isEnabled {
                    selectSuggestedRefuelAmount()
                }
            }
        )
    }

    private var outboundReserveNotConsumedBinding: Binding<Bool> {
        Binding(
            get: { outboundReserveNotConsumed },
            set: { newValue in
                reserveToggleMustNotEnableRefuel = true
                outboundReserveNotConsumed = newValue
            }
        )
    }

    private var startingFuelMaximumDisplayed: Int {
        max(1, Int(floor(fuelDisplayUnit.fromLiters(usableFuel))))
    }

    private var startingFuelDisplayedBinding: Binding<Int> {
        Binding(
            get: {
                min(
                    startingFuelMaximumDisplayed,
                    max(1, Int(ceil(fuelDisplayUnit.fromLiters(startingFuelLiters))))
                )
            },
            set: {
                startingFuelPreset = .manual
                startingFuelLiters = fuelDisplayUnit.toLiters(Double($0))
            }
        )
    }

    private func selectMinimumStartingFuel() {
        startingFuelPreset = .minimum
        startingFuelLiters = min(
            max(1, usableFuel),
            max(1, roundedUpForFuelDisplay(outboundRequiredFuel))
        )
    }

    private func selectFullStartingFuel() {
        startingFuelPreset = .full
        startingFuelLiters = max(1, usableFuel)
    }

    private func updateAutomaticStartingFuel() {
        switch startingFuelPreset {
        case .minimum:
            selectMinimumStartingFuel()
        case .full:
            selectFullStartingFuel()
        case .manual:
            break
        }
    }

    private func selectSuggestedRefuelAmount() {
        refuelLiters = minimumSuggestedRefuelLiters
    }

    private var minimumSuggestedRefuelLiters: Double {
        let displayedFirstLegMinimum = roundedUpForFuelDisplay(
            outboundRequiredFuel
        )
        return roundedUpForFuelDisplay(
            CharterMath.suggestedRefuelLiters(
                startingFuelLiters: startingFuelLiters,
                firstLegBlockFuelLiters: outboundBlockFuel,
                firstLegRequiredFuelLiters: displayedFirstLegMinimum,
                secondLegRequiredFuelLiters: secondLegFullRequiredFuel,
                remainingFirstLegFuelIsAvailable:
                    outboundReserveNotConsumed
            )
        )
    }

    private var recognizedFuelAfterFirstLeg: Double {
        let deduction = outboundReserveNotConsumed
            ? outboundBlockFuel
            : roundedUpForFuelDisplay(outboundRequiredFuel)
        return max(0, startingFuelLiters - deduction)
    }

    private var estimatedFuelAtTripEnd: Double {
        guard !isOneWay else {
            return max(0, startingFuelLiters - outboundBlockFuel)
        }
        let returnBlockFuel =
            Double(returnCalculatedBlockMinutes)
            * returnFuelConsumptionPerHour
            / 60.0
        return recognizedFuelAfterFirstLeg + refuelLiters - returnBlockFuel
    }

    private func roundedUpForFuelDisplay(_ liters: Double) -> Double {
        let displayed = fuelDisplayUnit.fromLiters(max(0, liters))
        let precisionFactor = fuelDisplayUnit == .liters ? 1.0 : 10.0
        let roundedDisplayed =
            ceil(displayed * precisionFactor) / precisionFactor
        return fuelDisplayUnit.toLiters(roundedDisplayed)
    }

    private var requiredReservationBlockHours: Double {
        ReservationBreakdown.calculate(
            from: Date(timeIntervalSince1970: reservationFromTimestamp),
            until: Date(timeIntervalSince1970: reservationUntilTimestamp)
        ).requiredBlockHours
    }

    private var outboundStartInstant: Date {
        return FlightDateTime.instant(
            date: outboundFlightDate,
            timeText: outboundStartText,
            timeZone: displayTimeZone
        ) ?? outboundFlightDate
    }

    private var outboundArrivalInstantForWeather: Date {
        outboundStartInstant.addingTimeInterval(
            TimeInterval(
                outboundTravelMinutesForWeather * 60
            )
        )
    }

    private var plannedMainDestinationArrivalInstant: Date {
        flightPlanningMode == .multiStop
            ? returnArrivalInstant
            : outboundArrivalInstantForWeather
    }

    private var returnArrivalInstant: Date {
        if flightPlanningMode == .multiStop {
            return returnDepartureInstantForWeather.addingTimeInterval(
                TimeInterval(returnTravelMinutesForWeather * 60)
            )
        }
        return FlightDateTime.instant(
            date: returnFlightDate,
            timeText: desiredHomeArrivalText,
            timeZone: displayTimeZone
        ) ?? returnFlightDate
    }

    private var returnDepartureInstantForWeather: Date {
        if flightPlanningMode == .multiStop {
            let multiStopTimeZone =
                timeDisplayMode == .utc
                    ? TimeZone(secondsFromGMT: 0)!
                    : secondLegOrigin.timeZone
            if !multiStopDepartureText.isEmpty,
               let manualDeparture = FlightDateTime.instant(
                    date: returnFlightDate,
                    timeText: multiStopDepartureText,
                    timeZone: multiStopTimeZone
               )
            {
                return manualDeparture
            }
            let rawDeparture = outboundArrivalInstantForWeather
                .addingTimeInterval(TimeInterval(tankStopMinutes * 60))
            let roundedTimestamp =
                ceil(rawDeparture.timeIntervalSince1970 / 300) * 300
            return Date(timeIntervalSince1970: roundedTimestamp)
        }
        return returnArrivalInstant.addingTimeInterval(
            TimeInterval(
                -returnTravelMinutesForWeather * 60
            )
        )
    }

    private var reservationArrivalInstant: Date {
        isOneWay
            ? outboundArrivalInstantForWeather
            : returnArrivalInstant
    }

    private func synchronizeReservationWindow() {
        reservationFromTimestamp =
            outboundStartInstant
                .addingTimeInterval(-60 * 60)
                .timeIntervalSince1970
        reservationUntilTimestamp =
            reservationArrivalInstant
                .addingTimeInterval(60 * 60)
                .timeIntervalSince1970
    }

    private var weatherTargetInstants: [Date] {
        [outboundArrivalInstantForWeather, returnDepartureInstantForWeather]
    }

    private var pageContent: some View {
        ZStack(alignment: .topLeading) {
            FlybookColor.background

            VStack(alignment: .leading, spacing: 0) {
                header
                    .frame(
                        width: 675,
                        alignment: .leading
                    )

                airportSection
                    .frame(width: 675)
                    .padding(.top, 8)

                flightSection
                    .frame(width: 675, height: 870, alignment: .top)
                    .padding(.top, 8)

            }
            .frame(
                width: 675,
                height: 1144,
                alignment: .top
            )
            .offset(x: 34, y: 28)

            VStack(spacing: 8) {
                fiveDayForecastSection

                tenDayForecastSection

                mapAndImageSection

                calculationRowSection
            }
            .frame(
                width: 1010,
                height: 1144,
                alignment: .top
            )
            .position(x: 1260, y: 600)
        }
    }

    private var displayedHeaderDestination: Destination {
        destination
    }

    private var headerSubtitle: String {
        let shown = displayedHeaderDestination
        let elevation = Int(shown.elevationFeet.rounded())
        return "\(countryFlag(shown.country))  ·  "
            + "\(shown.icao)  ·  "
            + "HÖHE \(elevation) FT"
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(displayedHeaderDestination.name.uppercased())
                    .font(
                        .system(
                            size: 42,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(FlybookColor.navy)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(headerSubtitle)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(FlybookColor.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: 330, alignment: .leading)

            }
            .frame(width: 330, height: 116, alignment: .topLeading)

            Spacer()

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                    Text("BASIS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)
                        .frame(width: 62, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    headerDropdown(
                        selection: $activeBaseRaw,
                        options: FlybookBase.allCases.map(\.rawValue)
                    )
                    }
                    HStack(spacing: 8) {
                    Text("FLUGZEUG")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)
                        .frame(width: 62, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    aircraftHeaderDropdown
                    }

                    HStack(spacing: 8) {
                    Text("NUTZER")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)
                        .frame(width: 62, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    headerDropdown(
                        selection: $activeUserRaw,
                        options: FlybookUser.allCases.map(\.rawValue)
                    )
                    }
                }

                Button(action: refreshLiveWeather) {
                    VStack(spacing: 2) {
                        if isLiveWeatherLoading {
                            ProgressView().controlSize(.regular)
                        } else {
                            Image(systemName: "cloud.sun.fill")
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 28, weight: .bold))
                        }
                        Text("NOW!")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(FlybookColor.navy)
                    }
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(FlybookColor.blue.opacity(0.14)))
                    .overlay(Circle().stroke(FlybookColor.blue, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .disabled(isLiveWeatherLoading)
                .help(
                    "Vollständiger Wetter-Refresh ohne Cache: "
                    + "Flugplatzwetter, Langfristprognose, Streckenwind, "
                    + "Korridorrisiko, Föhn und Alternates"
                )
            }
            .frame(width: 331, height: 88, alignment: .top)
            .offset(y: -6)
        }
        .frame(width: 675, height: 116, alignment: .topLeading)
        .overlay(alignment: .bottomLeading) {
            headerFeatureStrip
        }
        .onChange(of: activeUserRaw) { newValue in
            ETOPSProfileStore.activate(
                FlybookUser(rawValue: newValue) ?? .stephan
            )
        }
        .onChange(of: activeBaseRaw) { newValue in
            BaseProfileStore.activate(FlybookBase(rawValue: newValue) ?? .lsvMainz)
            normalizeAircraftForActiveBase()
        }
        .onChange(of: selectedAircraftRaw) { _ in
            selectedRefuelFuelRaw = preferredFuel.rawValue
            manualRefuelPrice = nil
        }
        .onAppear {
            normalizeAircraftForActiveBase()
        }
    }

    private var headerFeatureStrip: some View {
        HStack(spacing: 5) {
            ForEach(
                DestinationFeature.allCases.filter(
                    displayedHeaderDestination.features.contains
                )
            ) { feature in
                Label(feature.compactTitle, systemImage: feature.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(
                        Capsule()
                            .fill(FlybookColor.blue.opacity(0.12))
                    )
                    .help(feature.title)
            }
            if LandingVoucherBook.includes(displayedHeaderDestination.icao) {
                HStack(spacing: 5) {
                    Image(systemName: "book.closed.fill")
                    Text("GUTSCHEIN \(LandingVoucherBook.yearLabel)")
                    if landingVoucherBookEnabled {
                        Image(systemName: "checkmark.circle.fill")
                    }
                }
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.47, blue: 0.05),
                                Color(red: 0.94, green: 0.16, blue: 0.48),
                                FlybookColor.blue
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                )
                .overlay(
                    Capsule().stroke(
                        Color.white.opacity(0.75),
                        lineWidth: 1
                    )
                )
                .shadow(color: Color.orange.opacity(0.65), radius: 5)
                .shadow(color: FlybookColor.blue.opacity(0.42), radius: 9)
                .help(
                    "Lande-Gutscheinheft \(LandingVoucherBook.yearLabel), "
                        + "gültig bis \(LandingVoucherBook.validUntilLabel)"
                )
            }
            Spacer(minLength: 0)
        }
        .frame(width: 675, height: 24, alignment: .leading)
        .accessibilityLabel("Themen des Ziels")
    }

    private var aircraftHeaderDropdown: some View {
        Menu {
            ForEach(aircraftForActiveBase) { aircraft in
                Button(aircraft.displayName) {
                    selectedAircraftRaw = aircraft.rawValue
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedAircraft.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FlybookColor.navy)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
            }
            .padding(.horizontal, 8)
            .frame(width: 158, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(FlybookColor.muted.opacity(0.28), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .disabled(aircraftForActiveBase.isEmpty)
    }

    private func normalizeAircraftForActiveBase() {
        guard !aircraftForActiveBase.contains(selectedAircraft),
              let first = aircraftForActiveBase.first else { return }
        selectedAircraftRaw = first.rawValue
    }

    private func headerDropdown(
        selection: Binding<String>,
        options: [String]
    ) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) { selection.wrappedValue = option }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selection.wrappedValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FlybookColor.navy)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
            }
            .padding(.horizontal, 8)
            .frame(width: 158, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(FlybookColor.muted.opacity(0.28), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
    }

    private func countryFlag(_ countryCode: String) -> String {
        let code = countryCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard code.count == 2 else { return code }

        let base: UInt32 = 127397
        let scalars = code.unicodeScalars.compactMap {
            UnicodeScalar(base + $0.value)
        }

        guard scalars.count == 2 else { return code }
        return String(String.UnicodeScalarView(scalars))
    }

    private func refreshDataOptimizedWeather() {
        Task {
            async let planningAirports: Void =
                refreshPlanningAirportWeather(forceRefresh: true)
            async let alternates: Void =
                AlternateWeatherUpdater.refresh(
                    airports: nearestAlternateAirports,
                    forceRefresh: true
                )
            _ = await (planningAirports, alternates)
        }
    }

    private func refreshPlanningAirportWeather(
        forceRefresh: Bool
    ) async {
        // Ein gemeinsamer Task hält alle Karten einer Planung konsistent.
        // Doppelte Flugplätze werden vom Service zu einem Download gebündelt.
        async let outboundOrigin: Void = outboundEDFZWeatherModel.load(
            plannedDate: outboundFlightDate,
            airport: planningOrigin,
            forceRefresh: forceRefresh
        )
        async let outboundDestination: Void =
            destinationAirportWeatherModel.load(
                plannedDate: outboundFlightDate,
                airport: firstLegDestination,
                forceRefresh: forceRefresh
            )
        async let secondOrigin: Void = destinationReturnWeatherModel.load(
            plannedDate: returnFlightDate,
            airport: secondLegOrigin,
            forceRefresh: forceRefresh
        )
        async let secondDestination: Void = returnEDFZWeatherModel.load(
            plannedDate: returnFlightDate,
            airport: secondLegDestination,
            forceRefresh: forceRefresh
        )
        async let intermediate: Void = refreshIntermediatePlanningWeather(
            forceRefresh: forceRefresh
        )
        _ = await (
            outboundOrigin,
            outboundDestination,
            secondOrigin,
            secondDestination,
            intermediate
        )
    }

    private func refreshIntermediatePlanningWeather(
        forceRefresh: Bool
    ) async {
        guard flightPlanningMode == .multiStop else { return }
        await intermediateWeatherModel.load(
            plannedDate: outboundFlightDate,
            airport: intermediateAirport,
            forceRefresh: forceRefresh
        )
    }

    private func refreshRouteWinds() async {
        async let outbound: Void = outboundRouteWindModel.load(
                destination: firstLegDestination,
                origin: planningOrigin,
                plannedStart: outboundStartInstant,
                plannedEnd: outboundArrivalInstantForWeather,
                altitudeOptions: outboundAltitudeOptions,
                selectedAltitudeFeet:
                    outboundFlightAltitudeFeet,
                isReturn: false,
                directNM: outboundDirectNM,
                trackMilesNM: outboundTrackMiles,
                stopCount: outboundStops,
                tankStopMinutes: tankStopMinutes,
                fallbackCruiseSpeedKnots: cruiseGroundSpeedKnots,
                departurePressureAltitudeFeet: planningOrigin.elevationFeet,
                climbPerformance: climbPerformance,
                cruisePerformance: cruisePerformance
            )
        async let returning: Void = returnRouteWindModel.load(
                destination: secondLegDestination,
                origin: secondLegOrigin,
                plannedStart: returnDepartureInstantForWeather,
                plannedEnd: returnArrivalInstant,
                altitudeOptions: returnAltitudeOptions,
                selectedAltitudeFeet:
                    returnFlightAltitudeFeet,
                isReturn: false,
                directNM: returnDirectNM,
                trackMilesNM: returnTrackMiles,
                stopCount: returnStops,
                tankStopMinutes: tankStopMinutes,
                fallbackCruiseSpeedKnots: cruiseGroundSpeedKnots,
                departurePressureAltitudeFeet: secondLegOrigin.elevationFeet,
                climbPerformance: climbPerformance,
                cruisePerformance: cruisePerformance
            )
        _ = await (outbound, returning)
    }

    private func refreshRouteRisks() async {
        async let outbound: Void = outboundRouteRiskModel.load(
            waypoints: outboundRouteRiskWaypoints,
            start: outboundStartInstant,
            end: outboundArrivalInstantForWeather,
            cruiseAltitudeFeet: outboundFlightAltitudeFeet,
            forceRefresh: true
        )
        async let returning: Void = returnRouteRiskModel.load(
            waypoints: returnRouteRiskWaypoints,
            start: returnDepartureInstantForWeather,
            end: returnArrivalInstant,
            cruiseAltitudeFeet: returnFlightAltitudeFeet,
            forceRefresh: true
        )
        _ = await (outbound, returning)
    }

    private func refreshIntermediateWeatherIfNeeded() async {
        guard flightPlanningMode == .multiStop else { return }
        await intermediateWeatherModel.load(
            plannedDate: outboundFlightDate,
            airport: intermediateAirport,
            forceRefresh: true
        )
    }

    private func refreshLiveWeather() {
        guard !isLiveWeatherLoading else { return }
        isLiveWeatherLoading = true
        Task {
            defer { isLiveWeatherLoading = false }

            // NOW ist der bewusst maximale Abruf. Alle fachlichen Wetter-
            // caches werden für die aktuelle Planung umgangen bzw. geleert.
            await RouteWindService.shared.invalidateCaches()

            async let overview: Void = weatherModel.load(
                destination: destination,
                targetInstants: weatherTargetInstants,
                forceRefresh: true
            )
            async let routeWinds: Void = refreshRouteWinds()
            async let routeRisks: Void = refreshRouteRisks()
            async let planningAirports: Void =
                refreshPlanningAirportWeather(forceRefresh: true)
            async let intermediate: Void = refreshIntermediateWeatherIfNeeded()
            async let alternates: Void =
                AlternateWeatherUpdater.refresh(
                    airports: nearestAlternateAirports,
                    forceRefresh: true
                )
            async let foehn: Void = alpineFoehnModel.load(
                ifRelevant: alpineRelevantAirports,
                forceRefresh: true
            )
            _ = await (
                overview,
                routeWinds,
                routeRisks,
                planningAirports,
                intermediate,
                alternates,
                foehn
            )
        }
    }

    private func resetFlightPlanningSchedule() {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow =
            Calendar.current.date(
                byAdding: .day,
                value: 1,
                to: today
            ) ?? today

        outboundFlightDate = tomorrow
        outboundStartText = "09:00"
        multiStopDepartureText = ""

        if flightPlanningMode == .multiStop {
            returnFlightDate = tomorrow
        } else {
            returnFlightDate =
                Calendar.current.date(
                    byAdding: .day,
                    value: 2,
                    to: today
                ) ?? today
            desiredHomeArrivalText = standardArrivalText(
                on: returnFlightDate
            )
        }
    }

    private func standardArrivalText(
        on date: Date
    ) -> String {
        guard let events = SolarCalculator.events(
            forLocalDayContaining: date,
            latitude: secondLegDestination.latitude,
            longitude: secondLegDestination.longitude,
            timeZone: secondLegDestination.timeZone
        ) else {
            return "17:00"
        }

        let standardArrival = events.sunset.addingTimeInterval(-60 * 60)
        return FlightDateTime.clock(
            instant: standardArrival,
            timeZone: timeDisplayMode == .utc
                ? TimeZone(secondsFromGMT: 0)!
                : secondLegDestination.timeZone
        )
    }

    private func reverseFlightRoute() {
        let oldOutboundOrigin = planningOrigin.icao
        let oldOutboundDestination = planningDestination.icao
        let oldReturnOrigin = secondLegOrigin.icao
        let oldReturnDestination = secondLegDestination.icao

        selectedOriginICAO = oldOutboundDestination
        if let index = availableDestinations.firstIndex(where: {
            $0.icao == oldOutboundOrigin
        }) {
            selectedDestinationIndex = index
        }
        returnOriginICAO = oldReturnDestination
        returnDestinationICAO = oldReturnOrigin
        outboundTrackMilesOverride = nil
        returnTrackMilesOverride = nil
    }

    private var flightSection: some View {
        FlybookCard {
            VStack(spacing: 12) {
                HStack(spacing: 9) {
                    Text("FLUGPLANUNG")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)

                            Button(FlightPlanningMode.roundTrip.rawValue) {
                                flightPlanningMode = .roundTrip
                                outboundDestinationICAO = ""
                                returnOriginICAO = destinationReference.icao
                                returnDestinationICAO = planningOrigin.icao
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(
                                flightPlanningMode == .roundTrip
                                    ? FlybookColor.navy
                                    : FlybookColor.muted.opacity(0.55)
                            )

                            Button(FlightPlanningMode.multiStop.rawValue) {
                                if mainDestinationICAO.isEmpty {
                                    mainDestinationICAO = destinationReference.icao
                                }
                                flightPlanningMode = .multiStop
                                isOneWay = false
                                returnOriginICAO = planningDestination.icao
                                returnDestinationICAO = destinationReference.icao
                                returnFlightDate = outboundFlightDate
                                multiStopDepartureText = ""
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(
                                flightPlanningMode == .multiStop
                                    ? FlybookColor.navy
                                    : FlybookColor.muted.opacity(0.55)
                            )

                            Toggle("One-Way", isOn: $isOneWay)
                                .toggleStyle(.checkbox)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(FlybookColor.navy)

                    Spacer(minLength: 4)

                    Picker("Zeitbasis", selection: timeModeBinding) {
                        Text("Lokal").tag(TimeDisplayMode.local)
                        Text("UTC").tag(TimeDisplayMode.utc)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .font(.system(size: 13, weight: .semibold))
                    .controlSize(.small)
                    .frame(width: 112)
                }
                .font(.system(size: 13, weight: .semibold))

                Divider()

                FlightTimePlanningRows(
                    planningMode: flightPlanningMode,
                    isOneWay: isOneWay,
                    intermediateAirportICAO: $intermediateICAO,
                    airportOptions: allRouteAirportOptions,
                    outboundOriginSelection: planningOriginSelection,
                    outboundDestinationSelection: planningDestinationSelection,
                    returnOriginSelection: returnOriginSelection,
                    returnDestinationSelection: returnDestinationSelection,
                    outboundFlightDate: $outboundFlightDate,
                    returnFlightDate: $returnFlightDate,
                    outboundStartText: $outboundStartText,
                    desiredHomeArrivalText: $desiredHomeArrivalText,
                    multiStopDepartureText: $multiStopDepartureText,
                    outboundStops: outboundStopsBinding,
                    returnStops: returnStopsBinding,
                    outboundStop1ICAO: $outboundStop1ICAO,
                    outboundStop2ICAO: $outboundStop2ICAO,
                    returnStop1ICAO: $returnStop1ICAO,
                    returnStop2ICAO: $returnStop2ICAO,
                    stopAirportOptions: allRouteAirportOptions,
                    outboundFlightAltitudeFeet:
                        $outboundFlightAltitudeFeet,
                    returnFlightAltitudeFeet:
                        $returnFlightAltitudeFeet,
                    outboundAltitudeOptions:
                        outboundAltitudeOptions,
                    returnAltitudeOptions:
                        returnAltitudeOptions,
                    outboundRouteWind: outboundRouteWindModel.wind,
                    returnRouteWind: returnRouteWindModel.wind,
                    outboundRouteRisks: outboundRouteRiskModel.segments,
                    returnRouteRisks: returnRouteRiskModel.segments,
                    outboundRouteAssessments: outboundRouteRiskModel.assessments,
                    returnRouteAssessments: returnRouteRiskModel.assessments,
                    outboundBestLevelFeet:
                        outboundRouteWindModel.bestLevelFeet,
                    returnBestLevelFeet:
                        returnRouteWindModel.bestLevelFeet,
                    outboundEDFZForecast: outboundEDFZWeatherModel.forecast,
                    returnEDFZForecast: returnEDFZWeatherModel.forecast,
                    intermediateAirportForecast:
                        intermediateWeatherModel.forecast,
                    destinationAirportForecast:
                        destinationAirportWeatherModel.forecast,
                    destinationReturnForecast:
                        destinationReturnWeatherModel.forecast,
                    foehnModel: alpineFoehnModel,
                    outboundDestinationPressureMbar:
                        weatherModel.weather?.days.first?
                            .pressureMSLHPA
                            .map { Int($0.rounded()) },
                    returnDestinationPressureMbar:
                        weatherModel.weather?.days.dropFirst().first?
                            .pressureMSLHPA
                            .map { Int($0.rounded()) },
                    outboundDestinationWeather:
                        weatherModel.weather?.days.first,
                    returnDestinationWeather:
                        weatherModel.weather?.days.dropFirst().first,
                    destination: destination,
                    origin: planningOrigin,
                    routeDestination: planningDestination,
                    outboundDirectNM: outboundDirectNM,
                    returnDirectNM: returnDirectNM,
                    outboundTrackMiles: outboundTrackMilesBinding,
                    returnTrackMiles: returnTrackMilesBinding,
                    refuelAtDestination: refuelAtDestinationBinding,
                    destinationTimeZone: planningDestination.timeZone,
                    timeDisplayMode: timeDisplayMode,
                    tankStopMinutes: tankStopMinutes,
                    preTakeoffGroundMinutes: preTakeoffGroundMinutes,
                    postLandingGroundMinutes: postLandingGroundMinutes,
                    cruiseGroundSpeedKnots:
                        cruiseGroundSpeedKnots,
                    climbPerformance: climbPerformance,
                    cruisePerformance: cruisePerformance,
                    refreshWeather: refreshDataOptimizedWeather,
                    resetSchedule: resetFlightPlanningSchedule,
                    reverseRoute: reverseFlightRoute
                )
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .top
            )
        }
        .frame(height: 870, alignment: .top)
        .clipped()
    }


    private var calculationSection: some View {
        FlybookCard {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("CHARTERKALKULATION")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(FlybookColor.navy)

                        Spacer()

                        Toggle(
                            "Landegebühren einrechnen",
                            isOn: $includeLandingFeesInTotal
                        )
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FlybookColor.navy)
                    }

                    HStack {
                        HStack(spacing: 6) {
                            Button {
                                refuelAtDestination.toggle()
                            } label: {
                                Image(systemName: "fuelpump.fill")
                                    .font(.system(size: 23, weight: .bold))
                                    .foregroundStyle(
                                        refuelAtDestination
                                            ? FlybookColor.blue
                                            : FlybookColor.muted
                                    )
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                            .help(
                                refuelAtDestination
                                    ? "Tanken am Ziel: ein"
                                    : "Tanken am Ziel: aus"
                            )
                            Picker("Startkraftstoff", selection: startingFuelDisplayedBinding) {
                                ForEach(1...startingFuelMaximumDisplayed, id: \.self) { amount in
                                    Text("\(amount) \(fuelDisplayUnit.symbol)").tag(amount)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 94)
                            Button("Voll") {
                                selectFullStartingFuel()
                            }
                            .controlSize(.small)
                            Button("Minimum") {
                                selectMinimumStartingFuel()
                            }
                            .controlSize(.small)
                        }

                        Spacer()
                        Picker("Kraftstoffeinheit", selection: $fuelDisplayUnitRaw) {
                            ForEach(FuelDisplayUnit.allCases) { unit in
                                Text(unit.label).tag(unit.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 145)
                    }
                }

                CalculationColumnHeaders()

                CalculationRow(
                    title: flightPlanningMode == .multiStop
                        ? "1. FLUG"
                        : "HINFLUG",
                    stopCount: outboundStops,
                    directNM: outboundDirectNM,
                    trackMilesNM: outboundTrackMiles,
                    headwindKnots:
                        outboundRouteWindModel.wind?
                            .outboundHeadwindKnots,
                    tankStopMinutes: tankStopMinutes,
                    hourlyRateEUR: hourlyRateEUR,
                    vatPercent: vatPercent,
                    weekdayDiscountEnabled:
                        weekdayDiscountEnabled,
                    flightDate: outboundFlightDate,
                    cruiseGroundSpeedKnots:
                        cruiseGroundSpeedKnots,
                    climbDeparturePressureAltitudeFeet: planningOrigin.elevationFeet,
                    climbTargetPressureAltitudeFeet: Double(outboundFlightAltitudeFeet),
                    climbPerformance: climbPerformance,
                    cruisePerformance: cruisePerformance,
                    fuelConsumptionPerHour:
                        outboundFuelConsumptionPerHour,
                    reserveMinutes:
                        reserveMinutes,
                    usableFuel:
                        usableFuel,
                    fuelUnit: fuelDisplayUnit,
                    preTakeoffGroundMinutes: preTakeoffGroundMinutes,
                    postLandingGroundMinutes: postLandingGroundMinutes,
                    prepaymentDiscount15To29Enabled:
                        prepaymentDiscount15To29Enabled,
                    prepaymentDiscount30PlusEnabled:
                        prepaymentDiscount30PlusEnabled,
                    landingFeeQuote: outboundLandingFeeQuote,
                    showsLandingFee: includeLandingFeesInTotal,
                    reserveNotConsumed:
                        outboundReserveNotConsumed
                )

                if !isOneWay {
                    Divider()

                    CalculationRow(
                        title: flightPlanningMode == .multiStop
                            ? "2. FLUG"
                            : "RÜCKFLUG",
                        stopCount: returnStops,
                        directNM: returnDirectNM,
                        trackMilesNM: returnTrackMiles,
                        headwindKnots:
                            returnRouteWindModel.wind?
                                .outboundHeadwindKnots,
                        tankStopMinutes: tankStopMinutes,
                        hourlyRateEUR: hourlyRateEUR,
                        vatPercent: vatPercent,
                        weekdayDiscountEnabled:
                            weekdayDiscountEnabled,
                        flightDate: returnFlightDate,
                        cruiseGroundSpeedKnots:
                            cruiseGroundSpeedKnots,
                        climbDeparturePressureAltitudeFeet: secondLegOrigin.elevationFeet,
                        climbTargetPressureAltitudeFeet: Double(returnFlightAltitudeFeet),
                        climbPerformance: climbPerformance,
                        cruisePerformance: cruisePerformance,
                        fuelConsumptionPerHour:
                            returnFuelConsumptionPerHour,
                        reserveMinutes:
                            reserveMinutes,
                        usableFuel:
                            usableFuel,
                        fuelUnit: fuelDisplayUnit,
                        preTakeoffGroundMinutes: preTakeoffGroundMinutes,
                        postLandingGroundMinutes: postLandingGroundMinutes,
                        prepaymentDiscount15To29Enabled:
                            prepaymentDiscount15To29Enabled,
                        prepaymentDiscount30PlusEnabled:
                            prepaymentDiscount30PlusEnabled,
                        landingFeeQuote: returnLandingFeeQuote,
                        showsLandingFee: includeLandingFeesInTotal,
                        reserveToggle:
                            outboundReserveNotConsumedBinding
                    )
                }

                Divider()

                DestinationRefuelCalculationRow(
                    enabled: refuelAtDestinationBinding,
                    selectedFuelRaw: $selectedRefuelFuelRaw,
                    knownPrice: price(selectedRefuelFuel, at: refuelAirport),
                    manualPrice: $manualRefuelPrice,
                    liters: $refuelLiters,
                    unit: fuelDisplayUnit,
                    lossEUR: refuelLossEUR
                )

                CalculationTotalRow(
                    includesReturn: !isOneWay,
                    outboundReserveNotConsumed:
                        outboundReserveNotConsumed,
                    outboundStopCount: outboundStops,
                    returnStopCount: returnStops,
                    outboundDirectNM: outboundDirectNM,
                    returnDirectNM: returnDirectNM,
                    outboundTrackMilesNM: outboundTrackMiles,
                    returnTrackMilesNM: returnTrackMiles,
                    outboundHeadwindKnots:
                        outboundRouteWindModel.wind?
                            .outboundHeadwindKnots,
                    returnHeadwindKnots:
                        returnRouteWindModel.wind?
                            .outboundHeadwindKnots,
                    hourlyRateEUR: hourlyRateEUR,
                    vatPercent: vatPercent,
                    weekdayDiscountEnabled:
                        weekdayDiscountEnabled,
                    outboundFlightDate: outboundFlightDate,
                    returnFlightDate: returnFlightDate,
                    cruiseGroundSpeedKnots:
                        cruiseGroundSpeedKnots,
                    outboundClimbDeparturePressureAltitudeFeet: planningOrigin.elevationFeet,
                    outboundClimbTargetPressureAltitudeFeet: Double(outboundFlightAltitudeFeet),
                    returnClimbDeparturePressureAltitudeFeet: secondLegOrigin.elevationFeet,
                    returnClimbTargetPressureAltitudeFeet: Double(returnFlightAltitudeFeet),
                    climbPerformance: climbPerformance,
                    cruisePerformance: cruisePerformance,
                    outboundFuelConsumptionPerHour:
                        outboundFuelConsumptionPerHour,
                    returnFuelConsumptionPerHour:
                        returnFuelConsumptionPerHour,
                    reserveMinutes:
                        reserveMinutes,
                    usableFuel:
                        usableFuel,
                    fuelUnit: fuelDisplayUnit,
                    preTakeoffGroundMinutes: preTakeoffGroundMinutes,
                    postLandingGroundMinutes: postLandingGroundMinutes,
                    prepaymentDiscount15To29Enabled:
                        prepaymentDiscount15To29Enabled,
                    prepaymentDiscount30PlusEnabled:
                        prepaymentDiscount30PlusEnabled,
                    minimumRequiredBlockHours:
                        requiredReservationBlockHours,
                    outboundLandingFeeQuote:
                        outboundLandingFeeQuote,
                    returnLandingFeeQuote:
                        returnLandingFeeQuote,
                    includeLandingFees:
                        includeLandingFeesInTotal,
                    refuelLossEUR: refuelLossEUR,
                    startingFuelLiters: startingFuelLiters,
                    refuelEnabled: refuelAtDestination,
                    refuelLiters: refuelLiters,
                    minimumRequiredRefuelLiters:
                        minimumSuggestedRefuelLiters,
                    estimatedFuelAtTripEnd:
                        estimatedFuelAtTripEnd
                )
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 454,
                maxHeight: 454,
                alignment: .topLeading
            )
        }
        .frame(width: 501, height: 490, alignment: .topLeading)
        .clipped()
        .onAppear {
            selectedRefuelFuelRaw = preferredFuel.rawValue
            selectFullStartingFuel()
        }
    }

    private var calculationRowSection: some View {
        HStack(alignment: .top, spacing: 8) {
            calculationSection
                .frame(width: 501, height: 490, alignment: .topLeading)
            destinationAndAirportFeaturesSection
                .frame(width: 501, height: 490, alignment: .topLeading)
        }
        .frame(width: 1010, height: 490, alignment: .topLeading)
    }

    private var destinationAndAirportFeaturesSection: some View {
        FlybookCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ZIELINFORMATIONEN")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(FlybookColor.navy)
                        Text("\(destination.icao) · \(destination.name)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(FlybookColor.muted)
                    }
                    Spacer()
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(FlybookColor.blue)
                }

                HStack(spacing: 8) {
                    availabilityBadge(
                        "Fahrrad",
                        systemImage: "bicycle",
                        isAvailable: hasBicycleAtAirport
                    )
                    availabilityBadge(
                        "Mietwagen",
                        systemImage: "car.fill",
                        isAvailable: hasRentalCarAtAirport
                    )
                    availabilityBadge(
                        "app2drive",
                        systemImage: "car.side.fill",
                        isAvailable: hasApp2DriveAtAirport
                    )
                    Spacer()
                }

                if !destination.accessFeatures.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(destination.accessFeatures) { access in
                            destinationAccessRow(access)
                        }
                    }
                }

                if hasRestaurantAtAirport {
                    restaurantInformationRow
                }

                if !destination.highlights.isEmpty {
                    masterTextBlock("Highlights", destination.highlights)
                }
                if !destination.airportNote.isEmpty {
                    masterTextBlock("Flugplatzhinweis", destination.airportNote)
                }

                if destination.highlights.isEmpty,
                   destination.airportNote.isEmpty {
                    Text("Keine besonderen Merkmale hinterlegt")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FlybookColor.muted)
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 454,
                maxHeight: 454,
                alignment: .topLeading
            )
        }
        .frame(width: 501, height: 490, alignment: .topLeading)
        .clipped()
    }

    private var hasBicycleAtAirport: Bool {
        positiveService(destination.bikeDirect)
    }

    private var hasRentalCarAtAirport: Bool {
        positiveService(destination.rentalCarDirect)
    }

    private var hasApp2DriveAtAirport: Bool {
        positiveService(destination.app2DriveDirect)
    }

    private var hasRestaurantAtAirport: Bool {
        positiveService(destination.restaurantDirect)
    }

    private var restaurantInformationRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "fork.knife")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.green)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("RESTAURANT AM PLATZ")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
                Text(
                    destination.restaurantName.isEmpty
                        ? "Restaurant vorhanden"
                        : destination.restaurantName
                )
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FlybookColor.navy)
                if !destination.restaurantDescription.isEmpty {
                    Text(destination.restaurantDescription)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FlybookColor.muted)
                        .lineLimit(2)
                }
            }
            Spacer()
            if !destination.restaurantOpeningHours.isEmpty {
                Button {
                    showsRestaurantHours = true
                } label: {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.green)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.green.opacity(0.13)))
                }
                .buttonStyle(.plain)
                .help("Öffnungszeiten und Hinweise anzeigen")
                .popover(isPresented: $showsRestaurantHours) {
                    restaurantHoursPopover
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.green.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.green.opacity(0.30), lineWidth: 1)
        )
    }

    private var restaurantHoursPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("ÖFFNUNGSZEITEN", systemImage: "clock.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(FlybookColor.navy)
            Text(destination.restaurantName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(FlybookColor.navy)
            Text(destination.restaurantOpeningHours)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if !destination.restaurantNotes.isEmpty {
                Divider()
                Text(destination.restaurantNotes)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FlybookColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !destination.restaurantDataCheckedAt.isEmpty {
                Text("Geprüfter Datenstand: \(destination.restaurantDataCheckedAt)")
                    .font(.caption.bold())
                    .foregroundStyle(FlybookColor.muted)
            }
            if let url = URL(string: destination.restaurantSource),
               !destination.restaurantSource.isEmpty {
                Link("Quelle öffnen", destination: url)
                    .font(.system(size: 12, weight: .bold))
            }
            Text("Öffnungszeiten und Feiertagsregelungen vor dem Flug beim Betreiber bestätigen.")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 390, alignment: .leading)
    }

    private func positiveService(_ value: String) -> Bool {
        let normalized = value.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: .current
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == "ja"
            || normalized.hasPrefix("ja ")
            || normalized.hasPrefix("ja–")
            || normalized.hasPrefix("ja-")
            || normalized == "available"
    }

    private func availabilityBadge(
        _ title: String,
        systemImage: String,
        isAvailable: Bool
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(isAvailable ? Color.green : Color.red)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Capsule().fill(
                    (isAvailable ? Color.green : Color.red).opacity(0.11)
                )
            )
            .overlay(
                Capsule().stroke(
                    (isAvailable ? Color.green : Color.red).opacity(0.35),
                    lineWidth: 1
                )
            )
    }

    private func destinationAccessRow(
        _ access: DestinationAccessFeature
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: access.feature.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(FlybookColor.blue)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(access.feature.compactTitle.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
                Text(access.targetName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlybookColor.navy)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(destinationAccessSummary(access))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FlybookColor.navy)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(FlybookColor.blue.opacity(0.08))
        )
    }

    private func destinationAccessSummary(
        _ access: DestinationAccessFeature
    ) -> String {
        var values: [String] = []
        if let distance = access.distanceKilometers {
            values.append(String(format: "%.1f km", distance))
        }
        let travel = [
            access.recommendedMode,
            access.recommendedMinutes.map { "\($0) min" } ?? ""
        ].filter { !$0.isEmpty }.joined(separator: " · ")
        if !travel.isEmpty { values.append(travel) }
        return values.joined(separator: " · ")
    }

    private func masterTextBlock(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FlybookColor.navy)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var timeModeBinding: Binding<TimeDisplayMode> {
        Binding(
            get: { timeDisplayMode },
            set: { newMode in
                guard newMode != timeDisplayMode else { return }

                let oldZone = timeDisplayMode == .utc
                    ? TimeZone(secondsFromGMT: 0)!
                    : planningOrigin.timeZone
                let newZone = newMode == .utc
                    ? TimeZone(secondsFromGMT: 0)!
                    : planningOrigin.timeZone

                outboundStartText = convertedClock(
                    outboundStartText,
                    from: oldZone,
                    to: newZone
                )
                desiredHomeArrivalText = convertedClock(
                    desiredHomeArrivalText,
                    from: oldZone,
                    to: newZone
                )
                timeDisplayMode = newMode
            }
        )
    }

    private func convertedClock(
        _ clock: String,
        from sourceTimeZone: TimeZone,
        to destinationTimeZone: TimeZone
    ) -> String {
        guard let instant = FlightDateTime.instant(
            date: clock == outboundStartText ? outboundFlightDate : returnFlightDate,
            timeText: clock,
            timeZone: sourceTimeZone
        ) else {
            return clock
        }

        return FlightDateTime.clock(
            instant: instant,
            timeZone: destinationTimeZone
        )
    }

    private var weatherSection: some View {
        FlybookCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("WETTER AM ZIEL")
                        .font(.title3.bold())
                        .foregroundStyle(FlybookColor.navy)

        
                    Text("ICON-D2 bevorzugt")
                        .font(.caption.bold())
                        .foregroundStyle(FlybookColor.muted)

                    Button {
                        Task {
                            await weatherModel.load(
                                destination: destination,
                                targetInstants: weatherTargetInstants,
                                forceRefresh: true
                            )
                        }
                    } label: {
                        Image(
                            systemName:
                                "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Wetter aktualisieren")
                }

                Group {
                    if weatherModel.isLoading {
                        HStack {
                
                            ProgressView(
                                "Wetter wird geladen …"
                            )
                            .controlSize(.large)

                                        }
                        .frame(maxHeight: .infinity)
                    } else if let weather =
                        weatherModel.weather,
                        !weather.days.isEmpty
                    {
                        HStack(spacing: 0) {
                            LiveWeatherColumn(
                                title: "ANKUNFT \(destination.icao)",
                                day: weather.days[0]
                            ,
                                airportElevationFeet:
                                    destination.elevationFeet
                            )

                            Divider()

                            if weather.days.count > 1 {
                                LiveWeatherColumn(
                                    title: "ABFLUG \(destination.icao)",
                                    day: weather.days[1]
                                ,
                                airportElevationFeet:
                                    destination.elevationFeet
                            )
                            } else {
                                WeatherPlaceholderColumn(
                                    title: "ABFLUG \(destination.icao)"
                                )
                            }
                        }
                    } else {
                        VStack(spacing: 6) {
                            Image(
                                systemName:
                                    "cloud.sun.rain"
                            )
                            .font(.system(size: 30))
                            .foregroundStyle(
                                FlybookColor.muted
                            )

                            Text(
                                weatherModel.errorMessage
                                ?? "Keine Wetterdaten verfügbar"
                            )
                            .font(
                                .system(
                                    size: 13,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                FlybookColor.muted
                            )
                            .multilineTextAlignment(.center)

                            Button("Erneut laden") {
                                Task {
                                    await weatherModel.load(
                                        destination: destination,
                                        targetInstants: weatherTargetInstants,
                                        forceRefresh: true
                                    )
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                Text("Modellprognose · kein offizielles Flugwetterbriefing")
                    .font(.system(size: 12))
                    .foregroundStyle(FlybookColor.muted)
            }
        }
    }

    private var airportSection: some View {
        FlybookCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("AIRPORT")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)

                HStack(alignment: .top, spacing: 8) {
                    AirportMetric(
                        title: "Piste",
                        value: destination.runwayDimensionsDisplay,
                        secondaryValue: destination.referenceRunway
                    )
                    AirportMetric(title: "LDA", value: destination.ldaDisplay)
                    AirportMetric(title: "Surface", value: destination.surface)
                    AirportMetric(
                        title: "AVGAS",
                        value: destination.avgas,
                        fuelStatus: true,
                        pricePerLiterEUR:
                            destination.avgasPricePerLiterEUR,
                        referencePricePerLiterEUR: mainzAvgasPrice,
                        priceReportedAt: destination.fuelPriceReportedAt
                    )
                    AirportMetric(
                        title: "UL91",
                        value: destination.ul91,
                        fuelStatus: true,
                        pricePerLiterEUR:
                            destination.ul91PricePerLiterEUR,
                        referencePricePerLiterEUR: nil,
                        priceReportedAt: destination.fuelPriceReportedAt
                    )
                    AirportMetric(
                        title: "MOGAS",
                        value: destination.mogas,
                        fuelStatus: true,
                        pricePerLiterEUR:
                            destination.mogasPricePerLiterEUR,
                        referencePricePerLiterEUR: mainzMogasPrice,
                        priceReportedAt: destination.fuelPriceReportedAt
                    )
                }
            }
        }
        .frame(height: 142)
    }

    private var mapAndImageSection: some View {
        FlybookCard {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("EUROPA")
                        .font(.title3.bold())
                        .foregroundStyle(FlybookColor.navy)

                    DestinationMapView(
                        latitude: flightPlanningMode == .multiStop
                            ? secondLegDestination.latitude
                            : planningDestination.latitude,
                        longitude: flightPlanningMode == .multiStop
                            ? secondLegDestination.longitude
                            : planningDestination.longitude,
                        title: flightPlanningMode == .multiStop
                            ? secondLegDestination.name
                            : planningDestination.name,
                        originLatitude: planningOrigin.latitude,
                        originLongitude: planningOrigin.longitude,
                        originTitle: planningOrigin.icao,
                        intermediateLatitude:
                            flightPlanningMode == .multiStop
                                ? intermediateAirport.latitude
                                : nil,
                        intermediateLongitude:
                            flightPlanningMode == .multiStop
                                ? intermediateAirport.longitude
                                : nil,
                        intermediateTitle:
                            flightPlanningMode == .multiStop
                                ? intermediateAirport.icao
                                : nil,
                        routeWaypoints: mapRouteWaypoints
                    )
                }
                .frame(maxWidth: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("LUFTBILD FLUGPLATZ")
                        .font(.title3.bold())
                        .foregroundStyle(FlybookColor.navy)

                    ZStack(alignment: .bottomTrailing) {
                        DestinationMapView(
                            latitude: destination.latitude,
                            longitude: destination.longitude,
                            title: destination.icao,
                            presentation: .airportAerial
                        )

                        Text(
                            "© Esri · Maxar · Earthstar "
                            + "Geographics · GIS Community"
                        )
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.62))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 330)
    }

    private var fiveDayForecastSection: some View {
        FlybookCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("5-TAGES-WETTER FÜR \(destination.name.uppercased())")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)

                    Spacer()

                    Text(forecastSourceLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
                }

                if let forecast =
                    weatherModel.weather?.dailyForecast,
                   !forecast.isEmpty
                {
                    HStack(spacing: 10) {
                        ForEach(
                            Array(forecast.prefix(5).enumerated()),
                            id: \.element.id
                        ) { index, day in
                            DailyForecastTile(
                                day: day,
                                confidencePercent:
                                    forecastConfidence(dayIndex: index)
                            )
                        }
                    }
                } else if weatherModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    Text("5-Tage-Prognose nicht verfügbar")
                        .foregroundStyle(FlybookColor.muted)
                }
            }
        }
        .frame(height: 185)
    }

    private var forecastSourceLabel: String {
        let model = weatherModel.weather?.dailyForecast.first?.model ?? ""
        if model.contains("MET Norway") {
            return "MET Norway · Backup"
        }
        if model.contains("ICON") {
            return "\(model) · DWD"
        }
        return model.isEmpty
            ? "Wetterquelle wird geladen"
            : "\(model) · Open-Meteo"
    }

    private var tenDayForecastSection: some View {
        FlybookCard {
            VStack(alignment: .leading, spacing: 5) {
                Text("10-TAGES-WETTER")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)

                if let forecast = weatherModel.weather?.dailyForecast,
                   forecast.count > 5
                {
                    HStack(spacing: 4) {
                        ForEach(
                            Array(
                                forecast
                                    .dropFirst(5)
                                    .prefix(5)
                                    .enumerated()
                            ),
                            id: \.element.id
                        ) { index, day in
                            CompactDailyForecastTile(
                                day: day,
                                confidencePercent:
                                    forecastConfidence(
                                        dayIndex: index + 5
                                    )
                            )
                        }
                    }
                } else if weatherModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("10-Tage-Prognose nicht verfügbar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FlybookColor.muted)
                }
            }
        }
        .frame(height: 115)
    }

    private func forecastConfidence(dayIndex: Int) -> Int {
        let rawValue = 100.0
            - Double(dayIndex) * (50.0 / 9.0)
        return max(
            50,
            Int((rawValue / 5.0).rounded()) * 5
        )
    }
}

private struct CompactDailyForecastTile: View {
    let day: DailyForecast
    let confidencePercent: Int

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Text("\(weekday) \(shortDate)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)
                    .lineLimit(1)

                HStack {
                    confidenceLabel
                    Spacer()
                }
            }

            HStack(spacing: 4) {
                Image(
                    systemName: RepresentativeDailyWeatherSymbol.systemName(
                        morningCode: day.morningWeatherCode,
                        middayCode: day.middayWeatherCode,
                        eveningCode: day.eveningWeatherCode,
                        fallbackDailyCode: day.weatherCode
                    )
                )
                    .font(.system(size: 22, weight: .medium))
                    .symbolRenderingMode(.multicolor)
                    .frame(width: 30, height: 28)

                Text(
                    day.maximumTemperatureCelsius.map {
                        String(format: "%.0f°", $0)
                    } ?? "—"
                )
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.red)
            }

        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.13))
        )
    }

    private var confidenceLabel: some View {
        Text("\(confidencePercent)%")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(FlybookColor.blue)
            .help(
                "Geschätzte Prognosequalität; sie nimmt "
                + "mit wachsendem Vorhersagezeitraum ab."
            )
    }

    private var date: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day.localDate)
    }

    private var shortDate: String {
        guard let date else { return day.localDate }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM."
        return formatter.string(from: date)
    }

    private var weekday: String {
        guard let date else { return day.localDate }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EE"
        return formatter.string(from: date).uppercased()
    }

}

private struct WindsockIndicatorIcon: View {
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 24
            let sy = size.height / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * sx, y: y * sy)
            }
            func top(_ x: CGFloat) -> CGFloat { 4 + (x - 5) * 0.25 }
            func bottom(_ x: CGFloat) -> CGFloat { 10 + (x - 5) * 0.125 }

            var pole = Path()
            pole.move(to: p(5, 3))
            pole.addLine(to: p(5, 21))
            context.stroke(pole, with: .color(FlybookColor.navy), lineWidth: 1.8)

            var foot = Path()
            foot.move(to: p(2, 21))
            foot.addLine(to: p(8, 21))
            context.stroke(foot, with: .color(FlybookColor.navy), lineWidth: 1.8)

            let stripes: [(CGFloat, CGFloat, Color)] = [
                (5, 9, .orange),
                (9, 13, .red),
                (13, 17, .orange),
                (17, 21, .red)
            ]
            for (start, end, color) in stripes {
                var stripe = Path()
                stripe.move(to: p(start, top(start)))
                stripe.addLine(to: p(end, top(end)))
                stripe.addLine(to: p(end, bottom(end)))
                stripe.addLine(to: p(start, bottom(start)))
                stripe.closeSubpath()
                context.fill(stripe, with: .color(color))
            }
        }
        .accessibilityLabel("Starker Wind")
    }
}

private struct DailyForecastTile: View {
    let day: DailyForecast
    let confidencePercent: Int

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Text("\(weekday) · \(shortDate)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)

                HStack {
                    Text("\(confidencePercent)%")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(FlybookColor.blue)
                        .help(
                            "Geschätzte Prognosequalität; sie nimmt "
                            + "mit wachsendem Vorhersagezeitraum ab."
                        )
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                periodSymbol(
                    title: "08:00",
                    code: day.morningWeatherCode,
                    category: day.morningCategory,
                    interval: "05–11 Uhr"
                )
                periodSymbol(
                    title: "14:00",
                    code: day.middayWeatherCode,
                    category: day.middayCategory,
                    interval: "11–17 Uhr"
                )
                periodSymbol(
                    title: "20:00",
                    code: day.eveningWeatherCode,
                    category: day.eveningCategory,
                    interval: "17–23 Uhr"
                )
            }

            HStack(spacing: 10) {
                Text(
                    day.minimumTemperatureCelsius.map {
                        String(format: "↓ %.0f°", $0)
                    } ?? "↓ —"
                )
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(FlybookColor.blue)

                Text(
                    day.maximumTemperatureCelsius.map {
                        String(format: "↑ %.0f°", $0)
                    } ?? "↑ —"
                )
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.red)

            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.13))
        )
        .overlay(alignment: .bottom) {
            hourlyWindBar
                .clipShape(
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: 10,
                        bottomTrailingRadius: 10
                    )
                )
        }
        .overlay(alignment: .top) {
            hourlyFogRiskBar
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 10,
                        topTrailingRadius: 10
                    )
                )
        }
        .overlay(alignment: .leading) {
            if showsStrongWindIndicator {
                WindsockIndicatorIcon()
                    .frame(width: 24, height: 24)
                    .padding(.leading, 4)
                    .help(
                        "Starker Bodenwind: mindestens 15 kt "
                        + "Dauerwind oder mindestens 25 kt Böen."
                    )
            }
        }
    }

    private var showsStrongWindIndicator: Bool {
        (day.maximumSurfaceWindKnots ?? 0) >= 15
            || (day.maximumWindGustKnots ?? 0) >= 25
    }

    private var hourlyWindBar: some View {
        HStack(spacing: 0) {
            ForEach(
                Array(DailyWeatherTimeline.hours.enumerated()),
                id: \.offset
            ) { index, hour in
                let wind = day.hourlySurfaceWindKnots?
                    .indices.contains(index) == true
                    ? day.hourlySurfaceWindKnots?[index]
                    : nil
                Rectangle()
                    .fill(windColor(wind))
                    .overlay {
                        Rectangle()
                            .stroke(Color.white.opacity(0.75), lineWidth: 0.5)
                    }
                    .help(
                        String(
                            format: "%02d:00 Uhr: %@",
                            hour,
                            wind.map {
                                String(format: "%.0f kt Dauerwind", $0)
                            } ?? "keine Winddaten"
                        )
                    )
            }
        }
        .frame(height: 7)
    }

    private var hourlyFogRiskBar: some View {
        HStack(spacing: 0) {
            ForEach(
                Array(DailyWeatherTimeline.hours.enumerated()),
                id: \.offset
            ) { index, hour in
                let score = day.hourlyFogRiskScores?
                    .indices.contains(index) == true
                    ? day.hourlyFogRiskScores?[index]
                    : nil
                Rectangle()
                    .fill(fogRiskColor(score))
                    .overlay {
                        Rectangle()
                            .stroke(Color.white.opacity(0.7), lineWidth: 0.5)
                    }
                    .help(
                        String(
                            format: "%02d:00 Uhr: %@",
                            hour,
                            fogRiskDescription(score)
                        )
                    )
            }
        }
        .frame(height: 7)
    }

    private func fogRiskColor(_ score: Int?) -> Color {
        guard let score else {
            return Color.gray.opacity(0.12)
        }
        switch FogRiskModel.classify(score: score) {
        case .low:
            return .white
        case .raised:
            return Color(red: 247 / 255, green: 201 / 255, blue: 211 / 255)
        case .high:
            return Color(red: 230 / 255, green: 74 / 255, blue: 80 / 255)
        case .veryHigh:
            return Color(red: 142 / 255, green: 77 / 255, blue: 159 / 255)
        }
    }

    private func fogRiskDescription(_ score: Int?) -> String {
        guard let score else { return "keine Fog-Risk-Daten" }
        let level = FogRiskModel.classify(score: score)
        return "Fog Risk \(score) · \(level.label) "
            + "(Risikoindex, keine Wahrscheinlichkeit)"
    }

    private func windColor(_ windKnots: Double?) -> Color {
        guard let windKnots else {
            return Color(red: 0.92, green: 0.96, blue: 0.99)
        }

        switch windKnots {
        case ...3:
            return Color(red: 0.78, green: 0.94, blue: 0.80)
        case ...6:
            return Color(red: 0.39, green: 0.78, blue: 0.47)
        case ...9:
            return Color(red: 0.10, green: 0.50, blue: 0.22)
        case ...12:
            return Color(red: 0.69, green: 0.86, blue: 0.98)
        case ...15:
            return Color(red: 0.31, green: 0.61, blue: 0.88)
        case ...18:
            return Color(red: 0.08, green: 0.29, blue: 0.66)
        case ...21:
            return Color(red: 0.97, green: 0.69, blue: 0.67)
        case ...24:
            return Color(red: 0.88, green: 0.31, blue: 0.31)
        default:
            return Color(red: 0.58, green: 0.04, blue: 0.08)
        }
    }

    private func periodSymbol(
        title: String,
        code: Int?,
        category: FlightCategory?,
        interval: String
    ) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FlybookColor.muted)

            Image(systemName: weatherSymbol(for: code))
                .font(.system(size: 22, weight: .medium))
                .symbolRenderingMode(.multicolor)
                .frame(width: 30, height: 28)

            RoundedRectangle(cornerRadius: 3)
                .fill(categoryColor(category))
                .frame(width: 38, height: 6)
                .help(
                    "\(interval): schlechteste Kategorie "
                    + (category ?? .unavailable).rawValue
                )
        }
    }

    private func categoryColor(
        _ category: FlightCategory?
    ) -> Color {
        switch category ?? .unavailable {
        case .vfr: return .green
        case .mvfr: return .blue
        case .ifr: return .red
        case .lifr: return .purple
        case .unavailable: return FlybookColor.muted.opacity(0.45)
        }
    }

    private var shortDate: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day.localDate) else {
            return day.localDate
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM."
        return formatter.string(from: date)
    }

    private var weekday: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"

        guard let date = parser.date(from: day.localDate) else {
            return day.localDate
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    private func weatherSymbol(for code: Int?) -> String {
        guard let code else {
            return "questionmark.circle"
        }

        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67: return "cloud.rain.fill"
        case 71...77: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

private struct RouteWindSummary: View {
    let wind: RouteWind?
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wind")
                .foregroundStyle(FlybookColor.blue)

            if isLoading {
                Text("Wind an drei Streckenpunkten wird geladen …")
            } else if let wind {
                Text(
                    "WIND ¼ · ½ · ¾  \(wind.altitudeFeet.formatted()) FT  ·  "
                    + String(format: "%03.0f / %.0f kt", wind.directionDegrees, wind.speedKnots)
                    + "  ·  HIN " + componentText(wind.outboundHeadwindKnots)
                    + "  ·  RÜCK " + componentText(wind.returnHeadwindKnots)
                )
            } else {
                Text(errorMessage ?? "Windkompensation derzeit nicht verfügbar")
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(FlybookColor.navy)
        .lineLimit(1)
    }

    private func componentText(_ headwind: Double) -> String {
        if headwind >= 0 {
            return String(format: "GEGENWIND %.0f kt", headwind)
        }
        return String(format: "RÜCKENWIND %.0f kt", abs(headwind))
    }
}

private struct PlanningWeather {
    let direction: Double?
    let speed: Double?
    let gust: Double?
    let temperature: Double?
    let weatherCode: Int?
    let pressureMbar: Double?
    let elevationFeet: Double
    let visibilityMeters: Double?
    let lowCloudCoverPercent: Double?
    let lowestCloudBaseFeet: Double?
    let ceilingFeet: Double?
    let category: FlightCategory
    let runway: String?
    let runwayCrosswindWarning: RunwayCrosswindWarning
    let runwayWindComponents: RunwayWindComponents?
    let foehnWarning: AlpineFoehnWarning?

    init(
        sample: EDFZWeatherSample?,
        elevationFeet: Double,
        runwayICAO: String? = nil,
        referenceRunway: String? = nil,
        foehnWarning: AlpineFoehnWarning? = nil
    ) {
        direction = sample?.windDirectionDegrees
        speed = sample?.windSpeedKnots
        gust = sample?.windGustKnots
        temperature = sample?.temperatureCelsius
        weatherCode = sample?.weatherCode
        pressureMbar = sample?.pressureMSLHPA
        self.elevationFeet = elevationFeet
        visibilityMeters = sample?.visibilityMeters
        lowCloudCoverPercent = sample?.lowCloudCoverPercent
        lowestCloudBaseFeet = sample?.lowestCloudBaseFeetAGL
        ceilingFeet = sample?.ceilingFeetAGL
        category = sample?.category ?? .unavailable
        self.foehnWarning = foehnWarning
        if let runwayICAO,
           let direction,
           let speed,
           speed >= 0.5
        {
            runway = EDFZRunway.activeRunway(
                for: runwayICAO,
                referenceRunway: referenceRunway,
                windFromDegrees: direction,
                speedKnots: speed
            )
            runwayCrosswindWarning = EDFZRunway.crosswindWarning(
                for: runwayICAO,
                runway: runway,
                referenceRunway: referenceRunway,
                windFromDegrees: direction,
                steadyWindKnots: speed,
                gustKnots: gust
            )
            runwayWindComponents = EDFZRunway.windComponents(
                for: runwayICAO,
                runway: runway,
                referenceRunway: referenceRunway,
                windFromDegrees: direction,
                speedKnots: speed,
                gustKnots: gust
            )
        } else {
            runway = nil
            runwayCrosswindWarning = .none
            runwayWindComponents = nil
        }
    }

    init(day: ForecastDay?, elevationFeet: Double) {
        direction = day?.surfaceWind.directionDegrees
        speed = day?.surfaceWind.speedKnots
        gust = day?.windGustKnots
        temperature = day?.temperatureCelsius
        weatherCode = day?.weatherCode
        pressureMbar = day?.pressureMSLHPA
        self.elevationFeet = elevationFeet
        visibilityMeters = day?.visibilityMeters
        lowCloudCoverPercent = day?.lowCloudCoverPercent
        lowestCloudBaseFeet = day?.lowestCloudBaseFeetAGL
        ceilingFeet = day?.ceilingFeetAGL
        category = day?.category ?? .unavailable
        foehnWarning = nil
        runway = nil
        runwayCrosswindWarning = .none
        runwayWindComponents = nil
    }
}

private struct PlanningWeatherCard: View {
    let weather: PlanningWeather
    let civilDawnText: String?
    let sunriseText: String?
    let sunsetText: String?
    let civilDuskText: String?
    @State private var showsFoehnDetails = false

    @AppStorage(UnitSystemSettingsKey.displaySystem)
    private var displayUnitSystemRaw = DisplayUnitSystem.eu.rawValue

    private var usesTwelveHourFormat: Bool {
        DisplayUnitSystem(rawValue: displayUnitSystemRaw) == .us
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                WindFlowIndicator(weather: weather)

                Text(
                    AviationWindText.format(
                        direction: weather.direction,
                        speed: weather.speed,
                        gust: weather.gust
                    )
                )
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(FlybookColor.navy)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(windBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(FlybookColor.navy.opacity(0.45), lineWidth: 1)
            )
            .frame(height: 28)

            HStack(spacing: 7) {
                Text(
                    weather.temperature.map {
                        String(format: "%.0f°", $0)
                    } ?? "—"
                )
                .font(.system(size: 14, weight: .bold, design: .rounded))

                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .symbolRenderingMode(.multicolor)

                Text(description)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(FlybookColor.navy)

            Text(metarCloudAndVisibility)
                .font(
                    .system(
                        size: 14,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(FlybookColor.navy)
                .lineLimit(1)
                .help(
                    "ICON zeigt den modellierten niedrigen "
                    + "Wolkenanteil. METAR zeigt dessen "
                    + "Übertragung in Achtel-Bedeckung; "
                    + "BKN/OVC definieren eine Ceiling."
                )

            TimeContextInfo(weather: weather)

            HStack(spacing: 7) {
                Label(
                    weather.category.rawValue,
                    systemImage: "circle.fill"
                )
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(categoryColor)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text(categoryReason ?? " ")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(categoryColor)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 15,
                    alignment: .center
                )

            if let sunriseText, let sunsetText,
               let civilDawnText, let civilDuskText {
                HStack(spacing: 2) {
                    twilightColumn(
                        primary: sunriseText,
                        secondary: civilDawnText,
                        primarySymbol: "sunrise.fill",
                        secondarySymbol: "sun.horizon.fill",
                        secondaryHelp: "Beginn der bürgerlichen Dämmerung"
                    )
                    twilightColumn(
                        primary: sunsetText,
                        secondary: civilDuskText,
                        primarySymbol: "sunset.fill",
                        secondarySymbol: "moon.stars.fill",
                        secondaryHelp: "Ende der bürgerlichen Dämmerung"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    weather.foehnWarning?.level.color.opacity(0.75)
                        ?? Color.clear,
                    lineWidth: weather.foehnWarning == nil ? 0 : 1.5
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if weather.foehnWarning != nil { showsFoehnDetails = true }
        }
        .popover(isPresented: $showsFoehnDetails) {
            if let warning = weather.foehnWarning {
                VStack(alignment: .leading, spacing: 10) {
                    Label(warning.level.title, systemImage: "wind")
                        .font(.headline)
                        .foregroundStyle(warning.level.color)
                    Text(warning.flowName)
                        .font(.subheadline.bold())
                    Text(warning.explanation)
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Hinweis, kein offizielles Flugwetterbriefing.")
                        .font(.caption.bold())
                        .foregroundStyle(FlybookColor.muted)
                }
                .padding(18)
                .frame(width: 390)
            }
        }
    }

    private var cardBackgroundColor: Color {
        guard let warning = weather.foehnWarning else {
            return Color(nsColor: .controlBackgroundColor)
        }
        switch warning.level {
        case .none: return Color(nsColor: .controlBackgroundColor)
        case .yellow: return Color.yellow.opacity(0.30)
        case .orange: return Color.orange.opacity(0.34)
        case .red: return Color.red.opacity(0.34)
        }
    }

    private var windBackgroundColor: Color {
        FlightPlanningWeatherStyle.windBackgroundColor(
            steadyWindKnots: weather.speed
        )
    }

    private var symbol: String {
        if weather.weatherCode == nil,
           let cloudCover = weather.lowCloudCoverPercent {
            if cloudCover <= 12.5 { return "sun.max.fill" }
            if cloudCover <= 50 { return "cloud.sun.fill" }
            return "cloud.fill"
        }
        switch weather.weatherCode ?? -1 {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "questionmark.circle"
        }
    }

    private var description: String {
        if weather.weatherCode == nil,
           let cloudCover = weather.lowCloudCoverPercent {
            if cloudCover <= 12.5 { return "Klar" }
            if cloudCover <= 50 { return "Heiter" }
            return "Bedeckt"
        }
        switch weather.weatherCode ?? -1 {
        case 0: return "Klar"
        case 1, 2: return "Heiter"
        case 3: return "Bedeckt"
        case 45, 48: return "Nebel"
        case 51...57: return "Niesel"
        case 61...67, 80...82: return "Regen"
        case 71...77: return "Schnee"
        case 95...99: return "Gewitter"
        default: return "N/A"
        }
    }

    private func twilightColumn(
        primary: String,
        secondary: String,
        primarySymbol: String,
        secondarySymbol: String,
        secondaryHelp: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            twilightValue(primary, symbol: primarySymbol)
            .foregroundStyle(FlybookColor.navy)
            twilightValue(secondary, symbol: secondarySymbol)
            .foregroundStyle(FlybookColor.muted)
            .help(secondaryHelp)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .frame(width: 66, alignment: .leading)
    }

    private func twilightValue(_ value: String, symbol: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol).frame(width: 16, alignment: .center)
            Text(TimeInput.displayClock(value, usesTwelveHourFormat: usesTwelveHourFormat))
        }
        .frame(width: 66, alignment: .leading)
    }

    private var categoryColor: Color {
        switch weather.category {
        case .vfr: return .green
        case .mvfr: return .blue
        case .ifr: return .red
        case .lifr: return .purple
        case .unavailable: return .gray
        }
    }

    private var metarCloudAndVisibility: String {
        AviationWeatherText.cloudAndVisibility(
            lowCloudCoverPercent: weather.lowCloudCoverPercent,
            lowestCloudBaseFeet: weather.lowestCloudBaseFeet,
            visibilityMeters: weather.visibilityMeters,
            unitSystem:
                DisplayUnitSystem(rawValue: displayUnitSystemRaw) ?? .eu
        )
    }

    private var categoryReason: String? {
        guard weather.category != .vfr,
              weather.category != .unavailable
        else { return nil }
        let visibilitySM = weather.visibilityMeters.map {
            $0 / 1609.344
        }
        switch weather.category {
        case .lifr:
            if let ceiling = weather.ceilingFeet, ceiling < 500 {
                return String(format: "Ceiling %.0f ft", ceiling)
            }
            if let visibilitySM, visibilitySM < 1 {
                return String(format: "Sicht %.1f SM", visibilitySM)
            }
        case .ifr:
            if let ceiling = weather.ceilingFeet, ceiling < 1000 {
                return String(format: "Ceiling %.0f ft", ceiling)
            }
            if let visibilitySM, visibilitySM < 3 {
                return String(format: "Sicht %.1f SM", visibilitySM)
            }
        case .mvfr:
            if let ceiling = weather.ceilingFeet, ceiling <= 3000 {
                return String(format: "Ceiling %.0f ft", ceiling)
            }
            if let visibilitySM, visibilitySM <= 5 {
                return String(format: "Sicht %.1f SM", visibilitySM)
            }
        default:
            break
        }
        return nil
    }
}

private struct FlightTimePlanningRows: View {
    let planningMode: FlightPlanningMode
    let isOneWay: Bool
    @Binding var intermediateAirportICAO: String
    let airportOptions: [AirportReference]
    @Binding var outboundOriginSelection: String
    @Binding var outboundDestinationSelection: String
    @Binding var returnOriginSelection: String
    @Binding var returnDestinationSelection: String
    @Binding var outboundFlightDate: Date
    @Binding var returnFlightDate: Date
    @Binding var outboundStartText: String
    @Binding var desiredHomeArrivalText: String
    @Binding var multiStopDepartureText: String
    @Binding var outboundStops: Int
    @Binding var returnStops: Int
    @Binding var outboundStop1ICAO: String
    @Binding var outboundStop2ICAO: String
    @Binding var returnStop1ICAO: String
    @Binding var returnStop2ICAO: String
    let stopAirportOptions: [AirportReference]
    @Binding var outboundFlightAltitudeFeet: Int
    @Binding var returnFlightAltitudeFeet: Int

    let outboundAltitudeOptions: [Int]
    let returnAltitudeOptions: [Int]
    let outboundRouteWind: RouteWind?
    let returnRouteWind: RouteWind?
    let outboundRouteRisks: [RouteWeatherRisk]
    let returnRouteRisks: [RouteWeatherRisk]
    let outboundRouteAssessments: [RouteWeatherSegmentAssessment]
    let returnRouteAssessments: [RouteWeatherSegmentAssessment]
    let outboundBestLevelFeet: Int?
    let returnBestLevelFeet: Int?
    let outboundEDFZForecast: EDFZForecast?
    let returnEDFZForecast: EDFZForecast?
    let intermediateAirportForecast: EDFZForecast?
    let destinationAirportForecast: EDFZForecast?
    let destinationReturnForecast: EDFZForecast?
    @ObservedObject var foehnModel: AlpineFoehnViewModel
    let outboundDestinationPressureMbar: Int?
    let returnDestinationPressureMbar: Int?
    let outboundDestinationWeather: ForecastDay?
    let returnDestinationWeather: ForecastDay?
    let destination: Destination
    let origin: AirportReference
    let routeDestination: AirportReference
    let outboundDirectNM: Double
    let returnDirectNM: Double
    @Binding var outboundTrackMiles: Double
    @Binding var returnTrackMiles: Double
    @Binding var refuelAtDestination: Bool
    let destinationTimeZone: TimeZone
    let timeDisplayMode: TimeDisplayMode
    let tankStopMinutes: Int
    let preTakeoffGroundMinutes: Int
    let postLandingGroundMinutes: Int
    let cruiseGroundSpeedKnots: Double
    let climbPerformance: ClimbPerformance
    let cruisePerformance: CruisePerformance
    let refreshWeather: () -> Void
    let resetSchedule: () -> Void
    let reverseRoute: () -> Void

    private var destinationReference: AirportReference {
        routeDestination
    }

    private var intermediateAirport: AirportReference {
        airportOptions.first {
            $0.icao == intermediateAirportICAO
        } ?? destinationReference
    }

    private var firstArrivalAirport: AirportReference {
        destinationReference
    }

    private var secondDepartureAirport: AirportReference {
        airportOptions.first { $0.icao == returnOriginSelection }
            ?? destinationReference
    }

    private var secondArrivalAirport: AirportReference {
        airportOptions.first { $0.icao == returnDestinationSelection }
            ?? origin
    }

    private var displayTimeZone: TimeZone {
        timeDisplayMode == .utc
            ? TimeZone(secondsFromGMT: 0)!
            : origin.timeZone
    }

    private var activeBaseProfile: BaseProfile {
        let raw = UserDefaults.standard.string(forKey: BaseSettingsKey.activeBase)
        let activeBase = FlybookBase(rawValue: raw ?? "") ?? .lsvMainz
        return BaseProfileStore.profile(for: activeBase)
    }

    private var initialHomeDepartureInstant: Date? {
        origin.icao == activeBaseProfile.homeAirportICAO ? outboundStartInstant : nil
    }

    private var outboundTravelMinutes: Int {
        FlightMath.adjustedMinutes(
            directNM: outboundDirectNM,
            stopCount: outboundStops,
            headwindKnots: outboundRouteWind?.outboundHeadwindKnots,
            tankStopMinutes: tankStopMinutes,
            cruiseGroundSpeedKnots:
                cruiseGroundSpeedKnots,
            climbDeparturePressureAltitudeFeet: origin.elevationFeet,
            climbTargetPressureAltitudeFeet: Double(outboundFlightAltitudeFeet),
            climbPerformance: climbPerformance,
            cruisePerformance: cruisePerformance,
            trackMilesNM: outboundTrackMiles,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes
        )
    }

    private var returnTravelMinutes: Int {
        FlightMath.adjustedMinutes(
            directNM: returnDirectNM,
            stopCount: returnStops,
            headwindKnots: returnRouteWind?.outboundHeadwindKnots,
            tankStopMinutes: tankStopMinutes,
            cruiseGroundSpeedKnots:
                cruiseGroundSpeedKnots,
            climbDeparturePressureAltitudeFeet: secondDepartureAirport.elevationFeet,
            climbTargetPressureAltitudeFeet: Double(returnFlightAltitudeFeet),
            climbPerformance: climbPerformance,
            cruisePerformance: cruisePerformance,
            trackMilesNM: returnTrackMiles,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes
        )
    }

    private var outboundStartInstant: Date? {
        return FlightDateTime.instant(
            date: outboundFlightDate,
            timeText: outboundStartText,
            timeZone: displayTimeZone
        )
    }

    private var outboundArrivalInstant: Date? {
        outboundStartInstant?.addingTimeInterval(
            TimeInterval(outboundTravelMinutes * 60)
        )
    }

    private var homeArrivalInstant: Date? {
        if planningMode == .multiStop {
            return returnDepartureInstant?.addingTimeInterval(
                TimeInterval(returnTravelMinutes * 60)
            )
        }
        return FlightDateTime.instant(
            date: returnFlightDate,
            timeText: desiredHomeArrivalText,
            timeZone: timeDisplayMode == .utc
                ? TimeZone(secondsFromGMT: 0)!
                : secondArrivalAirport.timeZone
        )
    }

    private var automaticMultiStopDepartureInstant: Date? {
        guard let outboundArrivalInstant else { return nil }
        let rawDeparture = outboundArrivalInstant.addingTimeInterval(
            TimeInterval(tankStopMinutes * 60)
        )
        let roundedTimestamp =
            ceil(rawDeparture.timeIntervalSince1970 / 300) * 300
        return Date(timeIntervalSince1970: roundedTimestamp)
    }

    private var multiStopDepartureTimeZone: TimeZone {
        timeDisplayMode == .utc
            ? TimeZone(secondsFromGMT: 0)!
            : secondDepartureAirport.timeZone
    }

    private var multiStopDepartureBinding: Binding<String> {
        Binding(
            get: {
                guard multiStopDepartureText.isEmpty else {
                    return multiStopDepartureText
                }
                return FlightDateTime.clock(
                    instant: automaticMultiStopDepartureInstant,
                    timeZone: multiStopDepartureTimeZone
                )
            },
            set: { multiStopDepartureText = $0 }
        )
    }

    private var returnDepartureInstant: Date? {
        if planningMode == .multiStop {
            if !multiStopDepartureText.isEmpty,
               let manualDeparture = FlightDateTime.instant(
                    date: returnFlightDate,
                    timeText: multiStopDepartureText,
                    timeZone: multiStopDepartureTimeZone
               )
            {
                return manualDeparture
            }
            return automaticMultiStopDepartureInstant
        }
        return homeArrivalInstant?.addingTimeInterval(
            TimeInterval(-returnTravelMinutes * 60)
        )
    }

    private var outboundAirportSample: EDFZWeatherSample? {
        outboundEDFZForecast?.sample(nearestTo: outboundStartInstant)
    }

    private var homeArrivalAirportSample: EDFZWeatherSample? {
        returnEDFZForecast?.sample(nearestTo: homeArrivalInstant)
    }

    private var intermediateArrivalSample: EDFZWeatherSample? {
        intermediateAirportForecast?.sample(
            nearestTo: outboundArrivalInstant
        )
    }

    private var intermediateDepartureSample: EDFZWeatherSample? {
        intermediateAirportForecast?.sample(
            nearestTo: returnDepartureInstant
        )
    }

    private var destinationArrivalSample: EDFZWeatherSample? {
        destinationReturnForecast?.sample(
            nearestTo: homeArrivalInstant
        )
    }

    private var destinationOutboundArrivalSample: EDFZWeatherSample? {
        destinationAirportForecast?.sample(
            nearestTo: outboundArrivalInstant
        )
    }

    private var destinationReturnDepartureSample: EDFZWeatherSample? {
        destinationReturnForecast?.sample(
            nearestTo: returnDepartureInstant
        )
    }

    private var firstArrivalWeather: PlanningWeather {
        let sample = destinationOutboundArrivalSample
        return PlanningWeather(
            sample: sample,
            elevationFeet: firstArrivalAirport.elevationFeet,
            runwayICAO: firstArrivalAirport.icao,
            referenceRunway: firstArrivalAirport.referenceRunway,
            foehnWarning: foehnModel.warning(
                airport: firstArrivalAirport,
                instant: outboundArrivalInstant,
                localWindKnots: sample?.windSpeedKnots,
                localGustKnots: sample?.windGustKnots
            )
        )
    }

    private var secondDepartureWeather: PlanningWeather {
        let sample = destinationReturnDepartureSample
        return PlanningWeather(
            sample: sample,
            elevationFeet: secondDepartureAirport.elevationFeet,
            runwayICAO: secondDepartureAirport.icao,
            referenceRunway: secondDepartureAirport.referenceRunway,
            foehnWarning: foehnModel.warning(
                airport: secondDepartureAirport,
                instant: returnDepartureInstant,
                localWindKnots: sample?.windSpeedKnots,
                localGustKnots: sample?.windGustKnots
            )
        )
    }

    private var secondArrivalWeather: PlanningWeather {
        let sample = homeArrivalAirportSample
        return PlanningWeather(
            sample: sample,
            elevationFeet: secondArrivalAirport.elevationFeet,
            runwayICAO: secondArrivalAirport.icao,
            referenceRunway: secondArrivalAirport.referenceRunway,
            foehnWarning: foehnModel.warning(
                airport: secondArrivalAirport,
                instant: homeArrivalInstant,
                localWindKnots: sample?.windSpeedKnots,
                localGustKnots: sample?.windGustKnots
            )
        )
    }

    private func runway(
        for sample: EDFZWeatherSample?
    ) -> String? {
        guard let direction = sample?.windDirectionDegrees,
              let speed = sample?.windSpeedKnots,
              speed >= 0.5
        else { return "—" }
        return EDFZRunway.activeRunway(
            for: origin.icao,
            referenceRunway: origin.referenceRunway,
            windFromDegrees: direction,
            speedKnots: speed
        )
    }

    private var outboundStartCondition: LightCondition {
        SolarCalculator.lightCondition(
            at: outboundStartInstant,
            latitude: origin.latitude,
            longitude: origin.longitude,
            timeZone: origin.timeZone
        )
    }

    private var outboundArrivalCondition: LightCondition {
        SolarCalculator.lightCondition(
            at: outboundArrivalInstant,
            latitude: firstArrivalAirport.latitude,
            longitude: firstArrivalAirport.longitude,
            timeZone: firstArrivalAirport.timeZone
        )
    }

    private var returnDepartureCondition: LightCondition {
        SolarCalculator.lightCondition(
            at: returnDepartureInstant,
            latitude: secondDepartureAirport.latitude,
            longitude: secondDepartureAirport.longitude,
            timeZone: secondDepartureAirport.timeZone
        )
    }

    private var homeArrivalCondition: LightCondition {
        SolarCalculator.lightCondition(
            at: homeArrivalInstant,
            latitude: secondArrivalAirport.latitude,
            longitude: secondArrivalAirport.longitude,
            timeZone: secondArrivalAirport.timeZone
        )
    }


    private func sunTexts(
        at instant: Date?,
        latitude: Double?,
        longitude: Double?,
        timeZone: TimeZone
    ) -> (civilDawn: String?, sunrise: String?, sunset: String?, civilDusk: String?) {
        guard
            let instant,
            let latitude,
            let longitude,
            let events = SolarCalculator.events(
                forLocalDayContaining: instant,
                latitude: latitude,
                longitude: longitude,
                timeZone: timeZone
            )
        else {
            return (nil, nil, nil, nil)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"

        return (
            formatter.string(from: events.civilDawn),
            formatter.string(from: events.sunrise),
            formatter.string(from: events.sunset),
            formatter.string(from: events.civilDusk)
        )
    }

    private func pickerDate(
        for instant: Date,
        in timeZone: TimeZone
    ) -> Date {
        var airportCalendar = Calendar(identifier: .gregorian)
        airportCalendar.timeZone = timeZone
        var components = airportCalendar.dateComponents(
            [.year, .month, .day],
            from: instant
        )
        components.hour = 12
        components.minute = 0
        components.second = 0
        components.timeZone = Calendar.current.timeZone
        return Calendar.current.date(from: components) ?? instant
    }

    private func setOutboundToNow() {
        let now = Date()
        outboundFlightDate = pickerDate(
            for: now,
            in: origin.timeZone
        )
        outboundStartText = FlightDateTime.clock(
            instant: now,
            timeZone: origin.timeZone
        )
    }

    private func setOutboundDay(_ dayOffset: Int) {
        let date = Calendar.current.date(
            byAdding: .day,
            value: dayOffset,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        let standardTime = "09:00"
        if dayOffset == 0,
           let standardInstant = FlightDateTime.instant(
               date: date,
               timeText: standardTime,
               timeZone: origin.timeZone
           ), standardInstant <= Date()
        {
            setOutboundToNow()
            return
        }
        outboundFlightDate = date
        outboundStartText = standardTime
    }

    private func standardReturnTime(on date: Date) -> String {
        guard let events = SolarCalculator.events(
            forLocalDayContaining: date,
            latitude: secondArrivalAirport.latitude,
            longitude: secondArrivalAirport.longitude,
            timeZone: secondArrivalAirport.timeZone
        ) else { return "17:00" }
        return FlightDateTime.clock(
            instant: events.sunset.addingTimeInterval(-60 * 60),
            timeZone: timeDisplayMode == .utc
                ? TimeZone(secondsFromGMT: 0)!
                : secondArrivalAirport.timeZone
        )
    }

    private func setReturnToNow() {
        if planningMode == .multiStop {
            let now = Date()
            returnFlightDate = pickerDate(
                for: now,
                in: secondDepartureAirport.timeZone
            )
            multiStopDepartureText = FlightDateTime.clock(
                instant: now,
                timeZone: timeDisplayMode == .utc
                    ? TimeZone(secondsFromGMT: 0)!
                    : secondDepartureAirport.timeZone
            )
            return
        }
        let departureNow = Date()
        let arrivalInstant = departureNow.addingTimeInterval(
            TimeInterval(returnTravelMinutes * 60)
        )
        returnFlightDate = pickerDate(
            for: arrivalInstant,
            in: origin.timeZone
        )
        desiredHomeArrivalText = FlightDateTime.clock(
            instant: arrivalInstant,
            timeZone: timeDisplayMode == .utc
                ? TimeZone(secondsFromGMT: 0)!
                : secondArrivalAirport.timeZone
        )
    }

    private func setReturnDay(_ dayOffset: Int) {
        let date = Calendar.current.date(
            byAdding: .day,
            value: dayOffset,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        let standardTime = planningMode == .multiStop
            ? "09:00"
            : standardReturnTime(on: date)
        let timeZone = timeDisplayMode == .utc
            ? TimeZone(secondsFromGMT: 0)!
            : (planningMode == .multiStop
                ? secondDepartureAirport.timeZone
                : secondArrivalAirport.timeZone)
        if dayOffset == 0,
           let standardInstant = FlightDateTime.instant(
               date: date,
               timeText: standardTime,
               timeZone: timeZone
           ), standardInstant <= Date()
        {
            returnFlightDate = pickerDate(for: Date(), in: timeZone)
            let currentTime = FlightDateTime.clock(
                instant: Date(),
                timeZone: timeZone
            )
            if planningMode == .multiStop {
                multiStopDepartureText = currentTime
            } else {
                desiredHomeArrivalText = currentTime
            }
            return
        }
        returnFlightDate = date
        if planningMode == .multiStop {
            multiStopDepartureText = standardTime
        } else {
            desiredHomeArrivalText = standardTime
        }
    }

    private func synchronizeMultiStopDepartureDate() {
        guard planningMode == .multiStop else { return }
        returnFlightDate = outboundFlightDate
    }

    var body: some View {
        VStack(spacing: 0) {
            FlightPlanningLine(
                directionTitle:
                    planningMode == .multiStop
                    ? "1. FLUG"
                    : "HINFLUG",
                flightDate: $outboundFlightDate,
                showsRefreshButton: true,
                refreshWeather: refreshWeather,
                resetSchedule: resetSchedule,
                reverseRoute: reverseRoute,
                setNow: setOutboundToNow,
                setToday: { setOutboundDay(0) },
                setTomorrow: { setOutboundDay(1) },
                showsETOPSHeader: true,
                stopCount: $outboundStops,
                stop1ICAO: $outboundStop1ICAO,
                stop2ICAO: $outboundStop2ICAO,
                stopAirportOptions: stopAirportOptions,
                stopSortOrigin: origin,
                stopSortDestination: firstArrivalAirport,
                flightAltitudeFeet:
                    $outboundFlightAltitudeFeet,
                altitudeOptions: outboundAltitudeOptions,
                travelMinutes: outboundTravelMinutes,
                directNM: outboundDirectNM,
                trackMiles: $outboundTrackMiles,
                headwindKnots: outboundRouteWind?.outboundHeadwindKnots,
                bestLevelFeet: outboundBestLevelFeet,
                routeRisks: outboundRouteRisks,
                routeAssessments: outboundRouteAssessments,
                tankStopMinutes: tankStopMinutes,
                preTakeoffGroundMinutes: preTakeoffGroundMinutes,
                postLandingGroundMinutes: postLandingGroundMinutes,
                cruiseGroundSpeedKnots:
                    cruiseGroundSpeedKnots,
                climbDeparturePressureAltitudeFeet: origin.elevationFeet,
                climbTargetPressureAltitudeFeet: Double(outboundFlightAltitudeFeet),
                climbPerformance: climbPerformance,
                cruisePerformance: cruisePerformance,
                leadingWeather: PlanningWeather(
                    sample: outboundAirportSample,
                    elevationFeet: origin.elevationFeet,
                    runwayICAO: origin.icao,
                    referenceRunway: origin.referenceRunway,
                    foehnWarning: foehnModel.warning(
                        airport: origin,
                        instant: outboundStartInstant,
                        localWindKnots: outboundAirportSample?.windSpeedKnots,
                        localGustKnots: outboundAirportSample?.windGustKnots
                    )
                ),
                trailingWeather: firstArrivalWeather,
                leadingCivilDawnText:
                    sunTexts(
                        at: outboundStartInstant,
                        latitude: origin.latitude,
                        longitude: origin.longitude,
                        timeZone: origin.timeZone
                    ).civilDawn,
                leadingSunriseText:
                    sunTexts(
                        at: outboundStartInstant,
                        latitude: origin.latitude,
                        longitude: origin.longitude,
                        timeZone: origin.timeZone
                    ).sunrise,
                leadingSunsetText:
                    sunTexts(
                        at: outboundStartInstant,
                        latitude: origin.latitude,
                        longitude: origin.longitude,
                        timeZone: origin.timeZone
                    ).sunset,
                leadingCivilDuskText:
                    sunTexts(
                        at: outboundStartInstant,
                        latitude: origin.latitude,
                        longitude: origin.longitude,
                        timeZone: origin.timeZone
                    ).civilDusk,
                trailingCivilDawnText:
                    sunTexts(
                        at: outboundArrivalInstant,
                        latitude: firstArrivalAirport.latitude,
                        longitude: firstArrivalAirport.longitude,
                        timeZone: firstArrivalAirport.timeZone
                    ).civilDawn,
                trailingSunriseText:
                    sunTexts(
                        at: outboundArrivalInstant,
                        latitude: firstArrivalAirport.latitude,
                        longitude: firstArrivalAirport.longitude,
                        timeZone: firstArrivalAirport.timeZone
                    ).sunrise,
                trailingSunsetText:
                    sunTexts(
                        at: outboundArrivalInstant,
                        latitude: firstArrivalAirport.latitude,
                        longitude: firstArrivalAirport.longitude,
                        timeZone: firstArrivalAirport.timeZone
                    ).sunset,
                trailingCivilDuskText:
                    sunTexts(
                        at: outboundArrivalInstant,
                        latitude: firstArrivalAirport.latitude,
                        longitude: firstArrivalAirport.longitude,
                        timeZone: firstArrivalAirport.timeZone
                    ).civilDusk,
                leadingTitle: "ABFLUG \(origin.icao)",
                leadingRunway: runway(for: outboundAirportSample),
                trailingTitle:
                    "ANKUNFT \(firstArrivalAirport.icao)",
                trailingRunway: firstArrivalWeather.runway,
                leadingOperatingStatus: AirportOperatingHoursEvaluator.status(
                    airport: origin,
                    at: outboundStartInstant,
                    operation: .departure,
                    flyingWithoutFlightDirector: activeBaseProfile.flyingWithoutFlightDirectorEnabled,
                    homeAirportICAO: activeBaseProfile.homeAirportICAO,
                    initialHomeDeparture: initialHomeDepartureInstant,
                    plannedHomeReturn: homeArrivalInstant,
                    legOriginICAO: origin.icao
                ),
                trailingOperatingStatus: AirportOperatingHoursEvaluator.status(
                    airport: firstArrivalAirport,
                    at: outboundArrivalInstant,
                    operation: .arrival,
                    flyingWithoutFlightDirector: activeBaseProfile.flyingWithoutFlightDirectorEnabled,
                    homeAirportICAO: activeBaseProfile.homeAirportICAO,
                    initialHomeDeparture: initialHomeDepartureInstant,
                    plannedHomeReturn: homeArrivalInstant,
                    legOriginICAO: origin.icao
                ),
                leadingAirportSelection: $outboundOriginSelection,
                trailingAirportSelection: $outboundDestinationSelection,
                airportOptions: airportOptions,
                leading: {
                    EditableFlightTimeField(
                        title: "ABFLUG \(origin.icao)",
                        text: $outboundStartText,
                        symbol: "airplane.departure",
                        lightCondition:
                            outboundStartCondition
                    )
                },
                trailing: {
                    CalculatedFlightTime(
                        value: FlightDateTime.clock(
                            instant: outboundArrivalInstant,
                            timeZone: timeDisplayMode == .utc
                                ? TimeZone(secondsFromGMT: 0)!
                                : firstArrivalAirport.timeZone
                        ),
                        symbol: "airplane.arrival",
                        lightCondition:
                            outboundArrivalCondition
                    )
                }
            )
            .flightLegPanel()

            if !isOneWay {
                Color.clear.frame(height: 18)

                FlightPlanningLine(
                directionTitle:
                    planningMode == .multiStop
                    ? "2. FLUG"
                    : "RÜCKFLUG",
                flightDate: $returnFlightDate,
                showsRefreshButton: false,
                refreshWeather: refreshWeather,
                resetSchedule: resetSchedule,
                reverseRoute: reverseRoute,
                setNow: setReturnToNow,
                setToday: { setReturnDay(0) },
                setTomorrow: { setReturnDay(1) },
                    showsETOPSHeader: true,
                stopCount: $returnStops,
                stop1ICAO: $returnStop1ICAO,
                stop2ICAO: $returnStop2ICAO,
                stopAirportOptions: stopAirportOptions,
                stopSortOrigin: secondDepartureAirport,
                stopSortDestination: secondArrivalAirport,
                flightAltitudeFeet:
                    $returnFlightAltitudeFeet,
                altitudeOptions: returnAltitudeOptions,
                travelMinutes: returnTravelMinutes,
                directNM: returnDirectNM,
                trackMiles: $returnTrackMiles,
                headwindKnots: returnRouteWind?.outboundHeadwindKnots,
                bestLevelFeet: returnBestLevelFeet,
                routeRisks: returnRouteRisks,
                routeAssessments: returnRouteAssessments,
                tankStopMinutes: tankStopMinutes,
                preTakeoffGroundMinutes: preTakeoffGroundMinutes,
                postLandingGroundMinutes: postLandingGroundMinutes,
                cruiseGroundSpeedKnots:
                    cruiseGroundSpeedKnots,
                climbDeparturePressureAltitudeFeet: secondDepartureAirport.elevationFeet,
                climbTargetPressureAltitudeFeet: Double(returnFlightAltitudeFeet),
                climbPerformance: climbPerformance,
                cruisePerformance: cruisePerformance,
                leadingWeather: secondDepartureWeather,
                trailingWeather: secondArrivalWeather,
                leadingCivilDawnText:
                    sunTexts(
                        at: returnDepartureInstant,
                        latitude: secondDepartureAirport.latitude,
                        longitude: secondDepartureAirport.longitude,
                        timeZone: secondDepartureAirport.timeZone
                    ).civilDawn,
                leadingSunriseText:
                    sunTexts(
                        at: returnDepartureInstant,
                        latitude: secondDepartureAirport.latitude,
                        longitude: secondDepartureAirport.longitude,
                        timeZone: secondDepartureAirport.timeZone
                    ).sunrise,
                leadingSunsetText:
                    sunTexts(
                        at: returnDepartureInstant,
                        latitude: secondDepartureAirport.latitude,
                        longitude: secondDepartureAirport.longitude,
                        timeZone: secondDepartureAirport.timeZone
                    ).sunset,
                leadingCivilDuskText:
                    sunTexts(
                        at: returnDepartureInstant,
                        latitude: secondDepartureAirport.latitude,
                        longitude: secondDepartureAirport.longitude,
                        timeZone: secondDepartureAirport.timeZone
                    ).civilDusk,
                trailingCivilDawnText:
                    sunTexts(
                        at: homeArrivalInstant,
                        latitude: secondArrivalAirport.latitude,
                        longitude: secondArrivalAirport.longitude,
                        timeZone: secondArrivalAirport.timeZone
                    ).civilDawn,
                trailingSunriseText:
                    sunTexts(
                        at: homeArrivalInstant,
                        latitude: secondArrivalAirport.latitude,
                        longitude: secondArrivalAirport.longitude,
                        timeZone: secondArrivalAirport.timeZone
                    ).sunrise,
                trailingSunsetText:
                    sunTexts(
                        at: homeArrivalInstant,
                        latitude: secondArrivalAirport.latitude,
                        longitude: secondArrivalAirport.longitude,
                        timeZone: secondArrivalAirport.timeZone
                    ).sunset,
                trailingCivilDuskText:
                    sunTexts(
                        at: homeArrivalInstant,
                        latitude: secondArrivalAirport.latitude,
                        longitude: secondArrivalAirport.longitude,
                        timeZone: secondArrivalAirport.timeZone
                    ).civilDusk,
                leadingTitle:
                    "ABFLUG \(secondDepartureAirport.icao)",
                leadingRunway: secondDepartureWeather.runway,
                trailingTitle:
                    "ANKUNFT \(secondArrivalAirport.icao)",
                trailingRunway: secondArrivalWeather.runway,
                leadingOperatingStatus: AirportOperatingHoursEvaluator.status(
                    airport: secondDepartureAirport,
                    at: returnDepartureInstant,
                    operation: .departure,
                    flyingWithoutFlightDirector: activeBaseProfile.flyingWithoutFlightDirectorEnabled,
                    homeAirportICAO: activeBaseProfile.homeAirportICAO,
                    initialHomeDeparture: initialHomeDepartureInstant,
                    plannedHomeReturn: homeArrivalInstant,
                    legOriginICAO: secondDepartureAirport.icao
                ),
                trailingOperatingStatus: AirportOperatingHoursEvaluator.status(
                    airport: secondArrivalAirport,
                    at: homeArrivalInstant,
                    operation: .arrival,
                    flyingWithoutFlightDirector: activeBaseProfile.flyingWithoutFlightDirectorEnabled,
                    homeAirportICAO: activeBaseProfile.homeAirportICAO,
                    initialHomeDeparture: initialHomeDepartureInstant,
                    plannedHomeReturn: homeArrivalInstant,
                    legOriginICAO: secondDepartureAirport.icao
                ),
                leadingAirportSelection: $returnOriginSelection,
                trailingAirportSelection: $returnDestinationSelection,
                airportOptions: airportOptions,
                leading: {
                    if planningMode == .multiStop {
                        EditableFlightTimeField(
                            title:
                                "ABFLUG \(secondDepartureAirport.icao)",
                            text: multiStopDepartureBinding,
                            symbol: "airplane.departure",
                            lightCondition: returnDepartureCondition
                        )
                    } else {
                        CalculatedFlightTime(
                            value: FlightDateTime.clock(
                                instant: returnDepartureInstant,
                                timeZone: timeDisplayMode == .utc
                                    ? TimeZone(secondsFromGMT: 0)!
                                    : secondDepartureAirport.timeZone
                            ),
                            symbol: "airplane.departure",
                            lightCondition:
                                returnDepartureCondition
                        )
                    }
                },
                trailing: {
                    if planningMode == .multiStop {
                        CalculatedFlightTime(
                            value: FlightDateTime.clock(
                                instant: homeArrivalInstant,
                                timeZone: timeDisplayMode == .utc
                                    ? TimeZone(secondsFromGMT: 0)!
                                    : secondArrivalAirport.timeZone
                            ),
                            symbol: "airplane.arrival",
                            lightCondition: homeArrivalCondition
                        )
                    } else {
                        EditableFlightTimeField(
                            title: "ANKUNFT \(origin.icao)",
                            text: $desiredHomeArrivalText,
                            symbol: "airplane.arrival",
                            lightCondition:
                                homeArrivalCondition
                        )
                    }
                }
                )
                .padding(.bottom, 8)
                .flightLegPanel()
            }
        }
        .onChange(of: outboundStartText) { newValue in
            let filtered = TimeInput.filtered(newValue)

            if filtered != newValue {
                outboundStartText = filtered
            }
        }
        .onChange(of: desiredHomeArrivalText) { newValue in
            let filtered = TimeInput.filtered(newValue)

            if filtered != newValue {
                desiredHomeArrivalText = filtered
            }
        }
        .onChange(of: multiStopDepartureText) { newValue in
            let filtered = TimeInput.filtered(newValue)

            if filtered != newValue {
                multiStopDepartureText = filtered
            }
        }
        .onChange(of: planningMode) { _ in
            synchronizeMultiStopDepartureDate()
        }
        .onChange(of: intermediateAirportICAO) { _ in
            synchronizeMultiStopDepartureDate()
        }
        .onChange(of: outboundFlightDate) { _ in
            synchronizeMultiStopDepartureDate()
        }
        .onChange(of: outboundStartText) { _ in
            synchronizeMultiStopDepartureDate()
        }
        .onChange(of: outboundTravelMinutes) { _ in
            synchronizeMultiStopDepartureDate()
        }
        .onChange(of: tankStopMinutes) { _ in
            synchronizeMultiStopDepartureDate()
        }
        .onAppear {
            synchronizeMultiStopDepartureDate()
        }
    }
}


private struct TimeContextInfo: View {
    let weather: PlanningWeather

    @AppStorage(PressureSettingsKey.displayUnit)
    private var pressureDisplayUnitRaw =
        PressureDisplayUnit.mbar.rawValue

    private var pressureText: String {
        guard let pressure = weather.pressureMbar else { return "—" }
        let unit = PressureDisplayUnit(
            rawValue: pressureDisplayUnitRaw
        ) ?? .mbar
        switch unit {
        case .mbar:
            return String(format: "%.0f", pressure)
        case .inHg:
            return String(format: "%.2f", pressure * 0.0295299830714)
        }
    }

    private var densityAltitude: Double? {
        guard let temperature = weather.temperature,
              let pressure = weather.pressureMbar
        else { return nil }
        let pressureAltitude = weather.elevationFeet
            + (1013.25 - pressure) * 30
        let isaTemperature = 15
            - 1.98 * (pressureAltitude / 1000)
        return pressureAltitude
            + 120 * (temperature - isaTemperature)
    }

    private var densityAltitudeText: String {
        densityAltitude.map {
            let roundedAltitude =
                ($0 / 100).rounded(.toNearestOrAwayFromZero) * 100
            return String(format: "DA %.0f ft", roundedAltitude)
        } ?? "DA —"
    }

    private var densityAltitudeBackground: Color {
        guard let densityAltitude else { return .clear }
        if densityAltitude >= 5000 {
            return Color.red.opacity(0.82)
        }
        if densityAltitude >= 2500 {
            return Color.yellow.opacity(0.62)
        }
        return .clear
    }

    private var densityAltitudeForeground: Color {
        guard let densityAltitude, densityAltitude >= 5000 else {
            return FlybookColor.navy
        }
        return .white
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                HStack(spacing: 0) {
                    Image(
                        systemName:
                            "gauge.with.dots.needle.33percent"
                    )
                    Text(pressureText)
                }
                .fixedSize(horizontal: true, vertical: false)

                Text(densityAltitudeText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(densityAltitudeForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(densityAltitudeBackground)
                    )
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(FlybookColor.navy)
        }
        .frame(height: 22)
    }
}

private struct WindFlowIndicator: View {
    let weather: PlanningWeather

    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(FlybookColor.navy)
        .frame(width: 22, height: 22)
        .rotationEffect(
            .degrees((weather.direction ?? 180) + 180)
        )
        .opacity(weather.direction == nil ? 0.35 : 1)
        .help("Die Pfeilspitze zeigt in die Richtung, in die der Wind weht")
    }
}

private extension View {
    func flightLegPanel() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(FlybookColor.blue.opacity(0.035))
                    .padding(-5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(FlybookColor.navy.opacity(0.34), lineWidth: 2)
                    .padding(-5)
            )
    }
}

private struct FlightPlanningLine<
    Leading: View,
    Trailing: View
>: View {
    let directionTitle: String
    @Binding var flightDate: Date
    let showsRefreshButton: Bool
    let refreshWeather: () -> Void
    let resetSchedule: () -> Void
    let reverseRoute: () -> Void
    let setNow: () -> Void
    let setToday: () -> Void
    let setTomorrow: () -> Void
    let showsETOPSHeader: Bool
    @Binding var stopCount: Int
    @Binding var stop1ICAO: String
    @Binding var stop2ICAO: String
    let stopAirportOptions: [AirportReference]
    let stopSortOrigin: AirportReference
    let stopSortDestination: AirportReference
    @Binding var flightAltitudeFeet: Int
    let altitudeOptions: [Int]
    let travelMinutes: Int
    let directNM: Double
    @Binding var trackMiles: Double
    let headwindKnots: Double?
    let bestLevelFeet: Int?
    let routeRisks: [RouteWeatherRisk]
    let routeAssessments: [RouteWeatherSegmentAssessment]
    let tankStopMinutes: Int
    let preTakeoffGroundMinutes: Int
    let postLandingGroundMinutes: Int
    let cruiseGroundSpeedKnots: Double
    let climbDeparturePressureAltitudeFeet: Double
    let climbTargetPressureAltitudeFeet: Double
    let climbPerformance: ClimbPerformance
    let cruisePerformance: CruisePerformance
    let leadingWeather: PlanningWeather
    let trailingWeather: PlanningWeather
    let leadingCivilDawnText: String?
    let leadingSunriseText: String?
    let leadingSunsetText: String?
    let leadingCivilDuskText: String?
    let trailingCivilDawnText: String?
    let trailingSunriseText: String?
    let trailingSunsetText: String?
    let trailingCivilDuskText: String?
    let leadingTitle: String
    let leadingRunway: String?
    let trailingTitle: String
    let trailingRunway: String?
    let leadingOperatingStatus: AirportOperatingStatus?
    let trailingOperatingStatus: AirportOperatingStatus?
    let leadingAirportSelection: Binding<String>?
    let trailingAirportSelection: Binding<String>?
    let airportOptions: [AirportReference]

    @AppStorage(ETOPSSettingsKey.greenYellowMinutes)
    private var greenYellowMinutes =
        ETOPSScale.defaultGreenYellowMinutes

    @AppStorage(ETOPSSettingsKey.orangeRedMinutes)
    private var orangeRedMinutes =
        ETOPSScale.defaultOrangeRedMinutes

    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    private var selectedLegMinutes: Int {
        FlightMath.adjustedPerLegMinutes(
            directNM: directNM,
            stopCount: stopCount,
            headwindKnots: headwindKnots,
            tankStopMinutes: tankStopMinutes,
            cruiseGroundSpeedKnots:
                cruiseGroundSpeedKnots,
            climbDeparturePressureAltitudeFeet: climbDeparturePressureAltitudeFeet,
            climbTargetPressureAltitudeFeet: climbTargetPressureAltitudeFeet,
            climbPerformance: climbPerformance,
            cruisePerformance: cruisePerformance,
            trackMilesNM: trackMiles,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes
        )
    }

    private var blockMinutesWithoutPauses: Int {
        max(0, travelMinutes - stopCount * max(0, tankStopMinutes))
    }

    private var legBlockMinutes: [Int] {
        let legCount = max(1, stopCount + 1)
        guard legCount > 1 else { return [blockMinutesWithoutPauses] }

        var points: [(latitude: Double, longitude: Double)] = [
            (stopSortOrigin.latitude, stopSortOrigin.longitude)
        ]
        if stopCount >= 1 {
            points.append(
                stopAirportOptions.first(where: { $0.icao == stop1ICAO }).map {
                    ($0.latitude, $0.longitude)
                } ?? routePoint(fraction: stopCount == 1 ? 0.5 : 1.0 / 3.0)
            )
        }
        if stopCount >= 2 {
            points.append(
                stopAirportOptions.first(where: { $0.icao == stop2ICAO }).map {
                    ($0.latitude, $0.longitude)
                } ?? routePoint(fraction: 2.0 / 3.0)
            )
        }
        points.append((stopSortDestination.latitude, stopSortDestination.longitude))

        let distances = zip(points, points.dropFirst()).map {
            coordinateDistanceNM(from: $0.0, to: $0.1)
        }
        let totalDistance = distances.reduce(0, +)
        guard totalDistance > 0 else {
            let base = blockMinutesWithoutPauses / legCount
            return (0..<legCount).map {
                $0 == legCount - 1
                    ? blockMinutesWithoutPauses - base * (legCount - 1)
                    : base
            }
        }

        var allocated: [Int] = []
        var remaining = blockMinutesWithoutPauses
        for (index, distance) in distances.enumerated() {
            let value = index == distances.count - 1
                ? remaining
                : min(remaining, Int(round(Double(blockMinutesWithoutPauses) * distance / totalDistance)))
            allocated.append(value)
            remaining -= value
        }
        return allocated
    }

    private func altitudeLabel(_ altitudeFeet: Int) -> String {
        if altitudeFeet >= 5000 {
            return String(
                format: "FL%03d",
                Int(round(Double(altitudeFeet) / 100.0))
            )
        }
        return altitudeFeet.formatted(
            .number.grouping(.automatic)
        ) + " ft"
    }

    var body: some View {
        VStack(spacing: 0) {
            planningHeaderRow
            planningTimeRow.padding(.top, 8)
            planningWeatherRow.padding(.top, 8)
        }
        .frame(width: 622, alignment: .leading)
        .onAppear { selectNearestBestLevel() }
        .onChange(of: bestLevelFeet) { _ in selectNearestBestLevel() }
    }

    private func selectNearestBestLevel() {
        guard let bestLevelFeet, !altitudeOptions.isEmpty else { return }
        flightAltitudeFeet = altitudeOptions.min {
            abs($0 - bestLevelFeet) < abs($1 - bestLevelFeet)
        } ?? flightAltitudeFeet
    }

    private var planningHeaderRow: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(directionTitle)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(FlybookColor.navy)
                .frame(width: 128, alignment: .leading)

            Group {
                if let leadingAirportSelection {
                    airportHeaderPicker(
                        title: "ABFLUG",
                        selection: leadingAirportSelection,
                        runway: leadingRunway,
                        warning: leadingWeather.runwayCrosswindWarning,
                        operatingStatus: leadingOperatingStatus
                    )
                } else {
                    FlightLocationHeader(
                        title: leadingTitle,
                        runway: leadingRunway,
                        crosswindWarning: leadingWeather.runwayCrosswindWarning,
                        windComponents: leadingWeather.runwayWindComponents,
                        windDirection: leadingWeather.direction
                    )
                }
            }
            .frame(width: 174)

            Color.clear.frame(width: 18, height: 1)

            Group {
                if let trailingAirportSelection {
                    airportHeaderPicker(
                        title: "ANKUNFT",
                        selection: trailingAirportSelection,
                        runway: trailingRunway,
                        warning: trailingWeather.runwayCrosswindWarning,
                        operatingStatus: trailingOperatingStatus
                    )
                } else {
                    FlightLocationHeader(
                        title: trailingTitle,
                        runway: trailingRunway,
                        crosswindWarning: trailingWeather.runwayCrosswindWarning,
                        windComponents: trailingWeather.runwayWindComponents,
                        windDirection: trailingWeather.direction
                    )
                }
            }
            .frame(width: 174)

            VStack(spacing: 2) {
                Text("ETOPS-PIPI")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
                    .lineLimit(1)
                Circle()
                    .fill(ETOPSBand.color(for: selectedLegMinutes, greenYellowMinutes: greenYellowMinutes, orangeRedMinutes: orangeRedMinutes))
                    .overlay(Circle().stroke(FlybookColor.navy.opacity(0.35), lineWidth: 1))
                    .frame(width: 16, height: 16)
            }
            .frame(width: 128, height: 42)
        }
        .overlay(alignment: .topLeading) {
            RouteRiskDots(assessments: routeAssessments)
                .offset(x: 261, y: 1)
        }
    }

    private func airportHeaderPicker(
        title: String,
        selection: Binding<String>,
        runway: String?,
        warning: RunwayCrosswindWarning,
        operatingStatus: AirportOperatingStatus?
    ) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FlybookColor.muted)

            airportSelectionMenu(title: title, selection: selection, operatingStatus: operatingStatus)
                .padding(.top, 4)

            HStack(spacing: 6) {
                Circle()
                    .fill(airportOperatingStatusColor(operatingStatus))
                    .overlay(
                        Circle().stroke(FlybookColor.navy.opacity(0.35), lineWidth: 1)
                    )
                    .frame(width: 11, height: 11)

                RunwayRecommendationButton(
                    runway: runway,
                    warning: warning,
                    windComponents: title == "ABFLUG"
                        ? leadingWeather.runwayWindComponents
                        : trailingWeather.runwayWindComponents,
                    windDirection: title == "ABFLUG"
                        ? leadingWeather.direction
                        : trailingWeather.direction
                )
            }
            .frame(height: 28)
            .padding(.top, 8)
        }
    }

    private func airportSelectionMenu(
        title: String,
        selection: Binding<String>,
        operatingStatus: AirportOperatingStatus?
    ) -> some View {
        let selected = airportOptions.first { $0.icao == selection.wrappedValue }
        return Menu {
            ForEach(airportOptions) { airport in
                Button("\(airport.icao) · \(airport.name)") {
                    selection.wrappedValue = airport.icao
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selected.map { "\($0.icao) · \($0.name)" } ?? selection.wrappedValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FlybookColor.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
            }
            .padding(.horizontal, 9)
            .frame(width: 174, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(FlybookColor.line, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .frame(width: 174, height: 28)
    }

    private func airportOperatingStatusColor(_ status: AirportOperatingStatus?) -> Color {
        switch status {
        case .open, .closingSoon: return Color.green
        case .flyingWithoutFlightDirector: return FlybookColor.blue
        case .closedOrPPR: return Color.red
        case .none: return Color.gray
        }
    }

    private var planningTimeRow: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                DatePicker("", selection: $flightDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .controlSize(.large)
                    .font(.system(size: 18, weight: .semibold))
                    .fixedSize()
                Spacer(minLength: 0)
            }
            .frame(width: 128, height: 43)

            leading.frame(width: 174, height: 43)
            Image(systemName: "arrow.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FlybookColor.muted)
                .frame(width: 18, height: 43)
            trailing.frame(width: 174, height: 43)
            TravelDurationBadge(
                minutes: travelMinutes,
                blockMinutes: blockMinutesWithoutPauses,
                legMinutes: legBlockMinutes,
                stopCount: stopCount,
                pauseMinutesPerStop: tankStopMinutes
            )
                .frame(width: 74, height: 43)
                .frame(width: 128)
        }
    }

    private var planningWeatherRow: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 7) {
                Button("Jetzt", action: setNow)
                HStack(spacing: 6) {
                    Button("Heute", action: setToday)
                    Button("Morgen", action: setTomorrow)
                }
                .font(.system(size: 11, weight: .bold))
                .controlSize(.small)

                if showsRefreshButton {
                    planningActionButton(
                        "Update",
                        systemImage: "arrow.clockwise",
                        prominent: true,
                        action: refreshWeather
                    )
                    .help(
                        "Datensparender Flug-Refresh: nur die bis zu vier "
                        + "Flugplanungsplätze und Alternates; ohne "
                        + "Langfristprognose, Streckenwind und Korridorwetter"
                    )
                    planningActionButton("Reset", systemImage: "arrow.counterclockwise", action: resetSchedule)
                    planningActionButton("Zielumkehr", systemImage: "arrow.left.arrow.right", action: reverseRoute)
                }
            }
            .buttonStyle(.bordered)
            .frame(width: 128, alignment: .top)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    PlanningWeatherCard(weather: leadingWeather, civilDawnText: leadingCivilDawnText, sunriseText: leadingSunriseText, sunsetText: leadingSunsetText, civilDuskText: leadingCivilDuskText)
                        .frame(width: 174, height: 184)
                    Color.clear.frame(width: 18, height: 1)
                    PlanningWeatherCard(weather: trailingWeather, civilDawnText: trailingCivilDawnText, sunriseText: trailingSunriseText, sunsetText: trailingSunsetText, civilDuskText: trailingCivilDuskText)
                        .frame(width: 174, height: 184)
                }

                Spacer(minLength: 0)
                planningFooterContent
                    .frame(height: 24)
            }
            .frame(width: 366, height: 224, alignment: .top)

            VStack(spacing: 9) {
                TrackMilesEditor(trackMiles: $trackMiles)
                StopCountSelector(selection: $stopCount)
                    .frame(width: 120, height: 84)
                Group {
                    if stopCount > 0 {
                        stopAirportPicker(
                            title: "STOP 1",
                            selection: $stop1ICAO,
                            stopIndex: 1
                        )
                    } else {
                        Color.clear.frame(width: 120, height: 22)
                    }
                }
                Group {
                    if stopCount > 1 {
                        stopAirportPicker(
                            title: "STOP 2",
                            selection: $stop2ICAO,
                            stopIndex: 2
                        )
                    } else {
                        Color.clear.frame(width: 120, height: 22)
                    }
                }
            }
            .frame(width: 128, alignment: .top)
        }
    }

    private func stopAirportPicker(
        title: String,
        selection: Binding<String>,
        stopIndex: Int
    ) -> some View {
        Picker(title, selection: selection) {
            Text("Virtuell").tag("")
            ForEach(sortedStopAirportOptions(stopIndex: stopIndex)) { airport in
                Text("\(airport.icao) · \(airport.name)").tag(airport.icao)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: 120)
        .help("Virtuell verwendet die Modellroute; ein Flugplatz berechnet die tatsächlichen Teilstrecken.")
    }

    private func sortedStopAirportOptions(stopIndex: Int) -> [AirportReference] {
        let fraction: Double
        if stopCount <= 1 {
            fraction = 0.5
        } else {
            fraction = stopIndex == 1 ? 1.0 / 3.0 : 2.0 / 3.0
        }

        let target = routePoint(fraction: fraction)
        return stopAirportOptions
            .filter {
                $0.icao != stopSortOrigin.icao
                    && $0.icao != stopSortDestination.icao
                    && (stopIndex == 1 || $0.icao != stop1ICAO)
                    && (stopIndex == 2 || $0.icao != stop2ICAO)
            }
            .sorted { lhs, rhs in
                let lhsDistance = distanceNM(from: lhs, to: target)
                let rhsDistance = distanceNM(from: rhs, to: target)
                if abs(lhsDistance - rhsDistance) > 0.01 {
                    return lhsDistance < rhsDistance
                }
                return lhs.icao < rhs.icao
            }
    }

    private func routePoint(fraction: Double) -> (latitude: Double, longitude: Double) {
        let startLat = stopSortOrigin.latitude * .pi / 180
        let startLon = stopSortOrigin.longitude * .pi / 180
        let endLat = stopSortDestination.latitude * .pi / 180
        let endLon = stopSortDestination.longitude * .pi / 180
        let angularDistance = 2 * asin(sqrt(
            pow(sin((endLat - startLat) / 2), 2)
                + cos(startLat) * cos(endLat)
                * pow(sin((endLon - startLon) / 2), 2)
        ))
        guard angularDistance > 0.000_001 else {
            return (stopSortOrigin.latitude, stopSortOrigin.longitude)
        }
        let a = sin((1 - fraction) * angularDistance) / sin(angularDistance)
        let b = sin(fraction * angularDistance) / sin(angularDistance)
        let x = a * cos(startLat) * cos(startLon) + b * cos(endLat) * cos(endLon)
        let y = a * cos(startLat) * sin(startLon) + b * cos(endLat) * sin(endLon)
        let z = a * sin(startLat) + b * sin(endLat)
        return (
            atan2(z, sqrt(x * x + y * y)) * 180 / .pi,
            atan2(y, x) * 180 / .pi
        )
    }

    private func distanceNM(
        from airport: AirportReference,
        to point: (latitude: Double, longitude: Double)
    ) -> Double {
        let radiusNM = 3440.065
        let lat1 = airport.latitude * .pi / 180
        let lat2 = point.latitude * .pi / 180
        let deltaLat = (point.latitude - airport.latitude) * .pi / 180
        let deltaLon = (point.longitude - airport.longitude) * .pi / 180
        let value = pow(sin(deltaLat / 2), 2)
            + cos(lat1) * cos(lat2) * pow(sin(deltaLon / 2), 2)
        return radiusNM * 2 * atan2(sqrt(value), sqrt(max(0, 1 - value)))
    }

    private func coordinateDistanceNM(
        from start: (latitude: Double, longitude: Double),
        to end: (latitude: Double, longitude: Double)
    ) -> Double {
        let radiusNM = 3440.065
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLat = (end.latitude - start.latitude) * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180
        let value = pow(sin(deltaLat / 2), 2)
            + cos(lat1) * cos(lat2) * pow(sin(deltaLon / 2), 2)
        return radiusNM * 2 * atan2(sqrt(value), sqrt(max(0, 1 - value)))
    }

    private var planningFooterContent: some View {
            HStack(spacing: 0) {
                Text(bestLevelFeet.map { String(format: "Best Level: FL%03d", Int(round(Double($0) / 100.0))) } ?? "Best Level: —")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(width: 140, alignment: .trailing)
                Picker("Flughöhe", selection: $flightAltitudeFeet) {
                    ForEach(altitudeOptions, id: \.self) { altitude in Text(altitudeLabel(altitude)).tag(altitude) }
                }
                .labelsHidden()
                .font(.system(size: 14, weight: .bold))
                .controlSize(.small)
                .frame(width: 96)
                Group {
                    if let headwindKnots { WindInfluenceLabel(headwindKnots: headwindKnots) }
                }
                .frame(width: 130, alignment: .leading)
            }
            .frame(width: 366, alignment: .center)
    }

    private func planningActionButton(
        _ title: String,
        systemImage: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: systemImage).font(.system(size: 17, weight: .bold))
                Text(title).font(.system(size: 10, weight: .bold))
            }
            .frame(width: 96, height: 32)
            .foregroundStyle(prominent ? Color.white : FlybookColor.navy)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        prominent
                            ? FlybookColor.blue
                            : Color(nsColor: .controlBackgroundColor)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        prominent
                            ? FlybookColor.navy.opacity(0.35)
                            : FlybookColor.line,
                        lineWidth: prominent ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

}

private struct TrackMilesEditor: View {
    @Binding var trackMiles: Double

    var body: some View {
        VStack(spacing: 3) {
            Text("TRACK NM")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(width: 112)

            Text(String(format: "%.0f", trackMiles))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(FlybookColor.navy)

            HStack(spacing: 3) {
                Button {
                    trackMiles = nextLowerFive(from: trackMiles)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 28, height: 24)
                        .contentShape(Rectangle())
                }
                Button {
                    trackMiles = nextHigherFive(from: trackMiles)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 28, height: 24)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .help("Track Miles aus einem externen Flugplan übernehmen")
    }

    private func nextLowerFive(from value: Double) -> Double {
        let lower = floor(value / 5) * 5
        if abs(value - lower) < 0.001 {
            return max(0, lower - 5)
        }
        return max(0, lower)
    }

    private func nextHigherFive(from value: Double) -> Double {
        let upper = ceil(value / 5) * 5
        if abs(value - upper) < 0.001 {
            return upper + 5
        }
        return upper
    }
}

private struct MainzReservationView: View {
    @Binding var reservationFrom: Date
    @Binding var reservationUntil: Date
    let actualBlockMinutes: Int

    private var breakdown: ReservationBreakdown {
        ReservationBreakdown.calculate(
            from: reservationFrom,
            until: reservationUntil
        )
    }

    private var actualBlockHours: Double {
        CharterMath.commercialDecimalHours(
            minutes: actualBlockMinutes
        )
    }

    private var requirementIsMet: Bool {
        actualBlockHours + 0.000_1
            >= breakdown.requiredBlockHours
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("RESERVIERUNG MAINZ")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)
                Spacer()
                Text("08:00–20:00")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
            }

            HStack(spacing: 12) {
                reservationPicker(
                    title: "VON",
                    selection: $reservationFrom
                )
                reservationPicker(
                    title: "BIS",
                    selection: $reservationUntil
                )
            }

            Divider()

            reservationResult(
                title: "MO–FR",
                reservedHours: breakdown.weekdayHours,
                percentage: 10,
                requiredHours: breakdown.weekdayRequiredBlockHours
            )
            reservationResult(
                title: "SA/SO",
                reservedHours: breakdown.weekendHours,
                percentage: 20,
                requiredHours: breakdown.weekendRequiredBlockHours
            )

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ERFORDERLICHE BLOCKZEIT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(FlybookColor.muted)
                    Text(decimalHours(breakdown.requiredBlockHours))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("TATSÄCHLICHE BLOCKZEIT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(FlybookColor.muted)
                    Text(decimalHours(actualBlockHours))
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(
                            requirementIsMet ? Color.green : Color.red
                        )
                }
            }

            if reservationUntil <= reservationFrom {
                Text("„Bis“ muss nach „Von“ liegen.")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.red)
            } else {
                Text(
                    requirementIsMet
                        ? "Mindestnutzung erfüllt"
                        : "Mindestblockzeit unterschritten"
                )
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(
                    requirementIsMet ? Color.green : Color.red
                )
            }
        }
    }

    private func reservationPicker(
        title: String,
        selection: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
            DatePicker(
                title,
                selection: selection,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.field)
            .controlSize(.small)
            .environment(\.timeZone, DestinationTimeZone.edfz)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reservationResult(
        title: String,
        reservedHours: Double,
        percentage: Int,
        requiredHours: Double
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(FlybookColor.navy)
                .frame(width: 48, alignment: .leading)
            Text("Reserviert \(decimalHours(reservedHours))")
            Spacer()
            Text("\(percentage)% → \(decimalHours(requiredHours)) Block")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(FlybookColor.navy)
    }

    private func decimalHours(_ hours: Double) -> String {
        let rounded =
            (hours * 10).rounded(.toNearestOrAwayFromZero) / 10
        return rounded.formatted(
            .number
                .locale(Locale(identifier: "en_US_POSIX"))
                .precision(.fractionLength(1))
        ) + " h"
    }
}

private struct ReservationBreakdown {
    let weekdayHours: Double
    let weekendHours: Double

    var weekdayRequiredBlockHours: Double {
        weekdayHours * 0.10
    }

    var weekendRequiredBlockHours: Double {
        weekendHours * 0.20
    }

    var requiredBlockHours: Double {
        weekdayRequiredBlockHours + weekendRequiredBlockHours
    }

    static func calculate(
        from start: Date,
        until end: Date
    ) -> ReservationBreakdown {
        guard end > start else {
            return ReservationBreakdown(
                weekdayHours: 0,
                weekendHours: 0
            )
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DestinationTimeZone.edfz
        var day = calendar.startOfDay(for: start)
        let finalDay = calendar.startOfDay(for: end)
        var weekdaySeconds: TimeInterval = 0
        var weekendSeconds: TimeInterval = 0

        while day <= finalDay {
            guard
                let activeStart = calendar.date(
                    bySettingHour: 8,
                    minute: 0,
                    second: 0,
                    of: day
                ),
                let activeEnd = calendar.date(
                    bySettingHour: 20,
                    minute: 0,
                    second: 0,
                    of: day
                )
            else { break }

            let overlapStart = max(start, activeStart)
            let overlapEnd = min(end, activeEnd)
            if overlapEnd > overlapStart {
                let seconds =
                    overlapEnd.timeIntervalSince(overlapStart)
                let weekday = calendar.component(
                    .weekday,
                    from: day
                )
                if weekday == 1 || weekday == 7 {
                    weekendSeconds += seconds
                } else {
                    weekdaySeconds += seconds
                }
            }

            guard let nextDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: day
            ) else { break }
            day = nextDay
        }

        return ReservationBreakdown(
            weekdayHours: weekdaySeconds / 3600,
            weekendHours: weekendSeconds / 3600
        )
    }

}

struct ReservationManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CalculationSettingsKey.reservationFromTimestamp)
    private var fromTimestamp = Date().timeIntervalSince1970
    @AppStorage(CalculationSettingsKey.reservationUntilTimestamp)
    private var untilTimestamp =
        Date().addingTimeInterval(12 * 60 * 60).timeIntervalSince1970
    @AppStorage(CalculationSettingsKey.calculatedBlockMinutes)
    private var actualBlockMinutes = 0

    private var fromBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: fromTimestamp) },
            set: { fromTimestamp = $0.timeIntervalSince1970 }
        )
    }

    private var untilBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: untilTimestamp) },
            set: { untilTimestamp = $0.timeIntervalSince1970 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("RESERVIERUNGSMANAGER")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)
                Spacer()
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            FlybookCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("SCHNELLAUSWAHL")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FlybookColor.muted)

                    HStack(spacing: 18) {
                        quickControls(
                            title: "VON",
                            binding: fromBinding
                        )
                        Divider()
                        quickControls(
                            title: "BIS",
                            binding: untilBinding
                        )
                    }
                }
            }

            FlybookCard {
                MainzReservationView(
                    reservationFrom: fromBinding,
                    reservationUntil: untilBinding,
                    actualBlockMinutes: actualBlockMinutes
                )
            }
        }
        .padding(22)
        .frame(width: 760, height: 570)
        .background(FlybookColor.background)
    }

    private func quickControls(
        title: String,
        binding: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(FlybookColor.navy)

            HStack {
                Button("Heute") {
                    binding.wrappedValue = settingDay(
                        of: binding.wrappedValue,
                        offset: 0
                    )
                }
                Button("Morgen") {
                    binding.wrappedValue = settingDay(
                        of: binding.wrappedValue,
                        offset: 1
                    )
                }
                Button("− Tag") {
                    binding.wrappedValue = adding(
                        .day,
                        value: -1,
                        to: binding.wrappedValue
                    )
                }
                Button("+ Tag") {
                    binding.wrappedValue = adding(
                        .day,
                        value: 1,
                        to: binding.wrappedValue
                    )
                }
            }

            HStack {
                Button("− 60 min") {
                    binding.wrappedValue = adding(
                        .minute,
                        value: -60,
                        to: binding.wrappedValue
                    )
                }
                Button("− 15") {
                    binding.wrappedValue = adding(
                        .minute,
                        value: -15,
                        to: binding.wrappedValue
                    )
                }
                Button("+ 15") {
                    binding.wrappedValue = adding(
                        .minute,
                        value: 15,
                        to: binding.wrappedValue
                    )
                }
                Button("+ 60 min") {
                    binding.wrappedValue = adding(
                        .minute,
                        value: 60,
                        to: binding.wrappedValue
                    )
                }
            }

            HStack(spacing: 5) {
                ForEach([8, 11, 14, 17, 20], id: \.self) { hour in
                    Button(String(format: "%02d:00", hour)) {
                        binding.wrappedValue = settingTime(
                            of: binding.wrappedValue,
                            hour: hour
                        )
                    }
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func adding(
        _ component: Calendar.Component,
        value: Int,
        to date: Date
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DestinationTimeZone.edfz
        return calendar.date(
            byAdding: component,
            value: value,
            to: date
        ) ?? date
    }

    private func settingTime(
        of date: Date,
        hour: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DestinationTimeZone.edfz
        return calendar.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: date
        ) ?? date
    }

    private func settingDay(of date: Date, offset: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DestinationTimeZone.edfz
        let targetDay = calendar.date(
            byAdding: .day,
            value: offset,
            to: calendar.startOfDay(for: Date())
        ) ?? Date()
        let time = calendar.dateComponents(
            [.hour, .minute],
            from: date
        )
        return calendar.date(
            bySettingHour: time.hour ?? 8,
            minute: time.minute ?? 0,
            second: 0,
            of: targetDay
        ) ?? targetDay
    }
}

private enum CalculationGrid {
    static let labelWidth: CGFloat = 80
    static let columnWidth: CGFloat = 89.5
    static let boxHorizontalPadding: CGFloat = 4
    static let inputHorizontalPadding: CGFloat = 2
    static let boxContentWidth: CGFloat =
        columnWidth - 2 * boxHorizontalPadding
    static let inputContentWidth: CGFloat =
        columnWidth - 2 * inputHorizontalPadding
    static let doubleColumnWidth: CGFloat =
        columnWidth * 2 + 6
    static let doubleBoxContentWidth: CGFloat =
        doubleColumnWidth - 2 * boxHorizontalPadding
}

private struct DestinationRefuelCalculationRow: View {
    @Binding var enabled: Bool
    @Binding var selectedFuelRaw: String
    let knownPrice: Double?
    @Binding var manualPrice: Double?
    @Binding var liters: Double
    let unit: FuelDisplayUnit
    let lossEUR: Double?

    private var effectivePrice: Double? { manualPrice ?? knownPrice }
    private var shownQuantity: Double { unit.fromLiters(liters) }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(spacing: 3) {
                Button { enabled.toggle() } label: {
                    Text("TANKEN")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(enabled ? FlybookColor.blue : FlybookColor.navy)
                }
                .buttonStyle(.plain)
                Picker("Kraftstoff", selection: $selectedFuelRaw) {
                    ForEach(AircraftFuelType.allCases) { fuel in
                        Text(fuel.rawValue).tag(fuel.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: CalculationGrid.labelWidth)
                .onChange(of: selectedFuelRaw) { _ in manualPrice = nil }
            }
            .frame(width: CalculationGrid.labelWidth)

            refuelInputBox(
                value: priceBinding,
                format: .number.precision(.fractionLength(2)),
                suffix: "€/L",
                step: 0.01
            )
            refuelInputBox(
                value: quantityBinding,
                format: .number.precision(.fractionLength(unit == .liters ? 0 : 1)),
                suffix: unit.symbol,
                step: unit == .liters ? 1 : 1
            )
            Color.clear
                .frame(
                    width: CalculationGrid.columnWidth,
                    height: 1
                )
            resultBox(lossEUR.map { String(format: "%.2f €", $0) } ?? "?")
        }
        .opacity(enabled ? 1 : 0.45)
        .frame(height: 54, alignment: .top)
    }

    private func refuelInputBox<F: ParseableFormatStyle>(
        value: Binding<Double>,
        format: F,
        suffix: String,
        step: Double
    ) -> some View where F.FormatInput == Double, F.FormatOutput == String {
        HStack(spacing: 2) {
            TextField("", value: value, format: format)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(
                    suffix == "€/L" ? "Tankpreis" : "Tankmenge"
                )
                .help(
                    suffix == "€/L"
                        ? "Tankpreis direkt eingeben"
                        : "Tankmenge direkt eingeben"
                )
            Text(suffix)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
                .frame(width: 20, alignment: .leading)
            Stepper("", value: value, in: 0...10_000, step: step)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 18)
        }
        .foregroundStyle(FlybookColor.navy)
        .frame(
            width: CalculationGrid.inputContentWidth,
            height: 32,
            alignment: .leading
        )
        .padding(.horizontal, CalculationGrid.inputHorizontalPadding)
        .padding(.vertical, CalculationGrid.boxHorizontalPadding)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.08))
        )
        .disabled(!enabled)
    }

    private func resultBox(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 18, weight: .bold, design: .monospaced))
            .foregroundStyle(FlybookColor.navy)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(
                width: CalculationGrid.boxContentWidth,
                height: 30,
                alignment: .trailing
            )
            .padding(CalculationGrid.boxHorizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.08))
            )
    }

    private var priceBinding: Binding<Double> {
        Binding(
            get: { effectivePrice ?? 0 },
            set: { manualPrice = max(0, $0) }
        )
    }

    private var quantityBinding: Binding<Double> {
        Binding(
            get: { shownQuantity },
            set: { liters = max(0, unit.toLiters($0)) }
        )
    }
}

private struct CalculationTotalRow: View {
    let includesReturn: Bool
    let outboundReserveNotConsumed: Bool
    let outboundStopCount: Int
    let returnStopCount: Int
    let outboundDirectNM: Double
    let returnDirectNM: Double
    let outboundTrackMilesNM: Double
    let returnTrackMilesNM: Double
    let outboundHeadwindKnots: Double?
    let returnHeadwindKnots: Double?
    let hourlyRateEUR: Double
    let vatPercent: Double
    let weekdayDiscountEnabled: Bool
    let outboundFlightDate: Date
    let returnFlightDate: Date
    let cruiseGroundSpeedKnots: Double
    let outboundClimbDeparturePressureAltitudeFeet: Double
    let outboundClimbTargetPressureAltitudeFeet: Double
    let returnClimbDeparturePressureAltitudeFeet: Double
    let returnClimbTargetPressureAltitudeFeet: Double
    let climbPerformance: ClimbPerformance
    let cruisePerformance: CruisePerformance
    let outboundFuelConsumptionPerHour: Double
    let returnFuelConsumptionPerHour: Double
    let reserveMinutes: Int
    let usableFuel: Double
    let fuelUnit: FuelDisplayUnit
    let preTakeoffGroundMinutes: Int
    let postLandingGroundMinutes: Int
    let prepaymentDiscount15To29Enabled: Bool
    let prepaymentDiscount30PlusEnabled: Bool
    let minimumRequiredBlockHours: Double
    let outboundLandingFeeQuote: AirportLandingFeeQuote
    let returnLandingFeeQuote: AirportLandingFeeQuote
    let includeLandingFees: Bool
    let refuelLossEUR: Double?
    let startingFuelLiters: Double
    let refuelEnabled: Bool
    let refuelLiters: Double
    let minimumRequiredRefuelLiters: Double
    let estimatedFuelAtTripEnd: Double

    private var outboundMinutes: Int {
        FlightMath.adjustedBlockMinutes(
            directNM: outboundDirectNM,
            stopCount: outboundStopCount,
            headwindKnots: outboundHeadwindKnots,
            cruiseGroundSpeedKnots: cruiseGroundSpeedKnots,
            climbDeparturePressureAltitudeFeet: outboundClimbDeparturePressureAltitudeFeet,
            climbTargetPressureAltitudeFeet: outboundClimbTargetPressureAltitudeFeet,
            climbPerformance: climbPerformance,
            cruisePerformance: cruisePerformance,
            trackMilesNM: outboundTrackMilesNM,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes
        )
    }

    private var returnMinutes: Int {
        FlightMath.adjustedBlockMinutes(
            directNM: returnDirectNM,
            stopCount: returnStopCount,
            headwindKnots: returnHeadwindKnots,
            cruiseGroundSpeedKnots: cruiseGroundSpeedKnots,
            climbDeparturePressureAltitudeFeet: returnClimbDeparturePressureAltitudeFeet,
            climbTargetPressureAltitudeFeet: returnClimbTargetPressureAltitudeFeet,
            climbPerformance: climbPerformance,
            cruisePerformance: cruisePerformance,
            trackMilesNM: returnTrackMilesNM,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes
        )
    }

    private var totalMinutes: Int {
        outboundMinutes + (includesReturn ? returnMinutes : 0)
    }

    private var commercialTotalHours: Double {
        CharterMath.commercialTotalDecimalHours(
            legMinutes: includesReturn
                ? [outboundMinutes, returnMinutes]
                : [outboundMinutes]
        )
    }

    private func weekday(_ date: Date) -> Bool {
        (2...6).contains(
            Calendar.current.component(.weekday, from: date)
        )
    }

    private func legCost(minutes: Int, date: Date) -> Double {
        let prepaymentFactor: Double

        if prepaymentDiscount15To29Enabled {
            prepaymentFactor = 0.75
        } else if prepaymentDiscount30PlusEnabled {
            prepaymentFactor = 0.85
        } else {
            prepaymentFactor = 1.0
        }

        let baseRate =
            hourlyRateEUR * prepaymentFactor

        let rate =
            weekdayDiscountEnabled && weekday(date)
                ? baseRate * 0.95
                : baseRate
        return CharterMath.commercialCost(minutes: minutes, hourlyRateEUR: rate)
            * (1.0 + max(0, vatPercent) / 100.0)
    }

    private var totalRequiredFuel: Double {
        let blockFuel = Double(outboundMinutes)
            * outboundFuelConsumptionPerHour / 60
            + (includesReturn
                ? Double(returnMinutes) * returnFuelConsumptionPerHour / 60
                : 0)
        let reserveFuel = CharterMath.requiredReserveLiters(
            outboundConsumptionPerHour: outboundFuelConsumptionPerHour,
            returnConsumptionPerHour:
                includesReturn ? returnFuelConsumptionPerHour : nil,
            reserveMinutes: reserveMinutes,
            outboundReserveIsReused:
                includesReturn && outboundReserveNotConsumed
        )
        return blockFuel + reserveFuel
    }

    private var estimatedFuelAtTripEndWithoutRefuel: Double {
        startingFuelLiters
            - Double(outboundMinutes)
                * outboundFuelConsumptionPerHour / 60
            - (includesReturn
                ? Double(returnMinutes)
                    * returnFuelConsumptionPerHour / 60
                : 0)
    }

    private var totalCharterCost: Double {
        legCost(minutes: outboundMinutes, date: outboundFlightDate)
        + (
            includesReturn
                ? legCost(minutes: returnMinutes, date: returnFlightDate)
                : 0
        ) + (refuelLossEUR ?? 0)
    }

    private var includedLandingFeesEUR: Double {
        outboundLandingFeeQuote.knownTotalEUR
            + (includesReturn ? returnLandingFeeQuote.knownTotalEUR : 0)
    }

    private var hasUnknownLandingFees: Bool {
        outboundLandingFeeQuote.hasUnknownFees
            || (includesReturn && returnLandingFeeQuote.hasUnknownFees)
    }

    private var combinedTotalCost: Double {
        CharterMath.combinedTotalCost(
            charterCostEUR: totalCharterCost,
            landingFeesEUR: includedLandingFeesEUR,
            includeLandingFees: includeLandingFees
        )
    }

    private var showsUnknownLandingFeeWarning: Bool {
        includeLandingFees && hasUnknownLandingFees
    }

    private var combinedTotalDetail: String {
        guard includeLandingFees else { return "Nur Charter" }
        return hasUnknownLandingFees
            ? "? Gebühr nicht enthalten"
            : "Charter + Landegebühren"
    }

    private var totalFuelColor: Color {
        switch CharterMath.fuelStatus(
            totalRequiredFuelLiters: totalRequiredFuel,
            usableFuelLiters: usableFuel,
            startingFuelLiters: startingFuelLiters,
            estimatedFuelAtTripEndWithoutRefuelLiters:
                estimatedFuelAtTripEndWithoutRefuel,
            refuelEnabled: refuelEnabled,
            refuelLiters: refuelLiters,
            minimumRequiredRefuelLiters: minimumRequiredRefuelLiters,
            estimatedFuelAtTripEndLiters: estimatedFuelAtTripEnd
        ) {
        case .standard: return FlybookColor.navy
        case .sufficient: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("GESAMT")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(FlybookColor.navy)
                .frame(
                    width: CalculationGrid.labelWidth,
                    alignment: .leading
                )

            totalBox(
                value: decimalHours(commercialTotalHours),
                valueColor:
                    commercialTotalHours
                        < minimumRequiredBlockHours
                    ? .red
                    : FlybookColor.navy
            )

            totalBox(
                value:
                    "\(Int(ceil(fuelUnit.fromLiters(totalRequiredFuel)))) "
                    + fuelUnit.symbol,
                valueColor: totalFuelColor
            )

            totalBox(
                value: combinedTotalCost
                    .rounded(.toNearestOrAwayFromZero)
                    .formatted(
                    .currency(code: "EUR")
                        .locale(Locale(identifier: "de_DE"))
                        .precision(.fractionLength(0))
                ),
                detail: combinedTotalDetail,
                width: CalculationGrid.doubleBoxContentWidth,
                alignment: .trailing
            )
        }
    }

    private func decimalHours(_ minutes: Int) -> String {
        let commerciallyRounded = CharterMath.commercialDecimalHours(minutes: minutes)
        return decimalHours(commerciallyRounded)
    }

    private func decimalHours(_ hours: Double) -> String {
        let commerciallyRounded =
            (max(0, hours) * 10).rounded(.toNearestOrAwayFromZero) / 10
        return commerciallyRounded.formatted(
            .number
                .locale(Locale(identifier: "en_US_POSIX"))
                .precision(.fractionLength(1))
        ) + " h"
    }

    private func totalBox(
        value: String,
        valueColor: Color = FlybookColor.navy,
        detail: String? = nil,
        width: CGFloat = CalculationGrid.boxContentWidth,
        alignment: Alignment = .leading
    ) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(
                    .system(
                        size: 20,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: alignment)
            if let detail {
                Text(detail)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(
                        showsUnknownLandingFeeWarning
                            ? Color.orange
                            : FlybookColor.muted
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: alignment)
            }
        }
        .frame(width: width, alignment: alignment)
        .padding(CalculationGrid.boxHorizontalPadding)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(FlybookColor.blue.opacity(0.12))
        )
    }
}

private struct CalculationRow: View {
    let title: String
    let stopCount: Int
    let directNM: Double
    let trackMilesNM: Double
    let headwindKnots: Double?
    let tankStopMinutes: Int
    let hourlyRateEUR: Double
    let vatPercent: Double
    let weekdayDiscountEnabled: Bool
    let flightDate: Date
    let cruiseGroundSpeedKnots: Double
    let climbDeparturePressureAltitudeFeet: Double
    let climbTargetPressureAltitudeFeet: Double
    let climbPerformance: ClimbPerformance
    let cruisePerformance: CruisePerformance
    let fuelConsumptionPerHour: Double
    let reserveMinutes: Int
    let usableFuel: Double
    let fuelUnit: FuelDisplayUnit
    let preTakeoffGroundMinutes: Int
    let postLandingGroundMinutes: Int
    let prepaymentDiscount15To29Enabled: Bool
    let prepaymentDiscount30PlusEnabled: Bool
    let landingFeeQuote: AirportLandingFeeQuote
    let showsLandingFee: Bool
    var reserveNotConsumed = false
    var reserveToggle: Binding<Bool>? = nil

    private var blockMinutes: Int {
        FlightMath.adjustedBlockMinutes(
            directNM: directNM,
            stopCount: stopCount,
            headwindKnots: headwindKnots,
            cruiseGroundSpeedKnots:
                cruiseGroundSpeedKnots,
            climbDeparturePressureAltitudeFeet: climbDeparturePressureAltitudeFeet,
            climbTargetPressureAltitudeFeet: climbTargetPressureAltitudeFeet,
            climbPerformance: climbPerformance,
            cruisePerformance: cruisePerformance,
            trackMilesNM: trackMilesNM,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes
        )
    }

    private var isWeekday: Bool {
        let weekday = Calendar.current.component(
            .weekday,
            from: flightDate
        )
        return (2...6).contains(weekday)
    }

    private var discountApplies: Bool {
        weekdayDiscountEnabled && isWeekday
    }

    private var prepaymentFactor: Double {
        if prepaymentDiscount15To29Enabled {
            return 0.75
        }

        if prepaymentDiscount30PlusEnabled {
            return 0.85
        }

        return 1.0
    }

    private var netHourlyRateEUR: Double {
        let afterPrepayment =
            hourlyRateEUR * prepaymentFactor

        return discountApplies
            ? afterPrepayment * 0.95
            : afterPrepayment
    }

    private var costBeforeVATEUR: Double {
        CharterMath.commercialCost(
            minutes: blockMinutes,
            hourlyRateEUR: netHourlyRateEUR
        )
    }

    private var costEUR: Double {
        costBeforeVATEUR
            * (1.0 + max(0, vatPercent) / 100.0)
    }

    private var stopLabel: String {
        switch stopCount {
        case 0:
            return "Nonstop"
        case 1:
            return "1 Stopp"
        default:
            return "2 Stopps"
        }
    }

    private var blockTimeText: String {
        let commerciallyRounded = CharterMath.commercialDecimalHours(minutes: blockMinutes)
        return commerciallyRounded.formatted(
            .number
                .locale(Locale(identifier: "en_US_POSIX"))
                .precision(.fractionLength(1))
        ) + " h"
    }

    private var requiredFuel: Double {
        let blockFuel =
            Double(blockMinutes)
            * fuelConsumptionPerHour
            / 60.0

        let reserveFuel =
            fuelConsumptionPerHour
            * Double(reserveMinutes)
            / 60.0

        return blockFuel
            + (reserveNotConsumed ? 0 : reserveFuel)
    }

    private var requiredFuelText: String {
        "\(Int(ceil(fuelUnit.fromLiters(requiredFuel)))) "
            + fuelUnit.symbol
    }

    private var fuelResultColor: Color {
        guard usableFuel > 0 else {
            return requiredFuel > 0
                ? .red
                : .green
        }

        let percentage =
            requiredFuel / usableFuel * 100.0

        if percentage < 90 {
            return .green
        }

        if percentage < 100 {
            return .yellow
        }

        return .red
    }

    private var costText: String {
        costEUR
            .rounded(.toNearestOrAwayFromZero)
            .formatted(
            .currency(code: "EUR")
                .locale(Locale(identifier: "de_DE"))
                .precision(.fractionLength(0))
        )
    }

    private var landingFeeText: String {
        AirportLandingFeeDisplay.text(
            for: landingFeeQuote,
            isEnabled: showsLandingFee
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)
                        .lineLimit(1)
                        .allowsTightening(true)

                    Text(stopLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FlybookColor.muted)
                }
                .frame(
                    width: CalculationGrid.labelWidth,
                    alignment: .leading
                )

                valueBox(value: blockTimeText)

                valueBox(
                    value: requiredFuelText,
                    valueColor: fuelResultColor
                )

                valueBox(
                    value: landingFeeText,
                    valueColor: showsLandingFee
                        && landingFeeQuote.hasUnknownFees
                        ? Color.orange
                        : FlybookColor.navy,
                    alignment: .trailing
                )

                VStack(alignment: .trailing, spacing: 3) {
                    valueBox(value: costText, alignment: .trailing)

                    if prepaymentDiscount15To29Enabled {
                        discountText("25 % Vorauszahlungsrabatt")
                    } else if prepaymentDiscount30PlusEnabled {
                        discountText("15 % Vorauszahlungsrabatt")
                    }

                    if discountApplies {
                        discountText("5 % Wochentagsrabatt")
                    }
                }
                .frame(
                    width: CalculationGrid.columnWidth,
                    alignment: .topTrailing
                )
            }

            if let reserveToggle {
                Toggle(
                    "Hinflugreserve nicht verbraucht",
                    isOn: reserveToggle
                )
                .toggleStyle(.checkbox)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FlybookColor.navy)
                .padding(.leading, CalculationGrid.labelWidth + 6)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func discountText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.green)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func valueBox(
        value: String,
        valueColor: Color = FlybookColor.navy,
        alignment: Alignment = .leading
    ) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(
                    .system(
                        size: 20,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
        .frame(
            width: CalculationGrid.boxContentWidth,
            alignment: alignment
        )
        .padding(CalculationGrid.boxHorizontalPadding)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.08))
        )
    }
}

private struct CalculationColumnHeaders: View {
    var body: some View {
        HStack(spacing: 6) {
            Color.clear
                .frame(width: CalculationGrid.labelWidth, height: 1)

            header("BLOCKZEIT")
            header("KRAFTSTOFF")
            header("LANDEGEBÜHREN", alignment: .trailing)
            header("CHARTER", alignment: .trailing)
        }
    }

    private func header(
        _ title: String,
        alignment: Alignment = .leading
    ) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(FlybookColor.navy)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(
                width: CalculationGrid.columnWidth,
                alignment: alignment
            )
    }
}

private struct WindInfluenceLabel: View {
    let headwindKnots: Double

    private var isHeadwind: Bool {
        headwindKnots >= 0
    }

    private var label: String {
        let value = Int(abs(headwindKnots).rounded())
        return isHeadwind
            ? "Gegenwind \(value) kt"
            : "Rückenwind \(value) kt"
    }

    var body: some View {
        Text(label)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(
                isHeadwind ? Color.red : Color.green
            )
            .lineLimit(1)
            .minimumScaleFactor(0.9)
    }
}

private struct TravelDurationBadge: View {
    let minutes: Int
    let blockMinutes: Int
    let legMinutes: [Int]
    let stopCount: Int
    let pauseMinutesPerStop: Int
    @State private var showsBreakdown = false

    var body: some View {
        Button {
            showsBreakdown.toggle()
        } label: {
            VStack(spacing: 0) {
                Text(FlightMath.duration(minutes))
                    .font(
                        .system(
                            size: 22,
                            weight: .bold,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(FlybookColor.blue)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 7)
            .background(FlybookColor.blue.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(FlybookColor.blue.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("Klicken für Blockzeiten, Fluglegs und Pausen")
        .popover(isPresented: $showsBreakdown) {
            VStack(alignment: .leading, spacing: 12) {
                Label("ZEITAUFTEILUNG", systemImage: "clock.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)
                Divider()
                breakdownRow("Gesamtreisezeit", minutes: minutes, emphasized: true)
                breakdownRow("Gesamtblockzeit", minutes: blockMinutes, emphasized: true)
                Divider()
                ForEach(Array(legMinutes.enumerated()), id: \.offset) { index, value in
                    breakdownRow("\(index + 1). Leg", minutes: value)
                }
                Divider()
                HStack {
                    Text("Pause")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(pauseLabel)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(stopCount > 0 ? FlybookColor.blue : FlybookColor.muted)
                }
            }
            .padding(18)
            .frame(width: 280)
        }
    }

    private var pauseLabel: String {
        guard stopCount > 0 else { return "keine" }
        return "\(stopCount) × \(max(0, pauseMinutesPerStop)) min"
    }

    private func breakdownRow(
        _ title: String,
        minutes: Int,
        emphasized: Bool = false
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: emphasized ? .bold : .semibold))
            Spacer()
            Text(FlightMath.duration(minutes))
                .font(.system(size: emphasized ? 15 : 13, weight: .bold, design: .monospaced))
                .foregroundStyle(emphasized ? FlybookColor.blue : FlybookColor.navy)
        }
    }
}

private struct StopCountSelector: View {
    @Binding var selection: Int

    private let options: [(value: Int, label: String)] = [
        (0, "NONSTOP"),
        (1, "1 STOP"),
        (2, "2 STOPS")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(
                                selection == option.value
                                    ? FlybookColor.blue
                                    : Color.white
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        FlybookColor.navy,
                                        lineWidth: 1.5
                                    )
                            )
                            .frame(width: 16, height: 16)

                        Text(option.label)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(FlybookColor.navy)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .frame(height: 28)
                }
                .buttonStyle(.plain)
            }
        }
    }
}


private struct FlightTimeBox: View {
    let value: String
    let symbol: String
    let lightCondition: LightCondition
    var editable = false

    @AppStorage(UnitSystemSettingsKey.displaySystem)
    private var displayUnitSystemRaw = DisplayUnitSystem.eu.rawValue

    private var displayedValue: String {
        TimeInput.displayClock(
            value,
            usesTwelveHourFormat:
                DisplayUnitSystem(rawValue: displayUnitSystemRaw) == .us
        )
    }

    private var fillColor: Color {
        switch lightCondition {
        case .daylight, .unavailable:
            return Color.white
        case .civilTwilight:
            return Color.yellow.opacity(0.34)
        case .night:
            return Color.red.opacity(0.28)
        }
    }

    private var borderColor: Color {
        switch lightCondition {
        case .daylight:
            return FlybookColor.navy
        case .civilTwilight:
            return Color.orange
        case .night:
            return Color.red
        case .unavailable:
            return FlybookColor.muted
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))

            Text(displayedValue)
                .font(
                    .system(
                        size: 22,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .frame(width: 96)
                .minimumScaleFactor(0.72)
                .lineLimit(1)

            if editable {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
                    .frame(width: 10)
            } else {
                Color.clear.frame(width: 10, height: 1)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(fillColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(FlybookColor.navy)
    }
}

private struct EditableFlightTimeField: View {
    let title: String
    @Binding var text: String
    let symbol: String
    let lightCondition: LightCondition

    @State private var isTimeEditorPresented = false
    @State private var selectedHour = 9
    @State private var selectedMinute = 30

    private var currentMinutes: Int {
        TimeInput.minutes(from: text) ?? 570
    }

    private func openTimeEditor() {
        let minutes = currentMinutes
        selectedHour = (minutes / 60) % 24
        selectedMinute = minutes % 60
        isTimeEditorPresented = true
    }

    private func applyTime() {
        text = String(
            format: "%02d:%02d",
            selectedHour,
            selectedMinute
        )
        isTimeEditorPresented = false
    }

    var body: some View {
        VStack(spacing: 4) {
            Button(action: openTimeEditor) {
                FlightTimeBox(
                    value: text,
                    symbol: symbol,
                    lightCondition: lightCondition,
                    editable: true
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 174, height: 43)
            .help("Uhrzeit auswählen")
            .popover(
                isPresented: $isTimeEditorPresented,
                arrowEdge: .bottom
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)

                    HStack(spacing: 8) {
                        Picker("Stunde", selection: $selectedHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(String(format: "%02d", hour))
                                    .tag(hour)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 82)

                        Text(":")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(FlybookColor.navy)

                        Picker("Minute", selection: $selectedMinute) {
                            ForEach(0..<60, id: \.self) { minute in
                                Text(String(format: "%02d", minute))
                                    .tag(minute)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 82)
                    }

                    HStack {
                        Button("Abbrechen") {
                            isTimeEditorPresented = false
                        }

                        Spacer()

                        Button("Übernehmen") {
                            applyTime()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(16)
                .frame(width: 230)
            }

        }
        .foregroundStyle(FlybookColor.navy)
    }
}


private enum AviationWindText {
    static func format(
        direction: Double?,
        speed: Double?,
        gust: Double?
    ) -> String {
        guard let direction, let speed else {
            return "--- / --"
        }
        var roundedDirection =
            (Int((direction / 10).rounded()) * 10) % 360
        if roundedDirection == 0 && direction > 0 {
            roundedDirection = 360
        }
        let roundedSpeed = max(0, Int(speed.rounded()))
        let roundedGust = max(0, Int((gust ?? 0).rounded()))
        let steadyWind = String(
            format: "%03d / %02d",
            roundedDirection,
            roundedSpeed
        )
        guard let gust, gust - speed >= 10 else {
            return steadyWind
        }
        return steadyWind + String(format: " G%02d", roundedGust)
    }
}

private struct EDFZRunwayPressureRow: View {
    let sample: EDFZWeatherSample?
    let showsRunway: Bool

    private var runway: String {
        guard let direction = sample?.windDirectionDegrees,
              let speed = sample?.windSpeedKnots,
              speed >= 0.5
        else { return "—" }
        return EDFZRunway.activeRunway(
            windFromDegrees: direction,
            speedKnots: speed
        )
    }

    private var wind: String {
        AviationWindText.format(
            direction: sample?.windDirectionDegrees,
            speed: sample?.windSpeedKnots,
            gust: sample?.windGustKnots
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            if showsRunway {
                HStack(spacing: 4) {
                    Image(systemName: "road.lanes")
                    Text(runway)
                }
                .font(.system(size: 16, weight: .bold))
            }

            Label(wind, systemImage: "wind")
                .font(
                    .system(
                        size: 16,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .lineLimit(1)
        }
        .foregroundStyle(FlybookColor.navy)
        .frame(width: 174, height: 24, alignment: .center)
        .help("Wind: Richtung, Stärke und Böen in Knoten")
    }
}

private struct CalculatedFlightTime: View {
    let value: String
    let symbol: String
    let lightCondition: LightCondition

    var body: some View {
        VStack(spacing: 4) {
            FlightTimeBox(
                value: value,
                symbol: symbol,
                lightCondition: lightCondition
            )
            .frame(width: 174, height: 43)

        }
        .foregroundStyle(FlybookColor.navy)
    }
}

private struct RunwayRecommendationButton: View {
    let runway: String?
    let warning: RunwayCrosswindWarning
    let windComponents: RunwayWindComponents?
    let windDirection: Double?
    @State private var showsComponents = false

    var body: some View {
        Button {
            guard windComponents != nil else { return }
            showsComponents.toggle()
        } label: {
            Label(runway ?? " ", systemImage: "road.lanes")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(FlybookColor.navy)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(FlybookColor.navy.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(runway == nil ? 0 : 1)
        .help(
            windComponents == nil
                ? "Bevorzugte Piste nach Windrichtung"
                : "Klicken, um die Windkomponenten anzuzeigen"
        )
        .popover(isPresented: $showsComponents, arrowEdge: .bottom) {
            if let windComponents {
                VStack(alignment: .leading, spacing: 10) {
                    Text("PISTE \(runway ?? "—")")
                        .font(.system(size: 15, weight: .bold))
                    RunwayWindGeometryView(
                        runway: runway,
                        windDirection: windDirection,
                        activeRunway: runway
                    )
                    component(
                        symbol: windComponents.headwindKnots >= 0
                            ? "arrow.down" : "arrow.up",
                        title: windComponents.headwindKnots >= 0
                            ? "Gegenwind" : "Rückenwind",
                        value: abs(windComponents.headwindKnots),
                        color: windComponents.headwindKnots >= 0
                            ? .green : .red
                    )
                    component(
                        symbol: windComponents.crosswindComesFromRight
                            ? "arrow.left" : "arrow.right",
                        title: windComponents.crosswindComesFromRight
                            ? "Seitenwind von rechts"
                            : "Seitenwind von links",
                        value: windComponents.crosswindKnots,
                        gustValue: windComponents.gustCrosswindKnots,
                        color: .orange
                    )
                }
                .foregroundStyle(FlybookColor.navy)
                .padding(16)
                .frame(minWidth: 230)
            }
        }
    }

    private var backgroundColor: Color {
        EDFZRunway.crosswindWarning(for: windComponents)
            .recommendationBackgroundColor
    }

    private func component(
        symbol: String,
        title: String,
        value: Double,
        gustValue: Double? = nil,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 18)
            Text(title)
            Spacer()
            Text(componentValue(value, gustValue: gustValue))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(color)
    }

    private func componentValue(
        _ value: Double,
        gustValue: Double?
    ) -> String {
        guard let gustValue else {
            return String(format: "%.0f kt", value)
        }
        return String(format: "%.0f G%.0f kt", value, gustValue)
    }
}

private struct FlightLocationHeader: View {
    let title: String
    let runway: String?
    let crosswindWarning: RunwayCrosswindWarning
    let windComponents: RunwayWindComponents?
    let windDirection: Double?

    @State private var showsWindComponents = false

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(FlybookColor.navy)
                .lineLimit(1)

            Button {
                guard windComponents != nil else { return }
                showsWindComponents.toggle()
            } label: {
                Label(runway ?? " ", systemImage: "road.lanes")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(FlybookColor.navy)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(crosswindBackgroundColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(FlybookColor.navy.opacity(0.35), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .opacity(runway == nil ? 0 : 1)
            .frame(height: 28)
            .help(windComponents == nil ? crosswindHelp : crosswindHelp + " – klicken für Windkomponenten")
            .popover(isPresented: $showsWindComponents, arrowEdge: .bottom) {
                runwayWindComponentPopover
            }
        }
        .frame(width: 174)
    }

    @ViewBuilder
    private var runwayWindComponentPopover: some View {
        if let windComponents {
            VStack(alignment: .leading, spacing: 10) {
                Text("PISTE \(runway ?? "—")")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)

                RunwayWindGeometryView(
                    runway: runway,
                    windDirection: windDirection,
                    activeRunway: runway
                )

                componentRow(
                    symbol: windComponents.headwindKnots >= 0
                        ? "arrow.down" : "arrow.up",
                    title: windComponents.headwindKnots >= 0
                        ? "Gegenwind" : "Rückenwind",
                    knots: abs(windComponents.headwindKnots),
                    color: windComponents.headwindKnots >= 0
                        ? .green : .red
                )
                componentRow(
                    symbol: windComponents.crosswindComesFromRight
                        ? "arrow.left" : "arrow.right",
                    title: windComponents.crosswindComesFromRight
                        ? "Seitenwind von rechts" : "Seitenwind von links",
                    knots: windComponents.crosswindKnots,
                    gustKnots: windComponents.gustCrosswindKnots,
                    color: .orange
                )
            }
            .padding(14)
            .frame(minWidth: 220, alignment: .leading)
        }
    }

    private func componentRow(
        symbol: String,
        title: String,
        knots: Double,
        gustKnots: Double? = nil,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 16)
            Text(title)
            Spacer(minLength: 10)
            Text(componentValue(knots, gustKnots: gustKnots))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(color)
    }

    private func componentValue(
        _ knots: Double,
        gustKnots: Double?
    ) -> String {
        guard let gustKnots else {
            return String(format: "%.0f kt", knots)
        }
        return String(format: "%.0f G%.0f kt", knots, gustKnots)
    }

    private var crosswindBackgroundColor: Color {
        EDFZRunway.crosswindWarning(for: windComponents)
            .recommendationBackgroundColor
    }

    private var crosswindHelp: String {
        switch crosswindWarning {
        case .none:
            return "Pistenempfehlung nach Windrichtung"
        case .yellow:
            return "Erhöhte Querwindkomponente"
        case .red:
            return "Hohe Querwindkomponente"
        }
    }
}

struct RunwayWindGeometryView: View {
    let runway: String?
    let windDirection: Double?
    let activeRunway: String?
    var emphasizesActiveRunway = false

    private var runwayEnds: [String] {
        runway?.split(separator: "/").map(String.init) ?? []
    }

    private var runwayHeading: Double {
        let firstEnd = runway?
            .split(separator: "/")
            .first
            .map(String.init) ?? ""
        let digits = firstEnd.prefix { $0.isNumber }
        guard let number = Double(digits), number > 0 else { return 0 }
        return number == 36 ? 0 : number * 10
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(FlybookColor.blue.opacity(0.06))
                .overlay(
                    Circle().stroke(FlybookColor.line, lineWidth: 1)
                )

            Text("N")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(7)

            ZStack {
                Capsule()
                    .fill(FlybookColor.navy.opacity(0.78))
                    .frame(width: 9, height: 82)
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 1.5, height: 64)
            }
            .rotationEffect(.degrees(runwayHeading))

            if let windDirection {
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: 3, height: 66)
                        .offset(y: 8)
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.orange)
                }
                .frame(width: 20, height: 82)
                // Der Pfeil zeigt die Strömungsrichtung; sein Schaft kommt
                // damit geografisch aus der gemeldeten Windrichtung.
                .rotationEffect(.degrees(windDirection + 180))
            }

            runwayEndLabels
        }
        .frame(width: 128, height: 112)
        .frame(maxWidth: .infinity)
        .help("Nordorientierte Pistendarstellung mit geografischer Windströmung")
    }

    private var runwayEndLabels: some View {
        GeometryReader { geometry in
            let radians = runwayHeading * .pi / 180
            let radius = 49.0
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height / 2

            if let first = runwayEnds.first {
                runwayLabel(first, isActive: isActive(first))
                    .position(
                        x: centerX - sin(radians) * radius,
                        y: centerY + cos(radians) * radius
                    )
            }
            if runwayEnds.count > 1 {
                runwayLabel(
                    runwayEnds[1],
                    isActive: isActive(runwayEnds[1])
                )
                    .position(
                        x: centerX + sin(radians) * radius,
                        y: centerY - cos(radians) * radius
                    )
            }
        }
    }

    private func isActive(_ value: String) -> Bool {
        guard let activeRunway else { return false }
        return activeRunway.uppercased() == value.uppercased()
    }

    private func runwayLabel(
        _ value: String,
        isActive: Bool
    ) -> some View {
        Text(value)
            .font(
                .system(
                    size: emphasizesActiveRunway
                        ? (isActive ? 15 : 9)
                        : 11,
                    weight: .black,
                    design: .monospaced
                )
            )
            .foregroundStyle(isActive ? Color.white : FlybookColor.navy)
            .padding(.horizontal, isActive && emphasizesActiveRunway ? 6 : 4)
            .padding(.vertical, isActive && emphasizesActiveRunway ? 3 : 2)
            .background(
                Capsule().fill(
                    isActive
                        ? FlybookColor.blue
                        : Color.white.opacity(0.94)
                )
            )
            .overlay(
                Capsule().stroke(
                    isActive
                        ? FlybookColor.navy.opacity(0.45)
                        : Color.clear,
                    lineWidth: 1
                )
            )
    }
}

private struct WeatherPlaceholderColumn: View {
    let title: String

    var body: some View {
        VStack(spacing: 13) {
            Text(title)
                .font(.headline)
                .foregroundStyle(FlybookColor.navy)

            Text("12:00 LCL")
                .font(.caption)
                .foregroundStyle(FlybookColor.muted)

            Text("Wetterdaten werden\nbeim Abruf geladen")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FlybookColor.muted)
                .multilineTextAlignment(.center)
                .frame(height: 60)

            HStack {
                VStack {
                    Text("BODEN")
                    Image(systemName: "wind")
                    Text("N/A")
                }

                Spacer()

                VStack {
                    Text("5.000 FT AGL")
                    Image(systemName: "wind")
                    Text("N/A")
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(FlybookColor.navy)

            Text("Sunrise —  ·  Sunset —")
                .font(.caption)
                .foregroundStyle(FlybookColor.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
    }
}

private struct AirportMetric: View {
    let title: String
    let value: String
    var secondaryValue: String? = nil
    var fuelStatus = false
    var pricePerLiterEUR: Double? = nil
    var referencePricePerLiterEUR: Double? = nil
    var priceReportedAt: String? = nil
    private var normalizedAvailability: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var displayedValue: String {
        guard fuelStatus else { return value }
        if let pricePerLiterEUR {
            let price = pricePerLiterEUR.formatted(
            .currency(code: "EUR")
                .locale(Locale(identifier: "de_DE"))
                .precision(.fractionLength(2))
            ) + "/L"
            return price
        }
        if ["ja", "yes", "verfügbar", "vorhanden"].contains(normalizedAvailability) {
            return "Ja"
        }
        if ["nein", "no", "nicht vorhanden", "keine"].contains(normalizedAvailability) {
            return "Nein"
        }
        return "?"
    }

    private var fuelPriceDifference: String? {
        guard fuelStatus,
              let pricePerLiterEUR,
              let referencePricePerLiterEUR
        else { return nil }
        let cents = Int(
            ((pricePerLiterEUR - referencePricePerLiterEUR) * 100).rounded()
        )
        if cents == 0 { return "±0 ct" }
        return cents > 0 ? "+\(cents) ct" : "\(cents) ct"
    }

    private var valueFontSize: CGFloat {
        title == "Piste" || title == "LDA" ? 16 : 18
    }

    private var displayedColor: Color {
        guard fuelStatus else { return FlybookColor.navy }
        if let pricePerLiterEUR {
            guard let referencePricePerLiterEUR else {
                return FlybookColor.navy
            }
            if abs(pricePerLiterEUR - referencePricePerLiterEUR) < 0.005 {
                return FlybookColor.blue
            }
            return pricePerLiterEUR > referencePricePerLiterEUR
                ? .red
                : .green
        }
        if displayedValue == "Ja" { return .green }
        if displayedValue == "Nein" { return .red }
        return FlybookColor.muted
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 17, weight: .bold))

            Text(displayedValue)
                .font(.system(size: valueFontSize, weight: .bold))
                .foregroundStyle(displayedColor)
                .multilineTextAlignment(.center)
                .lineLimit(fuelStatus ? 1 : 2)
                .minimumScaleFactor(0.72)

            Text(fuelPriceDifference ?? " ")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(displayedColor)
                .lineLimit(1)
                .frame(height: 14)

            if let secondaryValue, !secondaryValue.isEmpty {
                RunwayOrientationView(
                    value: secondaryValue
                )
                .frame(height: 20)
            } else if fuelStatus,
                      pricePerLiterEUR != nil,
                      let priceReportedAt,
                      !priceReportedAt.isEmpty {
                Text(priceReportedAt)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FlybookColor.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 20)
            } else {
                Color.clear.frame(height: 20)
            }
        }
        .foregroundStyle(FlybookColor.navy)
        .frame(maxWidth: .infinity, minHeight: 82, maxHeight: 82, alignment: .top)
    }
}

private struct RunwayOrientationView: View {
    let value: String

    private var ends: (String, String) {
        let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
        return (parts.first ?? value, parts.count > 1 ? parts[1] : "")
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(ends.0)
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(FlybookColor.navy.opacity(0.86))
                    .frame(width: 28, height: 8)
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 12, height: 1)
            }
            .accessibilityHidden(true)
            Text(ends.1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(FlybookColor.blue)
        .lineLimit(1)
        .minimumScaleFactor(0.68)
    }
}

private struct WeekendRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: "circle")
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            Text(value)
        }
        .foregroundStyle(FlybookColor.navy)
    }
}

private struct LiveWeatherColumn: View {
    let title: String
    let day: ForecastDay
    let airportElevationFeet: Double

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))

                    Text(displayDate)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FlybookColor.navy)

                    Text(day.localTime)
                        .font(.system(size: 12))
                        .foregroundStyle(FlybookColor.muted)
                }

                Spacer()

                FlightCategoryBadge(day: day)
            }

            weatherSummary

            Divider()
                .overlay(FlybookColor.line.opacity(0.85))

            windSummary

            densityAltitudeSummary

        }
        .foregroundStyle(FlybookColor.navy)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
    }

    private var weatherSummary: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(
                day.temperatureCelsius.map {
                    String(format: "%.0f°", $0)
                } ?? "—"
            )
            .font(.system(size: 27, weight: .bold))

            Image(systemName: weatherSymbol(day.weatherCode))
                .font(.system(size: 28, weight: .medium))
                .symbolRenderingMode(.multicolor)
                .frame(width: 38)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(weatherDescription(day.weatherCode))
                    .font(.system(size: 13, weight: .semibold))

            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.gray.opacity(0.10))
        )
    }

    private var windSummary: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(classicWindText)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(FlybookColor.navy)

            WindBarbShape(
                directionDegrees:
                    day.surfaceWind.directionDegrees ?? 0,
                speedKnots:
                    day.surfaceWind.speedKnots ?? 0
            )
            .stroke(
                day.surfaceWind.speedKnots == nil
                    ? FlybookColor.muted
                    : FlybookColor.navy,
                style: StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(width: 52, height: 52)
            .overlay(
                Circle()
                    .stroke(FlybookColor.line, lineWidth: 1.5)
            )
        }
    }

    private var classicWindText: String {
        AviationWindText.format(
            direction: day.surfaceWind.directionDegrees,
            speed: day.surfaceWind.speedKnots,
            gust: day.windGustKnots
        )
    }

    private var densityAltitudeSummary: some View {
        HStack {
            Text("DENSITY ALTITUDE")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(FlybookColor.muted)

            Spacer()

            Text(densityAltitudeText)
                .font(
                    .system(
                        size: 13,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .foregroundStyle(FlybookColor.navy)
        }
        .padding(.horizontal, 10)
    }

    private var densityAltitudeText: String {
        guard
            let temperature = day.temperatureCelsius,
            let pressure = day.pressureMSLHPA
        else {
            return "—"
        }

        let pressureAltitude =
            airportElevationFeet
            + (1013.25 - pressure) * 30.0

        let isaTemperature =
            15.0 - 1.98 * (pressureAltitude / 1000.0)

        let densityAltitude =
            pressureAltitude
            + 120.0 * (temperature - isaTemperature)
        let roundedDensityAltitude =
            (densityAltitude / 100)
            .rounded(.toNearestOrAwayFromZero) * 100

        return String(
            format: "%.0f ft",
            roundedDensityAltitude
        )
    }

    private var displayDate: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"

        guard let date = parser.date(from: day.localDate) else {
            return day.localDate
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    private func weatherSymbol(_ code: Int?) -> String {
        guard let code else { return "questionmark.circle" }
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67: return "cloud.rain.fill"
        case 71...77: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    private func weatherDescription(_ code: Int?) -> String {
        guard let code else { return "—" }
        switch code {
        case 0: return "Klar"
        case 1, 2: return "Leicht bewölkt"
        case 3: return "Bedeckt"
        case 45, 48: return "Nebel"
        case 51...57: return "Nieselregen"
        case 61...67: return "Regen"
        case 71...77: return "Schnee"
        case 80...82: return "Schauer"
        case 95...99: return "Gewitter"
        default: return "Wetter"
        }
    }
}

private struct FlightCategoryBadge: View {
    let day: ForecastDay

    private var color: Color {
        switch day.category {
        case .vfr: return .green
        case .mvfr: return .blue
        case .ifr: return .red
        case .lifr: return .purple
        case .unavailable: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(day.category.rawValue)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(color))

            if let categoryReason {
                Text(categoryReason)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var categoryReason: String? {
        guard day.category == .mvfr
            || day.category == .ifr
            || day.category == .lifr
        else {
            return nil
        }

        let visibilitySM = day.visibilityMeters.map {
            $0 / 1609.344
        }

        switch day.category {
        case .lifr:
            if let ceiling = day.ceilingFeetAGL, ceiling < 500 {
                return String(format: "Ceiling %.0f ft", ceiling)
            }
            if let visibilitySM, visibilitySM < 1 {
                return String(format: "Sicht %.1f SM", visibilitySM)
            }

        case .ifr:
            if let ceiling = day.ceilingFeetAGL, ceiling < 1000 {
                return String(format: "Ceiling %.0f ft", ceiling)
            }
            if let visibilitySM, visibilitySM < 3 {
                return String(format: "Sicht %.1f SM", visibilitySM)
            }

        case .mvfr:
            if let ceiling = day.ceilingFeetAGL, ceiling <= 3000 {
                return String(format: "Ceiling %.0f ft", ceiling)
            }
            if let visibilitySM, visibilitySM <= 5 {
                return String(format: "Sicht %.1f SM", visibilitySM)
            }

        default:
            break
        }

        return nil
    }
}

private struct WindBarbView: View {
    let title: String
    let wind: WindSample

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))

            WindBarbShape(
                directionDegrees: wind.directionDegrees ?? 0,
                speedKnots: wind.speedKnots ?? 0
            )
            .stroke(
                wind.speedKnots == nil ? FlybookColor.muted : FlybookColor.navy,
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 52, height: 52)
            .overlay(
                Circle()
                    .stroke(FlybookColor.line, lineWidth: 1.5)
            )

            Text(wind.speedKnots.map { String(format: "%.0f kt", $0) } ?? "N/A")
                .font(.system(size: 12, weight: .bold))
        }
    }
}

private struct WindBarbShape: Shape {
    let directionDegrees: Double
    let speedKnots: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tip = CGPoint(x: rect.midX, y: rect.midY)
        let length = min(rect.width, rect.height) * 0.43
        let radians = (directionDegrees - 90.0) * .pi / 180.0
        let tail = CGPoint(
            x: tip.x - cos(radians) * length,
            y: tip.y - sin(radians) * length
        )

        path.move(to: tail)
        path.addLine(to: tip)

        let roundedSpeed = max(0, Int((speedKnots / 5.0).rounded()) * 5)
        var remaining = roundedSpeed
        var position = tail
        let spacing = min(rect.width, rect.height) * 0.11
        let forwards = CGVector(
            dx: cos(radians) * spacing,
            dy: sin(radians) * spacing
        )
        let barbAngle = radians + 60.0 * .pi / 180.0
        let fullBarbLength = min(rect.width, rect.height) * 0.28
        let halfBarbLength = fullBarbLength * 0.58

        while remaining >= 50 {
            let next = CGPoint(
                x: position.x + forwards.dx * 2,
                y: position.y + forwards.dy * 2
            )
            let flag = CGPoint(
                x: position.x + cos(barbAngle) * fullBarbLength,
                y: position.y + sin(barbAngle) * fullBarbLength
            )
            path.move(to: position)
            path.addLine(to: flag)
            path.addLine(to: next)
            remaining -= 50
            position = next
        }

        while remaining >= 10 {
            let end = CGPoint(
                x: position.x + cos(barbAngle) * fullBarbLength,
                y: position.y + sin(barbAngle) * fullBarbLength
            )
            path.move(to: position)
            path.addLine(to: end)
            position = CGPoint(
                x: position.x + forwards.dx,
                y: position.y + forwards.dy
            )
            remaining -= 10
        }

        if remaining >= 5 {
            let end = CGPoint(
                x: position.x + cos(barbAngle) * halfBarbLength,
                y: position.y + sin(barbAngle) * halfBarbLength
            )
            path.move(to: position)
            path.addLine(to: end)
        }

        return path
    }
}

private struct ResourceImage: View {
    let name: String
    let extensionName: String
    let subdirectory: String
    let fallbackText: String

    var body: some View {
        Group {
            if let url = Bundle.module.url(
                forResource: name,
                withExtension: extensionName,
                subdirectory: subdirectory
            ),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                ZStack {
                    Color.gray.opacity(0.12)
                    Text(fallbackText)
                        .foregroundStyle(FlybookColor.muted)
                }
            }
        }
    }
}
