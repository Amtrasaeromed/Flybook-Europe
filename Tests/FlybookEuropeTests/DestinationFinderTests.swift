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

    func testIncompleteRouteWeatherRemainsDistinguishableFromRejection() {
        XCTAssertEqual(
            DestinationFinderEvaluator.evaluateRouteWeather(
                [.green, .unavailable, .blue],
                maximum: .blue
            ),
            .incomplete
        )
        XCTAssertEqual(
            DestinationFinderEvaluator.evaluateRouteWeather(
                [.green, .unavailable, .red],
                maximum: .blue
            ),
            .rejects
        )
    }

    func testPurpleRouteWeatherDoesNotRejectIncompleteRoute() {
        XCTAssertEqual(
            DestinationFinderEvaluator.evaluateRouteWeather(
                [.purple, .unavailable],
                maximum: .purple
            ),
            .incomplete
        )
    }

    func testMinimumWeatherCoverageAllowsThreeBadOfTwelveDaylightHours() {
        let categories = Array(repeating: FlightCategory.vfr, count: 9)
            + Array(repeating: FlightCategory.ifr, count: 3)

        XCTAssertTrue(
            DestinationFinderEvaluator.minimumWeatherMatches(
                categories,
                minimum: .mvfr,
                usesCoverageRule: true
            )
        )
    }

    func testMinimumWeatherCoverageRejectsLessThanSixtySixPercent() {
        let categories = Array(repeating: FlightCategory.vfr, count: 7)
            + Array(repeating: FlightCategory.ifr, count: 5)

        XCTAssertFalse(
            DestinationFinderEvaluator.minimumWeatherMatches(
                categories,
                minimum: .mvfr,
                usesCoverageRule: true
            )
        )
    }

    func testStrictMinimumWeatherStillRejectsOneBadHour() {
        XCTAssertFalse(
            DestinationFinderEvaluator.minimumWeatherMatches(
                [.vfr, .vfr, .ifr],
                minimum: .mvfr,
                usesCoverageRule: false
            )
        )
    }

    func testUnavailableWeatherCountsAsNotMeetingCoverage() {
        XCTAssertFalse(
            DestinationFinderEvaluator.minimumWeatherMatches(
                [.vfr, .unavailable],
                minimum: .mvfr,
                usesCoverageRule: true
            )
        )
    }

    func testMissingTargetWeatherNeverMatchesActiveWeatherFilter() {
        XCTAssertFalse(
            DestinationFinderEvaluator.weatherMatches(
                Optional<[DestinationFinderWeatherHour]>.none,
                criteria: criteria(minimumWeather: .mvfr),
                destination: destination
            )
        )
    }

    func testRainFreeCoverageRequiresSelectedPercentageOnEveryDay() {
        let firstDay = utcDate(year: 2026, month: 8, day: 17)
        let secondDay = utcDate(year: 2026, month: 8, day: 18)
        let firstDayHours = rainHours(
            on: firstDay,
            dryHours: 8,
            rainyHours: 4
        )
        let secondDayHours = rainHours(
            on: secondDay,
            dryHours: 8,
            rainyHours: 4
        )

        XCTAssertTrue(
            DestinationFinderEvaluator.rainFreeCoverageMatches(
                firstDayHours + secondDayHours,
                from: firstDay,
                until: secondDay.addingTimeInterval(23 * 3600),
                destination: destination,
                minimumCoverage: 0.625
            )
        )
    }

    func testGoodDayCannotCompensateForDayBelowRainFreeCoverage() {
        let firstDay = utcDate(year: 2026, month: 8, day: 17)
        let secondDay = utcDate(year: 2026, month: 8, day: 18)
        let firstDayHours = rainHours(
            on: firstDay,
            dryHours: 7,
            rainyHours: 5
        )
        let secondDayHours = rainHours(
            on: secondDay,
            dryHours: 12,
            rainyHours: 0
        )

        XCTAssertFalse(
            DestinationFinderEvaluator.rainFreeCoverageMatches(
                firstDayHours + secondDayHours,
                from: firstDay,
                until: secondDay.addingTimeInterval(23 * 3600),
                destination: destination,
                minimumCoverage: 0.625
            )
        )
    }

    func testBlueSkyCoverageRequiresSelectedPercentageOnEveryDay() {
        let firstDay = utcDate(year: 2026, month: 8, day: 17)
        let secondDay = utcDate(year: 2026, month: 8, day: 18)

        XCTAssertTrue(
            DestinationFinderEvaluator.blueSkyCoverageMatches(
                cloudHours(on: firstDay, acceptableHours: 8, overcastHours: 4)
                    + cloudHours(on: secondDay, acceptableHours: 8, overcastHours: 4),
                from: firstDay,
                until: secondDay.addingTimeInterval(23 * 3600),
                destination: destination,
                minimumCoverage: 0.625
            )
        )
    }

    func testClearDayCannotCompensateForDayBelowBlueSkyCoverage() {
        let firstDay = utcDate(year: 2026, month: 8, day: 17)
        let secondDay = utcDate(year: 2026, month: 8, day: 18)

        XCTAssertFalse(
            DestinationFinderEvaluator.blueSkyCoverageMatches(
                cloudHours(on: firstDay, acceptableHours: 7, overcastHours: 5)
                    + cloudHours(on: secondDay, acceptableHours: 12, overcastHours: 0),
                from: firstDay,
                until: secondDay.addingTimeInterval(23 * 3600),
                destination: destination,
                minimumCoverage: 0.625
            )
        )
    }

    func testEntirePeriodBlueSkyCoverageAllowsClearDayToCompensate() {
        let firstDay = utcDate(year: 2026, month: 8, day: 17)
        let secondDay = utcDate(year: 2026, month: 8, day: 18)

        XCTAssertTrue(
            DestinationFinderEvaluator.blueSkyCoverageMatches(
                cloudHours(on: firstDay, acceptableHours: 1, overcastHours: 9)
                    + cloudHours(on: secondDay, acceptableHours: 11, overcastHours: 0),
                from: firstDay,
                until: secondDay.addingTimeInterval(23 * 3600),
                destination: destination,
                minimumCoverage: 0.125,
                scope: .entirePeriod
            )
        )
    }

    func testMissingCloudValuesCountAgainstBlueSkyCoverage() {
        let day = utcDate(year: 2026, month: 8, day: 17)
        var samples = cloudHours(on: day, acceptableHours: 8, overcastHours: 3)
        for hour in [17, 18] {
            samples.append(DestinationFinderWeatherHour(
                instant: day.addingTimeInterval(Double(hour) * 3600),
                temperatureCelsius: 20,
                steadyWindKnots: 5,
                gustKnots: 8,
                precipitationMillimeters: 0,
                totalCloudCoverPercent: nil,
                visibilityMeters: 10_000,
                lowCloudCoverPercent: nil,
                dewPointCelsius: 10
            ))
        }

        XCTAssertFalse(
            DestinationFinderEvaluator.blueSkyCoverageMatches(
                samples,
                from: day,
                until: day.addingTimeInterval(23 * 3600),
                destination: destination,
                minimumCoverage: 0.625
            )
        )
    }

    func testCoverageAcceptsExactEightySevenPointFivePercent() {
        let day = utcDate(year: 2026, month: 8, day: 17)

        XCTAssertTrue(
            DestinationFinderEvaluator.rainFreeCoverageMatches(
                rainHours(on: day, dryHours: 7, rainyHours: 1),
                from: day,
                until: day.addingTimeInterval(23 * 3600),
                destination: destination,
                minimumCoverage: 0.875
            )
        )
        XCTAssertTrue(
            DestinationFinderEvaluator.blueSkyCoverageMatches(
                cloudHours(on: day, acceptableHours: 7, overcastHours: 1),
                from: day,
                until: day.addingTimeInterval(23 * 3600),
                destination: destination,
                minimumCoverage: 0.875
            )
        )
    }

    func testNightRainDoesNotCountAgainstRainFreeDaylightCoverage() {
        let day = utcDate(year: 2026, month: 8, day: 17)
        let nightRain = DestinationFinderWeatherHour(
            instant: day.addingTimeInterval(2 * 3600),
            temperatureCelsius: 15,
            steadyWindKnots: 5,
            gustKnots: 8,
            precipitationMillimeters: 2,
            totalCloudCoverPercent: 100,
            visibilityMeters: 5_000,
            lowCloudCoverPercent: 100,
            dewPointCelsius: 14
        )

        XCTAssertTrue(
            DestinationFinderEvaluator.rainFreeCoverageMatches(
                [nightRain] + rainHours(on: day, dryHours: 12, rainyHours: 0),
                from: day,
                until: day.addingTimeInterval(23 * 3600),
                destination: destination
            )
        )
    }

    func testNightRainCountsWhenDaytimeWeatherBlockIsDisabled() {
        let day = utcDate(year: 2026, month: 8, day: 17)
        let dryDaylight = rainHours(on: day, dryHours: 12, rainyHours: 0)
        let rainyNight = [0, 1, 2, 3, 4, 5, 22].map { hour in
            DestinationFinderWeatherHour(
                instant: day.addingTimeInterval(Double(hour) * 3600),
                temperatureCelsius: 15,
                steadyWindKnots: 5,
                gustKnots: 8,
                precipitationMillimeters: 0.1,
                totalCloudCoverPercent: 100,
                visibilityMeters: 5_000,
                lowCloudCoverPercent: 100,
                dewPointCelsius: 14
            )
        }

        XCTAssertFalse(
            DestinationFinderEvaluator.rainFreeCoverageMatches(
                dryDaylight + rainyNight,
                from: day,
                until: day.addingTimeInterval(23 * 3600),
                destination: destination,
                daylightOnly: false
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

    func testAnyMobilityAcceptsOneConfirmedService() {
        XCTAssertTrue(
            DestinationFinderEvaluator.mobilityMatches(
                bicycle: "?",
                rentalCar: "Nein",
                app2Drive: "?",
                rail: "Ja – Bahnhof 350 m",
                bus: "Nein",
                requiresBicycle: false,
                requiresRentalCar: false,
                requiresApp2Drive: false,
                requiresRail: false,
                requiresBus: false,
                requiresAny: true
            )
        )
    }

    func testAnyMobilityRejectsOnlyUnknownAndNegativeServices() {
        XCTAssertFalse(
            DestinationFinderEvaluator.mobilityMatches(
                bicycle: "?",
                rentalCar: "Nein",
                app2Drive: "? – nicht bestätigt",
                rail: "?",
                bus: "Nein",
                requiresBicycle: false,
                requiresRentalCar: false,
                requiresApp2Drive: false,
                requiresRail: false,
                requiresBus: false,
                requiresAny: true
            )
        )
    }

    func testSpecificRailAndBusFiltersRequireConfirmedValues() {
        XCTAssertFalse(
            DestinationFinderEvaluator.mobilityMatches(
                bicycle: "Ja",
                rentalCar: "Ja",
                app2Drive: "Ja",
                rail: "?",
                bus: "Ja",
                requiresBicycle: false,
                requiresRentalCar: false,
                requiresApp2Drive: false,
                requiresRail: true,
                requiresBus: true,
                requiresAny: false
            )
        )
        XCTAssertTrue(
            DestinationFinderEvaluator.mobilityMatches(
                bicycle: "Nein",
                rentalCar: "Nein",
                app2Drive: "Nein",
                rail: "Ja",
                bus: "Ja – Haltestelle 200 m",
                requiresBicycle: false,
                requiresRentalCar: false,
                requiresApp2Drive: false,
                requiresRail: true,
                requiresBus: true,
                requiresAny: false
            )
        )
    }

    @MainActor
    func testCountryOnlyFilterFindsEveryUKMergeAirport() async {
        let store = DestinationStore()
        let criteria = DestinationFinderCriteria(
            originICAO: "EDFZ",
            from: baseDate,
            until: baseDate.addingTimeInterval(24 * 3600),
            maximumTravelMinutes: 0,
            ignoresTravelTime: true,
            appliesETOPS: false,
            maximumRoundTripPriceEUR: 0,
            ignoresPrice: true,
            priceAppliesETOPS: true,
            requiredFeatures: [],
            allowedCountryCodes: ["GB"],
            minimumTemperatureCelsius: 0,
            ignoresMinimumTemperature: true,
            maximumTemperatureCelsius: 0,
            ignoresMaximumTemperature: true,
            maximumSteadyWindKnots: 0,
            ignoresWind: true,
            maximumGustKnots: 0,
            ignoresGusts: true,
            minimumWeather: .vfr,
            ignoresMinimumWeather: true,
            requiresRainFree: false,
            daylightOnly: false,
            daytimeOnly: false
        )

        let result = await DestinationFinderService.find(
            destinations: store.destinations,
            origins: [.edfz],
            criteria: criteria,
            aircraft: .a211,
            greenYellowMinutes: 105,
            orangeRedMinutes: 165,
            tankStopMinutes: 60,
            preTakeoffGroundMinutes: 7,
            postLandingGroundMinutes: 3,
            vatPercent: 7,
            weekdayDiscountEnabled: false,
            prepaymentDiscount15To29Enabled: false,
            prepaymentDiscount30PlusEnabled: false
        )
        let found = Set(result.matches.map(\.destinationICAO))
        let ukMergeICAOs = Set([
            "EGHN", "EGHJ", "EGHF", "EGKA", "EGMD",
            "EGHQ", "EGHR", "EGKH", "EGHA"
        ])

        XCTAssertTrue(
            found.isSuperset(of: ukMergeICAOs),
            "Im Länderfilter GB fehlen: \(ukMergeICAOs.subtracting(found).sorted())"
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

    func testDaylightWeatherBlockIgnoresNighttimeViolations() {
        let hours = [
            hour(offset: 0, temperature: 20),
            hour(offset: 12, temperature: 50)
        ]

        XCTAssertTrue(
            DestinationFinderEvaluator.weatherMatches(
                hours,
                criteria: criteria(
                    maximumTemperature: 30,
                    durationHours: 16,
                    daylightOnly: true
                ),
                destination: destination
            )
        )
        XCTAssertFalse(
            DestinationFinderEvaluator.weatherMatches(
                hours,
                criteria: criteria(
                    maximumTemperature: 30,
                    durationHours: 16,
                    daylightOnly: false
                ),
                destination: destination
            )
        )
    }

    func testMinimumWeatherRemainsDaylightOnlyWhenWeatherBlockUsesWholePeriod() {
        let hours = [
            hour(offset: 0),
            hour(
                offset: 12,
                temperature: 10,
                lowCloud: 80,
                dewPoint: 9
            )
        ]

        XCTAssertTrue(
            DestinationFinderEvaluator.weatherMatches(
                hours,
                criteria: criteria(
                    minimumWeather: .mvfr,
                    durationHours: 16,
                    daylightOnly: false,
                    minimumWeatherDaylightOnly: true
                ),
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
        requiresRainFree: Bool = false,
        durationHours: Int = 3,
        daylightOnly: Bool = false,
        minimumWeatherDaylightOnly: Bool = false
    ) -> DestinationFinderCriteria {
        DestinationFinderCriteria(
            originICAO: "EDFZ",
            from: baseDate,
            until: baseDate.addingTimeInterval(Double(durationHours) * 3600),
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
            requiresRainFree: requiresRainFree,
            daylightOnly: daylightOnly,
            daytimeOnly: false,
            minimumWeatherDaylightOnly: minimumWeatherDaylightOnly
        )
    }

    private var baseDate: Date {
        Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func utcDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day
        ))!
    }

    private func rainHours(
        on day: Date,
        dryHours: Int,
        rainyHours: Int
    ) -> [DestinationFinderWeatherHour] {
        (0..<(dryHours + rainyHours)).map { index in
            DestinationFinderWeatherHour(
                instant: day.addingTimeInterval(Double(index + 6) * 3600),
                temperatureCelsius: 20,
                steadyWindKnots: 5,
                gustKnots: 8,
                precipitationMillimeters: index < dryHours ? 0 : 0.1,
                totalCloudCoverPercent: 0,
                visibilityMeters: 10_000,
                lowCloudCoverPercent: 0,
                dewPointCelsius: 10
            )
        }
    }

    private func cloudHours(
        on day: Date,
        acceptableHours: Int,
        overcastHours: Int
    ) -> [DestinationFinderWeatherHour] {
        (0..<(acceptableHours + overcastHours)).map { index in
            DestinationFinderWeatherHour(
                instant: day.addingTimeInterval(Double(index + 6) * 3600),
                temperatureCelsius: 20,
                steadyWindKnots: 5,
                gustKnots: 8,
                precipitationMillimeters: 0,
                totalCloudCoverPercent: index < acceptableHours ? 50 : 51,
                visibilityMeters: 10_000,
                lowCloudCoverPercent: index < acceptableHours ? 50 : 51,
                dewPointCelsius: 10
            )
        }
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
