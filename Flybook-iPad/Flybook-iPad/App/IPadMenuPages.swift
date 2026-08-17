import SwiftUI

enum IPadDashboardPage: String, CaseIterable {
    case home
    case destinationFinder
    case alternates
    case reservations
    case base
    case aircraft
    case setup

    var title: String {
        switch self {
        case .home: return "Hauptseite"
        case .destinationFinder: return "Destination Finder"
        case .alternates: return "Alternates"
        case .reservations: return "Reservierungsplaner"
        case .base: return "Heimatbasis"
        case .aircraft: return "Flugzeuge"
        case .setup: return "Setup"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .destinationFinder: return "airplane.arrival"
        case .alternates: return "signpost.right.and.left"
        case .reservations: return "calendar.badge.clock"
        case .base: return "building.2"
        case .aircraft: return "airplane"
        case .setup: return "gearshape"
        }
    }
}

struct IPadMenuPageView: View {
    let page: IPadDashboardPage
    let airports: [Airport]
    let destination: Airport
    @Binding var selectedDestinationICAO: String
    @Binding var activeBase: String
    @Binding var activeAircraft: String
    @Binding var activeUser: String
    @Binding var plannedDeparture: Date

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label(page.title.uppercased(), systemImage: page.symbol)
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.dashboardNavy)
                Spacer()
                Text("FLYBOOK iOS")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .frame(height: 54)

            Group {
                switch page {
                case .destinationFinder:
                    IPadDestinationFinderPage(
                        airports: airports,
                        selectedDestinationICAO: $selectedDestinationICAO,
                        initialFrom: plannedDeparture
                    )
                case .alternates:
                    IPadAlternatesPage(
                        airports: airports,
                        destination: destination,
                        selectedDestinationICAO: $selectedDestinationICAO,
                        forecastDate: $plannedDeparture
                    )
                case .reservations:
                    IPadReservationsPage(
                        airports: airports,
                        selectedDestinationICAO: $selectedDestinationICAO,
                        plannedDeparture: $plannedDeparture
                    )
                case .base:
                    IPadBasePage(activeBase: $activeBase)
                case .aircraft:
                    IPadAircraftPage(activeAircraft: $activeAircraft)
                case .setup:
                    IPadSetupPage(activeUser: $activeUser)
                case .home:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct MenuCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.black.opacity(0.09), lineWidth: 1)
            }
    }
}

private struct IPadDestinationFinderPage: View {
    let airports: [Airport]
    @Binding var selectedDestinationICAO: String
    @StateObject private var blueSkyWeather = IPadDestinationFinderWeather()
    @State private var search = ""
    @State private var category = "Alle"
    @State private var minimumRunway = 300.0
    @State private var voucherOnly = false
    @State private var requiresBlueSkyCoverage = false
    @State private var minimumBlueSkyCoverage = 12.5
    @State private var blueSkyCoverageScope = IPadBlueSkyCoverageScope.perDay
    @State private var from: Date
    @State private var until: Date
    private let features = AirportFeatureCatalog.load()

    init(
        airports: [Airport],
        selectedDestinationICAO: Binding<String>,
        initialFrom: Date
    ) {
        self.airports = airports
        _selectedDestinationICAO = selectedDestinationICAO
        _from = State(initialValue: initialFrom)
        _until = State(
            initialValue: initialFrom.addingTimeInterval(48 * 60 * 60)
        )
    }

    private var results: [Airport] {
        airports.filter { airport in
            let queryMatches = search.isEmpty
                || airport.icao.localizedCaseInsensitiveContains(search)
                || airport.name.localizedCaseInsensitiveContains(search)
            let runwayMatches = Double(airport.runwayLengthMeters ?? 0) >= minimumRunway
            let featureMatches = category == "Alle"
                || features.features(for: airport.icao).contains { $0.title == category }
            let blueSkyMatches = !requiresBlueSkyCoverage
                || blueSkyWeather.matches(
                    airport: airport,
                    from: from,
                    until: until,
                    minimumCoverage: minimumBlueSkyCoverage / 100,
                    scope: blueSkyCoverageScope
                )
            return queryMatches && runwayMatches && featureMatches
                && (!voucherOnly || IPadLandingVoucherBook.includes(airport.icao))
                && blueSkyMatches
        }
        .sorted { lhs, rhs in
            (lhs.distanceFromEDFZ ?? .max, lhs.icao) < (rhs.distanceFromEDFZ ?? .max, rhs.icao)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            MenuCard {
                VStack(spacing: 9) {
                    HStack(spacing: 12) {
                        TextField("ICAO oder Flugplatz", text: $search)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 210)
                        Picker("Kategorie", selection: $category) {
                            ForEach(["Alle", "TechStop", "Frühstück", "Stadt", "Meer", "See / Natur", "Berge"], id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        .frame(width: 150)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MINIMUM RUNWAY  \(Int(minimumRunway)) m")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Slider(value: $minimumRunway, in: 300...1_000, step: 100)
                        }
                        Toggle("Gutschein", isOn: $voucherOnly)
                            .toggleStyle(.button)
                            .tint(Color.dashboardBlue)
                        Text("\(results.count) Ziele")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    HStack(spacing: 10) {
                        Toggle("Blaue-Himmel-Quote", isOn: $requiresBlueSkyCoverage)
                            .toggleStyle(.button)
                            .tint(Color.dashboardBlue)
                        Slider(
                            value: $minimumBlueSkyCoverage,
                            in: 12.5...100,
                            step: 12.5
                        )
                        .frame(width: 125)
                        .disabled(!requiresBlueSkyCoverage)
                        Text(blueSkyPercentage)
                            .font(.caption.monospacedDigit().bold())
                            .frame(width: 45, alignment: .trailing)
                        Picker("Auswertung", selection: $blueSkyCoverageScope) {
                            ForEach(IPadBlueSkyCoverageScope.allCases) { scope in
                                Text(scope.rawValue).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 245)
                        .disabled(!requiresBlueSkyCoverage)
                        Spacer()
                        if blueSkyWeather.isLoading {
                            ProgressView().controlSize(.small)
                        }
                    }
                    HStack(spacing: 10) {
                        Text("ZEITRAUM")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        DatePicker(
                            "Von",
                            selection: $from,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .frame(width: 130)
                        DatePicker(
                            "Bis",
                            selection: $until,
                            in: from...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .frame(width: 130)
                        Spacer()
                    }
                    if requiresBlueSkyCoverage,
                       let errorMessage = blueSkyWeather.errorMessage
                    {
                        Text(errorMessage)
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: requiresBlueSkyCoverage ? 175 : 156)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Array(results.prefix(12))) { airport in
                    Button {
                        selectedDestinationICAO = airport.icao
                    } label: {
                        DestinationResultCard(
                            airport: airport,
                            featureItems: Array(features.features(for: airport.icao).prefix(3)),
                            selected: selectedDestinationICAO == airport.icao
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task(id: weatherRequestKey) {
            guard requiresBlueSkyCoverage else { return }
            await blueSkyWeather.load(
                airports: airports,
                from: from,
                until: until
            )
        }
    }

    private var blueSkyPercentage: String {
        minimumBlueSkyCoverage.rounded() == minimumBlueSkyCoverage
            ? "\(Int(minimumBlueSkyCoverage)) %"
            : String(format: "%.1f %%", minimumBlueSkyCoverage)
    }

    private var weatherRequestKey: String {
        guard requiresBlueSkyCoverage else { return "inactive" }
        return "\(from.timeIntervalSince1970)-\(until.timeIntervalSince1970)"
    }
}

private enum IPadLandingVoucherBook {
    // Identischer, redaktionell geprüfter Offline-Stand wie im Hauptprojekt.
    private static let participants2026: Set<String> = [
        "EDGA", "EDKD", "EDQF", "EDLA", "EDBA", "EDOA", "EDVA", "EDRA",
        "EDFD", "EDVW", "EDRS", "EDXL", "EDNC", "EDMB", "EDMC", "EDOE",
        "EDVE", "EDGB", "EDKO", "EDQE", "EDAP", "ETND", "EDRW", "LOAB",
        "EDPM", "EDAV", "EDFY", "LOKF", "EDXF", "LOKH", "EDOT", "EDMH",
        "EDXB", "EDVH", "EDRH", "EDVI", "EDMI", "EDBJ", "EDLC", "EDWK",
        "EDQK", "EDBK", "EDWF", "EDLM", "EDFM", "EDFN", "EDKZ", "EDAX",
        "EDHM", "LOGO", "ETHN", "EDNM", "EDXN", "EDWH", "EDGP", "EDCV",
        "EDQZ", "EDTP", "EKRD", "EDNR", "EDOD", "EDXE", "LOLK", "EKRS",
        "EDVR", "EDXQ", "EDXC", "EDAZ", "EDRO", "EDBS", "EDAY", "EDQS",
        "EHTX", "EDRM", "EDNT", "EDVU", "EDUY", "EDWM", "LOAN", "EDBI"
    ]

    static func includes(_ icao: String, on date: Date = .now) -> Bool {
        Calendar.current.component(.year, from: date) == 2026
            && participants2026.contains(icao.uppercased())
    }
}

private struct DestinationResultCard: View {
    let airport: Airport
    let featureItems: [AirportFeature]
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(airport.icao)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color.dashboardBlue)
                Spacer()
                if airport.isTechStop {
                    Image(systemName: "fuelpump.fill").foregroundStyle(.green)
                }
            }
            Text(airport.name)
                .font(.headline.bold())
                .foregroundStyle(Color.dashboardNavy)
                .lineLimit(1)
            Text(airport.runwayDisplay)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(featureItems) { feature in Image(systemName: feature.symbol) }
            }
            .foregroundStyle(Color.dashboardBlue)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 135, alignment: .topLeading)
        .background(selected ? Color.dashboardBlue.opacity(0.14) : Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(selected ? Color.dashboardBlue : Color.black.opacity(0.09), lineWidth: 1.3)
        }
    }
}

private struct IPadAlternatesPage: View {
    let airports: [Airport]
    let destination: Airport
    @Binding var selectedDestinationICAO: String
    @Binding var forecastDate: Date
    @State private var minimum = "MVFR"
    @State private var minimumRunway = 300.0
    @State private var openingHours = "JA"

    private var alternates: [Airport] {
        airports.filter {
            $0.icao != destination.icao
                && Double($0.runwayLengthMeters ?? 0) >= minimumRunway
        }
        .sorted {
            FlightGeometry.nauticalMiles(from: destination, to: $0)
                < FlightGeometry.nauticalMiles(from: destination, to: $1)
        }
        .prefix(4)
        .map { $0 }
    }

    var body: some View {
        VStack(spacing: 10) {
            MenuCard {
                VStack(spacing: 10) {
                    HStack(spacing: 14) {
                        DatePicker("Prognose", selection: $forecastDate, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                        Button("Geplante Zeit") {}
                            .buttonStyle(.borderedProminent)
                        Button("Jetzt") { forecastDate = .now }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button("Homebase") { selectedDestinationICAO = "EDFZ" }
                            .buttonStyle(.bordered)
                        Button("Update") {}
                            .buttonStyle(.borderedProminent)
                    }
                    HStack(spacing: 14) {
                        Picker("Minimums", selection: $minimum) {
                            ForEach(["OFF", "MVFR", "VFR"], id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("MINIMUM RUNWAY  \(Int(minimumRunway)) m").font(.caption2.bold())
                            Slider(value: $minimumRunway, in: 300...1_000, step: 100)
                        }
                        Picker("Öffnungszeiten", selection: $openingHours) {
                            ForEach(["NEIN", "JA", "BESTÄTIGT"], id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }
                }
            }
            .frame(height: 126)

            HStack(spacing: 9) {
                AlternateCard(airport: destination, origin: destination, isDestination: true)
                ForEach(alternates) { airport in
                    AlternateCard(airport: airport, origin: destination, isDestination: false)
                }
            }
            .frame(height: 690)
        }
    }
}

private struct AlternateCard: View {
    let airport: Airport
    let origin: Airport
    let isDestination: Bool

    var body: some View {
        VStack(spacing: 10) {
            if isDestination {
                Text("ZIEL")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.dashboardBlue, in: Capsule())
            }
            Text(airport.icao).font(.system(size: 23, weight: .heavy)).foregroundStyle(Color.dashboardBlue)
            Text(airport.name).font(.headline.bold()).foregroundStyle(Color.dashboardNavy).lineLimit(2)
            if !isDestination {
                Text(distanceText).font(.caption.bold().monospacedDigit()).foregroundStyle(.secondary)
            }
            Divider()
            Image(systemName: "road.lanes")
                .font(.system(size: 55, weight: .bold))
                .foregroundStyle(Color.dashboardNavy)
                .rotationEffect(
                    .degrees((Double(airport.referenceRunway.prefix(2)) ?? 0) * 10 - 90)
                )
                .frame(height: 115)
            Text(airport.runwayDisplay).font(.headline.bold()).foregroundStyle(Color.dashboardNavy)
            Text(airport.runwaySurface).font(.caption.bold()).foregroundStyle(Color.dashboardBlue)
            Spacer()
            Text("Wetter wird zur Prognosezeit geladen")
                .font(.caption2.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Öffnungszeit unklar")
                .font(.caption.bold())
                .foregroundStyle(.orange)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.09)) }
    }

    private var distanceText: String {
        let distance = FlightGeometry.nauticalMiles(from: origin, to: airport)
        let bearing = FlightGeometry.initialBearing(from: origin, to: airport)
        return "\(Int(distance.rounded())) NM · \(Int(bearing.rounded()))°"
    }
}

private struct IPadReservationsPage: View {
    let airports: [Airport]
    @Binding var selectedDestinationICAO: String
    @Binding var plannedDeparture: Date
    @AppStorage("ipad.reservation.title") private var reservationTitle = ""
    @AppStorage("ipad.reservation.confirmed") private var confirmed = false

    var body: some View {
        HStack(spacing: 12) {
            MenuCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text("NEUE RESERVIERUNG").font(.headline.bold()).foregroundStyle(Color.dashboardNavy)
                    Picker("Flugplatz", selection: $selectedDestinationICAO) {
                        ForEach(airports) { Text("\($0.icao) · \($0.name)").tag($0.icao) }
                    }
                    DatePicker("Datum und Uhrzeit", selection: $plannedDeparture)
                    TextField("Reservierungsnummer / Kontakt", text: $reservationTitle)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Bestätigt", isOn: $confirmed).tint(Color.dashboardBlue)
                    Button("In Flugplanung übernehmen") {}
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
            }
            MenuCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text("AKTUELLE PLANUNG").font(.headline.bold()).foregroundStyle(Color.dashboardNavy)
                    ReservationRow(title: "Flugplatz", value: selectedDestinationICAO)
                    ReservationRow(title: "Termin", value: plannedDeparture.formatted(date: .abbreviated, time: .shortened))
                    ReservationRow(title: "Referenz", value: reservationTitle.isEmpty ? "—" : reservationTitle)
                    ReservationRow(title: "Status", value: confirmed ? "BESTÄTIGT" : "OFFEN", accent: confirmed ? .green : .orange)
                    Divider()
                    Text("Reservierungen bleiben lokal auf diesem Gerät gespeichert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }
}

private struct ReservationRow: View {
    let title: String
    let value: String
    var accent: Color = Color.dashboardNavy
    var body: some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).foregroundStyle(accent).bold() }
    }
}

private struct IPadBasePage: View {
    @Binding var activeBase: String
    var body: some View {
        MenuCard {
            VStack(alignment: .leading, spacing: 20) {
                Text("AKTIVE HEIMATBASIS").font(.headline.bold()).foregroundStyle(Color.dashboardNavy)
                Picker("Basis", selection: $activeBase) {
                    Text("LSV Mainz · EDFZ").tag("LSV Mainz")
                }
                .pickerStyle(.segmented)
                Label("EDFZ · Mainz-Finthen", systemImage: "house.fill")
                    .font(.title2.bold()).foregroundStyle(Color.dashboardBlue)
                Text("Die Heimatbasis wird für Flugplanung, Referenzpreise, Homebase-Alternates und Standardrouten verwendet.")
                    .font(.body).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

private struct IPadAircraftPage: View {
    @Binding var activeAircraft: String
    private let aircraft = ["DEZHS", "DEUKS", "DETIK"]
    var body: some View {
        VStack(spacing: 12) {
            Picker("Aktives Flugzeug", selection: $activeAircraft) {
                ForEach(aircraft, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(5)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            HStack(spacing: 12) {
                ForEach(aircraft, id: \.self) { registration in
                    Button { activeAircraft = registration } label: {
                        AircraftSelectionCard(
                            registration: registration,
                            selected: activeAircraft == registration
                        )
                    }.buttonStyle(.plain)
                }
            }
            Spacer()
        }
    }
}

private struct AircraftSelectionCard: View {
    let registration: String
    let selected: Bool

    private var profile: IPadAircraftPerformance {
        IPadAircraftPerformanceStore.profile(named: registration)
    }
    private var tasText: String {
        let value = profile.cruise.tasKnots(at: 5_000) ?? profile.fallbackCruiseKnots
        return "\(Int(value.rounded())) kt"
    }
    private var fuelText: String {
        let value = profile.cruise.fuelLitersPerHour(at: 5_000) ?? profile.fallbackFuelLitersPerHour
        return "\(Int(value.rounded())) L/h"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Image(systemName: "airplane").font(.system(size: 46)).foregroundStyle(Color.dashboardBlue)
            Text(registration).font(.system(size: 28, weight: .heavy)).foregroundStyle(Color.dashboardNavy)
            ReservationRow(title: "65 % TAS", value: tasText)
            ReservationRow(title: "Verbrauch", value: fuelText)
            ReservationRow(title: "Charter", value: "\(Int(profile.hourlyRateEUR.rounded())) €/h")
            Spacer()
            Text(selected ? "AKTIV" : "AUSWÄHLEN")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(selected ? .green : Color.dashboardBlue)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(selected ? Color.green : Color.black.opacity(0.09), lineWidth: 1.5)
        }
    }
}

private struct IPadSetupPage: View {
    @Binding var activeUser: String
    @AppStorage("ipad.unitSystem") private var unitSystem = "EU"
    @AppStorage("ipad.fofEnabled") private var fofEnabled = false
    @AppStorage("ipad.voucherBookEnabled") private var voucherBookEnabled = false
    @AppStorage("ipad.offlineCache") private var offlineCache = true

    var body: some View {
        HStack(spacing: 12) {
            MenuCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text("PROFIL UND EINHEITEN").font(.headline.bold()).foregroundStyle(Color.dashboardNavy)
                    Picker("Nutzer", selection: $activeUser) {
                        Text("Stephan").tag("Stephan")
                        Text("Maria").tag("Maria")
                    }.pickerStyle(.segmented)
                    Picker("Einheiten", selection: $unitSystem) {
                        Text("🇪🇺").tag("EU")
                        Text("🇺🇸").tag("US")
                    }.pickerStyle(.segmented)
                    Spacer()
                }
            }
            MenuCard {
                VStack(alignment: .leading, spacing: 20) {
                    Text("FLUGBETRIEB").font(.headline.bold()).foregroundStyle(Color.dashboardNavy)
                    Toggle("Fliegen ohne Flugleiter (EDFZ)", isOn: $fofEnabled)
                    Toggle("Landegutscheinheft", isOn: $voucherBookEnabled)
                    Toggle("Wettercache für Offlinebetrieb", isOn: $offlineCache)
                    Divider()
                    Label("ICON-Seamless zuerst, weitere ICON-Zugänge als Reserve, danach unabhängiger Fallback", systemImage: "cloud.sun.fill")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .tint(Color.dashboardBlue)
            }
        }
    }
}
