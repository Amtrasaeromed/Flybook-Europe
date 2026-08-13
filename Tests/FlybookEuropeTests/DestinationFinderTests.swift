import XCTest
@testable import FlybookEurope

final class DestinationFinderTests: XCTestCase {
    func testRouteWeatherMinimumRejectsWorseSegmentsAndMissingData() {
        XCTAssertTrue(
            DestinationFinderEvaluator.routeWeatherMatches(
                [.green, .blue, .green],
                maximum: .blue
            )
        )
        XCTAssertFalse(
            DestinationFinderEvaluator.routeWeatherMatches(
                [.green, .red],
                maximum: .blue
            )
        )
        XCTAssertFalse(
            DestinationFinderEvaluator.routeWeatherMatches(
                [.green, .unavailable],
                maximum: .purple
            )
        )
    }

    private let destination = AirportReference(
        icao: "TEST",
        name: "Test",
        latitude: 50,
        longitude: 8,
        elevationFeet: 300,
        timeZone: TimeZone(secondsFromGMT: 0)!
    )

    func testFinderOffersEveryCategoryFromMasterTable() {
        XCTAssertEqual(
            DestinationFeature.finderCases,
            [
                .techStop,
                .breakfast,
                .city,
                .beachSea,
                .lakeNature,
                .mountainHiking,
                .wellness
            ]
        )
    }

    func testMultipleCategoriesUseOrSemantics() {
        XCTAssertTrue(
            DestinationFinderEvaluator.featuresMatch(
                destinationFeatures: [.breakfast],
                requiredFeatures: [.breakfast, .beachSea]
            )
        )
        XCTAssertFalse(
            DestinationFinderEvaluator.featuresMatch(
                destinationFeatures: [.city],
                requiredFeatures: [.breakfast, .beachSea]
            )
        )
    }

    func testOneTemperatureValueAboveMinimumIsEnough() {
        let hours = [hour(offset: 0, temperature: 9), hour(offset: 1, temperature: 12)]
        XCTAssertTrue(
            DestinationFinderEvaluator.weatherMatches(
                hours,
                criteria: criteria(minimumTemperature: 10),
                destination: destination
            )
        )
    }

    func testOneWindValueAboveMaximumRejectsDestination() {
        let hours = [hour(offset: 0, wind: 10), hour(offset: 1, wind: 16)]
        XCTAssertFalse(
            DestinationFinderEvaluator.weatherMatches(
                hours,
                criteria: criteria(maximumWind: 15),
                destination: destination
            )
        )
    }

    func testWindFilterCanBeIgnored() {
        let hours = [hour(offset: 0, wind: 28)]
        XCTAssertTrue(
            DestinationFinderEvaluator.weatherMatches(
                hours,
                criteria: criteria(maximumWind: 10, ignoresWind: true),
                destination: destination
            )
        )
    }

    func testOneTemperatureValueAboveMaximumRejectsDestination() {
        let hours = [hour(offset: 0, temperature: 21), hour(offset: 1, temperature: 31)]
        XCTAssertFalse(
            DestinationFinderEvaluator.weatherMatches(
                hours,
                criteria: criteria(maximumTemperature: 30),
                destination: destination
            )
        )
    }

    func testGustFilterCanBeIgnored() {
        let hours = [hour(offset: 0, gust: 40)]
        XCTAssertTrue(
            DestinationFinderEvaluator.weatherMatches(
                hours,
                criteria: criteria(maximumGust: 20, ignoresGusts: true),
                destination: destination
            )
        )
    }

    func testOneMVFRHourRejectsVFRRequirement() {
        let hours = [
            hour(offset: 0),
            hour(
                offset: 1,
                temperature: 10,
                lowCloud: 80,
                dewPoint: 5
            )
        ]
        XCTAssertFalse(
            DestinationFinderEvaluator.weatherMatches(
                hours,
                criteria: criteria(minimumWeather: .vfr),
                destination: destination
            )
        )
        XCTAssertTrue(
            DestinationFinderEvaluator.weatherMatches(
                hours,
                criteria: criteria(minimumWeather: .mvfr),
                destination: destination
            )
        )
    }

    func testPointOneMillimeterRainRejectsRainFreeDestination() {
        let hours = [hour(offset: 0, precipitation: 0.1)]
        XCTAssertFalse(
            DestinationFinderEvaluator.weatherMatches(
                hours,
                criteria: criteria(requiresRainFree: true),
                destination: destination
            )
        )
    }

    func testRoundTripPriceRoundsEachLegLikeCharterCalculation() {
        XCTAssertEqual(
            DestinationFinderPricing.roundTripCost(
                outboundMinutes: 65,
                returnMinutes: 65,
                outboundDate: baseDate,
                returnDate: baseDate,
                hourlyRateEUR: 100,
                vatPercent: 0,
                weekdayDiscountEnabled: false,
                prepaymentDiscount15To29Enabled: false,
                prepaymentDiscount30PlusEnabled: false
            ),
            220,
            accuracy: 0.0001
        )
    }

    func testVoucherFilterUsesLandegutParticipantForFlightDate() {
        let date = baseDate
        XCTAssertTrue(
            DestinationFinderEvaluator.landingVoucherMatches(
                icao: "EDLA",
                flightDate: date,
                required: true,
                voucherProvider: { icao, suppliedDate in
                    icao == "EDLA" && suppliedDate == date
                }
            )
        )
        XCTAssertFalse(
            DestinationFinderEvaluator.landingVoucherMatches(
                icao: "EDFZ",
                flightDate: date,
                required: true,
                voucherProvider: { icao, _ in icao == "EDLA" }
            )
        )
        XCTAssertTrue(
            DestinationFinderEvaluator.landingVoucherMatches(
                icao: "EDFZ",
                flightDate: date,
                required: false,
                voucherProvider: { _, _ in false }
            )
        )
    }

    func testVoucherWebsiteYearMustMatchBeforeCaching() {
        XCTAssertTrue(
            LandingVoucherBook.pageContainsParticipantList(
                for: 2026,
                in: "<h3>Teilnehmerliste 2026</h3><li>EDLA</li>"
            )
        )
        XCTAssertFalse(
            LandingVoucherBook.pageContainsParticipantList(
                for: 2027,
                in: "<h3>Teilnehmerliste 2026</h3><li>EDLA</li>"
            )
        )
    }

    private func criteria(
        minimumTemperature: Double = -10,
        maximumTemperature: Double = 40,
        maximumWind: Double = 30,
        ignoresWind: Bool = false,
        maximumGust: Double = 50,
        ignoresGusts: Bool = false,
        minimumWeather: DestinationFinderMinimumWeather = .vfr,
        requiresRainFree: Bool = false
    ) -> DestinationFinderCriteria {
        DestinationFinderCriteria(
            originICAO: "EDFZ",
            from: baseDate,
            until: baseDate.addingTimeInterval(3 * 3600),
            maximumTravelMinutes: 420,
            appliesETOPS: false,
            maximumRoundTripPriceEUR: 3_000,
            priceAppliesETOPS: false,
            requiredFeatures: [],
            minimumTemperatureCelsius: minimumTemperature,
            maximumTemperatureCelsius: maximumTemperature,
            maximumSteadyWindKnots: maximumWind,
            ignoresWind: ignoresWind,
            maximumGustKnots: maximumGust,
            ignoresGusts: ignoresGusts,
            minimumWeather: minimumWeather,
            requiresCloudless: false,
            requiresRainFree: requiresRainFree,
            daylightOnly: false,
            daytimeOnly: false
        )
    }

    private var baseDate: Date {
        Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func hour(
        offset: Int,
        temperature: Double = 20,
        wind: Double = 5,
        gust: Double = 8,
        precipitation: Double = 0,
        cloud: Double = 0,
        lowCloud: Double = 0,
        dewPoint: Double = 0
    ) -> DestinationFinderWeatherHour {
        DestinationFinderWeatherHour(
            instant: baseDate.addingTimeInterval(Double(offset) * 3600),
            temperatureCelsius: temperature,
            steadyWindKnots: wind,
            gustKnots: gust,
            precipitationMillimeters: precipitation,
            totalCloudCoverPercent: cloud,
            visibilityMeters: 10_000,
            lowCloudCoverPercent: lowCloud,
            dewPointCelsius: dewPoint
        )
    }
}
