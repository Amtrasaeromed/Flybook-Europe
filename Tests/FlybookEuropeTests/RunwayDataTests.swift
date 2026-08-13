import XCTest
@testable import FlybookEurope

@MainActor
final class RunwayDataTests: XCTestCase {
    func testEveryDestinationHasRequiredTechnicalData() {
        let store = DestinationStore()

        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.destinations.count, 128)
        XCTAssertEqual(
            store.destinations.filter { $0.icao != "EDFZ" }.count,
            127
        )

        for destination in store.destinations {
            XCTAssertFalse(
                destination.referenceRunway.isEmpty,
                "Missing reference runway for \(destination.icao)"
            )
            XCTAssertGreaterThan(
                destination.runwayM,
                0,
                "Invalid runway length for \(destination.icao)"
            )
            XCTAssertTrue(
                destination.elevationFeet.isFinite,
                "Invalid elevation for \(destination.icao)"
            )
            XCTAssertGreaterThanOrEqual(destination.elevationFeet, -100)
            XCTAssertLessThan(destination.elevationFeet, 5_000)
            let width = try? XCTUnwrap(
                destination.runwayWidthM,
                "Missing runway width for \(destination.icao)"
            )
            XCTAssertGreaterThan(width ?? 0, 0)
            XCTAssertGreaterThan(
                destination.runwayLDAM,
                0,
                "Invalid LDA for \(destination.icao)"
            )
            XCTAssertLessThanOrEqual(
                destination.runwayLDAM,
                destination.runwayM,
                "LDA exceeds physical runway length for \(destination.icao)"
            )
            XCTAssertNotNil(
                TimeZone(identifier: destination.timeZoneIdentifier),
                "Invalid timezone for \(destination.icao)"
            )
            if destination.grassOnly {
                XCTAssertTrue(
                    destination.surface.localizedCaseInsensitiveContains("Gras"),
                    "Grass-only flag and surface disagree for \(destination.icao)"
                )
            }
        }
    }

    func testPreferredAlternatesAreStandardTechStopDestinations() throws {
        let store = DestinationStore()
        let byICAO = Dictionary(
            uniqueKeysWithValues: store.destinations.map { ($0.icao, $0) }
        )

        for icao in ["EDFE", "EDFM", "EDRY", "EDRK"] {
            let destination = try XCTUnwrap(
                byICAO[icao],
                "Preferred alternate \(icao) is missing from standard data"
            )
            XCTAssertTrue(
                destination.features.contains(.techStop),
                "Preferred alternate \(icao) is missing the TechStop feature"
            )
        }
    }

    func testKnownMultiRunwayReferencesUseConfiguredReferenceRunway() throws {
        let store = DestinationStore()
        let byICAO = Dictionary(uniqueKeysWithValues: store.destinations.map { ($0.icao, $0) })

        XCTAssertEqual(try XCTUnwrap(byICAO["EDXH"]).referenceRunway, "15/33")
        XCTAssertEqual(try XCTUnwrap(byICAO["LSZL"]).referenceRunway, "08L/26R")
        XCTAssertEqual(try XCTUnwrap(byICAO["LFLP"]).referenceRunway, "04/22")
        XCTAssertEqual(try XCTUnwrap(byICAO["EHHV"]).referenceRunway, "18/36")
    }

    func testFeaturesAreEqualLevelAndDoNotInventTourismForPureTechstops() throws {
        let store = DestinationStore()
        let byICAO = Dictionary(uniqueKeysWithValues: store.destinations.map { ($0.icao, $0) })

        let strausberg = try XCTUnwrap(byICAO["EDAY"])
        XCTAssertEqual(strausberg.features, [.techStop])

        let luebeck = try XCTUnwrap(byICAO["EDHL"])
        XCTAssertTrue(luebeck.features.contains(.techStop))
        XCTAssertTrue(luebeck.features.contains(.lakeNature))

        let texel = try XCTUnwrap(byICAO["EHTX"])
        XCTAssertTrue(texel.features.contains(.beachSea))
        XCTAssertFalse(texel.features.contains(.techStop))
    }

    func testBreakfastCategoryContainsRequestedAirports() throws {
        let store = DestinationStore()
        let breakfastICAOs = Set(
            store.destinations
                .filter { $0.features.contains(.breakfast) }
                .map(\.icao)
        )

        XCTAssertEqual(
            breakfastICAOs,
            Set(["LSZB", "LSZG", "EDNH", "EDWC", "EDVM", "EDXE", "EDVI", "EDLD", "EDKB"])
        )
    }

    func testCorrectedRunwayDimensionsAndLDA() throws {
        let store = DestinationStore()
        let byICAO = Dictionary(uniqueKeysWithValues: store.destinations.map { ($0.icao, $0) })
        XCTAssertEqual(try XCTUnwrap(byICAO["EDKB"]).runwayWidthM, 30)
        XCTAssertEqual(try XCTUnwrap(byICAO["EDNH"]).runwayWidthM, 30)
        XCTAssertEqual(try XCTUnwrap(byICAO["EDXE"]).runwayM, 920)
        XCTAssertEqual(try XCTUnwrap(byICAO["EDXE"]).runwayWidthM, 30)
        XCTAssertEqual(try XCTUnwrap(byICAO["EDXE"]).runwayLDAM, 633)
        XCTAssertEqual(try XCTUnwrap(byICAO["EKAE"]).runwayWidthM, 30)
    }

    func testCityAndCorrectedVacationCategories() throws {
        let store = DestinationStore()
        let byICAO = Dictionary(uniqueKeysWithValues: store.destinations.map { ($0.icao, $0) })
        XCTAssertTrue(try XCTUnwrap(byICAO["LFGA"]).features.contains(.city))
        XCTAssertTrue(try XCTUnwrap(byICAO["EDTF"]).features.contains(.city))
        XCTAssertTrue(try XCTUnwrap(byICAO["LOWS"]).features.isSuperset(of: [.city, .wellness, .mountainHiking]))
        XCTAssertTrue(try XCTUnwrap(byICAO["EDCG"]).features.contains(.beachSea))
        XCTAssertTrue(try XCTUnwrap(byICAO["LIEO"]).features.contains(.beachSea))
        for icao in ["LIPB", "LIDT", "LSGS"] {
            let destination = try XCTUnwrap(byICAO[icao])
            XCTAssertTrue(destination.features.contains(.mountainHiking))
            XCTAssertTrue(destination.features.contains(.lakeNature))
        }
    }

    func testBreakfastAndCityAreFinderFilters() {
        XCTAssertTrue(DestinationFeature.finderCases.contains(.breakfast))
        XCTAssertTrue(DestinationFeature.finderCases.contains(.city))
    }

    func testBritishAndChannelIslandTimeZones() throws {
        let store = DestinationStore()
        let byICAO = Dictionary(uniqueKeysWithValues: store.destinations.map { ($0.icao, $0) })
        XCTAssertEqual(try XCTUnwrap(byICAO["EGKA"]).timeZoneIdentifier, "Europe/London")
        XCTAssertEqual(try XCTUnwrap(byICAO["EGJB"]).timeZoneIdentifier, "Europe/Guernsey")
        XCTAssertEqual(try XCTUnwrap(byICAO["EGJJ"]).timeZoneIdentifier, "Europe/Jersey")
    }

    func testAuditedElevationsAreLoaded() throws {
        let store = DestinationStore()
        let byICAO = Dictionary(uniqueKeysWithValues: store.destinations.map { ($0.icao, $0) })

        XCTAssertEqual(try XCTUnwrap(byICAO["LOSM"]).elevationFeet, 3_642)
        XCTAssertEqual(try XCTUnwrap(byICAO["EDWJ"]).elevationFeet, 8)
        XCTAssertEqual(try XCTUnwrap(byICAO["EHLE"]).elevationFeet, -12)
        XCTAssertEqual(try XCTUnwrap(byICAO["EDKM"]).elevationFeet, 1_436)
    }

    func testAmelandAIPFuelTypesAndFacilitiesAreLoaded() throws {
        let store = DestinationStore()
        let ameland = try XCTUnwrap(
            store.destinations.first { $0.icao == "EHAL" }
        )

        XCTAssertEqual(ameland.avgas, "Ja")
        XCTAssertEqual(ameland.mogas, "Ja")
        XCTAssertEqual(ameland.jetA1, "Ja")
        XCTAssertEqual(ameland.ul91, "Nein")
        XCTAssertTrue(ameland.fuelDetails.contains("AVGAS 100LL"))
        XCTAssertTrue(ameland.fuelDetails.contains("MOGAS Euro 98"))
        XCTAssertTrue(ameland.fuelDetails.contains("Jet A1 O/R"))
        XCTAssertTrue(ameland.fuelDetails.contains("12000 l"))
    }
}
