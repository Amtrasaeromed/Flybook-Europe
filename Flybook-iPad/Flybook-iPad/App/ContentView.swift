import SwiftUI

struct ContentView: View {
    private let airports = AirportCatalog.load()

    var body: some View {
        FlybookDashboardView(airports: airports)
    }
}

#Preview {
    ContentView()
}
