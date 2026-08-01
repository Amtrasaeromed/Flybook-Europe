import SwiftUI

@main
struct FlybookEuropeApp: App {
    @StateObject private var store = DestinationStore()
    @State private var selectedIndex = 0
    @State private var didSelectDefaultDestination = false
    @State private var showsETOPSSetup = false
    @State private var showsAircraftSetup = false
    @State private var showsBaseSetup = false
    @State private var showsAlternates = false
    @State private var showsReservationManager = false
    @AppStorage(UnitSystemSettingsKey.displaySystem)
    private var displayUnitSystemRaw = DisplayUnitSystem.eu.rawValue
    @AppStorage(CalculationSettingsKey.fuelDisplayUnit)
    private var fuelDisplayUnitRaw = FuelDisplayUnit.liters.rawValue
    @AppStorage(PressureSettingsKey.displayUnit)
    private var pressureDisplayUnitRaw =
        PressureDisplayUnit.mbar.rawValue

    var body: some Scene {
        WindowGroup("Flybook Europe") {
            VStack(spacing: 0) {
                navigationBar

                if store.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()

                        Text("Ziele werden geladen …")
                            .foregroundStyle(.secondary)
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                } else if let error = store.loadError {
                    VStack(spacing: 14) {
                        Image(
                            systemName:
                                "exclamationmark.triangle"
                        )
                        .font(.system(size: 42))

                        Text(
                            "Masterdaten konnten "
                            + "nicht geladen werden"
                        )
                        .font(.title2.bold())

                        Text(error)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .padding(32)
                } else if store.destinations.indices
                    .contains(selectedIndex)
                {
                    DestinationPage(
                        destination:
                            store.destinations[selectedIndex],
                        availableOrigins: [.edfz]
                            + store.destinations.compactMap { airport in
                                guard airport.icao != "EDFZ" else {
                                    return nil
                                }
                                guard let latitude = airport.latitude,
                                      let longitude = airport.longitude
                                else { return nil }
                                return AirportReference(
                                    icao: airport.icao,
                                    name: airport.name,
                                    latitude: latitude,
                                    longitude: longitude,
                                    elevationFeet: airport.elevationFeet,
                                    timeZone: DestinationTimeZone.value(
                                        for: airport,
                                        weatherTimeZone: nil
                                    )
                                )
                            }
                    )
                } else {
                    VStack(spacing: 14) {
                        Image(
                            systemName:
                                "tray"
                        )
                        .font(.system(size: 40))

                        Text("Keine Ziele geladen")
                            .font(.title2.bold())

                        Text(
                            "Die Mastertabelle wurde gelesen, "
                            + "enthielt aber keine verwendbaren "
                            + "Zieldatensätze."
                        )
                        .foregroundStyle(.secondary)
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                }
            }
            .frame(minWidth: 1100, minHeight: 760)
            .onAppear {
                selectDefaultDestinationIfAvailable()
            }
            .onChange(of: store.isLoading) { isLoading in
                guard !isLoading else { return }
                selectDefaultDestinationIfAvailable()
            }
        }
        .windowStyle(.titleBar)
    }

    private func selectDefaultDestinationIfAvailable() {
        guard !didSelectDefaultDestination,
              let aachenIndex = store.destinations.firstIndex(
                where: { $0.icao == "EDKA" }
              )
        else { return }

        selectedIndex = aachenIndex
        didSelectDefaultDestination = true
    }

    private var navigationBar: some View {
        HStack {
            HStack(spacing: 6) {
                Button(action: previous) {
                    Image(systemName: "chevron.left")
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button(action: next) {
                    Image(systemName: "chevron.right")
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
            }

            Text("ZIEL")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(FlybookColor.navy)

            Picker("", selection: $selectedIndex) {
                ForEach(
                    Array(store.destinations.enumerated()),
                    id: \.element.id
                ) { index, destination in
                    Text("\(destination.name) · \(destination.icao)")
                        .tag(index)
                }
            }
            .frame(width: 280)

            Text(
                "\(min(selectedIndex + 1, store.destinations.count)) "
                + "/ \(store.destinations.count)"
            )
            .font(.system(size: 13, weight: .semibold))

            Spacer()

            Picker("Einheitensystem", selection: $displayUnitSystemRaw) {
                ForEach(DisplayUnitSystem.allCases) { system in
                    Text(system.rawValue).tag(system.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 88)
            .help("EU: km, Liter, hPa · US: SM, US gal, inHg")
            .onChange(of: displayUnitSystemRaw) { newValue in
                applyUnitSystem(
                    DisplayUnitSystem(rawValue: newValue) ?? .eu
                )
            }

            Button {
                showsAlternates = true
            } label: {
                Label("Alternates", systemImage: "signpost.right.and.left")
            }
            .help("Heimatflugplatz und Alternates vergleichen")
            .sheet(isPresented: $showsAlternates) {
                AlternatesView()
            }

            Button {
                showsReservationManager = true
            } label: {
                Label("Reservierung", systemImage: "calendar.badge.clock")
            }
            .help("Reservierungsmanager Mainz")
            .sheet(isPresented: $showsReservationManager) {
                ReservationManagerView()
            }

            Button {
                showsETOPSSetup = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Allgemeines Setup")
            .sheet(isPresented: $showsETOPSSetup) {
                ETOPSSetupView()
            }
            Button {
                showsBaseSetup = true
            } label: {
                Image(systemName: "building.2")
            }
            .help("Basiskonfiguration")
            .sheet(isPresented: $showsBaseSetup) {
                BaseSetupView(destinations: store.destinations)
            }
            Button {
                showsAircraftSetup = true
            } label: {
                Image(systemName: "airplane")
            }
            .help("Flugzeugkonfiguration")
            .sheet(isPresented: $showsAircraftSetup) {
                AircraftSetupView()
            }

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func previous() {
        guard !store.destinations.isEmpty else {
            return
        }

        selectedIndex =
            (selectedIndex - 1 + store.destinations.count)
            % store.destinations.count
    }

    private func next() {
        guard !store.destinations.isEmpty else {
            return
        }

        selectedIndex =
            (selectedIndex + 1)
            % store.destinations.count
    }

    private func applyUnitSystem(_ system: DisplayUnitSystem) {
        switch system {
        case .eu:
            fuelDisplayUnitRaw = FuelDisplayUnit.liters.rawValue
            pressureDisplayUnitRaw =
                PressureDisplayUnit.mbar.rawValue
        case .us:
            fuelDisplayUnitRaw = FuelDisplayUnit.usGallons.rawValue
            pressureDisplayUnitRaw =
                PressureDisplayUnit.inHg.rawValue
        }
    }
}
