import Foundation

@MainActor
final class EDFZWeatherViewModel: ObservableObject {
    @Published private(set) var forecast: EDFZForecast?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var currentRequestID = UUID()

    func load(
        plannedDate: Date,
        airport: AirportReference
    ) async {
        let requestID = UUID()
        currentRequestID = requestID
        isLoading = true
        errorMessage = nil
        do {
            let result = try await EDFZWeatherService.shared.forecast(
                plannedDate: plannedDate,
                airport: airport
            )
            guard currentRequestID == requestID else { return }
            forecast = result
        } catch {
            guard currentRequestID == requestID else { return }
            forecast = nil
            errorMessage = error.localizedDescription
        }
        if currentRequestID == requestID {
            isLoading = false
        }
    }
}
