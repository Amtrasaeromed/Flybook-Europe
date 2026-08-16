import Foundation

struct RunwayPerformanceProfile: Equatable {
    let maximumTakeoffWeightKilograms: Double
    let takeoffRollMeters: Double
    let takeoffOver50FeetMeters: Double
    let landingRollMeters: Double
    let landingOver50FeetMeters: Double
}

struct RunwayPerformanceResult: Equatable {
    let rollMeters: Int
    let over50FeetMeters: Int

    func runwayPercentage(availableMeters: Int) -> Int? {
        guard availableMeters > 0 else { return nil }
        return Int(ceil(Double(rollMeters) / Double(availableMeters) * 100))
    }

    func addingSafetyMargin(percent: Int) -> RunwayPerformanceResult {
        let clampedPercent = min(50, max(0, percent))
        let factor = 1 + Double(clampedPercent) / 100
        return RunwayPerformanceResult(
            rollMeters: Int(ceil(Double(rollMeters) * factor)),
            over50FeetMeters: Int(ceil(Double(over50FeetMeters) * factor))
        )
    }
}

enum RunwayPerformance {
    static func profile(for aircraft: AircraftType) -> RunwayPerformanceProfile? {
        let normalizedName = AircraftRegistry.name(for: aircraft)
            .uppercased()
            .replacingOccurrences(of: "-", with: "")
        let isA211 = aircraft == .a211
            || ["A211", "DEUKS", "DEZHS"].contains(normalizedName)
        guard isA211 else { return nil }
        return RunwayPerformanceProfile(
            maximumTakeoffWeightKilograms: max(
                1,
                AircraftProfileStore.mtowKilograms(for: aircraft)
            ),
            takeoffRollMeters: 250,
            takeoffOver50FeetMeters: 430,
            landingRollMeters: 210,
            landingOver50FeetMeters: 500
        )
    }

    static func densityAltitudeFeet(
        elevationFeet: Double,
        temperatureCelsius: Double?,
        pressureHPA: Double?
    ) -> Double? {
        guard let temperatureCelsius, let pressureHPA else { return nil }
        let pressureAltitude = elevationFeet + (1013.25 - pressureHPA) * 30
        let isaTemperature = 15 - 1.98 * (pressureAltitude / 1_000)
        return pressureAltitude + 120 * (temperatureCelsius - isaTemperature)
    }

    static func takeoff(
        profile: RunwayPerformanceProfile,
        weightKilograms: Double,
        densityAltitudeFeet: Double,
        headwindKnots: Double
    ) -> RunwayPerformanceResult {
        let weightFactor = pow(max(1, weightKilograms) / profile.maximumTakeoffWeightKilograms, 2)
        let altitudeThousands = max(-1, densityAltitudeFeet / 1_000)
        let windDenominator = max(20, 50 + headwindKnots)
        let windFactor = pow(50 / windDenominator, 2)
        return RunwayPerformanceResult(
            rollMeters: safeMeters(
                profile.takeoffRollMeters
                    * max(0.75, 1 + 0.068 * altitudeThousands)
                    * weightFactor * windFactor
            ),
            over50FeetMeters: safeMeters(
                profile.takeoffOver50FeetMeters
                    * max(0.72, 1 + 0.106 * altitudeThousands)
                    * weightFactor * windFactor
            )
        )
    }

    static func landing(
        profile: RunwayPerformanceProfile,
        weightKilograms: Double,
        densityAltitudeFeet: Double,
        headwindKnots: Double
    ) -> RunwayPerformanceResult {
        let weightFactor = pow(max(1, weightKilograms) / profile.maximumTakeoffWeightKilograms, 2)
        let altitudeThousands = max(-1, densityAltitudeFeet / 1_000)
        let windFactor = headwindKnots >= 0
            ? max(0.5, 1 - 0.0111 * headwindKnots)
            : 1 + 0.05 * abs(headwindKnots)
        return RunwayPerformanceResult(
            rollMeters: safeMeters(
                profile.landingRollMeters
                    * max(0.75, 1 + 0.089 * altitudeThousands)
                    * weightFactor * windFactor
            ),
            over50FeetMeters: safeMeters(
                profile.landingOver50FeetMeters
                    * max(0.75, 1 + 0.074 * altitudeThousands)
                    * weightFactor * windFactor
            )
        )
    }

    private static func safeMeters(_ value: Double) -> Int {
        // Operational values are always rounded upward to the safety side.
        max(0, Int(ceil(value)))
    }
}
