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

struct DestinationPage: View {
    let destination: Destination
    let availableOrigins: [AirportReference]
    @State private var selectedOriginICAO = "EDFZ"
    @State private var isRouteReversed = false
    @StateObject private var weatherModel = WeatherViewModel()
    @StateObject private var outboundRouteWindModel = RouteWindViewModel()
    @StateObject private var returnRouteWindModel = RouteWindViewModel()
    @StateObject private var outboundEDFZWeatherModel = EDFZWeatherViewModel()
    @StateObject private var returnEDFZWeatherModel = EDFZWeatherViewModel()
    @StateObject private var intermediateWeatherModel = EDFZWeatherViewModel()
    @StateObject private var destinationAirportWeatherModel =
        EDFZWeatherViewModel()
    @StateObject private var destinationReturnWeatherModel =
        EDFZWeatherViewModel()
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
    @State private var outboundStartText = "09:30"
    @State private var desiredHomeArrivalText = "17:00"
    @State private var multiStopDepartureText = ""
    @State private var outboundStops = 0
    @State private var returnStops = 0
    @State private var outboundStopsManuallySet = false
    @State private var returnStopsManuallySet = false
    @State private var outboundTrackMilesOverride: Double?
    @State private var returnTrackMilesOverride: Double?
    @State private var outboundFlightAltitudeFeet = 5000
    @State private var returnFlightAltitudeFeet = 5000
    @State private var timeDisplayMode: TimeDisplayMode = .local
    @State private var flightPlanningMode = FlightPlanningMode.roundTrip
    @State private var isOneWay = false
    @State private var outboundReserveNotConsumed = false
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

    @AppStorage(AircraftSettingsKey.selectedAircraft)
    private var selectedAircraftRaw =
        AircraftType.a211.rawValue

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
        availableOrigins.first {
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
            )
        )
    }

    private var planningOrigin: AirportReference {
        isRouteReversed ? destinationReference : selectedOrigin
    }

    private var planningDestination: AirportReference {
        isRouteReversed ? selectedOrigin : destinationReference
    }

    private var planningOriginSelection: Binding<String> {
        Binding(
            get: { planningOrigin.icao },
            set: { newICAO in
                if newICAO.caseInsensitiveCompare(destinationReference.icao)
                    == .orderedSame
                {
                    isRouteReversed = true
                } else {
                    selectedOriginICAO = newICAO
                    isRouteReversed = false
                }
            }
        )
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

    private var intermediateAirport: AirportReference {
        availableOrigins.first {
            $0.icao == intermediateICAO
        } ?? planningDestination
    }

    private var firstLegDestination: AirportReference {
        flightPlanningMode == .multiStop
            ? intermediateAirport
            : planningDestination
    }

    private var secondLegOrigin: AirportReference {
        flightPlanningMode == .multiStop
            ? intermediateAirport
            : planningDestination
    }

    private var secondLegDestination: AirportReference {
        flightPlanningMode == .multiStop
            ? planningDestination
            : planningOrigin
    }

    private var outboundDirectNM: Double {
        AirportDistance.nauticalMiles(
            from: planningOrigin,
            to: firstLegDestination
        )
    }

    private var returnDirectNM: Double {
        AirportDistance.nauticalMiles(
            from: secondLegOrigin,
            to: secondLegDestination
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
        if (180..<360).contains(
            WindMath.normalized(courseDegrees)
        ) {
            return [2500, 3500, 4500, 6500, 8500]
        }
        return [2500, 3500, 5500, 7500, 9500]
    }

    private var selectedAircraft: AircraftType {
        AircraftType(rawValue: selectedAircraftRaw)
            ?? .a211
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

    private var fuelConsumptionPerHour: Double {
        AircraftProfileStore.fuelConsumption(
            for: selectedAircraft
        )
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

    @AppStorage(CalculationSettingsKey.weekdayDiscountEnabled)
    private var weekdayDiscountEnabled =
        CalculationSettings.defaultWeekdayDiscountEnabled

    @AppStorage(CalculationSettingsKey.reserveMinutes)
    private var reserveMinutes =
        CalculationSettings.defaultReserveMinutes

    @AppStorage(
        CalculationSettingsKey.maxTravelMinutesUntilOvernight
    )
    private var maxTravelMinutesUntilOvernight =
        CalculationSettings
            .defaultMaxTravelMinutesUntilOvernight

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
        .id(selectedAircraftRaw)
        .task(id: weatherTaskID) {
            await weatherModel.load(
                destination: destination,
                targetInstants: weatherTargetInstants,
                forceRefresh: true
            )
        }
        .task(id: outboundWindTaskID) {
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
        .task(id: outboundEDFZWeatherTaskID) {
            await outboundEDFZWeatherModel.load(
                plannedDate: outboundFlightDate,
                airport: planningOrigin
            )
        }
        .task(id: returnEDFZWeatherTaskID) {
            await returnEDFZWeatherModel.load(
                plannedDate: returnFlightDate,
                airport: planningOrigin
            )
        }
        .task(id: multiStopWeatherTaskID) {
            await destinationAirportWeatherModel.load(
                plannedDate: outboundFlightDate,
                airport: planningDestination
            )
            await destinationReturnWeatherModel.load(
                plannedDate: returnFlightDate,
                airport: planningDestination
            )
            if flightPlanningMode == .multiStop {
                await intermediateWeatherModel.load(
                    plannedDate: outboundFlightDate,
                    airport: intermediateAirport
                )
            }
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
            resetAutomaticStops()
            normalizeFlightAltitudes()
        }
        .onChange(of: selectedOriginICAO) { _ in
            normalizeFlightAltitudes()
        }
        .onChange(of: isRouteReversed) { _ in
            resetAutomaticStops()
            normalizeFlightAltitudes()
        }
        .onChange(of: flightPlanningMode) { mode in
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
        .onChange(of: totalCalculatedBlockMinutes) { minutes in
            storedCalculatedBlockMinutes = minutes
        }
        .onChange(of: outboundStartInstant) { _ in
            synchronizeReservationWindow()
        }
        .onChange(of: reservationArrivalInstant) { _ in
            synchronizeReservationWindow()
        }
        .onAppear {
            normalizeFlightAltitudes()
            storedCalculatedBlockMinutes = totalCalculatedBlockMinutes
            synchronizeReservationWindow()
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
        options.min {
            abs($0 - current) < abs($1 - current)
        } ?? current
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

    private var outboundEDFZWeatherTaskID: String {
        dateTaskID(prefix: "out-\(planningOrigin.icao)-\(planningDestination.icao)", date: outboundFlightDate)
    }

    private var returnEDFZWeatherTaskID: String {
        dateTaskID(prefix: "ret-\(planningOrigin.icao)-\(planningDestination.icao)", date: returnFlightDate)
    }

    private var multiStopWeatherTaskID: String {
        dateTaskID(
            prefix:
                "multi-\(flightPlanningMode.rawValue)-"
                + "\(intermediateICAO)-\(planningOrigin.icao)-"
                + planningDestination.icao,
            date: outboundFlightDate
        )
        + "-"
        + dateTaskID(prefix: "destination-return", date: returnFlightDate)
    }

    private var weatherTaskID: String {
        let stamps = weatherTargetInstants.map { String(Int($0.timeIntervalSince1970 / 1800)) }
        return ([destination.icao] + stamps).joined(separator: "-")
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
        let outbound = FlightMath.adjustedBlockMinutes(
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
        let returnFlight = FlightMath.adjustedBlockMinutes(
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
        return outbound + (isOneWay ? 0 : returnFlight)
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
                    .padding(.top, 10)

                flightSection
                    .frame(width: 675)
                    .padding(.top, 12)

            }
            .frame(
                width: 675,
                height: 1144,
                alignment: .top
            )
            .offset(x: 34, y: 28)

            VStack(spacing: 12) {
                FlybookCard {
                    TravelDurationBar(
                        minutes:
                            outboundTravelMinutesForWeather,
                        thresholdMinutes:
                            maxTravelMinutesUntilOvernight
                    )
                    .offset(y: 2)
                }
                .frame(height: 64)

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

    private var headerSubtitle: String {
        let elevation = Int(destination.elevationFeet.rounded())
        let distance = Int(routeDirectNM.rounded())
        return "\(destination.icao)  ·  "
            + "\(countryFlag(destination.country))  ·  "
            + "\(destination.region.uppercased())  ·  "
            + "HÖHE \(elevation) FT  ·  LUFTLINIE \(distance) NM"
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(destination.name.uppercased())
                    .font(
                        .system(
                            size: destination.name.count > 16
                                ? 54
                                : 70,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(FlybookColor.navy)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )

                Text(headerSubtitle)
                .font(.system(size: 16))
                .foregroundStyle(FlybookColor.navy)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 10) {
                    Text("FLUGZEUG")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)
                        .frame(width: 78, alignment: .trailing)

                    Picker(
                        "Flugzeug",
                        selection: $selectedAircraftRaw
                    ) {
                        ForEach(AircraftType.allCases) {
                            aircraft in
                            Text(aircraft.rawValue)
                                .tag(aircraft.rawValue)
                        }
                    }
                    .labelsHidden()
                    .font(.system(size: 15, weight: .semibold))
                    .controlSize(.regular)
                    .frame(width: 160)
                }

                HStack(spacing: 10) {
                    Text("NUTZER")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)
                        .frame(width: 78, alignment: .trailing)

                    Picker(
                        "Nutzer",
                        selection: $activeUserRaw
                    ) {
                        ForEach(FlybookUser.allCases) { user in
                            Text(user.rawValue).tag(user.rawValue)
                        }
                    }
                    .labelsHidden()
                    .font(.system(size: 15, weight: .semibold))
                    .controlSize(.regular)
                    .frame(width: 160)
                }
            }
            .padding(.top, 8)
        }
        .onChange(of: activeUserRaw) { newValue in
            ETOPSProfileStore.activate(
                FlybookUser(rawValue: newValue) ?? .stephan
            )
        }
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

    private func refreshWeather() {
        Task {
            await weatherModel.load(
                destination: destination,
                targetInstants: weatherTargetInstants
            )
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
            await outboundEDFZWeatherModel.load(
                plannedDate: outboundFlightDate,
                airport: planningOrigin
            )
            await returnEDFZWeatherModel.load(
                plannedDate: returnFlightDate,
                airport: planningOrigin
            )
            await destinationAirportWeatherModel.load(
                plannedDate: outboundFlightDate,
                airport: planningDestination
            )
            await destinationReturnWeatherModel.load(
                plannedDate: returnFlightDate,
                airport: planningDestination
            )
            if flightPlanningMode == .multiStop {
                await intermediateWeatherModel.load(
                    plannedDate: outboundFlightDate,
                    airport: intermediateAirport
                )
            }
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
        outboundStartText = "09:30"
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
            desiredHomeArrivalText = "17:00"
        }
    }

    private func reverseFlightRoute() {
        isRouteReversed.toggle()
        outboundTrackMilesOverride = nil
        returnTrackMilesOverride = nil
    }

    private var flightSection: some View {
        FlybookCard {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("FLUGPLANUNG")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(FlybookColor.navy)

                            Spacer()

                            Picker("Zeitbasis", selection: timeModeBinding) {
                                Text("Lokal").tag(TimeDisplayMode.local)
                                Text("UTC").tag(TimeDisplayMode.utc)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .font(.system(size: 14, weight: .semibold))
                            .controlSize(.regular)
                            .frame(width: 150)
                        }

                        HStack(spacing: 10) {
                            Button {
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
                                flightPlanningMode = .roundTrip
                            } label: {
                                Text(FlightPlanningMode.roundTrip.rawValue)
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(
                                flightPlanningMode == .roundTrip
                                    ? FlybookColor.navy
                                    : FlybookColor.muted.opacity(0.55)
                            )
                            .controlSize(.regular)
                            .frame(width: 160)

                            Text("ABFLUG")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(FlybookColor.navy)
                                .frame(width: 62, alignment: .leading)

                            Picker(
                                "Abflugort",
                                selection: planningOriginSelection
                            ) {
                                ForEach(planningAirportOptions) { airport in
                                    Text("\(airport.icao) · \(airport.name)")
                                        .tag(airport.icao)
                                }
                            }
                            .labelsHidden()
                            .font(.system(size: 15))
                            .controlSize(.regular)
                            .frame(width: 230)
                            .help("Abflugort für alle Berechnungen")

                            if flightPlanningMode == .roundTrip {
                                Toggle("One-Way", isOn: $isOneWay)
                                    .toggleStyle(.checkbox)
                                    .font(
                                        .system(
                                            size: 15,
                                            weight: .semibold
                                        )
                                    )
                                    .foregroundStyle(FlybookColor.navy)
                                    .fixedSize()
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                flightPlanningMode = .multiStop
                                isOneWay = false
                                returnFlightDate = outboundFlightDate
                                multiStopDepartureText = ""
                            } label: {
                                Text(FlightPlanningMode.multiStop.rawValue)
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(
                                flightPlanningMode == .multiStop
                                    ? FlybookColor.navy
                                    : FlybookColor.muted.opacity(0.55)
                            )
                            .controlSize(.regular)
                            .frame(width: 160)

                            Text("STOP")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(FlybookColor.navy)
                                .frame(width: 62, alignment: .leading)

                            Picker(
                                "Zwischenstopp",
                                selection: $intermediateICAO
                            ) {
                                ForEach(availableOrigins) { airport in
                                    Text("\(airport.icao) · \(airport.name)")
                                        .tag(airport.icao)
                                }
                            }
                            .labelsHidden()
                            .font(.system(size: 15))
                            .controlSize(.regular)
                            .frame(width: 230)
                            .disabled(flightPlanningMode != .multiStop)
                            .opacity(
                                flightPlanningMode == .multiStop ? 1 : 0.55
                            )
                        }
                    }

                }

                Divider()

                FlightTimePlanningRows(
                    planningMode: flightPlanningMode,
                    isOneWay: isOneWay,
                    intermediateAirportICAO: $intermediateICAO,
                    airportOptions: planningAirportOptions,
                    outboundFlightDate: $outboundFlightDate,
                    returnFlightDate: $returnFlightDate,
                    outboundStartText: $outboundStartText,
                    desiredHomeArrivalText: $desiredHomeArrivalText,
                    multiStopDepartureText: $multiStopDepartureText,
                    outboundStops: outboundStopsBinding,
                    returnStops: returnStopsBinding,
                    outboundFlightAltitudeFeet:
                        $outboundFlightAltitudeFeet,
                    returnFlightAltitudeFeet:
                        $returnFlightAltitudeFeet,
                    outboundAltitudeOptions:
                        outboundAltitudeOptions,
                    returnAltitudeOptions:
                        returnAltitudeOptions,
                    flightTimes: destination.flightTimes,
                    outboundRouteWind: outboundRouteWindModel.wind,
                    returnRouteWind: returnRouteWindModel.wind,
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
                    destinationTimeZone: planningDestination.timeZone,
                    timeDisplayMode: timeDisplayMode,
                    tankStopMinutes: tankStopMinutes,
                    preTakeoffGroundMinutes: preTakeoffGroundMinutes,
                    postLandingGroundMinutes: postLandingGroundMinutes,
                    cruiseGroundSpeedKnots:
                        cruiseGroundSpeedKnots,
                    climbPerformance: climbPerformance,
                    cruisePerformance: cruisePerformance,
                    refreshWeather: refreshWeather,
                    resetSchedule: resetFlightPlanningSchedule,
                    reverseRoute: reverseFlightRoute
                )
            }
        }
    }


    private var calculationSection: some View {
        FlybookCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("CHARTERKALKULATION")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)
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

                CalculationColumnHeaders()

                CalculationRow(
                    title: flightPlanningMode == .multiStop
                        ? "1. LEG"
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
                        fuelConsumptionPerHour,
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
                    reserveNotConsumed:
                        $outboundReserveNotConsumed
                )

                if !isOneWay {
                    Divider()

                    CalculationRow(
                        title: flightPlanningMode == .multiStop
                            ? "2. LEG"
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
                            fuelConsumptionPerHour,
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
                            prepaymentDiscount30PlusEnabled
                    )
                }

                Divider()

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
                    fuelConsumptionPerHour:
                        fuelConsumptionPerHour,
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
                        requiredReservationBlockHours
                )

            }
        }
        .frame(width: 466, height: isOneWay ? 272 : 362)
    }

    private var calculationRowSection: some View {
        HStack {
            calculationSection
            Spacer()
        }
        .frame(width: 1010, alignment: .leading)
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
                    AirportMetric(title: "Runway", value: "\(destination.runwayM) m")
                    AirportMetric(title: "Surface", value: destination.surface)
                    AirportMetric(
                        title: "AVGAS",
                        value: destination.avgas,
                        fuelStatus: true,
                        pricePerLiterEUR:
                            destination.avgasPricePerLiterEUR,
                        referencePricePerLiterEUR: mainzAvgasPrice
                    )
                    AirportMetric(
                        title: "UL91",
                        value: destination.ul91,
                        fuelStatus: true,
                        pricePerLiterEUR:
                            destination.ul91PricePerLiterEUR,
                        referencePricePerLiterEUR: nil
                    )
                    AirportMetric(
                        title: "MOGAS",
                        value: destination.mogas,
                        fuelStatus: true,
                        pricePerLiterEUR:
                            destination.mogasPricePerLiterEUR,
                        referencePricePerLiterEUR: mainzMogasPrice
                    )
                }
            }
        }
    }

    private var mapAndImageSection: some View {
        FlybookCard {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("EUROPA")
                        .font(.title3.bold())
                        .foregroundStyle(FlybookColor.navy)

                    DestinationMapView(
                        latitude: planningDestination.latitude,
                        longitude: planningDestination.longitude,
                        title: planningDestination.name,
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
                                : nil
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
        .frame(height: 375)
    }

    private var fiveDayForecastSection: some View {
        FlybookCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("5-TAGES-WETTER FÜR \(destination.name.uppercased())")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)

                    Spacer()

                    Text("ICON Seamless · DWD")
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
                Image(systemName: weatherSymbol(for: day.weatherCode))
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

    private func weatherSymbol(for code: Int?) -> String {
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
}

private struct DailyForecastTile: View {
    let day: DailyForecast
    let confidencePercent: Int

    var body: some View {
        VStack(spacing: 7) {
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

                if showsStrongWindIndicator {
                    Image(systemName: "windsock.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.orange)
                        .help(
                            "Starker Bodenwind: über 15 kt "
                            + "Dauerwind oder über 20 kt Böen."
                        )
                }
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
    }

    private var showsStrongWindIndicator: Bool {
        (day.maximumSurfaceWindKnots ?? 0) > 15
            || (day.maximumWindGustKnots ?? 0) > 20
    }

    private var hourlyWindBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<12, id: \.self) { index in
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
                            format: "%02d–%02d Uhr: %@",
                            index + 8,
                            index + 9,
                            wind.map {
                                String(format: "%.0f kt Dauerwind", $0)
                            } ?? "keine Winddaten"
                        )
                    )
            }
        }
        .frame(height: 7)
    }

    private func windColor(_ windKnots: Double?) -> Color {
        guard let windKnots else {
            return FlybookColor.muted.opacity(0.22)
        }

        switch windKnots {
        case ..<3:
            return .white
        case ..<6:
            return Color(red: 1.00, green: 0.96, blue: 0.82)
        case ..<9:
            return Color(red: 1.00, green: 0.90, blue: 0.62)
        case ..<12:
            return Color(red: 1.00, green: 0.82, blue: 0.42)
        case ..<15:
            return Color(red: 1.00, green: 0.72, blue: 0.25)
        case ..<18:
            return Color(red: 0.98, green: 0.60, blue: 0.13)
        case ..<21:
            return Color(red: 0.94, green: 0.48, blue: 0.06)
        case ..<24:
            return Color(red: 0.90, green: 0.36, blue: 0.02)
        case ..<25:
            return Color(red: 0.87, green: 0.30, blue: 0.01)
        default:
            return Color(red: 0.78, green: 0.20, blue: 0.00)
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

    init(
        sample: EDFZWeatherSample?,
        elevationFeet: Double,
        runwayICAO: String? = nil
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
        if let runwayICAO,
           let direction,
           let speed,
           speed >= 0.5
        {
            runway = EDFZRunway.activeRunway(
                for: runwayICAO,
                windFromDegrees: direction,
                speedKnots: speed
            )
            runwayCrosswindWarning = EDFZRunway.crosswindWarning(
                for: runwayICAO,
                runway: runway,
                windFromDegrees: direction,
                steadyWindKnots: speed,
                gustKnots: gust
            )
        } else {
            runway = nil
            runwayCrosswindWarning = .none
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
        runway = nil
        runwayCrosswindWarning = .none
    }
}

private struct PlanningWeatherCard: View {
    let weather: PlanningWeather
    let civilDawnText: String?
    let sunriseText: String?
    let sunsetText: String?
    let civilDuskText: String?

    @AppStorage(UnitSystemSettingsKey.displaySystem)
    private var displayUnitSystemRaw = DisplayUnitSystem.eu.rawValue

    private var usesTwelveHourFormat: Bool {
        DisplayUnitSystem(rawValue: displayUnitSystemRaw) == .us
    }

    var body: some View {
        VStack(spacing: 3) {
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
                    .fill(Color.gray.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(FlybookColor.navy.opacity(0.45), lineWidth: 1)
            )

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

            if let sunriseText, let sunsetText {
                HStack(spacing: 8) {
                    Label(
                        TimeInput.displayClock(
                            sunriseText,
                            usesTwelveHourFormat: usesTwelveHourFormat
                        ),
                        systemImage: "sunrise.fill"
                    )
                    Label(
                        TimeInput.displayClock(
                            sunsetText,
                            usesTwelveHourFormat: usesTwelveHourFormat
                        ),
                        systemImage: "sunset.fill"
                    )
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(FlybookColor.muted)
            }

            if let civilDawnText, let civilDuskText {
                HStack(spacing: 8) {
                    Label(
                        TimeInput.displayClock(
                            civilDawnText,
                            usesTwelveHourFormat: usesTwelveHourFormat
                        ),
                        systemImage: "sun.horizon.fill"
                    )
                    .help("Beginn der bürgerlichen Dämmerung")

                    Label(
                        TimeInput.displayClock(
                            civilDuskText,
                            usesTwelveHourFormat: usesTwelveHourFormat
                        ),
                        systemImage: "moon.stars.fill"
                    )
                    .help("Ende der bürgerlichen Dämmerung")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(FlybookColor.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.13))
        )
    }

    private var symbol: String {
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
    @Binding var outboundFlightDate: Date
    @Binding var returnFlightDate: Date
    @Binding var outboundStartText: String
    @Binding var desiredHomeArrivalText: String
    @Binding var multiStopDepartureText: String
    @Binding var outboundStops: Int
    @Binding var returnStops: Int
    @Binding var outboundFlightAltitudeFeet: Int
    @Binding var returnFlightAltitudeFeet: Int

    let outboundAltitudeOptions: [Int]
    let returnAltitudeOptions: [Int]
    let flightTimes: FlightTimes
    let outboundRouteWind: RouteWind?
    let returnRouteWind: RouteWind?
    let outboundBestLevelFeet: Int?
    let returnBestLevelFeet: Int?
    let outboundEDFZForecast: EDFZForecast?
    let returnEDFZForecast: EDFZForecast?
    let intermediateAirportForecast: EDFZForecast?
    let destinationAirportForecast: EDFZForecast?
    let destinationReturnForecast: EDFZForecast?
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
        planningMode == .multiStop
            ? intermediateAirport
            : destinationReference
    }

    private var secondDepartureAirport: AirportReference {
        planningMode == .multiStop
            ? intermediateAirport
            : destinationReference
    }

    private var secondArrivalAirport: AirportReference {
        planningMode == .multiStop
            ? destinationReference
            : origin
    }

    private var displayTimeZone: TimeZone {
        timeDisplayMode == .utc
            ? TimeZone(secondsFromGMT: 0)!
            : origin.timeZone
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
            timeZone: displayTimeZone
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
        if planningMode == .multiStop {
            return PlanningWeather(
                sample: intermediateArrivalSample,
                elevationFeet: firstArrivalAirport.elevationFeet,
                runwayICAO: firstArrivalAirport.icao
            )
        }
        return PlanningWeather(
            sample: destinationOutboundArrivalSample,
            elevationFeet: firstArrivalAirport.elevationFeet,
            runwayICAO: firstArrivalAirport.icao
        )
    }

    private var secondDepartureWeather: PlanningWeather {
        if planningMode == .multiStop {
            return PlanningWeather(
                sample: intermediateDepartureSample,
                elevationFeet: secondDepartureAirport.elevationFeet,
                runwayICAO: secondDepartureAirport.icao
            )
        }
        return PlanningWeather(
            sample: destinationReturnDepartureSample,
            elevationFeet: secondDepartureAirport.elevationFeet,
            runwayICAO: secondDepartureAirport.icao
        )
    }

    private var secondArrivalWeather: PlanningWeather {
        PlanningWeather(
            sample: planningMode == .multiStop
                ? destinationArrivalSample
                : homeArrivalAirportSample,
            elevationFeet: secondArrivalAirport.elevationFeet,
            runwayICAO: secondArrivalAirport.icao
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

    private func setReturnToNow() {
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
            timeZone: origin.timeZone
        )
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
                    ? "1. LEG"
                    : "HINFLUG",
                flightDate: $outboundFlightDate,
                showsRefreshButton: true,
                refreshWeather: refreshWeather,
                resetSchedule: resetSchedule,
                reverseRoute: reverseRoute,
                setNow: setOutboundToNow,
                showsETOPSHeader: true,
                stopCount: $outboundStops,
                flightAltitudeFeet:
                    $outboundFlightAltitudeFeet,
                altitudeOptions: outboundAltitudeOptions,
                travelMinutes: outboundTravelMinutes,
                directNM: outboundDirectNM,
                trackMiles: $outboundTrackMiles,
                headwindKnots: outboundRouteWind?.outboundHeadwindKnots,
                bestLevelFeet: outboundBestLevelFeet,
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
                    runwayICAO: origin.icao
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
                trailingAirportSelection: nil,
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

            if !isOneWay {
                Divider()
                    .padding(.vertical, 6)

                FlightPlanningLine(
                directionTitle:
                    planningMode == .multiStop
                    ? "2. LEG"
                    : "RÜCKFLUG",
                flightDate: $returnFlightDate,
                showsRefreshButton: false,
                refreshWeather: refreshWeather,
                resetSchedule: resetSchedule,
                reverseRoute: reverseRoute,
                setNow: setReturnToNow,
                showsETOPSHeader: true,
                stopCount: $returnStops,
                flightAltitudeFeet:
                    $returnFlightAltitudeFeet,
                altitudeOptions: returnAltitudeOptions,
                travelMinutes: returnTravelMinutes,
                directNM: returnDirectNM,
                trackMiles: $returnTrackMiles,
                headwindKnots: returnRouteWind?.outboundHeadwindKnots,
                bestLevelFeet: returnBestLevelFeet,
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
                trailingAirportSelection: nil,
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
    let showsETOPSHeader: Bool
    @Binding var stopCount: Int
    @Binding var flightAltitudeFeet: Int
    let altitudeOptions: [Int]
    let travelMinutes: Int
    let directNM: Double
    @Binding var trackMiles: Double
    let headwindKnots: Double?
    let bestLevelFeet: Int?
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
        HStack(alignment: .top, spacing: 5) {
            StopCountSelector(selection: $stopCount)
                .frame(width: 98, height: 108)
                .padding(.top, 158)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(directionTitle)
                        .font(
                            .system(
                                size: 18,
                                weight: .bold,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(FlybookColor.navy)

                    DatePicker(
                        "",
                        selection: $flightDate,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .font(.system(size: 16, weight: .semibold))
                    .controlSize(.regular)
                    .frame(width: 128)

                    Button("Heute") {
                        flightDate =
                            Calendar.current.startOfDay(for: Date())
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 15, weight: .semibold))
                    .controlSize(.regular)

                    Button("Jetzt", action: setNow)
                        .buttonStyle(.bordered)
                        .font(.system(size: 15, weight: .semibold))
                        .controlSize(.regular)

                    Spacer(minLength: 0)
                }

                HStack(alignment: .top, spacing: 22) {
                    FlightLocationHeader(
                        title: leadingTitle,
                        runway: leadingRunway,
                        crosswindWarning:
                            leadingWeather.runwayCrosswindWarning
                    )

                    if let trailingAirportSelection {
                        VStack(spacing: 3) {
                            Text("ANKUNFT")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(FlybookColor.muted)

                            Picker(
                                "Zwischenstopp",
                                selection: trailingAirportSelection
                            ) {
                                ForEach(airportOptions) { airport in
                                    Text("\(airport.icao) · \(airport.name)")
                                        .tag(airport.icao)
                                }
                            }
                            .labelsHidden()
                            .controlSize(.small)
                            .frame(width: 174)
                        }
                        .frame(width: 174)
                    } else {
                        FlightLocationHeader(
                            title: trailingTitle,
                            runway: trailingRunway,
                            crosswindWarning:
                                trailingWeather.runwayCrosswindWarning
                        )
                    }
                }

                HStack(alignment: .center, spacing: 4) {
                    VStack(spacing: 5) {
                        leading
                    }
                    .frame(width: 174)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FlybookColor.muted)
                        .frame(width: 18, height: 43)

                    VStack(spacing: 5) {
                        trailing
                    }
                    .frame(width: 174)
                }
                .frame(height: 43)
                .overlay(alignment: .trailing) {
                    TravelDurationBadge(minutes: travelMinutes)
                        .frame(width: 70, height: 43)
                        .offset(x: 75)
                }

                HStack(spacing: 4) {
                    PlanningWeatherCard(
                        weather: leadingWeather,
                        civilDawnText: leadingCivilDawnText,
                        sunriseText: leadingSunriseText,
                        sunsetText: leadingSunsetText,
                        civilDuskText: leadingCivilDuskText
                    )
                    .frame(width: 142, height: 184)
                    .frame(width: 174)

                    Color.clear
                        .frame(width: 18)

                    PlanningWeatherCard(
                        weather: trailingWeather,
                        civilDawnText: trailingCivilDawnText,
                        sunriseText: trailingSunriseText,
                        sunsetText: trailingSunsetText,
                        civilDuskText: trailingCivilDuskText
                    )
                    .frame(width: 142, height: 184)
                    .frame(width: 174)
                }

                HStack(spacing: 8) {
                    Text(
                        bestLevelFeet.map {
                            String(format: "Best Level: FL%03d", Int(round(Double($0) / 100.0)))
                        } ?? "Best Level: —"
                    )
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(FlybookColor.blue)
                    .frame(width: 140, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                    Picker(
                        "Flughöhe",
                        selection: $flightAltitudeFeet
                    ) {
                        ForEach(
                            altitudeOptions,
                            id: \.self
                        ) { altitude in
                            Text(altitudeLabel(altitude)).tag(altitude)
                        }
                    }
                    .labelsHidden()
                    .font(.system(size: 15, weight: .semibold))
                    .controlSize(.regular)
                    .frame(width: 100)

                    if let headwindKnots {
                        WindInfluenceLabel(
                            headwindKnots: headwindKnots
                        )
                    }
                }

            }
            .frame(width: 420)

            Color.clear
                .frame(width: 52, height: 1)

            VStack(spacing: 5) {
                Text("ETOPS-\nPIPI")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(-1)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 54, height: 28)
                Circle()
                    .fill(
                        ETOPSBand.color(
                            for: selectedLegMinutes,
                            greenYellowMinutes: greenYellowMinutes,
                            orangeRedMinutes: orangeRedMinutes
                        )
                    )
                    .overlay(
                        Circle().stroke(
                            FlybookColor.navy.opacity(0.35),
                            lineWidth: 1
                        )
                    )
                    .frame(width: 16, height: 16)

                Divider().frame(width: 48)

                TrackMilesEditor(trackMiles: $trackMiles)
            }
            .frame(width: 64)
            .help("Farbe aus der Dauer des einzelnen Fluglegs")
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .topLeading) {
            if showsRefreshButton {
                VStack(spacing: 8) {
                    Button(action: refreshWeather) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 21, weight: .bold))
                            .frame(width: 38, height: 32)
                    }
                    .help("Wetterdaten jetzt aktualisieren")

                    Button(action: resetSchedule) {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 17, weight: .bold))
                            Text("Reset")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .frame(width: 38, height: 38)
                    }
                    .help("Datum und Uhrzeiten auf Standard zurücksetzen")

                    Button(action: reverseRoute) {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 17, weight: .bold))
                            Text("Umkehren")
                                .font(.system(size: 9, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(width: 38, height: 38)
                    }
                    .help("Start- und Zielflugplatz vertauschen")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }
}

private struct TrackMilesEditor: View {
    @Binding var trackMiles: Double

    var body: some View {
        VStack(spacing: 3) {
            Text("TRACK\nNM")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
                .multilineTextAlignment(.center)

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
        Double(actualBlockMinutes) / 60
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
                .locale(Locale(identifier: "de_DE"))
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
    let fuelConsumptionPerHour: Double
    let reserveMinutes: Int
    let usableFuel: Double
    let fuelUnit: FuelDisplayUnit
    let preTakeoffGroundMinutes: Int
    let postLandingGroundMinutes: Int
    let prepaymentDiscount15To29Enabled: Bool
    let prepaymentDiscount30PlusEnabled: Bool
    let minimumRequiredBlockHours: Double

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
        return Double(minutes) / 60.0 * rate
            * (1.0 + max(0, vatPercent) / 100.0)
    }

    private var totalRequiredFuel: Double {
        let blockFuel =
            Double(totalMinutes)
            * fuelConsumptionPerHour
            / 60.0

        let reserveFuel =
            fuelConsumptionPerHour
            * Double(reserveMinutes)
            / 60.0

        return blockFuel
            + (outboundReserveNotConsumed ? 0 : reserveFuel)
    }

    private var totalCost: Double {
        legCost(minutes: outboundMinutes, date: outboundFlightDate)
        + (
            includesReturn
                ? legCost(minutes: returnMinutes, date: returnFlightDate)
                : 0
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("GESAMT")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(FlybookColor.navy)
                .frame(width: 78, alignment: .leading)

            totalBox(
                value: decimalHours(totalMinutes),
                valueColor:
                    Double(totalMinutes) / 60
                        < minimumRequiredBlockHours
                    ? .red
                    : FlybookColor.navy
            )

            totalBox(
                value:
                    "\(Int(ceil(fuelUnit.fromLiters(totalRequiredFuel)))) "
                    + fuelUnit.symbol
            )

            totalBox(
                value: totalCost
                    .rounded(.toNearestOrAwayFromZero)
                    .formatted(
                    .currency(code: "EUR")
                        .locale(Locale(identifier: "de_DE"))
                        .precision(.fractionLength(0))
                )
            )
        }
    }

    private func decimalHours(_ minutes: Int) -> String {
        let hours = Double(minutes) / 60.0
        let commerciallyRounded =
            (hours * 10).rounded(.toNearestOrAwayFromZero) / 10
        return commerciallyRounded.formatted(
            .number
                .locale(Locale(identifier: "de_DE"))
                .precision(.fractionLength(1))
        ) + " h"
    }

    private func totalBox(
        value: String,
        valueColor: Color = FlybookColor.navy
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
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
                .minimumScaleFactor(0.75)
        }
        .frame(width: 96, alignment: .leading)
        .padding(7)
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
    var reserveNotConsumed: Binding<Bool>? = nil

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
        Double(blockMinutes) / 60.0
            * netHourlyRateEUR
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
        let hours = Double(blockMinutes) / 60.0
        let commerciallyRounded =
            (hours * 10).rounded(.toNearestOrAwayFromZero) / 10
        return commerciallyRounded.formatted(
            .number
                .locale(Locale(identifier: "de_DE"))
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
            + (
                reserveNotConsumed?.wrappedValue == true
                    ? 0
                    : reserveFuel
            )
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(stopLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FlybookColor.muted)
                }
                .frame(width: 78, alignment: .leading)

                valueBox(value: blockTimeText)

                valueBox(
                    value: requiredFuelText,
                    valueColor: fuelResultColor
                )

                VStack(alignment: .leading, spacing: 3) {
                    valueBox(value: costText)

                    if prepaymentDiscount15To29Enabled {
                        discountText("25 % Vorauszahlungsrabatt")
                    } else if prepaymentDiscount30PlusEnabled {
                        discountText("15 % Vorauszahlungsrabatt")
                    }

                    if discountApplies {
                        discountText("5 % Wochentagsrabatt")
                    }
                }
                .frame(width: 110, alignment: .topLeading)
                .frame(minHeight: 70, alignment: .topLeading)
            }

            if let reserveNotConsumed {
                Toggle(
                    "Hinflugreserve nicht verbraucht",
                    isOn: reserveNotConsumed
                )
                .toggleStyle(.checkbox)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FlybookColor.navy)
                .padding(.leading, 84)
            }
        }
        .frame(minHeight: 70, alignment: .top)
    }

    private func discountText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.green)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func valueBox(
        value: String,
        valueColor: Color = FlybookColor.navy
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
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
                .minimumScaleFactor(0.75)
        }
        .frame(width: 96, alignment: .leading)
        .padding(7)
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
                .frame(width: 78, height: 1)

            header("BLOCKZEIT")
            header("KRAFTSTOFF")
            header("KOSTEN")
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(FlybookColor.navy)
            .frame(width: 110, alignment: .leading)
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
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(
                isHeadwind ? Color.red : Color.green
            )
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

private struct TravelDurationBadge: View {
    let minutes: Int

    var body: some View {
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
        .help("Gesamtreisezeit für die gewählte Anzahl Zwischenstopps")
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
                    .frame(height: 36)
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

private struct FlightLocationHeader: View {
    let title: String
    let runway: String?
    let crosswindWarning: RunwayCrosswindWarning

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(FlybookColor.navy)
                .lineLimit(1)

            Label(runway ?? " ", systemImage: "road.lanes")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(FlybookColor.navy)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(crosswindBackgroundColor)
                )
                .opacity(runway == nil ? 0 : 1)
                .frame(height: 20)
                .help(crosswindHelp)
        }
        .frame(width: 174)
    }

    private var crosswindBackgroundColor: Color {
        switch crosswindWarning {
        case .none: return .clear
        case .yellow: return Color.yellow.opacity(0.65)
        case .red: return Color.red.opacity(0.72)
        }
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
    var fuelStatus = false
    var pricePerLiterEUR: Double? = nil
    var referencePricePerLiterEUR: Double? = nil

    private var valueColor: Color {
        guard fuelStatus else { return FlybookColor.navy }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized == "ja" || normalized == "yes" { return .green }
        if normalized == "nein" || normalized == "no" { return .red }
        return FlybookColor.navy
    }

    private var priceColor: Color {
        guard let pricePerLiterEUR,
              let referencePricePerLiterEUR
        else { return FlybookColor.muted }
        if abs(pricePerLiterEUR - referencePricePerLiterEUR) < 0.005 {
            return FlybookColor.blue
        }
        return pricePerLiterEUR > referencePricePerLiterEUR
            ? .red
            : .green
    }

    private var priceText: String {
        guard let pricePerLiterEUR else { return "— €/L" }
        let formattedPrice = pricePerLiterEUR.formatted(
            .currency(code: "EUR")
                .locale(Locale(identifier: "de_DE"))
                .precision(.fractionLength(2))
        ) + "/L"

        guard let referencePricePerLiterEUR else {
            return formattedPrice
        }

        let differenceCents =
            Int(
                ((pricePerLiterEUR - referencePricePerLiterEUR) * 100)
                    .rounded()
            )
        if differenceCents == 0 {
            return formattedPrice + " (±0 ct)"
        }
        let sign = differenceCents > 0 ? "+" : ""
        return formattedPrice + " (\(sign)\(differenceCents) ct)"
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .bold))

            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            if fuelStatus {
                Text(priceText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(priceColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(FlybookColor.navy)
        .frame(maxWidth: .infinity)
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
