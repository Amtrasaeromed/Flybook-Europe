import Foundation

@MainActor
final class RouteWindViewModel: ObservableObject {
    @Published private(set) var wind: RouteWind?
    @Published private(set) var bestLevelFeet: Int?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var currentRequestID = UUID()
    private var windsByAltitude: [Int: RouteWind] = [:]

    func load(
        destination: AirportReference,
        origin: AirportReference,
        plannedStart: Date,
        plannedEnd: Date,
        altitudeOptions: [Int],
        selectedAltitudeFeet: Int,
        isReturn: Bool,
        directNM: Double,
        trackMilesNM: Double,
        stopCount: Int,
        tankStopMinutes: Int,
        fallbackCruiseSpeedKnots: Double,
        departurePressureAltitudeFeet: Double,
        climbPerformance: ClimbPerformance,
        cruisePerformance: CruisePerformance
    ) async {
        let requestID = UUID()
        currentRequestID = requestID
        isLoading = true
        errorMessage = nil
        do {
            var result: [RouteWind] = []
            let optimizationLevels = Array(stride(from: 1_500, through: 10_000, by: 100))
            let requestedLevels = Array(
                Set(optimizationLevels + altitudeOptions + [selectedAltitudeFeet])
            ).sorted()
            for altitudeFeet in requestedLevels {
                if let candidate =
                    try? await RouteWindService.shared.wind(
                        for: destination,
                        origin: origin,
                        plannedStart: plannedStart,
                        plannedEnd: plannedEnd,
                        altitudeFeet: altitudeFeet,
                        isReturn: isReturn
                    )
                {
                    result.append(candidate)
                }
            }
            guard !result.isEmpty else {
                throw RouteWindError.noForecast
            }

            let candidates = result.filter {
                (1_500...10_000).contains($0.altitudeFeet)
            }
            let bestLevel = candidates.min { first, second in
                travelMinutes(
                    wind: first,
                    isReturn: isReturn,
                    directNM: directNM,
                    trackMilesNM: trackMilesNM,
                    stopCount: stopCount,
                    tankStopMinutes: tankStopMinutes,
                    fallbackCruiseSpeedKnots: fallbackCruiseSpeedKnots,
                    departurePressureAltitudeFeet: departurePressureAltitudeFeet,
                    climbPerformance: climbPerformance,
                    cruisePerformance: cruisePerformance
                ) < travelMinutes(
                    wind: second,
                    isReturn: isReturn,
                    directNM: directNM,
                    trackMilesNM: trackMilesNM,
                    stopCount: stopCount,
                    tankStopMinutes: tankStopMinutes,
                    fallbackCruiseSpeedKnots: fallbackCruiseSpeedKnots,
                    departurePressureAltitudeFeet: departurePressureAltitudeFeet,
                    climbPerformance: climbPerformance,
                    cruisePerformance: cruisePerformance
                )
            }?.altitudeFeet
            let selected = result.first {
                $0.altitudeFeet == selectedAltitudeFeet
            } ?? result.min {
                abs($0.altitudeFeet - selectedAltitudeFeet)
                    < abs($1.altitudeFeet - selectedAltitudeFeet)
            }
            guard let selected else {
                throw RouteWindError.noForecast
            }
            guard currentRequestID == requestID else { return }
            windsByAltitude = Dictionary(
                uniqueKeysWithValues: result.map {
                    ($0.altitudeFeet, $0)
                }
            )
            bestLevelFeet = bestLevel
            wind = selected
        } catch {
            guard currentRequestID == requestID else { return }
            windsByAltitude = [:]
            bestLevelFeet = nil
            wind = nil
            errorMessage = error.localizedDescription
        }
        if currentRequestID == requestID {
            isLoading = false
        }
    }

    private func travelMinutes(
        wind: RouteWind,
        isReturn: Bool,
        directNM: Double,
        trackMilesNM: Double,
        stopCount: Int,
        tankStopMinutes: Int,
        fallbackCruiseSpeedKnots: Double,
        departurePressureAltitudeFeet: Double,
        climbPerformance: ClimbPerformance,
        cruisePerformance: CruisePerformance
    ) -> Double {
        FlightMath.adjustedDurationMinutes(
            directNM: directNM,
            stopCount: stopCount,
            headwindKnots: isReturn
                ? wind.returnHeadwindKnots
                : wind.outboundHeadwindKnots,
            tankStopMinutes: tankStopMinutes,
            cruiseGroundSpeedKnots: fallbackCruiseSpeedKnots,
            climbDeparturePressureAltitudeFeet: departurePressureAltitudeFeet,
            climbTargetPressureAltitudeFeet: Double(wind.altitudeFeet),
            climbPerformance: climbPerformance,
            cruisePerformance: cruisePerformance,
            trackMilesNM: trackMilesNM
        )
    }

    func selectAltitude(_ altitudeFeet: Int) {
        guard let selected = windsByAltitude[altitudeFeet] else {
            return
        }
        wind = selected
    }
}
