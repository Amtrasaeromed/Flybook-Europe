import Foundation

extension RunwayPerformance {
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

}
