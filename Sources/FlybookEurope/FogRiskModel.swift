import Foundation

/// Shared local-hour timeline for the two color bars on every daily tile.
enum DailyWeatherTimeline {
    static let hours = Array(6...22)
}

enum FogRiskLevel: String, Hashable, Sendable {
    case low
    case raised
    case high
    case veryHigh

    var label: String {
        switch self {
        case .low: return "gering"
        case .raised: return "erhöht"
        case .high: return "hoch"
        case .veryHigh: return "sehr hoch"
        }
    }
}

struct FogRiskInput: Hashable, Sendable {
    let temperatureC: Double
    let dewPointC: Double
    let windKt: Double
    let visibilityKm: Double
    let lowCloudPercent: Double
    let ceilingFt: Double
    var lowLevelRHPercent: Double?
    var totalCloudPercent = 0.0
    var rainLast6HoursMM = 0.0
    var isNight = false
    var isValley = false
}

struct FogRiskAssessment: Hashable, Sendable {
    let score: Int
    let level: FogRiskLevel
    let spreadC: Double
    let hasOperationalSignal: Bool
}

/// Swift port of Universal Fog and Low Cloud Risk Index v1.0.0.
/// The score is a risk index, not a calibrated probability.
enum FogRiskModel {
    static func classify(score: Int) -> FogRiskLevel {
        switch score {
        case 70...: return .veryHigh
        case 50...: return .high
        case 25...: return .raised
        default: return .low
        }
    }

    static func calculate(_ input: FogRiskInput) -> FogRiskAssessment? {
        let required = [
            input.temperatureC,
            input.dewPointC,
            input.windKt,
            input.visibilityKm,
            input.lowCloudPercent,
            input.ceilingFt,
            input.totalCloudPercent,
            input.rainLast6HoursMM
        ]
        guard required.allSatisfy(\.isFinite) else { return nil }

        let lowLevelRHPercent: Double
        if let supplied = input.lowLevelRHPercent, supplied.isFinite {
            lowLevelRHPercent = supplied
        } else {
            lowLevelRHPercent = relativeHumidity(
                temperatureC: input.temperatureC,
                dewPointC: input.dewPointC
            )
        }

        let spreadC = max(0, input.temperatureC - input.dewPointC)
        let saturation = interpolate(spreadC, points: [
            (0, 25), (0.5, 24), (1, 21), (2, 15),
            (3, 9), (5, 2), (7, 0)
        ])
        let visibility = interpolate(max(0.1, input.visibilityKm), points: [
            (0.2, 40), (0.5, 39), (1, 35), (2, 27),
            (5, 12), (10, 2), (20, 0)
        ])
        let ceilingBase = interpolate(max(0, input.ceilingFt), points: [
            (100, 30), (200, 30), (500, 26), (1_000, 19),
            (1_500, 11), (3_000, 2), (10_000, 0)
        ])
        let ceilingAndLowCloud = ceilingBase
            * clamped(input.lowCloudPercent / 100, minimum: 0, maximum: 1)
        let lowLevelHumidity = clamped(
            ((lowLevelRHPercent - 75) / 25) * 12,
            minimum: 0,
            maximum: 12
        )

        let wind: Double
        if input.windKt < 1 {
            wind = 4
        } else if input.windKt <= 5 {
            wind = 8
        } else if input.windKt <= 8 {
            wind = 4
        } else if input.windKt > 12 {
            wind = -5
        } else {
            wind = 0
        }

        let radiation = input.isNight
            ? clamped(
                ((100 - input.totalCloudPercent) / 100) * 6,
                minimum: 0,
                maximum: 6
            )
            : 0
        let wetGround = clamped(
            (input.rainLast6HoursMM / 5) * 6,
            minimum: 0,
            maximum: 6
        )
        let terrain = input.isValley ? 4.0 : 0.0

        var score = clamped(
            saturation + visibility + ceilingAndLowCloud
                + lowLevelHumidity + wind + radiation
                + wetGround + terrain,
            minimum: 0,
            maximum: 100
        )

        if input.visibilityKm <= 1 {
            score = max(score, 70)
        }
        if input.lowCloudPercent >= 75, input.ceilingFt <= 500 {
            score = max(score, 70)
        } else if input.lowCloudPercent >= 75, input.ceilingFt <= 1_000 {
            score = max(score, 50)
        }
        if input.visibilityKm <= 2,
           input.lowCloudPercent >= 75,
           input.ceilingFt <= 1_000 {
            score = max(score, 70)
        }

        let hasOperationalSignal = input.visibilityKm <= 5
            || (input.lowCloudPercent >= 75 && input.ceilingFt <= 1_500)
        if score >= 50, !hasOperationalSignal {
            score = 49
        }

        let roundedScore = Int(score.rounded())
        return FogRiskAssessment(
            score: roundedScore,
            level: classify(score: roundedScore),
            spreadC: (spreadC * 10).rounded() / 10,
            hasOperationalSignal: hasOperationalSignal
        )
    }

    private static func interpolate(
        _ value: Double,
        points: [(Double, Double)]
    ) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if value <= first.0 { return first.1 }

        for index in 1..<points.count where value <= points[index].0 {
            let lower = points[index - 1]
            let upper = points[index]
            return lower.1
                + ((upper.1 - lower.1) * (value - lower.0))
                / (upper.0 - lower.0)
        }
        return last.1
    }

    private static func relativeHumidity(
        temperatureC: Double,
        dewPointC: Double
    ) -> Double {
        func saturation(_ temperature: Double) -> Double {
            exp((17.625 * temperature) / (243.04 + temperature))
        }
        return clamped(
            100 * saturation(dewPointC) / saturation(temperatureC),
            minimum: 0,
            maximum: 100
        )
    }

    private static func clamped(
        _ value: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        max(minimum, min(maximum, value))
    }
}
