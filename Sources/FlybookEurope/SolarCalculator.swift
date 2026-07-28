import Foundation
import CoreLocation
import SwiftUI

enum LightCondition {
    case daylight
    case civilTwilight
    case night
    case unavailable

    var fillColor: Color {
        switch self {
        case .daylight:
            return Color.white
        case .civilTwilight:
            return Color.yellow.opacity(0.34)
        case .night:
            return Color.red.opacity(0.28)
        case .unavailable:
            return Color.white
        }
    }

    var borderColor: Color {
        switch self {
        case .daylight:
            return FlybookColor.navy
        case .civilTwilight:
            return Color.orange
        case .night:
            return Color.red
        case .unavailable:
            return FlybookColor.muted
        }
    }
}

struct SolarEvents {
    let civilDawn: Date
    let sunrise: Date
    let sunset: Date
    let civilDusk: Date
}

enum SolarCalculator {
    static func lightCondition(
        at instant: Date?,
        latitude: Double?,
        longitude: Double?,
        timeZone: TimeZone
    ) -> LightCondition {
        guard
            let instant,
            let latitude,
            let longitude,
            let events = events(
                forLocalDayContaining: instant,
                latitude: latitude,
                longitude: longitude,
                timeZone: timeZone
            )
        else {
            return .unavailable
        }

        if instant >= events.sunrise && instant < events.sunset {
            return .daylight
        }

        if
            (instant >= events.civilDawn && instant < events.sunrise)
            || (instant >= events.sunset && instant < events.civilDusk)
        {
            return .civilTwilight
        }

        return .night
    }

    static func events(
        forLocalDayContaining instant: Date,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone
    ) -> SolarEvents? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let localParts = calendar.dateComponents(
            [.year, .month, .day],
            from: instant
        )

        guard
            let year = localParts.year,
            let month = localParts.month,
            let day = localParts.day
        else {
            return nil
        }

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        guard let utcMidnight = utcCalendar.date(
            from: DateComponents(
                timeZone: TimeZone(secondsFromGMT: 0),
                year: year,
                month: month,
                day: day,
                hour: 0,
                minute: 0,
                second: 0
            )
        ) else {
            return nil
        }

        let dayOfYear = calendar.ordinality(
            of: .day,
            in: .year,
            for: instant
        ) ?? 1

        guard
            let civilDawnMinutes = eventMinutesUTC(
                dayOfYear: dayOfYear,
                latitude: latitude,
                longitude: longitude,
                zenithDegrees: 96.0,
                sunrise: true
            ),
            let sunriseMinutes = eventMinutesUTC(
                dayOfYear: dayOfYear,
                latitude: latitude,
                longitude: longitude,
                zenithDegrees: 90.833,
                sunrise: true
            ),
            let sunsetMinutes = eventMinutesUTC(
                dayOfYear: dayOfYear,
                latitude: latitude,
                longitude: longitude,
                zenithDegrees: 90.833,
                sunrise: false
            ),
            let civilDuskMinutes = eventMinutesUTC(
                dayOfYear: dayOfYear,
                latitude: latitude,
                longitude: longitude,
                zenithDegrees: 96.0,
                sunrise: false
            )
        else {
            return nil
        }

        return SolarEvents(
            civilDawn: date(
                fromUTCMidnight: utcMidnight,
                minutes: civilDawnMinutes
            ),
            sunrise: date(
                fromUTCMidnight: utcMidnight,
                minutes: sunriseMinutes
            ),
            sunset: date(
                fromUTCMidnight: utcMidnight,
                minutes: sunsetMinutes
            ),
            civilDusk: date(
                fromUTCMidnight: utcMidnight,
                minutes: civilDuskMinutes
            )
        )
    }

    private static func eventMinutesUTC(
        dayOfYear: Int,
        latitude: Double,
        longitude: Double,
        zenithDegrees: Double,
        sunrise: Bool
    ) -> Double? {
        let gamma = 2.0 * Double.pi / 365.0
            * (Double(dayOfYear) - 1.0)

        let equationOfTime = 229.18 * (
            0.000075
            + 0.001868 * cos(gamma)
            - 0.032077 * sin(gamma)
            - 0.014615 * cos(2.0 * gamma)
            - 0.040849 * sin(2.0 * gamma)
        )

        let solarDeclination =
            0.006918
            - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma)
            - 0.006758 * cos(2.0 * gamma)
            + 0.000907 * sin(2.0 * gamma)
            - 0.002697 * cos(3.0 * gamma)
            + 0.00148 * sin(3.0 * gamma)

        let latitudeRadians = latitude * Double.pi / 180.0
        let zenithRadians = zenithDegrees * Double.pi / 180.0

        let cosineHourAngle = (
            cos(zenithRadians)
            / (cos(latitudeRadians) * cos(solarDeclination))
        ) - tan(latitudeRadians) * tan(solarDeclination)

        guard (-1.0...1.0).contains(cosineHourAngle) else {
            return nil
        }

        let hourAngleDegrees =
            acos(cosineHourAngle) * 180.0 / Double.pi

        let solarNoonUTC =
            720.0 - 4.0 * longitude - equationOfTime

        return sunrise
            ? solarNoonUTC - 4.0 * hourAngleDegrees
            : solarNoonUTC + 4.0 * hourAngleDegrees
    }

    private static func date(
        fromUTCMidnight midnight: Date,
        minutes: Double
    ) -> Date {
        midnight.addingTimeInterval(minutes * 60.0)
    }
}

enum DestinationTimeZone {
    static let edfz = TimeZone(identifier: "Europe/Berlin")!

    static func value(
        for destination: Destination,
        weatherTimeZone: String?
    ) -> TimeZone {
        if
            let weatherTimeZone,
            let zone = TimeZone(identifier: weatherTimeZone)
        {
            return zone
        }

        let identifier: String

        switch destination.country.uppercased() {
        case "AT":
            identifier = "Europe/Vienna"
        case "BE":
            identifier = "Europe/Brussels"
        case "CH":
            identifier = "Europe/Zurich"
        case "CZ":
            identifier = "Europe/Prague"
        case "DE":
            identifier = "Europe/Berlin"
        case "DK":
            identifier = "Europe/Copenhagen"
        case "FR":
            identifier = "Europe/Paris"
        case "HR":
            identifier = "Europe/Zagreb"
        case "HU":
            identifier = "Europe/Budapest"
        case "IT":
            identifier = "Europe/Rome"
        case "NL":
            identifier = "Europe/Amsterdam"
        case "NO":
            identifier = "Europe/Oslo"
        case "PL":
            identifier = "Europe/Warsaw"
        case "SE":
            identifier = "Europe/Stockholm"
        case "SI":
            identifier = "Europe/Ljubljana"
        default:
            identifier = "Europe/Berlin"
        }

        return TimeZone(identifier: identifier) ?? edfz
    }
}

enum FlightDateTime {
    static let edfzLatitude = 49.9675
    static let edfzLongitude = 8.1472

    static func instant(
        date: Date,
        timeText: String,
        timeZone: TimeZone
    ) -> Date? {
        guard let minutes = TimeInput.minutes(from: timeText) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var parts = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        parts.second = 0
        parts.timeZone = timeZone

        return calendar.date(from: parts)
    }

    static func clock(
        instant: Date?,
        timeZone: TimeZone
    ) -> String {
        guard let instant else {
            return "—"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: instant)
    }
}
