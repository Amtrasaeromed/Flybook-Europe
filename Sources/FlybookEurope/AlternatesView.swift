import SwiftUI

struct AlternateAirport: Identifiable {
    var id: String { reference.icao }
    let reference: AirportReference
    let runwayLengthMeters: Int
    var isDestination = false
    var primaryBadgeText = "ZIEL"
    var distanceFromDestinationNM: Double? = nil
    var bearingFromDestinationDegrees: Double? = nil
    var flightTimeMinutes: Int? = nil
    var estimatedFuelLiters: Double? = nil
    var openingAssessment: AirportOpeningAssessment? = nil
    var operatingStatus: AirportOperatingStatus? = nil

    var relativePositionDescription: String? {
        guard let distanceFromDestinationNM,
              let bearingFromDestinationDegrees else { return nil }
        let flightTime = flightTimeMinutes.map {
            " · \(FlightMath.duration($0)) h"
        } ?? ""
        return String(
            format: "%.0f NM%@ · %03.0f° %@",
            distanceFromDestinationNM,
            flightTime,
            bearingFromDestinationDegrees,
            Self.compassDirection(for: bearingFromDestinationDegrees)
        )
    }

    private static func compassDirection(for bearing: Double) -> String {
        let directions = [
            "N", "NE", "E", "SE", "S", "SW", "W", "NW"
        ]
        let normalized = WindMath.normalized(bearing)
        let index = Int((normalized + 22.5) / 45.0) % directions.count
        return directions[index]
    }
}

extension AlternateAirport {
    static let edfzStandardICAOs = ["EDFE", "EDFM", "EDRK", "EDRY"]

    func assessingOpeningHours(
        at forecastTime: Date,
        flyingWithoutFlightDirector: Bool,
        homeAirportICAO: String
    ) -> AlternateAirport {
        var assessed = self
        assessed.operatingStatus = AirportOperatingHoursEvaluator.status(
            airport: reference,
            at: forecastTime,
            operation: .arrival,
            flyingWithoutFlightDirector: flyingWithoutFlightDirector,
            homeAirportICAO: homeAirportICAO
        )
        assessed.openingAssessment =
            AirportOperatingHoursEvaluator.openingAssessment(
                airport: reference,
                at: forecastTime,
                flyingWithoutFlightDirector: flyingWithoutFlightDirector,
                homeAirportICAO: homeAirportICAO
            )
        return assessed
    }

    static func primaryAirport(
        for destination: Destination
    ) -> AlternateAirport? {
        if let latitude = destination.latitude,
           let longitude = destination.longitude {
            return AlternateAirport(
                reference: AirportReference(
                    icao: destination.icao,
                    name: destination.name,
                    latitude: latitude,
                    longitude: longitude,
                    elevationFeet: destination.elevationFeet,
                    timeZone: DestinationTimeZone.value(
                        for: destination,
                        weatherTimeZone: nil
                    ),
                    referenceRunway: destination.referenceRunway
                ),
                runwayLengthMeters: destination.runwayM,
                isDestination: true
            )
        }
        return nil
    }

    static func edfzPrimaryAirport() -> AlternateAirport {
        AlternateAirport(
            reference: .edfz,
            runwayLengthMeters: 1000,
            isDestination: true,
            primaryBadgeText: "HOMEBASE"
        )
    }

    static func homebasePrimaryAirport(
        icao rawICAO: String,
        availableDestinations: [Destination]
    ) -> AlternateAirport? {
        let icao = rawICAO.uppercased()
        if icao == "EDFZ" { return edfzPrimaryAirport() }
        guard let destination = availableDestinations.first(where: {
            $0.icao == icao
        }), var airport = primaryAirport(for: destination) else { return nil }
        airport.primaryBadgeText = "HOMEBASE"
        return airport
    }

    static func candidates(
        from primaryAirport: AlternateAirport,
        availableDestinations: [Destination],
        cruiseSpeedKnots: Double,
        fuelConsumptionLitersPerHour: Double,
        preferredICAOs: [String] = []
    ) -> [AlternateAirport] {
        let preferredOrder = Dictionary(
            uniqueKeysWithValues: preferredICAOs.enumerated().map {
                ($0.element, $0.offset)
            }
        )

        let result: [AlternateAirport] = availableDestinations.compactMap {
            destination -> AlternateAirport? in
            guard destination.icao != primaryAirport.id,
                  let latitude = destination.latitude,
                  let longitude = destination.longitude else { return nil }
            let reference = AirportReference(
                icao: destination.icao,
                name: destination.name,
                latitude: latitude,
                longitude: longitude,
                elevationFeet: destination.elevationFeet,
                timeZone: DestinationTimeZone.value(
                    for: destination,
                    weatherTimeZone: nil
                ),
                referenceRunway: destination.referenceRunway
            )
            return makeCandidate(
                reference: reference,
                runwayLengthMeters: destination.runwayM,
                primaryAirport: primaryAirport,
                cruiseSpeedKnots: cruiseSpeedKnots,
                fuelConsumptionLitersPerHour:
                    fuelConsumptionLitersPerHour
            )
        }

        return result.sorted { lhs, rhs in
            let lhsPreferred = preferredOrder[lhs.id] ?? Int.max
            let rhsPreferred = preferredOrder[rhs.id] ?? Int.max
            if lhsPreferred != rhsPreferred {
                return lhsPreferred < rhsPreferred
            }
            return (lhs.distanceFromDestinationNM ?? .greatestFiniteMagnitude)
                < (rhs.distanceFromDestinationNM ?? .greatestFiniteMagnitude)
        }
    }

    private static func makeCandidate(
        reference: AirportReference,
        runwayLengthMeters: Int,
        primaryAirport: AlternateAirport,
        cruiseSpeedKnots: Double,
        fuelConsumptionLitersPerHour: Double
    ) -> AlternateAirport {
        let distance = AirportDistance.nauticalMiles(
            from: primaryAirport.reference,
            to: reference
        )
        return AlternateAirport(
            reference: reference,
            runwayLengthMeters: runwayLengthMeters,
            distanceFromDestinationNM: distance,
            bearingFromDestinationDegrees: WindMath.initialBearing(
                latitude1: primaryAirport.reference.latitude,
                longitude1: primaryAirport.reference.longitude,
                latitude2: reference.latitude,
                longitude2: reference.longitude
            ),
            flightTimeMinutes: max(
                1,
                Int((distance / max(1, cruiseSpeedKnots) * 60).rounded())
            ),
            estimatedFuelLiters:
                distance / max(1, cruiseSpeedKnots)
                * max(0, fuelConsumptionLitersPerHour)
        )
    }

    static func nearestAirports(
        for destination: Destination,
        availableDestinations: [Destination],
        cruiseSpeedKnots: Double,
        fuelConsumptionLitersPerHour: Double
    ) -> [AlternateAirport] {
        guard let primary = primaryAirport(for: destination) else { return [] }
        return [primary] + Array(candidates(
            from: primary,
            availableDestinations: availableDestinations,
            cruiseSpeedKnots: cruiseSpeedKnots,
            fuelConsumptionLitersPerHour:
                fuelConsumptionLitersPerHour
        ).prefix(4))
    }
}

enum AlternateWeatherMinimum: String, CaseIterable, Identifiable {
    case off = "OFF"
    case mvfr = "MVFR"
    case vfr = "VFR"

    var id: String { rawValue }

    func includes(_ category: FlightCategory?) -> Bool {
        switch self {
        case .off:
            return true
        case .mvfr:
            guard let category, category != .unavailable else { return false }
            return category == .vfr || category == .mvfr
        case .vfr:
            guard let category, category != .unavailable else { return false }
            return category == .vfr
        }
    }
}

enum AlternateOpeningHoursFilter: String, CaseIterable, Identifiable {
    case off = "NEIN"
    case consider = "JA"
    case confirmed = "BESTÄTIGT"

    var id: String { rawValue }

    func includes(_ assessment: AirportOpeningAssessment) -> Bool {
        switch self {
        case .off:
            return true
        case .consider:
            return assessment != .confirmedClosed
        case .confirmed:
            return assessment == .confirmedOpen
        }
    }
}

enum AlternateFuelDisplay {
    static func roundedUpEvenQuantity(
        liters: Double,
        unit: FuelDisplayUnit
    ) -> Int {
        let displayed = max(0, unit.fromLiters(liters))
        return Int(ceil(displayed / 2) * 2)
    }
}

extension Notification.Name {
    static let alternateWeatherDidRefresh = Notification.Name(
        "de.flybook.europe.alternate-weather-did-refresh"
    )
}

enum AlternateWeatherUpdater {
    static func refresh(
        airports: [AlternateAirport],
        forceRefresh: Bool
    ) async {
        let forecastTime = Date()
        await withTaskGroup(of: Void.self) { group in
            for airport in airports {
                group.addTask {
                    _ = try? await EDFZWeatherService.shared.forecast(
                        plannedDate: forecastTime,
                        airport: airport.reference,
                        forceRefresh: forceRefresh
                    )
                }
            }
        }
        await MainActor.run {
            NotificationCenter.default.post(
                name: .alternateWeatherDidRefresh,
                object: nil
            )
        }
    }
}

struct AlternatesView: View {
    let destination: Destination
    let availableDestinations: [Destination]
    let plannedMainDestinationArrival: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var forecastTime = Date()
    @State private var isRefreshing = false
    @State private var weatherMinimum: AlternateWeatherMinimum = .mvfr
    @State private var minimumRunwayLengthMeters = 300.0
    @State private var openingHoursFilter = AlternateOpeningHoursFilter.consider
    @State private var usesHomebase = false
    @State private var selectedAlternates: [AlternateAirport] = []
    @State private var isSearchingAlternates = false
    @State private var searchRevision = UUID()
    @State private var activeSearchRunID = UUID()

    @AppStorage(AircraftSettingsKey.selectedAircraft)
    private var selectedAircraftRaw = AircraftType.a211.rawValue
    @AppStorage(BaseSettingsKey.activeBase)
    private var activeBaseRaw = FlybookBase.lsvMainz.rawValue

    private var airports: [AlternateAirport] {
        guard let primaryAirport else { return [] }
        let assessedPrimary = primaryAirport.assessingOpeningHours(
            at: forecastTime,
            flyingWithoutFlightDirector:
                activeBaseProfile.flyingWithoutFlightDirectorEnabled,
            homeAirportICAO: activeBaseProfile.homeAirportICAO
        )
        return [assessedPrimary] + selectedAlternates
    }

    private var primaryAirport: AlternateAirport? {
        usesHomebase
            ? homebasePrimaryAirport
            : AlternateAirport.primaryAirport(for: destination)
    }

    private var activeBase: FlybookBase {
        FlybookBase(rawValue: activeBaseRaw) ?? .lsvMainz
    }

    private var homebaseICAO: String {
        BaseProfileStore.profile(for: activeBase).homeAirportICAO.uppercased()
    }

    private var activeBaseProfile: BaseProfile {
        BaseProfileStore.profile(for: activeBase)
    }

    private var homebasePrimaryAirport: AlternateAirport? {
        AlternateAirport.homebasePrimaryAirport(
            icao: homebaseICAO,
            availableDestinations: availableDestinations
        )
    }

    private var selectedAircraft: AircraftType {
        AircraftType(rawValue: selectedAircraftRaw) ?? .a211
    }

    private var sixtyFivePercentCruisePerformance: CruisePerformance {
        AircraftProfileStore.cruisePerformance(
            for: selectedAircraft,
            powerPercent: 65
        )
    }

    private var cruiseSpeedAt1500FeetKnots: Double {
        sixtyFivePercentCruisePerformance
            .tasKnots(atPressureAltitudeFeet: 1500)
            ?? selectedAircraft.defaultCruiseGroundSpeedKnots
    }

    private var fuelConsumptionAt1500FeetLitersPerHour: Double {
        sixtyFivePercentCruisePerformance
            .fuelConsumptionPerHour(atPressureAltitudeFeet: 1500)
            ?? selectedAircraft.defaultFuelConsumptionPerHour
    }

    private var candidateAirports: [AlternateAirport] {
        guard let primaryAirport else { return [] }
        return AlternateAirport.candidates(
            from: primaryAirport,
            availableDestinations: availableDestinations,
            cruiseSpeedKnots: cruiseSpeedAt1500FeetKnots,
            fuelConsumptionLitersPerHour:
                fuelConsumptionAt1500FeetLitersPerHour,
            preferredICAOs:
                usesHomebase && homebaseICAO == "EDFZ"
                    ? AlternateAirport.edfzStandardICAOs
                    : []
        )
    }

    private var visibleAlternateCount: Int {
        selectedAlternates.count
    }

    private var alternateSearchID: String {
        [
            primaryAirport?.id ?? "none",
            String(forecastTime.timeIntervalSinceReferenceDate),
            weatherMinimum.rawValue,
            String(Int(minimumRunwayLengthMeters)),
            openingHoursFilter.rawValue,
            selectedAircraftRaw,
            searchRevision.uuidString
        ].joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ALTERNATES")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)
                    Text(alternatesSubtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FlybookColor.muted)
                }

                Spacer()

                Button {
                    usesHomebase.toggle()
                    selectedAlternates.removeAll()
                    searchRevision = UUID()
                } label: {
                    Label("Homebase", systemImage: "house.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(
                            usesHomebase ? Color.white : FlybookColor.blue
                        )
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    usesHomebase
                                        ? FlybookColor.blue
                                        : Color.white.opacity(0.82)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(FlybookColor.blue, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .help(
                    usesHomebase
                        ? "Homebase \(homebaseICAO) aktiv · erneut klicken für das aktuelle Ziel"
                        : "Aktuelle Homebase \(homebaseICAO) als ersten Flugplatz auswählen"
                )

                Button {
                    refreshAlternates()
                } label: {
                    HStack(spacing: 7) {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .bold))
                        }
                        Text("Update")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(FlybookColor.blue)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                FlybookColor.navy.opacity(0.35),
                                lineWidth: 2
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
                .help(
                    "Nur die fünf angezeigten Flugplätze ohne Cache "
                    + "aktualisieren"
                )

                Button("Schließen") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PROGNOSEZEIT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(FlybookColor.muted)

                    HStack(alignment: .bottom, spacing: 7) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("DATUM")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(FlybookColor.muted)
                            DatePicker(
                                "Datum",
                                selection: $forecastTime,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .controlSize(.large)
                            .frame(width: 145)
                            .accessibilityIdentifier("alternateForecastDate")
                            .help("Prognosedatum per Tastatur oder Kalender wählen")
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("UHRZEIT")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(FlybookColor.muted)
                            DatePicker(
                                "Uhrzeit",
                                selection: $forecastTime,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .controlSize(.large)
                            .frame(width: 98)
                            .accessibilityIdentifier("alternateForecastTime")
                            .help("Prognosezeit per Tastatur oder Maus einstellen")
                        }
                    }
                    .environment(\.locale, Locale(identifier: "de_DE"))
                    .environment(\.timeZone, forecastTimeZone)

                    Text("Ortszeit \(primaryAirport?.reference.icao ?? destination.icao)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FlybookColor.muted)
                }
                .frame(width: 265, alignment: .leading)

                Button {
                    if let plannedMainDestinationArrival {
                        forecastTime = plannedMainDestinationArrival
                    }
                } label: {
                    Label("Geplante Zeit", systemImage: "airplane.arrival")
                }
                .buttonStyle(.borderedProminent)
                .tint(
                    isPlannedTimeSelected
                        ? FlybookColor.blue
                        : FlybookColor.muted.opacity(0.55)
                )
                .disabled(plannedMainDestinationArrival == nil)
                .help(
                    plannedMainDestinationArrival == nil
                        ? "Noch keine geplante Ankunft aus der Flugplanung verfügbar"
                        : "Prognosezeit auf die geplante Landung am Hauptziel setzen"
                )

                ForEach(ForecastOffset.allCases) { offset in
                    Button(offset.title) {
                        forecastTime = Date().addingTimeInterval(
                            TimeInterval(offset.minutes * 60)
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(
                        isSelected(offset)
                            ? FlybookColor.blue
                            : FlybookColor.muted.opacity(0.55)
                    )
                }

                Spacer()
            }

            filterControls

            HStack(alignment: .top, spacing: 10) {
                ForEach(airports) { airport in
                    AlternateAirportColumn(
                        airport: airport,
                        forecastTime: forecastTime
                    )
                    .frame(width: 219)
                }

                if visibleAlternateCount < 4 {
                    alternateSearchStatus
                }

                Spacer(minLength: 0)
            }
        }
        .padding(22)
        .frame(minWidth: 1180, minHeight: 740)
        .background(FlybookColor.background)
        .task(id: alternateSearchID) {
            await searchAlternates()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .alternateWeatherDidRefresh
            )
        ) { _ in
            searchRevision = UUID()
        }
    }

    private var filterControls: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("MINIMUMS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)

                HStack(spacing: 3) {
                    ForEach(AlternateWeatherMinimum.allCases) { minimum in
                        minimumButton(minimum)
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.white.opacity(0.72))
                )
            }

            Divider()
                .frame(height: 44)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text("MINIMUM RUNWAY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(FlybookColor.muted)
                    Text(minimumRunwayLabel)
                        .font(
                            .system(
                                size: 12,
                                weight: .black,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(FlybookColor.navy)
                }

                RunwayLengthSlider(value: $minimumRunwayLengthMeters)
                .frame(width: 290)
            }

            Divider()
                .frame(height: 44)

            VStack(alignment: .leading, spacing: 5) {
                Text("ÖFFNUNGSZEITEN BEACHTEN")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)

                HStack(spacing: 3) {
                    ForEach(AlternateOpeningHoursFilter.allCases) { filter in
                        openingHoursButton(filter)
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.white.opacity(0.72))
                )
            }

            Spacer()

            Text(
                isSearchingAlternates
                    ? "\(visibleAlternateCount) von 4 · suche …"
                    : "\(visibleAlternateCount) von 4 Alternates"
            )
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(FlybookColor.muted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(FlybookColor.blue.opacity(0.07))
        )
    }

    private func minimumButton(
        _ minimum: AlternateWeatherMinimum
    ) -> some View {
        let color: Color = switch minimum {
        case .off: FlybookColor.muted
        case .mvfr: FlybookColor.blue
        case .vfr: .green
        }
        let isSelected = weatherMinimum == minimum

        return Button {
            weatherMinimum = minimum
        } label: {
            Text(minimum.rawValue)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(isSelected ? Color.white : color)
                .frame(width: 54, height: 25)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? color : color.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .help(minimumHelp(minimum))
    }

    private func minimumHelp(_ minimum: AlternateWeatherMinimum) -> String {
        switch minimum {
        case .off:
            return "Wetterfilter aus · IFR und LIFR ebenfalls anzeigen"
        case .mvfr:
            return "Nur VFR und MVFR anzeigen"
        case .vfr:
            return "Nur VFR anzeigen"
        }
    }

    private func openingHoursButton(
        _ filter: AlternateOpeningHoursFilter
    ) -> some View {
        let isSelected = openingHoursFilter == filter
        let color: Color = switch filter {
        case .off: FlybookColor.muted
        case .consider: FlybookColor.blue
        case .confirmed: .green
        }
        return Button {
            openingHoursFilter = filter
        } label: {
            Text(filter.rawValue)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(isSelected ? Color.white : color)
                .frame(
                    width: filter == .confirmed ? 82 : 48,
                    height: 25
                )
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? color : color.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .help(openingHoursHelp(filter))
    }

    private func openingHoursHelp(
        _ filter: AlternateOpeningHoursFilter
    ) -> String {
        switch filter {
        case .off:
            return "Öffnungszeiten bei der Alternate-Auswahl nicht filtern"
        case .consider:
            return "Sicher geschlossene Plätze entfernen; unklare Öffnungszeiten anzeigen"
        case .confirmed:
            return "Nur Plätze anzeigen, die zur Prognosezeit nachweislich geöffnet sind"
        }
    }

    private var minimumRunwayLabel: String {
        let value = Int(minimumRunwayLengthMeters)
        return value == 1000 ? "1000 m+" : "\(value) m"
    }

    private var alternateSearchStatus: some View {
        VStack(spacing: 8) {
            if isSearchingAlternates {
                ProgressView()
                    .controlSize(.small)
                Text("Suche weitere passende Alternates …")
                    .font(.system(size: 14, weight: .bold))
            } else {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 24, weight: .semibold))
                Text("Nur \(visibleAlternateCount) passende Alternates gefunden")
                    .font(.system(size: 14, weight: .bold))
                Text("Minimums reduzieren oder Runway-Länge verkürzen")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .foregroundStyle(FlybookColor.muted)
        .frame(maxWidth: .infinity, minHeight: 505)
        .background(Color.white.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var forecastTimeZone: TimeZone {
        primaryAirport?.reference.timeZone ?? .current
    }

    private var alternatesSubtitle: String {
        usesHomebase
            ? "Homebase \(homebaseICAO) und vier passende Ausweichflugplätze"
            : "Hauptziel und vier nächste passende Ausweichflugplätze"
    }

    private var isPlannedTimeSelected: Bool {
        guard let plannedMainDestinationArrival else { return false }
        return abs(
            forecastTime.timeIntervalSince(plannedMainDestinationArrival)
        ) < 120
    }

    private func isSelected(_ offset: ForecastOffset) -> Bool {
        let difference = forecastTime.timeIntervalSinceNow / 60
        return abs(difference - Double(offset.minutes)) < 2
    }

    private func refreshAlternates() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await AlternateWeatherUpdater.refresh(
                airports: airports,
                forceRefresh: true
            )
            isRefreshing = false
        }
    }

    @MainActor
    private func searchAlternates() async {
        let runID = UUID()
        activeSearchRunID = runID
        selectedAlternates = []
        isSearchingAlternates = true
        defer {
            if activeSearchRunID == runID {
                isSearchingAlternates = false
            }
        }

        let requestedForecastTime = forecastTime
        let runwayCandidates: [AlternateAirport] = candidateAirports.compactMap {
            candidate -> AlternateAirport? in
            guard candidate.runwayLengthMeters
                    >= Int(minimumRunwayLengthMeters) else { return nil }
            let assessedCandidate = candidate.assessingOpeningHours(
                at: requestedForecastTime,
                flyingWithoutFlightDirector:
                    activeBaseProfile.flyingWithoutFlightDirectorEnabled,
                homeAirportICAO: activeBaseProfile.homeAirportICAO
            )
            let assessment = assessedCandidate.openingAssessment ?? .unclear
            guard openingHoursFilter.includes(assessment) else { return nil }
            return assessedCandidate
        }
        if weatherMinimum == .off {
            selectedAlternates = Array(runwayCandidates.prefix(4))
            return
        }

        var nextIndex = 0
        while selectedAlternates.count < 4,
              nextIndex < runwayCandidates.count {
            guard !Task.isCancelled, activeSearchRunID == runID else { return }
            let missingCount = 4 - selectedAlternates.count
            let upperBound = min(
                runwayCandidates.count,
                nextIndex + missingCount
            )
            let batch = Array(runwayCandidates[nextIndex..<upperBound])
            let results = await withTaskGroup(
                of: (Int, AlternateAirport, FlightCategory?).self,
                returning: [(Int, AlternateAirport, FlightCategory?)].self
            ) { group in
                for (offset, candidate) in batch.enumerated() {
                    group.addTask {
                        let category: FlightCategory?
                        do {
                            let forecast = try await EDFZWeatherService.shared
                                .forecast(
                                    plannedDate: requestedForecastTime,
                                    airport: candidate.reference,
                                    forceRefresh: false
                                )
                            category = forecast.sample(
                                nearestTo: requestedForecastTime
                            )?.category
                        } catch {
                            category = nil
                        }
                        return (offset, candidate, category)
                    }
                }

                var values: [(Int, AlternateAirport, FlightCategory?)] = []
                for await value in group { values.append(value) }
                return values.sorted { $0.0 < $1.0 }
            }

            guard !Task.isCancelled, activeSearchRunID == runID else { return }
            for (_, candidate, category) in results
            where weatherMinimum.includes(category) {
                selectedAlternates.append(candidate)
            }
            nextIndex = upperBound
        }
    }
}

private struct RunwayLengthSlider: View {
    @Binding var value: Double

    private let minimum = 300.0
    private let maximum = 1000.0
    private let step = 100.0

    private var progress: Double {
        (value - minimum) / (maximum - minimum)
    }

    var body: some View {
        GeometryReader { geometry in
            let thumbRadius = 8.0
            let usableWidth = max(1, geometry.size.width - thumbRadius * 2)
            let thumbX = thumbRadius + usableWidth * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(FlybookColor.muted.opacity(0.22))
                    .frame(height: 5)
                    .padding(.horizontal, thumbRadius)

                Capsule()
                    .fill(FlybookColor.blue)
                    .frame(
                        width: max(5, usableWidth * progress),
                        height: 5
                    )
                    .offset(x: thumbRadius)

                ForEach(0...7, id: \.self) { index in
                    Circle()
                        .fill(
                            index <= Int(progress * 7.0 + 0.01)
                                ? FlybookColor.blue
                                : FlybookColor.muted.opacity(0.42)
                        )
                        .frame(width: 4, height: 4)
                        .position(
                            x: thumbRadius
                                + usableWidth * Double(index) / 7.0,
                            y: geometry.size.height / 2
                        )
                }

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                    .overlay(
                        Circle().stroke(FlybookColor.blue, lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    .position(x: thumbX, y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let rawProgress = (
                            gesture.location.x - thumbRadius
                        ) / usableWidth
                        let clamped = min(1, max(0, rawProgress))
                        let rawValue = minimum
                            + clamped * (maximum - minimum)
                        value = (rawValue / step).rounded() * step
                    }
            )
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Minimum Runway")
        .accessibilityValue(
            value == maximum
                ? "1000 Meter oder länger"
                : "\(Int(value)) Meter"
        )
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(maximum, value + step)
            case .decrement:
                value = max(minimum, value - step)
            @unknown default:
                break
            }
        }
    }
}

private enum ForecastOffset: Int, CaseIterable, Identifiable {
    case now = 0
    case thirty = 30
    case sixty = 60
    case ninety = 90

    var id: Int { rawValue }
    var minutes: Int { rawValue }

    var title: String {
        switch self {
        case .now: return "Jetzt"
        case .thirty: return "30 Minuten"
        case .sixty: return "60 Minuten"
        case .ninety: return "90 Minuten"
        }
    }
}

private struct AlternateAirportColumn: View {
    let airport: AlternateAirport
    let forecastTime: Date
    @StateObject private var weatherModel = EDFZWeatherViewModel()
    @AppStorage(CalculationSettingsKey.fuelDisplayUnit)
    private var fuelDisplayUnitRaw = FuelDisplayUnit.liters.rawValue

    private var fuelDisplayUnit: FuelDisplayUnit {
        FuelDisplayUnit(rawValue: fuelDisplayUnitRaw) ?? .liters
    }

    private var sample: EDFZWeatherSample? {
        weatherModel.forecast?.sample(nearestTo: forecastTime)
    }

    private var recommendation: RunwayRecommendation? {
        guard let direction = sample?.windDirectionDegrees,
              let speed = sample?.windSpeedKnots,
              let runway = EDFZRunway.activeRunway(
                for: airport.reference.icao,
                referenceRunway: airport.reference.referenceRunway,
                windFromDegrees: direction,
                speedKnots: speed
              ),
              let components = EDFZRunway.windComponents(
                for: airport.reference.icao,
                runway: runway,
                referenceRunway: airport.reference.referenceRunway,
                windFromDegrees: direction,
                speedKnots: speed,
                gustKnots: sample?.windGustKnots
              )
        else { return nil }
        return RunwayRecommendation(
            runwayLabel: runway,
            headwindKnots: max(0, components.headwindKnots),
            crosswindKnots: components.crosswindKnots,
            crosswindComesFromRight: components.crosswindComesFromRight
        )
    }

    private var crosswindWarning: RunwayCrosswindWarning {
        guard let recommendation,
              let direction = sample?.windDirectionDegrees,
              let speed = sample?.windSpeedKnots else { return .none }
        return EDFZRunway.crosswindWarning(
            for: airport.reference.icao,
            runway: recommendation.runwayLabel,
            referenceRunway: airport.reference.referenceRunway,
            windFromDegrees: direction,
            steadyWindKnots: speed,
            gustKnots: sample?.windGustKnots
        )
    }

    private var windComponentsBackgroundColor: Color {
        guard recommendation != nil else {
            return FlybookColor.blue.opacity(0.04)
        }
        return crosswindWarning.recommendationBackgroundColor
    }

    private var dailyOpeningHours: AirportDailyOpeningHours {
        AirportOperatingHoursEvaluator.dailyOpeningHours(
            airport: airport.reference,
            at: forecastTime
        )
    }

    private var forecastOpeningAssessment: AirportOpeningAssessment {
        airport.openingAssessment
            ?? AirportOperatingHoursEvaluator.openingAssessment(
                airport: airport.reference,
                at: forecastTime
            )
    }

    private var localOpeningHoursText: String {
        if airport.operatingStatus == .flyingWithoutFlightDirector {
            return "Fliegen ohne Flugleiter"
        }
        if forecastOpeningAssessment == .confirmedClosed {
            return "Geschlossen"
        }
        switch dailyOpeningHours {
        case .confirmed(let windows):
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.timeZone = airport.reference.timeZone
            formatter.dateFormat = "HH:mm"
            let intervals = windows.map {
                "\(formatter.string(from: $0.opening))–"
                    + formatter.string(from: $0.closing)
            }
            return "Lokal " + intervals.joined(separator: " / ")
        case .confirmedClosed:
            return "Heute geschlossen"
        case .unclear:
            return "Öffnungszeit unklar"
        }
    }

    private var openingHoursColor: Color {
        if airport.operatingStatus == .flyingWithoutFlightDirector {
            return FlybookColor.blue
        }
        if forecastOpeningAssessment == .confirmedClosed { return .red }
        return switch dailyOpeningHours {
        case .confirmed: FlybookColor.navy
        case .confirmedClosed: .red
        case .unclear: .orange
        }
    }

    private var openingHoursSymbol: String {
        if airport.operatingStatus == .flyingWithoutFlightDirector {
            return "airplane.circle.fill"
        }
        if forecastOpeningAssessment == .confirmedClosed {
            return "xmark.circle.fill"
        }
        return switch dailyOpeningHours {
        case .confirmed: "clock.fill"
        case .confirmedClosed: "xmark.circle.fill"
        case .unclear: "questionmark.circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            airportHeader
                .frame(height: 120)

            Divider()

            runwayWindSection
                .frame(height: 178)

            Divider()

            AlternateWeatherBlock(
                sample: sample,
                isLoading: weatherModel.isLoading,
                errorMessage: weatherModel.errorMessage
            )
            .frame(height: 205)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(FlybookColor.navy.opacity(0.16), lineWidth: 1)
        )
        .task(id: forecastTime) {
            await weatherModel.load(
                plannedDate: forecastTime,
                airport: airport.reference
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .alternateWeatherDidRefresh
            )
        ) { _ in
            Task {
                await weatherModel.load(
                    plannedDate: forecastTime,
                    airport: airport.reference
                )
            }
        }
    }

    private var airportHeader: some View {
        VStack(spacing: 4) {
            if airport.isDestination {
                Text(airport.primaryBadgeText)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(FlybookColor.blue))
            }
            Text(airport.reference.icao)
                .font(.system(size: 19, weight: .bold, design: .monospaced))
                .foregroundStyle(FlybookColor.blue)
            Text(airport.reference.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(FlybookColor.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let relativePosition = airport.relativePositionDescription {
                Text(relativePosition)
                    .font(
                        .system(
                            size: 10,
                            weight: .black,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(FlybookColor.muted)
                    .help("Geschätzte direkte Flugzeit ohne Wind")
            }
            if let estimatedFuelLiters = airport.estimatedFuelLiters {
                Label(
                    fuelDescription(estimatedFuelLiters),
                    systemImage: "fuelpump.fill"
                )
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(FlybookColor.blue)
                .help("Geschätzter direkter Streckenverbrauch")
            }
            Label(localOpeningHoursText, systemImage: openingHoursSymbol)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(openingHoursColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .help("Tagesgültige veröffentlichte Öffnungszeit in Platz-Lokalzeit")
        }
        .padding(.horizontal, 8)
    }

    private func fuelDescription(_ liters: Double) -> String {
        let quantity = AlternateFuelDisplay.roundedUpEvenQuantity(
            liters: liters,
            unit: fuelDisplayUnit
        )
        return "Fuel \(quantity) \(fuelDisplayUnit.symbol)"
    }

    private var runwayWindSection: some View {
        VStack(spacing: 4) {
            Text("\(airport.runwayLengthMeters) m")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(FlybookColor.navy)

            RunwayWindGeometryView(
                runway: airport.reference.referenceRunway,
                windDirection: sample?.windDirectionDegrees,
                activeRunway: recommendation?.runwayLabel,
                emphasizesActiveRunway: true
            )
            .frame(height: 112)

            HStack(spacing: 8) {
                component(
                    symbol: (recommendation?.headwindKnots ?? 0) >= 0
                        ? "arrow.down" : "arrow.up",
                    value: recommendation?.headwindKnots,
                    color: .green,
                    help: "Gegenwindkomponente"
                )
                component(
                    symbol:
                        recommendation?.crosswindSymbol
                        ?? "arrow.left.and.right",
                    value: recommendation?.crosswindKnots,
                    color: .orange,
                    help: "Seitenwindkomponente"
                )
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(windComponentsBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(FlybookColor.navy.opacity(0.25), lineWidth: 1)
            )
            .padding(.horizontal, 8)
            .help(crosswindHelp)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var crosswindHelp: String {
        guard recommendation != nil else {
            return "Runway-Empfehlung wird mit den Wetterdaten berechnet"
        }
        switch crosswindWarning {
        case .none:
            return "Pistenempfehlung ohne Crosswindwarnung"
        case .yellow:
            return "Erhöhte Querwindkomponente"
        case .red:
            return "Hohe Querwindkomponente"
        }
    }

    private func component(
        symbol: String,
        value: Double?,
        color: Color,
        help: String
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(value.map { String(format: "%.0f kt", $0) } ?? "—")
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(color)
        .help(help)
    }
}

private struct RunwayRecommendation {
    let runwayLabel: String
    let headwindKnots: Double
    let crosswindKnots: Double
    let crosswindComesFromRight: Bool

    var crosswindSymbol: String {
        crosswindComesFromRight ? "arrow.left" : "arrow.right"
    }

}

private struct AlternateWeatherBlock: View {
    let sample: EDFZWeatherSample?
    let isLoading: Bool
    let errorMessage: String?
    @AppStorage(UnitSystemSettingsKey.displaySystem)
    private var displayUnitSystemRaw = DisplayUnitSystem.eu.rawValue

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let sample {
                VStack(spacing: 12) {
                    weatherRow(
                        title: "WIND",
                        value: windText(sample)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                FlightPlanningWeatherStyle
                                    .windBackgroundColor(
                                        steadyWindKnots:
                                            sample.windSpeedKnots
                                    )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                FlybookColor.navy.opacity(0.45),
                                lineWidth: 1
                            )
                    )
                    weatherRow(
                        title: "WOLKEN / SICHT",
                        value: cloudVisibilityText(sample)
                    )
                    categoryBadge(sample.category)
                }
                .padding(12)
            } else {
                Text(errorMessage ?? "Wetter nicht verfügbar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FlybookColor.muted)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.07))
    }

    private func weatherRow(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(FlybookColor.navy)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private func categoryBadge(_ category: FlightCategory) -> some View {
        Text(category.rawValue)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(categoryColor(category))
            .clipShape(Capsule())
    }

    private func windText(_ sample: EDFZWeatherSample) -> String {
        guard let direction = sample.windDirectionDegrees,
              let speed = sample.windSpeedKnots
        else { return "--- / --" }
        var roundedDirection =
            (Int((direction / 10).rounded()) * 10) % 360
        if roundedDirection == 0 && direction > 0 {
            roundedDirection = 360
        }
        var result = String(
            format: "%03d / %02d",
            roundedDirection,
            max(0, Int(speed.rounded()))
        )
        if let gust = sample.windGustKnots, gust - speed >= 10 {
            result += String(format: " G%02d", max(0, Int(gust.rounded())))
        }
        return result
    }

    private func cloudVisibilityText(_ sample: EDFZWeatherSample) -> String {
        AviationWeatherText.cloudAndVisibility(
            lowCloudCoverPercent: sample.lowCloudCoverPercent,
            lowestCloudBaseFeet: sample.lowestCloudBaseFeetAGL,
            visibilityMeters: sample.visibilityMeters,
            unitSystem:
                DisplayUnitSystem(rawValue: displayUnitSystemRaw) ?? .eu
        )
    }

    private func categoryColor(_ category: FlightCategory) -> Color {
        switch category {
        case .vfr: return .green
        case .mvfr: return .blue
        case .ifr: return .red
        case .lifr: return .purple
        case .unavailable: return .gray
        }
    }
}
