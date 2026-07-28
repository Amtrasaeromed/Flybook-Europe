import SwiftUI

@main
struct FlybookEuropeApp: App {
    @StateObject private var store = DestinationStore()
    @State private var selectedIndex = 0
    @State private var showsETOPSSetup = false
    @State private var showsAircraftSetup = false

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
                            store.destinations[selectedIndex]
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
        }
        .windowStyle(.titleBar)
    }

    private var navigationBar: some View {
        HStack {
            Button(action: previous) {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

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

            Button {
                showsETOPSSetup = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("ETOPS-PIPI Setup")
            .sheet(isPresented: $showsETOPSSetup) {
                ETOPSSetupView()
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


            Button(action: next) {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
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
}
