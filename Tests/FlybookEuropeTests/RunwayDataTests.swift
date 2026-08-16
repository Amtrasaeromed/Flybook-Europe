import XCTest
@testable import FlybookEurope

@MainActor
final class RunwayDataTests: XCTestCase {
    func testEveryDestinationHasRequiredTechnicalData() {
        let store = DestinationStore()

        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.destinations.count, 145)
        XCTAssertEqual(
            store.destinations.filter { $0.icao != "EDFZ" }.count,
            144
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

    func testSelectedSwissNatureAirportsAreLoaded() throws {
        let byICAO = Dictionary(
            uniqueKeysWithValues: DestinationStore().destinations.map { ($0.icao, $0) }
        )

        let neuchatel = try XCTUnwrap(byICAO["LSGN"])
        XCTAssertEqual(neuchatel.referenceRunway, "05/23")
        XCTAssertEqual(neuchatel.runwayM, 700)
        XCTAssertEqual(neuchatel.avgas, "Ja")
        XCTAssertTrue(neuchatel.features.contains(.lakeNature))
        XCTAssertTrue(neuchatel.bikeDirect.hasPrefix("Ja"))
        XCTAssertEqual(neuchatel.bikeHalfDayPrice, 10)
        XCTAssertEqual(neuchatel.bikeFullDayPrice, 15)
        XCTAssertEqual(neuchatel.bikeDepositPrice, 20)
        XCTAssertEqual(neuchatel.bikePriceCurrency, "CHF")
        XCTAssertTrue(neuchatel.bikeInformation.contains("Pointe-du-Grain"))
        XCTAssertTrue(neuchatel.railDirect.contains("Littorail"))
        XCTAssertTrue(neuchatel.railDirect.contains("200 m"))
        XCTAssertTrue(neuchatel.railInformation.contains("15 Minuten"))

        let buochs = try XCTUnwrap(byICAO["LSZC"])
        XCTAssertEqual(buochs.runwayM, 2_000)
        XCTAssertEqual(buochs.runwayLDAM, 1_940)
        XCTAssertEqual(buochs.avgas, "Nein")
        XCTAssertTrue(buochs.features.isSuperset(of: [.lakeNature, .mountainHiking]))
        XCTAssertTrue(buochs.ppr.contains("3 Stunden"))
        XCTAssertTrue(buochs.ppr.contains("24 Stunden"))
        XCTAssertTrue(buochs.airportNote.contains("ARR Y"))
        XCTAssertTrue(buochs.airportNote.contains("CAT 3–5"))
        XCTAssertTrue(buochs.fuelDetails.contains("Jet-A1"))
        XCTAssertTrue(buochs.fuelDetails.contains("CHF 2.34"))
        XCTAssertTrue(buochs.airportFeeNote.contains("CHF 38.70"))
        XCTAssertTrue(buochs.airportFeeNote.contains("CHF 70.00"))

        let mollis = try XCTUnwrap(byICAO["LSZM"])
        XCTAssertEqual(mollis.referenceRunway, "01/19")
        XCTAssertTrue(mollis.features.isSuperset(of: [.lakeNature, .mountainHiking]))

        let lugano = try XCTUnwrap(byICAO["LSZA"])
        XCTAssertEqual(lugano.runwayLDAM, 1_135)
        XCTAssertEqual(lugano.avgas, "Ja")
        XCTAssertTrue(lugano.features.isSuperset(of: [.lakeNature, .mountainHiking]))

        let yverdon = try XCTUnwrap(byICAO["LSGY"])
        XCTAssertEqual(yverdon.referenceRunway, "04/22")
        XCTAssertEqual(yverdon.runwayM, 872)
        XCTAssertEqual(yverdon.avgas, "Ja")
        XCTAssertEqual(yverdon.ul91, "Ja")
        XCTAssertTrue(yverdon.features.isSuperset(of: [.lakeNature, .wellness]))

        let reichenbach = try XCTUnwrap(byICAO["LSGR"])
        XCTAssertEqual(reichenbach.referenceRunway, "03/21")
        XCTAssertEqual(reichenbach.runwayM, 805)
        XCTAssertEqual(reichenbach.runwayLDAM, 650)
        XCTAssertTrue(reichenbach.features.isSuperset(of: [.lakeNature, .mountainHiking]))
    }

    func testNewSouthernTechStopsAreLoadedWithConfirmedMogas() throws {
        let byICAO = Dictionary(
            uniqueKeysWithValues: DestinationStore().destinations.map {
                ($0.icao, $0)
            }
        )
        let mengen = try XCTUnwrap(byICAO["EDTM"])
        XCTAssertTrue(mengen.features.contains(.techStop))
        XCTAssertEqual(mengen.referenceRunway, "07/25")
        XCTAssertEqual(mengen.runwayM, 1_566)
        XCTAssertEqual(mengen.mogas, "Ja")

        let herzogenaurach = try XCTUnwrap(byICAO["EDQH"])
        XCTAssertTrue(herzogenaurach.features.contains(.techStop))
        XCTAssertEqual(herzogenaurach.referenceRunway, "08/26")
        XCTAssertEqual(herzogenaurach.runwayM, 700)
        XCTAssertEqual(herzogenaurach.mogas, "Ja")

        let bremgarten = try XCTUnwrap(byICAO["EDTG"])
        XCTAssertTrue(bremgarten.features.contains(.techStop))
        XCTAssertEqual(bremgarten.referenceRunway, "05/23")
        XCTAssertEqual(bremgarten.runwayM, 1_650)
        XCTAssertEqual(bremgarten.mogas, "Ja")
        XCTAssertEqual(bremgarten.avgas, "Ja")
        XCTAssertEqual(bremgarten.portOfEntry, "Ja")

        let schwenningen = try XCTUnwrap(byICAO["EDTS"])
        XCTAssertTrue(schwenningen.features.contains(.techStop))
        XCTAssertEqual(schwenningen.referenceRunway, "04/22")
        XCTAssertEqual(schwenningen.runwayM, 804)
        XCTAssertEqual(schwenningen.runwayLDAM, 631)
        XCTAssertEqual(schwenningen.mogas, "Ja – nur PPR")
        XCTAssertEqual(schwenningen.avgas, "Ja – nur PPR")
        XCTAssertTrue(schwenningen.fuelDetails.contains("nur PPR"))
    }

    func testAllSwissFinderDestinationsExposeAuditedPOEStatus() throws {
        let byICAO = Dictionary(
            uniqueKeysWithValues: DestinationStore().destinations.map { ($0.icao, $0) }
        )
        let swissICAOs = [
            "LSGL", "LSGS", "LSGT", "LSZL", "LSZR", "LSGN",
            "LSZC", "LSZM", "LSZA", "LSGY"
        ]

        for icao in swissICAOs {
            XCTAssertEqual(
                try XCTUnwrap(byICAO[icao]).portOfEntry,
                "Ja",
                "POE fehlt für \(icao)"
            )
        }

        let reichenbach = try XCTUnwrap(byICAO["LSGR"])
        XCTAssertEqual(reichenbach.portOfEntry, "Nein")
        XCTAssertTrue(reichenbach.airportNote.contains("Homebase Reichenbach"))
        XCTAssertTrue(reichenbach.airportNote.contains("1 Std. vor Abflug"))
        XCTAssertTrue(reichenbach.airportNote.contains("2 Std. vor Landung"))
    }

    func testUKMergePackAirportsExposePOEAndConservativeFuelStatus() throws {
        let store = DestinationStore()
        let byICAO = Dictionary(
            uniqueKeysWithValues: store.destinations.map { ($0.icao, $0) }
        )
        let ukICAOs = [
            "EGHC", "EGHE", "EGHN", "EGHJ", "EGHF", "EGKA",
            "EGMD", "EGHQ", "EGHR", "EGKH", "EGHA"
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

        let headcorn = try XCTUnwrap(byICAO["EGKH"])
        XCTAssertEqual(headcorn.avgas, "Ja")
        XCTAssertEqual(headcorn.ul91, "Ja")
        XCTAssertEqual(headcorn.mogas, "?")
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

        for icao in ["EDFE", "EDFM", "EDRY", "EDRK", "EDXE", "EDLM", "EDLS"] {
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
        XCTAssertTrue(LandingVoucherBook.includes("EDXE"))

        let edlm = try XCTUnwrap(byICAO["EDLM"])
        XCTAssertTrue(edlm.features.contains(.techStop))
        XCTAssertEqual(edlm.referenceRunway, "07/25")
        XCTAssertEqual(edlm.runwayM, 830)
        XCTAssertEqual(edlm.runwayLDAM, 700)
        XCTAssertEqual(edlm.avgas, "Ja")
        XCTAssertEqual(edlm.mogas, "Ja")
        XCTAssertEqual(edlm.avgasPricePerLiterEUR, 3.14)
        XCTAssertEqual(edlm.mogasPricePerLiterEUR, 2.61)
        XCTAssertTrue(LandingVoucherBook.includes("EDLM"))
    }

    func testEDLSIsConfiguredAsCustomsFuelTechStop() throws {
        let edls = try XCTUnwrap(
            DestinationStore().destinations.first { $0.icao == "EDLS" }
        )

        XCTAssertTrue(edls.features.contains(.techStop))
        XCTAssertEqual(edls.avgas, "Ja")
        XCTAssertEqual(edls.mogas, "Ja")
        XCTAssertEqual(edls.portOfEntry, "Ja")
        XCTAssertEqual(edls.referenceRunway, "11/29")
        XCTAssertEqual(edls.runwayM, 1_240)
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

    func testAuditedDestinationMarkersAreLoadedWithoutBorderlineState() throws {
        let byICAO = Dictionary(
            uniqueKeysWithValues: DestinationStore().destinations.map { ($0.icao, $0) }
        )
        let mountainICAOs = [
            "EDTF", "ESMH", "LFGA", "LFKB", "LFKJ", "LFLP", "LIEO"
        ]
        let wellnessICAOs = [
            "EDWG", "EGJJ", "EHAL", "EKSB", "LFGA", "LFKJ", "LFLP",
            "LIDT", "LIEA", "LIEO", "LIPB", "LIRJ", "LOWI", "LSGS"
        ]

        for icao in mountainICAOs {
            XCTAssertTrue(
                try XCTUnwrap(byICAO[icao]).features.contains(.mountainHiking),
                "Berge/Wandern fehlt für \(icao)"
            )
        }
        for icao in wellnessICAOs {
            XCTAssertTrue(
                try XCTUnwrap(byICAO[icao]).features.contains(.wellness),
                "Auszeit/Wellness fehlt für \(icao)"
            )
        }
    }

    func testMobilityUsesOnlyYesUnknownOrNo() throws {
        for destination in DestinationStore().destinations {
            for (label, value) in [
                ("Fahrrad", destination.bikeDirect),
                ("Mietwagen", destination.rentalCarDirect),
                ("Bahn", destination.railDirect),
                ("Bus", destination.busDirect)
            ] {
                XCTAssertTrue(
                    value.hasPrefix("Ja")
                        || value.hasPrefix("?")
                        || value.hasPrefix("Nein"),
                    "\(label) hat für \(destination.icao) einen ungültigen Status: \(value)"
                )
            }
        }

        let byICAO = Dictionary(
            uniqueKeysWithValues: DestinationStore().destinations.map { ($0.icao, $0) }
        )
        XCTAssertTrue(try XCTUnwrap(byICAO["EDMB"]).bikeDirect.hasPrefix("Ja"))
        XCTAssertTrue(try XCTUnwrap(byICAO["EDVE"]).rentalCarDirect.hasPrefix("Ja"))
        XCTAssertTrue(try XCTUnwrap(byICAO["EDXB"]).rentalCarDirect.hasPrefix("Ja"))
        XCTAssertTrue(try XCTUnwrap(byICAO["LOAN"]).rentalCarDirect.hasPrefix("Ja"))
        XCTAssertTrue(try XCTUnwrap(byICAO["EDLA"]).bikeDirect.hasPrefix("Nein"))
        XCTAssertTrue(try XCTUnwrap(byICAO["EGHJ"]).bikeDirect.hasPrefix("?"))
        XCTAssertTrue(try XCTUnwrap(byICAO["EGHJ"]).rentalCarDirect.hasPrefix("?"))
        XCTAssertTrue(try XCTUnwrap(byICAO["EDKA"]).railDirect.hasPrefix("Ja"))
        XCTAssertTrue(try XCTUnwrap(byICAO["LSGN"]).railDirect.hasPrefix("Ja"))
        XCTAssertTrue(try XCTUnwrap(byICAO["EGHC"]).busDirect.hasPrefix("Ja"))
        XCTAssertTrue(try XCTUnwrap(byICAO["EDVE"]).busDirect.hasPrefix("?"))
    }

    func testEveryAirportHasFinalApp2DriveYesOrNoStatus() {
        let destinations = DestinationStore().destinations
        let app2DriveAirports: Set<String> = [
            "EDAH", "EDAX", "EDAY", "EDAZ", "EDFE", "EDFM", "EDFZ",
            "EDGE", "EDGS", "EDKA", "EDKB", "EDLD", "EDLE", "EDLM",
            "EDLN", "EDLS", "EDMA", "EDMV", "EDQH", "EDRK", "EDRY",
            "EDTD", "EDTF", "EDTY", "EDVE", "EDVK", "EDVM", "EDWF",
            "EDWI", "EDXO", "EDXW", "LJPZ", "LOAN"
        ]

        XCTAssertEqual(destinations.count, 145)
        XCTAssertEqual(app2DriveAirports.count, 33)
        for destination in destinations {
            let expected = app2DriveAirports.contains(destination.icao)
                ? "Ja"
                : "Nein"
            XCTAssertTrue(
                destination.app2DriveDirect.hasPrefix(expected),
                "App2Drive-Status für \(destination.icao) ist nicht \(expected): "
                    + destination.app2DriveDirect
            )
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
        XCTAssertEqual(ameland.ul91, "Nein")
        XCTAssertTrue(ameland.fuelDetails.contains("AVGAS 100LL"))
        XCTAssertTrue(ameland.fuelDetails.contains("MOGAS Euro 98"))
        XCTAssertTrue(ameland.fuelDetails.contains("12000 l"))
    }

    func testEveryTechStopHasAuditedMogasAndRestaurantInformation() {
        let techStops = DestinationStore().destinations.filter {
            $0.features.contains(.techStop)
        }

        XCTAssertEqual(techStops.count, 39)
        for destination in techStops {
            XCTAssertFalse(
                destination.mogas.isEmpty,
                "MOGAS-Status fehlt für \(destination.icao)"
            )
            XCTAssertFalse(
                destination.restaurantDirect.isEmpty,
                "Restaurantstatus fehlt für \(destination.icao)"
            )
            XCTAssertFalse(
                destination.restaurantName.isEmpty,
                "Restaurantname oder Negativhinweis fehlt für \(destination.icao)"
            )
            XCTAssertFalse(
                destination.restaurantOpeningHours.isEmpty,
                "Restaurantzeiten oder Prüfhilfe fehlen für \(destination.icao)"
            )
            XCTAssertEqual(destination.restaurantDataCheckedAt, "2026-08-16")
        }
    }

    func testCurrentPublishedTechStopMogasPricesAreLoaded() throws {
        let byICAO = Dictionary(
            uniqueKeysWithValues: DestinationStore().destinations.map { ($0.icao, $0) }
        )
        let expectedPrices: [String: Double] = [
            "EDAZ": 2.81,
            "EDGS": 2.81,
            "EDLH": 2.45,
            "EDMB": 2.35,
            "EDPA": 2.39,
            "EDRK": 2.81,
            "EDRY": 2.89,
            "EDXE": 2.45
        ]

        for (icao, expectedPrice) in expectedPrices {
            let destination = try XCTUnwrap(byICAO[icao])
            XCTAssertEqual(destination.mogas, "Ja")
            XCTAssertEqual(
                try XCTUnwrap(destination.mogasPricePerLiterEUR),
                expectedPrice,
                accuracy: 0.001,
                "Veralteter MOGAS-Preis für \(icao)"
            )
            XCTAssertEqual(destination.fuelPriceReportedAt, "Stand 2026-08-16")
        }
    }

    func testUserVisibleAirportInformationExcludesTurbineFuel() {
        for destination in DestinationStore().destinations {
            let visibleInformation = [
                destination.fuelDetails,
                destination.airportNote,
                destination.restaurantNotes,
                destination.highlights
            ].joined(separator: " ").lowercased()

            XCTAssertFalse(
                visibleInformation.contains("jet a1")
                    || visibleInformation.contains("jet a-1")
                    || visibleInformation.contains("jet fuel"),
                "Nicht benötigte Kraftstoffinformation bei \(destination.icao)"
            )
        }
    }
}
