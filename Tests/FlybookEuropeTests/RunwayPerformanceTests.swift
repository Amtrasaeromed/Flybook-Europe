import XCTest
@testable import FlybookEurope

final class RunwayPerformanceTests: XCTestCase {
    private let profile = RunwayPerformanceProfile(
        maximumTakeoffWeightKilograms: 750,
        takeoffRollMeters: 250,
        takeoffOver50FeetMeters: 430,
        landingRollMeters: 210,
        landingOver50FeetMeters: 500
    )

    func testA211TakeoffMatchesPOHWorkedExample() {
        let densityAltitude = RunwayPerformance.densityAltitudeFeet(
            elevationFeet: 1_800,
            temperatureCelsius: 18,
            pressureHPA: 1_013.25
        )!
        let result = RunwayPerformance.takeoff(
            profile: profile,
            weightKilograms: 720,
            densityAltitudeFeet: densityAltitude,
            headwindKnots: 8
        )

        XCTAssertEqual(result.rollMeters, 203, accuracy: 2)
        XCTAssertEqual(result.over50FeetMeters, 376, accuracy: 2)
    }

    func testA211LandingMatchesPOHWorkedExample() {
        let densityAltitude = RunwayPerformance.densityAltitudeFeet(
            elevationFeet: 380,
            temperatureCelsius: 20,
            pressureHPA: 1_013.25
        )!
        let result = RunwayPerformance.landing(
            profile: profile,
            weightKilograms: 659,
            densityAltitudeFeet: densityAltitude,
            headwindKnots: 9
        )

        XCTAssertEqual(result.rollMeters, 160, accuracy: 2)
        XCTAssertEqual(result.over50FeetMeters, 376, accuracy: 2)
    }

    func testTailwindAndHigherWeightNeverImproveTakeoffResult() {
        let lightHeadwind = RunwayPerformance.takeoff(
            profile: profile,
            weightKilograms: 650,
            densityAltitudeFeet: 1_000,
            headwindKnots: 8
        )
        let heavyTailwind = RunwayPerformance.takeoff(
            profile: profile,
            weightKilograms: 750,
            densityAltitudeFeet: 1_000,
            headwindKnots: -5
        )

        XCTAssertGreaterThan(heavyTailwind.rollMeters, lightHeadwind.rollMeters)
        XCTAssertGreaterThan(heavyTailwind.over50FeetMeters, lightHeadwind.over50FeetMeters)
    }

    func testRunwayPercentageRoundsUp() {
        let result = RunwayPerformanceResult(
            rollMeters: 251,
            over50FeetMeters: 430
        )
        XCTAssertEqual(result.runwayPercentage(availableMeters: 1_000), 26)
    }
}
