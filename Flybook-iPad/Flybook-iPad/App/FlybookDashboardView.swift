import SwiftUI

struct FlybookDashboardView: View {
    let airports: [Airport]
    private let fuelCatalog = AirportFuelCatalog.load()

    @AppStorage("ipad.activeBase") private var activeBase = "LSV Mainz"
    @AppStorage("ipad.activeAircraft") private var activeAircraft = "DEZHS"
    @AppStorage("ipad.activeUser") private var activeUser = "Stephan"
    @AppStorage("ipad.destinationICAO") private var destinationICAO = "EDKA"
    @AppStorage("ipad.unitSystem") private var unitSystem = "EU"

    @State private var outboundDeparture = Date.now.roundedToNextQuarterHour
    @State private var returnDeparture = Date.now
        .addingTimeInterval(4 * 60 * 60)
        .roundedToNextQuarterHour
    @State private var showsAirportPicker = false
    @State private var showsMigrationNotice = false
    @State private var includeLandingFees = false

    private var homeAirport: Airport {
        airports.first(where: { $0.icao == "EDFZ" })
            ?? Airport.fallbackEDFZ
    }

    private var destination: Airport {
        airports.first(where: { $0.icao == destinationICAO })
            ?? airports.first(where: { $0.icao == "EDKA" })
            ?? homeAirport
    }

    private var routeDistanceNM: Double {
        FlightGeometry.nauticalMiles(from: homeAirport, to: destination)
    }

    private var routeMinutes: Int {
        max(8, Int((routeDistanceNM / 109 * 60).rounded()) + 8)
    }

    private var destinationAirports: [Airport] {
        airports.filter { $0.icao != "EDFZ" }
    }

    private var destinationFuel: AirportFuelAvailability {
        fuelCatalog.availability(for: destination.icao)
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
    }

    private var fixedDashboard: some View {
        VStack(spacing: 9) {
            mainHeader
                .frame(height: 72)
            airportInformationRow
                .frame(height: 96)
            fiveDayOverview
                .frame(height: 250, alignment: .top)
            oneWayFlightSection
                .frame(height: 190, alignment: .top)
            charterCalculationSection
                .frame(height: 238, alignment: .top)
            Spacer(minLength: 0)
            bottomMenuBar
                .frame(height: 62)
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
        }
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 52)
                FuelStatusCell(title: "AVGAS", status: destinationFuel.avgas)
                Divider().frame(height: 52)
                FuelStatusCell(title: "UL91", status: destinationFuel.ul91)
                Divider().frame(height: 52)
                FuelStatusCell(title: "MOGAS", status: destinationFuel.mogas)
            }
        }
    }

    private var fiveDayOverview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(title: "5-TAGES-WETTER", systemName: "cloud.sun")
                Spacer()
                Text("ICON-SEAMLESS · NOCH NICHT VERBUNDEN")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }

            DashboardCard {
                VStack(spacing: 12) {
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
        }
    }

    private var oneWayFlightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "FLUGPLANUNG · ONEWAY", systemName: "point.topleft.down.to.point.bottomright.curvepath")
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
        }
    }

    private var charterCalculationSection: some View {
        DashboardCard {
            VStack(spacing: 10) {
                HStack {
                    Text("CHARTERKALKULATION")
                        .font(.headline.bold())
                        .foregroundStyle(Color.dashboardNavy)

                    Menu {
                        ForEach(["DEZHS", "DEUKS", "DETIK"], id: \.self) { aircraft in
                            Button(aircraft) { activeAircraft = aircraft }
                        }
                    } label: {
                        Text(activeAircraft)
                            .font(.caption.bold())
                            .foregroundStyle(Color.dashboardBlue)
                    }

                    Spacer()

                    Toggle("Landegebühren", isOn: $includeLandingFees)
                        .font(.caption.bold())
                        .tint(Color.dashboardBlue)
                }

                HStack(spacing: 8) {
                    CharterColumnHeader("BLOCKZEIT")
                    CharterColumnHeader("KRAFTSTOFF")
                    CharterColumnHeader("LANDEGEBÜHR")
                    CharterColumnHeader("CHARTER")
                }

                HStack(spacing: 8) {
                    CharterValueBox(value: charterBlockHours.formatted(.number.precision(.fractionLength(1))) + " h")
                    CharterValueBox(value: "\(charterFuelLiters) L", accent: .green)
                    CharterValueBox(value: includeLandingFees ? "?" : "—")
                    CharterValueBox(value: "\(charterCostEUR) €")
                }

                Divider()

                HStack {
                    Text("GESAMT ONEWAY")
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

    private var color: Color {
        switch status {
        case .available: return .green
        case .unavailable: return .red
        case .check: return .orange
        }
    }

    var body: some View {
        VStack(spacing: 6) {
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.black.opacity(0.09), lineWidth: 1)
            }
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
}

private extension Date {
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
