import SwiftUI
import AppKit

final class FlybookAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct FlybookEuropeApp: App {
    @NSApplicationDelegateAdaptor(FlybookAppDelegate.self)
    private var appDelegate
    @StateObject private var store = DestinationStore()
    @State private var selectedIndex = 0
    @State private var didSelectDefaultDestination = false
    @State private var showsETOPSSetup = false
    @State private var showsAircraftSetup = false
    @State private var showsBaseSetup = false
    @State private var showsAirportSetup = false
    @State private var showsAlternates = false
    @State private var showsReservationManager = false
    @State private var showsDestinationFinder = false
    @State private var filteredDestinationICAOs: Set<String>?
    @State private var destinationFilterIsActive = true
    @State private var destinationSearchText = ""
    @State private var plannedMainDestinationArrival: Date?
    @State private var destinationSearchIsFocused = false
    @State private var destinationSearchFocusRequest = 0
    @AppStorage(UnitSystemSettingsKey.displaySystem)
    private var displayUnitSystemRaw = DisplayUnitSystem.eu.rawValue
    @AppStorage(CalculationSettingsKey.fuelDisplayUnit)
    private var fuelDisplayUnitRaw = FuelDisplayUnit.liters.rawValue
    @AppStorage(PressureSettingsKey.displayUnit)
    private var pressureDisplayUnitRaw =
        PressureDisplayUnit.mbar.rawValue

    init() {
        ETOPSProfileStore.restorePersistentProfiles()
        AircraftProfileStore.installDEZHSClimbChartIfNeeded()
        AircraftProfileStore.installDEZHS65PercentCruiseChartIfNeeded()
        AircraftProfileStore.installDEZHSConservativeCruiseFuelIfNeeded()
        AircraftProfileStore.installDEUKSConservativeCruiseFuelIfNeeded()
        AircraftProfileStore.installDETIK65PercentCruiseChartIfNeeded()
        AircraftProfileStore.installDETIKISAClimbPerformanceIfNeeded()
    }

    var body: some Scene {
        Window("Flybook Europe", id: "main") {
            VStack(spacing: 0) {
                navigationBar
                    .zIndex(100)

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
                } else if destinationFilterIsActive
                    && selectableDestinations.isEmpty
                {
                    VStack(spacing: 14) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 40))
                        Text("Keine passenden Ziele")
                            .font(.title2.bold())
                        Text("Die aktuellen Destination-Finder-Kriterien erfüllen keine Ziele.")
                            .foregroundStyle(.secondary)
                        Button("Filter aufheben") {
                            clearDestinationFilter()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.destinations.indices
                    .contains(selectedIndex)
                {
                    DestinationPage(
                        destination:
                            store.destinations[selectedIndex],
                        availableDestinations: store.destinations,
                        destinationPickerDestinations:
                            selectableDestinations,
                        destinationFilterIsActive:
                            destinationFilterActiveBinding,
                        destinationFilterIsAvailable:
                            filteredDestinationICAOs != nil,
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
                                    ),
                                    referenceRunway: airport.referenceRunway
                                )
                            },
                        selectedDestinationIndex: $selectedIndex,
                        plannedMainDestinationArrival:
                            $plannedMainDestinationArrival
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
                applyUnitSystem(
                    DisplayUnitSystem(rawValue: displayUnitSystemRaw) ?? .eu
                )
                selectDefaultDestinationIfAvailable()
            }
            .task {
                await LandingVoucherBook.refreshIfNeeded()
            }
            .task(id: selectedFuelPriceRefreshICAO) {
                guard !selectedFuelPriceRefreshICAO.isEmpty else { return }
                while !Task.isCancelled {
                    await store.refreshFuelPriceIfNeeded(
                        for: selectedFuelPriceRefreshICAO
                    )
                    do {
                        try await Task.sleep(
                            nanoseconds: 6 * 60 * 60 * 1_000_000_000
                        )
                    } catch {
                        return
                    }
                }
            }
            .onChange(of: store.isLoading) { isLoading in
                guard !isLoading else { return }
                selectDefaultDestinationIfAvailable()
                Task {
                    // Nur Geometrie registrieren. Wetter wird gezielt fuer die
                    // sichtbare Route oder beim Anwenden eines Filters geladen.
                    // Zwei Vollabrufe aller Flugplaetze beim App-Start waren
                    // teuer, redundant und konnten Open-Meteo drosseln.
                    await DestinationFinderWeatherCache.shared.register(
                        destinations: store.destinations
                    )
                }
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

    private var selectedFuelPriceRefreshICAO: String {
        guard didSelectDefaultDestination,
              !store.isLoading,
              store.destinations.indices.contains(selectedIndex)
        else { return "" }
        return store.destinations[selectedIndex].icao
    }

    private var navigationBar: some View {
        HStack {
            HStack(spacing: 8) {
                Button(action: previous) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(FlybookColor.navy)
                        )
                }
                .buttonStyle(.plain)
                .help("Vorheriges Ziel")

                Button(action: next) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(FlybookColor.blue)
                        )
                }
                .buttonStyle(.plain)
                .help("Nächstes Ziel")

                Button {
                    destinationFilterIsActive.toggle()
                    if destinationFilterIsActive,
                       filteredDestinationICAOs != nil,
                       let first = selectableDestinationIndices.first {
                        selectedIndex = first
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(
                                    destinationFilterIsActive
                                        ? FlybookColor.blue
                                        : FlybookColor.muted
                                )
                        )
                }
                .buttonStyle(.plain)
                .help(
                    filteredDestinationICAOs == nil
                        ? "Zielfilter aktiv · noch keine Kriterien bestätigt"
                        : destinationFilterIsActive
                            ? "Bestätigte Destination-Finder-Kriterien aktiv"
                            : "Bestätigte Destination-Finder-Kriterien pausiert"
                )
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(FlybookColor.blue.opacity(0.10))
            )

            destinationSearchField

            Spacer()

            Picker("Einheitensystem", selection: $displayUnitSystemRaw) {
                ForEach(DisplayUnitSystem.allCases) { system in
                    Text(system.pickerSymbol)
                        .accessibilityLabel(system.accessibilityLabel)
                        .tag(system.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 92, height: 36)
            .help("EU: km, Liter, mbar · US: SM, US gal, inHg")
            .onChange(of: displayUnitSystemRaw) { newValue in
                applyUnitSystem(
                    DisplayUnitSystem(rawValue: newValue) ?? .eu
                )
            }

            Button {
                showsDestinationFinder = true
            } label: {
                Image(systemName: "airplane.arrival")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 28, height: 36)
                    .accessibilityLabel("Destination Finder")
            }
            .frame(height: 36)
            .help("Ziele nach Reisezeit und Wetter filtern")
            .sheet(isPresented: $showsDestinationFinder) {
                DestinationFinderView(
                    destinations: store.destinations,
                    origins: allAirportReferences,
                    onApply: applyDestinationFilter,
                    onClear: clearDestinationFilter
                )
            }

            Button {
                showsAlternates = true
            } label: {
                Image(systemName: "signpost.right.and.left")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 28, height: 36)
                    .accessibilityLabel("Alternates")
            }
            .frame(height: 36)
            .help("Aktuellen Zielairport und vier Alternates vergleichen")
            .sheet(isPresented: $showsAlternates) {
                if store.destinations.indices.contains(selectedIndex) {
                    AlternatesView(
                        destination: store.destinations[selectedIndex],
                        availableDestinations: store.destinations,
                        plannedMainDestinationArrival:
                            plannedMainDestinationArrival
                    )
                } else {
                    Text("Kein Zielairport ausgewählt")
                        .padding(24)
                }
            }

            Button {
                showsReservationManager = true
            } label: {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 28, height: 36)
                    .accessibilityLabel("Reservierung")
            }
            .frame(height: 36)
            .help("Reservierungsmanager Mainz")
            .sheet(isPresented: $showsReservationManager) {
                ReservationManagerView()
            }

            Button {
                showsBaseSetup = true
            } label: {
                Image(systemName: "building.2")
                    .frame(width: 28, height: 36)
            }
            .frame(height: 36)
            .help("Basiskonfiguration")
            .sheet(isPresented: $showsBaseSetup) {
                BaseSetupView(destinations: store.destinations)
            }
            Button {
                showsAirportSetup = true
            } label: {
                Image(systemName: "road.lanes")
                    .frame(width: 28, height: 36)
            }
            .frame(height: 36)
            .help("Airportkonfiguration")
            .sheet(isPresented: $showsAirportSetup) {
                AirportSetupView(destinations: store.destinations)
            }
            Button {
                showsAircraftSetup = true
            } label: {
                Image(systemName: "airplane")
                    .frame(width: 28, height: 36)
            }
            .frame(height: 36)
            .help("Flugzeugkonfiguration")
            .sheet(isPresented: $showsAircraftSetup) {
                AircraftSetupView()
            }
            Button {
                showsETOPSSetup = true
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 28, height: 36)
            }
            .frame(height: 36)
            .help("Allgemeines Setup")
            .sheet(isPresented: $showsETOPSSetup) {
                ETOPSSetupView()
            }

        }
        .controlSize(.large)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var destinationSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FlybookColor.muted)

            DestinationSearchTextField(
                text: $destinationSearchText,
                isEditing: $destinationSearchIsFocused,
                focusRequest: $destinationSearchFocusRequest,
                placeholder: "Ziel suchen · ICAO oder Name",
                onSubmit: selectTypedDestination
            )
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
            .onChange(of: destinationSearchText) { value in
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                if let destination = store.destinations.first(where: {
                    $0.icao.uppercased() == normalized
                }) {
                    selectDestination(destination)
                }
            }

            Menu {
                ForEach(selectableDestinations, id: \.icao) { destination in
                    Button("\(destination.icao) · \(destination.name)") {
                        selectDestination(destination)
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)
                    .frame(width: 24, height: 28)
            }
            .menuStyle(.borderlessButton)
            .focusable(false)
        }
        .padding(.horizontal, 10)
        .frame(width: 330, height: 36)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(FlybookColor.blue.opacity(0.55), lineWidth: 1.5)
                .allowsHitTesting(false)
        )
        .overlay(alignment: .topLeading) {
            if destinationSearchIsFocused,
               normalizedDestinationSearch.count >= 3,
               !destinationSearchSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(destinationSearchSuggestions, id: \.icao) { destination in
                        Button {
                            selectDestination(destination)
                            destinationSearchIsFocused = false
                        } label: {
                            HStack(spacing: 8) {
                                Text(destination.icao)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .frame(width: 48, alignment: .leading)
                                Text(destination.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .foregroundStyle(FlybookColor.navy)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 5)
                .frame(width: 330)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .shadow(color: .black.opacity(0.20), radius: 8, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(FlybookColor.line, lineWidth: 1)
                )
                .offset(y: 39)
            }
        }
        .zIndex(50)
        .onAppear { synchronizeDestinationSearchText() }
        .onChange(of: selectedIndex) { _ in synchronizeDestinationSearchText() }
        .help("Ziel aus der Liste wählen oder ICAO beziehungsweise Namen eingeben und Return drücken")
    }

    private var normalizedDestinationSearch: String {
        destinationSearchText
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var destinationSearchSuggestions: [Destination] {
        let query = normalizedDestinationSearch
        guard query.count >= 3 else { return [] }
        return store.destinations.filter { destination in
            let searchable = "\(destination.icao) \(destination.name)"
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return searchable.contains(query)
        }
        .prefix(8)
        .map { $0 }
    }

    private func selectTypedDestination() {
        guard let destination = destinationSearchSuggestions.first else {
            synchronizeDestinationSearchText()
            return
        }
        selectDestination(destination)
        destinationSearchIsFocused = false
    }

    private func selectDestination(_ destination: Destination) {
        guard let index = store.destinations.firstIndex(where: {
            $0.icao == destination.icao
        }) else { return }
        selectedIndex = index
        destinationSearchText = "\(destination.icao) · \(destination.name)"
    }

    private func synchronizeDestinationSearchText() {
        guard store.destinations.indices.contains(selectedIndex) else { return }
        let destination = store.destinations[selectedIndex]
        destinationSearchText = "\(destination.icao) · \(destination.name)"
    }

    private func previous() {
        let indices = selectableDestinationIndices
        guard !indices.isEmpty else {
            return
        }
        let currentPosition = indices.firstIndex(of: selectedIndex) ?? 0
        selectedIndex = indices[
            (currentPosition - 1 + indices.count) % indices.count
        ]
    }

    private func next() {
        let indices = selectableDestinationIndices
        guard !indices.isEmpty else {
            return
        }
        let currentPosition = indices.firstIndex(of: selectedIndex) ?? -1
        selectedIndex = indices[(currentPosition + 1) % indices.count]
    }

    private var selectableDestinations: [Destination] {
        guard destinationFilterIsActive,
              let filteredDestinationICAOs
        else {
            return store.destinations
        }
        return store.destinations.filter {
            filteredDestinationICAOs.contains($0.icao)
        }
    }

    private var selectableDestinationIndices: [Int] {
        store.destinations.indices.filter { index in
            guard destinationFilterIsActive,
                  let filteredDestinationICAOs
            else { return true }
            return filteredDestinationICAOs.contains(
                store.destinations[index].icao
            )
        }
    }

    private var destinationFilterActiveBinding: Binding<Bool> {
        Binding(
            get: { destinationFilterIsActive },
            set: { newValue in
                destinationFilterIsActive = newValue
                if newValue,
                   let first = selectableDestinationIndices.first
                {
                    selectedIndex = first
                }
            }
        )
    }

    private var allAirportReferences: [AirportReference] {
        var airports = [AirportReference.edfz]
        for destination in store.destinations {
            guard let latitude = destination.latitude,
                  let longitude = destination.longitude,
                  !airports.contains(where: { $0.icao == destination.icao })
            else { continue }
            airports.append(
                AirportReference(
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
            )
        }
        return airports
    }

    private func applyDestinationFilter(_ matches: [DestinationFinderMatch]) {
        let identifiers = Set(matches.map(\.destinationICAO))
        filteredDestinationICAOs = identifiers
        if destinationFilterIsActive,
           let first = store.destinations.firstIndex(where: {
               identifiers.contains($0.icao)
           })
        {
            selectedIndex = first
        }
    }

    private func clearDestinationFilter() {
        filteredDestinationICAOs = nil
        destinationFilterIsActive = true
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

private struct DestinationSearchTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    @Binding var focusRequest: Int
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = FlybookActivatingSearchTextField()
        context.coordinator.appliedFocusRequest = focusRequest
        field.delegate = context.coordinator
        field.isEnabled = true
        field.isEditable = true
        field.isSelectable = true
        field.refusesFirstResponder = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 14, weight: .semibold)
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.appliedFocusRequest != focusRequest {
            context.coordinator.appliedFocusRequest = focusRequest
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                field.window?.makeKeyAndOrderFront(nil)
                field.window?.makeFirstResponder(field)
                field.selectText(nil)
            }
        } else if !isEditing,
           field.window?.firstResponder === field.currentEditor() {
            field.window?.makeFirstResponder(nil)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DestinationSearchTextField
        var appliedFocusRequest = 0

        init(parent: DestinationSearchTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isEditing = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isEditing = false
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:))
            else { return false }
            parent.onSubmit()
            return true
        }
    }
}
