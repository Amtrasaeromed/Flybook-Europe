import SwiftUI

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

    private var routeMinutes: Int {
        let climbMinutes = Int(
            (Double(max(0, selectedAltitudeFeet - 1_500)) / 1_000 * 1.2)
                .rounded()
        )
        return max(
            8,
            Int((routeDistanceNM / 109 * 60).rounded())
                + 5 + climbMinutes + intermediateStopCount * 60
        )
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
        ceil((Double(routeMinutes) / 60) * 10) / 10
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

    var body: some View {
        GeometryReader { geometry in
            let canvasWidth = 820.0
            let canvasHeight = 1_075.0
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
        .alert("Dieser Bereich folgt", isPresented: $showsMigrationNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Die Oberfläche ist vorbereitet. Die bestehende Flybook-Funktion wird in einem der nächsten Migrationsschritte angebunden.")
        }
        .onAppear {
            if flightArrivalICAO.isEmpty {
                flightArrivalICAO = destination.icao
            }
        }
        .onChange(of: destinationICAO) { _, newValue in
            if flightDepartureICAO == "EDFZ" {
                flightArrivalICAO = newValue
            }
        }
    }

    private var fixedDashboard: some View {
        VStack(spacing: 6) {
            mainHeader
                .frame(height: 64)
            featureStrip
                .frame(height: 32)
            airportInformationRow
                .frame(height: 104)
            fiveDayOverview
                .frame(height: 190, alignment: .top)
            oneWayFlightSection
                .frame(height: 224, alignment: .top)
            airportWeatherSection
                .frame(height: 116, alignment: .top)
            intermediateStopSection
                .frame(height: 72, alignment: .top)
            charterCalculationSection
                .frame(height: 142, alignment: .top)
            Spacer(minLength: 0)
            bottomMenuBar
                .frame(height: 54)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var mainHeader: some View {
        ZStack {
            HStack(alignment: .center) {
                Button {
                    showsAirportPicker = true
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(destination.name.uppercased())
                            .font(.system(size: 27, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.dashboardNavy)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                        HStack(spacing: 7) {
                            Text(countryFlag(destination.countryCode))
                            Text("·  \(destination.icao)  ·  HÖHE \(destination.elevationFeet.formatted()) FT")
                            Image(systemName: "chevron.down")
                                .font(.caption.bold())
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.dashboardNavy)
                    }
                    .frame(width: 315, alignment: .leading)
                    .clipped()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

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
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 0) {
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
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                SectionTitle(title: "FLUGPLANUNG", systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Text("ABFLUG")
                        .font(.caption.bold())
                        .foregroundStyle(Color.dashboardNavy)
                    DatePicker("Datum", selection: $outboundDeparture, displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 120)
                    DatePicker("Startzeit", selection: $outboundDeparture, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 88)
                }

                HStack {
                    Spacer()
                    Text("FLUGHÖHE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Picker("Flughöhe", selection: $selectedAltitudeFeet) {
                        ForEach([1_500, 2_500, 3_500, 4_500, 5_000, 7_000, 9_000], id: \.self) { altitude in
                            Text(dashboardAltitudeLabel(altitude)).tag(altitude)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.caption.bold().monospacedDigit())
                    .tint(Color.dashboardBlue)
                    .frame(width: 112)
                }
            }
            .frame(height: 30)
            EditableFlightLegCard(
                airports: airports,
                departureICAO: $flightDepartureICAO,
                arrivalICAO: $flightArrivalICAO,
                departure: $outboundDeparture,
                durationMinutes: routeMinutes,
                distanceNM: routeDistanceNM,
                selectedAltitudeFeet: $selectedAltitudeFeet,
                bestLevelFeet: 7_000,
                departureAirport: flightDepartureAirport,
                arrivalAirport: flightArrivalAirport,
                onSwap: {
                    let previousDeparture = flightDepartureICAO
                    flightDepartureICAO = flightArrivalICAO
                    flightArrivalICAO = previousDeparture
                },
                onArrivalSelected: { airport in
                    destinationICAO = airport.icao
                }
            )
            .frame(height: 190)
        }
    }

    private func dashboardAltitudeLabel(_ altitude: Int) -> String {
        altitude < 5_000
            ? "\(altitude.formatted(.number.grouping(.automatic))) ft"
            : String(format: "FL%03d", altitude / 100)
    }

    private var airportWeatherSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionTitle(title: "FLUGPLATZWETTER", systemName: "cloud.sun.rain")
                Spacer()
                Text("VORSCHAUDATEN")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange)
            }
            DashboardCard {
                HStack(spacing: 0) {
                    AirportWeatherColumn(airport: flightDepartureAirport)
                    Divider().frame(height: 68)
                    AirportWeatherColumn(airport: flightArrivalAirport)
                }
            }
        }
    }

    private var intermediateStopSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionTitle(title: "ZWISCHENSTOPPS", systemName: "point.3.connected.trianglepath.dotted")
                Spacer()
                Picker("Anzahl Zwischenstopps", selection: $intermediateStopCount) {
                    Text("0").tag(0)
                    Text("1").tag(1)
                    Text("2").tag(2)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            DashboardCard {
                HStack(spacing: 10) {
                    if intermediateStopCount == 0 {
                        Text("Direktflug ohne Zwischenstopp")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    } else {
                        StopAirportPicker(
                            title: "STOP 1",
                            selection: $intermediateStop1ICAO,
                            airports: airports,
                            excluding: [flightDepartureICAO, flightArrivalICAO, intermediateStop2ICAO]
                        )
                        if intermediateStopCount == 2 {
                            StopAirportPicker(
                                title: "STOP 2",
                                selection: $intermediateStop2ICAO,
                                airports: airports,
                                excluding: [flightDepartureICAO, flightArrivalICAO, intermediateStop1ICAO]
                            )
                        }
                    }
                    Spacer()
                    Text("Strecke \(Int(routeDistanceNM.rounded())) NM")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(Color.dashboardBlue)
                }
            }
        }
    }

    private var charterCalculationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            DashboardCard {
                VStack(spacing: 5) {
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
                }
            }
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
                    options: ["Stephan"]
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

    private var options: [Airport] {
        airports
            .filter { airport in
                !excluding.contains(airport.icao)
                    && (airport.isTechStop || airport.runwayLengthMeters != nil)
            }
            .sorted { $0.icao < $1.icao }
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Picker(title, selection: $selection) {
                Text("Virtuell · Modellroute").tag("")
                ForEach(options) { airport in
                    Text("\(airport.icao) · \(airport.name)").tag(airport.icao)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Color.dashboardBlue)
            .frame(width: 190, alignment: .leading)
        }
    }
}

private struct CharterValueBox: View {
    let value: String
    var accent: Color = Color.dashboardNavy

    var body: some View {
        Text(value)
            .font(.headline.bold().monospacedDigit())
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity, minHeight: 46)
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
    let distanceNM: Double
    @Binding var selectedAltitudeFeet: Int
    let bestLevelFeet: Int
    let departureAirport: Airport
    let arrivalAirport: Airport
    let onSwap: () -> Void
    let onArrivalSelected: (Airport) -> Void

    private var arrival: Date {
        departure.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    private var routeWind: (title: String, value: String, color: Color) {
        let weather = DashboardWeatherPreview.snapshot(for: arrivalAirport)
        let course = FlightGeometry.initialBearing(from: departureAirport, to: arrivalAirport)
        let difference = (weather.windDirectionDegrees - course) * .pi / 180
        let component = weather.windSpeedKnots * cos(difference)
        if component > 0.5 {
            return ("WIND", "↓ \(Int(component.rounded())) kt", .orange)
        }
        if component < -0.5 {
            return ("WIND", "↑ \(Int(abs(component).rounded())) kt", .green)
        }
        return ("WIND", "→ 0 kt", Color.dashboardBlue)
    }

    var body: some View {
        DashboardCard {
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

                    Button(action: onSwap) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.dashboardBlue, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 36)
                    .accessibilityLabel("Abflug und Ankunft tauschen")

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

                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        UniformFlightMetricBox(
                            title: "ABFLUG",
                            value: departure.formatted(date: .omitted, time: .shortened)
                        )
                        UniformFlightMetricBox(
                            title: "BEST LEVEL",
                            value: altitudeLabel(bestLevelFeet)
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)

                    Color.clear.frame(width: 36, height: 1)

                    HStack(spacing: 6) {
                        UniformFlightMetricBox(
                            title: "ANKUNFT",
                            value: arrival.formatted(date: .omitted, time: .shortened)
                        )
                        UniformFlightMetricBox(
                            title: "BLOCKZEIT",
                            value: "\(durationMinutes / 60):\(String(format: "%02d", durationMinutes % 60))",
                            boxTint: .orange
                        )
                        UniformFlightMetricBox(
                            title: routeWind.title,
                            value: routeWind.value,
                            valueColor: routeWind.color
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                }
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

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
        .background(boxTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(boxTint.opacity(0.65)) }
    }
}

private struct FlightAirportHalf: View {
    let title: String
    @Binding var text: String
    let airports: [Airport]
    let airport: Airport
    let referenceDate: Date
    let onSelect: (Airport) -> Void

    var body: some View {
        HStack(spacing: 7) {
            AirportICAOField(
                title: title,
                text: $text,
                airports: airports,
                referenceDate: referenceDate,
                onSelect: onSelect
            )
            RunwayRecommendationPanel(
                airport: airport,
                weather: DashboardWeatherPreview.snapshot(for: airport)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

private struct RunwayRecommendationPanel: View {
    let airport: Airport
    let weather: DashboardWeatherSnapshot

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

    private var recommendation: (label: String, heading: Double, headwind: Double, crosswind: Double)? {
        runwayHeadings.map { end in
            let difference = shortestAngle(weather.windDirectionDegrees - end.heading) * .pi / 180
            return (
                end.label,
                end.heading,
                weather.windSpeedKnots * cos(difference),
                abs(weather.windSpeedKnots * sin(difference))
            )
        }.max { $0.headwind < $1.headwind }
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
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

                VStack(spacing: 2) {
                    Text("WIND")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(metarWindText)
                        .font(.system(size: 9, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Color.dashboardNavy)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: 60, height: 42)
                .background(windLimitColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(windLimitColor.opacity(0.7)) }
            }

            HStack(spacing: 8) {
                Text(headwindText)
                    .foregroundStyle((recommendation?.headwind ?? 0) >= 0 ? .green : .red)
                Text("→ \(Int((recommendation?.crosswind ?? 0).rounded())) kt")
                    .foregroundStyle(.orange)
            }
            .font(.system(size: 12, weight: .heavy).monospacedDigit())
        }
        .frame(width: 158)
        .accessibilityLabel("Runway \(airport.referenceRunway), bevorzugt \(recommendation?.label ?? "unbekannt")")
    }

    private func runwayLabelOffset(heading: Double) -> CGSize {
        let radians = (heading - 90) * .pi / 180
        return CGSize(width: cos(radians) * 35, height: sin(radians) * 35)
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
            .font(.system(size: active ? 10 : 7, weight: .black).monospacedDigit())
            .foregroundStyle(active ? .white : Color.dashboardNavy)
            .padding(.horizontal, active ? 6 : 4)
            .frame(height: active ? 20 : 15)
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
            HStack(spacing: 0) {
                WeatherMetric(title: "TEMP", value: "\(weather.temperatureCelsius) °C")
                WeatherMetric(title: "SICHT", value: "\(weather.visibilityKilometers) km")
                WeatherMetric(title: "WOLKEN", value: weather.clouds)
                WeatherMetric(title: "BASIS", value: "\(weather.cloudBaseFeet) ft")
                WeatherMetric(title: "QNH", value: "\(weather.pressureHPA)")
                WeatherMetric(title: "DICHTEHÖHE", value: "\(weather.densityAltitudeFeet.formatted()) ft")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

private struct WeatherMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(value)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
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
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                TextField("ICAO", text: $text)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.dashboardBlue)
                    .focused($isFocused)
                    .frame(width: 76)
                    .onChange(of: text) { _, value in
                        let normalized = String(value.uppercased().prefix(4))
                        if normalized != value { text = normalized }
                    }
            }
            Text(selectedAirport?.name ?? "Flugplatz wählen")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.dashboardNavy)
                .lineLimit(1)
            Text(DashboardSolarClock.display(for: selectedAirport, on: referenceDate))
                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 180, alignment: .leading)
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
