import Foundation

enum FlightAltitudeRules {
    static let defaultFeet = 2_500
    static let allOptions = Array(stride(from: 1_500, through: 12_000, by: 500))

    static func options(forCourseDegrees _: Double) -> [Int] {
        allOptions
    }

    static func recommendedOptions(forCourseDegrees courseDegrees: Double) -> [Int] {
        let normalized = courseDegrees.truncatingRemainder(dividingBy: 360)
        let course = normalized < 0 ? normalized + 360 : normalized
        if (180..<360).contains(course) {
            return [2_500, 4_500, 6_500, 8_500, 10_500]
        }
        return [2_500, 3_500, 5_500, 7_500, 9_500, 11_500]
    }

    static func isRecommended(
        _ altitudeFeet: Int,
        forCourseDegrees courseDegrees: Double
    ) -> Bool {
        recommendedOptions(forCourseDegrees: courseDegrees)
            .contains(altitudeFeet)
    }

    static func nearest(to current: Int, in options: [Int]) -> Int {
        options.min {
            abs($0 - current) < abs($1 - current)
        } ?? current
    }
}
