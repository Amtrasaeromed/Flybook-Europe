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

enum FlightCategory: String, Codable {
    case vfr = "VFR"
    case mvfr = "MVFR"
    case ifr = "IFR"
    case lifr = "LIFR"
    case unavailable = "N/A"
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

    var outboundHeadwindKnots: Double {
        WindMath.headwindComponent(
            windFromDegrees: directionDegrees,
            speedKnots: speedKnots,
            courseDegrees: outboundCourseDegrees
        )
    }

    var returnHeadwindKnots: Double {
        WindMath.headwindComponent(
            windFromDegrees: directionDegrees,
            speedKnots: speedKnots,
            courseDegrees: WindMath.normalized(outboundCourseDegrees + 180.0)
        )
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
    let minimumTemperatureCelsius: Double?
    let maximumTemperatureCelsius: Double?
    let model: String
}

struct DestinationWeather: Codable, Hashable {
    let icao: String
    let retrievedAt: Date
    let timezone: String
    let days: [ForecastDay]
    let dailyForecast: [DailyForecast]
}

enum FlightMath {
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

    static func adjustedMinutes(
        directNM: Double,
        stopCount: Int,
        headwindKnots: Double?,
        tankStopMinutes: Int = 60,
        cruiseGroundSpeedKnots: Double = 105.0
    ) -> Int {
        let cruiseKnots =
            max(60.0, cruiseGroundSpeedKnots)
        let slowKnots = 75.0

        let routeExtraNM: Double
        let slowDistanceNM: Double
        let taxiMinutes: Double
        let groundStopMinutes: Double

        switch stopCount {
        case 0:
            routeExtraNM = 10.0
            slowDistanceNM = 10.0
            taxiMinutes = 6.0
            groundStopMinutes = 0.0
        case 2:
            routeExtraNM = 50.0
            slowDistanceNM = 30.0
            taxiMinutes = 18.0
            groundStopMinutes =
                Double(max(0, tankStopMinutes) * 2)
        default:
            routeExtraNM = 30.0
            slowDistanceNM = 20.0
            taxiMinutes = 12.0
            groundStopMinutes =
                Double(max(0, tankStopMinutes))
        }

        let routeNM = directNM * 1.05 + routeExtraNM
        let cruiseDistanceNM = max(0.0, routeNM - slowDistanceNM)
        let component = headwindKnots ?? 0.0
        let effectiveCruiseKnots = max(55.0, min(155.0, cruiseKnots - component))

        let minutes =
            cruiseDistanceNM / effectiveCruiseKnots * 60.0
            + slowDistanceNM / slowKnots * 60.0
            + taxiMinutes
            + groundStopMinutes

        return Int(round(minutes))
    }


    static func adjustedBlockMinutes(
        directNM: Double,
        stopCount: Int,
        headwindKnots: Double?,
        cruiseGroundSpeedKnots: Double = 105.0
    ) -> Int {
        adjustedMinutes(
            directNM: directNM,
            stopCount: stopCount,
            headwindKnots: headwindKnots,
            tankStopMinutes: 0,
            cruiseGroundSpeedKnots:
                cruiseGroundSpeedKnots
        )
    }

    static func adjustedPerLegMinutes(
        directNM: Double,
        stopCount: Int,
        headwindKnots: Double?,
        tankStopMinutes: Int = 60,
        cruiseGroundSpeedKnots: Double = 105.0
    ) -> Int {
        let legs = max(1, stopCount + 1)
        let total = adjustedMinutes(
            directNM: directNM,
            stopCount: stopCount,
            headwindKnots: headwindKnots,
            tankStopMinutes: tankStopMinutes,
            cruiseGroundSpeedKnots:
                cruiseGroundSpeedKnots
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
