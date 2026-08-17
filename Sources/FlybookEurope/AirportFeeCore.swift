import Foundation

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

    static let lsgt = AirportLandingFeeProfile(
        bands: [
            AirportLandingFeeBand(
                weightBand: "bis 600 kg",
                withoutNoiseProtectionEUR: "20",
                normalNoiseProtectionEUR: "20",
                enhancedNoiseProtectionEUR: "20"
            ),
            AirportLandingFeeBand(
                weightBand: "601–1.000 kg",
                withoutNoiseProtectionEUR: "22",
                normalNoiseProtectionEUR: "22",
                enhancedNoiseProtectionEUR: "22"
            ),
            AirportLandingFeeBand(
                weightBand: "1.001–1.500 kg",
                withoutNoiseProtectionEUR: "24",
                normalNoiseProtectionEUR: "24",
                enhancedNoiseProtectionEUR: "24"
            ),
            AirportLandingFeeBand(
                weightBand: "1.501–2.000 kg",
                withoutNoiseProtectionEUR: "26",
                normalNoiseProtectionEUR: "26",
                enhancedNoiseProtectionEUR: "26"
            ),
            AirportLandingFeeBand(
                weightBand: "2.001–2.500 kg",
                withoutNoiseProtectionEUR: "35",
                normalNoiseProtectionEUR: "35",
                enhancedNoiseProtectionEUR: "35"
            ),
            AirportLandingFeeBand(
                weightBand: "2.501–3.500 kg",
                withoutNoiseProtectionEUR: "45",
                normalNoiseProtectionEUR: "45",
                enhancedNoiseProtectionEUR: "45"
            )
        ],
        basicTrainingLandingFeeEUR: "18",
        overnightParkingPerNightEUR: "10",
        customsClearancePerControlEUR: "10",
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
            if normalized == "LSGT", saved.isCompletelyEmpty { return .lsgt }
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
        if normalized == "LSGT" { return .lsgt }
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
        voucherProvider: (String, Date) -> Bool = { _, _ in false },
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
