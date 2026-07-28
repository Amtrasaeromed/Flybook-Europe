import Foundation

@MainActor
final class RouteWindViewModel: ObservableObject {
    @Published private(set) var wind: RouteWind?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func load(
        destination: Destination,
        origin: AirportReference,
        plannedInstant: Date,
        altitudeFeet: Int
    ) async {
        isLoading = true
        errorMessage = nil
        do {
            wind = try await RouteWindService.shared.wind(
                for: destination,
                origin: origin,
                plannedInstant: plannedInstant,
                altitudeFeet: altitudeFeet
            )
        } catch {
            wind = nil
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
