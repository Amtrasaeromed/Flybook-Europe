import XCTest
@testable import FlybookEurope

@MainActor
final class RunwayDataTests: XCTestCase {
    func testEveryDestinationHasRequiredTechnicalData() {
        let store = DestinationStore()

        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.destinations.count, 135)
        XCTAssertEqual(
            store.destinations.filter { $0.icao != "EDFZ" }.count,
            134
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

    func testUKMergePackAirportsExposePOEAndConservativeFuelStatus() throws {
        let store = DestinationStore()
        let byICAO = Dictionary(
            uniqueKeysWithValues: store.destinations.map { ($0.icao, $0) }
        )
        let ukICAOs = [
            "EGHN", "EGHJ", "EGHF", "EGKA", "EGMD",
            "EGHQ", "EGHR", "EGKH", "EGHA"
        ]

        for icao in ukICAOs {
            XCTAssertEqual(
                try XCTUnwrap(byICAO[icao]).portOfEntry,
                "Ja",
                "POE fehlt für \(icao)"
            )
        }

        let bembridge = try XCTUnwrap(byICAO["EGHJ"])
        XCTAssertEqual(bembridge.avgas, "?")
        XCTAssertEqual(bembridge.ul91, "?")
        XCTAssertEqual(bembridge.mogas, "?")
        XCTAssertEqual(bembridge.jetA1, "?")

        let headcorn = try XCTUnwrap(byICAO["EGKH"])
        XCTAssertEqual(headcorn.avgas, "?")
        XCTAssertEqual(headcorn.ul91, "?")
        XCTAssertEqual(headcorn.mogas, "?")
        XCTAssertEqual(headcorn.jetA1, "?")
    }

    func testUKMergePackTourismFeaturesMatchTravelTimeRules() throws {
        let store = DestinationStore()
        let byICAO = Dictionary(
            uniqueKeysWithValues: store.destinations.map { ($0.icao, $0) }
        )
        let ukICAOs = [
            "EGHN", "EGHJ", "EGHF", "EGKA", "EGMD",
            "EGHQ", "EGHR", "EGKH", "EGHA"
        ]

        for icao in ukICAOs {
            let destination = try XCTUnwrap(byICAO[icao])
            XCTAssertTrue(
                destination.features.contains(.lakeNature),
                "See / Natur fehlt für \(icao)"
            )
            XCTAssertTrue(
                destination.features.contains(.wellness),
                "Wellness fehlt für \(icao)"
            )
            XCTAssertFalse(
                destination.features.contains(.mountainHiking),
                "Hügellandschaft darf nicht als Berge gelten: \(icao)"
            )
        }

        for icao in ukICAOs where !["EGHA", "EGKH"].contains(icao) {
            XCTAssertTrue(
                try XCTUnwrap(byICAO[icao]).features.contains(.beachSea),
                "Strand / Meer fehlt für \(icao)"
            )
        }
        for icao in ["EGHA", "EGKH"] {
            XCTAssertFalse(
                try XCTUnwrap(byICAO[icao]).features.contains(.beachSea),
                "\(icao) überschreitet die 45-Minuten-Regel zur Küste"
            )
        }
    }

    func testEveryBeachDestinationUsesHumanScaleAccessWithin45Minutes() throws {
        let destinations = DestinationStore().destinations.filter {
            $0.features.contains(.beachSea)
        }
        let acceptedModes = Set(["Fahrrad", "Zu Fuß", "zu Fuß", "E-Roller"])

        XCTAssertEqual(destinations.count, 51)
        for destination in destinations {
            let beach = try XCTUnwrap(
                destination.accessFeatures.first { $0.feature == .beachSea },
                "Strandzugang fehlt für \(destination.icao)"
            )
            XCTAssertTrue(
                acceptedModes.contains(beach.recommendedMode),
                "Unzulässiger Strandzugang für \(destination.icao): \(beach.recommendedMode)"
            )
            XCTAssertLessThanOrEqual(
                try XCTUnwrap(beach.recommendedMinutes),
                45,
                "Strandzugang dauert für \(destination.icao) länger als 45 Minuten"
            )
        }
    }

    func testPreferredAlternatesAreStandardTechStopDestinations() throws {
        let store = DestinationStore()
        let byICAO = Dictionary(
            uniqueKeysWithValues: store.destinations.map { ($0.icao, $0) }
        )

        for icao in ["EDFE", "EDFM", "EDRY", "EDRK", "EDXE", "EDLM"] {
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

    func testEDXEAndEDLMAreConfiguredTechStops() throws {
        let byICAO = Dictionary(
            uniqueKeysWithValues: DestinationStore().destinations.map {
                ($0.icao, $0)
            }
        )

        let edxe = try XCTUnwrap(byICAO["EDXE"])
        XCTAssertTrue(edxe.features.contains(.techStop))
        XCTAssertEqual(edxe.avgas, "Ja")
        XCTAssertEqual(edxe.mogas, "Ja")
        XCTAssertEqual(edxe.jetA1, "Nein")
        XCTAssertTrue(LandingVoucherBook.includes("EDXE"))

        let edlm = try XCTUnwrap(byICAO["EDLM"])
        XCTAssertTrue(edlm.features.contains(.techStop))
        XCTAssertEqual(edlm.referenceRunway, "07/25")
        XCTAssertEqual(edlm.runwayM, 830)
        XCTAssertEqual(edlm.runwayLDAM, 700)
        XCTAssertEqual(edlm.avgas, "Ja")
        XCTAssertEqual(edlm.jetA1, "Ja")
        XCTAssertEqual(edlm.mogas, "Ja")
        XCTAssertEqual(edlm.avgasPricePerLiterEUR, 3.06)
        XCTAssertEqual(edlm.mogasPricePerLiterEUR, 2.49)
        XCTAssertTrue(LandingVoucherBook.includes("EDLM"))
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
        XCTAssertFalse(try XCTUnwrap(byICAO["EDCG"]).features.contains(.beachSea))
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
