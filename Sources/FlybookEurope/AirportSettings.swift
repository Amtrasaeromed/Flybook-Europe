import SwiftUI

enum AirportClosingReference: String, Codable, CaseIterable, Identifiable {
    case fixed = "Feste Uhrzeit"
    case sunset = "Sonnenuntergang"
    case civilDusk = "Ende bürgerliche Dämmerung (ECET)"

    var id: String { rawValue }
}

enum AirportOpeningReference: String, Codable, CaseIterable, Identifiable {
    case fixed = "Feste Uhrzeit"
    case sunrise = "Sonnenaufgang"

    var id: String { rawValue }
}

struct AirportOpeningPeriod: Codable, Equatable {
    var fromUTC = ""
    var openingReference: AirportOpeningReference?
    var sunriseOffsetMinutes: Int?
    var closingReference = AirportClosingReference.sunset
    var fixedUntilUTC = ""
    var sunsetOffsetMinutes = 0
    var latestUTC = ""
    var landingUntilUTC: String?
    var secondFromUTC: String?
    var secondClosingReference: AirportClosingReference?
    var secondFixedUntilUTC: String?
    var secondSunsetOffsetMinutes: Int?
    var secondLatestUTC: String?
    var departureClosedFromUTC: String?
    var departureClosedUntilUTC: String?
}

struct AirportSeasonHours: Codable, Equatable {
    var monday = AirportOpeningPeriod()
    var tuesday = AirportOpeningPeriod()
    var wednesday = AirportOpeningPeriod()
    var thursday = AirportOpeningPeriod()
    var friday = AirportOpeningPeriod()
    var saturday = AirportOpeningPeriod()
    var sunday = AirportOpeningPeriod()
    var holiday = AirportOpeningPeriod()
    var outsideHoursPPR = false

    init(
        monday: AirportOpeningPeriod = AirportOpeningPeriod(),
        tuesday: AirportOpeningPeriod = AirportOpeningPeriod(),
        wednesday: AirportOpeningPeriod = AirportOpeningPeriod(),
        thursday: AirportOpeningPeriod = AirportOpeningPeriod(),
        friday: AirportOpeningPeriod = AirportOpeningPeriod(),
        saturday: AirportOpeningPeriod = AirportOpeningPeriod(),
        sunday: AirportOpeningPeriod = AirportOpeningPeriod(),
        holiday: AirportOpeningPeriod = AirportOpeningPeriod(),
        outsideHoursPPR: Bool = false
    ) {
        self.monday = monday
        self.tuesday = tuesday
        self.wednesday = wednesday
        self.thursday = thursday
        self.friday = friday
        self.saturday = saturday
        self.sunday = sunday
        self.holiday = holiday
        self.outsideHoursPPR = outsideHoursPPR
    }

    private enum CodingKeys: String, CodingKey {
        case monday, tuesday, wednesday, thursday, friday, saturday, sunday, holiday
        case weekdays, weekendsAndHolidays, outsideHoursPPR
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let oldWeekday = try values.decodeIfPresent(AirportOpeningPeriod.self, forKey: .weekdays) ?? AirportOpeningPeriod()
        let oldWeekend = try values.decodeIfPresent(AirportOpeningPeriod.self, forKey: .weekendsAndHolidays) ?? AirportOpeningPeriod()
        monday = try values.decodeIfPresent(AirportOpeningPeriod.self, forKey: .monday) ?? oldWeekday
        tuesday = try values.decodeIfPresent(AirportOpeningPeriod.self, forKey: .tuesday) ?? oldWeekday
        wednesday = try values.decodeIfPresent(AirportOpeningPeriod.self, forKey: .wednesday) ?? oldWeekday
        thursday = try values.decodeIfPresent(AirportOpeningPeriod.self, forKey: .thursday) ?? oldWeekday
        friday = try values.decodeIfPresent(AirportOpeningPeriod.self, forKey: .friday) ?? oldWeekday
        saturday = try values.decodeIfPresent(AirportOpeningPeriod.self, forKey: .saturday) ?? oldWeekend
        sunday = try values.decodeIfPresent(AirportOpeningPeriod.self, forKey: .sunday) ?? oldWeekend
        holiday = try values.decodeIfPresent(AirportOpeningPeriod.self, forKey: .holiday) ?? oldWeekend
        outsideHoursPPR = try values.decodeIfPresent(Bool.self, forKey: .outsideHoursPPR) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(monday, forKey: .monday)
        try values.encode(tuesday, forKey: .tuesday)
        try values.encode(wednesday, forKey: .wednesday)
        try values.encode(thursday, forKey: .thursday)
        try values.encode(friday, forKey: .friday)
        try values.encode(saturday, forKey: .saturday)
        try values.encode(sunday, forKey: .sunday)
        try values.encode(holiday, forKey: .holiday)
        try values.encode(outsideHoursPPR, forKey: .outsideHoursPPR)
    }
}

struct AirportDateRule: Codable, Equatable, Identifiable {
    var id: String {
        "\(startMonth)-\(startDay)-\(endMonth)-\(endDay)-\(label)-"
            + String(appliesDuringDaylightSavingTime ?? false)
    }
    var startMonth: Int
    var startDay: Int
    var endMonth: Int
    var endDay: Int
    var label: String
    var period = AirportOpeningPeriod()
    var seasonHours: AirportSeasonHours? = nil
    var appliesDuringDaylightSavingTime: Bool? = nil
    var summary: String? = nil
}

struct AirportOpeningHoursProfile: Codable, Equatable {
    var summer = AirportSeasonHours()
    var winter = AirportSeasonHours()
    var dateRules: [AirportDateRule]?

    static let edfz = AirportOpeningHoursProfile(
        summer: AirportSeasonHours(
            monday: AirportOpeningPeriod(
                fromUTC: "06:00",
                closingReference: .sunset,
                fixedUntilUTC: "",
                sunsetOffsetMinutes: 0,
                latestUTC: "18:00"
            ),
            tuesday: AirportOpeningPeriod(fromUTC: "06:00", closingReference: .sunset, latestUTC: "18:00"),
            wednesday: AirportOpeningPeriod(fromUTC: "06:00", closingReference: .sunset, latestUTC: "18:00"),
            thursday: AirportOpeningPeriod(fromUTC: "06:00", closingReference: .sunset, latestUTC: "18:00"),
            friday: AirportOpeningPeriod(fromUTC: "06:00", closingReference: .sunset, latestUTC: "18:00"),
            saturday: AirportOpeningPeriod(
                fromUTC: "07:00",
                closingReference: .sunset,
                fixedUntilUTC: "",
                sunsetOffsetMinutes: 0,
                latestUTC: "18:00"
            ),
            sunday: AirportOpeningPeriod(fromUTC: "07:00", closingReference: .sunset, latestUTC: "18:00"),
            holiday: AirportOpeningPeriod(fromUTC: "07:00", closingReference: .sunset, latestUTC: "18:00"),
            outsideHoursPPR: true
        ),
        winter: AirportSeasonHours(
            monday: AirportOpeningPeriod(
                fromUTC: "08:00",
                closingReference: .sunset,
                fixedUntilUTC: "",
                sunsetOffsetMinutes: 0,
                latestUTC: "19:00"
            ),
            tuesday: AirportOpeningPeriod(fromUTC: "08:00", closingReference: .sunset, latestUTC: "19:00"),
            wednesday: AirportOpeningPeriod(fromUTC: "08:00", closingReference: .sunset, latestUTC: "19:00"),
            thursday: AirportOpeningPeriod(fromUTC: "08:00", closingReference: .sunset, latestUTC: "19:00"),
            friday: AirportOpeningPeriod(fromUTC: "08:00", closingReference: .sunset, latestUTC: "19:00"),
            saturday: AirportOpeningPeriod(fromUTC: "08:00", closingReference: .sunset, latestUTC: "19:00"),
            sunday: AirportOpeningPeriod(fromUTC: "08:00", closingReference: .sunset, latestUTC: "19:00"),
            holiday: AirportOpeningPeriod(fromUTC: "08:00", closingReference: .sunset, latestUTC: "19:00"),
            outsideHoursPPR: true
        )
    )

    static let edfu = AirportOpeningHoursProfile(
        summer: AirportSeasonHours(
            monday: AirportOpeningPeriod(),
            tuesday: AirportOpeningPeriod(fromUTC: "11:00", closingReference: .fixed, fixedUntilUTC: "15:00"),
            wednesday: AirportOpeningPeriod(fromUTC: "11:00", closingReference: .fixed, fixedUntilUTC: "15:00"),
            thursday: AirportOpeningPeriod(fromUTC: "11:00", closingReference: .fixed, fixedUntilUTC: "15:00"),
            friday: AirportOpeningPeriod(fromUTC: "12:00", closingReference: .fixed, fixedUntilUTC: "16:00"),
            saturday: AirportOpeningPeriod(fromUTC: "08:00", closingReference: .fixed, fixedUntilUTC: "16:00"),
            sunday: AirportOpeningPeriod(fromUTC: "08:00", closingReference: .fixed, fixedUntilUTC: "16:00"),
            holiday: AirportOpeningPeriod(fromUTC: "08:00", closingReference: .fixed, fixedUntilUTC: "16:00"),
            outsideHoursPPR: true
        ),
        winter: AirportSeasonHours(outsideHoursPPR: true)
    )

    static let edtm: AirportOpeningHoursProfile = {
        let summerPeriod = AirportOpeningPeriod(
            fromUTC: "07:00",
            closingReference: .sunset,
            sunsetOffsetMinutes: 30,
            latestUTC: "18:00"
        )
        let winterPeriod = AirportOpeningPeriod(
            fromUTC: "08:00",
            closingReference: .sunset,
            sunsetOffsetMinutes: 30,
            latestUTC: "19:00"
        )
        return AirportOpeningHoursProfile(
            summer: AirportSeasonHours(
                monday: summerPeriod, tuesday: summerPeriod,
                wednesday: summerPeriod, thursday: summerPeriod,
                friday: summerPeriod, saturday: summerPeriod,
                sunday: summerPeriod, holiday: summerPeriod,
                outsideHoursPPR: true
            ),
            winter: AirportSeasonHours(
                monday: winterPeriod, tuesday: winterPeriod,
                wednesday: winterPeriod, thursday: winterPeriod,
                friday: winterPeriod, saturday: winterPeriod,
                sunday: winterPeriod, holiday: winterPeriod,
                outsideHoursPPR: true
            )
        )
    }()

    static let edqh: AirportOpeningHoursProfile = {
        let summerPeriod = AirportOpeningPeriod(
            fromUTC: "07:00",
            closingReference: .sunset,
            sunsetOffsetMinutes: 30,
            latestUTC: "18:30"
        )
        let winterPeriod = AirportOpeningPeriod(
            fromUTC: "08:00",
            closingReference: .sunset,
            sunsetOffsetMinutes: 30
        )
        return AirportOpeningHoursProfile(
            summer: AirportSeasonHours(
                monday: summerPeriod, tuesday: summerPeriod,
                wednesday: summerPeriod, thursday: summerPeriod,
                friday: summerPeriod, saturday: summerPeriod,
                sunday: summerPeriod, holiday: summerPeriod,
                outsideHoursPPR: true
            ),
            winter: AirportSeasonHours(
                monday: winterPeriod, tuesday: winterPeriod,
                wednesday: winterPeriod, thursday: winterPeriod,
                friday: winterPeriod, saturday: winterPeriod,
                sunday: winterPeriod, holiday: winterPeriod,
                outsideHoursPPR: true
            )
        )
    }()

    static let edka: AirportOpeningHoursProfile = {
        let summer = AirportOpeningPeriod(
            fromUTC: "07:00",
            closingReference: .sunset,
            sunsetOffsetMinutes: 30,
            latestUTC: "18:30"
        )
        let winter = AirportOpeningPeriod(
            fromUTC: "08:00",
            closingReference: .sunset,
            sunsetOffsetMinutes: 30
        )
        return AirportOpeningHoursProfile(
            summer: AirportSeasonHours(
                monday: summer, tuesday: summer, wednesday: summer,
                thursday: summer, friday: summer, saturday: summer,
                sunday: summer, holiday: summer, outsideHoursPPR: true
            ),
            winter: AirportSeasonHours(
                monday: winter, tuesday: winter, wednesday: winter,
                thursday: winter, friday: winter, saturday: winter,
                sunday: winter, holiday: winter, outsideHoursPPR: true
            )
        )
    }()

    static let ehmz: AirportOpeningHoursProfile = {
        let summer = AirportOpeningPeriod(
            fromUTC: "07:00",
            closingReference: .fixed,
            fixedUntilUTC: "18:00"
        )
        let winter = AirportOpeningPeriod(
            fromUTC: "08:00",
            closingReference: .fixed,
            fixedUntilUTC: "19:00"
        )
        return AirportOpeningHoursProfile(
            summer: AirportSeasonHours(
                monday: summer, tuesday: summer, wednesday: summer,
                thursday: summer, friday: summer, saturday: summer,
                sunday: summer, holiday: summer
            ),
            winter: AirportSeasonHours(
                monday: winter, tuesday: winter, wednesday: winter,
                thursday: winter, friday: winter, saturday: winter,
                sunday: winter, holiday: winter
            )
        )
    }()

    static let ehtx: AirportOpeningHoursProfile = {
        let summerWeekday = AirportOpeningPeriod(
            fromUTC: "07:00",
            closingReference: .fixed,
            fixedUntilUTC: "17:00"
        )
        let summerSundayHoliday = AirportOpeningPeriod(
            fromUTC: "08:00",
            closingReference: .fixed,
            fixedUntilUTC: "17:00"
        )
        let winterWeekday = AirportOpeningPeriod(
            fromUTC: "08:00",
            closingReference: .fixed,
            fixedUntilUTC: "18:00"
        )
        let winterSundayHoliday = AirportOpeningPeriod(
            fromUTC: "09:00",
            closingReference: .fixed,
            fixedUntilUTC: "18:00"
        )
        return AirportOpeningHoursProfile(
            summer: AirportSeasonHours(
                monday: summerWeekday, tuesday: summerWeekday,
                wednesday: summerWeekday, thursday: summerWeekday,
                friday: summerWeekday, saturday: summerWeekday,
                sunday: summerSundayHoliday, holiday: summerSundayHoliday
            ),
            winter: AirportSeasonHours(
                monday: winterWeekday, tuesday: winterWeekday,
                wednesday: winterWeekday, thursday: winterWeekday,
                friday: winterWeekday, saturday: winterWeekday,
                sunday: winterSundayHoliday, holiday: winterSundayHoliday
            )
        )
    }()

    static let ehal: AirportOpeningHoursProfile = {
        let summer = AirportOpeningPeriod(
            fromUTC: "07:30",
            closingReference: .fixed,
            fixedUntilUTC: "16:00"
        )
        return AirportOpeningHoursProfile(
            summer: AirportSeasonHours(outsideHoursPPR: true),
            winter: AirportSeasonHours(outsideHoursPPR: true),
            dateRules: [
                AirportDateRule(
                    startMonth: 4, startDay: 1,
                    endMonth: 10, endDay: 30,
                    label: "UDP 1 · 1. Apr.–30. Okt.",
                    period: summer,
                    summary: "0730–1600 UTC regulär; 1600–1700 UTC PPR"
                )
            ]
        )
    }()

    static let edwj: AirportOpeningHoursProfile = {
        let summer = AirportOpeningPeriod(
            fromUTC: "05:30",
            closingReference: .sunset,
            sunsetOffsetMinutes: 30,
            latestUTC: "17:30"
        )
        let winterWeekday = AirportOpeningPeriod(
            fromUTC: "07:00",
            openingReference: .sunrise,
            sunriseOffsetMinutes: -30,
            closingReference: .fixed,
            fixedUntilUTC: "11:30",
            secondFromUTC: "13:00",
            secondClosingReference: .sunset,
            secondSunsetOffsetMinutes: 30,
            secondLatestUTC: "16:30"
        )
        let winterWeekendHoliday = AirportOpeningPeriod(
            fromUTC: "07:30",
            closingReference: .sunset,
            sunsetOffsetMinutes: 30,
            latestUTC: "16:30"
        )
        return AirportOpeningHoursProfile(
            summer: AirportSeasonHours(
                monday: summer, tuesday: summer, wednesday: summer,
                thursday: summer, friday: summer, saturday: summer,
                sunday: summer, holiday: summer, outsideHoursPPR: true
            ),
            winter: AirportSeasonHours(
                monday: winterWeekday, tuesday: winterWeekday,
                wednesday: winterWeekday, thursday: winterWeekday,
                friday: winterWeekday, saturday: winterWeekendHoliday,
                sunday: winterWeekendHoliday, holiday: winterWeekendHoliday,
                outsideHoursPPR: true
            )
        )
    }()

    static let edwy: AirportOpeningHoursProfile = {
        let summer = AirportOpeningPeriod(
            fromUTC: "06:00",
            closingReference: .fixed,
            fixedUntilUTC: "17:00"
        )
        let winter = AirportOpeningPeriod(
            fromUTC: "08:00",
            closingReference: .fixed,
            fixedUntilUTC: "15:00"
        )
        func season(_ period: AirportOpeningPeriod) -> AirportSeasonHours {
            AirportSeasonHours(
                monday: period, tuesday: period, wednesday: period,
                thursday: period, friday: period, saturday: period,
                sunday: period, holiday: period, outsideHoursPPR: true
            )
        }
        return AirportOpeningHoursProfile(
            summer: season(summer),
            winter: season(winter),
            dateRules: [
                AirportDateRule(
                    startMonth: 10, startDay: 1, endMonth: 11, endDay: 14,
                    label: "1. Okt.–14. Nov.",
                    period: AirportOpeningPeriod(
                        fromUTC: "07:00", closingReference: .fixed, fixedUntilUTC: "14:00"
                    )
                ),
                AirportDateRule(
                    startMonth: 11, startDay: 15, endMonth: 11, endDay: 15,
                    label: "15. Nov.",
                    period: AirportOpeningPeriod(
                        fromUTC: "08:00", closingReference: .fixed, fixedUntilUTC: "15:00"
                    )
                ),
                AirportDateRule(
                    startMonth: 11, startDay: 16, endMonth: 2, endDay: 28,
                    label: "16. Nov.–28. Feb.",
                    period: AirportOpeningPeriod(
                        fromUTC: "08:00", closingReference: .fixed, fixedUntilUTC: "12:30"
                    )
                )
            ]
        )
    }()

    static let edwl: AirportOpeningHoursProfile = {
        let summer = AirportOpeningPeriod(
            fromUTC: "07:00",
            closingReference: .fixed,
            fixedUntilUTC: "11:00",
            secondFromUTC: "13:00",
            secondClosingReference: .fixed,
            secondFixedUntilUTC: "17:00"
        )
        return AirportOpeningHoursProfile(
            summer: AirportSeasonHours(
                monday: summer, tuesday: summer, wednesday: summer,
                thursday: summer, friday: summer, saturday: summer,
                sunday: summer, holiday: summer, outsideHoursPPR: true
            ),
            winter: AirportSeasonHours(outsideHoursPPR: true)
        )
    }()

    static let edwg: AirportOpeningHoursProfile = {
        let summer = AirportOpeningPeriod(
            fromUTC: "06:00",
            closingReference: .fixed,
            fixedUntilUTC: "10:00",
            landingUntilUTC: "11:00",
            secondFromUTC: "13:00",
            secondClosingReference: .sunset,
            secondSunsetOffsetMinutes: 0,
            secondLatestUTC: "17:00"
        )
        let winter = AirportOpeningPeriod(
            fromUTC: "08:00",
            closingReference: .fixed,
            fixedUntilUTC: "11:00",
            landingUntilUTC: "12:00",
            secondFromUTC: "14:00",
            secondClosingReference: .sunset,
            secondSunsetOffsetMinutes: 0
        )
        func season(_ period: AirportOpeningPeriod) -> AirportSeasonHours {
            AirportSeasonHours(
                monday: period, tuesday: period, wednesday: period,
                thursday: period, friday: period, saturday: period,
                sunday: period, holiday: period, outsideHoursPPR: true
            )
        }
        return AirportOpeningHoursProfile(
            summer: season(summer),
            winter: season(winter)
        )
    }()

    static let edwf: AirportOpeningHoursProfile = {
        let summerWeekday = AirportOpeningPeriod(
            fromUTC: "06:00",
            closingReference: .sunset,
            sunsetOffsetMinutes: 0,
            latestUTC: "17:00"
        )
        let summerWeekendHoliday = AirportOpeningPeriod(
            fromUTC: "07:00",
            closingReference: .sunset,
            sunsetOffsetMinutes: 0,
            latestUTC: "17:00"
        )
        let winterWeekday = AirportOpeningPeriod(
            fromUTC: "07:00",
            closingReference: .sunset,
            sunsetOffsetMinutes: 0
        )
        let winterWeekendHoliday = AirportOpeningPeriod(
            fromUTC: "08:00",
            closingReference: .sunset,
            sunsetOffsetMinutes: 0
        )
        return AirportOpeningHoursProfile(
            summer: AirportSeasonHours(
                monday: summerWeekday, tuesday: summerWeekday,
                wednesday: summerWeekday, thursday: summerWeekday,
                friday: summerWeekday, saturday: summerWeekendHoliday,
                sunday: summerWeekendHoliday, holiday: summerWeekendHoliday,
                outsideHoursPPR: true
            ),
            winter: AirportSeasonHours(
                monday: winterWeekday, tuesday: winterWeekday,
                wednesday: winterWeekday, thursday: winterWeekday,
                friday: winterWeekday, saturday: winterWeekendHoliday,
                sunday: winterWeekendHoliday, holiday: winterWeekendHoliday,
                outsideHoursPPR: true
            )
        )
    }()

    static let edxe: AirportOpeningHoursProfile = {
        let weekday = AirportOpeningPeriod(
            fromUTC: "11:00",
            closingReference: .fixed,
            fixedUntilUTC: "17:00"
        )
        let weekendHoliday = AirportOpeningPeriod(
            fromUTC: "08:00",
            closingReference: .fixed,
            fixedUntilUTC: "17:00"
        )
        return AirportOpeningHoursProfile(
            summer: AirportSeasonHours(
                monday: AirportOpeningPeriod(),
                tuesday: weekday,
                wednesday: weekday,
                thursday: weekday,
                friday: weekday,
                saturday: weekendHoliday,
                sunday: weekendHoliday,
                holiday: weekendHoliday,
                outsideHoursPPR: true
            ),
            winter: AirportSeasonHours(outsideHoursPPR: true)
        )
    }()

    static let edlm: AirportOpeningHoursProfile = {
        let summer = AirportOpeningPeriod(
            fromUTC: "06:00",
            closingReference: .sunset,
            sunsetOffsetMinutes: 30,
            latestUTC: "20:00"
        )
        let winter = AirportOpeningPeriod(
            fromUTC: "07:30",
            closingReference: .sunset,
            sunsetOffsetMinutes: 30
        )
        func season(_ period: AirportOpeningPeriod) -> AirportSeasonHours {
            AirportSeasonHours(
                monday: period,
                tuesday: period,
                wednesday: period,
                thursday: period,
                friday: period,
                saturday: period,
                sunday: period,
                holiday: period,
                outsideHoursPPR: true
            )
        }
        return AirportOpeningHoursProfile(
            summer: season(summer),
            winter: season(winter)
        )
    }()

    static let edls: AirportOpeningHoursProfile = {
        let summer = AirportOpeningPeriod(
            fromUTC: "07:00",
            closingReference: .sunset,
            sunsetOffsetMinutes: 0,
            latestUTC: "19:00"
        )
        let winter = AirportOpeningPeriod(
            fromUTC: "08:00",
            closingReference: .sunset,
            sunsetOffsetMinutes: 0
        )
        func season(_ period: AirportOpeningPeriod) -> AirportSeasonHours {
            AirportSeasonHours(
                monday: period,
                tuesday: period,
                wednesday: period,
                thursday: period,
                friday: period,
                saturday: period,
                sunday: period,
                holiday: period,
                outsideHoursPPR: true
            )
        }
        return AirportOpeningHoursProfile(
            summer: season(summer),
            winter: season(winter)
        )
    }()

    static let edtf: AirportOpeningHoursProfile = {
        let summer = AirportOpeningPeriod(
            fromUTC: "06:00",
            closingReference: .sunset,
            sunsetOffsetMinutes: 30,
            latestUTC: "18:00"
        )
        let winter = AirportOpeningPeriod(
            fromUTC: "07:00",
            closingReference: .sunset,
            sunsetOffsetMinutes: 30
        )
        func season(_ period: AirportOpeningPeriod) -> AirportSeasonHours {
            AirportSeasonHours(
                monday: period, tuesday: period, wednesday: period,
                thursday: period, friday: period, saturday: period,
                sunday: period, holiday: period, outsideHoursPPR: true
            )
        }
        return AirportOpeningHoursProfile(
            summer: season(summer),
            winter: season(winter)
        )
    }()

    static let edtg: AirportOpeningHoursProfile = {
        let summerWeekday = AirportOpeningPeriod(
            fromUTC: "07:30",
            closingReference: .sunset,
            sunsetOffsetMinutes: 30,
            latestUTC: "18:00"
        )
        let summerWeekendHoliday = AirportOpeningPeriod(
            fromUTC: "07:30",
            closingReference: .sunset,
            sunsetOffsetMinutes: 30,
            latestUTC: "17:00",
            departureClosedFromUTC: "11:00",
            departureClosedUntilUTC: "12:00"
        )
        let winterWeekday = AirportOpeningPeriod(
            fromUTC: "08:30",
            closingReference: .sunset,
            sunsetOffsetMinutes: 30
        )
        let winterWeekendHoliday = AirportOpeningPeriod(
            fromUTC: "08:30",
            closingReference: .sunset,
            sunsetOffsetMinutes: 30,
            latestUTC: "18:00",
            departureClosedFromUTC: "12:00",
            departureClosedUntilUTC: "13:00"
        )
        return AirportOpeningHoursProfile(
            summer: AirportSeasonHours(
                monday: summerWeekday, tuesday: summerWeekday,
                wednesday: summerWeekday, thursday: summerWeekday,
                friday: summerWeekday, saturday: summerWeekendHoliday,
                sunday: summerWeekendHoliday, holiday: summerWeekendHoliday,
                outsideHoursPPR: true
            ),
            winter: AirportSeasonHours(
                monday: winterWeekday, tuesday: winterWeekday,
                wednesday: winterWeekday, thursday: winterWeekday,
                friday: winterWeekday, saturday: winterWeekendHoliday,
                sunday: winterWeekendHoliday, holiday: winterWeekendHoliday,
                outsideHoursPPR: true
            )
        )
    }()

    static let edts: AirportOpeningHoursProfile = {
        let summer = AirportOpeningPeriod(
            fromUTC: "07:00",
            closingReference: .sunset,
            latestUTC: "18:00"
        )
        let winterWeekday = AirportOpeningPeriod(
            fromUTC: "10:00",
            closingReference: .sunset
        )
        let winterWeekendHoliday = AirportOpeningPeriod(
            fromUTC: "08:00",
            closingReference: .sunset
        )
        return AirportOpeningHoursProfile(
            summer: AirportSeasonHours(
                monday: summer, tuesday: summer, wednesday: summer,
                thursday: summer, friday: summer, saturday: summer,
                sunday: summer, holiday: summer, outsideHoursPPR: true
            ),
            winter: AirportSeasonHours(
                monday: winterWeekday, tuesday: winterWeekday,
                wednesday: winterWeekday, thursday: winterWeekday,
                friday: winterWeekday, saturday: winterWeekendHoliday,
                sunday: winterWeekendHoliday, holiday: winterWeekendHoliday,
                outsideHoursPPR: true
            )
        )
    }()

    static let edfe: AirportOpeningHoursProfile = {
        let summer = AirportOpeningPeriod(
            fromUTC: "06:00",
            closingReference: .civilDusk,
            latestUTC: "19:00"
        )
        let winter = AirportOpeningPeriod(
            fromUTC: "07:00",
            closingReference: .civilDusk
        )
        func season(_ period: AirportOpeningPeriod) -> AirportSeasonHours {
            AirportSeasonHours(
                monday: period, tuesday: period, wednesday: period,
                thursday: period, friday: period, saturday: period,
                sunday: period, holiday: period, outsideHoursPPR: true
            )
        }
        return AirportOpeningHoursProfile(
            summer: season(summer),
            winter: season(winter)
        )
    }()

    static let edfm: AirportOpeningHoursProfile = {
        let summerWeekday = AirportOpeningPeriod(
            fromUTC: "04:00", closingReference: .fixed,
            fixedUntilUTC: "19:00"
        )
        let summerWeekendHoliday = AirportOpeningPeriod(
            fromUTC: "06:00", closingReference: .fixed,
            fixedUntilUTC: "18:00"
        )
        let winterWeekday = AirportOpeningPeriod(
            fromUTC: "05:00", closingReference: .fixed,
            fixedUntilUTC: "20:00"
        )
        let winterWeekendHoliday = AirportOpeningPeriod(
            fromUTC: "07:00", closingReference: .fixed,
            fixedUntilUTC: "19:00"
        )
        return AirportOpeningHoursProfile(
            summer: AirportSeasonHours(
                monday: summerWeekday, tuesday: summerWeekday,
                wednesday: summerWeekday, thursday: summerWeekday,
                friday: summerWeekday, saturday: summerWeekendHoliday,
                sunday: summerWeekendHoliday, holiday: summerWeekendHoliday,
                outsideHoursPPR: true
            ),
            winter: AirportSeasonHours(
                monday: winterWeekday, tuesday: winterWeekday,
                wednesday: winterWeekday, thursday: winterWeekday,
                friday: winterWeekday, saturday: winterWeekendHoliday,
                sunday: winterWeekendHoliday, holiday: winterWeekendHoliday,
                outsideHoursPPR: true
            )
        )
    }()

    static let edry: AirportOpeningHoursProfile = {
        let summerWeekday = AirportOpeningPeriod(
            fromUTC: "05:00", closingReference: .fixed,
            fixedUntilUTC: "18:00"
        )
        let summerWeekendHoliday = AirportOpeningPeriod(
            fromUTC: "07:00", closingReference: .fixed,
            fixedUntilUTC: "18:00"
        )
        let winterWeekday = AirportOpeningPeriod(
            fromUTC: "06:00", closingReference: .fixed,
            fixedUntilUTC: "19:00"
        )
        let winterWeekendHoliday = AirportOpeningPeriod(
            fromUTC: "08:00", closingReference: .sunset,
            sunsetOffsetMinutes: 30
        )
        return AirportOpeningHoursProfile(
            summer: AirportSeasonHours(
                monday: summerWeekday, tuesday: summerWeekday,
                wednesday: summerWeekday, thursday: summerWeekday,
                friday: summerWeekday, saturday: summerWeekendHoliday,
                sunday: summerWeekendHoliday, holiday: summerWeekendHoliday,
                outsideHoursPPR: true
            ),
            winter: AirportSeasonHours(
                monday: winterWeekday, tuesday: winterWeekday,
                wednesday: winterWeekday, thursday: winterWeekday,
                friday: winterWeekday, saturday: winterWeekendHoliday,
                sunday: winterWeekendHoliday, holiday: winterWeekendHoliday,
                outsideHoursPPR: true
            )
        )
    }()

    static let edrk: AirportOpeningHoursProfile = {
        let summerWeekday = AirportOpeningPeriod(
            fromUTC: "06:00", closingReference: .sunset,
            sunsetOffsetMinutes: 30, latestUTC: "19:00"
        )
        let summerWeekendHoliday = AirportOpeningPeriod(
            fromUTC: "07:00", closingReference: .sunset,
            sunsetOffsetMinutes: 30, latestUTC: "19:00"
        )
        let winterShoulderWeekday = AirportOpeningPeriod(
            fromUTC: "07:00", closingReference: .sunset,
            sunsetOffsetMinutes: 30
        )
        let winterShoulderWeekendHoliday = AirportOpeningPeriod(
            fromUTC: "08:00", closingReference: .sunset,
            sunsetOffsetMinutes: 30
        )
        let deepWinter = AirportOpeningPeriod(
            fromUTC: "08:00", closingReference: .sunset,
            sunsetOffsetMinutes: 30
        )
        let summerHours = AirportSeasonHours(
            monday: summerWeekday, tuesday: summerWeekday,
            wednesday: summerWeekday, thursday: summerWeekday,
            friday: summerWeekday, saturday: summerWeekendHoliday,
            sunday: summerWeekendHoliday, holiday: summerWeekendHoliday,
            outsideHoursPPR: true
        )
        let winterShoulderHours = AirportSeasonHours(
            monday: winterShoulderWeekday, tuesday: winterShoulderWeekday,
            wednesday: winterShoulderWeekday, thursday: winterShoulderWeekday,
            friday: winterShoulderWeekday,
            saturday: winterShoulderWeekendHoliday,
            sunday: winterShoulderWeekendHoliday,
            holiday: winterShoulderWeekendHoliday,
            outsideHoursPPR: true
        )
        let deepWinterHours = AirportSeasonHours(
            monday: deepWinter, tuesday: deepWinter,
            wednesday: deepWinter, thursday: deepWinter,
            friday: deepWinter, saturday: deepWinter,
            sunday: deepWinter, holiday: deepWinter,
            outsideHoursPPR: true
        )
        return AirportOpeningHoursProfile(
            summer: summerHours,
            winter: deepWinterHours,
            dateRules: [
                AirportDateRule(
                    startMonth: 3, startDay: 1,
                    endMonth: 10, endDay: 31,
                    label: "SUM · 1. Mär.–31. Okt.",
                    seasonHours: summerHours,
                    appliesDuringDaylightSavingTime: true,
                    summary: "Mo–Fr 0600–SS+30/1900; Sa, So, HOL 0700–SS+30/1900"
                ),
                AirportDateRule(
                    startMonth: 3, startDay: 1,
                    endMonth: 10, endDay: 31,
                    label: "WIN · 1. Mär.–31. Okt.",
                    seasonHours: winterShoulderHours,
                    appliesDuringDaylightSavingTime: false,
                    summary: "Mo–Fr 0700–SS+30; Sa, So, HOL 0800–SS+30"
                ),
                AirportDateRule(
                    startMonth: 11, startDay: 1,
                    endMonth: 2, endDay: 29,
                    label: "1. Nov.–28/29. Feb.",
                    seasonHours: deepWinterHours,
                    appliesDuringDaylightSavingTime: false,
                    summary: "täglich 0800–SS+30"
                )
            ]
        )
    }()

    static let edgs: AirportOpeningHoursProfile = {
        let summerEdgeWeekday = AirportOpeningPeriod(
            fromUTC: "06:00", closingReference: .fixed,
            fixedUntilUTC: "18:00"
        )
        let summerEdgeWeekendHoliday = AirportOpeningPeriod(
            fromUTC: "06:00", closingReference: .sunset,
            sunsetOffsetMinutes: 30
        )
        let summerCore = AirportOpeningPeriod(
            fromUTC: "06:00", closingReference: .fixed,
            fixedUntilUTC: "18:00"
        )
        let winterEdgeWeekday = AirportOpeningPeriod(
            fromUTC: "07:00", closingReference: .fixed,
            fixedUntilUTC: "19:00"
        )
        let winterEdgeWeekendHoliday = AirportOpeningPeriod(
            fromUTC: "07:00", closingReference: .sunset,
            sunsetOffsetMinutes: 30
        )
        let deepWinterWeekday = AirportOpeningPeriod(
            fromUTC: "08:00", closingReference: .fixed,
            fixedUntilUTC: "17:00"
        )
        let deepWinterWeekendHoliday = AirportOpeningPeriod(
            fromUTC: "08:00", closingReference: .sunset,
            sunsetOffsetMinutes: 30
        )
        let summerEdgeHours = AirportSeasonHours(
            monday: summerEdgeWeekday, tuesday: summerEdgeWeekday,
            wednesday: summerEdgeWeekday, thursday: summerEdgeWeekday,
            friday: summerEdgeWeekday, saturday: summerEdgeWeekendHoliday,
            sunday: summerEdgeWeekendHoliday,
            holiday: summerEdgeWeekendHoliday, outsideHoursPPR: true
        )
        let summerCoreHours = AirportSeasonHours(
            monday: summerCore, tuesday: summerCore,
            wednesday: summerCore, thursday: summerCore,
            friday: summerCore, saturday: summerCore,
            sunday: summerCore, holiday: summerCore,
            outsideHoursPPR: true
        )
        let winterEdgeHours = AirportSeasonHours(
            monday: winterEdgeWeekday, tuesday: winterEdgeWeekday,
            wednesday: winterEdgeWeekday, thursday: winterEdgeWeekday,
            friday: winterEdgeWeekday, saturday: winterEdgeWeekendHoliday,
            sunday: winterEdgeWeekendHoliday,
            holiday: winterEdgeWeekendHoliday, outsideHoursPPR: true
        )
        let deepWinterHours = AirportSeasonHours(
            monday: deepWinterWeekday, tuesday: deepWinterWeekday,
            wednesday: deepWinterWeekday, thursday: deepWinterWeekday,
            friday: deepWinterWeekday, saturday: deepWinterWeekendHoliday,
            sunday: deepWinterWeekendHoliday,
            holiday: deepWinterWeekendHoliday, outsideHoursPPR: true
        )
        return AirportOpeningHoursProfile(
            summer: summerCoreHours,
            winter: deepWinterHours,
            dateRules: [
                AirportDateRule(
                    startMonth: 3, startDay: 1, endMonth: 3, endDay: 31,
                    label: "SUM · März", seasonHours: summerEdgeHours,
                    appliesDuringDaylightSavingTime: true,
                    summary: "Mo–Fr 0600–1800; Sa, So, HOL 0600–SS+30"
                ),
                AirportDateRule(
                    startMonth: 10, startDay: 1, endMonth: 10, endDay: 31,
                    label: "SUM · Oktober", seasonHours: summerEdgeHours,
                    appliesDuringDaylightSavingTime: true,
                    summary: "Mo–Fr 0600–1800; Sa, So, HOL 0600–SS+30"
                ),
                AirportDateRule(
                    startMonth: 3, startDay: 1, endMonth: 3, endDay: 31,
                    label: "WIN · März", seasonHours: winterEdgeHours,
                    appliesDuringDaylightSavingTime: false,
                    summary: "Mo–Fr 0700–1900; Sa, So, HOL 0700–SS+30"
                ),
                AirportDateRule(
                    startMonth: 10, startDay: 1, endMonth: 10, endDay: 31,
                    label: "WIN · Oktober", seasonHours: winterEdgeHours,
                    appliesDuringDaylightSavingTime: false,
                    summary: "Mo–Fr 0700–1900; Sa, So, HOL 0700–SS+30"
                )
            ]
        )
    }()

    var isCompletelyEmpty: Bool {
        let periods = [
            summer.monday, summer.tuesday, summer.wednesday, summer.thursday,
            summer.friday, summer.saturday, summer.sunday, summer.holiday,
            winter.monday, winter.tuesday, winter.wednesday, winter.thursday,
            winter.friday, winter.saturday, winter.sunday, winter.holiday
        ]
        return (dateRules ?? []).isEmpty && periods.allSatisfy {
            $0.fromUTC.isEmpty && $0.fixedUntilUTC.isEmpty && $0.latestUTC.isEmpty
        }
    }
}

enum AirportOpeningHoursStore {
    private static let key = "airportOpeningHoursProfiles.v1"

    static func profile(for icao: String) -> AirportOpeningHoursProfile {
        let normalized = icao.uppercased()
        if let profile = allProfiles()[normalized] {
            if normalized == "EDKA", profile.isCompletelyEmpty { return .edka }
            if normalized == "EHMZ", profile.isCompletelyEmpty { return .ehmz }
            if normalized == "EHTX", profile.isCompletelyEmpty { return .ehtx }
            if normalized == "EHAL", profile.isCompletelyEmpty { return .ehal }
            if normalized == "EDWJ", profile.isCompletelyEmpty { return .edwj }
            if normalized == "EDWY", profile.isCompletelyEmpty { return .edwy }
            if normalized == "EDWL", profile.isCompletelyEmpty { return .edwl }
            if normalized == "EDWG", profile.isCompletelyEmpty { return .edwg }
            if normalized == "EDWF", profile.isCompletelyEmpty { return .edwf }
            if normalized == "EDXE", profile.isCompletelyEmpty { return .edxe }
            if normalized == "EDLM", profile.isCompletelyEmpty { return .edlm }
            if normalized == "EDLS", profile.isCompletelyEmpty { return .edls }
            if normalized == "EDTF", profile.isCompletelyEmpty { return .edtf }
            if normalized == "EDTG", profile.isCompletelyEmpty { return .edtg }
            if normalized == "EDTS", profile.isCompletelyEmpty { return .edts }
            if normalized == "EDFE", profile.isCompletelyEmpty { return .edfe }
            if normalized == "EDFM", profile.isCompletelyEmpty { return .edfm }
            if normalized == "EDRY", profile.isCompletelyEmpty { return .edry }
            if normalized == "EDRK", profile.isCompletelyEmpty { return .edrk }
            if normalized == "EDGS", profile.isCompletelyEmpty { return .edgs }
            if normalized == "EDTM", profile.isCompletelyEmpty { return .edtm }
            if normalized == "EDQH", profile.isCompletelyEmpty { return .edqh }
            return profile
        }
        if normalized == "EDFZ" { return .edfz }
        if normalized == "EDFU" { return .edfu }
        if normalized == "EDKA" { return .edka }
        if normalized == "EHMZ" { return .ehmz }
        if normalized == "EHTX" { return .ehtx }
        if normalized == "EHAL" { return .ehal }
        if normalized == "EDWJ" { return .edwj }
        if normalized == "EDWY" { return .edwy }
        if normalized == "EDWL" { return .edwl }
        if normalized == "EDWG" { return .edwg }
        if normalized == "EDWF" { return .edwf }
        if normalized == "EDXE" { return .edxe }
        if normalized == "EDLM" { return .edlm }
        if normalized == "EDLS" { return .edls }
        if normalized == "EDTF" { return .edtf }
        if normalized == "EDTG" { return .edtg }
        if normalized == "EDTS" { return .edts }
        if normalized == "EDFE" { return .edfe }
        if normalized == "EDFM" { return .edfm }
        if normalized == "EDRY" { return .edry }
        if normalized == "EDRK" { return .edrk }
        if normalized == "EDGS" { return .edgs }
        if normalized == "EDTM" { return .edtm }
        if normalized == "EDQH" { return .edqh }
        return AirportOpeningHoursProfile()
    }

    static func save(_ profile: AirportOpeningHoursProfile, for icao: String) {
        var profiles = allProfiles()
        profiles[icao.uppercased()] = profile
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func hasProfile(for icao: String) -> Bool {
        let normalized = icao.uppercased()
        return normalized == "EDFZ" || normalized == "EDFU" || normalized == "EDKA"
            || normalized == "EHMZ" || normalized == "EHTX"
            || normalized == "EHAL"
            || normalized == "EDWJ"
            || normalized == "EDWY"
            || normalized == "EDWL"
            || normalized == "EDWG"
            || normalized == "EDWF"
            || normalized == "EDXE"
            || normalized == "EDLM"
            || normalized == "EDLS"
            || normalized == "EDTF"
            || normalized == "EDTG"
            || normalized == "EDTS"
            || normalized == "EDFE"
            || normalized == "EDFM"
            || normalized == "EDRY"
            || normalized == "EDRK"
            || normalized == "EDGS"
            || normalized == "EDTM"
            || normalized == "EDQH"
            || allProfiles()[normalized] != nil
    }

    private static func allProfiles() -> [String: AirportOpeningHoursProfile] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profiles = try? JSONDecoder().decode(
                  [String: AirportOpeningHoursProfile].self,
                  from: data
              ) else { return [:] }
        return profiles
    }
}

enum AirportOperatingStatus: Equatable {
    case open
    case closingSoon
    case flyingWithoutFlightDirector
    case closedOrPPR
}

enum AirportOperationKind: Equatable {
    case departure
    case arrival
}

enum AirportOpeningAssessment: Equatable {
    case confirmedOpen
    case confirmedClosed
    case unclear
}

struct AirportPublishedOpeningWindow: Equatable {
    let opening: Date
    let closing: Date
}

enum AirportDailyOpeningHours: Equatable {
    case confirmed([AirportPublishedOpeningWindow])
    case confirmedClosed
    case unclear
}

enum AirportOperatingHoursEvaluator {
    static func status(
        airport: AirportReference,
        at instant: Date?,
        operation: AirportOperationKind? = nil,
        flyingWithoutFlightDirector: Bool = false,
        homeAirportICAO: String? = nil,
        initialHomeDeparture: Date? = nil,
        plannedHomeReturn: Date? = nil,
        legOriginICAO: String? = nil
    ) -> AirportOperatingStatus? {
        guard let instant,
              AirportOpeningHoursStore.hasProfile(for: airport.icao)
        else { return nil }

        let profile = AirportOpeningHoursStore.profile(for: airport.icao)
        let season = airport.timeZone.isDaylightSavingTime(for: instant)
            ? profile.summer
            : profile.winter
        let period = selectedPeriod(
            profile: profile,
            season: season,
            instant: instant,
            airport: airport
        )

        let hasPublishedPeriod = !period.fromUTC.isEmpty
            && (period.closingReference == .fixed
                ? !period.fixedUntilUTC.isEmpty
                : true)
        if !hasPublishedPeriod {
            return season.outsideHoursPPR ? .closedOrPPR : nil
        }

        let windows = operatingWindows(
            period: period,
            airport: airport,
            on: instant,
            operation: operation
        )
        guard let opening = windows.first?.opening,
              let closing = windows.last?.closing
        else {
            return .closedOrPPR
        }

        if let activeWindow = windows.first(where: { instant >= $0.opening && instant < $0.closing }) {
            if activeWindow.closing.timeIntervalSince(instant) <= 30 * 60 { return .closingSoon }
            return .open
        } else {
            if flyingWithoutFlightDirector,
               airport.icao.uppercased() == "EDFZ",
               airport.icao.uppercased() == homeAirportICAO?.uppercased(),
               let operation,
               fofPermits(
                   operation: operation,
                   airport: airport,
                   instant: instant,
                   publishedOpening: opening,
                   publishedClosing: closing,
                   initialHomeDeparture: initialHomeDeparture,
                   plannedHomeReturn: plannedHomeReturn,
                   legOriginICAO: legOriginICAO
               ) {
                return .flyingWithoutFlightDirector
            }
            return .closedOrPPR
        }
    }

    static func openingAssessment(
        airport: AirportReference,
        at instant: Date,
        flyingWithoutFlightDirector: Bool = false,
        homeAirportICAO: String? = nil
    ) -> AirportOpeningAssessment {
        guard AirportOpeningHoursStore.hasProfile(for: airport.icao) else {
            return .unclear
        }

        if flyingWithoutFlightDirector,
           airport.icao.uppercased() == "EDFZ",
           airport.icao.uppercased() == homeAirportICAO?.uppercased() {
            switch status(
                airport: airport,
                at: instant,
                operation: .arrival,
                flyingWithoutFlightDirector: true,
                homeAirportICAO: homeAirportICAO
            ) {
            case .open, .closingSoon, .flyingWithoutFlightDirector:
                return .confirmedOpen
            case .closedOrPPR:
                return .confirmedClosed
            case .none:
                break
            }
        }

        return openingAssessment(
            airport: airport,
            at: instant,
            profile: AirportOpeningHoursStore.profile(for: airport.icao)
        )
    }

    static func dailyOpeningHours(
        airport: AirportReference,
        at instant: Date
    ) -> AirportDailyOpeningHours {
        guard AirportOpeningHoursStore.hasProfile(for: airport.icao) else {
            return .unclear
        }

        let profile = AirportOpeningHoursStore.profile(for: airport.icao)
        let season = airport.timeZone.isDaylightSavingTime(for: instant)
            ? profile.summer
            : profile.winter
        let selectedPeriod = selectedPeriod(
            profile: profile,
            season: season,
            instant: instant,
            airport: airport
        )
        let hasPublishedPeriod = !selectedPeriod.fromUTC.isEmpty
            && (selectedPeriod.closingReference == .fixed
                ? !selectedPeriod.fixedUntilUTC.isEmpty
                : true)
        guard hasPublishedPeriod else {
            return season.outsideHoursPPR
                ? .confirmedClosed
                : .unclear
        }

        let windows = operatingWindows(
            period: selectedPeriod,
            airport: airport,
            on: instant,
            operation: .arrival
        )
        guard !windows.isEmpty else { return .unclear }
        return .confirmed(
            windows.map {
                AirportPublishedOpeningWindow(
                    opening: $0.opening,
                    closing: $0.closing
                )
            }
        )
    }

    static func openingAssessment(
        airport: AirportReference,
        at instant: Date,
        profile: AirportOpeningHoursProfile
    ) -> AirportOpeningAssessment {
        let season = airport.timeZone.isDaylightSavingTime(for: instant)
            ? profile.summer
            : profile.winter
        let period = selectedPeriod(
            profile: profile,
            season: season,
            instant: instant,
            airport: airport
        )
        let hasPublishedPeriod = !period.fromUTC.isEmpty
            && (period.closingReference == .fixed
                ? !period.fixedUntilUTC.isEmpty
                : true)
        guard hasPublishedPeriod else {
            return season.outsideHoursPPR
                ? .confirmedClosed
                : .unclear
        }

        let windows = operatingWindows(
            period: period,
            airport: airport,
            on: instant,
            operation: .arrival
        )
        guard !windows.isEmpty else { return .unclear }
        if windows.contains(where: {
            instant >= $0.opening && instant < $0.closing
        }) {
            return .confirmedOpen
        }

        // PPR gilt in Flybook für die automatische Flugentscheidung als
        // geschlossen. Unklar bleiben nur Plätze ohne belastbare Daten.
        return .confirmedClosed
    }

    private static func fofPermits(
        operation: AirportOperationKind,
        airport: AirportReference,
        instant: Date,
        publishedOpening: Date,
        publishedClosing: Date,
        initialHomeDeparture: Date?,
        plannedHomeReturn: Date?,
        legOriginICAO: String?
    ) -> Bool {
        guard let events = SolarCalculator.events(
            forLocalDayContaining: instant,
            latitude: airport.latitude,
            longitude: airport.longitude,
            timeZone: airport.timeZone
        ) else { return false }

        let earliest = localInstant(hour: 6, on: instant, timeZone: airport.timeZone)
        let latest = localInstant(hour: 22, on: instant, timeZone: airport.timeZone)
        guard let earliest, let latest else { return false }
        let fofStart = max(events.civilDawn, earliest)
        let fofEnd = min(events.civilDusk, latest)
        guard instant >= fofStart, instant < fofEnd else { return false }

        switch operation {
        case .departure:
            if instant < publishedOpening,
               let plannedHomeReturn,
               let returnOpening = publishedWindow(
                   airport: airport,
                   at: plannedHomeReturn
               )?.opening,
               plannedHomeReturn < returnOpening {
                return false
            }
            return true

        case .arrival:
            guard instant >= publishedClosing else { return true }
            // Bei einem vorherigen Start in EDFZ muss dieser mindestens eine
            // Stunde vor dem veröffentlichten Betriebsschluss erfolgt sein.
            if legOriginICAO == airport.icao || initialHomeDeparture != nil {
                guard let initialHomeDeparture else { return false }
                return initialHomeDeparture <= publishedClosing.addingTimeInterval(-60 * 60)
            }
            return true
        }
    }

    private static func publishedWindow(
        airport: AirportReference,
        at instant: Date
    ) -> (opening: Date, closing: Date)? {
        guard AirportOpeningHoursStore.hasProfile(for: airport.icao) else { return nil }
        let profile = AirportOpeningHoursStore.profile(for: airport.icao)
        let season = airport.timeZone.isDaylightSavingTime(for: instant) ? profile.summer : profile.winter
        let selectedPeriod = selectedPeriod(
            profile: profile,
            season: season,
            instant: instant,
            airport: airport
        )
        let windows = operatingWindows(period: selectedPeriod, airport: airport, on: instant)
        guard let opening = windows.first?.opening, let closing = windows.last?.closing else { return nil }
        return (opening, closing)
    }

    private static func operatingWindows(
        period: AirportOpeningPeriod,
        airport: AirportReference,
        on instant: Date,
        operation: AirportOperationKind? = nil
    ) -> [(opening: Date, closing: Date)] {
        var result: [(Date, Date)] = []
        if let opening = openingInstant(period: period, airport: airport, on: instant),
           let regularClosing = closingInstant(period: period, airport: airport, on: instant) {
            let closing: Date
            if operation == .arrival,
               let landingUntil = period.landingUntilUTC,
               let landingClosing = utcInstant(landingUntil, on: instant, localTimeZone: airport.timeZone) {
                closing = landingClosing
            } else {
                closing = regularClosing
            }
            if opening < closing {
                result.append((opening, closing))
            }
        }
        if let secondFrom = period.secondFromUTC,
           let opening = utcInstant(secondFrom, on: instant, localTimeZone: airport.timeZone),
           let closing = secondClosingInstant(period: period, airport: airport, on: instant),
           opening < closing {
            result.append((opening, closing))
        }
        let sorted = result.sorted { $0.0 < $1.0 }
        guard operation == .departure,
              let blockedFromText = period.departureClosedFromUTC,
              let blockedUntilText = period.departureClosedUntilUTC,
              let blockedFrom = utcInstant(
                  blockedFromText,
                  on: instant,
                  localTimeZone: airport.timeZone
              ),
              let blockedUntil = utcInstant(
                  blockedUntilText,
                  on: instant,
                  localTimeZone: airport.timeZone
              ),
              blockedFrom < blockedUntil
        else { return sorted }

        return sorted.flatMap { window -> [(opening: Date, closing: Date)] in
            if blockedUntil <= window.0 || blockedFrom >= window.1 {
                return [window]
            }
            var pieces: [(opening: Date, closing: Date)] = []
            if window.0 < blockedFrom {
                pieces.append((window.0, min(blockedFrom, window.1)))
            }
            if blockedUntil < window.1 {
                pieces.append((max(blockedUntil, window.0), window.1))
            }
            return pieces.filter { $0.opening < $0.closing }
        }
    }

    private static func selectedPeriod(
        profile: AirportOpeningHoursProfile,
        season: AirportSeasonHours,
        instant: Date,
        airport: AirportReference
    ) -> AirportOpeningPeriod {
        if let rule = profile.dateRules?.first(where: {
            dateRule($0, contains: instant, timeZone: airport.timeZone)
        }) {
            if let ruleHours = rule.seasonHours {
                return period(
                    for: instant,
                    airport: airport,
                    season: ruleHours
                )
            }
            return rule.period
        }
        return period(for: instant, airport: airport, season: season)
    }

    private static func dateRule(
        _ rule: AirportDateRule,
        contains instant: Date,
        timeZone: TimeZone
    ) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.month, .day], from: instant)
        guard let month = parts.month, let day = parts.day else { return false }
        let value = month * 100 + day
        if let expectedDST = rule.appliesDuringDaylightSavingTime,
           timeZone.isDaylightSavingTime(for: instant) != expectedDST {
            return false
        }
        let start = rule.startMonth * 100 + rule.startDay
        let end = rule.endMonth * 100 + rule.endDay
        if start <= end { return value >= start && value <= end }
        return value >= start || value <= end
    }

    private static func openingInstant(
        period: AirportOpeningPeriod,
        airport: AirportReference,
        on instant: Date
    ) -> Date? {
        guard let fixed = utcInstant(period.fromUTC, on: instant, localTimeZone: airport.timeZone) else { return nil }
        guard period.openingReference == .sunrise,
              let sunrise = SolarCalculator.events(
                  forLocalDayContaining: instant,
                  latitude: airport.latitude,
                  longitude: airport.longitude,
                  timeZone: airport.timeZone
              )?.sunrise
        else { return fixed }
        let adjusted = sunrise.addingTimeInterval(TimeInterval((period.sunriseOffsetMinutes ?? 0) * 60))
        return max(fixed, adjusted)
    }

    private static func secondClosingInstant(
        period: AirportOpeningPeriod,
        airport: AirportReference,
        on instant: Date
    ) -> Date? {
        if period.secondClosingReference == .fixed {
            return utcInstant(period.secondFixedUntilUTC ?? "", on: instant, localTimeZone: airport.timeZone)
        }
        guard let events = SolarCalculator.events(
            forLocalDayContaining: instant,
            latitude: airport.latitude,
            longitude: airport.longitude,
            timeZone: airport.timeZone
        ) else { return nil }
        let closingReference = period.secondClosingReference ?? .sunset
        let astronomicalClosing = closingReference == .civilDusk
            ? events.civilDusk
            : events.sunset
        let adjusted = astronomicalClosing.addingTimeInterval(
            TimeInterval((period.secondSunsetOffsetMinutes ?? 0) * 60)
        )
        guard let latest = utcInstant(period.secondLatestUTC ?? "", on: instant, localTimeZone: airport.timeZone) else {
            return adjusted
        }
        return min(adjusted, latest)
    }

    private static func localInstant(hour: Int, on instant: Date, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: instant)
        return calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: day.year,
            month: day.month,
            day: day.day,
            hour: hour
        ))
    }

    private static func period(
        for instant: Date,
        airport: AirportReference,
        season: AirportSeasonHours
    ) -> AirportOpeningPeriod {
        if airport.icao.hasPrefix("ED"), isGermanPublicHoliday(instant, timeZone: airport.timeZone) {
            return season.holiday
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = airport.timeZone
        switch calendar.component(.weekday, from: instant) {
        case 1: return season.sunday
        case 2: return season.monday
        case 3: return season.tuesday
        case 4: return season.wednesday
        case 5: return season.thursday
        case 6: return season.friday
        default: return season.saturday
        }
    }

    private static func closingInstant(
        period: AirportOpeningPeriod,
        airport: AirportReference,
        on instant: Date
    ) -> Date? {
        if period.closingReference == .fixed {
            return utcInstant(period.fixedUntilUTC, on: instant, localTimeZone: airport.timeZone)
        }
        guard let events = SolarCalculator.events(
                  forLocalDayContaining: instant,
                  latitude: airport.latitude,
                  longitude: airport.longitude,
                  timeZone: airport.timeZone
              )
        else { return nil }
        let astronomicalClosing = period.closingReference == .civilDusk
            ? events.civilDusk
            : events.sunset
        let adjustedSunset = astronomicalClosing.addingTimeInterval(
            TimeInterval(period.sunsetOffsetMinutes * 60)
        )
        guard let latest = utcInstant(period.latestUTC, on: instant, localTimeZone: airport.timeZone) else {
            return adjustedSunset
        }
        return min(adjustedSunset, latest)
    }

    private static func utcInstant(
        _ text: String,
        on instant: Date,
        localTimeZone: TimeZone
    ) -> Date? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else {
            return nil
        }
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = localTimeZone
        let day = localCalendar.dateComponents([.year, .month, .day], from: instant)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return utcCalendar.date(from: DateComponents(
            timeZone: utcCalendar.timeZone,
            year: day.year,
            month: day.month,
            day: day.day,
            hour: parts[0],
            minute: parts[1]
        ))
    }

    private static func isGermanPublicHoliday(_ instant: Date, timeZone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: instant)
        guard let year = components.year, let month = components.month, let day = components.day else { return false }
        if [(1, 1), (5, 1), (10, 3), (12, 25), (12, 26)].contains(where: { $0 == (month, day) }) {
            return true
        }
        guard let easter = easterSunday(year: year, calendar: calendar) else { return false }
        let offset = calendar.dateComponents([.day], from: easter, to: instant).day
        return [-2, 1, 39, 50].contains(offset)
    }

    private static func easterSunday(year: Int, calendar: Calendar) -> Date? {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

struct AirportLandingFeeBand: Codable, Equatable, Identifiable {
    var id: String { weightBand }
    var weightBand: String
    var withoutNoiseProtectionEUR = ""
    var normalNoiseProtectionEUR = ""
    var enhancedNoiseProtectionEUR = ""
}

struct AirportAncillaryFeeBand: Codable, Equatable, Identifiable {
    var id: String { weightBand }
    var weightBand: String
    var amountEUR: String
}

struct AirportNoiseFeeBand: Codable, Equatable, Identifiable {
    var id: String { "\(upperNoiseDBA)-\(amountEUR)" }
    var upperNoiseDBA: Double
    var amountEUR: String
}

struct AirportLandingFeeProfile: Codable, Equatable {
    var bands: [AirportLandingFeeBand] = [
        AirportLandingFeeBand(weightBand: "bis 750 kg"),
        AirportLandingFeeBand(weightBand: "bis 1.000 kg"),
        AirportLandingFeeBand(weightBand: "1.001–1.200 kg"),
        AirportLandingFeeBand(weightBand: "1.201–1.400 kg")
    ]
    var weekendBands: [AirportLandingFeeBand]?
    var weekendTimeZoneIdentifier: String?
    /// Optional chapter-10 base tariff. When present, a real dB(A) value from
    /// the aircraft profile is mandatory; the generic enhanced column is not
    /// used as a silent estimate.
    var noiseBands: [AirportNoiseFeeBand]?
    var weekendNoiseBands: [AirportNoiseFeeBand]?
    var noiseWeightSurchargeBands: [AirportAncillaryFeeBand]?
    var basicTrainingLandingFeeEUR: String?
    var commercialSurchargeEUR: String?
    var overnightParkingPerNightEUR: String?
    var overnightParkingBands: [AirportAncillaryFeeBand]?
    var customsClearancePerControlEUR: String?
    var handlingPerMovementEUR: String?
    var customsOutsideOfficeHoursSurchargeEUR: String?
    var winterServiceSurchargeEUR: String?
    var winterServiceStartMonth: Int?
    var winterServiceEndMonth: Int?
    /// Original tariff currency. Older profiles without this field are EUR.
    var currencyCode: String?

    var effectiveCurrencyCode: String {
        currencyCode?.uppercased() ?? "EUR"
    }

    static let edfz = AirportLandingFeeProfile(bands: [
        AirportLandingFeeBand(
            weightBand: "bis 750 kg",
            withoutNoiseProtectionEUR: "21,80",
            normalNoiseProtectionEUR: "16,40",
            enhancedNoiseProtectionEUR: "10,90"
        ),
        AirportLandingFeeBand(
            weightBand: "bis 1.000 kg",
            withoutNoiseProtectionEUR: "24,00",
            normalNoiseProtectionEUR: "18,00",
            enhancedNoiseProtectionEUR: "12,00"
        ),
        AirportLandingFeeBand(
            weightBand: "1.001–1.200 kg",
            withoutNoiseProtectionEUR: "28,80",
            normalNoiseProtectionEUR: "21,60",
            enhancedNoiseProtectionEUR: "14,40"
        ),
        AirportLandingFeeBand(
            weightBand: "1.201–1.400 kg",
            withoutNoiseProtectionEUR: "37,20",
            normalNoiseProtectionEUR: "27,90",
            enhancedNoiseProtectionEUR: "18,60"
        )
    ])

    static let edka = AirportLandingFeeProfile(bands: [
        AirportLandingFeeBand(
            weightBand: "bis 1.000 kg",
            withoutNoiseProtectionEUR: "14,40",
            normalNoiseProtectionEUR: "14,40",
            enhancedNoiseProtectionEUR: "9,00"
        ),
        AirportLandingFeeBand(
            weightBand: "1.001–1.200 kg",
            withoutNoiseProtectionEUR: "18,00",
            normalNoiseProtectionEUR: "18,00",
            enhancedNoiseProtectionEUR: "11,00"
        ),
        AirportLandingFeeBand(
            weightBand: "1.201–1.400 kg",
            withoutNoiseProtectionEUR: "31,20",
            normalNoiseProtectionEUR: "31,20",
            enhancedNoiseProtectionEUR: "15,00"
        ),
        AirportLandingFeeBand(
            weightBand: "1.401–2.000 kg",
            withoutNoiseProtectionEUR: "46,80",
            normalNoiseProtectionEUR: "46,80",
            enhancedNoiseProtectionEUR: "25,00"
        )
    ])

    static let edtg = AirportLandingFeeProfile(
        bands: edtgBands(weekend: false),
        weekendBands: edtgBands(weekend: true),
        weekendTimeZoneIdentifier: "Europe/Berlin",
        noiseBands: edtgNoiseBands(weekend: false),
        weekendNoiseBands: edtgNoiseBands(weekend: true),
        noiseWeightSurchargeBands: [
            AirportAncillaryFeeBand(weightBand: "bis 500 kg", amountEUR: "1,49"),
            AirportAncillaryFeeBand(weightBand: "501–600 kg", amountEUR: "2,98"),
            AirportAncillaryFeeBand(weightBand: "601–1.000 kg", amountEUR: "5,95"),
            AirportAncillaryFeeBand(weightBand: "1.001–1.200 kg", amountEUR: "10,41"),
            AirportAncillaryFeeBand(weightBand: "1.201–1.400 kg", amountEUR: "14,88"),
            AirportAncillaryFeeBand(weightBand: "1.401–2.000 kg", amountEUR: "19,34"),
            AirportAncillaryFeeBand(weightBand: "2.001–3.000 kg", amountEUR: "23,80"),
            AirportAncillaryFeeBand(weightBand: "3.001–4.000 kg", amountEUR: "28,26"),
            AirportAncillaryFeeBand(weightBand: "4.001–5.000 kg", amountEUR: "32,73"),
            AirportAncillaryFeeBand(weightBand: "5.001–6.000 kg", amountEUR: "37,19"),
            AirportAncillaryFeeBand(weightBand: "6.001–7.000 kg", amountEUR: "41,65"),
            AirportAncillaryFeeBand(weightBand: "7.001–8.000 kg", amountEUR: "46,11"),
            AirportAncillaryFeeBand(weightBand: "8.001–9.000 kg", amountEUR: "50,58"),
            AirportAncillaryFeeBand(weightBand: "9.001–10.000 kg", amountEUR: "55,04")
        ],
        overnightParkingBands: [
            AirportAncillaryFeeBand(weightBand: "bis 500 kg", amountEUR: "10,23"),
            AirportAncillaryFeeBand(weightBand: "501–600 kg", amountEUR: "11,42"),
            AirportAncillaryFeeBand(weightBand: "601–1.000 kg", amountEUR: "12,73"),
            AirportAncillaryFeeBand(weightBand: "1.001–1.200 kg", amountEUR: "25,35"),
            AirportAncillaryFeeBand(weightBand: "1.201–1.400 kg", amountEUR: "50,69"),
            AirportAncillaryFeeBand(weightBand: "1.401–2.000 kg", amountEUR: "88,66"),
            AirportAncillaryFeeBand(weightBand: "2.001–3.000 kg", amountEUR: "126,62"),
            AirportAncillaryFeeBand(weightBand: "3.001–4.000 kg", amountEUR: "164,58"),
            AirportAncillaryFeeBand(weightBand: "4.001–5.000 kg", amountEUR: "202,66"),
            AirportAncillaryFeeBand(weightBand: "5.001–6.000 kg", amountEUR: "240,62"),
            AirportAncillaryFeeBand(weightBand: "6.001–7.000 kg", amountEUR: "278,58"),
            AirportAncillaryFeeBand(weightBand: "7.001–8.000 kg", amountEUR: "316,54"),
            AirportAncillaryFeeBand(weightBand: "8.001–9.000 kg", amountEUR: "354,50"),
            AirportAncillaryFeeBand(weightBand: "9.001–10.000 kg", amountEUR: "392,46")
        ],
        customsClearancePerControlEUR: "10,12"
    )

    private static func edtgNoiseBands(
        weekend: Bool
    ) -> [AirportNoiseFeeBand] {
        let weekday: [(Double, String)] = [
            (59.9, "8,69"),
            (62.9, "9,76"),
            (65.9, "10,83"),
            (68.9, "21,54"),
            (71.9, "21,54"),
            (74.9, "43,08"),
            (77.9, "75,21"),
            (80.9, "107,46"),
            (83.9, "139,71"),
            (999, "171,96")
        ]
        let weekendRows: [(Double, String)] = [
            (59.9, "10,83"),
            (62.9, "12,14"),
            (65.9, "13,45"),
            (68.9, "26,89"),
            (71.9, "26,89"),
            (74.9, "53,79"),
            (77.9, "94,01"),
            (80.9, "134,35"),
            (83.9, "174,69"),
            (999, "214,91")
        ]
        return (weekend ? weekendRows : weekday).map {
            AirportNoiseFeeBand(upperNoiseDBA: $0.0, amountEUR: $0.1)
        }
    }

    private static func edtgBands(
        weekend: Bool
    ) -> [AirportLandingFeeBand] {
        let weekdayRows: [(String, String, String, String)] = [
            ("bis 500 kg", "34,87", "12,26", "12,32"),
            ("501–600 kg", "34,87", "14,04", "13,81"),
            ("601–1.000 kg", "69,73", "15,71", "16,78"),
            ("1.001–1.200 kg", "121,98", "17,49", "21,24"),
            ("1.201–1.400 kg", "174,34", "34,87", "25,71"),
            ("1.401–2.000 kg", "226,58", "34,87", "30,17"),
            ("2.001–3.000 kg", "278,82", "69,73", "34,63"),
            ("3.001–4.000 kg", "332,25", "121,98", "39,09"),
            ("4.001–5.000 kg", "383,30", "174,34", "43,56"),
            ("5.001–6.000 kg", "435,66", "226,58", "48,02"),
            ("6.001–7.000 kg", "487,90", "278,82", "52,48"),
            ("7.001–8.000 kg", "540,14", "331,06", "56,94"),
            ("8.001–9.000 kg", "592,38", "383,30", "61,41"),
            ("9.001–10.000 kg", "644,62", "435,66", "65,87")
        ]
        let weekendRows: [(String, String, String, String)] = [
            ("bis 500 kg", "43,67", "15,35", "14,94"),
            ("501–600 kg", "43,67", "17,49", "16,43"),
            ("601–1.000 kg", "87,23", "19,64", "19,40"),
            ("1.001–1.200 kg", "152,56", "21,90", "23,86"),
            ("1.201–1.400 kg", "217,89", "43,67", "28,33"),
            ("1.401–2.000 kg", "283,22", "43,67", "32,79"),
            ("2.001–3.000 kg", "348,55", "87,23", "37,25"),
            ("3.001–4.000 kg", "413,88", "152,56", "41,71"),
            ("4.001–5.000 kg", "479,21", "217,89", "46,18"),
            ("5.001–6.000 kg", "544,54", "283,22", "50,64"),
            ("6.001–7.000 kg", "609,88", "348,55", "55,10"),
            ("7.001–8.000 kg", "675,21", "413,88", "59,56"),
            ("8.001–9.000 kg", "740,54", "479,21", "64,03"),
            ("9.001–10.000 kg", "805,87", "544,54", "68,49")
        ]
        return (weekend ? weekendRows : weekdayRows).map {
            AirportLandingFeeBand(
                weightBand: $0.0,
                withoutNoiseProtectionEUR: $0.1,
                normalNoiseProtectionEUR: $0.2,
                enhancedNoiseProtectionEUR: $0.3
            )
        }
    }

    static let lsgn = AirportLandingFeeProfile(
        bands: [
            AirportLandingFeeBand(
                weightBand: "bis 700 kg",
                withoutNoiseProtectionEUR: "23",
                normalNoiseProtectionEUR: "23",
                enhancedNoiseProtectionEUR: "23"
            ),
            AirportLandingFeeBand(
                weightBand: "701–1.000 kg",
                withoutNoiseProtectionEUR: "25",
                normalNoiseProtectionEUR: "25",
                enhancedNoiseProtectionEUR: "25"
            ),
            AirportLandingFeeBand(
                weightBand: "1.001–1.500 kg",
                withoutNoiseProtectionEUR: "31",
                normalNoiseProtectionEUR: "31",
                enhancedNoiseProtectionEUR: "31"
            ),
            AirportLandingFeeBand(
                weightBand: "1.501–2.000 kg",
                withoutNoiseProtectionEUR: "39",
                normalNoiseProtectionEUR: "39",
                enhancedNoiseProtectionEUR: "39"
            ),
            AirportLandingFeeBand(
                weightBand: "2.001–3.000 kg",
                withoutNoiseProtectionEUR: "59",
                normalNoiseProtectionEUR: "59",
                enhancedNoiseProtectionEUR: "59"
            ),
            AirportLandingFeeBand(
                weightBand: "3.001–4.000 kg",
                withoutNoiseProtectionEUR: "90",
                normalNoiseProtectionEUR: "90",
                enhancedNoiseProtectionEUR: "90"
            ),
            AirportLandingFeeBand(
                weightBand: "bis 999.999 kg",
                withoutNoiseProtectionEUR: "110",
                normalNoiseProtectionEUR: "110",
                enhancedNoiseProtectionEUR: "110"
            )
        ],
        basicTrainingLandingFeeEUR: "20",
        commercialSurchargeEUR: "30",
        overnightParkingPerNightEUR: "19",
        customsClearancePerControlEUR: "15",
        customsOutsideOfficeHoursSurchargeEUR: "32",
        currencyCode: "CHF"
    )

    static let lsgr = AirportLandingFeeProfile(
        bands: [
            AirportLandingFeeBand(
                weightBand: "bis 999 kg",
                withoutNoiseProtectionEUR: "25",
                normalNoiseProtectionEUR: "25",
                enhancedNoiseProtectionEUR: "25"
            ),
            AirportLandingFeeBand(
                weightBand: "1.000–2.249 kg",
                withoutNoiseProtectionEUR: "35",
                normalNoiseProtectionEUR: "35",
                enhancedNoiseProtectionEUR: "35"
            ),
            AirportLandingFeeBand(
                weightBand: "bis 999.999 kg",
                withoutNoiseProtectionEUR: "100",
                normalNoiseProtectionEUR: "100",
                enhancedNoiseProtectionEUR: "100"
            )
        ],
        overnightParkingPerNightEUR: "10",
        customsClearancePerControlEUR: "20",
        winterServiceSurchargeEUR: "20",
        winterServiceStartMonth: 12,
        winterServiceEndMonth: 3,
        currencyCode: "CHF"
    )

    var isCompletelyEmpty: Bool {
        bands.allSatisfy {
            $0.withoutNoiseProtectionEUR.isEmpty
                && $0.normalNoiseProtectionEUR.isEmpty
                && $0.enhancedNoiseProtectionEUR.isEmpty
        }
    }
}

enum AirportLandingFeeStore {
    private static let key = "airportLandingFeeProfiles.v1"

    static func profile(for icao: String) -> AirportLandingFeeProfile {
        let normalized = icao.uppercased()
        if let saved = allProfiles()[normalized] {
            if normalized == "EDFZ", saved.isCompletelyEmpty { return .edfz }
            if normalized == "EDKA", saved.isCompletelyEmpty { return .edka }
            if normalized == "EDTG", saved.isCompletelyEmpty { return .edtg }
            if normalized == "LSGN", saved.isCompletelyEmpty { return .lsgn }
            if normalized == "LSGR", saved.isCompletelyEmpty { return .lsgr }
            var migrated = saved
            if normalized.hasPrefix("LS"), migrated.currencyCode == nil {
                migrated.currencyCode = "CHF"
            }
            if normalized == "EDKA" {
                for index in migrated.bands.indices where migrated.bands[index].normalNoiseProtectionEUR.isEmpty {
                    migrated.bands[index].normalNoiseProtectionEUR = migrated.bands[index].withoutNoiseProtectionEUR
                }
                return migrated
            }
            return migrated
        }
        if normalized == "EDFZ" { return .edfz }
        if normalized == "EDKA" { return .edka }
        if normalized == "EDTG" { return .edtg }
        if normalized == "LSGN" { return .lsgn }
        if normalized == "LSGR" { return .lsgr }
        var profile = AirportLandingFeeProfile()
        if normalized.hasPrefix("LS") { profile.currencyCode = "CHF" }
        return profile
    }

    static func save(_ profile: AirportLandingFeeProfile, for icao: String) {
        var profiles = allProfiles()
        profiles[icao.uppercased()] = profile
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func allProfiles() -> [String: AirportLandingFeeProfile] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profiles = try? JSONDecoder().decode(
                  [String: AirportLandingFeeProfile].self,
                  from: data
              ) else { return [:] }
        return profiles
    }
}

struct AirportLandingFeeQuote: Equatable {
    let knownTotalEUR: Double
    let unknownICAOs: [String]

    var totalEUR: Double? {
        unknownICAOs.isEmpty ? knownTotalEUR : nil
    }

    var hasUnknownFees: Bool {
        !unknownICAOs.isEmpty
    }
}

enum AirportLandingFeeDisplay {
    static func text(
        for quote: AirportLandingFeeQuote,
        isEnabled: Bool
    ) -> String {
        guard isEnabled else { return "" }
        if quote.hasUnknownFees {
            guard quote.knownTotalEUR > 0 else { return "?" }
            return quote.knownTotalEUR
                .rounded(.toNearestOrAwayFromZero)
                .formatted(
                    .currency(code: "EUR")
                        .locale(Locale(identifier: "de_DE"))
                        .precision(.fractionLength(0))
                ) + " + ?"
        }
        return quote.knownTotalEUR
            .rounded(.toNearestOrAwayFromZero)
            .formatted(
                .currency(code: "EUR")
                    .locale(Locale(identifier: "de_DE"))
                    .precision(.fractionLength(0))
            )
    }
}

enum AirportLandingFeeCalculator {
    static func ancillaryFeeEUR(
        profile: AirportLandingFeeProfile,
        amountText: String?,
        weightBands: [AirportAncillaryFeeBand]? = nil,
        mtowKilograms: Double? = nil,
        count: Int,
        chfToEURRate: Double? = nil
    ) -> Double? {
        guard count > 0 else { return 0 }
        let resolvedAmountText: String?
        if let weightBands, !weightBands.isEmpty {
            guard let mtowKilograms, mtowKilograms > 0 else { return nil }
            resolvedAmountText = weightBands
                .compactMap { band -> (Int, String)? in
                    guard let upperLimit = upperWeightLimit(
                        in: band.weightBand
                    ) else { return nil }
                    return (upperLimit, band.amountEUR)
                }
                .sorted { $0.0 < $1.0 }
                .first { Double($0.0) >= mtowKilograms }?
                .1
        } else {
            resolvedAmountText = amountText
        }
        guard let resolvedAmountText,
              let amount = decimalEUR(from: resolvedAmountText)
        else { return nil }
        guard let singleFeeEUR = convertedEUR(
            amount,
            currencyCode: profile.effectiveCurrencyCode,
            chfToEURRate: chfToEURRate
        ) else { return nil }
        return singleFeeEUR * Double(count)
    }

    static func feeEUR(
        profile: AirportLandingFeeProfile,
        mtowKilograms: Double,
        hasIncreasedNoiseProtection: Bool,
        noiseLevelDBA: Double? = nil,
        landingDate: Date? = nil,
        chfToEURRate: Double? = nil
    ) -> Double? {
        guard mtowKilograms > 0 else { return nil }
        let weekendTariff = landingDate.map {
            isWeekendOrHoliday(
                $0,
                timeZoneIdentifier: profile.weekendTimeZoneIdentifier
            )
        } ?? false

        if hasIncreasedNoiseProtection,
           let weekdayNoiseBands = profile.noiseBands,
           !weekdayNoiseBands.isEmpty {
            guard let noiseLevelDBA,
                  noiseLevelDBA > 0,
                  let weightBands = profile.noiseWeightSurchargeBands
            else { return nil }
            let noiseBands = weekendTariff
                ? (profile.weekendNoiseBands ?? weekdayNoiseBands)
                : weekdayNoiseBands
            let baseText = noiseBands
                .sorted(by: { $0.upperNoiseDBA < $1.upperNoiseDBA })
                .first(where: { $0.upperNoiseDBA >= noiseLevelDBA })?
                .amountEUR
            let weightText = weightBands
                .compactMap({ band -> (Int, String)? in
                    guard let limit = upperWeightLimit(in: band.weightBand)
                    else { return nil }
                    return (limit, band.amountEUR)
                })
                .sorted(by: { $0.0 < $1.0 })
                .first(where: { Double($0.0) >= mtowKilograms })?
                .1
            guard let baseText,
                  let weightText,
                  let baseAmount = decimalEUR(from: baseText),
                  let weightAmount = decimalEUR(from: weightText)
            else { return nil }
            return convertedEUR(
                baseAmount + weightAmount,
                currencyCode: profile.effectiveCurrencyCode,
                chfToEURRate: chfToEURRate
            )
        }

        let tariffBands: [AirportLandingFeeBand]
        if weekendTariff,
           let weekendBands = profile.weekendBands {
            tariffBands = weekendBands
        } else {
            tariffBands = profile.bands
        }
        let matchingBand = tariffBands
            .compactMap { band -> (upperLimit: Int, band: AirportLandingFeeBand)? in
                guard let upperLimit = upperWeightLimit(in: band.weightBand) else {
                    return nil
                }
                return (upperLimit, band)
            }
            .sorted { $0.upperLimit < $1.upperLimit }
            .first { Double($0.upperLimit) >= mtowKilograms }?
            .band
        guard let matchingBand else { return nil }

        let feeText = hasIncreasedNoiseProtection
            ? matchingBand.enhancedNoiseProtectionEUR
            : matchingBand.normalNoiseProtectionEUR
        guard let nativeAmount = decimalEUR(from: feeText) else { return nil }
        return convertedEUR(
            nativeAmount,
            currencyCode: profile.effectiveCurrencyCode,
            chfToEURRate: chfToEURRate
        )
    }

    static func quote(
        for airportICAOs: [String],
        mtowKilograms: Double,
        hasIncreasedNoiseProtection: Bool,
        noiseLevelDBA: Double? = nil,
        landingDate: Date? = nil,
        landingVoucherBookEnabled: Bool = false,
        chfToEURRate: Double? = nil,
        voucherProvider: (String, Date) -> Bool = {
            LandingVoucherBook.includes($0, on: $1)
        },
        profileProvider: (String) -> AirportLandingFeeProfile = {
            AirportLandingFeeStore.profile(for: $0)
        }
    ) -> AirportLandingFeeQuote {
        var knownTotalEUR = 0.0
        var unknownICAOs: [String] = []

        for rawICAO in airportICAOs {
            let icao = rawICAO.uppercased()
            let profile = profileProvider(icao)
            let landingFeeWaived = landingVoucherBookEnabled
                && landingDate.map { voucherProvider(icao, $0) } == true
            var airportTotalEUR = 0.0

            if !landingFeeWaived {
                guard let fee = feeEUR(
                    profile: profile,
                    mtowKilograms: mtowKilograms,
                    hasIncreasedNoiseProtection: hasIncreasedNoiseProtection,
                    noiseLevelDBA: noiseLevelDBA,
                    landingDate: landingDate,
                    chfToEURRate: chfToEURRate
                ) else {
                    unknownICAOs.append(icao)
                    continue
                }
                airportTotalEUR += fee
            }

            if let landingDate,
               winterServiceSurchargeApplies(
                    profile: profile,
                    on: landingDate
               ) {
                guard let winterSurcharge = ancillaryFeeEUR(
                    profile: profile,
                    amountText: profile.winterServiceSurchargeEUR,
                    count: 1,
                    chfToEURRate: chfToEURRate
                ) else {
                    unknownICAOs.append(icao)
                    continue
                }
                airportTotalEUR += winterSurcharge
            }

            knownTotalEUR += airportTotalEUR
        }

        return AirportLandingFeeQuote(
            knownTotalEUR: knownTotalEUR,
            unknownICAOs: unknownICAOs
        )
    }

    static func winterServiceSurchargeApplies(
        profile: AirportLandingFeeProfile,
        on date: Date
    ) -> Bool {
        guard profile.winterServiceSurchargeEUR != nil,
              let startMonth = profile.winterServiceStartMonth,
              let endMonth = profile.winterServiceEndMonth,
              (1...12).contains(startMonth),
              (1...12).contains(endMonth)
        else { return false }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")
            ?? .current
        let month = calendar.component(.month, from: date)
        if startMonth <= endMonth {
            return (startMonth...endMonth).contains(month)
        }
        return month >= startMonth || month <= endMonth
    }

    private static func isWeekendOrHoliday(
        _ date: Date,
        timeZoneIdentifier: String?
    ) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? TimeZone(identifier: "Europe/Berlin")
            ?? .current
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { return true }

        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year,
              let month = parts.month,
              let day = parts.day
        else { return false }
        let fixedHolidays = [
            (1, 1), (1, 6), (5, 1), (10, 3), (11, 1),
            (12, 25), (12, 26)
        ]
        if fixedHolidays.contains(where: { $0 == (month, day) }) {
            return true
        }
        guard let easter = easterSunday(year: year, calendar: calendar) else {
            return false
        }
        let offset = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: easter),
            to: calendar.startOfDay(for: date)
        ).day
        return [-2, 1, 39, 50, 60].contains(offset)
    }

    private static func easterSunday(
        year: Int,
        calendar: Calendar
    ) -> Date? {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        )
    }

    private static func upperWeightLimit(in text: String) -> Int? {
        let withoutThousandsSeparators = text.replacingOccurrences(of: ".", with: "")
        return withoutThousandsSeparators
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap(Int.init)
            .max()
    }

    private static func convertedEUR(
        _ amount: Double,
        currencyCode: String,
        chfToEURRate: Double?
    ) -> Double? {
        switch currencyCode.uppercased() {
        case "EUR":
            return amount
        case "CHF":
            guard let chfToEURRate,
                  chfToEURRate.isFinite,
                  chfToEURRate > 0
            else { return nil }
            // Swiss tariff positions are always shown conservatively as full
            // euros. `ceil` deliberately rounds 31.01 EUR to 32 EUR.
            return ceil(amount * chfToEURRate)
        default:
            return nil
        }
    }

    private static func decimalEUR(from text: String) -> Double? {
        var normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !normalized.isEmpty else { return nil }
        if normalized.contains(",") {
            normalized = normalized
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
        }
        guard let value = Double(normalized), value >= 0 else { return nil }
        return value
    }
}

struct AirportSetupView: View {
    let destinations: [Destination]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedICAO = "EDFZ"
    @State private var searchText = "EDFZ · Mainz-Finthen"
    @State private var profile = AirportOpeningHoursProfile.edfz
    @State private var landingFees = AirportLandingFeeProfile()
    @State private var showsSuggestions = false
    @State private var savedConfirmation = false
    @State private var landingVoucherRevision = 0

    private var airportOptions: [(icao: String, name: String)] {
        var values: [(icao: String, name: String)] = [
            (icao: "EDFZ", name: "Mainz-Finthen"),
            (icao: "EDFU", name: "Mainbullau")
        ]
        values += destinations
            .filter { !["EDFZ", "EDFU"].contains($0.icao) }
            .map { (icao: $0.icao, name: $0.name) }
        return values.sorted { $0.icao < $1.icao }
    }

    private var normalizedQuery: String {
        searchText.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var suggestions: [(icao: String, name: String)] {
        guard normalizedQuery.count >= 2 else { return airportOptions }
        return Array(airportOptions.filter {
            "\($0.icao) \($0.name)".folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ).contains(normalizedQuery)
        }.prefix(8))
    }

    var body: some View {
        let _ = landingVoucherRevision
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AIRPORTS")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)
                    Text("Flugplatzdaten und Betriebszeiten")
                        .foregroundStyle(FlybookColor.muted)
                }
                Spacer()
                Button("Schließen") { dismiss() }
            }

            airportSearch

            if LandingVoucherBook.includes(selectedICAO) {
                HStack(spacing: 9) {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(FlybookColor.blue)
                    Text("Gutscheinheft \(LandingVoucherBook.yearLabel)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)
                    Text("gültig bis \(LandingVoucherBook.validUntilLabel)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FlybookColor.muted)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(FlybookColor.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(FlybookColor.blue.opacity(0.28)))
            }

            ScrollView {
                VStack(spacing: 14) {
                    seasonCard(
                        title: "SOMMER",
                        symbol: "sun.max.fill",
                        season: $profile.summer
                    )
                    seasonCard(
                        title: "WINTER",
                        symbol: "snowflake",
                        season: $profile.winter
                    )
                    if let rules = profile.dateRules, !rules.isEmpty {
                        dateRulesCard(rules)
                    }
                    landingFeeCard
                }
                .padding(.vertical, 2)
                .padding(.trailing, 5)
            }

            HStack {
                Text(savedConfirmation ? "Gespeichert" : "Zeiten in UTC/Z")
                    .font(.caption.bold())
                    .foregroundStyle(savedConfirmation ? Color.green : FlybookColor.muted)
                Spacer()
                Button("Speichern") {
                    AirportOpeningHoursStore.save(profile, for: selectedICAO)
                    AirportLandingFeeStore.save(landingFees, for: selectedICAO)
                    savedConfirmation = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 880, height: 720)
        .background(FlybookColor.background)
        .onAppear { selectAirport("EDFZ") }
        .onReceive(NotificationCenter.default.publisher(for: LandingVoucherBook.didRefreshNotification)) { _ in
            landingVoucherRevision += 1
        }
    }

    private var airportSearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FlybookColor.muted)
            TextField("ICAO oder Flugplatzname", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .onTapGesture { showsSuggestions = true }
                .onChange(of: searchText) { _ in showsSuggestions = true }
                .onSubmit {
                    if let first = suggestions.first { selectAirport(first.icao) }
                }
            Menu {
                ForEach(airportOptions, id: \.icao) { airport in
                    Button("\(airport.icao) · \(airport.name)") {
                        selectAirport(airport.icao)
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(FlybookColor.blue.opacity(0.6), lineWidth: 1.5))
        .overlay(alignment: .topLeading) {
            if showsSuggestions, normalizedQuery.count >= 2, !suggestions.isEmpty {
                VStack(spacing: 1) {
                    ForEach(suggestions, id: \.icao) { airport in
                        Button {
                            selectAirport(airport.icao)
                        } label: {
                            HStack {
                                Text(airport.icao).font(.system(.body, design: .monospaced).bold())
                                    .frame(width: 60, alignment: .leading)
                                Text(airport.name).lineLimit(1)
                                Spacer()
                            }
                            .foregroundStyle(FlybookColor.navy)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 5)
                .frame(width: 832)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(FlybookColor.line))
                .shadow(radius: 8, y: 4)
                .offset(y: 44)
                .zIndex(20)
            }
        }
        .zIndex(20)
    }

    private func seasonCard(
        title: String,
        symbol: String,
        season: Binding<AirportSeasonHours>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(FlybookColor.navy)
            Divider()
            openingHeader
            openingRow("Montag", period: season.monday)
            openingRow("Dienstag", period: season.tuesday)
            openingRow("Mittwoch", period: season.wednesday)
            openingRow("Donnerstag", period: season.thursday)
            openingRow("Freitag", period: season.friday)
            openingRow("Samstag", period: season.saturday)
            openingRow("Sonntag", period: season.sunday)
            openingRow("Feiertag", period: season.holiday)
            Toggle(
                "Außerhalb der Zeiten PPR (gilt als geschlossen)",
                isOn: season.outsideHoursPPR
            )
                .toggleStyle(.checkbox)
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(16)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(FlybookColor.line, lineWidth: 1.5))
    }

    private var landingFeeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("LANDEGEBÜHREN", systemImage: "eurosign.circle.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)
                Spacer()
                Text("\(landingFees.effectiveCurrencyCode) je Landung")
                    .font(.caption.bold())
                    .foregroundStyle(FlybookColor.muted)
            }
            Divider()
            HStack(spacing: 12) {
                Text("MTOW")
                    .frame(width: 155, alignment: .leading)
                Text("OHNE LÄRMSCHUTZ")
                    .frame(width: 175, alignment: .leading)
                Text("NORMALER LÄRMSCHUTZ")
                    .frame(width: 190, alignment: .leading)
                Text("ERWEITERTER LÄRMSCHUTZ")
                    .frame(width: 190, alignment: .leading)
                Spacer()
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(FlybookColor.muted)

            ForEach(landingFees.bands.indices, id: \.self) { index in
                HStack(spacing: 12) {
                    Text(landingFees.bands[index].weightBand)
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 155, alignment: .leading)
                    feeField($landingFees.bands[index].withoutNoiseProtectionEUR)
                        .frame(width: 175, alignment: .leading)
                    feeField($landingFees.bands[index].normalNoiseProtectionEUR)
                        .frame(width: 190, alignment: .leading)
                    feeField($landingFees.bands[index].enhancedNoiseProtectionEUR)
                        .frame(width: 190, alignment: .leading)
                    Spacer()
                }
            }

            Divider()
            Text("WEITERE FLUGPLATZGEBÜHREN")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
            HStack(spacing: 24) {
                ancillaryFeeField(
                    "Parken über Nacht · je Nacht",
                    value: optionalFeeBinding(\.overnightParkingPerNightEUR)
                )
                ancillaryFeeField(
                    "Zollabfertigung · je Kontrolle",
                    value: optionalFeeBinding(\.customsClearancePerControlEUR)
                )
                ancillaryFeeField(
                    "Handling · je Bewegung",
                    value: optionalFeeBinding(\.handlingPerMovementEUR)
                )
                ancillaryFeeField(
                    "Zoll außerhalb Bürozeit · Zuschlag",
                    value: optionalFeeBinding(\.customsOutsideOfficeHoursSurchargeEUR)
                )
                ancillaryFeeField(
                    "Winterdienst · je Landung",
                    value: optionalFeeBinding(\.winterServiceSurchargeEUR)
                )
            }

            Text("Dezimalwerte können mit Komma oder Punkt eingegeben werden.")
                .font(.caption)
                .foregroundStyle(FlybookColor.muted)
        }
        .padding(16)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(FlybookColor.line, lineWidth: 1.5))
    }

    private func dateRulesCard(_ rules: [AirportDateRule]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("DATUMSABHÄNGIGE BETRIEBSZEITEN", systemImage: "calendar.badge.clock")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(FlybookColor.navy)
            Divider()
            ForEach(rules) { rule in
                HStack {
                    Text(rule.label)
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 180, alignment: .leading)
                    Text(
                        rule.summary
                            ?? "\(rule.period.fromUTC)–\(rule.period.fixedUntilUTC) Z"
                    )
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .lineLimit(2)
                    Spacer()
                    Text("O/T geschlossen")
                        .font(.caption.bold())
                        .foregroundStyle(FlybookColor.muted)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(FlybookColor.line, lineWidth: 1.5))
    }

    private func feeField(_ value: Binding<String>) -> some View {
        HStack(spacing: 5) {
            TextField("0,00", text: value)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 92)
            Text(landingFees.effectiveCurrencyCode)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
        }
    }

    private func ancillaryFeeField(
        _ title: String,
        value: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FlybookColor.navy)
                .lineLimit(1)
            feeField(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func optionalFeeBinding(
        _ keyPath: WritableKeyPath<AirportLandingFeeProfile, String?>
    ) -> Binding<String> {
        Binding(
            get: { landingFees[keyPath: keyPath] ?? "" },
            set: { landingFees[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private var openingHeader: some View {
        HStack(spacing: 10) {
            Text("TAGE").frame(width: 145, alignment: .leading)
            Text("VON (Z)").frame(width: 90, alignment: .leading)
            Text("BIS").frame(width: 150, alignment: .leading)
            Text("SS-OFFSET").frame(width: 105, alignment: .leading)
            Text("FESTE ZEIT / MAX (Z)").frame(width: 165, alignment: .leading)
            Spacer()
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(FlybookColor.muted)
    }

    private func openingRow(
        _ title: String,
        period: Binding<AirportOpeningPeriod>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 145, alignment: .leading)
                timeField(period.fromUTC)
                Picker("Bis", selection: period.closingReference) {
                    ForEach(AirportClosingReference.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                Stepper(value: period.sunsetOffsetMinutes, in: -120...120, step: 5) {
                    Text(offsetText(period.wrappedValue.sunsetOffsetMinutes))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .frame(width: 52, alignment: .trailing)
                }
                .frame(width: 105)
                timeField(
                    period.wrappedValue.closingReference == .fixed
                        ? period.fixedUntilUTC
                        : period.latestUTC
                )
                .frame(width: 165, alignment: .leading)
                Spacer()
            }
            if period.wrappedValue.openingReference == .sunrise {
                Text("Beginn: späterer Wert aus \(period.wrappedValue.fromUTC) Z und SR\(signedOffset(period.wrappedValue.sunriseOffsetMinutes ?? 0))")
                    .font(.caption.bold())
                    .foregroundStyle(FlybookColor.muted)
                    .padding(.leading, 155)
            }
            if let landingUntil = period.wrappedValue.landingUntilUTC, !landingUntil.isEmpty {
                Text("Landungen im 1. Zeitfenster bis \(landingUntil) Z")
                    .font(.caption.bold())
                    .foregroundStyle(FlybookColor.blue)
                    .padding(.leading, 155)
            }
            if let secondFrom = period.wrappedValue.secondFromUTC, !secondFrom.isEmpty {
                Text("2. Zeitfenster: \(secondFrom) Z–\(secondClosingLabel(period.wrappedValue))")
                    .font(.caption.bold())
                    .foregroundStyle(FlybookColor.blue)
                    .padding(.leading, 155)
            }
        }
    }

    private func signedOffset(_ minutes: Int) -> String {
        minutes >= 0 ? "+\(minutes)" : "\(minutes)"
    }

    private func secondClosingLabel(_ period: AirportOpeningPeriod) -> String {
        if period.secondClosingReference == .fixed {
            return "\(period.secondFixedUntilUTC ?? "—") Z"
        }
        let offset = signedOffset(period.secondSunsetOffsetMinutes ?? 0)
        if let latest = period.secondLatestUTC, !latest.isEmpty {
            return "SS\(offset), max. \(latest) Z"
        }
        return "SS\(offset)"
    }

    private func timeField(_ value: Binding<String>) -> some View {
        TextField("HH:MM", text: value)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .frame(width: 90)
    }

    private func offsetText(_ minutes: Int) -> String {
        if minutes == 0 { return "SS" }
        return minutes > 0 ? "SS+\(minutes)" : "SS\(minutes)"
    }

    private func selectAirport(_ icao: String) {
        guard let airport = airportOptions.first(where: { $0.icao == icao }) else { return }
        selectedICAO = airport.icao
        searchText = "\(airport.icao) · \(airport.name)"
        profile = AirportOpeningHoursStore.profile(for: airport.icao)
        landingFees = AirportLandingFeeStore.profile(for: airport.icao)
        showsSuggestions = false
        savedConfirmation = false
    }
}
