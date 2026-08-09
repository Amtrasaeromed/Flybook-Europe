import XCTest
@testable import FlybookEurope

final class FlightMathTests: XCTestCase {
    func testRouteModelUsesOneNormalizedProfile() {
        XCTAssertEqual(FlightMath.routeMiles(directNM: 100, stopCount: 0), 115, accuracy: 0.001)
        XCTAssertEqual(FlightMath.routeMiles(directNM: 100, stopCount: 1), 135, accuracy: 0.001)
        XCTAssertEqual(FlightMath.routeMiles(directNM: 100, stopCount: 2), 155, accuracy: 0.001)
        XCTAssertEqual(
            FlightMath.routeMiles(directNM: 100, stopCount: -1),
            FlightMath.routeMiles(directNM: 100, stopCount: 0),
            accuracy: 0.001
        )
        XCTAssertEqual(
            FlightMath.routeMiles(directNM: 100, stopCount: 8),
            FlightMath.routeMiles(directNM: 100, stopCount: 2),
            accuracy: 0.001
        )
    }

    func testHeadwindIncreasesAndTailwindReducesDuration() {
        let tailwind = FlightMath.adjustedDurationMinutes(
            directNM: 150,
            stopCount: 0,
            headwindKnots: -20
        )
        let calm = FlightMath.adjustedDurationMinutes(
            directNM: 150,
            stopCount: 0,
            headwindKnots: 0
        )
        let headwind = FlightMath.adjustedDurationMinutes(
            directNM: 150,
            stopCount: 0,
            headwindKnots: 20
        )
        XCTAssertLessThan(tailwind, calm)
        XCTAssertLessThan(calm, headwind)
    }

    func testStopsIncreaseTotalTravelTime() {
        let direct = FlightMath.adjustedDurationMinutes(
            directNM: 150,
            stopCount: 0,
            headwindKnots: 0
        )
        let oneStop = FlightMath.adjustedDurationMinutes(
            directNM: 150,
            stopCount: 1,
            headwindKnots: 0
        )
        let twoStops = FlightMath.adjustedDurationMinutes(
            directNM: 150,
            stopCount: 2,
            headwindKnots: 0
        )
        XCTAssertLessThan(direct, oneStop)
        XCTAssertLessThan(oneStop, twoStops)
    }

    func testDirectMilesFollowSelectedIntermediateAirports() {
        let airports = [
            AirportReference(icao: "A", name: "A", latitude: 50, longitude: 8, elevationFeet: 0, timeZone: .gmt),
            AirportReference(icao: "B", name: "B", latitude: 51, longitude: 8, elevationFeet: 0, timeZone: .gmt),
            AirportReference(icao: "C", name: "C", latitude: 51, longitude: 9, elevationFeet: 0, timeZone: .gmt)
        ]
        let expected = AirportDistance.nauticalMiles(from: airports[0], to: airports[1])
            + AirportDistance.nauticalMiles(from: airports[1], to: airports[2])
        XCTAssertEqual(FlightMath.directMiles(along: airports), expected, accuracy: 0.001)
    }
}
