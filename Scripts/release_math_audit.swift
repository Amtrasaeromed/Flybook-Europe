import Foundation

private var checks = 0
private var failures: [String] = []

private func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    checks += 1
    if !condition() { failures.append(name) }
}

private func checkClose(
    _ actual: Double,
    _ expected: Double,
    tolerance: Double = 0.000_1,
    _ name: String
) {
    check(abs(actual - expected) <= tolerance, "\(name): \(actual) != \(expected)")
}

// Commercial rounding and cost consistency.
checkClose(CharterMath.commercialDecimalHours(minutes: 65), 1.1, "65 min")
checkClose(CharterMath.commercialDecimalHours(minutes: 66), 1.1, "66 min")
checkClose(CharterMath.commercialDecimalHours(minutes: 67), 1.2, "67 min")
checkClose(CharterMath.commercialCost(minutes: 67, hourlyRateEUR: 100), 120, "cost")
checkClose(
    CharterMath.commercialTotalDecimalHours(legMinutes: [75, 69]),
    2.5,
    "commercial total must equal displayed legs"
)
check(
    CharterMath.commercialEquivalentMinutes(legMinutes: [81, 82]) == 168,
    "reservation equivalent for two 1.4 h legs"
)

// Fuel reserve and refuelling calculations.
checkClose(
    CharterMath.requiredReserveLiters(
        outboundConsumptionPerHour: 20,
        returnConsumptionPerHour: 30,
        reserveMinutes: 30,
        outboundReserveIsReused: false
    ),
    25,
    "two independent reserves"
)
checkClose(
    CharterMath.requiredReserveLiters(
        outboundConsumptionPerHour: 20,
        returnConsumptionPerHour: 30,
        reserveMinutes: 30,
        outboundReserveIsReused: true
    ),
    15,
    "reused reserve must cover larger leg reserve"
)
checkClose(
    CharterMath.suggestedRefuelLiters(
        startingFuelLiters: 45,
        firstLegBlockFuelLiters: 30,
        firstLegRequiredFuelLiters: 45,
        secondLegRequiredFuelLiters: 50,
        remainingFirstLegFuelIsAvailable: true
    ),
    35,
    "remaining fuel credit"
)
checkClose(
    CharterMath.refuelLoss(
        grossPricePerLiter: 2.81,
        homeReferencePerLiter: 2.59,
        liters: 45,
        destinationVATPercent: 19,
        isForeign: false
    ) ?? -1,
    9.90,
    "EDKA MOGAS surcharge"
)
checkClose(
    CharterMath.refuelLoss(
        grossPricePerLiter: 2.40,
        homeReferencePerLiter: 2.59,
        liters: 45,
        destinationVATPercent: 19,
        isForeign: false
    ) ?? -1,
    0,
    "no domestic surcharge below reference"
)
checkClose(
    CharterMath.refuelLoss(
        grossPricePerLiter: 1.83,
        homeReferencePerLiter: 2.59,
        liters: 10,
        destinationVATPercent: 21,
        isForeign: true
    ) ?? -1,
    3.176_033_057_9,
    tolerance: 0.000_001,
    "foreign non-reimbursed VAT"
)
check(
    CharterMath.refuelLoss(
        grossPricePerLiter: nil,
        homeReferencePerLiter: 2.59,
        liters: 10,
        destinationVATPercent: 19,
        isForeign: false
    ) == nil,
    "unknown fuel price must remain unknown"
)

// Geometry, wind and route model.
checkClose(WindMath.normalized(-10), 350, "wind normalization")
checkClose(
    WindMath.headwindComponent(
        windFromDegrees: 0,
        speedKnots: 10,
        courseDegrees: 0
    ),
    10,
    "headwind"
)
checkClose(
    WindMath.headwindComponent(
        windFromDegrees: 180,
        speedKnots: 10,
        courseDegrees: 0
    ),
    -10,
    "tailwind"
)
let midpoint = WindMath.point(
    latitude1: 50,
    longitude1: 8,
    latitude2: 52,
    longitude2: 10,
    fraction: 0.5
)
check(midpoint.latitude > 50.9 && midpoint.latitude < 51.1, "route midpoint latitude")
check(midpoint.longitude > 8.9 && midpoint.longitude < 9.1, "route midpoint longitude")
checkClose(FlightMath.routeMiles(directNM: 100, stopCount: 0), 115, "nonstop route")
checkClose(FlightMath.routeMiles(directNM: 100, stopCount: 1), 135, "one-stop route")
checkClose(FlightMath.routeMiles(directNM: 100, stopCount: 2), 155, "two-stop route")
let tailwindMinutes = FlightMath.adjustedDurationMinutes(
    directNM: 150,
    stopCount: 0,
    headwindKnots: -20
)
let calmMinutes = FlightMath.adjustedDurationMinutes(
    directNM: 150,
    stopCount: 0,
    headwindKnots: 0
)
let headwindMinutes = FlightMath.adjustedDurationMinutes(
    directNM: 150,
    stopCount: 0,
    headwindKnots: 20
)
check(tailwindMinutes < calmMinutes && calmMinutes < headwindMinutes, "wind duration monotonicity")
check(
    FlightMath.adjustedDurationMinutes(directNM: 150, stopCount: 0, headwindKnots: 0)
        < FlightMath.adjustedDurationMinutes(directNM: 150, stopCount: 1, headwindKnots: 0),
    "stop duration monotonicity"
)

// Performance table interpolation.
let climb = ClimbPerformance.a211Default
checkClose(climb.cumulativeTimeMinutes(atPressureAltitudeFeet: 2_000), 3.15, "climb time interpolation")
checkClose(climb.cumulativeDistanceNM(atPressureAltitudeFeet: 2_000), 3.55, "climb distance interpolation")
checkClose(climb.timeMinutes(fromPressureAltitudeFeet: 1_000, toPressureAltitudeFeet: 3_000), 3.3, "climb delta")
let cruise = CruisePerformance(
    powerPercent: 65,
    tasAt1000Feet: 107,
    tasAt3000Feet: 109,
    tasAt5000Feet: 111,
    tasAt7000Feet: 113,
    tasAt10000Feet: 116,
    fuelAt1000FeetPerHour: 21,
    fuelAt3000FeetPerHour: 22,
    fuelAt5000FeetPerHour: 23,
    fuelAt7000FeetPerHour: 24,
    fuelAt10000FeetPerHour: 25
)
checkClose(cruise.tasKnots(atPressureAltitudeFeet: 4_000) ?? -1, 110, "TAS interpolation")
checkClose(cruise.fuelConsumptionPerHour(atPressureAltitudeFeet: 4_000) ?? -1, 22.5, "fuel interpolation")

// Time, altitude and daylight boundary behavior.
check(TimeInput.minutes(from: "09:05") == 545, "colon time input")
check(TimeInput.minutes(from: "0905") == 545, "compact time input")
check(TimeInput.minutes(from: "24:00") == nil, "invalid time input")
check(TimeInput.clock(-1) == "23:59", "clock wrap")
check(TimeInput.displayClock("13:05", usesTwelveHourFormat: true) == "1:05 PM", "12-hour display")
check(
    FlightAltitudeRules.options(forCourseDegrees: 90) == FlightAltitudeRules.allOptions
        && FlightAltitudeRules.recommendedOptions(forCourseDegrees: 90)
            == [2_500, 3_500, 5_500, 7_500, 9_500, 11_500],
    "eastbound selectable and recommended levels"
)
check(
    FlightAltitudeRules.options(forCourseDegrees: 270) == FlightAltitudeRules.allOptions
        && FlightAltitudeRules.recommendedOptions(forCourseDegrees: 270)
            == [2_500, 4_500, 6_500, 8_500, 10_500],
    "westbound selectable and recommended levels"
)

var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(secondsFromGMT: 0)!
let summerDate = utc.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
let solar = SolarCalculator.events(
    forLocalDayContaining: summerDate,
    latitude: 49.9675,
    longitude: 8.1472,
    timeZone: TimeZone(identifier: "Europe/Berlin")!
)
check(solar != nil, "solar events available")
if let solar {
    check(
        solar.civilDawn < solar.sunrise
            && solar.sunrise < solar.sunset
            && solar.sunset < solar.civilDusk,
        "solar event ordering"
    )
}

print("Rechenprüfungen: \(checks)")
if failures.isEmpty {
    print("ERGEBNIS: PASS")
} else {
    failures.forEach { print("FEHLER: \($0)") }
    print("ERGEBNIS: FAIL (\(failures.count) Fehler)")
    exit(1)
}
