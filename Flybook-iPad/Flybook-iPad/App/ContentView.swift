import SwiftUI

struct ContentView: View {
    private let airports: [Airport]

    @State private var selection: Airport?
    @State private var searchText = ""

    init() {
        let loadedAirports = AirportCatalog.load()
        airports = loadedAirports
        _selection = State(
            initialValue: loadedAirports.first(where: { $0.icao == "EDFZ" })
                ?? loadedAirports.first
        )
    }

    private var filteredAirports: [Airport] {
        guard !searchText.isEmpty else { return airports }
        return airports.filter {
            $0.icao.localizedCaseInsensitiveContains(searchText)
                || $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filteredAirports, selection: $selection) { airport in
                NavigationLink(value: airport) {
                    AirportRow(airport: airport)
                }
            }
            .navigationTitle("Flugplätze")
            .searchable(text: $searchText, prompt: "ICAO oder Name")
        } detail: {
            if let selection {
                AirportDetailView(airport: selection)
            } else {
                ContentUnavailableView(
                    "Flugplatz auswählen",
                    systemImage: "airplane.circle",
                    description: Text("Der lokale Flybook-Datenbestand ist bereits eingebunden.")
                )
            }
        }
        .tint(.flybookBlue)
    }
}

private struct AirportRow: View {
    let airport: Airport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(airport.icao)
                .font(.headline)
                .foregroundStyle(Color.flybookBlue)
            Text(airport.name)
                .font(.subheadline)
                .lineLimit(1)
            HStack(spacing: 8) {
                Label(airport.runwayDisplay, systemImage: "road.lanes")
                if airport.isTechStop {
                    Text("TECHSTOP")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.12), in: Capsule())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct AirportDetailView: View {
    let airport: Airport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: 14)],
                    spacing: 14
                ) {
                    MetricCard(
                        title: "RUNWAY",
                        value: airport.runwayDisplay,
                        icon: "road.lanes"
                    )
                    MetricCard(
                        title: "HÖHE",
                        value: "\(airport.elevationFeet.formatted()) ft",
                        icon: "mountain.2"
                    )
                    MetricCard(
                        title: "ZEITZONE",
                        value: airport.timeZoneIdentifier,
                        icon: "clock"
                    )
                    MetricCard(
                        title: "ENTFERNUNG EDFZ",
                        value: airport.distanceFromEDFZ.map { "\($0.formatted()) NM" } ?? "–",
                        icon: "location"
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("iPad-Migration gestartet", systemImage: "ipad.landscape")
                        .font(.title2.bold())
                        .foregroundStyle(Color.flybookNavy)
                    Text("Diese erste native Version liest bereits die aktuelle Flybook-Flugplatzdatei. Wetter, Flugplanung, Alternates und Charterkalkulation werden anschließend schrittweise als gemeinsame iOS-Komponenten übernommen.")
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.flybookPanel, in: RoundedRectangle(cornerRadius: 20))
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(airport.icao)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: "airplane.arrival")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(Color.flybookBlue)
                .frame(width: 72, height: 72)
                .background(Color.flybookBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 5) {
                Text(airport.icao)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.flybookNavy)
                Text(airport.name)
                    .font(.title2.weight(.semibold))
                Text(airport.countryCode)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(Color.flybookNavy)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.gray.opacity(0.2), lineWidth: 1)
        }
    }
}

private extension Color {
    static let flybookNavy = Color(red: 0.02, green: 0.18, blue: 0.35)
    static let flybookBlue = Color(red: 0.18, green: 0.50, blue: 0.83)
    static let flybookPanel = Color(red: 0.92, green: 0.96, blue: 0.99)
}

#Preview {
    ContentView()
}
