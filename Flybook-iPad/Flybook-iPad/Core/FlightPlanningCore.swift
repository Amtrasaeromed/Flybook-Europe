import Foundation

struct IPadClimbPerformance: Hashable {
    let speedKIAS: Double
    let times: [Double]
    let distances: [Double]

    private let altitudes = [0.0, 1_000, 3_000, 5_000, 7_000, 10_000]

    private func value(at altitude: Double, values: [Double]) -> Double {
        let points = [0.0] + values
        let height = max(0, altitude)
        for index in 1..<altitudes.count where height <= altitudes[index] {
            let fraction = (height - altitudes[index - 1]) / (altitudes[index] - altitudes[index - 1])
            return points[index - 1] + fraction * (points[index] - points[index - 1])
        }
        let last = altitudes.count - 1
        let fraction = (height - altitudes[last - 1]) / (altitudes[last] - altitudes[last - 1])
        return points[last - 1] + fraction * (points[last] - points[last - 1])
    }

    func timeMinutes(from departure: Double, to target: Double) -> Double {
        max(0, value(at: target, values: times) - value(at: departure, values: times))
    }

    func distanceNM(from departure: Double, to target: Double) -> Double {
        max(0, value(at: target, values: distances) - value(at: departure, values: distances))
    }
}

struct IPadCruisePerformance: Hashable {
    let powerPercent: Int
    let tas: [Double]
    let fuel: [Double]
    private let altitudes = [1_000.0, 3_000, 5_000, 7_000, 10_000]

    private func interpolated(_ values: [Double], altitude: Double) -> Double? {
        guard values.count == altitudes.count, values.allSatisfy({ $0 > 0 }) else { return nil }
        let height = max(altitudes[0], altitude)
        for index in 1..<altitudes.count where height <= altitudes[index] {
            let fraction = (height - altitudes[index - 1]) / (altitudes[index] - altitudes[index - 1])
            return values[index - 1] + fraction * (values[index] - values[index - 1])
        }
        let last = altitudes.count - 1
        let fraction = (height - altitudes[last - 1]) / (altitudes[last] - altitudes[last - 1])
        return values[last - 1] + fraction * (values[last] - values[last - 1])
    }

    func tasKnots(at altitude: Double) -> Double? { interpolated(tas, altitude: altitude) }
    func fuelLitersPerHour(at altitude: Double) -> Double? { interpolated(fuel, altitude: altitude) }
}

struct IPadAircraftPerformance: Hashable {
    let name: String
    let hourlyRateEUR: Double
    let usableFuelLiters: Double
    let maximumTakeoffWeightKilograms: Double
    let noiseLevelDBA: Double?
    let hasIncreasedNoiseProtection: Bool
    let preferredFuelCode: String
    let approvedFuelCodes: Set<String>
    let fallbackCruiseKnots: Double
    let fallbackFuelLitersPerHour: Double
    let climb: IPadClimbPerformance
    let cruise: IPadCruisePerformance
}

enum IPadAircraftPerformanceStore {
    static func profile(named name: String) -> IPadAircraftPerformance {
        let normalized = name.uppercased()
        let isDETIK = normalized == "DETIK"
        let isDEZHS = normalized == "DEZHS"
        let climb = isDETIK
            ? IPadClimbPerformance(
                speedKIAS: 79,
                times: [1.6, 5.3, 9.8, 15.6, 29.6],
                distances: [2.1, 7.0, 12.9, 20.6, 39.0]
            )
            : IPadClimbPerformance(
                speedKIAS: 65,
                times: [1.5, 4.8, 8.8, 13.0, 23.2],
                distances: [1.6, 5.5, 9.7, 15.4, 27.2]
            )
        let cruise: IPadCruisePerformance
        if isDETIK {
            cruise = IPadCruisePerformance(
                powerPercent: 65,
                tas: [104, 106, 107.5, 109, 111],
                fuel: [40, 40, 40, 40, 40]
            )
        } else if isDEZHS {
            cruise = IPadCruisePerformance(
                powerPercent: 65,
                tas: [107, 109, 111, 113, 116],
                fuel: [21.5, 21.5, 21.5, 23.75, 23.5]
            )
        } else {
            cruise = IPadCruisePerformance(
                powerPercent: 65,
                tas: [107, 109, 111, 113, 116],
                fuel: [21.15, 21.4, 21.9, 22.65, 23.0]
            )
        }
        return IPadAircraftPerformance(
            name: name,
            hourlyRateEUR: isDETIK ? 191 : 149,
            usableFuelLiters: isDETIK ? 182 : (isDEZHS ? 97 : 110),
            maximumTakeoffWeightKilograms: isDETIK ? 1_110 : 750,
            noiseLevelDBA: isDETIK ? nil : (isDEZHS ? 63.9 : 65.1),
            hasIncreasedNoiseProtection: !isDETIK,
            preferredFuelCode: isDETIK ? "AVGAS" : "MOGAS_SUPER",
            approvedFuelCodes: isDETIK
                ? ["AVGAS"]
                : ["AVGAS", "UL91", "UL94", "MOGAS_SUPER"],
            fallbackCruiseKnots: isDETIK ? 110 : 105,
            fallbackFuelLitersPerHour: isDETIK ? 40 : (isDEZHS ? 24 : 25),
            climb: climb,
            cruise: cruise
        )
    }
}

enum IPadFlightMath {
    private static func routeProfile(stopCount: Int) -> (extraNM: Double, slowNM: Double, stops: Int, legs: Int) {
        switch min(2, max(0, stopCount)) {
        case 0: return (10, 10, 0, 1)
        case 2: return (50, 30, 2, 3)
        default: return (30, 20, 1, 2)
        }
    }

    static func minutes(
        directNM: Double,
        stopCount: Int,
        headwindKnots: Double?,
        tankStopMinutes: Int,
        altitudeFeet: Int,
        departureElevationFeet: Int,
        performance: IPadAircraftPerformance,
        trackMilesNM: Double?,
        preTakeoffGroundMinutes: Int,
        postLandingGroundMinutes: Int
    ) -> Int {
        let profile = routeProfile(stopCount: stopCount)
        let routeNM = max(0, trackMilesNM ?? directNM * 1.05 + profile.extraNM)
        let target = Double(altitudeFeet)
        let departure = Double(departureElevationFeet)
        let cruiseKnots = max(60, performance.cruise.tasKnots(at: target) ?? performance.fallbackCruiseKnots)
        let climbDistancePerLeg = performance.climb.distanceNM(from: departure, to: target)
        let climbDistance = min(routeNM, climbDistancePerLeg * Double(profile.legs))
        let fullClimbDistance = climbDistancePerLeg * Double(profile.legs)
        let climbFraction = fullClimbDistance > 0 ? min(1, climbDistance / fullClimbDistance) : 0
        let climbMinutes = performance.climb.timeMinutes(from: departure, to: target)
            * Double(profile.legs) * climbFraction
        let remainingSlow = min(max(0, routeNM - climbDistance), max(0, profile.slowNM - climbDistance))
        let cruiseDistance = max(0, routeNM - climbDistance - remainingSlow)
        let effectiveCruise = max(55, min(155, cruiseKnots - (headwindKnots ?? 0)))
        let localGround = Double(profile.legs * (max(0, preTakeoffGroundMinutes) + max(0, postLandingGroundMinutes)))
        let result = cruiseDistance / effectiveCruise * 60
            + climbMinutes
            + remainingSlow / 75 * 60
            + Double(profile.stops * max(0, tankStopMinutes))
            + localGround
        return Int(result.rounded())
    }

    static func perLegMinutes(totalMinutes: Int, stopCount: Int, tankStopMinutes: Int) -> Int {
        let profile = routeProfile(stopCount: stopCount)
        return Int(((Double(totalMinutes - profile.stops * max(0, tankStopMinutes))) / Double(profile.legs)).rounded())
    }
}

enum IPadCharterMath {
    static func commercialHours(minutes: Int) -> Double {
        ceil(Double(max(0, minutes)) / 6) / 10
    }
}
