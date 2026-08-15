import SwiftUI

enum DestinationFinderMinimumWeather: String, CaseIterable, Identifiable {
    case vfr = "VFR"
    case mvfr = "MVFR"

    var id: String { rawValue }

    var maximumSeverity: Int {
        switch self {
        case .vfr: return FlightCategory.vfr.severity
        case .mvfr: return FlightCategory.mvfr.severity
        }
    }
}

struct DestinationFinderCriteria {
    let originICAO: String
    let from: Date
    let until: Date
    var minimumTravelMinutes = 0
    let maximumTravelMinutes: Int
    var ignoresTravelTime = false
    let appliesETOPS: Bool
    let maximumRoundTripPriceEUR: Double
    var ignoresPrice = false
    let priceAppliesETOPS: Bool
    var requiresLandingVoucher = false
    let requiredFeatures: Set<DestinationFeature>
    var requiresBicycleAtAirport = false
    var requiresRentalCarAtAirport = false
    var requiresApp2DriveAtAirport = false
    var minimumRunwayLengthMeters = 300
    var allowedCountryCodes: Set<String>? = nil
    var requiredFuelTypes: Set<AircraftFuelType> = []
    var requiresFuelAtOrBelowReferencePrice = false
    let minimumTemperatureCelsius: Double
    var ignoresMinimumTemperature = false
    let maximumTemperatureCelsius: Double
    var ignoresMaximumTemperature = false
    let maximumSteadyWindKnots: Double
    let ignoresWind: Bool
    let maximumGustKnots: Double
    let ignoresGusts: Bool
    var maximumFoehnPressureDifferenceHPA = 2.0
    var ignoresFoehn = true
    let minimumWeather: DestinationFinderMinimumWeather
    var ignoresMinimumWeather = false
    var usesMinimumWeatherCoverageRule = true
    let requiresCloudless: Bool
    var requiresScatteredCloudCoverage = false
    let requiresRainFree: Bool
    var requiresRainFreeCoverage = false
    let daylightOnly: Bool
    let daytimeOnly: Bool
    var minimumWeatherDaylightOnly = false
    var maximumRouteWeatherRisk = RouteWeatherRisk.green
    var ignoresRouteWeather = true

    var requiresWeatherData: Bool {
        !ignoresMinimumTemperature
            || !ignoresMaximumTemperature
            || !ignoresWind
            || !ignoresGusts
            || !ignoresMinimumWeather
            || requiresCloudless
            || requiresScatteredCloudCoverage
            || requiresRainFree
            || requiresRainFreeCoverage
    }
}

@MainActor
private final class DestinationFinderSession {
    static let shared = DestinationFinderSession()

    var originICAO = "EDFZ"
    var from: Date
    var until: Date
    var minimumTravelHours = 0.0
    var maximumTravelHours = 3.0
    var ignoresTravelTime = false
    var appliesETOPS = true
    var maximumRoundTripPrice = 1_000.0
    var ignoresPrice = true
    var priceAppliesETOPS = true
    var requiresLandingVoucher = false
    var requiredFeatures: Set<DestinationFeature> = [
        .beachSea, .lakeNature, .mountainHiking, .wellness
    ]
    var requiresBicycleAtAirport = false
    var requiresRentalCarAtAirport = false
    var requiresApp2DriveAtAirport = false
    var minimumRunwayLength = 300.0
    var selectedCountryCodes: Set<String>?
    var requiredFuelTypes: Set<AircraftFuelType> = []
    var requiresFuelAtOrBelowReferencePrice = false
    var minimumTemperature = 10.0
    var ignoresMinimumTemperature = false
    var maximumTemperature = 40.0
    var ignoresMaximumTemperature = true
    var maximumWind = 15.0
    var ignoresWind = false
    var maximumGust = 25.0
    var ignoresGusts = true
    var maximumFoehnPressureDifference = 2.0
    var ignoresFoehn = true
    var minimumWeather = DestinationFinderMinimumWeather.vfr
    var ignoresMinimumWeather = false
    var usesMinimumWeatherCoverageRule = true
    var requiresCloudless = false
    var requiresScatteredCloudCoverage = false
    var requiresRainFree = false
    var requiresRainFreeCoverage = false
    var daylightOnly = true
    var filterUserRaw = ""
    var maximumRouteWeatherRisk = RouteWeatherRisk.green
    var ignoresRouteWeather = true

    private init() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: Date())
        ) ?? Date()
        from = calendar.date(
            bySettingHour: 6, minute: 0, second: 0, of: tomorrow
        ) ?? tomorrow
        until = calendar.date(
            bySettingHour: 22, minute: 0, second: 0, of: tomorrow
        ) ?? tomorrow
    }

    func reset(countryCodes: Set<String>, activeUserRaw: String) {
        originICAO = "EDFZ"
        let calendar = Calendar.current
        let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: Date())
        ) ?? Date()
        from = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        until = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        minimumTravelHours = 0
        maximumTravelHours = 3
        ignoresTravelTime = false
        appliesETOPS = true
        maximumRoundTripPrice = 1_000
        ignoresPrice = true
        priceAppliesETOPS = true
        requiresLandingVoucher = false
        requiredFeatures = [
            .beachSea, .lakeNature, .mountainHiking, .wellness
        ]
        requiresBicycleAtAirport = false
        requiresRentalCarAtAirport = false
        requiresApp2DriveAtAirport = false
        minimumRunwayLength = 300
        selectedCountryCodes = countryCodes
        requiredFuelTypes = []
        requiresFuelAtOrBelowReferencePrice = false
        minimumTemperature = 10
        ignoresMinimumTemperature = false
        maximumTemperature = 40
        ignoresMaximumTemperature = true
        maximumWind = 15
        ignoresWind = false
        maximumGust = 25
        ignoresGusts = true
        maximumFoehnPressureDifference = 2
        ignoresFoehn = true
        minimumWeather = .vfr
        ignoresMinimumWeather = false
        usesMinimumWeatherCoverageRule = true
        requiresCloudless = false
        requiresScatteredCloudCoverage = false
        requiresRainFree = false
        requiresRainFreeCoverage = false
        daylightOnly = true
        filterUserRaw = activeUserRaw
        maximumRouteWeatherRisk = .green
        ignoresRouteWeather = true
    }
}

struct DestinationFinderMatch: Identifiable, Hashable {
    var id: String { destinationICAO }
    let destinationICAO: String
    let destinationName: String
    let travelMinutes: Int
    let stopCount: Int
    let roundTripPriceEUR: Double
    let priceStopCount: Int
    var weatherWasChecked = true
}

struct DestinationFinderWeatherHour: Codable, Equatable {
    let instant: Date
    let temperatureCelsius: Double?
    let steadyWindKnots: Double?
    let gustKnots: Double?
    let precipitationMillimeters: Double?
    let totalCloudCoverPercent: Double?
    let visibilityMeters: Double?
    let lowCloudCoverPercent: Double?
    let dewPointCelsius: Double?
}

enum DestinationFinderRouteWeatherEvaluation: Equatable {
    case matches
    case rejects
    case incomplete
}

enum DestinationFinderEvaluator {
    static func evaluateRouteWeather(
        _ risks: [RouteWeatherRisk],
        maximum: RouteWeatherRisk
    ) -> DestinationFinderRouteWeatherEvaluation {
        let availableRisks = risks.filter { $0 != .unavailable }
        if availableRisks.contains(where: { $0 > maximum }) {
            return .rejects
        }
        if risks.isEmpty || availableRisks.count != risks.count {
            return .incomplete
        }
        return .matches
    }

    static func routeWeatherMatches(
        _ risks: [RouteWeatherRisk],
        maximum: RouteWeatherRisk
    ) -> Bool {
        evaluateRouteWeather(risks, maximum: maximum) == .matches
    }

    static func serviceIsAvailable(_ value: String) -> Bool {
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

    static func featuresMatch(
        destinationFeatures: Set<DestinationFeature>,
        requiredFeatures: Set<DestinationFeature>
    ) -> Bool {
        requiredFeatures.isEmpty
            || !destinationFeatures.isDisjoint(with: requiredFeatures)
    }

    static func landingVoucherMatches(
        icao: String,
        flightDate: Date,
        required: Bool,
        voucherProvider: (String, Date) -> Bool = {
            LandingVoucherBook.includes($0, on: $1)
        }
    ) -> Bool {
        !required || voucherProvider(icao, flightDate)
    }

    static func weatherMatches(
        _ hours: [DestinationFinderWeatherHour]?,
        criteria: DestinationFinderCriteria,
        destination: AirportReference
    ) -> Bool {
        guard let hours else { return false }
        return weatherMatches(
            hours,
            criteria: criteria,
            destination: destination
        )
    }

    static func weatherMatches(
        _ hours: [DestinationFinderWeatherHour],
        criteria: DestinationFinderCriteria,
        destination: AirportReference
    ) -> Bool {
        let periodHours = hours.filter { hour in
            guard hour.instant >= criteria.from,
                  hour.instant <= criteria.until
            else { return false }

            if criteria.daytimeOnly {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = destination.timeZone
                let localHour = calendar.component(.hour, from: hour.instant)
                guard (6..<22).contains(localHour) else { return false }
            }

            return true
        }

        func isDaylight(_ hour: DestinationFinderWeatherHour) -> Bool {
            guard let events = SolarCalculator.events(
                forLocalDayContaining: hour.instant,
                latitude: destination.latitude,
                longitude: destination.longitude,
                timeZone: destination.timeZone
            ) else { return false }
            return hour.instant >= events.sunrise
                && hour.instant <= events.sunset
        }

        let selected = criteria.daylightOnly
            ? periodHours.filter(isDaylight)
            : periodHours
        let minimumWeatherHours = criteria.minimumWeatherDaylightOnly
            ? periodHours.filter(isDaylight)
            : selected
        let requiresSelectedHours = !criteria.ignoresMinimumTemperature
            || !criteria.ignoresMaximumTemperature
            || !criteria.ignoresWind
            || !criteria.ignoresGusts
            || criteria.requiresCloudless
            || criteria.requiresScatteredCloudCoverage
            || criteria.requiresRainFree
        guard !requiresSelectedHours || !selected.isEmpty else { return false }

        guard criteria.ignoresMinimumTemperature || selected.contains(where: {
            ($0.temperatureCelsius ?? -.infinity)
                >= criteria.minimumTemperatureCelsius
        }) else { return false }

        if !criteria.ignoresMaximumTemperature, selected.contains(where: {
            ($0.temperatureCelsius ?? -.infinity)
                > criteria.maximumTemperatureCelsius
        }) {
            return false
        }

        if !criteria.ignoresWind,
           selected.contains(where: {
            ($0.steadyWindKnots ?? 0) > criteria.maximumSteadyWindKnots
           })
        {
            return false
        }

        if !criteria.ignoresGusts,
           selected.contains(where: {
               ($0.gustKnots ?? 0) > criteria.maximumGustKnots
           })
        {
            return false
        }

        let categories = minimumWeatherHours.map(category)
        guard criteria.ignoresMinimumWeather || minimumWeatherMatches(
            categories,
            minimum: criteria.minimumWeather,
            usesCoverageRule: criteria.usesMinimumWeatherCoverageRule
        )
        else { return false }

        if criteria.requiresCloudless {
            let cloudValues = selected.compactMap(\.totalCloudCoverPercent)
            guard !cloudValues.isEmpty,
                  !cloudValues.contains(where: { $0 > 25 })
            else { return false }
            let fewHours = cloudValues.filter { $0 > 0 }.count
            guard Double(fewHours) / Double(cloudValues.count) < 0.5
            else { return false }
        }

        if criteria.requiresScatteredCloudCoverage {
            guard scatteredCloudCoverageMatches(
                hours,
                from: criteria.from,
                until: criteria.until,
                destination: destination,
                daylightOnly: criteria.daylightOnly
            ) else { return false }
        }

        if criteria.requiresRainFree {
            guard selected.allSatisfy({ hour in
                guard let precipitation = hour.precipitationMillimeters else {
                    return false
                }
                return precipitation < 0.1
            }) else { return false }
        }

        if criteria.requiresRainFreeCoverage {
            guard rainFreeCoverageMatches(
                hours,
                from: criteria.from,
                until: criteria.until,
                destination: destination,
                daylightOnly: criteria.daylightOnly
            ) else { return false }
        }

        return true
    }

    static func minimumWeatherMatches(
        _ categories: [FlightCategory],
        minimum: DestinationFinderMinimumWeather,
        usesCoverageRule: Bool
    ) -> Bool {
        guard !categories.isEmpty else { return false }
        let acceptable = categories.filter {
            $0 != .unavailable
                && $0.severity <= minimum.maximumSeverity
        }.count
        if usesCoverageRule {
            return Double(acceptable) / Double(categories.count) >= 0.66
        }
        return acceptable == categories.count
    }

    static func rainFreeCoverageMatches(
        _ hours: [DestinationFinderWeatherHour],
        from: Date,
        until: Date,
        destination: AirportReference,
        daylightOnly: Bool = true
    ) -> Bool {
        guard until >= from else { return false }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = destination.timeZone
        var day = calendar.startOfDay(for: from)
        let lastDay = calendar.startOfDay(for: until)
        var evaluatedDay = false

        while day <= lastDay {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day)
            else { return false }
            let localNoon = calendar.date(
                bySettingHour: 12,
                minute: 0,
                second: 0,
                of: day
            ) ?? day
            let evaluationBounds: (start: Date, end: Date)?
            if daylightOnly {
                evaluationBounds = SolarCalculator.events(
                    forLocalDayContaining: localNoon,
                    latitude: destination.latitude,
                    longitude: destination.longitude,
                    timeZone: destination.timeZone
                ).map { events in
                    (max(from, events.sunrise), min(until, events.sunset))
                }
            } else {
                let endOfDay = nextDay.addingTimeInterval(-1)
                evaluationBounds = (max(from, day), min(until, endOfDay))
            }

            if let bounds = evaluationBounds,
               bounds.start <= bounds.end
            {
                evaluatedDay = true
                let samples = hours.filter {
                    $0.instant >= bounds.start
                        && $0.instant <= bounds.end
                }
                guard !samples.isEmpty else { return false }
                let rainFreeSamples = samples.filter {
                    guard let precipitation = $0.precipitationMillimeters else {
                        return false
                    }
                    return precipitation < 0.1
                }.count
                guard Double(rainFreeSamples) / Double(samples.count) >= 0.66
                else { return false }
            }

            day = nextDay
        }

        return evaluatedDay
    }

    static func scatteredCloudCoverageMatches(
        _ hours: [DestinationFinderWeatherHour],
        from: Date,
        until: Date,
        destination: AirportReference,
        daylightOnly: Bool = true
    ) -> Bool {
        guard until >= from else { return false }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = destination.timeZone
        var day = calendar.startOfDay(for: from)
        let lastDay = calendar.startOfDay(for: until)
        var evaluatedDay = false

        while day <= lastDay {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day)
            else { return false }
            let localNoon = calendar.date(
                bySettingHour: 12,
                minute: 0,
                second: 0,
                of: day
            ) ?? day
            let evaluationBounds: (start: Date, end: Date)?
            if daylightOnly {
                evaluationBounds = SolarCalculator.events(
                    forLocalDayContaining: localNoon,
                    latitude: destination.latitude,
                    longitude: destination.longitude,
                    timeZone: destination.timeZone
                ).map { events in
                    (max(from, events.sunrise), min(until, events.sunset))
                }
            } else {
                let endOfDay = nextDay.addingTimeInterval(-1)
                evaluationBounds = (max(from, day), min(until, endOfDay))
            }

            if let bounds = evaluationBounds,
               bounds.start <= bounds.end
            {
                evaluatedDay = true
                let samples = hours.filter {
                    $0.instant >= bounds.start
                        && $0.instant <= bounds.end
                }
                guard !samples.isEmpty else { return false }
                let scatteredOrBetterSamples = samples.filter {
                    guard let cloudCover = $0.totalCloudCoverPercent else {
                        return false
                    }
                    return cloudCover <= 50
                }.count
                guard scatteredOrBetterSamples * 3 >= samples.count * 2
                else { return false }
            }

            day = nextDay
        }

        return evaluatedDay
    }

    static func category(
        _ hour: DestinationFinderWeatherHour
    ) -> FlightCategory {
        let cloudBaseFeet: Double?
        if let temperature = hour.temperatureCelsius,
           let dewPoint = hour.dewPointCelsius
        {
            cloudBaseFeet = max(0, temperature - dewPoint) * 400
        } else {
            cloudBaseFeet = nil
        }
        let ceiling = (hour.lowCloudCoverPercent ?? 0) >= 62.5
            ? cloudBaseFeet
            : nil
        let visibilitySM = hour.visibilityMeters.map { $0 / 1609.344 }

        if (ceiling ?? .infinity) < 500
            || (visibilitySM ?? .infinity) < 1
        {
            return .lifr
        }
        if (ceiling ?? .infinity) < 1000
            || (visibilitySM ?? .infinity) < 3
        {
            return .ifr
        }
        if (ceiling ?? .infinity) <= 3000
            || (visibilitySM ?? .infinity) <= 5
        {
            return .mvfr
        }
        if ceiling != nil || visibilitySM != nil { return .vfr }
        return .unavailable
    }
}

enum DestinationFinderPricing {
    static func roundTripCost(
        outboundMinutes: Int,
        returnMinutes: Int,
        outboundDate: Date,
        returnDate: Date,
        hourlyRateEUR: Double,
        vatPercent: Double,
        weekdayDiscountEnabled: Bool,
        prepaymentDiscount15To29Enabled: Bool,
        prepaymentDiscount30PlusEnabled: Bool,
        calendar: Calendar = .current
    ) -> Double {
        legCost(
            minutes: outboundMinutes,
            date: outboundDate,
            hourlyRateEUR: hourlyRateEUR,
            vatPercent: vatPercent,
            weekdayDiscountEnabled: weekdayDiscountEnabled,
            prepaymentDiscount15To29Enabled:
                prepaymentDiscount15To29Enabled,
            prepaymentDiscount30PlusEnabled:
                prepaymentDiscount30PlusEnabled,
            calendar: calendar
        ) + legCost(
            minutes: returnMinutes,
            date: returnDate,
            hourlyRateEUR: hourlyRateEUR,
            vatPercent: vatPercent,
            weekdayDiscountEnabled: weekdayDiscountEnabled,
            prepaymentDiscount15To29Enabled:
                prepaymentDiscount15To29Enabled,
            prepaymentDiscount30PlusEnabled:
                prepaymentDiscount30PlusEnabled,
            calendar: calendar
        )
    }

    private static func legCost(
        minutes: Int,
        date: Date,
        hourlyRateEUR: Double,
        vatPercent: Double,
        weekdayDiscountEnabled: Bool,
        prepaymentDiscount15To29Enabled: Bool,
        prepaymentDiscount30PlusEnabled: Bool,
        calendar: Calendar
    ) -> Double {
        let prepaymentFactor: Double
        if prepaymentDiscount15To29Enabled {
            prepaymentFactor = 0.75
        } else if prepaymentDiscount30PlusEnabled {
            prepaymentFactor = 0.85
        } else {
            prepaymentFactor = 1
        }
        let weekday = (2...6).contains(
            calendar.component(.weekday, from: date)
        )
        let weekdayFactor = weekdayDiscountEnabled && weekday ? 0.95 : 1
        return CharterMath.commercialCost(
            minutes: minutes,
            hourlyRateEUR:
                hourlyRateEUR * prepaymentFactor * weekdayFactor
        ) * (1 + max(0, vatPercent) / 100)
    }
}

enum DestinationFinderService {
    struct Result {
        let matches: [DestinationFinderMatch]
        let unavailableWeatherCount: Int
        let incompleteRouteWeatherCount: Int
    }

    static func find(
        destinations: [Destination],
        origins: [AirportReference],
        criteria: DestinationFinderCriteria,
        aircraft: AircraftType,
        greenYellowMinutes: Int,
        orangeRedMinutes: Int,
        tankStopMinutes: Int,
        preTakeoffGroundMinutes: Int,
        postLandingGroundMinutes: Int,
        vatPercent: Double,
        weekdayDiscountEnabled: Bool,
        prepaymentDiscount15To29Enabled: Bool,
        prepaymentDiscount30PlusEnabled: Bool
    ) async -> Result {
        guard let origin = origins.first(where: {
            $0.icao == criteria.originICAO
        }) else {
            return Result(
                matches: [],
                unavailableWeatherCount: 0,
                incompleteRouteWeatherCount: 0
            )
        }

        let climb = AircraftProfileStore.climbPerformance(for: aircraft)
        let cruise = AircraftProfileStore.cruisePerformance(for: aircraft)
        let hourlyRateEUR = AircraftProfileStore.hourlyRate(for: aircraft)
        let preferredFuel = AircraftProfileStore.preferredFuel(for: aircraft)
        let approvedFuels = AircraftProfileStore.approvedFuels(for: aircraft)

        func fuelPrice(_ fuel: AircraftFuelType, at destination: Destination) -> Double? {
            switch fuel {
            case .avgas: return destination.avgasPricePerLiterEUR
            case .ul91: return destination.ul91PricePerLiterEUR
            case .ul94: return nil
            case .mogas: return destination.mogasPricePerLiterEUR
            }
        }

        func fuelIsAvailable(_ fuel: AircraftFuelType, at destination: Destination) -> Bool {
            switch fuel {
            case .avgas: return destination.avgasPricePerLiterEUR != nil
            case .ul91: return destination.ul91PricePerLiterEUR != nil
            case .ul94: return false
            case .mogas: return destination.mogasPricePerLiterEUR != nil
            }
        }

        let activeBaseRaw = UserDefaults.standard.string(
            forKey: BaseSettingsKey.activeBase
        ) ?? FlybookBase.lsvMainz.rawValue
        let activeBase = FlybookBase(rawValue: activeBaseRaw) ?? .lsvMainz
        let homeICAO = BaseProfileStore.profile(for: activeBase).homeAirportICAO
        let referenceFuelPrice: Double? = {
            if homeICAO == "EDFZ" {
                switch preferredFuel {
                case .avgas:
                    return UserDefaults.standard.object(forKey: FuelPriceSettingsKey.mainzAvgas) == nil
                        ? nil : UserDefaults.standard.double(forKey: FuelPriceSettingsKey.mainzAvgas)
                case .mogas:
                    return UserDefaults.standard.object(forKey: FuelPriceSettingsKey.mainzMogas) == nil
                        ? nil : UserDefaults.standard.double(forKey: FuelPriceSettingsKey.mainzMogas)
                case .ul91, .ul94: return nil
                }
            }
            guard let home = destinations.first(where: { $0.icao == homeICAO }) else { return nil }
            return fuelPrice(preferredFuel, at: home)
        }()

        func etopsStopCount(
            directNM: Double,
            departureElevationFeet: Double,
            arrivalElevationFeet: Double,
            enabled: Bool
        ) -> Int {
            guard enabled else { return 0 }
            for stopCount in 0...2 {
                let perLeg = FlightMath.adjustedPerLegMinutes(
                    directNM: directNM,
                    stopCount: stopCount,
                    headwindKnots: nil,
                    tankStopMinutes: tankStopMinutes,
                    cruiseGroundSpeedKnots:
                        aircraft.defaultCruiseGroundSpeedKnots,
                    climbDeparturePressureAltitudeFeet:
                        departureElevationFeet,
                    climbTargetPressureAltitudeFeet:
                        max(5000, arrivalElevationFeet),
                    climbPerformance: climb,
                    cruisePerformance: cruise,
                    preTakeoffGroundMinutes: preTakeoffGroundMinutes,
                    postLandingGroundMinutes: postLandingGroundMinutes
                )
                if !ETOPSScale.isRed(
                    travelMinutes: perLeg,
                    greenYellow: greenYellowMinutes,
                    orangeRed: orangeRedMinutes
                ) {
                    return stopCount
                }
            }
            return 2
        }

        let travelCandidates: [(Destination, Int, Int, Double, Int)] = destinations
            .compactMap { destination in
                let countryMatches = criteria.allowedCountryCodes?.contains(
                    destination.country.uppercased()
                ) ?? true
                guard destination.icao != origin.icao,
                      countryMatches,
                      DestinationFinderEvaluator.featuresMatch(
                          destinationFeatures: destination.features,
                          requiredFeatures: criteria.requiredFeatures
                      ),
                      DestinationFinderEvaluator.landingVoucherMatches(
                        icao: destination.icao,
                        flightDate: criteria.from,
                        required: criteria.requiresLandingVoucher
                      ),
                      (!criteria.requiresBicycleAtAirport
                        || DestinationFinderEvaluator.serviceIsAvailable(
                            destination.bikeDirect
                        )),
                      (!criteria.requiresRentalCarAtAirport
                        || DestinationFinderEvaluator.serviceIsAvailable(
                            destination.rentalCarDirect
                        )),
                      (!criteria.requiresApp2DriveAtAirport
                        || DestinationFinderEvaluator.serviceIsAvailable(
                            destination.app2DriveDirect
                        )),
                      destination.runwayM >= criteria.minimumRunwayLengthMeters,
                      destination.latitude != nil,
                      destination.longitude != nil,
                      (criteria.requiredFuelTypes.isEmpty
                        || criteria.requiredFuelTypes.contains(where: {
                            fuelIsAvailable($0, at: destination)
                        })),
                      (!criteria.requiresFuelAtOrBelowReferencePrice
                        || referenceFuelPrice.map { reference in
                            approvedFuels.contains(where: { fuel in
                                fuelIsAvailable(fuel, at: destination)
                                    && (fuelPrice(fuel, at: destination) ?? .infinity) <= reference
                            })
                        } == true)
                else { return nil }
                let directNM = AirportDistance.nauticalMiles(
                    from: origin,
                    to: destination
                )
                let selectedStops = etopsStopCount(
                    directNM: directNM,
                    departureElevationFeet: origin.elevationFeet,
                    arrivalElevationFeet: destination.elevationFeet,
                    enabled: criteria.appliesETOPS
                )
                let travelMinutes = FlightMath.adjustedMinutes(
                    directNM: directNM,
                    stopCount: selectedStops,
                    headwindKnots: nil,
                    tankStopMinutes: tankStopMinutes,
                    cruiseGroundSpeedKnots:
                        aircraft.defaultCruiseGroundSpeedKnots,
                    climbDeparturePressureAltitudeFeet: origin.elevationFeet,
                    climbTargetPressureAltitudeFeet: 5000,
                    climbPerformance: climb,
                    cruisePerformance: cruise,
                    preTakeoffGroundMinutes: preTakeoffGroundMinutes,
                    postLandingGroundMinutes: postLandingGroundMinutes
                )
                guard criteria.ignoresTravelTime
                    || (
                        travelMinutes >= criteria.minimumTravelMinutes
                            && travelMinutes <= criteria.maximumTravelMinutes
                    )
                else { return nil }

                let outboundPriceStops = etopsStopCount(
                    directNM: directNM,
                    departureElevationFeet: origin.elevationFeet,
                    arrivalElevationFeet: destination.elevationFeet,
                    enabled: criteria.priceAppliesETOPS
                )
                let returnPriceStops = etopsStopCount(
                    directNM: directNM,
                    departureElevationFeet: destination.elevationFeet,
                    arrivalElevationFeet: origin.elevationFeet,
                    enabled: criteria.priceAppliesETOPS
                )
                let outboundPriceMinutes = FlightMath.adjustedBlockMinutes(
                    directNM: directNM,
                    stopCount: outboundPriceStops,
                    headwindKnots: nil,
                    cruiseGroundSpeedKnots:
                        aircraft.defaultCruiseGroundSpeedKnots,
                    climbDeparturePressureAltitudeFeet: origin.elevationFeet,
                    climbTargetPressureAltitudeFeet: 5000,
                    climbPerformance: climb,
                    cruisePerformance: cruise,
                    preTakeoffGroundMinutes: preTakeoffGroundMinutes,
                    postLandingGroundMinutes: postLandingGroundMinutes
                )
                let returnPriceMinutes = FlightMath.adjustedBlockMinutes(
                    directNM: directNM,
                    stopCount: returnPriceStops,
                    headwindKnots: nil,
                    cruiseGroundSpeedKnots:
                        aircraft.defaultCruiseGroundSpeedKnots,
                    climbDeparturePressureAltitudeFeet:
                        destination.elevationFeet,
                    climbTargetPressureAltitudeFeet: 5000,
                    climbPerformance: climb,
                    cruisePerformance: cruise,
                    preTakeoffGroundMinutes: preTakeoffGroundMinutes,
                    postLandingGroundMinutes: postLandingGroundMinutes
                )
                let price = DestinationFinderPricing.roundTripCost(
                    outboundMinutes: outboundPriceMinutes,
                    returnMinutes: returnPriceMinutes,
                    outboundDate: criteria.from,
                    returnDate: criteria.until,
                    hourlyRateEUR: hourlyRateEUR,
                    vatPercent: vatPercent,
                    weekdayDiscountEnabled: weekdayDiscountEnabled,
                    prepaymentDiscount15To29Enabled:
                        prepaymentDiscount15To29Enabled,
                    prepaymentDiscount30PlusEnabled:
                        prepaymentDiscount30PlusEnabled
                )
                guard criteria.ignoresPrice
                    || price <= criteria.maximumRoundTripPriceEUR
                else { return nil }
                return (
                    destination,
                    travelMinutes,
                    selectedStops,
                    price,
                    max(outboundPriceStops, returnPriceStops)
                )
            }

        var unavailableFoehnCount = 0
        let foehnSamples: [AlpineFoehnPressureSample]?
        if !criteria.ignoresFoehn,
           travelCandidates.contains(where: {
               guard let latitude = $0.0.latitude,
                     let longitude = $0.0.longitude else { return false }
               return AlpineRegion.contains(
                   latitude: latitude,
                   longitude: longitude
               )
           }) {
            foehnSamples = try? await AlpineFoehnForecastService.shared.samples(
                from: criteria.from,
                until: criteria.until
            )
        } else {
            foehnSamples = nil
        }
        let airportFoehnCandidates = travelCandidates.filter {
            destination, _, _, _, _ in
            guard !criteria.ignoresFoehn,
                  let latitude = destination.latitude,
                  let longitude = destination.longitude,
                  AlpineRegion.contains(
                    latitude: latitude,
                    longitude: longitude
                  )
            else { return true }
            guard let foehnSamples else {
                unavailableFoehnCount += 1
                return false
            }
            let airport = AirportReference(
                icao: destination.icao,
                name: destination.name,
                latitude: latitude,
                longitude: longitude,
                elevationFeet: destination.elevationFeet,
                timeZone: DestinationTimeZone.value(
                    for: destination,
                    weatherTimeZone: nil
                )
            )
            guard let matches = AlpineFoehnEvaluator.airportMatches(
                samples: foehnSamples,
                airport: airport,
                from: criteria.from,
                until: criteria.until,
                maximumExclusive: criteria.maximumFoehnPressureDifferenceHPA
            ) else {
                unavailableFoehnCount += 1
                return false
            }
            return matches
        }

        // A shared ICON airport mesh serves both destination filters and the
        // route-weather pre-screening. Even with 133 destinations this stays
        // at a small number of serial batches instead of one heavy 18-point
        // corridor request per candidate.
        let weatherByICAO: [String: [DestinationFinderWeatherHour]]
        if criteria.requiresWeatherData || !criteria.ignoresRouteWeather {
            let candidateDestinations = airportFoehnCandidates.map { $0.0 }
            let candidateICAOs = Set(candidateDestinations.map(\.icao))
            let weatherDestinations = criteria.ignoresRouteWeather
                ? candidateDestinations
                : candidateDestinations + destinations.filter {
                    !candidateICAOs.contains($0.icao)
                }
            weatherByICAO = await DestinationFinderWeatherCache.shared.hours(
                for: weatherDestinations,
                from: criteria.from,
                until: criteria.until
            )
        } else {
            weatherByICAO = [:]
        }

        // Apply target weather before route weather. A destination that fails
        // the cheaper batch-based rules must never trigger route work.
        var unavailableTargetWeatherCount = 0
        let targetWeatherCandidates = airportFoehnCandidates.filter {
            destination, _, _, _, _ in
            guard criteria.requiresWeatherData else { return true }
            let hours = weatherByICAO[destination.icao]
            if hours == nil { unavailableTargetWeatherCount += 1 }
            let reference = AirportReference(
                icao: destination.icao,
                name: destination.name,
                latitude: destination.latitude ?? 0,
                longitude: destination.longitude ?? 0,
                elevationFeet: destination.elevationFeet,
                timeZone: DestinationTimeZone.value(
                    for: destination,
                    weatherTimeZone: nil
                )
            )
            return DestinationFinderEvaluator.weatherMatches(
                hours,
                criteria: criteria,
                destination: reference
            )
        }

        var filteredTravelCandidates = targetWeatherCandidates
        var unavailableRouteWeatherCount = 0
        var incompleteRouteWeatherICAOs: Set<String> = []
        if !criteria.ignoresRouteWeather {
            var routeMatches: [(Destination, Int, Int, Double, Int)] = []
            for candidate in targetWeatherCandidates {
                let destination = candidate.0
                guard let latitude = destination.latitude,
                      let longitude = destination.longitude
                else {
                    unavailableRouteWeatherCount += 1
                    incompleteRouteWeatherICAOs.insert(destination.icao)
                    routeMatches.append(candidate)
                    continue
                }
                let destinationReference = AirportReference(
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
                let risks = await RouteWeatherRiskService.shared.cachedRisks(
                    waypoints: [origin, destinationReference],
                    start: criteria.from,
                    end: criteria.from.addingTimeInterval(
                        Double(candidate.1) * 60
                    ),
                    cruiseAltitudeFeet: 5_000
                )
                switch DestinationFinderEvaluator.evaluateRouteWeather(
                    risks,
                    maximum: criteria.maximumRouteWeatherRisk
                ) {
                case .matches:
                    routeMatches.append(candidate)
                case .rejects:
                    break
                case .incomplete:
                    unavailableRouteWeatherCount += 1
                    incompleteRouteWeatherICAOs.insert(destination.icao)
                    routeMatches.append(candidate)
                }
            }
            filteredTravelCandidates = routeMatches
        }

        var matches = filteredTravelCandidates.map {
            destination, travelMinutes, stopCount, price, priceStops in
            DestinationFinderMatch(
                destinationICAO: destination.icao,
                destinationName: destination.name,
                travelMinutes: travelMinutes,
                stopCount: stopCount,
                roundTripPriceEUR: price,
                priceStopCount: priceStops,
                weatherWasChecked:
                    !incompleteRouteWeatherICAOs.contains(destination.icao)
            )
        }
        matches.sort {
            if $0.travelMinutes == $1.travelMinutes {
                return $0.destinationName < $1.destinationName
            }
            return $0.travelMinutes < $1.travelMinutes
        }
        return Result(
            matches: matches,
            unavailableWeatherCount:
                unavailableFoehnCount
                    + unavailableTargetWeatherCount,
            incompleteRouteWeatherCount: unavailableRouteWeatherCount
        )
    }
}

private enum DestinationFinderError: Error {
    case invalidRequest
    case serverError
}

private struct DestinationFinderAPIResponse: Decodable {
    let timezone: String
    let hourly: Hourly

    struct Hourly: Decodable {
        let time: [String]
        let temperature2m: [Double?]
        let dewPoint2m: [Double?]
        let precipitation: [Double?]
        let cloudCover: [Double?]
        let cloudCoverLow: [Double?]
        let visibility: [Double?]
        let windSpeed10m: [Double?]
        let windGusts10m: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case dewPoint2m = "dew_point_2m"
            case precipitation
            case cloudCover = "cloud_cover"
            case cloudCoverLow = "cloud_cover_low"
            case visibility
            case windSpeed10m = "wind_speed_10m"
            case windGusts10m = "wind_gusts_10m"
        }
    }
}

actor DestinationFinderWeatherCache {
    static let shared = DestinationFinderWeatherCache()
    private struct CacheEntry: Codable {
        let retrievedAt: Date
        let hours: [DestinationFinderWeatherHour]
    }

    private let nearTermLifetime: TimeInterval = 30 * 60
    private let futureLifetime: TimeInterval = 3 * 60 * 60
    private let maximumIndividualFallbacksPerRun = 12
    private var cache: [String: CacheEntry] = [:]
    private var knownDestinations: [Destination] = []
    private var didLoadPersistentCache = false

    func register(destinations: [Destination]) {
        loadPersistentCacheIfNeeded()
        knownDestinations = destinations.filter {
            $0.latitude != nil && $0.longitude != nil
        }
    }

    func cachedHour(
        nearestToLatitude latitude: Double,
        longitude: Double,
        instant: Date
    ) -> DestinationFinderWeatherHour? {
        loadPersistentCacheIfNeeded()
        let candidates = knownDestinations.compactMap { destination
            -> (Double, [DestinationFinderWeatherHour])? in
            guard let destinationLatitude = destination.latitude,
                  let destinationLongitude = destination.longitude,
                  let cached = cache[destination.icao],
                  cacheIsFresh(cached, for: instant)
            else { return nil }
            let distance = Self.distanceNM(
                latitude,
                longitude,
                destinationLatitude,
                destinationLongitude
            )
            return (distance, cached.hours)
        }
        guard let nearest = candidates.min(by: { $0.0 < $1.0 }),
              nearest.0 <= 60,
              let hour = nearest.1.min(by: {
                  abs($0.instant.timeIntervalSince(instant))
                      < abs($1.instant.timeIntervalSince(instant))
              }),
              abs(hour.instant.timeIntervalSince(instant)) <= 90 * 60
        else { return nil }
        return hour
    }

    private static func distanceNM(
        _ latitude1: Double,
        _ longitude1: Double,
        _ latitude2: Double,
        _ longitude2: Double
    ) -> Double {
        let lat1 = latitude1 * .pi / 180
        let lat2 = latitude2 * .pi / 180
        let deltaLat = (latitude2 - latitude1) * .pi / 180
        let deltaLon = (longitude2 - longitude1) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * 3440.065 * atan2(sqrt(a), sqrt(1 - a))
    }

    func hours(
        for destinations: [Destination],
        from: Date,
        until: Date
    ) async -> [String: [DestinationFinderWeatherHour]] {
        loadPersistentCacheIfNeeded()
        let eligible = destinations.filter {
            $0.latitude != nil && $0.longitude != nil
        }
        let missing = eligible.filter {
            guard let cached = cache[$0.icao],
                  cacheIsFresh(cached, for: from)
            else { return true }
            return !Self.covers(cached.hours, from: from, until: until)
        }

        // Kleine serielle Batches sind auch bei kurzem, schlechtem Empfang
        // robuster als viele parallele Einzelanfragen.
        var openMeteoWasThrottled = false
        for start in stride(from: 0, to: missing.count, by: 10) {
            guard !Task.isCancelled else { break }
            guard !openMeteoWasThrottled else { break }
            let end = min(start + 10, missing.count)
            let batch = Array(missing[start..<end])
            do {
                try await fetchBatch(batch, from: from, until: until)
            } catch is OpenMeteoAccessError {
                openMeteoWasThrottled = true
            } catch {
                // Open-Meteo kann einen kompletten Batch etwa bei erreichtem
                // Tageslimit ablehnen. Die noch offenen Ziele werden danach
                // gesammelt über den vorhandenen MET-Norway-Pfad geladen.
            }
        }

        let unresolved = eligible.filter {
            guard let cached = cache[$0.icao],
                  cacheIsFresh(cached, for: from)
            else { return true }
            return !Self.covers(cached.hours, from: from, until: until)
        }
        // Never replace a failed shared batch with an unbounded request fanout
        // to another provider. Candidates arrive first, so the small fallback
        // budget helps the most relevant destinations before the route mesh.
        let fallbackCandidates = Array(
            unresolved.prefix(maximumIndividualFallbacksPerRun)
        )
        for start in stride(from: 0, to: fallbackCandidates.count, by: 4) {
            guard !Task.isCancelled else { break }
            let end = min(start + 4, fallbackCandidates.count)
            let batch = Array(fallbackCandidates[start..<end])
            let fallbacks = await withTaskGroup(
                of: (String, [DestinationFinderWeatherHour])?.self,
                returning: [(String, [DestinationFinderWeatherHour])].self
            ) { group in
                for destination in batch {
                    group.addTask {
                        guard let latitude = destination.latitude,
                              let longitude = destination.longitude
                        else { return nil }
                        let reference = AirportReference(
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
                        do {
                            let forecast: EDFZForecast
                            do {
                                forecast = try await EDFZWeatherService.shared
                                    .metNorwayForecast(airport: reference)
                            } catch {
                                forecast = try await DWDMOSMIXService.shared
                                    .forecast(airport: reference)
                            }
                            let hours = Self.fallbackHours(
                                forecast,
                                from: from,
                                until: until
                            )
                            guard Self.covers(
                                hours,
                                from: from,
                                until: until
                            ) else { return nil }
                            return (destination.icao, hours)
                        } catch {
                            return nil
                        }
                    }
                }
                var values: [(String, [DestinationFinderWeatherHour])] = []
                for await value in group {
                    if let value { values.append(value) }
                }
                return values
            }
            for (icao, hours) in fallbacks {
                cache[icao] = CacheEntry(retrievedAt: Date(), hours: hours)
            }
        }

        savePersistentCache()

        return Dictionary(
            uniqueKeysWithValues: eligible.compactMap { destination in
                guard let entry = cache[destination.icao],
                      cacheIsFresh(entry, for: from),
                      Self.covers(entry.hours, from: from, until: until)
                else { return nil }
                return (destination.icao, entry.hours)
            }
        )
    }

    private func cacheIsFresh(_ entry: CacheEntry, for instant: Date) -> Bool {
        let lifetime = instant.timeIntervalSinceNow > 24 * 60 * 60
            ? futureLifetime
            : nearTermLifetime
        return Date().timeIntervalSince(entry.retrievedAt) < lifetime
    }

    private func loadPersistentCacheIfNeeded() {
        guard !didLoadPersistentCache else { return }
        didLoadPersistentCache = true
        guard let data = try? Data(contentsOf: persistentCacheURL()),
              let saved = try? JSONDecoder().decode(
                  [String: CacheEntry].self,
                  from: data
              )
        else { return }
        let oldestUsefulDate = Date().addingTimeInterval(-futureLifetime)
        cache = saved.filter { $0.value.retrievedAt >= oldestUsefulDate }
    }

    private func savePersistentCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: persistentCacheURL(), options: .atomic)
    }

    private func persistentCacheURL() -> URL {
        let root = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let directory = root
            .appendingPathComponent("Flybook Europe", isDirectory: true)
            .appendingPathComponent("WeatherCache", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("destination-finder.json")
    }

    private static func covers(
        _ hours: [DestinationFinderWeatherHour],
        from: Date,
        until: Date
    ) -> Bool {
        guard let first = hours.first?.instant,
              let last = hours.last?.instant
        else { return false }
        return first <= from.addingTimeInterval(60 * 60)
            && last >= until.addingTimeInterval(-60 * 60)
    }

    private static func fallbackHours(
        _ forecast: EDFZForecast,
        from: Date,
        until: Date
    ) -> [DestinationFinderWeatherHour] {
        guard until >= from else { return [] }
        let first = Calendar.current.dateInterval(of: .hour, for: from)?.start
            ?? from
        let last = Calendar.current.dateInterval(of: .hour, for: until)?.end
            ?? until
        var instant = first
        var result: [DestinationFinderWeatherHour] = []
        while instant <= last {
            if let sample = forecast.sample(nearestTo: instant) {
                let precipitation: Double?
                switch sample.weatherCode {
                case 61, 67, 71, 95:
                    precipitation = 0.1
                case .some:
                    precipitation = 0
                case nil:
                    precipitation = nil
                }
                result.append(
                    DestinationFinderWeatherHour(
                        instant: instant,
                        temperatureCelsius: sample.temperatureCelsius,
                        steadyWindKnots: sample.windSpeedKnots,
                        gustKnots: sample.windGustKnots,
                        precipitationMillimeters: precipitation,
                        totalCloudCoverPercent: sample.totalCloudCoverPercent,
                        visibilityMeters: sample.visibilityMeters,
                        lowCloudCoverPercent: sample.lowCloudCoverPercent,
                        dewPointCelsius: sample.dewPointCelsius
                    )
                )
            }
            instant = instant.addingTimeInterval(60 * 60)
        }
        return result
    }

    private func fetchBatch(
        _ destinations: [Destination],
        from: Date,
        until: Date
    ) async throws {
        let responses = try await fetch(
            destinations,
            from: from,
            until: until
        )
        guard responses.count == destinations.count else {
            throw DestinationFinderError.serverError
        }
        for (destination, response) in zip(destinations, responses) {
            cache[destination.icao] = CacheEntry(
                retrievedAt: Date(),
                hours: transform(response, destination: destination)
            )
        }
    }

    private func fetch(
        _ destinations: [Destination],
        from: Date,
        until: Date
    ) async throws
        -> [DestinationFinderAPIResponse]
    {
        for route in ICONSeamlessAccessRoute.allCases {
            do {
                return try await fetch(
                    destinations,
                    from: from,
                    until: until,
                    route: route
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch is OpenMeteoAccessError {
                throw OpenMeteoAccessError.rateLimited
            } catch {
                continue
            }
        }
        throw DestinationFinderError.serverError
    }

    private func fetch(
        _ destinations: [Destination],
        from: Date,
        until: Date,
        route: ICONSeamlessAccessRoute
    ) async throws -> [DestinationFinderAPIResponse] {
        let latitudes = destinations.compactMap(\.latitude)
            .map { String($0) }.joined(separator: ",")
        let longitudes = destinations.compactMap(\.longitude)
            .map { String($0) }.joined(separator: ",")
        guard !latitudes.isEmpty, !longitudes.isEmpty
        else { throw DestinationFinderError.invalidRequest }
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let queryItems = [
            URLQueryItem(name: "latitude", value: latitudes),
            URLQueryItem(name: "longitude", value: longitudes),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(
                name: "start_date",
                value: dateFormatter.string(from: from)
            ),
            URLQueryItem(
                name: "end_date",
                value: dateFormatter.string(from: until)
            ),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(name: "hourly", value: [
                "temperature_2m", "dew_point_2m", "precipitation",
                "cloud_cover", "cloud_cover_low", "visibility",
                "wind_speed_10m", "wind_gusts_10m"
            ].joined(separator: ","))
        ]
        guard let url = route.url(queryItems: queryItems) else {
            throw DestinationFinderError.invalidRequest
        }
        let (data, response) = try await FlightNetwork.openMeteoData(
            from: url,
            priority: .low
        )
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { throw DestinationFinderError.serverError }
        if destinations.count == 1 {
            return [try JSONDecoder().decode(
                DestinationFinderAPIResponse.self,
                from: data
            )]
        }
        return try JSONDecoder().decode(
            [DestinationFinderAPIResponse].self,
            from: data
        )
    }

    private func transform(
        _ decoded: DestinationFinderAPIResponse,
        destination: Destination
    ) -> [DestinationFinderWeatherHour] {
        let timezone = TimeZone(identifier: decoded.timezone)
            ?? DestinationTimeZone.value(
                for: destination,
                weatherTimeZone: decoded.timezone
            )
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = timezone
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return decoded.hourly.time.indices.compactMap { index in
            guard let instant = parser.date(from: decoded.hourly.time[index])
            else { return nil }
            return DestinationFinderWeatherHour(
                instant: instant,
                temperatureCelsius: decoded.hourly.temperature2m[safe: index] ?? nil,
                steadyWindKnots: decoded.hourly.windSpeed10m[safe: index] ?? nil,
                gustKnots: decoded.hourly.windGusts10m[safe: index] ?? nil,
                precipitationMillimeters: decoded.hourly.precipitation[safe: index] ?? nil,
                totalCloudCoverPercent: decoded.hourly.cloudCover[safe: index] ?? nil,
                visibilityMeters: decoded.hourly.visibility[safe: index] ?? nil,
                lowCloudCoverPercent: decoded.hourly.cloudCoverLow[safe: index] ?? nil,
                dewPointCelsius: decoded.hourly.dewPoint2m[safe: index] ?? nil
            )
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct DestinationFinderView: View {
    let destinations: [Destination]
    let origins: [AirportReference]
    let onApply: ([DestinationFinderMatch]) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AircraftSettingsKey.selectedAircraft)
    private var selectedAircraftRaw = AircraftType.a211.rawValue
    @AppStorage(ETOPSSettingsKey.activeUser)
    private var activeUserRaw = FlybookUser.stephan.rawValue
    @AppStorage(CalculationSettingsKey.tankStopMinutes)
    private var tankStopMinutes = CalculationSettings.defaultTankStopMinutes
    @AppStorage(CalculationSettingsKey.preTakeoffGroundMinutes)
    private var preTakeoffGroundMinutes = CalculationSettings.defaultPreTakeoffGroundMinutes
    @AppStorage(CalculationSettingsKey.postLandingGroundMinutes)
    private var postLandingGroundMinutes = CalculationSettings.defaultPostLandingGroundMinutes
    @AppStorage(CalculationSettingsKey.vatPercent)
    private var vatPercent = CalculationSettings.defaultVATPercent
    @AppStorage(CalculationSettingsKey.weekdayDiscountEnabled)
    private var weekdayDiscountEnabled = CalculationSettings.defaultWeekdayDiscountEnabled
    @AppStorage(CalculationSettingsKey.prepaymentDiscount15To29Enabled)
    private var prepaymentDiscount15To29Enabled = CalculationSettings.defaultPrepaymentDiscount15To29Enabled
    @AppStorage(CalculationSettingsKey.prepaymentDiscount30PlusEnabled)
    private var prepaymentDiscount30PlusEnabled = CalculationSettings.defaultPrepaymentDiscount30PlusEnabled

    @State private var originICAO: String
    @State private var from: Date
    @State private var until: Date
    @State private var minimumTravelHours = 0.0
    @State private var maximumTravelHours = 3.0
    @State private var ignoresTravelTime = false
    @State private var appliesETOPS = true
    @State private var maximumRoundTripPrice = 1_000.0
    @State private var ignoresPrice = true
    @State private var priceAppliesETOPS = true
    @State private var requiresLandingVoucher = false
    @State private var requiredFeatures: Set<DestinationFeature> = [
        .beachSea, .lakeNature, .mountainHiking, .wellness
    ]
    @State private var requiresBicycleAtAirport = false
    @State private var requiresRentalCarAtAirport = false
    @State private var requiresApp2DriveAtAirport = false
    @State private var minimumRunwayLength = 300.0
    @State private var selectedCountryCodes: Set<String>
    @State private var requiredFuelTypes: Set<AircraftFuelType> = []
    @State private var requiresFuelAtOrBelowReferencePrice = false
    @State private var minimumTemperature = 10.0
    @State private var ignoresMinimumTemperature = false
    @State private var maximumTemperature = 40.0
    @State private var ignoresMaximumTemperature = true
    @State private var maximumWind = 15.0
    @State private var ignoresWind = false
    @State private var maximumGust = 25.0
    @State private var ignoresGusts = true
    @State private var maximumFoehnPressureDifference = 2.0
    @State private var ignoresFoehn = true
    @State private var minimumWeather = DestinationFinderMinimumWeather.vfr
    @State private var ignoresMinimumWeather = false
    @State private var usesMinimumWeatherCoverageRule = true
    @State private var requiresCloudless = false
    @State private var requiresScatteredCloudCoverage = false
    @State private var requiresRainFree = false
    @State private var requiresRainFreeCoverage = false
    @State private var daylightOnly = true
    @State private var maximumRouteWeatherRisk = RouteWeatherRisk.green
    @State private var ignoresRouteWeather = true
    @State private var isFiltering = false
    @State private var hasAppliedFilter = false
    @State private var matches: [DestinationFinderMatch] = []
    @State private var unavailableWeatherCount = 0
    @State private var incompleteRouteWeatherCount = 0
    @State private var filterUserRaw = ""
    @State private var originSearchText = ""
    @FocusState private var originSearchIsFocused: Bool

    init(
        destinations: [Destination],
        origins: [AirportReference],
        onApply: @escaping ([DestinationFinderMatch]) -> Void,
        onClear: @escaping () -> Void
    ) {
        let session = DestinationFinderSession.shared
        self.destinations = destinations
        self.origins = origins
        self.onApply = onApply
        self.onClear = onClear
        let allCountryCodes = Set(
            destinations.map { $0.country.uppercased() } + ["ES", "PT"]
        )
        _originICAO = State(initialValue: origins.contains(where: {
            $0.icao == session.originICAO
        }) ? session.originICAO : (origins.first?.icao ?? "EDFZ"))
        _from = State(initialValue: session.from)
        _until = State(initialValue: session.until)
        _minimumTravelHours = State(initialValue: session.minimumTravelHours)
        _maximumTravelHours = State(initialValue: session.maximumTravelHours)
        _ignoresTravelTime = State(initialValue: session.ignoresTravelTime)
        _appliesETOPS = State(initialValue: session.appliesETOPS)
        _maximumRoundTripPrice = State(initialValue: session.maximumRoundTripPrice)
        _ignoresPrice = State(initialValue: session.ignoresPrice)
        _priceAppliesETOPS = State(initialValue: session.priceAppliesETOPS)
        _requiresLandingVoucher = State(initialValue: session.requiresLandingVoucher)
        _requiredFeatures = State(initialValue: session.requiredFeatures)
        _requiresBicycleAtAirport = State(initialValue: session.requiresBicycleAtAirport)
        _requiresRentalCarAtAirport = State(initialValue: session.requiresRentalCarAtAirport)
        _requiresApp2DriveAtAirport = State(initialValue: session.requiresApp2DriveAtAirport)
        _minimumRunwayLength = State(initialValue: session.minimumRunwayLength)
        _selectedCountryCodes = State(initialValue: session.selectedCountryCodes ?? allCountryCodes)
        _requiredFuelTypes = State(initialValue: session.requiredFuelTypes)
        _requiresFuelAtOrBelowReferencePrice = State(initialValue: session.requiresFuelAtOrBelowReferencePrice)
        _minimumTemperature = State(initialValue: session.minimumTemperature)
        _ignoresMinimumTemperature = State(initialValue: session.ignoresMinimumTemperature)
        _maximumTemperature = State(initialValue: session.maximumTemperature)
        _ignoresMaximumTemperature = State(initialValue: session.ignoresMaximumTemperature)
        _maximumWind = State(initialValue: session.maximumWind)
        _ignoresWind = State(initialValue: session.ignoresWind)
        _maximumGust = State(initialValue: session.maximumGust)
        _ignoresGusts = State(initialValue: session.ignoresGusts)
        _maximumFoehnPressureDifference = State(
            initialValue: session.maximumFoehnPressureDifference
        )
        _ignoresFoehn = State(initialValue: session.ignoresFoehn)
        _minimumWeather = State(initialValue: session.minimumWeather)
        _ignoresMinimumWeather = State(initialValue: session.ignoresMinimumWeather)
        _usesMinimumWeatherCoverageRule = State(
            initialValue: session.usesMinimumWeatherCoverageRule
        )
        _requiresCloudless = State(initialValue: session.requiresCloudless)
        _requiresScatteredCloudCoverage = State(
            initialValue: session.requiresScatteredCloudCoverage
        )
        _requiresRainFree = State(initialValue: session.requiresRainFree)
        _requiresRainFreeCoverage = State(
            initialValue: session.requiresRainFreeCoverage
        )
        _daylightOnly = State(initialValue: session.daylightOnly)
        _maximumRouteWeatherRisk = State(initialValue: session.maximumRouteWeatherRisk)
        _ignoresRouteWeather = State(initialValue: session.ignoresRouteWeather)
        _filterUserRaw = State(initialValue: session.filterUserRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DESTINATION FINDER")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)
                Spacer()
                if isFiltering { ProgressView().controlSize(.small) }
                Button("Schließen") { dismiss() }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    periodSection
                    countrySection
                    flightAndPriceSection
                    featureSection
                    mobilitySection
                    runwaySection
                    fuelSection
                    weatherSection
                    flightConditionsSection
                    routeWeatherSection
                    resultSection
                }
                .padding(.trailing, 6)
            }

            HStack {
                Button("Filter zurücksetzen") {
                    onClear()
                    resetFilters()
                }
                .disabled(isFiltering)

                Spacer()

                Button("Filter anwenden") { applyFilter() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isFiltering || until <= from)
            }
        }
        .padding(24)
        .frame(width: 800, height: 900)
        .onAppear {
            if filterUserRaw.isEmpty { filterUserRaw = activeUserRaw }
            synchronizeOriginSearchText()
        }
        .onDisappear { saveSession() }
        .task {
            await LandingVoucherBook.refreshIfNeeded()
        }
        .onChange(of: minimumTemperature) { value in
            if value > maximumTemperature { maximumTemperature = value }
        }
        .onChange(of: maximumTemperature) { value in
            if value < minimumTemperature { minimumTemperature = value }
        }
    }

    private var periodSection: some View {
        filterGroup(title: "NUTZER & ZEITRAUM", symbol: "person.crop.circle") {
            HStack {
                Text("Filter für")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)
                    .frame(width: 135, alignment: .leading)
                Picker("Nutzer", selection: $filterUserRaw) {
                    ForEach(FlybookUser.allCases) { user in
                        Text(user.rawValue).tag(user.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                Spacer()
            }
            HStack(spacing: 8) {
                periodButton("Morgen") { setWholeDay(offset: 1) }
                periodButton("Übermorgen") { setWholeDay(offset: 2) }
                periodButton("Nächste 48 Stunden") { setRollingHours(48) }
                periodButton("Nächste 72 Stunden") { setRollingHours(72) }
                periodButton("Kommende 4 Tage") { setComingFourDays() }
            }
            HStack(spacing: 12) {
                DatePicker("Von", selection: $from)
                DatePicker("Bis", selection: $until)
            }
        }
    }

    private var flightAndPriceSection: some View {
        filterGroup(title: "FLUG & PREIS", symbol: "airplane") {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 11) {
            GridRow {
                criterionLabel("Abflugort")
                originSearchField
                Color.clear.frame(width: 130)
            }
            travelTimeRangeRow
            sliderRow(
                title: "Max. Gesamtpreis",
                value: $maximumRoundTripPrice,
                range: 0...2000,
                step: 25,
                valueText: maximumRoundTripPrice.formatted(
                    .currency(code: "EUR")
                        .locale(Locale(identifier: "de_DE"))
                        .precision(.fractionLength(0))
                ),
                trailing: AnyView(
                    HStack(spacing: 10) {
                        Toggle("ETOPS-PIPI", isOn: $priceAppliesETOPS)
                            .toggleStyle(.checkbox)
                        Toggle("Ignorieren", isOn: $ignoresPrice)
                            .toggleStyle(.checkbox)
                    }
                )
            )
            GridRow {
                criterionLabel("Lande-Gutschein")
                HStack(spacing: 10) {
                    Button {
                        requiresLandingVoucher.toggle()
                    } label: {
                        Label(
                            "Gutschein \(LandingVoucherBook.yearLabel)",
                            systemImage: "book.closed.fill"
                        )
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(
                        requiresLandingVoucher
                            ? Color.orange
                            : FlybookColor.blue.opacity(0.25)
                    )
                    .accessibilityValue(
                        requiresLandingVoucher ? "Aktiv" : "Inaktiv"
                    )

                    Text(requiresLandingVoucher ? "nur Teilnehmer" : "aus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FlybookColor.muted)
                }
                .frame(width: 350, alignment: .leading)

                Text("Landegut.de · Flugjahr")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlybookColor.muted)
                    .frame(width: 210, alignment: .leading)
            }
        }
        }
    }

    private var originSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FlybookColor.muted)
            TextField("ICAO oder Airportname", text: $originSearchText)
                .textFieldStyle(.plain)
                .focused($originSearchIsFocused)
                .onSubmit { selectTypedOrigin() }
                .onChange(of: originSearchText) { value in
                    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        .uppercased()
                    if let airport = origins.first(where: {
                        $0.icao.uppercased() == normalized
                    }) {
                        selectOrigin(airport)
                    }
                }
            Menu {
                ForEach(origins) { airport in
                    Button("\(airport.icao) · \(airport.name)") {
                        selectOrigin(airport)
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 9)
        .frame(width: 350, height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(FlybookColor.line, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            if originSearchIsFocused,
               normalizedOriginSearch.count >= 3,
               !originSearchSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(originSearchSuggestions) { airport in
                        Button {
                            selectOrigin(airport)
                            originSearchIsFocused = false
                        } label: {
                            HStack(spacing: 8) {
                                Text(airport.icao)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .frame(width: 48, alignment: .leading)
                                Text(airport.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .foregroundStyle(FlybookColor.navy)
                            .padding(.horizontal, 9)
                            .frame(height: 29)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 5)
                .frame(width: 350)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .shadow(color: .black.opacity(0.20), radius: 8, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(FlybookColor.line, lineWidth: 1)
                )
                .offset(y: 32)
                .zIndex(20)
            }
        }
        .zIndex(20)
        .help("Airport wählen oder ab drei Zeichen nach ICAO beziehungsweise Name suchen")
    }

    private var normalizedOriginSearch: String {
        originSearchText
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var originSearchSuggestions: [AirportReference] {
        let query = normalizedOriginSearch
        guard query.count >= 3 else { return [] }
        return origins.filter { airport in
            "\(airport.icao) \(airport.name)"
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .contains(query)
        }
        .prefix(8)
        .map { $0 }
    }

    private func selectTypedOrigin() {
        guard let airport = originSearchSuggestions.first else { return }
        selectOrigin(airport)
        originSearchIsFocused = false
    }

    private func selectOrigin(_ airport: AirportReference) {
        originICAO = airport.icao
        originSearchText = "\(airport.icao) · \(airport.name)"
    }

    private func synchronizeOriginSearchText() {
        guard let airport = origins.first(where: { $0.icao == originICAO }) else { return }
        originSearchText = "\(airport.icao) · \(airport.name)"
    }

    private var countrySection: some View {
        filterGroup(title: "LÄNDER", symbol: "globe.europe.africa.fill") {
            HStack(spacing: 8) {
                Button("Alle auswählen") {
                    selectedCountryCodes = Set(availableCountryCodes)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Keins auswählen") {
                    selectedCountryCodes.removeAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
                Text("\(selectedCountryCodes.count) von \(availableCountryCodes.count)")
                    .font(.caption.bold())
                    .foregroundStyle(FlybookColor.muted)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4),
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(availableCountryCodes, id: \.self) { code in
                    Toggle(isOn: countryBinding(code)) {
                        Text("\(countryFlag(code))  \(countryName(code))")
                            .lineLimit(1)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var availableCountryCodes: [String] {
        Set(destinations.map { $0.country.uppercased() } + ["ES", "PT"])
            .sorted { countryName($0) < countryName($1) }
    }

    private func countryBinding(_ code: String) -> Binding<Bool> {
        Binding(
            get: { selectedCountryCodes.contains(code) },
            set: { enabled in
                if enabled { selectedCountryCodes.insert(code) }
                else { selectedCountryCodes.remove(code) }
            }
        )
    }

    private func countryName(_ code: String) -> String {
        [
            "AT": "Österreich", "BE": "Belgien", "CH": "Schweiz",
            "CZ": "Tschechien", "DE": "Deutschland", "DK": "Dänemark",
            "ES": "Spanien", "FR": "Frankreich", "GB": "Großbritannien",
            "GG": "Guernsey", "HR": "Kroatien", "IT": "Italien",
            "JE": "Jersey", "NL": "Niederlande", "PL": "Polen",
            "PT": "Portugal", "SE": "Schweden", "SI": "Slowenien"
        ][code] ?? code
    }

    private func countryFlag(_ code: String) -> String {
        let scalars = code.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value)
        }
        return scalars.count == 2
            ? String(String.UnicodeScalarView(scalars))
            : code
    }

    private var featureSection: some View {
        filterGroup(title: "MERKMALE", symbol: "square.grid.2x2") {
            Text("Keine Auswahl zeigt alle Ziele. Mehrere Haken werden als ODER-Filter ausgewertet.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                alignment: .leading,
                spacing: 9
            ) {
                ForEach(DestinationFeature.finderCases) { feature in
                    Toggle(isOn: featureBinding(feature)) {
                        Label(feature.title, systemImage: feature.symbol)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private func featureBinding(_ feature: DestinationFeature) -> Binding<Bool> {
        Binding(
            get: { requiredFeatures.contains(feature) },
            set: { enabled in
                if enabled {
                    requiredFeatures.insert(feature)
                } else {
                    requiredFeatures.remove(feature)
                }
            }
        )
    }

    private var mobilitySection: some View {
        filterGroup(title: "MOBILITÄT AM PLATZ", symbol: "car.fill") {
            HStack(spacing: 28) {
                Toggle("Fahrrad am Platz", isOn: $requiresBicycleAtAirport)
                    .toggleStyle(.checkbox)
                Toggle("Mietwagen am Platz", isOn: $requiresRentalCarAtAirport)
                    .toggleStyle(.checkbox)
                Toggle("app2drive am Platz", isOn: $requiresApp2DriveAtAirport)
                    .toggleStyle(.checkbox)
                Spacer()
            }
            Text("Aktivierte Merkmale müssen am Flugplatz als verfügbar hinterlegt sein.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var runwaySection: some View {
        filterGroup(title: "PISTE", symbol: "road.lanes") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                sliderRow(
                    title: "Min. Pistenlänge",
                    value: $minimumRunwayLength,
                    range: 300...1500,
                    step: 50,
                    valueText: minimumRunwayLength >= 1500
                        ? "1.500 m+"
                        : "\(Int(minimumRunwayLength)) m"
                )
            }
            Text("Es zählt die längste hinterlegte Bahn. 1.500 m+ schließt alle längeren Bahnen ein.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var fuelSection: some View {
        filterGroup(title: "KRAFTSTOFF", symbol: "fuelpump.fill") {
            HStack(spacing: 22) {
                fuelToggle(.avgas)
                fuelToggle(.ul91)
                fuelToggle(.mogas)
                Spacer()
            }

            Toggle(
                "Preis gleich oder niedriger als Referenzbasis",
                isOn: $requiresFuelAtOrBelowReferencePrice
            )
            .toggleStyle(.checkbox)
            .help("Vergleicht den bevorzugten Kraftstoff des aktiven Flugzeugs an der Heimatbasis mit allen am Ziel verfügbaren und für das Flugzeug zugelassenen Kraftstoffsorten.")

            Text("Keine Sortenauswahl filtert nicht nach Verfügbarkeit. Mehrere Sorten werden als ODER-Auswahl behandelt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func fuelToggle(_ fuel: AircraftFuelType) -> some View {
        Toggle(fuel.rawValue, isOn: Binding(
            get: { requiredFuelTypes.contains(fuel) },
            set: { enabled in
                if enabled { requiredFuelTypes.insert(fuel) }
                else { requiredFuelTypes.remove(fuel) }
            }
        ))
        .toggleStyle(.checkbox)
    }

    private var weatherSection: some View {
        filterGroup(
            title: "TEMPERATUR, NIEDERSCHLAG & WIND",
            symbol: "cloud.sun.fill"
        ) {
            Toggle("Tagsüber", isOn: $daylightOnly)
                .toggleStyle(.checkbox)
                .help(
                    "Aktiv: Regeln gelten nur zwischen Sonnenaufgang und Sonnenuntergang am Ziel. Inaktiv: Regeln gelten für den gesamten oben gewählten Zeitraum."
                )
            Text(
                daylightOnly
                    ? "Diese Regeln gelten nur zwischen Sonnenaufgang und Sonnenuntergang."
                    : "Diese Regeln gelten für den gesamten oben gewählten Zeitraum."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 11) {
                sliderRow(
                    title: "Mindesttemperatur",
                    value: $minimumTemperature,
                    range: -10...40,
                    step: 1,
                    valueText: "\(Int(minimumTemperature)) °C",
                    trailing: AnyView(
                        Toggle("Ignorieren", isOn: $ignoresMinimumTemperature)
                            .toggleStyle(.checkbox)
                    ),
                    colors: temperatureScaleColors
                )
                sliderRow(
                    title: "Maximale Temperatur",
                    value: $maximumTemperature,
                    range: -10...40,
                    step: 1,
                    valueText: "\(Int(maximumTemperature)) °C",
                    trailing: AnyView(
                        Toggle("Ignorieren", isOn: $ignoresMaximumTemperature)
                            .toggleStyle(.checkbox)
                    ),
                    colors: temperatureScaleColors
                )
                GridRow {
                    Color.clear.frame(width: 135, height: 1)
                    HStack(spacing: 20) {
                        Toggle("Regenfrei", isOn: Binding(
                            get: { requiresRainFree },
                            set: { enabled in
                                requiresRainFree = enabled
                                if enabled { requiresRainFreeCoverage = false }
                            }
                        ))
                            .toggleStyle(.checkbox)
                            .frame(width: 110, alignment: .leading)
                            .help("Schließt Ziele aus, sobald in einer geprüften Stunde mindestens 0,1 mm Niederschlag vorhergesagt ist.")
                        Toggle("66 % regenfrei", isOn: Binding(
                            get: { requiresRainFreeCoverage },
                            set: { enabled in
                                requiresRainFreeCoverage = enabled
                                if enabled { requiresRainFree = false }
                            }
                        ))
                            .toggleStyle(.checkbox)
                            .help(
                                daylightOnly
                                    ? "Pro Kalendertag am Ziel müssen mindestens 66 % der Tageslichtstunden weniger als 0,1 mm Niederschlag haben."
                                    : "Pro Kalendertag am Ziel müssen mindestens 66 % der Stunden im gewählten Zeitraum weniger als 0,1 mm Niederschlag haben."
                            )
                    }
                    Color.clear.frame(width: 210, height: 1)
                }
                GridRow {
                    Color.clear.frame(width: 135, height: 1)
                    HStack(spacing: 20) {
                        Toggle("Wolkenlos", isOn: Binding(
                            get: { requiresCloudless },
                            set: { enabled in
                                requiresCloudless = enabled
                                if enabled {
                                    requiresScatteredCloudCoverage = false
                                }
                            }
                        ))
                            .toggleStyle(.checkbox)
                            .frame(width: 110, alignment: .leading)
                            .help("Akzeptiert höchstens FEW und dies in weniger als 50 % des geprüften Zeitraums.")
                        Toggle("66 % max. SCT", isOn: Binding(
                            get: { requiresScatteredCloudCoverage },
                            set: { enabled in
                                requiresScatteredCloudCoverage = enabled
                                if enabled { requiresCloudless = false }
                            }
                        ))
                            .toggleStyle(.checkbox)
                            .help(
                                daylightOnly
                                    ? "Pro Kalendertag am Ziel muss in mindestens zwei Dritteln der Tageslichtstunden höchstens SCT (50 % Gesamtbewölkung) vorhergesagt sein."
                                    : "Pro Kalendertag am Ziel muss in mindestens zwei Dritteln der Stunden im gewählten Zeitraum höchstens SCT (50 % Gesamtbewölkung) vorhergesagt sein."
                            )
                    }
                    Color.clear.frame(width: 210, height: 1)
                }
                sliderRow(
                    title: "Maximaler Wind",
                    value: $maximumWind,
                    range: 0...30,
                    step: 1,
                    valueText: "\(Int(maximumWind)) kt",
                    trailing: AnyView(
                        Toggle("Ignorieren", isOn: $ignoresWind)
                            .toggleStyle(.checkbox)
                    ),
                    colors: windScaleColors
                )
                sliderRow(
                    title: "Gusts",
                    value: $maximumGust,
                    range: 0...50,
                    step: 1,
                    valueText: "\(Int(maximumGust)) kt",
                    trailing: AnyView(
                        Toggle("Ignorieren", isOn: $ignoresGusts)
                            .toggleStyle(.checkbox)
                    ),
                    colors: windScaleColors
                )
                sliderRow(
                    title: "Maximaler Föhn",
                    value: $maximumFoehnPressureDifference,
                    range: 2...12,
                    step: 2,
                    valueText: ignoresFoehn
                        ? "Unbegrenzt"
                        : "< \(Int(maximumFoehnPressureDifference)) hPa",
                    trailing: AnyView(
                        Toggle("Ignorieren", isOn: $ignoresFoehn)
                            .toggleStyle(.checkbox)
                    ),
                    colors: [.green, .yellow, .orange, .red]
                )
                .help("Gilt nur für Flugplätze in der Alpenregion. Je nach Lage wird die Achse Annecy–Aosta, Zürich–Lugano oder Innsbruck–Bozen geprüft. Maßgeblich ist die stärkste für die jeweilige Alpenseite relevante Druckdifferenz im gewählten Zeitraum.")
            }
        }
    }

    private var flightConditionsSection: some View {
        filterGroup(title: "MINIMALE BEDINGUNGEN", symbol: "cloud.sun.fill") {
            HStack(spacing: 10) {
                conditionButton(.vfr, color: .green)
                conditionButton(.mvfr, color: .blue)
                Toggle("Ignorieren", isOn: $ignoresMinimumWeather)
                    .toggleStyle(.checkbox)
                Spacer()
            }
            Toggle(isOn: Binding(
                get: { usesMinimumWeatherCoverageRule },
                set: { enabled in
                    usesMinimumWeatherCoverageRule = enabled
                }
            )) {
                Label(
                    "66-%-Tagesregel",
                    systemImage: "chart.pie.fill"
                )
            }
            .toggleStyle(.checkbox)
            .disabled(ignoresMinimumWeather)
            .help("Mindestens 66 % der Tageslichtstunden müssen die gewählte Flugwetterkategorie oder besser erreichen.")

            Text(minimumWeatherRuleExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var minimumWeatherRuleExplanation: String {
        if ignoresMinimumWeather {
            return "Der Filter für die Flugwetterkategorie ist deaktiviert."
        }
        if usesMinimumWeatherCoverageRule {
            return "Mindestens 66 % der Stunden zwischen Sonnenaufgang und Sonnenuntergang müssen \(minimumWeather.rawValue) oder besser sein. Bis zu 34 % schlechtere Stunden bleiben zulässig."
        }
        return "Jede Wetterstunde zwischen Sonnenaufgang und Sonnenuntergang muss \(minimumWeather.rawValue) oder besser sein."
    }

    private var targetWeatherFilterSummary: String {
        var conditions: [String] = []
        if !ignoresMinimumWeather {
            let rule = usesMinimumWeatherCoverageRule
                ? "mindestens 66 % der Stunden"
                : "jede Stunde"
            conditions.append(
                "mind. \(minimumWeather.rawValue) · Sonnenaufgang–Sonnenuntergang · \(rule)"
            )
        }
        if requiresRainFree {
            conditions.append(
                daylightOnly
                    ? "tagsüber durchgehend regenfrei"
                    : "im gesamten Zeitraum regenfrei"
            )
        } else if requiresRainFreeCoverage {
            conditions.append(
                daylightOnly
                    ? "pro Tag mind. 66 % der Tageslichtstunden regenfrei"
                    : "pro Tag mind. 66 % des gewählten Zeitraums regenfrei"
            )
        }
        if requiresCloudless {
            conditions.append(
                daylightOnly
                    ? "tagsüber wolkenlos"
                    : "im gesamten Zeitraum wolkenlos"
            )
        } else if requiresScatteredCloudCoverage {
            conditions.append(
                daylightOnly
                    ? "pro Tag mind. 66 % der Tageslichtstunden max. SCT"
                    : "pro Tag mind. 66 % des gewählten Zeitraums max. SCT"
            )
        }
        return conditions.isEmpty
            ? "Zielwetter: Flugwetterkategorie und Regen ignoriert"
            : "Zielwetter: " + conditions.joined(separator: " · ")
    }

    private var routeWeatherSection: some View {
        filterGroup(title: "STRECKENWETTER", symbol: "point.topleft.down.to.point.bottomright.curvepath") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                sliderRow(
                    title: "Mindestwetter Strecke",
                    value: Binding(
                        get: { Double(maximumRouteWeatherRisk.rawValue) },
                        set: { value in
                            maximumRouteWeatherRisk = RouteWeatherRisk(
                                rawValue: Int(value.rounded())
                            ) ?? .green
                        }
                    ),
                    range: 0...3,
                    step: 1,
                    valueText: routeWeatherFilterTitle,
                    trailing: AnyView(
                        Toggle("Ignorieren", isOn: $ignoresRouteWeather)
                            .toggleStyle(.checkbox)
                    ),
                    colors: [.green, FlybookColor.blue, .red, .purple]
                )
            }
            Text("Schnelles Vorscreening aus dem gemeinsam geladenen ICON-D2-/ICON-EU-Flugplatznetz. Die detaillierte 18-Punkte-Korridorprüfung erfolgt anschließend in der konkreten Flugplanung.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var routeWeatherFilterTitle: String {
        switch maximumRouteWeatherRisk {
        case .unavailable: return "Keine Daten"
        case .green: return "Grün"
        case .blue: return "Blau"
        case .red: return "Rot"
        case .purple: return "Lila"
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ERGEBNIS")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)
                Spacer()
                Text("\(matches.count) Ziele")
                    .font(.system(size: 14, weight: .bold))
            }
            Label(targetWeatherFilterSummary, systemImage: "cloud.sun.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    ignoresMinimumWeather ? Color.secondary : FlybookColor.blue
                )
            if matches.isEmpty {
                Text(
                    isFiltering
                        ? "Ziele und Wetterdaten werden geprüft …"
                        : hasAppliedFilter
                            ? "Keine Ziele erfüllen die gewählten Filterbedingungen."
                            : "Noch kein Filter angewendet."
                )
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(matches) { match in
                            HStack {
                                Text(match.destinationICAO)
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .frame(width: 55, alignment: .leading)
                                Text(match.destinationName)
                                Spacer()
                                if match.stopCount > 0 {
                                    Text("\(match.stopCount) Stop\(match.stopCount == 1 ? "" : "ps")")
                                        .foregroundStyle(FlybookColor.blue)
                                }
                                if !match.weatherWasChecked {
                                    Label("Streckenwetter offen", systemImage: "questionmark.circle.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.orange)
                                        .help("Das Ziel bleibt sichtbar. Mindestens ein Streckenabschnitt konnte noch nicht bewertet werden.")
                                }
                                Text(FlightMath.duration(match.travelMinutes))
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .frame(width: 48, alignment: .trailing)
                                Text(
                                    match.roundTripPriceEUR.formatted(
                                        .currency(code: "EUR")
                                            .locale(Locale(identifier: "de_DE"))
                                            .precision(.fractionLength(0))
                                    )
                                )
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .frame(width: 74, alignment: .trailing)
                                .help(
                                    match.priceStopCount == 0
                                        ? "Hin- und Rückflug Nonstop kalkuliert"
                                        : "Preis mit bis zu \(match.priceStopCount) ETOPS-Zwischenstopp\(match.priceStopCount == 1 ? "" : "s") je Strecke kalkuliert"
                                )
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(height: 130)
            }
            if unavailableWeatherCount > 0 {
                Text(
                    "\(unavailableWeatherCount) Ziele wurden ausgeschlossen, weil Ziel- oder Föhnwetterdaten nicht verfügbar waren."
                )
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if incompleteRouteWeatherCount > 0 {
                Text(
                    "\(incompleteRouteWeatherCount) Ziele bleiben trotz unvollständiger Streckenwetterdaten sichtbar."
                )
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func criterionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(FlybookColor.navy)
            .frame(width: 135, alignment: .leading)
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String,
        trailing: AnyView = AnyView(Color.clear.frame(width: 1)),
        colors: [Color]? = nil
    ) -> some View {
        GridRow {
            criterionLabel(title)
            HStack(spacing: 10) {
                if let colors {
                    GradientSlider(
                        value: value,
                        range: range,
                        step: step,
                        colors: colors
                    )
                } else {
                    Slider(value: value, in: range, step: step)
                }
                Text(valueText)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .frame(width: 84, alignment: .trailing)
            }
            .frame(width: 350)
            trailing.frame(width: 210, alignment: .leading)
        }
    }

    private func filterGroup<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(FlybookColor.navy)
            content()
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(Color.gray.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(FlybookColor.navy.opacity(0.12), lineWidth: 1)
        )
    }

    private func conditionButton(
        _ condition: DestinationFinderMinimumWeather,
        color: Color
    ) -> some View {
        Button {
            minimumWeather = condition
        } label: {
            Text(condition.rawValue)
            .font(.system(size: 14, weight: .bold))
            .frame(width: 110)
        }
        .buttonStyle(.borderedProminent)
        .tint(
            minimumWeather == condition
                ? color
                : color.opacity(0.25)
        )
    }

    private var windScaleColors: [Color] {
        [
            Color(red: 0.78, green: 0.94, blue: 0.80),
            Color(red: 0.39, green: 0.78, blue: 0.47),
            Color(red: 0.10, green: 0.50, blue: 0.22),
            Color(red: 0.69, green: 0.86, blue: 0.98),
            Color(red: 0.31, green: 0.61, blue: 0.88),
            Color(red: 0.08, green: 0.29, blue: 0.66),
            Color(red: 0.97, green: 0.69, blue: 0.67),
            Color(red: 0.88, green: 0.31, blue: 0.31),
            Color(red: 0.58, green: 0.04, blue: 0.08)
        ]
    }

    private var temperatureScaleColors: [Color] {
        [
            Color(red: 0.03, green: 0.16, blue: 0.42),
            Color(red: 0.05, green: 0.28, blue: 0.65),
            Color(red: 0.18, green: 0.48, blue: 0.82),
            Color(red: 0.58, green: 0.80, blue: 0.96),
            Color(red: 0.72, green: 0.93, blue: 0.72),
            Color(red: 0.42, green: 0.86, blue: 0.67),
            Color(red: 0.10, green: 0.55, blue: 0.28),
            Color(red: 0.96, green: 0.62, blue: 0.18),
            Color(red: 0.94, green: 0.31, blue: 0.16),
            Color(red: 0.82, green: 0.08, blue: 0.10),
            Color(red: 0.58, green: 0.02, blue: 0.05)
        ]
    }

    private var travelTimeText: String {
        let minimum = FlightMath.duration(
            Int((minimumTravelHours * 60).rounded())
        )
        let maximum = FlightMath.duration(
            Int((maximumTravelHours * 60).rounded())
        )
        return "\(minimum)–\(maximum)"
    }

    private var travelTimeRangeRow: some View {
        GridRow {
            criterionLabel("Reisezeit")
            HStack(spacing: 10) {
                RangeSlider(
                    lowerValue: $minimumTravelHours,
                    upperValue: $maximumTravelHours,
                    range: 0...7,
                    step: 0.25
                )
                Text(travelTimeText)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .frame(width: 104, alignment: .trailing)
            }
            .frame(width: 370)
            HStack(spacing: 10) {
                Toggle("ETOPS-PIPI", isOn: $appliesETOPS)
                    .toggleStyle(.checkbox)
                Toggle("Ignorieren", isOn: $ignoresTravelTime)
                    .toggleStyle(.checkbox)
            }
            .frame(width: 210, alignment: .leading)
        }
    }

    private func periodButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.system(size: 11, weight: .semibold))
    }

    private func setWholeDay(offset: Int) {
        let calendar = Calendar.current
        let start = calendar.date(
            byAdding: .day,
            value: offset,
            to: calendar.startOfDay(for: Date())
        ) ?? Date()
        from = start
        until = calendar.date(byAdding: .second, value: -1, to:
            calendar.date(byAdding: .day, value: 1, to: start) ?? start
        ) ?? start
    }

    private func setRollingHours(_ hours: Int) {
        let calendar = Calendar.current
        let hourStart = calendar.dateInterval(of: .hour, for: Date())?.start ?? Date()
        let nextFullHour = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? Date()
        from = nextFullHour
        until = calendar.date(byAdding: .hour, value: hours, to: nextFullHour) ?? nextFullHour
    }

    private func setComingFourDays() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: Date())
        ) ?? Date()
        from = tomorrow
        let end = calendar.date(byAdding: .day, value: 4, to: tomorrow) ?? tomorrow
        until = calendar.date(byAdding: .second, value: -1, to: end) ?? end
    }

    private func saveSession() {
        let session = DestinationFinderSession.shared
        session.originICAO = originICAO
        session.from = from
        session.until = until
        session.minimumTravelHours = minimumTravelHours
        session.maximumTravelHours = maximumTravelHours
        session.ignoresTravelTime = ignoresTravelTime
        session.appliesETOPS = appliesETOPS
        session.maximumRoundTripPrice = maximumRoundTripPrice
        session.ignoresPrice = ignoresPrice
        session.priceAppliesETOPS = priceAppliesETOPS
        session.requiresLandingVoucher = requiresLandingVoucher
        session.requiredFeatures = requiredFeatures
        session.requiresBicycleAtAirport = requiresBicycleAtAirport
        session.requiresRentalCarAtAirport = requiresRentalCarAtAirport
        session.requiresApp2DriveAtAirport = requiresApp2DriveAtAirport
        session.minimumRunwayLength = minimumRunwayLength
        session.selectedCountryCodes = selectedCountryCodes
        session.requiredFuelTypes = requiredFuelTypes
        session.requiresFuelAtOrBelowReferencePrice = requiresFuelAtOrBelowReferencePrice
        session.minimumTemperature = minimumTemperature
        session.ignoresMinimumTemperature = ignoresMinimumTemperature
        session.maximumTemperature = maximumTemperature
        session.ignoresMaximumTemperature = ignoresMaximumTemperature
        session.maximumWind = maximumWind
        session.ignoresWind = ignoresWind
        session.maximumGust = maximumGust
        session.ignoresGusts = ignoresGusts
        session.maximumFoehnPressureDifference = maximumFoehnPressureDifference
        session.ignoresFoehn = ignoresFoehn
        session.minimumWeather = minimumWeather
        session.ignoresMinimumWeather = ignoresMinimumWeather
        session.usesMinimumWeatherCoverageRule = usesMinimumWeatherCoverageRule
        session.requiresCloudless = requiresCloudless
        session.requiresScatteredCloudCoverage = requiresScatteredCloudCoverage
        session.requiresRainFree = requiresRainFree
        session.requiresRainFreeCoverage = requiresRainFreeCoverage
        session.daylightOnly = daylightOnly
        session.filterUserRaw = filterUserRaw
        session.maximumRouteWeatherRisk = maximumRouteWeatherRisk
        session.ignoresRouteWeather = ignoresRouteWeather
    }

    private func resetFilters() {
        let allCountryCodes = Set(
            destinations.map { $0.country.uppercased() } + ["ES", "PT"]
        )
        let session = DestinationFinderSession.shared
        session.reset(countryCodes: allCountryCodes, activeUserRaw: activeUserRaw)
        originICAO = origins.contains(where: { $0.icao == "EDFZ" })
            ? "EDFZ" : (origins.first?.icao ?? "EDFZ")
        from = session.from
        until = session.until
        minimumTravelHours = session.minimumTravelHours
        maximumTravelHours = session.maximumTravelHours
        ignoresTravelTime = session.ignoresTravelTime
        appliesETOPS = session.appliesETOPS
        maximumRoundTripPrice = session.maximumRoundTripPrice
        ignoresPrice = session.ignoresPrice
        priceAppliesETOPS = session.priceAppliesETOPS
        requiresLandingVoucher = session.requiresLandingVoucher
        requiredFeatures = session.requiredFeatures
        requiresBicycleAtAirport = session.requiresBicycleAtAirport
        requiresRentalCarAtAirport = session.requiresRentalCarAtAirport
        requiresApp2DriveAtAirport = session.requiresApp2DriveAtAirport
        minimumRunwayLength = session.minimumRunwayLength
        selectedCountryCodes = allCountryCodes
        requiredFuelTypes = session.requiredFuelTypes
        requiresFuelAtOrBelowReferencePrice = session.requiresFuelAtOrBelowReferencePrice
        minimumTemperature = session.minimumTemperature
        ignoresMinimumTemperature = session.ignoresMinimumTemperature
        maximumTemperature = session.maximumTemperature
        ignoresMaximumTemperature = session.ignoresMaximumTemperature
        maximumWind = session.maximumWind
        ignoresWind = session.ignoresWind
        maximumGust = session.maximumGust
        ignoresGusts = session.ignoresGusts
        maximumFoehnPressureDifference = session.maximumFoehnPressureDifference
        ignoresFoehn = session.ignoresFoehn
        minimumWeather = session.minimumWeather
        ignoresMinimumWeather = session.ignoresMinimumWeather
        usesMinimumWeatherCoverageRule = session.usesMinimumWeatherCoverageRule
        requiresCloudless = session.requiresCloudless
        requiresScatteredCloudCoverage = session.requiresScatteredCloudCoverage
        requiresRainFree = session.requiresRainFree
        requiresRainFreeCoverage = session.requiresRainFreeCoverage
        daylightOnly = session.daylightOnly
        filterUserRaw = session.filterUserRaw
        maximumRouteWeatherRisk = session.maximumRouteWeatherRisk
        ignoresRouteWeather = session.ignoresRouteWeather
        matches = []
        unavailableWeatherCount = 0
        incompleteRouteWeatherCount = 0
        hasAppliedFilter = false
        synchronizeOriginSearchText()
    }

    private func applyFilter() {
        saveSession()
        isFiltering = true
        matches = []
        unavailableWeatherCount = 0
        incompleteRouteWeatherCount = 0
        let criteria = DestinationFinderCriteria(
            originICAO: originICAO,
            from: from,
            until: until,
            minimumTravelMinutes: Int((minimumTravelHours * 60).rounded()),
            maximumTravelMinutes: Int((maximumTravelHours * 60).rounded()),
            ignoresTravelTime: ignoresTravelTime,
            appliesETOPS: appliesETOPS,
            maximumRoundTripPriceEUR: maximumRoundTripPrice,
            ignoresPrice: ignoresPrice,
            priceAppliesETOPS: priceAppliesETOPS,
            requiresLandingVoucher: requiresLandingVoucher,
            requiredFeatures: requiredFeatures,
            requiresBicycleAtAirport: requiresBicycleAtAirport,
            requiresRentalCarAtAirport: requiresRentalCarAtAirport,
            requiresApp2DriveAtAirport: requiresApp2DriveAtAirport,
            minimumRunwayLengthMeters: Int(minimumRunwayLength.rounded()),
            allowedCountryCodes: selectedCountryCodes,
            requiredFuelTypes: requiredFuelTypes,
            requiresFuelAtOrBelowReferencePrice: requiresFuelAtOrBelowReferencePrice,
            minimumTemperatureCelsius: minimumTemperature,
            ignoresMinimumTemperature: ignoresMinimumTemperature,
            maximumTemperatureCelsius: maximumTemperature,
            ignoresMaximumTemperature: ignoresMaximumTemperature,
            maximumSteadyWindKnots: maximumWind,
            ignoresWind: ignoresWind,
            maximumGustKnots: maximumGust,
            ignoresGusts: ignoresGusts,
            maximumFoehnPressureDifferenceHPA:
                maximumFoehnPressureDifference,
            ignoresFoehn: ignoresFoehn,
            minimumWeather: minimumWeather,
            ignoresMinimumWeather: ignoresMinimumWeather,
            usesMinimumWeatherCoverageRule: usesMinimumWeatherCoverageRule,
            requiresCloudless: requiresCloudless,
            requiresScatteredCloudCoverage: requiresScatteredCloudCoverage,
            requiresRainFree: requiresRainFree,
            requiresRainFreeCoverage: requiresRainFreeCoverage,
            daylightOnly: daylightOnly,
            daytimeOnly: false,
            minimumWeatherDaylightOnly: true,
            maximumRouteWeatherRisk: maximumRouteWeatherRisk,
            ignoresRouteWeather: ignoresRouteWeather
        )
        let aircraft = AircraftType(rawValue: selectedAircraftRaw) ?? .a211
        let filterUser = FlybookUser(rawValue: filterUserRaw)
            ?? FlybookUser(rawValue: activeUserRaw)
            ?? .stephan
        Task {
            let result = await DestinationFinderService.find(
                destinations: destinations,
                origins: origins,
                criteria: criteria,
                aircraft: aircraft,
                greenYellowMinutes:
                    ETOPSProfileStore.greenYellow(for: filterUser),
                orangeRedMinutes:
                    ETOPSProfileStore.orangeRed(for: filterUser),
                tankStopMinutes: tankStopMinutes,
                preTakeoffGroundMinutes: preTakeoffGroundMinutes,
                postLandingGroundMinutes: postLandingGroundMinutes,
                vatPercent: vatPercent,
                weekdayDiscountEnabled: weekdayDiscountEnabled,
                prepaymentDiscount15To29Enabled:
                    prepaymentDiscount15To29Enabled,
                prepaymentDiscount30PlusEnabled:
                    prepaymentDiscount30PlusEnabled
            )
            await MainActor.run {
                matches = result.matches
                unavailableWeatherCount = result.unavailableWeatherCount
                incompleteRouteWeatherCount =
                    result.incompleteRouteWeatherCount
                onApply(result.matches)
                hasAppliedFilter = true
                isFiltering = false
            }
        }
    }
}

private struct RangeSlider: View {
    @Binding var lowerValue: Double
    @Binding var upperValue: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        GeometryReader { proxy in
            let knobSize = 17.0
            let width = max(1, proxy.size.width - knobSize)
            let lowerX = width * fraction(for: lowerValue)
            let upperX = width * fraction(for: upperValue)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.22))
                    .frame(height: 7)
                Capsule()
                    .fill(FlybookColor.blue)
                    .frame(width: max(7, upperX - lowerX), height: 7)
                    .offset(x: lowerX + knobSize / 2)
                knob.offset(x: lowerX)
                knob.offset(x: upperX)
            }
            .frame(height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let candidate = value(at: drag.location.x, width: proxy.size.width)
                        if abs(candidate - lowerValue) <= abs(candidate - upperValue) {
                            lowerValue = min(candidate, upperValue)
                        } else {
                            upperValue = max(candidate, lowerValue)
                        }
                    }
            )
        }
        .frame(height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reisezeit von bis")
        .accessibilityValue("\(lowerValue) bis \(upperValue) Stunden")
    }

    private var knob: some View {
        Circle()
            .fill(Color(nsColor: .controlBackgroundColor))
            .frame(width: 17, height: 17)
            .overlay(Circle().stroke(FlybookColor.navy, lineWidth: 1.5))
    }

    private func fraction(for value: Double) -> Double {
        max(0, min(1, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    private func value(at x: Double, width: Double) -> Double {
        let fraction = max(0, min(1, x / max(1, width)))
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        let stepped = (raw / step).rounded() * step
        return max(range.lowerBound, min(range.upperBound, stepped))
    }
}

private struct GradientSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { proxy in
            let knobSize = 17.0
            let availableWidth = max(1, proxy.size.width - knobSize)
            let fraction = max(
                0,
                min(
                    1,
                    (value - range.lowerBound)
                        / (range.upperBound - range.lowerBound)
                )
            )

            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: colors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 9)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.14)))

                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: knobSize, height: knobSize)
                    .overlay(
                        Circle().stroke(FlybookColor.navy, lineWidth: 1.5)
                    )
                    .offset(x: availableWidth * fraction)
            }
            .frame(height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let rawFraction = max(
                            0,
                            min(1, gesture.location.x / proxy.size.width)
                        )
                        let rawValue = range.lowerBound
                            + rawFraction
                            * (range.upperBound - range.lowerBound)
                        let stepped = (rawValue / step).rounded() * step
                        value = max(
                            range.lowerBound,
                            min(range.upperBound, stepped)
                        )
                    }
            )
        }
        .frame(height: 22)
    }
}
