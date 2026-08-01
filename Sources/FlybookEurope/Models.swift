import Foundation
import CoreGraphics

struct AirportReference: Identifiable, Hashable {
    var id: String { icao }
    let icao: String
    let name: String
    let latitude: Double
    let longitude: Double
    let elevationFeet: Double
    let timeZone: TimeZone

    static let edfz = AirportReference(
        icao: "EDFZ",
        name: "Mainz-Finthen",
        latitude: FlightDateTime.edfzLatitude,
        longitude: FlightDateTime.edfzLongitude,
        elevationFeet: 760,
        timeZone: DestinationTimeZone.edfz
    )
}

enum AirportDistance {
    static func nauticalMiles(
        from origin: AirportReference,
        to destination: AirportReference
    ) -> Double {
        let radiusNM = 3440.065
        let lat1 = origin.latitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let deltaLat =
            (destination.latitude - origin.latitude) * .pi / 180
        let deltaLon =
            (destination.longitude - origin.longitude) * .pi / 180
        let value = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2)
            * sin(deltaLon / 2) * sin(deltaLon / 2)
        return radiusNM * 2 * atan2(sqrt(value), sqrt(1 - value))
    }

    static func nauticalMiles(
        from origin: AirportReference,
        to destination: Destination
    ) -> Double {
        guard let latitude = destination.latitude,
              let longitude = destination.longitude
        else { return destination.directNM }
        let radiusNM = 3440.065
        let lat1 = origin.latitude * .pi / 180
        let lat2 = latitude * .pi / 180
        let deltaLat = (latitude - origin.latitude) * .pi / 180
        let deltaLon = (longitude - origin.longitude) * .pi / 180
        let value = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2)
            * sin(deltaLon / 2) * sin(deltaLon / 2)
        return radiusNM * 2 * atan2(sqrt(value), sqrt(1 - value))
    }
}

struct FlightTimes: Hashable {
    let nonstopMinutes: Int
    let oneStopMinutes: Int
    let twoStopMinutes: Int
    let perLegMinutes: Int
    let twoStopPerLegMinutes: Int
    let totalOneStopMinutes: Int
    let arrivalMinutes: Int
    let returnDepartureMinutes: Int

    func minutes(for stopCount: Int) -> Int {
        switch stopCount {
        case 0:
            return nonstopMinutes
        case 2:
            return twoStopMinutes
        default:
            return oneStopMinutes
        }
    }
}

struct Destination: Identifiable, Hashable {
    var id: String { icao }
    let icao: String
    let name: String
    let country: String
    let region: String
    let weekendScore: String
    let season: String
    let airportFilter: String
    let directNM: Double
    let runwayM: Int
    let surface: String
    let avgas: String
    let ul91: String
    let mogas: String
    var avgasPricePerLiterEUR: Double?
    var ul91PricePerLiterEUR: Double?
    var mogasPricePerLiterEUR: Double?
    let ppr: String
    let transfer: String
    let transferMinutes: Int
    let bikeDirect: String
    let highlights: String
    let activities: String
    let airportNote: String
    let status: String
    let airportSource: String
    let tourismSource: String
    let latitude: Double?
    let longitude: Double?
    let elevationFeet: Double
    let regionalImageName: String
    let flightTimes: FlightTimes
}

enum FlightCategory: String, Codable, Hashable {
    case vfr = "VFR"
    case mvfr = "MVFR"
    case ifr = "IFR"
    case lifr = "LIFR"
    case unavailable = "N/A"

    var severity: Int {
        switch self {
        case .vfr: return 1
        case .mvfr: return 2
        case .ifr: return 3
        case .lifr: return 4
        case .unavailable: return 0
        }
    }
}

struct WindSample: Codable, Hashable {
    let directionDegrees: Double?
    let speedKnots: Double?
}


struct RouteWind: Codable, Hashable {
    let retrievedAt: Date
    let validTime: Date
    let midpointLatitude: Double
    let midpointLongitude: Double
    let altitudeFeet: Int
    let directionDegrees: Double
    let speedKnots: Double
    let outboundCourseDegrees: Double
    let routeIsReturn: Bool
    let routeHeadwindComponents: [Double]
    let modelBestAltitudeFeetAtPoints: [Double]

    private var effectiveRouteHeadwindKnots: Double {
        guard !routeHeadwindComponents.isEmpty else { return 0 }
        return routeHeadwindComponents.reduce(0, +)
            / Double(routeHeadwindComponents.count)
    }

    var outboundHeadwindKnots: Double {
        routeIsReturn
            ? -effectiveRouteHeadwindKnots
            : effectiveRouteHeadwindKnots
    }

    var returnHeadwindKnots: Double {
        routeIsReturn
            ? effectiveRouteHeadwindKnots
            : -effectiveRouteHeadwindKnots
    }
}

enum WindMath {
    static func normalized(_ degrees: Double) -> Double {
        (degrees.truncatingRemainder(dividingBy: 360.0) + 360.0)
            .truncatingRemainder(dividingBy: 360.0)
    }

    static func headwindComponent(
        windFromDegrees: Double,
        speedKnots: Double,
        courseDegrees: Double
    ) -> Double {
        let angle = (windFromDegrees - courseDegrees) * .pi / 180.0
        return speedKnots * cos(angle)
    }

    static func midpoint(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double
    ) -> (latitude: Double, longitude: Double) {
        let lat1 = latitude1 * .pi / 180.0
        let lon1 = longitude1 * .pi / 180.0
        let lat2 = latitude2 * .pi / 180.0
        let deltaLon = (longitude2 - longitude1) * .pi / 180.0

        let bx = cos(lat2) * cos(deltaLon)
        let by = cos(lat2) * sin(deltaLon)
        let latitude = atan2(
            sin(lat1) + sin(lat2),
            sqrt((cos(lat1) + bx) * (cos(lat1) + bx) + by * by)
        )
        let longitude = lon1 + atan2(by, cos(lat1) + bx)

        return (
            latitude * 180.0 / .pi,
            normalized(longitude * 180.0 / .pi + 180.0) - 180.0
        )
    }

    static func initialBearing(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double
    ) -> Double {
        let lat1 = latitude1 * .pi / 180.0
        let lat2 = latitude2 * .pi / 180.0
        let deltaLon = (longitude2 - longitude1) * .pi / 180.0
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return normalized(atan2(y, x) * 180.0 / .pi)
    }

    static func point(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double,
        fraction: Double
    ) -> (latitude: Double, longitude: Double) {
        let clamped = max(0, min(1, fraction))
        let lat1 = latitude1 * .pi / 180
        let lon1 = longitude1 * .pi / 180
        let lat2 = latitude2 * .pi / 180
        let lon2 = longitude2 * .pi / 180
        let delta = 2 * asin(
            sqrt(
                pow(sin((lat2 - lat1) / 2), 2)
                + cos(lat1) * cos(lat2)
                * pow(sin((lon2 - lon1) / 2), 2)
            )
        )

        guard delta > 0.000_001 else {
            return (latitude1, longitude1)
        }

        let a = sin((1 - clamped) * delta) / sin(delta)
        let b = sin(clamped * delta) / sin(delta)
        let x = a * cos(lat1) * cos(lon1)
            + b * cos(lat2) * cos(lon2)
        let y = a * cos(lat1) * sin(lon1)
            + b * cos(lat2) * sin(lon2)
        let z = a * sin(lat1) + b * sin(lat2)
        let latitude = atan2(z, sqrt(x * x + y * y))
        let longitude = atan2(y, x)
        return (
            latitude * 180 / .pi,
            longitude * 180 / .pi
        )
    }
}

struct ForecastDay: Codable, Hashable, Identifiable {
    var id: String { "\(localDate)-\(localTime)-\(displayDay)" }
    let localDate: String
    let displayDay: String
    let localTime: String
    let model: String
    let temperatureCelsius: Double?
    let weatherCode: Int?
    let visibilityMeters: Double?
    let lowCloudCoverPercent: Double?
    let lowestCloudBaseFeetAGL: Double?
    let ceilingFeetAGL: Double?
    let precipitationProbability: Double?
    let pressureMSLHPA: Double?
    let windGustKnots: Double?
    let surfaceWind: WindSample
    let upperWind: WindSample
    let sunrise: String?
    let sunset: String?
    let category: FlightCategory
}

struct DailyForecast: Codable, Hashable, Identifiable {
    var id: String { localDate }
    let localDate: String
    let weatherCode: Int?
    let morningWeatherCode: Int?
    let middayWeatherCode: Int?
    let eveningWeatherCode: Int?
    let morningCategory: FlightCategory?
    let middayCategory: FlightCategory?
    let eveningCategory: FlightCategory?
    let minimumTemperatureCelsius: Double?
    let maximumTemperatureCelsius: Double?
    let maximumSurfaceWindKnots: Double?
    let maximumWindGustKnots: Double?
    let hourlySurfaceWindKnots: [Double?]?
    let model: String
}

struct DestinationWeather: Codable, Hashable {
    let icao: String
    let retrievedAt: Date
    let timezone: String
    let days: [ForecastDay]
    let dailyForecast: [DailyForecast]
}

struct ClimbPerformance: Hashable {
    let speedKIAS: Double
    let timeAt1000FeetMinutes: Double
    let distanceAt1000FeetNM: Double
    let timeAt3000FeetMinutes: Double
    let distanceAt3000FeetNM: Double
    let timeAt5000FeetMinutes: Double
    let distanceAt5000FeetNM: Double
    let timeAt7000FeetMinutes: Double
    let distanceAt7000FeetNM: Double
    let timeAt10000FeetMinutes: Double
    let distanceAt10000FeetNM: Double

    static let a211Default = ClimbPerformance(
        speedKIAS: 65,
        timeAt1000FeetMinutes: 1.5,
        distanceAt1000FeetNM: 1.6,
        timeAt3000FeetMinutes: 4.8,
        distanceAt3000FeetNM: 5.5,
        timeAt5000FeetMinutes: 8.8,
        distanceAt5000FeetNM: 9.7,
        timeAt7000FeetMinutes: 13.0,
        distanceAt7000FeetNM: 15.4,
        timeAt10000FeetMinutes: 23.2,
        distanceAt10000FeetNM: 27.2
    )

    private func interpolatedValue(
        atPressureAltitudeFeet altitude: Double,
        values: [Double]
    ) -> Double {
        let altitudes = [0.0, 1000, 3000, 5000, 7000, 10000]
        var monotonicValues = [0.0]
        for value in values {
            monotonicValues.append(max(monotonicValues.last ?? 0, value))
        }
        let height = max(0, altitude)
        let points = Array(zip(altitudes, monotonicValues))
        for index in 1..<points.count where height <= points[index].0 {
            let lower = points[index - 1]
            let upper = points[index]
            let fraction = (height - lower.0) / (upper.0 - lower.0)
            return lower.1 + fraction * (upper.1 - lower.1)
        }
        let lower = points[points.count - 2]
        let upper = points[points.count - 1]
        return upper.1 + (height - upper.0) / (upper.0 - lower.0) * (upper.1 - lower.1)
    }

    func cumulativeDistanceNM(atPressureAltitudeFeet altitude: Double) -> Double {
        interpolatedValue(
            atPressureAltitudeFeet: altitude,
            values: [
                distanceAt1000FeetNM,
                distanceAt3000FeetNM,
                distanceAt5000FeetNM,
                distanceAt7000FeetNM,
                distanceAt10000FeetNM
            ]
        )
    }

    func cumulativeTimeMinutes(atPressureAltitudeFeet altitude: Double) -> Double {
        interpolatedValue(
            atPressureAltitudeFeet: altitude,
            values: [
                timeAt1000FeetMinutes,
                timeAt3000FeetMinutes,
                timeAt5000FeetMinutes,
                timeAt7000FeetMinutes,
                timeAt10000FeetMinutes
            ]
        )
    }

    func distanceNM(fromPressureAltitudeFeet departure: Double, toPressureAltitudeFeet target: Double) -> Double {
        max(
            0,
            cumulativeDistanceNM(atPressureAltitudeFeet: target)
                - cumulativeDistanceNM(atPressureAltitudeFeet: departure)
        )
    }

    func timeMinutes(fromPressureAltitudeFeet departure: Double, toPressureAltitudeFeet target: Double) -> Double {
        max(
            0,
            cumulativeTimeMinutes(atPressureAltitudeFeet: target)
                - cumulativeTimeMinutes(atPressureAltitudeFeet: departure)
        )
    }
}

struct CruisePerformance: Hashable {
    let powerPercent: Int
    let tasAt1000Feet: Double
    let tasAt3000Feet: Double
    let tasAt5000Feet: Double
    let tasAt7000Feet: Double
    let tasAt10000Feet: Double

    func tasKnots(atPressureAltitudeFeet altitude: Double) -> Double? {
        let values = [
            tasAt1000Feet,
            tasAt3000Feet,
            tasAt5000Feet,
            tasAt7000Feet,
            tasAt10000Feet
        ]
        guard values.allSatisfy({ $0 > 0 }) else { return nil }
        let altitudes = [1000.0, 3000, 5000, 7000, 10000]
        let height = max(altitudes[0], altitude)
        for index in 1..<altitudes.count where height <= altitudes[index] {
            let fraction = (height - altitudes[index - 1])
                / (altitudes[index] - altitudes[index - 1])
            return values[index - 1]
                + fraction * (values[index] - values[index - 1])
        }
        let last = altitudes.count - 1
        let fraction = (height - altitudes[last - 1])
            / (altitudes[last] - altitudes[last - 1])
        return values[last - 1]
            + fraction * (values[last] - values[last - 1])
    }
}

enum FlightMath {
    static func routeMiles(directNM: Double, stopCount: Int) -> Double {
        let routeExtraNM: Double
        switch stopCount {
        case 0: routeExtraNM = 10
        case 2: routeExtraNM = 50
        default: routeExtraNM = 30
        }
        return directNM * 1.05 + routeExtraNM
    }

    static func calculate(directNM: Double) -> FlightTimes {
        let cruiseKnots = 105.0
        let slowKnots = 75.0

        let nonstopRouteNM = directNM * 1.05 + 10.0
        let nonstopMovementMinutes =
            (
                (nonstopRouteNM - 10.0) / cruiseKnots
                + 10.0 / slowKnots
            ) * 60.0
            + 6.0
        let nonstopMinutes = Int(round(nonstopMovementMinutes))

        let oneStopRouteNM = directNM * 1.05 + 30.0
        let oneStopMovementMinutes =
            (
                (oneStopRouteNM - 20.0) / cruiseKnots
                + 20.0 / slowKnots
            ) * 60.0
            + 12.0
        let oneStopMinutes = Int(
            round(oneStopMovementMinutes + 60.0)
        )

        // Zweiter Zwischenstopp:
        // nochmals 20 NM Routenzuschlag, 10 NM langsamer
        // An-/Abfluganteil, weitere 6 Minuten Bodenbewegung
        // und ein zusätzlicher Bodenstopp von 60 Minuten.
        let twoStopRouteNM = directNM * 1.05 + 50.0
        let twoStopMovementMinutes =
            (
                (twoStopRouteNM - 30.0) / cruiseKnots
                + 30.0 / slowKnots
            ) * 60.0
            + 18.0
        let twoStopMinutes = Int(
            round(twoStopMovementMinutes + 120.0)
        )

        let perLegMinutes = Int(
            round(oneStopMovementMinutes / 2.0)
        )

        let twoStopPerLegMinutes = Int(
            round(twoStopMovementMinutes / 3.0)
        )

        return FlightTimes(
            nonstopMinutes: nonstopMinutes,
            oneStopMinutes: oneStopMinutes,
            twoStopMinutes: twoStopMinutes,
            perLegMinutes: perLegMinutes,
            twoStopPerLegMinutes: twoStopPerLegMinutes,
            totalOneStopMinutes: oneStopMinutes,
            arrivalMinutes: 9 * 60 + 30 + oneStopMinutes,
            returnDepartureMinutes: 17 * 60 - oneStopMinutes
        )
    }

    static func adjustedDurationMinutes(
        directNM: Double,
        stopCount: Int,
        headwindKnots: Double?,
        tankStopMinutes: Int = 60,
        cruiseGroundSpeedKnots: Double = 105.0,
        climbDeparturePressureAltitudeFeet: Double = 0,
        climbTargetPressureAltitudeFeet: Double = 0,
        climbPerformance: ClimbPerformance = .a211Default,
        cruisePerformance: CruisePerformance? = nil,
        trackMilesNM: Double? = nil,
        preTakeoffGroundMinutes: Int = 5,
        postLandingGroundMinutes: Int = 3
    ) -> Double {
        let cruiseKnots = max(
            60.0,
            cruisePerformance?.tasKnots(
                atPressureAltitudeFeet: climbTargetPressureAltitudeFeet
            ) ?? cruiseGroundSpeedKnots
        )
        let routeExtraNM: Double
        let slowDistanceNM: Double
        let groundStopMinutes: Double

        switch stopCount {
        case 0:
            routeExtraNM = 10.0
            slowDistanceNM = 10.0
            groundStopMinutes = 0.0
        case 2:
            routeExtraNM = 50.0
            slowDistanceNM = 30.0
            groundStopMinutes =
                Double(max(0, tankStopMinutes) * 2)
        default:
            routeExtraNM = 30.0
            slowDistanceNM = 20.0
            groundStopMinutes =
                Double(max(0, tankStopMinutes))
        }

        let routeNM = max(
            0,
            trackMilesNM ?? (directNM * 1.05 + routeExtraNM)
        )
        let climbDistancePerLeg = climbPerformance.distanceNM(
            fromPressureAltitudeFeet: climbDeparturePressureAltitudeFeet,
            toPressureAltitudeFeet: climbTargetPressureAltitudeFeet
        )
        let climbDistanceNM = min(routeNM, climbDistancePerLeg * Double(stopCount + 1))
        let climbMinutesPerLeg = climbPerformance.timeMinutes(
            fromPressureAltitudeFeet: climbDeparturePressureAltitudeFeet,
            toPressureAltitudeFeet: climbTargetPressureAltitudeFeet
        )
        let fullClimbDistanceNM = climbDistancePerLeg * Double(stopCount + 1)
        let flownClimbFraction = fullClimbDistanceNM > 0
            ? min(1, climbDistanceNM / fullClimbDistanceNM)
            : 0
        let climbMinutes = climbMinutesPerLeg
            * Double(stopCount + 1)
            * flownClimbFraction
        let remainingSlowDistanceNM = min(
            max(0, routeNM - climbDistanceNM),
            max(0, slowDistanceNM - climbDistanceNM)
        )
        let cruiseDistanceNM = max(0.0, routeNM - climbDistanceNM - remainingSlowDistanceNM)
        let component = headwindKnots ?? 0.0
        let effectiveCruiseKnots = max(55.0, min(155.0, cruiseKnots - component))
        let legs = max(1, stopCount + 1)
        let localGroundMinutes = Double(
            legs * (
                max(0, preTakeoffGroundMinutes)
                + max(0, postLandingGroundMinutes)
            )
        )

        let minutes =
            cruiseDistanceNM / effectiveCruiseKnots * 60.0
            + climbMinutes
            + remainingSlowDistanceNM / 75.0 * 60.0
            + groundStopMinutes
            + localGroundMinutes

        return minutes
    }

    static func adjustedMinutes(
        directNM: Double,
        stopCount: Int,
        headwindKnots: Double?,
        tankStopMinutes: Int = 60,
        cruiseGroundSpeedKnots: Double = 105.0,
        climbDeparturePressureAltitudeFeet: Double = 0,
        climbTargetPressureAltitudeFeet: Double = 0,
        climbPerformance: ClimbPerformance = .a211Default,
        cruisePerformance: CruisePerformance? = nil,
        trackMilesNM: Double? = nil,
        preTakeoffGroundMinutes: Int = 5,
        postLandingGroundMinutes: Int = 3
    ) -> Int {
        Int(round(adjustedDurationMinutes(
            directNM: directNM,
            stopCount: stopCount,
            headwindKnots: headwindKnots,
            tankStopMinutes: tankStopMinutes,
            cruiseGroundSpeedKnots: cruiseGroundSpeedKnots,
            climbDeparturePressureAltitudeFeet: climbDeparturePressureAltitudeFeet,
            climbTargetPressureAltitudeFeet: climbTargetPressureAltitudeFeet,
            climbPerformance: climbPerformance,
            cruisePerformance: cruisePerformance,
            trackMilesNM: trackMilesNM,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes
        )))
    }


    static func adjustedBlockMinutes(
        directNM: Double,
        stopCount: Int,
        headwindKnots: Double?,
        cruiseGroundSpeedKnots: Double = 105.0,
        climbDeparturePressureAltitudeFeet: Double = 0,
        climbTargetPressureAltitudeFeet: Double = 0,
        climbPerformance: ClimbPerformance = .a211Default,
        cruisePerformance: CruisePerformance? = nil,
        trackMilesNM: Double? = nil,
        preTakeoffGroundMinutes: Int = 5,
        postLandingGroundMinutes: Int = 3
    ) -> Int {
        adjustedMinutes(
            directNM: directNM,
            stopCount: stopCount,
            headwindKnots: headwindKnots,
            tankStopMinutes: 0,
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

    static func adjustedPerLegMinutes(
        directNM: Double,
        stopCount: Int,
        headwindKnots: Double?,
        tankStopMinutes: Int = 60,
        cruiseGroundSpeedKnots: Double = 105.0,
        climbDeparturePressureAltitudeFeet: Double = 0,
        climbTargetPressureAltitudeFeet: Double = 0,
        climbPerformance: ClimbPerformance = .a211Default,
        cruisePerformance: CruisePerformance? = nil,
        trackMilesNM: Double? = nil,
        preTakeoffGroundMinutes: Int = 5,
        postLandingGroundMinutes: Int = 3
    ) -> Int {
        let legs = max(1, stopCount + 1)
        let total = adjustedMinutes(
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
            trackMilesNM: trackMilesNM,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes
        )
        let groundStops =
            Double(stopCount * max(0, tankStopMinutes))
        return Int(round((Double(total) - groundStops) / Double(legs)))
    }

    static func duration(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func clock(_ minutes: Int) -> String {
        let normalized = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }

    static func travelFraction(_ minutes: Int) -> CGFloat {
        max(0.0, min(1.0, CGFloat(minutes) / 400.0))
    }

    static func etopsFraction(_ minutes: Int) -> CGFloat {
        max(0.0, min(1.0, CGFloat(minutes - 45) / 150.0))
    }
}
