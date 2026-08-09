import SwiftUI

private enum DashboardLayout {
    static let sectionGap: CGFloat = 4
}

struct FlybookDashboardView: View {
    let airports: [Airport]
    private let fuelCatalog = AirportFuelCatalog.load()
    private let fuelPriceCatalog = AirportFuelPriceCatalog.load()
    private let featureCatalog = AirportFeatureCatalog.load()

    @AppStorage("ipad.activeBase") private var activeBase = "LSV Mainz"
    @AppStorage("ipad.activeAircraft") private var activeAircraft = "DEZHS"
    @AppStorage("ipad.activeUser") private var activeUser = "Stephan"
    @AppStorage("ipad.destinationICAO") private var destinationICAO = "EDKA"
    @AppStorage("ipad.unitSystem") private var unitSystem = "EU"

    @State private var outboundDeparture = Date.defaultFlightDeparture
    @State private var returnDeparture = Date.now
        .addingTimeInterval(4 * 60 * 60)
        .roundedToNextQuarterHour
    @State private var showsAirportPicker = false
    @State private var showsMigrationNotice = false
    @State private var includeLandingFees = false
    @State private var flightDepartureICAO = "EDFZ"
    @State private var flightArrivalICAO = ""
    @State private var selectedAltitudeFeet = 7_000
    @State private var intermediateStopCount = 0
    @State private var intermediateStop1ICAO = ""
    @State private var intermediateStop2ICAO = ""
    @State private var showsRouteMap = false
    @StateObject private var routeWeather = IPadRouteWeatherRiskViewModel()

    private var homeAirport: Airport {
        airports.first(where: { $0.icao == "EDFZ" })
            ?? Airport.fallbackEDFZ
    }

    private var destination: Airport {
        airports.first(where: { $0.icao == destinationICAO })
            ?? airports.first(where: { $0.icao == "EDKA" })
            ?? homeAirport
    }

    private var directRouteDistanceNM: Double {
        FlightGeometry.nauticalMiles(
            from: flightDepartureAirport,
            to: flightArrivalAirport
        )
    }

    private var selectedIntermediateAirports: [Airport] {
        [intermediateStop1ICAO, intermediateStop2ICAO]
            .prefix(intermediateStopCount)
            .compactMap { icao in airports.first { $0.icao == icao } }
    }

    private var routeDistanceNM: Double {
        let selected = selectedIntermediateAirports
        if intermediateStopCount > 0, selected.count == intermediateStopCount {
            let points = [flightDepartureAirport] + selected + [flightArrivalAirport]
            let legMiles = zip(points, points.dropFirst()).reduce(0.0) {
                $0 + FlightGeometry.nauticalMiles(from: $1.0, to: $1.1)
            }
            return legMiles * 1.05 + 10
        }
        let extra: Double = intermediateStopCount == 0 ? 10 : (intermediateStopCount == 1 ? 30 : 50)
        return directRouteDistanceNM * 1.05 + extra
    }

    private var routeBlockMinutes: Int {
        let climbMinutes = Int(
            (Double(max(0, selectedAltitudeFeet - 1_500)) / 1_000 * 1.2)
                .rounded()
        )
        let legCount = intermediateStopCount + 1
        return max(
            8,
            Int((routeDistanceNM / 109 * 60).rounded())
                + (5 + climbMinutes) * legCount
        )
    }

    private var routeMinutes: Int {
        routeBlockMinutes + intermediateStopCount * 60
    }

    private var etopsLegMinutes: Int {
        Int((Double(routeBlockMinutes) / Double(intermediateStopCount + 1)).rounded())
    }

    private var activeETOPSGreenYellowMinutes: Int {
        activeETOPSProfileValue(
            name: "greenYellowMinutes",
            legacyKey: "etopsGreenYellowMinutes",
            fallback: 105
        )
    }

    private var activeETOPSOrangeRedMinutes: Int {
        let configured = activeETOPSProfileValue(
            name: "orangeRedMinutes",
            legacyKey: "etopsOrangeRedMinutes",
            fallback: 150
        )
        return max(activeETOPSGreenYellowMinutes + 10, configured)
    }

    private func activeETOPSProfileValue(
        name: String,
        legacyKey: String,
        fallback: Int
    ) -> Int {
        let profileDefaults = UserDefaults(suiteName: "de.flybook.europe.user-profiles")
        let profileKey = "etopsProfile.\(activeUser).\(name)"
        if let profileDefaults,
           profileDefaults.object(forKey: profileKey) != nil {
            return profileDefaults.integer(forKey: profileKey)
        }
        if activeUser == "Stephan",
           UserDefaults.standard.object(forKey: legacyKey) != nil {
            return UserDefaults.standard.integer(forKey: legacyKey)
        }
        return fallback
    }

    private var routeMapWaypoints: [IPadRouteMapWaypoint] {
        var result = [
            IPadRouteMapWaypoint(
                title: "\(flightDepartureAirport.icao) · \(flightDepartureAirport.name)",
                latitude: flightDepartureAirport.latitude,
                longitude: flightDepartureAirport.longitude,
                role: .departure
            )
        ]

        for index in 0..<intermediateStopCount {
            let selectedICAO = index == 0 ? intermediateStop1ICAO : intermediateStop2ICAO
            if let airport = airports.first(where: { $0.icao == selectedICAO }) {
                result.append(
                    IPadRouteMapWaypoint(
                        title: "\(airport.icao) · \(airport.name)",
                        latitude: airport.latitude,
                        longitude: airport.longitude,
                        role: .stop
                    )
                )
            } else {
                let fraction = intermediateStopCount == 1
                    ? 0.5
                    : (index == 0 ? 1.0 / 3.0 : 2.0 / 3.0)
                let coordinate = FlightGeometry.intermediateCoordinate(
                    from: flightDepartureAirport,
                    to: flightArrivalAirport,
                    fraction: fraction
                )
                result.append(
                    IPadRouteMapWaypoint(
                        title: "Virtueller Stop \(index + 1)",
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude,
                        role: .virtualStop
                    )
                )
            }
        }

        result.append(
            IPadRouteMapWaypoint(
                title: "\(flightArrivalAirport.icao) · \(flightArrivalAirport.name)",
                latitude: flightArrivalAirport.latitude,
                longitude: flightArrivalAirport.longitude,
                role: .arrival
            )
        )
        return result
    }

    private var altitudeOptions: [Int] {
        let firstLegDestination = selectedIntermediateAirports.first ?? flightArrivalAirport
        let course = FlightGeometry.initialBearing(
            from: flightDepartureAirport,
            to: firstLegDestination
        )
        if (180..<360).contains(course) {
            return [2_500, 4_500, 6_500, 8_500]
        }
        return [2_500, 3_500, 5_500, 7_500, 9_500]
    }

    private var altitudeRuleKey: String {
        let firstLegICAO = selectedIntermediateAirports.first?.icao ?? flightArrivalAirport.icao
        return "\(flightDepartureAirport.icao)-\(firstLegICAO)"
    }

    private var bestLevelFeet: Int {
        altitudeOptions.min {
            abs($0 - 7_000) < abs($1 - 7_000)
        } ?? 2_500
    }

    private var destinationAirports: [Airport] {
        airports.filter { $0.icao != "EDFZ" }
    }

    private var destinationFuel: AirportFuelAvailability {
        fuelCatalog.availability(for: destination.icao)
    }

    private var destinationFuelPrices: AirportFuelPrices {
        fuelPriceCatalog.prices(for: destination.icao)
    }

    private var destinationFeatures: [AirportFeature] {
        featureCatalog.features(for: destination.icao)
    }

    private var flightDepartureAirport: Airport {
        airports.first(where: { $0.icao == flightDepartureICAO.uppercased() })
            ?? homeAirport
    }

    private var flightArrivalAirport: Airport {
        airports.first(where: { $0.icao == flightArrivalICAO.uppercased() })
            ?? destination
    }

    private var charterBlockHours: Double {
        ceil((Double(routeBlockMinutes) / 60) * 10) / 10
    }

    private var charterFuelLiters: Int {
        Int((charterBlockHours * 60).rounded())
    }

    private var charterCostEUR: Int {
        let hourlyRate: Double
        switch activeAircraft {
        case "DEUKS": hourlyRate = 145
        case "DETIK": hourlyRate = 180
        default: hourlyRate = 180
        }
        return Int((charterBlockHours * hourlyRate * 1.07).rounded())
    }

    private var routeWaypoints: [Airport] {
        [flightDepartureAirport] + selectedIntermediateAirports + [flightArrivalAirport]
    }

    private var routeWeatherRequestKey: String {
        routeWaypoints.map(\.icao).joined(separator: "-")
            + "-\(Int(outboundDeparture.timeIntervalSince1970 / 900))"
            + "-\(routeMinutes)-\(selectedAltitudeFeet)"
    }

    var body: some View {
        GeometryReader { geometry in
            let canvasWidth = 820.0
            let canvasHeight = 1_080.0
            let scale = min(
                geometry.size.width / canvasWidth,
                geometry.size.height / canvasHeight
            )

            ZStack {
                Color.dashboardBackground
                    .ignoresSafeArea()

                fixedDashboard
                    .frame(
                        width: canvasWidth,
                        height: canvasHeight,
                        alignment: .top
                    )
                    .scaleEffect(scale)
                    .frame(
                        width: canvasWidth * scale,
                        height: canvasHeight * scale
                    )
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .center
            )
        }
        .sheet(isPresented: $showsAirportPicker) {
            AirportPickerSheet(
                airports: airports.filter { $0.icao != "EDFZ" },
                selectedICAO: $destinationICAO
            )
        }
        .fullScreenCover(isPresented: $showsRouteMap) {
            IPadRouteMapSheet(waypoints: routeMapWaypoints)
        }
        .alert("Dieser Bereich folgt", isPresented: $showsMigrationNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Die Oberfläche ist vorbereitet. Die bestehende Flybook-Funktion wird in einem der nächsten Migrationsschritte angebunden.")
        }
        .onAppear {
            if flightArrivalICAO.isEmpty {
                flightArrivalICAO = destination.icao
            }
            normalizeSelectedAltitude()
        }
        .onChange(of: destinationICAO) { _, newValue in
            if flightDepartureICAO == "EDFZ" {
                flightArrivalICAO = newValue
            }
        }
        .onChange(of: altitudeRuleKey) { _, _ in
            normalizeSelectedAltitude()
        }
        .task(id: routeWeatherRequestKey) {
            await routeWeather.load(
                waypoints: routeWaypoints,
                start: outboundDeparture,
                end: outboundDeparture.addingTimeInterval(TimeInterval(routeMinutes * 60)),
                cruiseAltitudeFeet: selectedAltitudeFeet
            )
        }
    }

    private var fixedDashboard: some View {
        VStack(spacing: 6) {
            mainHeader
                .frame(height: 64)
                .zIndex(20)
            featureStrip
                .frame(height: 32)
            airportInformationRow
                .frame(height: 104)
            fiveDayOverview
                .frame(height: 194, alignment: .top)
            oneWayFlightSection
                .frame(height: 340, alignment: .top)
            intermediateStopSection
                .frame(height: 52, alignment: .top)
            charterCalculationSection
                .frame(height: 146, alignment: .top)
            Spacer(minLength: 0)
            bottomMenuBar
                .frame(height: 54)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private func normalizeSelectedAltitude() {
        guard !altitudeOptions.contains(selectedAltitudeFeet) else { return }
        selectedAltitudeFeet = altitudeOptions.min {
            abs($0 - selectedAltitudeFeet) < abs($1 - selectedAltitudeFeet)
        } ?? 2_500
    }

    private var mainHeader: some View {
        ZStack {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Button {
                        showsAirportPicker = true
                    } label: {
                        Text(destination.name.uppercased())
                            .font(.system(size: 27, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.dashboardNavy)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 6) {
                        Text(countryFlag(destination.countryCode))
                        Text("·")
                        HeaderDestinationSearch(
                            airports: airports,
                            selectedICAO: $destinationICAO
                        )
                        Text("·  HÖHE \(destination.elevationFeet.formatted()) FT")
                        Button { showsAirportPicker = true } label: {
                            Image(systemName: "chevron.down").font(.caption.bold())
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.dashboardNavy)
                }
                .frame(width: 330, alignment: .leading)
                .zIndex(30)

                Spacer()

                Button {
                    showsMigrationNotice = true
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: "cloud.sun.fill")
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 29, weight: .bold))
                        Text("NOW!")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(Color.dashboardNavy)
                    }
                    .frame(width: 64, height: 64)
                    .background(Color.white, in: Circle())
                    .overlay { Circle().stroke(Color.dashboardBlue, lineWidth: 2) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wetter jetzt vollständig aktualisieren")
            }

            HStack(spacing: 7) {
                HeaderNavigationButton(systemName: "chevron.left") {
                    selectDestination(offset: -1)
                }
                HeaderNavigationButton(
                    systemName: "line.3.horizontal.decrease.circle.fill",
                    highlighted: true
                ) {
                    showsMigrationNotice = true
                }
                HeaderNavigationButton(systemName: "chevron.right") {
                    selectDestination(offset: 1)
                }
            }

            Menu {
                ForEach(["DEZHS", "DEUKS", "DETIK"], id: \.self) { aircraft in
                    Button(aircraft) { activeAircraft = aircraft }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "airplane")
                    Text(activeAircraft)
                    Image(systemName: "chevron.down")
                        .font(.caption2.bold())
                }
                .font(.caption.bold())
                .foregroundStyle(Color.dashboardNavy)
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.dashboardBlue.opacity(0.45), lineWidth: 1)
                }
            }
            .offset(x: 154)
        }
    }

    private var featureStrip: some View {
        HStack(spacing: 7) {
            ForEach(destinationFeatures.prefix(6)) { feature in
                Label(feature.title, systemImage: feature.symbol)
                    .font(.caption.bold())
                    .foregroundStyle(Color.dashboardNavy)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Color.dashboardBlue.opacity(0.11), in: Capsule())
            }
            if destinationFeatures.isEmpty {
                Text("Keine besonderen Flugplatzmerkmale hinterlegt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .clipped()
    }

    private var airportInformationRow: some View {
        DashboardCard {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("RUNWAY", systemImage: "road.lanes")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(destination.runwayDisplay)
                        .font(.title3.bold())
                        .foregroundStyle(Color.dashboardNavy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(destination.runwaySurface.isEmpty ? "Belag unklar" : destination.runwaySurface)
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.dashboardBlue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 66)
                FuelStatusCell(
                    title: "AVGAS",
                    status: destinationFuel.avgas,
                    price: destinationFuelPrices.avgas,
                    referencePrice: AirportFuelPriceCatalog.referenceEDFZ.avgas
                )
                Divider().frame(height: 66)
                FuelStatusCell(
                    title: "UL91",
                    status: destinationFuel.ul91,
                    price: destinationFuelPrices.ul91,
                    referencePrice: AirportFuelPriceCatalog.referenceEDFZ.ul91
                )
                Divider().frame(height: 66)
                FuelStatusCell(
                    title: "MOGAS",
                    status: destinationFuel.mogas,
                    price: destinationFuelPrices.mogas,
                    referencePrice: AirportFuelPriceCatalog.referenceEDFZ.mogas
                )
            }
        }
    }

    private var fiveDayOverview: some View {
        VStack(alignment: .leading, spacing: DashboardLayout.sectionGap) {
            HStack {
                SectionTitle(title: "5-TAGES-WETTER", systemName: "cloud.sun")
                Spacer()
                Text("ICON-SEAMLESS · NOCH NICHT VERBUNDEN")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }

            DashboardCard {
                VStack(spacing: 4) {
                    ForecastRiskBar(
                        title: "FOG RISK 06–22 UHR",
                        systemName: "cloud.fog"
                    )
                    HStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { offset in
                            ForecastPlaceholderTile(
                                date: Calendar.current.date(
                                    byAdding: .day,
                                    value: offset,
                                    to: .now
                                ) ?? .now
                            )
                        }
                    }
                    ForecastRiskBar(
                        title: "WIND 06–22 UHR",
                        systemName: "wind"
                    )
                }
            }
        }
    }

    private var oneWayFlightSection: some View {
        VStack(alignment: .leading, spacing: DashboardLayout.sectionGap) {
            ZStack {
                SectionTitle(title: "FLUGPLANUNG", systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    Text("ABFLUG")
                        .font(.caption.bold())
                        .foregroundStyle(Color.dashboardNavy)
                    DatePicker("Datum", selection: $outboundDeparture, displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 112)
                    DatePicker("Startzeit", selection: $outboundDeparture, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 78)
                    departureTimeStepButton(systemName: "minus", minutes: -15)
                    departureTimeStepButton(systemName: "plus", minutes: 15)
                    departureShortcut("Jetzt") { setDepartureNow() }
                    departureShortcut("Heute") { setDepartureDay(offset: 0) }
                    departureShortcut("Morgen") { setDepartureDay(offset: 1) }
                }
            }
            .frame(height: 42)
            EditableFlightLegCard(
                airports: airports,
                departureICAO: $flightDepartureICAO,
                arrivalICAO: $flightArrivalICAO,
                departure: $outboundDeparture,
                durationMinutes: routeMinutes,
                etopsLegMinutes: etopsLegMinutes,
                etopsGreenYellowMinutes: activeETOPSGreenYellowMinutes,
                etopsOrangeRedMinutes: activeETOPSOrangeRedMinutes,
                distanceNM: routeDistanceNM,
                selectedAltitudeFeet: $selectedAltitudeFeet,
                altitudeOptions: altitudeOptions,
                bestLevelFeet: bestLevelFeet,
                departureAirport: flightDepartureAirport,
                arrivalAirport: flightArrivalAirport,
                routeRisks: routeWeather.segments,
                onSwap: {
                    let previousDeparture = flightDepartureICAO
                    flightDepartureICAO = flightArrivalICAO
                    flightArrivalICAO = previousDeparture
                },
                onArrivalSelected: { airport in
                    destinationICAO = airport.icao
                }
            )
            .frame(height: 294)
        }
    }

    private func departureShortcut(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .font(.system(size: 10, weight: .bold))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(Color.dashboardBlue)
    }

    private func departureTimeStepButton(systemName: String, minutes: Int) -> some View {
        Button {
            outboundDeparture = Calendar.current.date(
                byAdding: .minute,
                value: minutes,
                to: outboundDeparture
            ) ?? outboundDeparture
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.dashboardBlue)
                .frame(width: 27, height: 27)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.dashboardBlue.opacity(0.55), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(minutes < 0 ? "Startzeit 15 Minuten früher" : "Startzeit 15 Minuten später")
    }

    private func setDepartureNow() {
        outboundDeparture = Date()
    }

    private func setDepartureDay(offset: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: flightDepartureAirport.timeZoneIdentifier) ?? .current
        let now = Date()
        guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
              let standard = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
        else { return }
        outboundDeparture = offset == 0 && standard <= now ? now : standard
    }

    private struct AutomaticRoute {
        let stopCount: Int
        let firstICAO: String
        let secondICAO: String
        let routeDistanceNM: Double
    }

    private var automaticRouteCandidates: [Airport] {
        airports.filter {
            $0.isTechStop
                && $0.icao != flightDepartureAirport.icao
                && $0.icao != flightArrivalAirport.icao
                && ($0.runwayLengthMeters ?? 0) > 0
        }
    }

    private func routeDistanceNM(via stops: [Airport]) -> Double {
        let points = [flightDepartureAirport] + stops + [flightArrivalAirport]
        let legs = zip(points, points.dropFirst()).reduce(0.0) {
            $0 + FlightGeometry.nauticalMiles(from: $1.0, to: $1.1)
        }
        return legs * 1.05 + 10
    }

    private func estimatedBlockMinutes(routeDistanceNM: Double, stopCount: Int) -> Int {
        let climbMinutes = Int(
            (Double(max(0, selectedAltitudeFeet - 1_500)) / 1_000 * 1.2)
                .rounded()
        )
        return max(
            8,
            Int((routeDistanceNM / 109 * 60).rounded())
                + (5 + climbMinutes) * (stopCount + 1)
        )
    }

    private func optimizedAutomaticRoute(stopCount: Int) -> AutomaticRoute? {
        guard stopCount > 0 else {
            return AutomaticRoute(
                stopCount: 0,
                firstICAO: "",
                secondICAO: "",
                routeDistanceNM: routeDistanceNM(via: [])
            )
        }

        let candidates = automaticRouteCandidates
        guard !candidates.isEmpty else { return nil }
        let direct = directRouteDistanceNM

        if stopCount == 1 {
            let target = FlightGeometry.intermediateCoordinate(
                from: flightDepartureAirport,
                to: flightArrivalAirport,
                fraction: 0.5
            )
            guard let best = candidates.min(by: { lhs, rhs in
                let lhsRoute = routeDistanceNM(via: [lhs])
                let rhsRoute = routeDistanceNM(via: [rhs])
                let lhsScore = (lhsRoute - direct) * 4
                    + FlightGeometry.nauticalMiles(from: lhs, to: target)
                let rhsScore = (rhsRoute - direct) * 4
                    + FlightGeometry.nauticalMiles(from: rhs, to: target)
                if abs(lhsScore - rhsScore) > 0.01 { return lhsScore < rhsScore }
                return lhs.icao < rhs.icao
            }) else { return nil }
            return AutomaticRoute(
                stopCount: 1,
                firstICAO: best.icao,
                secondICAO: "",
                routeDistanceNM: routeDistanceNM(via: [best])
            )
        }

        let firstTarget = FlightGeometry.intermediateCoordinate(
            from: flightDepartureAirport,
            to: flightArrivalAirport,
            fraction: 1.0 / 3.0
        )
        let secondTarget = FlightGeometry.intermediateCoordinate(
            from: flightDepartureAirport,
            to: flightArrivalAirport,
            fraction: 2.0 / 3.0
        )
        var best: (score: Double, first: Airport, second: Airport, route: Double)?
        for first in candidates {
            for second in candidates where second.icao != first.icao {
                let route = routeDistanceNM(via: [first, second])
                let firstLeg = FlightGeometry.nauticalMiles(from: flightDepartureAirport, to: first)
                let middleLeg = FlightGeometry.nauticalMiles(from: first, to: second)
                let finalLeg = FlightGeometry.nauticalMiles(from: second, to: flightArrivalAirport)
                let idealLeg = (firstLeg + middleLeg + finalLeg) / 3
                let balanceError = abs(firstLeg - idealLeg)
                    + abs(middleLeg - idealLeg)
                    + abs(finalLeg - idealLeg)
                let targetError = FlightGeometry.nauticalMiles(from: first, to: firstTarget)
                    + FlightGeometry.nauticalMiles(from: second, to: secondTarget)
                let score = (route - direct) * 4 + balanceError * 2 + targetError
                if best == nil || score < best!.score {
                    best = (score, first, second, route)
                }
            }
        }
        guard let best else { return nil }
        return AutomaticRoute(
            stopCount: 2,
            firstICAO: best.first.icao,
            secondICAO: best.second.icao,
            routeDistanceNM: best.route
        )
    }

    private func applyAutomaticETOPSRoute() {
        for count in 0...2 {
            guard let route = optimizedAutomaticRoute(stopCount: count) else { continue }
            let block = estimatedBlockMinutes(
                routeDistanceNM: route.routeDistanceNM,
                stopCount: count
            )
            let perLeg = Int((Double(block) / Double(count + 1)).rounded())
            if perLeg < activeETOPSOrangeRedMinutes || count == 2 {
                intermediateStopCount = route.stopCount
                intermediateStop1ICAO = route.firstICAO
                intermediateStop2ICAO = route.secondICAO
                return
            }
        }
    }

    private var intermediateStopSection: some View {
        DashboardCard {
            HStack(spacing: 8) {
                Text("Stops:")
                    .font(.caption.bold())
                    .foregroundStyle(Color.dashboardNavy)

                Picker("Anzahl Zwischenstopps", selection: $intermediateStopCount) {
                    Text("0").tag(0)
                    Text("1").tag(1)
                    Text("2").tag(2)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 120)

                Group {
                    if intermediateStopCount >= 1 {
                        StopAirportPicker(
                            title: "STOP 1",
                            selection: $intermediateStop1ICAO,
                            airports: airports,
                            excluding: [flightDepartureICAO, flightArrivalICAO]
                                + (intermediateStopCount == 2 ? [intermediateStop2ICAO] : []),
                            origin: flightDepartureAirport,
                            destination: flightArrivalAirport,
                            stopCount: intermediateStopCount,
                            stopIndex: 1
                        )
                    } else {
                        Text("Direktflug")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 220, alignment: .leading)

                Group {
                    if intermediateStopCount == 2 {
                            StopAirportPicker(
                                title: "STOP 2",
                                selection: $intermediateStop2ICAO,
                                airports: airports,
                                excluding: [flightDepartureICAO, flightArrivalICAO, intermediateStop1ICAO],
                                origin: flightDepartureAirport,
                                destination: flightArrivalAirport,
                                stopCount: intermediateStopCount,
                                stopIndex: 2
                            )
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
                .frame(width: 220, alignment: .leading)

                Spacer(minLength: 0)

                Button {
                    applyAutomaticETOPSRoute()
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.dashboardBlue)
                        .frame(width: 38, height: 32)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.dashboardBlue.opacity(0.55), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ETOPS-Route automatisch planen")

                Button {
                    showsRouteMap = true
                } label: {
                    Image(systemName: "globe.europe.africa.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 32)
                        .background(Color.dashboardBlue, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Streckenkarte öffnen")
            }
        }
        .zIndex(12)
    }

    private var charterCalculationSection: some View {
        VStack(alignment: .leading, spacing: DashboardLayout.sectionGap) {
            HStack {
                SectionTitle(title: "CHARTERKALKULATION", systemName: "eurosign.circle")
                Spacer()
                Text("Landegebühren")
                    .font(.caption.bold())
                    .foregroundStyle(Color.dashboardNavy)
                Toggle("", isOn: $includeLandingFees)
                    .labelsHidden()
                    .tint(Color.dashboardBlue)
            }
            .frame(height: 27)
            DashboardCard {
                VStack(spacing: 3) {
                HStack {
                    CharterColumnHeader("STRECKE NM")
                    CharterColumnHeader("BLOCKZEIT")
                    CharterColumnHeader("KRAFTSTOFF")
                    CharterColumnHeader("LANDEGEBÜHR")
                    CharterColumnHeader("CHARTER")
                }

                HStack(spacing: 8) {
                    CharterValueBox(value: "\(Int(routeDistanceNM.rounded())) NM")
                    CharterValueBox(value: charterBlockHours.formatted(.number.precision(.fractionLength(1))) + " h")
                    CharterValueBox(value: "\(charterFuelLiters) L", accent: .green)
                    CharterValueBox(value: includeLandingFees ? "?" : "—")
                    CharterValueBox(value: "\(charterCostEUR) €")
                }

                Divider()

                HStack {
                    Text("GESAMT HINFLUG")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.dashboardNavy)
                    Spacer()
                    Text(includeLandingFees ? "\(charterCostEUR) € + ?" : "\(charterCostEUR) €")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(Color.dashboardNavy)
                }
                .padding(.horizontal, 4)
                .frame(height: 29)
                }
            }
            .frame(height: 115)
        }
    }

    private var bottomMenuBar: some View {
        HStack(spacing: 0) {
            BottomMenuButton(systemName: "house.fill", label: "Hauptseite", selected: true) {}
            BottomMenuButton(systemName: "airplane.arrival", label: "Destination Finder") { showsMigrationNotice = true }
            BottomMenuButton(systemName: "signpost.right.and.left", label: "Alternates") { showsMigrationNotice = true }
            BottomMenuButton(systemName: "calendar.badge.clock", label: "Reservierungen") { showsMigrationNotice = true }
            BottomMenuButton(systemName: "building.2", label: "Basis") { showsMigrationNotice = true }
            BottomMenuButton(systemName: "airplane", label: "Flugzeug") { showsMigrationNotice = true }
            BottomMenuButton(systemName: "gearshape", label: "Setup") { showsMigrationNotice = true }
        }
        .padding(.horizontal, 6)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black.opacity(0.09), lineWidth: 1)
        }
    }

    private func selectDestination(offset: Int) {
        guard !destinationAirports.isEmpty else { return }
        let current = destinationAirports.firstIndex(where: { $0.icao == destination.icao }) ?? 0
        let next = (current + offset + destinationAirports.count) % destinationAirports.count
        destinationICAO = destinationAirports[next].icao
    }

    private var destinationHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                showsAirportPicker = true
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(destination.name.uppercased())
                        .font(.system(size: 31, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.dashboardNavy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    HStack(spacing: 7) {
                        Text(countryFlag(destination.countryCode))
                        Text("·")
                        Text(destination.icao)
                        Text("·")
                        Text("HÖHE \(destination.elevationFeet.formatted()) FT")
                        Image(systemName: "chevron.down")
                            .font(.caption.bold())
                    }
                    .font(.headline)
                    .foregroundStyle(Color.dashboardNavy)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                showsMigrationNotice = true
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "cloud.sun.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 30, weight: .bold))
                    Text("NOW!")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(Color.dashboardNavy)
                }
                .frame(width: 66, height: 66)
                .background(Color.white, in: Circle())
                .overlay {
                    Circle().stroke(Color.dashboardBlue, lineWidth: 2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Wetter jetzt vollständig aktualisieren")
        }
        .padding(.top, 2)
    }

    private var setupPanel: some View {
        DashboardCard {
            HStack(spacing: 10) {
                CompactSetupPicker(
                    title: "BASIS",
                    icon: "building.2",
                    selection: $activeBase,
                    options: ["LSV Mainz"]
                )
                Divider().frame(height: 42)
                CompactSetupPicker(
                    title: "FLUGZEUG",
                    icon: "airplane",
                    selection: $activeAircraft,
                    options: ["DEZHS", "DEUKS", "DETIK"]
                )
                Divider().frame(height: 42)
                CompactSetupPicker(
                    title: "NUTZER",
                    icon: "person",
                    selection: $activeUser,
                    options: ["Stephan", "Maria"]
                )
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            DashboardIconButton(
                systemName: "airplane.arrival",
                accessibilityLabel: "Destination Finder",
                action: { showsMigrationNotice = true }
            )
            DashboardIconButton(
                systemName: "signpost.right.and.left",
                accessibilityLabel: "Alternates",
                action: { showsMigrationNotice = true }
            )
            DashboardIconButton(
                systemName: "calendar.badge.clock",
                accessibilityLabel: "Reservierungen",
                action: { showsMigrationNotice = true }
            )
            DashboardIconButton(
                systemName: "gearshape",
                accessibilityLabel: "Setup",
                action: { showsMigrationNotice = true }
            )

            Spacer(minLength: 4)

            Picker("Einheitensystem", selection: $unitSystem) {
                Text("🇪🇺").tag("EU")
                Text("🇺🇸").tag("US")
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 118)
            .accessibilityLabel("Einheitensystem")
        }
        .padding(.horizontal, 4)
    }

    private var airportSummary: some View {
        DashboardCard {
            HStack(spacing: 0) {
                SummaryMetric(
                    title: "RUNWAY",
                    value: destination.runwayDisplay,
                    icon: "road.lanes"
                )
                Divider().frame(height: 52)
                SummaryMetric(
                    title: "DISTANZ",
                    value: "\(Int(routeDistanceNM.rounded())) NM",
                    icon: "location"
                )
                Divider().frame(height: 52)
                SummaryMetric(
                    title: "TECHSTOP",
                    value: destination.isTechStop ? "JA" : "–",
                    icon: "fuelpump"
                )
            }
        }
    }

    private var flightPlanningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "FLUGPLANUNG", systemName: "point.topleft.down.to.point.bottomright.curvepath")

            FlightLegCard(
                title: "HINFLUG",
                departureAirport: homeAirport,
                arrivalAirport: destination,
                departure: $outboundDeparture,
                durationMinutes: routeMinutes,
                distanceNM: routeDistanceNM
            )
            .frame(height: 154)
            .clipped()

            FlightLegCard(
                title: "RÜCKFLUG",
                departureAirport: destination,
                arrivalAirport: homeAirport,
                departure: $returnDeparture,
                durationMinutes: routeMinutes,
                distanceNM: routeDistanceNM
            )
            .frame(height: 154)
            .clipped()
        }
    }

    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: "5-TAGES-WETTER", systemName: "cloud.sun")
                Spacer()
                Text("ICON-SEAMLESS · NOCH NICHT VERBUNDEN")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }

            DashboardCard {
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { offset in
                            ForecastPlaceholderTile(
                                date: Calendar.current.date(
                                    byAdding: .day,
                                    value: offset,
                                    to: .now
                                ) ?? .now
                            )
                        }
                    }

                    Divider()

                    HStack {
                        Label("FOG RISK 06–22 UHR", systemImage: "cloud.fog")
                        Spacer()
                        Text("Wetteranbindung folgt")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                }
            }

            DashboardCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("10-TAGES-WETTER")
                            .font(.headline.bold())
                            .foregroundStyle(Color.dashboardNavy)
                        Text("Tagesmittel aus 08 / 14 / 20 Uhr")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "calendar.badge.clock")
                        .font(.title2)
                        .foregroundStyle(Color.dashboardBlue)
                }
            }
        }
    }

    private func countryFlag(_ countryCode: String) -> String {
        countryCode.uppercased().unicodeScalars.compactMap {
            Unicode.Scalar(127_397 + $0.value).map(String.init)
        }.joined()
    }
}

private struct HeaderNavigationButton: View {
    let systemName: String
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 42, height: 38)
                .background(
                    highlighted ? Color.dashboardBlue : Color.dashboardNavy,
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct HeaderDestinationSearch: View {
    let airports: [Airport]
    @Binding var selectedICAO: String

    @State private var query = ""
    @FocusState private var focused: Bool

    private var suggestions: [Airport] {
        guard query.count >= 3 else { return [] }
        return Array(
            airports.filter {
                $0.icao.hasPrefix(query.uppercased())
                    || $0.name.localizedCaseInsensitiveContains(query)
            }.prefix(4)
        )
    }

    var body: some View {
        TextField("ICAO", text: $query)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .font(.subheadline.bold().monospaced())
            .foregroundStyle(Color.dashboardBlue)
            .frame(width: 54)
            .focused($focused)
            .onAppear { query = selectedICAO }
            .onChange(of: selectedICAO) { _, value in
                if !focused { query = value }
            }
            .onChange(of: query) { _, value in
                let normalized = String(value.uppercased().prefix(4))
                if normalized != value {
                    query = normalized
                    return
                }
                if let airport = airports.first(where: { $0.icao == normalized }) {
                    selectedICAO = airport.icao
                }
            }
            .overlay(alignment: .topLeading) {
                if focused, !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions) { airport in
                            Button {
                                query = airport.icao
                                selectedICAO = airport.icao
                                focused = false
                            } label: {
                                Text("\(airport.icao) · \(airport.name)")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.dashboardNavy)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .frame(width: 230, height: 30, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.dashboardBlue.opacity(0.4)) }
                    .shadow(radius: 7)
                    .offset(y: 25)
                    .zIndex(100)
                }
            }
    }
}

private struct FuelStatusCell: View {
    let title: String
    let status: FuelAvailabilityStatus
    let price: FuelPricePoint?
    let referencePrice: FuelPricePoint?

    private var color: Color {
        switch status {
        case .available: return .green
        case .unavailable: return .red
        case .check: return .orange
        }
    }

    private var priceText: String {
        guard let price else { return "? €/L" }
        let formatted = String(format: "%.2f", price.eurosPerLiter)
            .replacingOccurrences(of: ".", with: ",")
        guard let referencePrice else { return "\(formatted) €/L" }
        let delta = price.eurosPerLiter - referencePrice.eurosPerLiter
        let difference = String(format: "%+.2f", delta)
            .replacingOccurrences(of: ".", with: ",")
        return "\(formatted) €/L (\(difference))"
    }

    private var dateText: String {
        "Stand \(price?.checkedAt ?? "unklar")"
    }

    var body: some View {
        VStack(spacing: 3) {
            Label(title, systemImage: "fuelpump.fill")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                Text(status.label)
                    .font(.subheadline.bold())
                    .foregroundStyle(color)
            }
            Text(priceText)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.dashboardNavy)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(dateText)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CharterColumnHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct StopAirportPicker: View {
    let title: String
    @Binding var selection: String
    let airports: [Airport]
    let excluding: [String]
    let origin: Airport
    let destination: Airport
    let stopCount: Int
    let stopIndex: Int
    @State private var query = ""
    @FocusState private var queryIsFocused: Bool

    private var targetCoordinate: (latitude: Double, longitude: Double) {
        let fraction = stopCount <= 1 ? 0.5 : (stopIndex == 1 ? 1.0 / 3.0 : 2.0 / 3.0)
        return FlightGeometry.intermediateCoordinate(
            from: origin,
            to: destination,
            fraction: fraction
        )
    }

    private var options: [Airport] {
        airports
            .filter { airport in
                !excluding.contains(airport.icao)
                    && (airport.isTechStop || airport.runwayLengthMeters != nil)
            }
            .sorted {
                let lhsDistance = FlightGeometry.nauticalMiles(from: $0, to: targetCoordinate)
                let rhsDistance = FlightGeometry.nauticalMiles(from: $1, to: targetCoordinate)
                if abs(lhsDistance - rhsDistance) > 0.1 { return lhsDistance < rhsDistance }
                return $0.icao < $1.icao
            }
    }

    private var suggestions: [Airport] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 3 else { return [] }
        return Array(options.filter {
            $0.icao.localizedCaseInsensitiveContains(term)
                || $0.name.localizedCaseInsensitiveContains(term)
        }.prefix(5))
    }

    private var showsSuggestions: Bool {
        queryIsFocused && query.count >= 3 && !suggestions.isEmpty
    }

    private func choose(_ airport: Airport?) {
        selection = airport?.icao ?? ""
        query = airport?.icao ?? ""
        queryIsFocused = false
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    TextField("Virtuell / ICAO", text: $query)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.dashboardNavy)
                        .lineLimit(1)
                        .padding(.leading, 8)
                        .focused($queryIsFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            if let airport = suggestions.first { choose(airport) }
                        }

                    Menu {
                        Button("Virtuell · Modellroute") { choose(nil) }
                        ForEach(options) { airport in
                            Button("\(airport.icao) · \(airport.name)") {
                                choose(airport)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.dashboardBlue)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 172, height: 28)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.dashboardBlue.opacity(0.45), lineWidth: 1)
                }

                if showsSuggestions {
                    VStack(spacing: 0) {
                        ForEach(suggestions) { airport in
                            Button {
                                choose(airport)
                            } label: {
                                HStack(spacing: 5) {
                                    Text(airport.icao).fontWeight(.heavy)
                                    Text(airport.name)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer(minLength: 0)
                                }
                                .font(.system(size: 10))
                                .foregroundStyle(Color.dashboardNavy)
                                .padding(.horizontal, 8)
                                .frame(width: 205, height: 28)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if airport.id != suggestions.last?.id { Divider() }
                        }
                    }
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Color.dashboardBlue.opacity(0.42), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                    .offset(y: 31)
                    .zIndex(30)
                }
            }
            .frame(width: 172, height: 28, alignment: .topLeading)
        }
        .onAppear { query = selection }
        .onChange(of: selection) { _, newValue in
            if query.uppercased() != newValue.uppercased() { query = newValue }
        }
        .onChange(of: query) { _, newValue in
            let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if normalized.isEmpty {
                selection = ""
            } else if let airport = options.first(where: { $0.icao == normalized }) {
                selection = airport.icao
            }
        }
        .zIndex(showsSuggestions ? 30 : 1)
    }
}

private struct CharterValueBox: View {
    let value: String
    var accent: Color = Color.dashboardNavy

    var body: some View {
        Text(value)
            .font(.headline.bold().monospacedDigit())
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
            .background(Color.dashboardBackground, in: RoundedRectangle(cornerRadius: 12))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct BottomMenuButton: View {
    let systemName: String
    let label: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(selected ? .white : Color.dashboardBlue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    selected ? Color.dashboardBlue : Color.clear,
                    in: RoundedRectangle(cornerRadius: 13)
                )
        }
        .buttonStyle(.plain)
        .padding(5)
        .accessibilityLabel(label)
    }
}

private struct CompactSetupPicker: View {
    let title: String
    let icon: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(Color.dashboardNavy)

            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Color.dashboardNavy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.dashboardBlue)
                .frame(width: 46, height: 40)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.dashboardBlue.opacity(0.45), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(Color.dashboardNavy)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }
}

private struct EditableFlightLegCard: View {
    let airports: [Airport]
    @Binding var departureICAO: String
    @Binding var arrivalICAO: String
    @Binding var departure: Date
    let durationMinutes: Int
    let etopsLegMinutes: Int
    let etopsGreenYellowMinutes: Int
    let etopsOrangeRedMinutes: Int
    let distanceNM: Double
    @Binding var selectedAltitudeFeet: Int
    let altitudeOptions: [Int]
    let bestLevelFeet: Int
    let departureAirport: Airport
    let arrivalAirport: Airport
    let routeRisks: [IPadRouteWeatherRisk]
    let onSwap: () -> Void
    let onArrivalSelected: (Airport) -> Void

    private var arrival: Date {
        departure.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    private var routeWind: (value: String, color: Color) {
        let weather = DashboardWeatherPreview.snapshot(for: arrivalAirport)
        let course = FlightGeometry.initialBearing(from: departureAirport, to: arrivalAirport)
        let difference = (weather.windDirectionDegrees - course) * .pi / 180
        let component = weather.windSpeedKnots * cos(difference)
        if component > 0.5 {
            return ("Gegenwind \(Int(component.rounded())) kt", .red)
        }
        if component < -0.5 {
            return ("Rückenwind \(Int(abs(component).rounded())) kt", .green)
        }
        return ("Wind neutral 0 kt", Color.dashboardBlue)
    }

    private var etopsBlockColor: Color {
        let greenYellow = max(30, etopsGreenYellowMinutes)
        let orangeRed = max(greenYellow + 10, etopsOrangeRedMinutes)
        let yellowOrange = greenYellow + (orangeRed - greenYellow) / 2
        if etopsLegMinutes < greenYellow { return .green }
        if etopsLegMinutes < yellowOrange { return .yellow }
        if etopsLegMinutes < orangeRed { return .orange }
        return .red
    }

    var body: some View {
        DashboardCard {
            VStack(spacing: 6) {
                IPadRouteRiskBars(risks: routeRisks)
                    .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14)

                ZStack {
                Rectangle()
                    .fill(Color.dashboardNavy.opacity(0.15))
                    .frame(width: 1)
                    .padding(.vertical, -2)

                VStack(spacing: 5) {
                    HStack(spacing: 0) {
                        FlightAirportHalf(
                            title: "ABFLUG",
                            text: $departureICAO,
                            airports: airports,
                            airport: departureAirport,
                            referenceDate: departure,
                            onSelect: { _ in }
                        )
                        FlightAirportHalf(
                            title: "ANKUNFT",
                            text: $arrivalICAO,
                            airports: airports,
                            airport: arrivalAirport,
                            referenceDate: arrival,
                            onSelect: onArrivalSelected
                        )
                    }
                    .zIndex(2)

                    Color.clear.frame(height: 76)
                }

                UniformFlightMetricBox(
                    title: "ABFLUG",
                    value: departure.formatted(date: .omitted, time: .shortened)
                )
                .frame(width: 132)
                .offset(x: -306, y: 43)

                UniformFlightMetricBox(
                    title: "ANKUNFT",
                    value: arrival.formatted(date: .omitted, time: .shortened)
                )
                .frame(width: 132)
                .offset(x: 306, y: 43)

                UniformFlightMetricBox(
                    title: "REISEZEIT",
                    value: "\(durationMinutes / 60):\(String(format: "%02d", durationMinutes % 60))",
                    valueColor: Color.dashboardBlue,
                    boxTint: Color.dashboardNavy,
                    solidBackground: true
                )
                .frame(width: 128)
                .offset(y: 43)

                RoundedRectangle(cornerRadius: 3)
                    .fill(etopsBlockColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.dashboardNavy.opacity(0.55), lineWidth: 0.8)
                    }
                    .frame(width: 68, height: 6)
                    .offset(y: 17)
                    .zIndex(5)

                VStack(spacing: 1) {
                    Text("BEST LEVEL")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(altitudeLabel(bestLevelFeet))
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.dashboardNavy)
                }
                .frame(width: 94)
                .offset(x: -111, y: 43)

                Menu {
                    ForEach(altitudeOptions, id: \.self) { altitude in
                        Button(altitudeLabel(altitude)) {
                            selectedAltitudeFeet = altitude
                        }
                    }
                } label: {
                    VStack(spacing: 1) {
                        Text("FLUGHÖHE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 3) {
                            Text(altitudeLabel(selectedAltitudeFeet))
                                .font(.system(size: 17, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.dashboardNavy)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 7, weight: .heavy))
                                .foregroundStyle(Color.dashboardNavy.opacity(0.72))
                        }
                    }
                    .frame(width: 94)
                }
                .buttonStyle(.plain)
                .offset(x: 111, y: 43)
                .accessibilityLabel("Flughöhe auswählen")

                Button(action: onSwap) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.dashboardBlue, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .offset(y: -12)
                .zIndex(4)
                .accessibilityLabel("Abflug und Ankunft tauschen")

                Text(routeWind.value)
                    .font(.system(size: 11, weight: .heavy).monospacedDigit())
                    .foregroundStyle(routeWind.color)
                    .lineLimit(1)
                    .frame(width: 128, height: 16)
                    .offset(y: 78)
                    .zIndex(4)
                }
                .frame(height: 188)

                HStack(spacing: 0) {
                    FlightWeatherMetrics(airport: departureAirport)
                    Divider().frame(height: 42)
                    FlightWeatherMetrics(airport: arrivalAirport)
                }
                .frame(height: 55)
            }
        }
    }

    private func altitudeLabel(_ altitude: Int) -> String {
        altitude < 5_000
            ? "\(altitude.formatted(.number.grouping(.automatic))) ft"
            : String(format: "FL%03d", altitude / 100)
    }
}

private struct UniformFlightMetricBox: View {
    let title: String
    let value: String
    var valueColor: Color = Color.dashboardBlue
    var boxTint: Color = Color.dashboardBlue
    var solidBackground = false

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
        .background(solidBackground ? Color.white : boxTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(solidBackground ? Color.dashboardNavy : boxTint.opacity(0.65), lineWidth: solidBackground ? 1.5 : 1)
        }
    }
}

private struct FlightAirportHalf: View {
    let title: String
    @Binding var text: String
    let airports: [Airport]
    let airport: Airport
    let referenceDate: Date
    let onSelect: (Airport) -> Void

    private var mirrored: Bool { title == "ANKUNFT" }
    private var weather: DashboardWeatherSnapshot {
        DashboardWeatherPreview.snapshot(for: airport)
    }

    var body: some View {
        ZStack {
            AirportICAOField(
                title: title,
                text: $text,
                airports: airports,
                referenceDate: referenceDate,
                mirrored: mirrored,
                weather: weather,
                onSelect: onSelect
            )
            .frame(maxWidth: .infinity, alignment: mirrored ? .trailing : .leading)

            RunwayRecommendationPanel(
                airport: airport,
                weather: weather,
                mirrored: mirrored
            )
        }
        .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 100)
        .padding(.horizontal, 8)
    }
}

private struct RunwayRecommendationPanel: View {
    let airport: Airport
    let weather: DashboardWeatherSnapshot
    let mirrored: Bool

    private var runwayEnds: [String] {
        airport.referenceRunway
            .split(separator: "/")
            .map { String($0.prefix(2)) }
    }

    private var runwayHeading: Double {
        (Double(runwayEnds.first ?? "") ?? 0) * 10
    }

    private var runwayHeadings: [(label: String, heading: Double)] {
        runwayEnds.compactMap { label in
            guard let number = Double(label) else { return nil }
            return (label, number * 10)
        }
    }

    private var recommendation: (
        label: String,
        heading: Double,
        headwind: Double,
        crosswind: Double,
        crosswindComesFromRight: Bool
    )? {
        runwayHeadings.map { end in
            let difference = shortestAngle(weather.windDirectionDegrees - end.heading) * .pi / 180
            let signedCrosswind = weather.windSpeedKnots * sin(difference)
            return (
                end.label,
                end.heading,
                weather.windSpeedKnots * cos(difference),
                abs(signedCrosswind),
                signedCrosswind > 0
            )
        }.max { $0.headwind < $1.headwind }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 1) {
                ZStack {
                    Circle()
                        .fill(Color.dashboardBackground)
                        .overlay { Circle().stroke(Color.dashboardBlue.opacity(0.22)) }
                    Text("N")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .offset(y: -37)
                    Capsule()
                        .fill(Color.dashboardNavy.opacity(0.82))
                        .frame(width: 72, height: 10)
                        .overlay {
                            Rectangle().fill(Color.white.opacity(0.85)).frame(width: 54, height: 1.5)
                        }
                        .rotationEffect(.degrees(runwayHeading - 90))
                    WindDirectionArrow()
                        .stroke(.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(width: 44, height: 66)
                        .rotationEffect(.degrees(weather.windDirectionDegrees))

                    if runwayEnds.count == 2 {
                        RunwayEndLabel(
                            text: runwayEnds[0],
                            active: recommendation?.label == runwayEnds[0]
                        )
                            .offset(runwayLabelOffset(heading: runwayHeading + 180))
                        RunwayEndLabel(
                            text: runwayEnds[1],
                            active: recommendation?.label == runwayEnds[1]
                        )
                            .offset(runwayLabelOffset(heading: runwayHeading))
                    }
                }
                .frame(width: 90, height: 80)
                HStack(spacing: 8) {
                    Text(headwindText)
                        .foregroundStyle((recommendation?.headwind ?? 0) >= 0 ? .green : .red)
                    Text(crosswindText)
                        .foregroundStyle(.orange)
                }
                .font(.system(size: 13, weight: .heavy).monospacedDigit())
                .frame(width: 132, alignment: .center)
            }

            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "road.lanes")
                    Text(recommendation?.label ?? "—")
                }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.dashboardNavy)
                .frame(height: 18)

                Text(metarWindText)
                    .font(.system(size: 12.5, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Color.dashboardNavy)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .frame(width: 82, height: 40)
                    .background(metarBoxFill, in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(metarBoxBorder, lineWidth: 1.3) }
            }
            .offset(x: mirrored ? -106 : 106, y: -9)
        }
        .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 100)
        .accessibilityLabel("Runway \(airport.referenceRunway), bevorzugt \(recommendation?.label ?? "unbekannt")")
    }

    private func runwayLabelOffset(heading: Double) -> CGSize {
        let radians = (heading - 90) * .pi / 180
        return CGSize(width: cos(radians) * 41, height: sin(radians) * 41)
    }

    private func shortestAngle(_ angle: Double) -> Double {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized > 180 { normalized -= 360 }
        if normalized < -180 { normalized += 360 }
        return normalized
    }

    private var headwindText: String {
        let value = recommendation?.headwind ?? 0
        return value >= 0
            ? "↓ \(Int(value.rounded())) kt"
            : "↑ \(Int(abs(value).rounded())) kt"
    }

    private var crosswindText: String {
        let value = recommendation?.crosswind ?? 0
        guard value >= 0.5 else { return "↔ 0 kt" }
        let arrow = recommendation?.crosswindComesFromRight == true ? "←" : "→"
        return "\(arrow) \(Int(value.rounded())) kt"
    }

    private var metarWindText: String {
        let base = String(format: "%03.0f/%02.0f", weather.windDirectionDegrees, weather.windSpeedKnots)
        return weather.gustKnots.map { "\(base) G\($0)" } ?? base
    }

    private var windLimitColor: Color {
        let crosswind = recommendation?.crosswind ?? 0
        if crosswind >= 12 || weather.windSpeedKnots >= 18 || (weather.gustKnots ?? 0) >= 25 {
            return .red
        }
        if crosswind >= 8 || weather.windSpeedKnots >= 12 || (weather.gustKnots ?? 0) >= 18 {
            return .orange
        }
        return .green
    }

    private var metarBoxFill: Color {
        isNormalWind ? .white : windLimitColor.opacity(0.18)
    }

    private var metarBoxBorder: Color {
        isNormalWind ? Color.gray.opacity(0.35) : windLimitColor.opacity(0.85)
    }

    private var isNormalWind: Bool {
        let crosswind = recommendation?.crosswind ?? 0
        return crosswind < 8
            && weather.windSpeedKnots < 12
            && (weather.gustKnots ?? 0) < 18
    }
}

private struct WindDirectionArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.midX
        let top = rect.minY + 4
        let bottom = rect.maxY - 5
        path.move(to: CGPoint(x: x, y: top))
        path.addLine(to: CGPoint(x: x, y: bottom))
        path.move(to: CGPoint(x: x, y: bottom))
        path.addLine(to: CGPoint(x: x - 7, y: bottom - 10))
        path.move(to: CGPoint(x: x, y: bottom))
        path.addLine(to: CGPoint(x: x + 7, y: bottom - 10))
        return path
    }
}

private struct RunwayEndLabel: View {
    let text: String
    let active: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .black).monospacedDigit())
            .foregroundStyle(active ? .white : Color.dashboardNavy)
            .padding(.horizontal, 5)
            .frame(height: 18)
            .background(active ? Color.dashboardBlue : Color.white, in: Capsule())
            .overlay { Capsule().stroke(Color.dashboardBlue.opacity(0.35)) }
    }
}

private enum OperationalStatus {
    case open, closed, unknown

    var tint: Color {
        switch self {
        case .open: return .green
        case .closed: return .red
        case .unknown: return Color.dashboardBlue
        }
    }
}

private struct FlightTimeBox: View {
    let title: String
    @Binding var date: Date
    let status: OperationalStatus

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
            DatePicker(title, selection: $date, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .font(.subheadline.bold().monospacedDigit())
        }
        .frame(width: 84, height: 44)
        .background(status.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(status.tint.opacity(0.65)) }
    }
}

private struct ReadOnlyFlightTimeBox: View {
    let title: String
    let date: Date
    let status: OperationalStatus

    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(Color.dashboardNavy)
        }
        .frame(width: 78, height: 44)
        .background(status.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(status.tint.opacity(0.65)) }
    }
}

private struct AltitudeDisplayBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(Color.dashboardBlue)
        }
        .frame(width: 82, height: 44)
        .background(Color.dashboardBackground, in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct DashboardWeatherSnapshot {
    let category: String
    let temperatureCelsius: Int
    let visibilityKilometers: String
    let clouds: String
    let cloudBaseFeet: String
    let pressureHPA: Int
    let densityAltitudeFeet: Int
    let windDirectionDegrees: Double
    let windSpeedKnots: Double
    let gustKnots: Int?

    var categoryColor: Color {
        switch category {
        case "VFR": return .green
        case "MVFR": return Color.dashboardBlue
        case "IFR": return .red
        default: return .purple
        }
    }

    var symbolName: String {
        switch clouds {
        case "SKC": return "sun.max.fill"
        case "FEW", "SCT": return "cloud.sun.fill"
        case "BKN": return "cloud.fill"
        default: return "cloud.fog.fill"
        }
    }

    var symbolColor: Color {
        switch clouds {
        case "SKC": return .orange
        case "FEW", "SCT": return Color.dashboardBlue
        default: return Color.dashboardNavy.opacity(0.72)
        }
    }
}

private enum DashboardWeatherPreview {
    static func snapshot(for airport: Airport) -> DashboardWeatherSnapshot {
        switch airport.icao {
        case "EDFZ":
            return .init(
                category: "VFR", temperatureCelsius: 23, visibilityKilometers: "10+",
                clouds: "FEW", cloudBaseFeet: "4.800", pressureHPA: 1018,
                densityAltitudeFeet: 2_180, windDirectionDegrees: 240,
                windSpeedKnots: 5, gustKnots: nil
            )
        case "EDAX":
            return .init(
                category: "VFR", temperatureCelsius: 21, visibilityKilometers: "10+",
                clouds: "SCT", cloudBaseFeet: "3.900", pressureHPA: 1015,
                densityAltitudeFeet: 1_620, windDirectionDegrees: 260,
                windSpeedKnots: 8, gustKnots: 14
            )
        default:
            return .init(
                category: "MVFR", temperatureCelsius: 19, visibilityKilometers: "8",
                clouds: "BKN", cloudBaseFeet: "2.400", pressureHPA: 1016,
                densityAltitudeFeet: max(1_400, airport.elevationFeet + 1_100),
                windDirectionDegrees: 230, windSpeedKnots: 7, gustKnots: 12
            )
        }
    }
}

private struct FlightCategoryBadge: View {
    let weather: DashboardWeatherSnapshot

    var body: some View {
        Text(weather.category)
            .font(.system(size: 10, weight: .black))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: 48, height: 25)
            .background(weather.categoryColor, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.dashboardNavy.opacity(0.22), lineWidth: 1)
            }
    }
}

private struct FlightWeatherMetrics: View {
    let airport: Airport

    private var weather: DashboardWeatherSnapshot {
        DashboardWeatherPreview.snapshot(for: airport)
    }

    var body: some View {
        HStack(spacing: 5) {
            WeatherMetricGroup {
                WeatherMetric(title: "QNH", value: "\(weather.pressureHPA)")
                WeatherMetric(title: "TEMP", value: "\(weather.temperatureCelsius) °C")
                WeatherMetric(title: "DICHTEHÖHE", value: "\(weather.densityAltitudeFeet.formatted()) ft")
            }
            WeatherMetricGroup {
                WeatherMetric(title: "WOLKEN", value: weather.clouds)
                WeatherMetric(title: "BASIS", value: "\(weather.cloudBaseFeet) ft")
                WeatherMetric(title: "SICHT", value: "\(weather.visibilityKilometers) km")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }
}

private struct AirportWeatherColumn: View {
    let airport: Airport

    private var weather: DashboardWeatherSnapshot {
        DashboardWeatherPreview.snapshot(for: airport)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(weather.categoryColor).frame(width: 10, height: 10)
                Text(airport.icao).font(.system(size: 17, weight: .bold)).foregroundStyle(Color.dashboardBlue)
                Text(airport.name).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.dashboardNavy).lineLimit(1)
                Text(weather.category)
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(weather.categoryColor)
                Spacer(minLength: 2)
                Image(systemName: weather.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(weather.symbolColor)
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 24)
            }
            HStack(spacing: 5) {
                WeatherMetricGroup {
                    WeatherMetric(title: "QNH", value: "\(weather.pressureHPA)")
                    WeatherMetric(title: "TEMP", value: "\(weather.temperatureCelsius) °C")
                    WeatherMetric(title: "DICHTEHÖHE", value: "\(weather.densityAltitudeFeet.formatted()) ft")
                }
                WeatherMetricGroup {
                    WeatherMetric(title: "WOLKEN", value: weather.clouds)
                    WeatherMetric(title: "BASIS", value: "\(weather.cloudBaseFeet) ft")
                    WeatherMetric(title: "SICHT", value: "\(weather.visibilityKilometers) km")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

private struct WeatherMetricGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.dashboardBlue.opacity(0.38), lineWidth: 1)
        }
    }
}

private struct WeatherMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 7.8, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(value)
                .font(.system(size: 12.5, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.dashboardNavy)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AirportICAOField: View {
    let title: String
    @Binding var text: String
    let airports: [Airport]
    let referenceDate: Date
    let mirrored: Bool
    let weather: DashboardWeatherSnapshot
    let onSelect: (Airport) -> Void

    @FocusState private var isFocused: Bool

    private var matchingAirports: [Airport] {
        guard text.count >= 3 else { return [] }
        let normalized = text.uppercased()
        return Array(
            airports.filter {
                $0.icao.hasPrefix(normalized)
                    || $0.name.localizedCaseInsensitiveContains(text)
            }.prefix(3)
        )
    }

    private var selectedAirport: Airport? {
        airports.first { $0.icao == text.uppercased() }
    }

    var body: some View {
        VStack(alignment: mirrored ? .trailing : .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                if mirrored {
                    FlightCategoryBadge(weather: weather)
                }
                TextField("ICAO", text: $text)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.dashboardBlue)
                    .multilineTextAlignment(mirrored ? .trailing : .leading)
                    .focused($isFocused)
                    .frame(width: 76)
                    .onChange(of: text) { _, value in
                        let normalized = String(value.uppercased().prefix(4))
                        if normalized != value { text = normalized }
                    }
                if !mirrored {
                    FlightCategoryBadge(weather: weather)
                }
            }
            .frame(maxWidth: .infinity, alignment: mirrored ? .trailing : .leading)
            Text(selectedAirport?.name ?? "Flugplatz wählen")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.dashboardNavy)
                .lineLimit(1)
            Text(DashboardSolarClock.display(for: selectedAirport, on: referenceDate))
                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 142, alignment: mirrored ? .trailing : .leading)
        .overlay(alignment: .topLeading) {
            if isFocused, !matchingAirports.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(matchingAirports) { airport in
                        Button {
                            text = airport.icao
                            onSelect(airport)
                            isFocused = false
                        } label: {
                            Text("\(airport.icao) · \(airport.name)")
                                .font(.caption.bold())
                                .foregroundStyle(Color.dashboardNavy)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .frame(width: 210, height: 30, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.dashboardBlue.opacity(0.35), lineWidth: 1)
                }
                .shadow(radius: 6)
                .offset(y: 66)
                .zIndex(10)
            }
        }
    }
}

private struct PlanningMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(Color.dashboardNavy)
        }
        .frame(width: 58)
    }
}

private struct ForecastRiskBar: View {
    let title: String
    let systemName: String

    var body: some View {
        HStack(spacing: 6) {
            Label(title, systemImage: systemName)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 128, alignment: .leading)
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.18))
                    .frame(maxWidth: .infinity, minHeight: 14)
            }
            Text("Daten ausstehend")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct FlightLegCard: View {
    let title: String
    let departureAirport: Airport
    let arrivalAirport: Airport
    @Binding var departure: Date
    let durationMinutes: Int
    let distanceNM: Double

    private var arrival: Date {
        departure.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    var body: some View {
        DashboardCard {
            VStack(spacing: 9) {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.headline.bold())
                        .foregroundStyle(Color.dashboardNavy)
                        .frame(width: 92, alignment: .leading)

                    AirportEndpoint(airport: departureAirport, title: "ABFLUG")
                    Image(systemName: "arrow.right")
                        .font(.headline.bold())
                        .foregroundStyle(.secondary)
                    AirportEndpoint(airport: arrivalAirport, title: "ANKUNFT")

                    Button(action: {}) {
                        Image(systemName: "arrow.clockwise")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 34)
                            .background(Color.dashboardBlue, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Flugplatzwetter datenoptimiert aktualisieren")
                }

                Divider()

                HStack(spacing: 10) {
                    DatePicker("Datum", selection: $departure, displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 132)
                    DatePicker("Abflug", selection: $departure, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 92)

                    Spacer()

                    Label("\(durationMinutes / 60):\(String(format: "%02d", durationMinutes % 60)) h", systemImage: "clock")
                    Label("\(Int(distanceNM.rounded())) NM", systemImage: "location")
                    Text("FL070")

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(arrival.formatted(date: .omitted, time: .shortened))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Color.dashboardNavy)
                        Text("ANKUNFT")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption.bold())
                .foregroundStyle(Color.dashboardNavy)
            }
        }
    }
}

private struct AirportEndpoint: View {
    let airport: Airport
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(airport.icao)
                .font(.headline.bold())
                .foregroundStyle(Color.dashboardBlue)
            Text(airport.name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.dashboardNavy)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ForecastPlaceholderTile: View {
    let date: Date

    var body: some View {
        VStack(spacing: 6) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption.bold())
                .foregroundStyle(Color.dashboardNavy)
            Image(systemName: "cloud")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("—° / —°")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.dashboardBackground, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SectionTitle: View {
    let title: String
    let systemName: String

    var body: some View {
        Label(title, systemImage: systemName)
            .font(.headline.bold())
            .foregroundStyle(Color.dashboardNavy)
    }
}

private struct DashboardCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.black.opacity(0.09), lineWidth: 1)
            }
    }
}

private enum DashboardSolarClock {
    static func display(for airport: Airport?, on date: Date) -> String {
        guard let airport,
              let sunrise = event(on: date, airport: airport, sunrise: true),
              let sunset = event(on: date, airport: airport, sunrise: false)
        else { return "☀ —  ·  ☾ —" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = TimeZone(identifier: airport.timeZoneIdentifier) ?? .current
        formatter.dateFormat = "HH:mm"
        return "☀ \(formatter.string(from: sunrise))  ·  ☾ \(formatter.string(from: sunset))"
    }

    private static func event(on date: Date, airport: Airport, sunrise: Bool) -> Date? {
        let timeZone = TimeZone(identifier: airport.timeZoneIdentifier) ?? .current
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone
        let day = localCalendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let gamma = 2 * Double.pi / 365 * (Double(day) - 1)
        let equation = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let declination = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let latitude = airport.latitude * .pi / 180
        let zenith = 90.833 * .pi / 180
        let cosineHour = cos(zenith) / (cos(latitude) * cos(declination))
            - tan(latitude) * tan(declination)
        guard (-1.0...1.0).contains(cosineHour) else { return nil }
        let hourAngle = acos(cosineHour) * 180 / .pi
        let noonUTC = 720 - 4 * airport.longitude - equation
        let minutesUTC = sunrise ? noonUTC - 4 * hourAngle : noonUTC + 4 * hourAngle

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = localCalendar.dateComponents([.year, .month, .day], from: date)
        guard let midnight = utcCalendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: parts.year,
            month: parts.month,
            day: parts.day
        )) else { return nil }
        return midnight.addingTimeInterval(minutesUTC * 60)
    }
}

private struct AirportPickerSheet: View {
    let airports: [Airport]
    @Binding var selectedICAO: String

    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var filteredAirports: [Airport] {
        guard !searchText.isEmpty else { return airports }
        return airports.filter {
            $0.icao.localizedCaseInsensitiveContains(searchText)
                || $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredAirports) { airport in
                Button {
                    selectedICAO = airport.icao
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(airport.icao)
                                .font(.headline)
                                .foregroundStyle(Color.dashboardBlue)
                            Text(airport.name)
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        Text(airport.runwayDisplay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Zielflugplatz")
            .searchable(text: $searchText, prompt: "ICAO oder Name")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }
}

private enum FlightGeometry {
    static func nauticalMiles(from origin: Airport, to destination: Airport) -> Double {
        let radiusNM = 3_440.065
        let lat1 = origin.latitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let deltaLat = (destination.latitude - origin.latitude) * .pi / 180
        let deltaLon = (destination.longitude - origin.longitude) * .pi / 180
        let value = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2)
            * sin(deltaLon / 2) * sin(deltaLon / 2)
        return radiusNM * 2 * atan2(sqrt(value), sqrt(1 - value))
    }

    static func initialBearing(from origin: Airport, to destination: Airport) -> Double {
        let lat1 = origin.latitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let deltaLongitude = (destination.longitude - origin.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLongitude)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func nauticalMiles(
        from origin: Airport,
        to coordinate: (latitude: Double, longitude: Double)
    ) -> Double {
        let radiusNM = 3_440.065
        let lat1 = origin.latitude * .pi / 180
        let lat2 = coordinate.latitude * .pi / 180
        let deltaLat = (coordinate.latitude - origin.latitude) * .pi / 180
        let deltaLon = (coordinate.longitude - origin.longitude) * .pi / 180
        let value = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return radiusNM * 2 * atan2(sqrt(value), sqrt(max(0, 1 - value)))
    }

    static func intermediateCoordinate(
        from origin: Airport,
        to destination: Airport,
        fraction: Double
    ) -> (latitude: Double, longitude: Double) {
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let lon2 = destination.longitude * .pi / 180
        let angular = 2 * asin(sqrt(
            pow(sin((lat2 - lat1) / 2), 2)
                + cos(lat1) * cos(lat2) * pow(sin((lon2 - lon1) / 2), 2)
        ))
        guard angular > 0.000_001 else { return (origin.latitude, origin.longitude) }
        let a = sin((1 - fraction) * angular) / sin(angular)
        let b = sin(fraction * angular) / sin(angular)
        let x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2)
        let y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2)
        let z = a * sin(lat1) + b * sin(lat2)
        return (
            atan2(z, sqrt(x * x + y * y)) * 180 / .pi,
            atan2(y, x) * 180 / .pi
        )
    }
}

private extension Date {
    static var defaultFlightDeparture: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        return calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: tomorrow
        ) ?? tomorrow
    }

    var roundedToNextQuarterHour: Date {
        let interval: TimeInterval = 15 * 60
        return Date(timeIntervalSince1970: ceil(timeIntervalSince1970 / interval) * interval)
    }
}

extension Color {
    static let dashboardNavy = Color(red: 0.02, green: 0.18, blue: 0.35)
    static let dashboardBlue = Color(red: 0.18, green: 0.50, blue: 0.83)
    static let dashboardBackground = Color(red: 0.96, green: 0.97, blue: 0.985)
}
