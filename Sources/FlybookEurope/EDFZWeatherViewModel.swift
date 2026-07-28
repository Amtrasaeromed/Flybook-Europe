import Foundation

@MainActor
final class EDFZWeatherViewModel: ObservableObject {
    @Published private(set) var forecast: EDFZForecast?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func load(plannedDate: Date) async {
        isLoading = true
        errorMessage = nil
        do {
            forecast = try await EDFZWeatherService.shared.forecast(
                plannedDate: plannedDate
            )
        } catch {
            forecast = nil
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
