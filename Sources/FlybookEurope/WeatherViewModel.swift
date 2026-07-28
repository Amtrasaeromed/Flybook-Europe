import Foundation

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published private(set) var weather: DestinationWeather?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var currentICAO: String?

    func load(
        destination: Destination,
        targetInstants: [Date],
        forceRefresh: Bool = false
    ) async {
        currentICAO = destination.icao
        isLoading = true
        errorMessage = nil

        do {
            let result = try await WeatherService.shared.weather(
                for: destination,
                targetInstants: targetInstants,
                forceRefresh: forceRefresh
            )
            guard currentICAO == destination.icao else { return }
            weather = result
        } catch {
            guard currentICAO == destination.icao else { return }
            weather = nil
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
