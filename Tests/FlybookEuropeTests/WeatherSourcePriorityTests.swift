import Foundation
import XCTest
@testable import FlybookEurope

final class WeatherSourcePriorityTests: XCTestCase {
    @MainActor
    func testLivePlanningWeatherWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment[
            "FLYBOOK_LIVE_WEATHER_TEST"
        ] == "1" else {
            throw XCTSkip("Nur für den expliziten Live-Quellencheck")
        }

        let timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let target = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: 1,
            to: Date()
        ))
        let airports = [
            AirportReference(
                icao: "EDLE",
                name: "Essen/Mülheim",
                latitude: 51.403,
                longitude: 6.9392,
                elevationFeet: 423,
                timeZone: timeZone,
                referenceRunway: "06/24"
            ),
            AirportReference.edfz
        ]

        for airport in airports {
            let forecast = try await EDFZWeatherService.shared.forecast(
                plannedDate: target,
                airport: airport,
                forceRefresh: true
            )
            XCTAssertFalse(forecast.samples.isEmpty, airport.icao)
            XCTAssertNotNil(
                forecast.sample(nearestTo: target),
                "Keine zeitlich passende Prognose für \(airport.icao)"
            )
        }

        let store = DestinationStore()
        let destination = try XCTUnwrap(
            store.destinations.first(where: { $0.icao == "EDLE" })
        )
        let destinationWeather = try await WeatherService.shared.weather(
            for: destination,
            targetInstants: [target],
            forceRefresh: true
        )
        XCTAssertGreaterThanOrEqual(
            destinationWeather.dailyForecast.count,
            10,
            "Die 10-Tage-Ansicht darf durch ICON Seamless nicht verkürzt werden"
        )
        XCTAssertTrue(
            destinationWeather.dailyForecast.prefix(5).allSatisfy {
                $0.model.contains("ICON Seamless")
            },
            "ICON Seamless muss in der Kurzfristprognose vorrangig bleiben"
        )
    }

    func testICONSeamlessRoutesHaveStrictPriority() {
        XCTAssertEqual(
            ICONSeamlessAccessRoute.allCases,
            [.dedicatedDWD, .genericForecast]
        )
    }

    func testEveryRouteRequestsICONSeamlessExplicitly() throws {
        for route in ICONSeamlessAccessRoute.allCases {
            let url = try XCTUnwrap(route.url(queryItems: [
                URLQueryItem(name: "latitude", value: "49.9675"),
                URLQueryItem(name: "longitude", value: "8.1472")
            ]))
            let components = try XCTUnwrap(
                URLComponents(url: url, resolvingAgainstBaseURL: false)
            )
            XCTAssertEqual(
                components.queryItems?.first(where: { $0.name == "models" })?.value,
                "icon_seamless"
            )
        }
    }

    func testBackupIsNotReportedAsICONSeamless() {
        XCTAssertTrue(
            EDFZForecastSource.iconSeamless(.dedicatedDWD).isICONSeamless
        )
        XCTAssertFalse(EDFZForecastSource.bestMatch.isICONSeamless)
        XCTAssertFalse(EDFZForecastSource.metNorway.isICONSeamless)
        XCTAssertFalse(EDFZForecastSource.mosmix.isICONSeamless)
    }

    func testOpenMeteoRetryAfterSecondsAreRespected() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let retry = try XCTUnwrap(
            OpenMeteoCircuitBreaker.retryDate(header: "900", now: now)
        )
        XCTAssertEqual(retry.timeIntervalSince(now), 900, accuracy: 0.1)
    }

    func testOpenMeteoDailyLimitWaitsUntilNextUTCDay() {
        let date = ISO8601DateFormatter().date(
            from: "2026-08-13T21:30:00Z"
        )!
        let expected = ISO8601DateFormatter().date(
            from: "2026-08-14T00:05:00Z"
        )!
        XCTAssertEqual(
            OpenMeteoCircuitBreaker.startOfNextUTCDay(after: date),
            expected
        )
    }

    func testMOSMIXKMZExtractorReadsDeflatedKML() throws {
        let encoded = "UEsDBBQAAAAIALCtDV3daiF9DwAAABAAAAAIAAAAdGVzdC5rbWyzyc7NsctIzcnJt9EHMQFQSwECFAMUAAAACACwrQ1d3WohfQ8AAAAQAAAACAAAAAAAAAAAAAAAgAEAAAAAdGVzdC5rbWxQSwUGAAAAAAEAAQA2AAAANQAAAAAA"
        let archive = try XCTUnwrap(Data(base64Encoded: encoded))
        let kml = try DWDMOSMIXService.firstFile(inKMZ: archive)
        XCTAssertEqual(String(data: kml, encoding: .utf8), "<kml>hello</kml>")
    }

    func testMOSMIXKMLIsConvertedToFlightWeather() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml:kml xmlns:kml="http://www.opengis.net/kml/2.2" xmlns:dwd="https://opendata.dwd.de/weather/lib/pointforecast_dwd_extension_V1_0.xsd">
          <dwd:TimeStep>2026-08-14T09:00:00.000Z</dwd:TimeStep>
          <dwd:Forecast dwd:elementName="TTT"><dwd:value>293.15</dwd:value></dwd:Forecast>
          <dwd:Forecast dwd:elementName="Td"><dwd:value>291.15</dwd:value></dwd:Forecast>
          <dwd:Forecast dwd:elementName="FF"><dwd:value>5</dwd:value></dwd:Forecast>
          <dwd:Forecast dwd:elementName="Nl"><dwd:value>80</dwd:value></dwd:Forecast>
          <dwd:Forecast dwd:elementName="VV"><dwd:value>4000</dwd:value></dwd:Forecast>
        </kml:kml>
        """
        let forecast = try DWDMOSMIXService.parseKML(
            Data(xml.utf8),
            retrievedAt: Date()
        )
        let sample = try XCTUnwrap(forecast.samples.first)
        XCTAssertEqual(sample.temperatureCelsius!, 20, accuracy: 0.01)
        XCTAssertEqual(sample.windSpeedKnots!, 9.71922, accuracy: 0.001)
        XCTAssertEqual(sample.ceilingFeetAGL!, 800, accuracy: 0.1)
        XCTAssertEqual(sample.category, .ifr)
    }

    func testLiveMOSMIXWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment[
            "FLYBOOK_LIVE_MOSMIX_TEST"
        ] == "1" else {
            throw XCTSkip("Nur für den expliziten DWD-MOSMIX-Quellencheck")
        }
        let forecast = try await DWDMOSMIXService.shared.forecast(
            airport: .edfz
        )
        XCTAssertFalse(forecast.samples.isEmpty)
        XCTAssertEqual(forecast.source, .mosmix)
    }
}
