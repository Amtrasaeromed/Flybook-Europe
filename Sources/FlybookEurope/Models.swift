import Foundation
import CoreGraphics

enum LandingVoucherBook {
    static var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }
    static var yearLabel: String { String(currentYear) }
    static var validUntilLabel: String { "31.12.\(yearLabel)" }
    static var settingKey: String {
        "flybookLandingVoucherBook\(yearLabel)Enabled"
    }
    static let didRefreshNotification = Notification.Name("LandingVoucherBookDidRefresh")
    private static let cacheYearKey = "landingVoucherBook.cache.year"
    private static let cacheICAOsKey = "landingVoucherBook.cache.icaos"

    // Teilnehmerliste der Ausgabe 2026, geprüft bei landegut.de.
    private static let fallback2026ICAOs: Set<String> = [
        "EDGA", "EDKD", "EDQF", "EDLA", "EDBA", "EDOA", "EDVA", "EDRA",
        "EDFD", "EDVW", "EDRS", "EDXL", "EDNC", "EDMB", "EDMC", "EDOE",
        "EDVE", "EDGB", "EDKO", "EDQE", "EDAP", "ETND", "EDRW", "LOAB",
        "EDPM", "EDAV", "EDFY", "LOKF", "EDXF", "LOKH", "EDOT", "EDMH",
        "EDXB", "EDVH", "EDRH", "EDVI", "EDMI", "EDBJ", "EDLC", "EDWK",
        "EDQK", "EDBK", "EDWF", "EDLM", "EDFM", "EDFN", "EDKZ", "EDAX",
        "EDHM", "LOGO", "ETHN", "EDNM", "EDXN", "EDWH", "EDGP", "EDCV",
        "EDQZ", "EDTP", "EKRD", "EDNR", "EDOD", "EDXE", "LOLK", "EKRS",
        "EDVR", "EDXQ", "EDXC", "EDAZ", "EDRO", "EDBS", "EDAY", "EDQS",
        "EHTX", "EDRM", "EDNT", "EDVU", "EDUY", "EDWM", "LOAN", "EDBI"
    ]

    static var participatingICAOs: Set<String> {
        let defaults = UserDefaults.standard
        if defaults.integer(forKey: cacheYearKey) == currentYear,
           let values = defaults.stringArray(forKey: cacheICAOsKey),
           !values.isEmpty {
            return Set(values)
        }
        return currentYear == 2026 ? fallback2026ICAOs : []
    }

    static func includes(_ icao: String) -> Bool {
        participatingICAOs.contains(icao.uppercased())
    }

    static func includes(_ icao: String, on date: Date) -> Bool {
        Calendar.current.component(.year, from: date) == currentYear
            && includes(icao)
    }

    static func refreshIfNeeded() async {
        let defaults = UserDefaults.standard
        let requestedYear = currentYear
        guard defaults.integer(forKey: cacheYearKey) != requestedYear else {
            return
        }
        guard let url = URL(string: "https://landegut.de/") else { return }
        do {
            let (data, response) = try await FlightNetwork.data(
                from: url,
                priority: .low
            )
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8)
            else { return }
            // Rund um den Jahreswechsel darf die noch sichtbare Liste des
            // Vorjahres nicht unter dem neuen Jahr gespeichert werden.
            guard currentYear == requestedYear,
                  pageContainsParticipantList(
                    for: requestedYear,
                    in: html
                  )
            else { return }
            let expression = try NSRegularExpression(
                pattern: #"\b(?:ED|ET|LO|EH|EK)[A-Z]{2}\b"#
            )
            let range = NSRange(html.startIndex..., in: html)
            let values = Set(expression.matches(in: html, range: range).compactMap {
                Range($0.range, in: html).map { String(html[$0]) }
            })
            // Eine unvollständige Fehler- oder Shopseite darf den Cache nicht ersetzen.
            guard values.count >= 40 else { return }
            defaults.set(requestedYear, forKey: cacheYearKey)
            defaults.set(values.sorted(), forKey: cacheICAOsKey)
            await MainActor.run {
                NotificationCenter.default.post(name: didRefreshNotification, object: nil)
            }
        } catch {
            // Der statische 2026-Datensatz bleibt als Offline-Fallback erhalten.
        }
    }

    static func pageContainsParticipantList(
        for year: Int,
        in html: String
    ) -> Bool {
        let pattern = #"Teilnehmerliste[\s\S]{0,100}\b"#
            + String(year)
            + #"\b"#
        return html.range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

struct AirportReference: Identifiable, Hashable {
    var id: String { icao }
    let icao: String
    let name: String
    let latitude: Double
    let longitude: Double
    let elevationFeet: Double
    let timeZone: TimeZone
    var referenceRunway: String? = nil

    static let edfz = AirportReference(
        icao: "EDFZ",
        name: "Mainz-Finthen",
        latitude: FlightDateTime.edfzLatitude,
        longitude: FlightDateTime.edfzLongitude,
        elevationFeet: 760,
        timeZone: DestinationTimeZone.edfz,
        referenceRunway: "07/25"
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


enum DestinationFeature: String, CaseIterable, Identifiable, Hashable {
    case techStop = "techstop"
    case breakfast = "breakfast"
    case city = "city"
    case beachSea = "beach"
    case lakeNature = "lake"
    case mountainHiking = "mountain"
    case wellness = "wellness"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .techStop: return "TechStop"
        case .breakfast: return "Frühstück"
        case .city: return "Stadt"
        case .beachSea: return "Strand / Meer"
        case .lakeNature: return "See / Natur"
        case .mountainHiking: return "Berge / Wandern"
        case .wellness: return "Auszeit / Wellness"
        }
    }

    var compactTitle: String {
        switch self {
        case .techStop: return "TechStop"
        case .breakfast: return "Frühstück"
        case .city: return "Stadt"
        case .beachSea: return "Strand"
        case .lakeNature: return "See / Natur"
        case .mountainHiking: return "Berge"
        case .wellness: return "Wellness"
        }
    }

    static let finderCases: [DestinationFeature] = [
        .techStop,
        .breakfast,
        .city,
        .beachSea,
        .lakeNature,
        .mountainHiking,
        .wellness
    ]

    var symbol: String {
        switch self {
        case .techStop: return "fuelpump.fill"
        case .breakfast: return "cup.and.saucer.fill"
        case .city: return "building.2.fill"
        case .beachSea: return "water.waves"
        case .lakeNature: return "leaf.fill"
        case .mountainHiking: return "mountain.2.fill"
        case .wellness: return "sparkles"
        }
    }
}

struct Destination: Identifiable, Hashable {
    var id: String { icao }
    let icao: String
    let name: String
    let country: String
    let timeZoneIdentifier: String
    let region: String
    let weekendScore: String
    let season: String
    let airportFilter: String
    let features: Set<DestinationFeature>
    let directNM: Double
    let referenceRunway: String
    let runwayM: Int
    let runwayWidthM: Int?
    let runwayLDAM: Int
    let surface: String
    let grassOnly: Bool
    var avgas: String
    var ul91: String
    var mogas: String
    var jetA1: String = ""
    var fuelDetails: String = ""
    var avgasPricePerLiterEUR: Double?
    var ul91PricePerLiterEUR: Double?
    var mogasPricePerLiterEUR: Double?
    var fuelPriceReportedAt: String?
    let ppr: String
    let portOfEntry: String
    let transfer: String
    let transferMinutes: Int
    let bikeDirect: String
    var rentalCarDirect: String = ""
    var app2DriveDirect: String = ""
    var restaurantDirect: String = ""
    var restaurantName: String = ""
    var restaurantDescription: String = ""
    var restaurantOpeningHours: String = ""
    var restaurantNotes: String = ""
    var restaurantSource: String = ""
    var restaurantDataCheckedAt: String = ""
    var accessFeatures: [DestinationAccessFeature] = []
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
}

struct DestinationAccessFeature: Hashable, Identifiable {
    var id: String { feature.rawValue }
    let feature: DestinationFeature
    let targetName: String
    let distanceKilometers: Double?
    let recommendedMode: String
    let recommendedMinutes: Int?
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
    let hourlyFogRiskScores: [Int?]?
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
    var vyKnots: Double { speedKIAS }
    var climbGroundSpeedKnots: Double { vyKnots }
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
    let fuelAt1000FeetPerHour: Double
    let fuelAt3000FeetPerHour: Double
    let fuelAt5000FeetPerHour: Double
    let fuelAt7000FeetPerHour: Double
    let fuelAt10000FeetPerHour: Double

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

    func fuelConsumptionPerHour(
        atPressureAltitudeFeet altitude: Double
    ) -> Double? {
        let values = [
            fuelAt1000FeetPerHour,
            fuelAt3000FeetPerHour,
            fuelAt5000FeetPerHour,
            fuelAt7000FeetPerHour,
            fuelAt10000FeetPerHour
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
    private static func routeProfile(
        stopCount: Int
    ) -> (
        routeExtraNM: Double,
        slowDistanceNM: Double,
        groundStops: Int,
        legs: Int
    ) {
        switch min(2, max(0, stopCount)) {
        case 0: return (10, 10, 0, 1)
        case 2: return (50, 30, 2, 3)
        default: return (30, 20, 1, 2)
        }
    }

    static func routeMiles(directNM: Double, stopCount: Int) -> Double {
        directNM * 1.05 + routeProfile(stopCount: stopCount).routeExtraNM
    }

    static func directMiles(along airports: [AirportReference]) -> Double {
        guard airports.count > 1 else { return 0 }
        return zip(airports, airports.dropFirst()).reduce(0) { total, leg in
            total + AirportDistance.nauticalMiles(from: leg.0, to: leg.1)
        }
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
        let profile = routeProfile(stopCount: stopCount)
        let routeExtraNM = profile.routeExtraNM
        let slowDistanceNM = profile.slowDistanceNM
        let groundStopMinutes = Double(
            max(0, tankStopMinutes) * profile.groundStops
        )

        let routeNM = max(
            0,
            trackMilesNM ?? (directNM * 1.05 + routeExtraNM)
        )
        let climbDistancePerLeg = climbPerformance.distanceNM(
            fromPressureAltitudeFeet: climbDeparturePressureAltitudeFeet,
            toPressureAltitudeFeet: climbTargetPressureAltitudeFeet
        )
        let climbDistanceNM = min(
            routeNM,
            climbDistancePerLeg * Double(profile.legs)
        )
        let climbMinutesPerLeg = climbPerformance.timeMinutes(
            fromPressureAltitudeFeet: climbDeparturePressureAltitudeFeet,
            toPressureAltitudeFeet: climbTargetPressureAltitudeFeet
        )
        let fullClimbDistanceNM = climbDistancePerLeg * Double(profile.legs)
        let flownClimbFraction = fullClimbDistanceNM > 0
            ? min(1, climbDistanceNM / fullClimbDistanceNM)
            : 0
        let climbMinutes = climbMinutesPerLeg
            * Double(profile.legs)
            * flownClimbFraction
        let remainingSlowDistanceNM = min(
            max(0, routeNM - climbDistanceNM),
            max(0, slowDistanceNM - climbDistanceNM)
        )
        let cruiseDistanceNM = max(0.0, routeNM - climbDistanceNM - remainingSlowDistanceNM)
        let component = headwindKnots ?? 0.0
        let effectiveCruiseKnots = max(55.0, min(155.0, cruiseKnots - component))
        let localGroundMinutes = Double(
            profile.legs * (
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
        let profile = routeProfile(stopCount: stopCount)
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
        let groundStops = Double(
            profile.groundStops * max(0, tankStopMinutes)
        )
        return Int(round(
            (Double(total) - groundStops) / Double(profile.legs)
        ))
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

extension Destination {
    var runwayDimensionsDisplay: String {
        if let runwayWidthM {
            return "\(runwayM) × \(runwayWidthM) m"
        }
        return "\(runwayM) m"
    }

    var referenceRunwayDisplay: String {
        let dimensions = runwayDimensionsDisplay
        guard !referenceRunway.isEmpty else { return dimensions }
        return "\(dimensions)\n\(referenceRunway)"
    }

    var ldaDisplay: String {
        "\(runwayLDAM) m"
    }
}
