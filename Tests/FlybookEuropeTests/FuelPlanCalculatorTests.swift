import XCTest
@testable import FlybookEurope

final class FuelPlanCalculatorTests: XCTestCase {
    private let legs = [
        FuelPlanLeg(
            id: "A-C", originICAO: "A", destinationICAO: "C",
            flightMinutes: 30, consumptionLitersPerHour: 20
        ),
        FuelPlanLeg(
            id: "C-B", originICAO: "C", destinationICAO: "B",
            flightMinutes: 30, consumptionLitersPerHour: 20
        ),
        FuelPlanLeg(
            id: "B-A", originICAO: "B", destinationICAO: "A",
            flightMinutes: 30, consumptionLitersPerHour: 20
        )
    ]

    func testCalculatedLitersAreAlwaysRoundedUpToWholeLiters() {
        XCTAssertEqual(FuelPlanCalculator.roundedLitersForDisplay(39.2), 40)
        XCTAssertEqual(FuelPlanCalculator.roundedLitersForDisplay(39), 39)
        XCTAssertEqual(FuelPlanCalculator.roundedLitersForDisplay(0.2), 1)
        XCTAssertEqual(FuelPlanCalculator.roundedLitersForDisplay(-0.2), -1)
    }

    func testRefuelAtCReusesArrivalReserveForTheReturnTrip() {
        let result = FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: 45,
            usableFuelLiters: 60,
            startingFuelLiters: 25,
            refuelAfterLegIndex: 0,
            refuelLiters: 20
        )

        XCTAssertEqual(result.finalReserveLiters, 15, accuracy: 0.001)
        XCTAssertEqual(result.minimumStartingFuelLiters, 25, accuracy: 0.001)
        XCTAssertEqual(result.minimumRefuelLiters, 20, accuracy: 0.001)
        XCTAssertEqual(result.rows[1].minimumDepartureLiters, 35, accuracy: 0.001)
        XCTAssertEqual(result.rows[2].minimumDepartureLiters, 25, accuracy: 0.001)
        XCTAssertEqual(result.rows[2].plannedArrivalLiters, 15, accuracy: 0.001)
        XCTAssertFalse(result.hasWarning)
    }

    func testRefuelAtBRequiresEnoughStartingFuelToReachBWithReserve() {
        let result = FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: 45,
            usableFuelLiters: 60,
            startingFuelLiters: 35,
            refuelAfterLegIndex: 1,
            refuelLiters: 10
        )

        XCTAssertEqual(result.minimumStartingFuelLiters, 35, accuracy: 0.001)
        XCTAssertEqual(result.minimumRefuelLiters, 10, accuracy: 0.001)
        XCTAssertEqual(result.rows[1].minimumArrivalLiters, 15, accuracy: 0.001)
        XCTAssertEqual(result.rows[2].plannedArrivalLiters, 15, accuracy: 0.001)
        XCTAssertFalse(result.hasWarning)
    }

    func testTooSmallTankAndManualShortfallsAreWarnings() {
        let result = FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: 45,
            usableFuelLiters: 30,
            startingFuelLiters: 20,
            refuelAfterLegIndex: 1,
            refuelLiters: 5
        )

        XCTAssertTrue(result.hasCapacityViolation)
        XCTAssertTrue(result.hasStartingFuelShortfall)
        XCTAssertTrue(result.hasRefuelShortfall)
        XCTAssertTrue(result.hasFinalReserveShortfall)
        XCTAssertTrue(result.hasFuelExhaustion)
        XCTAssertLessThan(result.rows.last?.plannedArrivalLiters ?? 0, 0)
        XCTAssertTrue(result.hasWarning)
    }

    func testWithoutRefuelEverythingIsCalculatedBackFromFinalReserve() {
        let result = FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: 45,
            usableFuelLiters: 60,
            startingFuelLiters: 45,
            refuelAfterLegIndex: nil,
            refuelLiters: 0
        )

        XCTAssertEqual(result.minimumStartingFuelLiters, 45, accuracy: 0.001)
        XCTAssertEqual(result.rows.map(\.minimumDepartureLiters), [45, 35, 25])
        XCTAssertEqual(result.rows.map(\.minimumArrivalLiters), [35, 25, 15])
        XCTAssertFalse(result.hasWarning)
    }
}
