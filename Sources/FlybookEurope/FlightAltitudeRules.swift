import Foundation

enum FlightAltitudeRules {
    /// 2.500 ft bleibt als niedrige VFR-Reiseflughöhe in beiden
    /// Kursgruppen auswählbar. Oberhalb davon gelten die
    /// kursabhängigen Halbkreisflughöhen.
    static let defaultFeet = 2_500

    static func options(forCourseDegrees courseDegrees: Double) -> [Int] {
        if (180..<360).contains(WindMath.normalized(courseDegrees)) {
            return [2_500, 4_500, 6_500, 8_500]
        }
        return [2_500, 3_500, 5_500, 7_500, 9_500]
    }

    static func nearest(to current: Int, in options: [Int]) -> Int {
        options.min {
            abs($0 - current) < abs($1 - current)
        } ?? current
    }
}
