import Foundation

enum TimeInput {
    static func filtered(_ input: String) -> String {
        let allowed = input.filter {
            $0.isNumber || $0 == ":"
        }

        return String(allowed.prefix(5))
    }

    static func minutes(from input: String) -> Int? {
        let value = input.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let hour: Int
        let minute: Int

        if value.contains(":") {
            let parts = value.split(
                separator: ":",
                omittingEmptySubsequences: false
            )

            guard
                parts.count == 2,
                let parsedHour = Int(parts[0]),
                let parsedMinute = Int(parts[1])
            else {
                return nil
            }

            hour = parsedHour
            minute = parsedMinute
        } else {
            let digits = value.filter { $0.isNumber }

            guard
                digits.count == 4,
                let parsedHour = Int(digits.prefix(2)),
                let parsedMinute = Int(digits.suffix(2))
            else {
                return nil
            }

            hour = parsedHour
            minute = parsedMinute
        }

        guard
            (0...23).contains(hour),
            (0...59).contains(minute)
        else {
            return nil
        }

        return hour * 60 + minute
    }

    static func clock(_ minutes: Int) -> String {
        let normalized =
            ((minutes % 1440) + 1440) % 1440

        return String(
            format: "%02d:%02d",
            normalized / 60,
            normalized % 60
        )
    }

    static func displayClock(
        _ timeText: String,
        usesTwelveHourFormat: Bool
    ) -> String {
        guard usesTwelveHourFormat,
              let minutes = minutes(from: timeText)
        else {
            return timeText
        }

        let hour24 = minutes / 60
        let minute = minutes % 60
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let period = hour24 < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", hour12, minute, period)
    }
}
