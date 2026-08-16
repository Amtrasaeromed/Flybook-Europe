import SwiftUI

enum PressureDisplayUnit: String, CaseIterable, Identifiable {
    case mbar
    case inHg

    var id: String { rawValue }
    var label: String { self == .mbar ? "mbar" : "inHg" }
}

enum PressureSettingsKey {
    static let displayUnit = "flybookPressureDisplayUnit"
}

enum FuelDisplayUnit: String, CaseIterable, Identifiable {
    case liters
    case usGallons

    var id: String { rawValue }
    var label: String { self == .liters ? "Liter" : "US gal" }
    var symbol: String { self == .liters ? "L" : "gal" }

    func fromLiters(_ liters: Double) -> Double {
        self == .liters ? liters : liters / 3.785_411_784
    }

    func toLiters(_ quantity: Double) -> Double {
        self == .liters ? quantity : quantity * 3.785_411_784
    }
}

enum CalculationSettingsKey {
    static let tankStopMinutes =
        "flybookTankStopMinutes"
    static let vatPercent =
        "flybookVATPercent"
    static let weekdayDiscountEnabled =
        "flybookWeekdayDiscountEnabled"
    static let flyingWithoutFlightDirectorEnabled =
        "flybookFlyingWithoutFlightDirectorEnabled"
    static let reserveMinutes =
        "flybookReserveMinutes"
    static let maxTravelMinutesUntilOvernight =
        "flybookMaxTravelMinutesUntilOvernight"
    static let prepaymentDiscount15To29Enabled =
        "flybookPrepaymentDiscount15To29Enabled"
    static let prepaymentDiscount30PlusEnabled =
        "flybookPrepaymentDiscount30PlusEnabled"
    static let fuelDisplayUnit =
        "flybookFuelDisplayUnit"
    static let preTakeoffGroundMinutes =
        "flybookPreTakeoffGroundMinutes"
    static let postLandingGroundMinutes =
        "flybookPostLandingGroundMinutes"
    static let runwayPerformanceSafetyMarginPercent =
        "flybookRunwayPerformanceSafetyMarginPercent"
    static let reservationFromTimestamp =
        "flybookReservationFromTimestamp"
    static let reservationUntilTimestamp =
        "flybookReservationUntilTimestamp"
    static let calculatedBlockMinutes =
        "flybookCalculatedBlockMinutes"
}

enum CalculationSettings {
    static let defaultTankStopMinutes = 60
    static let defaultVATPercent = 7.0
    static let defaultWeekdayDiscountEnabled = true
    static let defaultFlyingWithoutFlightDirectorEnabled = true
    static let defaultReserveMinutes = 45
    static let defaultMaxTravelMinutesUntilOvernight = 105
    static let defaultPrepaymentDiscount15To29Enabled = false
    static let defaultPrepaymentDiscount30PlusEnabled = false
    static let defaultPreTakeoffGroundMinutes = 5
    static let defaultPostLandingGroundMinutes = 3
    static let defaultRunwayPerformanceSafetyMarginPercent = 0
}

enum FlybookBase: String, CaseIterable, Identifiable {
    case lsvMainz = "LSV Mainz"
    var id: String { rawValue }
}

enum BaseSettingsKey { static let activeBase = "flybookActiveBase" }

struct BaseProfile {
    var homeAirportICAO: String
    var vatPercent: Double
    var flyingWithoutFlightDirectorEnabled: Bool
    var weekdayDiscountEnabled: Bool
    var prepaymentDiscount15To29Enabled: Bool
    var prepaymentDiscount30PlusEnabled: Bool
}

enum BaseProfileStore {
    private static func key(_ base: FlybookBase, _ item: String) -> String {
        "baseProfile.\(base.rawValue).\(item)"
    }
    static func profile(for base: FlybookBase) -> BaseProfile {
        let d = UserDefaults.standard
        func number(_ name: String, _ fallback: Double) -> Double {
            d.object(forKey: key(base, name)) == nil ? fallback : d.double(forKey: key(base, name))
        }
        func flag(_ name: String, _ fallback: Bool) -> Bool {
            d.object(forKey: key(base, name)) == nil ? fallback : d.bool(forKey: key(base, name))
        }
        let discount15To29 = flag(
            "prepaymentDiscount15To29Enabled",
            CalculationSettings.defaultPrepaymentDiscount15To29Enabled
        )
        let discount30Plus = flag(
            "prepaymentDiscount30PlusEnabled",
            CalculationSettings.defaultPrepaymentDiscount30PlusEnabled
        )
        return BaseProfile(
            homeAirportICAO: d.string(forKey: key(base, "homeAirportICAO")) ?? "EDFZ",
            vatPercent: number("vatPercent", CalculationSettings.defaultVATPercent),
            flyingWithoutFlightDirectorEnabled: flag(
                "flyingWithoutFlightDirectorEnabled",
                CalculationSettings.defaultFlyingWithoutFlightDirectorEnabled
            ),
            weekdayDiscountEnabled: flag("weekdayDiscountEnabled", CalculationSettings.defaultWeekdayDiscountEnabled),
            prepaymentDiscount15To29Enabled: discount15To29,
            prepaymentDiscount30PlusEnabled: discount30Plus && !discount15To29
        )
    }
    static func save(_ profile: BaseProfile, for base: FlybookBase) {
        let d = UserDefaults.standard
        var profile = profile
        if profile.prepaymentDiscount15To29Enabled {
            profile.prepaymentDiscount30PlusEnabled = false
        }
        d.set(profile.homeAirportICAO, forKey: key(base, "homeAirportICAO"))
        d.set(profile.vatPercent, forKey: key(base, "vatPercent"))
        d.set(profile.flyingWithoutFlightDirectorEnabled, forKey: key(base, "flyingWithoutFlightDirectorEnabled"))
        d.set(profile.weekdayDiscountEnabled, forKey: key(base, "weekdayDiscountEnabled"))
        d.set(profile.prepaymentDiscount15To29Enabled, forKey: key(base, "prepaymentDiscount15To29Enabled"))
        d.set(profile.prepaymentDiscount30PlusEnabled, forKey: key(base, "prepaymentDiscount30PlusEnabled"))
    }
    static func activate(_ base: FlybookBase) {
        let d = UserDefaults.standard
        let p = profile(for: base)
        d.set(base.rawValue, forKey: BaseSettingsKey.activeBase)
        d.set(p.vatPercent, forKey: CalculationSettingsKey.vatPercent)
        d.set(
            p.flyingWithoutFlightDirectorEnabled,
            forKey: CalculationSettingsKey.flyingWithoutFlightDirectorEnabled
        )
        d.set(p.weekdayDiscountEnabled, forKey: CalculationSettingsKey.weekdayDiscountEnabled)
        d.set(p.prepaymentDiscount15To29Enabled, forKey: CalculationSettingsKey.prepaymentDiscount15To29Enabled)
        d.set(p.prepaymentDiscount30PlusEnabled, forKey: CalculationSettingsKey.prepaymentDiscount30PlusEnabled)
    }
}

struct BaseSetupView: View {
    let destinations: [Destination]
    @AppStorage(BaseSettingsKey.activeBase) private var activeBaseRaw = FlybookBase.lsvMainz.rawValue
    @State private var base = FlybookBase.lsvMainz
    @State private var profile = BaseProfileStore.profile(for: .lsvMainz)
    @Environment(\.dismiss) private var dismiss

    private var discount15To29Binding: Binding<Bool> {
        Binding(
            get: { profile.prepaymentDiscount15To29Enabled },
            set: { enabled in
                profile.prepaymentDiscount15To29Enabled = enabled
                if enabled { profile.prepaymentDiscount30PlusEnabled = false }
            }
        )
    }

    private var discount30PlusBinding: Binding<Bool> {
        Binding(
            get: { profile.prepaymentDiscount30PlusEnabled },
            set: { enabled in
                profile.prepaymentDiscount30PlusEnabled = enabled
                if enabled { profile.prepaymentDiscount15To29Enabled = false }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Vereinskonfiguration")
                    .font(.system(size: 24, weight: .bold))
                Spacer()
                Button("Schließen") { dismiss() }
            }

            Grid(
                alignment: .leading,
                horizontalSpacing: 18,
                verticalSpacing: 16
            ) {
                GridRow {
                    settingLabel("Basis")
                    Picker("Basis", selection: $base) {
                        ForEach(FlybookBase.allCases) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 350, alignment: .leading)
                }

                GridRow {
                    settingLabel("Heimatflugplatz")
                    Picker(
                        "Heimatflugplatz",
                        selection: $profile.homeAirportICAO
                    ) {
                        Text("EDFZ · Mainz-Finthen").tag("EDFZ")
                        ForEach(destinations.filter { $0.icao != "EDFZ" }) {
                            Text("\($0.icao) · \($0.name)").tag($0.icao)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 350, alignment: .leading)
                }

                GridRow {
                    settingLabel("Mehrwertsteuer")
                    HStack(spacing: 8) {
                        TextField(
                            "Mehrwertsteuer",
                            value: $profile.vatPercent,
                            format: .number.precision(.fractionLength(1))
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        Text("%")
                    }
                }

                GridRow {
                    Color.clear.frame(width: 170, height: 1)
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(
                            "Fliegen ohne Flugleiter",
                            isOn: $profile.flyingWithoutFlightDirectorEnabled
                        )
                        Toggle(
                            "Werktagsrabatt",
                            isOn: $profile.weekdayDiscountEnabled
                        )
                        Toggle(
                            "Vorauszahlungsrabatt 15–29 h",
                            isOn: discount15To29Binding
                        )
                        Toggle(
                            "Vorauszahlungsrabatt ab 30 h",
                            isOn: discount30PlusBinding
                        )
                    }
                    .toggleStyle(.checkbox)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Speichern und aktivieren") {
                    BaseProfileStore.save(profile, for: base)
                    BaseProfileStore.activate(base)
                    activeBaseRaw = base.rawValue
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 680, height: 440)
        .onChange(of: base) { profile = BaseProfileStore.profile(for: $0) }
    }

    private func settingLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 170, alignment: .trailing)
    }
}

enum ETOPSSettingsKey {
    static let greenYellowMinutes = "etopsGreenYellowMinutes"
    static let orangeRedMinutes = "etopsOrangeRedMinutes"
    static let activeUser = "etopsActiveUser"
}

enum FlybookUser: String, CaseIterable, Identifiable {
    case stephan = "Stephan"
    case maria = "Maria"

    var id: String { rawValue }
}

enum ETOPSProfileStore {
    private static let persistentDefaults =
        UserDefaults(suiteName: "de.flybook.europe.user-profiles")!

    private static func key(
        _ user: FlybookUser,
        _ value: String
    ) -> String {
        "etopsProfile.\(user.rawValue).\(value)"
    }

    static func greenYellow(for user: FlybookUser) -> Int {
        let defaults = persistentDefaults
        let profileKey = key(user, "greenYellowMinutes")
        migrateLegacyValue(forKey: profileKey)
        if defaults.object(forKey: profileKey) != nil {
            return defaults.integer(forKey: profileKey)
        }
        if user == .stephan,
           defaults.object(
            forKey: ETOPSSettingsKey.greenYellowMinutes
           ) != nil
        {
            return defaults.integer(
                forKey: ETOPSSettingsKey.greenYellowMinutes
            )
        }
        return ETOPSScale.defaultGreenYellowMinutes
    }

    static func orangeRed(for user: FlybookUser) -> Int {
        let defaults = persistentDefaults
        let profileKey = key(user, "orangeRedMinutes")
        migrateLegacyValue(forKey: profileKey)
        if defaults.object(forKey: profileKey) != nil {
            return defaults.integer(forKey: profileKey)
        }
        if user == .stephan,
           defaults.object(
            forKey: ETOPSSettingsKey.orangeRedMinutes
           ) != nil
        {
            return defaults.integer(
                forKey: ETOPSSettingsKey.orangeRedMinutes
            )
        }
        return ETOPSScale.defaultOrangeRedMinutes
    }

    private static func integer(
        _ value: String,
        for user: FlybookUser,
        fallback: Int
    ) -> Int {
        let defaults = persistentDefaults
        let profileKey = key(user, value)
        migrateLegacyValue(forKey: profileKey)
        return defaults.object(forKey: profileKey) == nil
            ? fallback
            : defaults.integer(forKey: profileKey)
    }

    static func tankStopMinutes(for user: FlybookUser) -> Int {
        integer("tankStopMinutes", for: user, fallback: CalculationSettings.defaultTankStopMinutes)
    }

    static func preTakeoffGroundMinutes(for user: FlybookUser) -> Int {
        integer("preTakeoffGroundMinutes", for: user, fallback: CalculationSettings.defaultPreTakeoffGroundMinutes)
    }

    static func postLandingGroundMinutes(for user: FlybookUser) -> Int {
        integer("postLandingGroundMinutes", for: user, fallback: CalculationSettings.defaultPostLandingGroundMinutes)
    }

    static func runwayPerformanceSafetyMarginPercent(
        for user: FlybookUser
    ) -> Int {
        integer(
            "runwayPerformanceSafetyMarginPercent",
            for: user,
            fallback: CalculationSettings.defaultRunwayPerformanceSafetyMarginPercent
        )
    }

    static func reserveMinutes(for user: FlybookUser) -> Int {
        integer("reserveMinutes", for: user, fallback: CalculationSettings.defaultReserveMinutes)
    }

    static func maximumDailyTravelMinutes(for user: FlybookUser) -> Int {
        integer("maximumDailyTravelMinutes", for: user, fallback: CalculationSettings.defaultMaxTravelMinutesUntilOvernight)
    }

    static func save(
        user: FlybookUser,
        greenYellow: Int,
        orangeRed: Int,
        tankStopMinutes: Int,
        preTakeoffGroundMinutes: Int,
        postLandingGroundMinutes: Int,
        runwayPerformanceSafetyMarginPercent: Int,
        reserveMinutes: Int,
        maximumDailyTravelMinutes: Int,
        activate: Bool
    ) {
        let limits = ETOPSScale.normalized(
            greenYellow: greenYellow,
            orangeRed: orangeRed
        )
        let defaults = persistentDefaults
        defaults.set(
            limits.greenYellow,
            forKey: key(user, "greenYellowMinutes")
        )
        defaults.set(
            limits.orangeRed,
            forKey: key(user, "orangeRedMinutes")
        )
        defaults.set(tankStopMinutes, forKey: key(user, "tankStopMinutes"))
        defaults.set(preTakeoffGroundMinutes, forKey: key(user, "preTakeoffGroundMinutes"))
        defaults.set(postLandingGroundMinutes, forKey: key(user, "postLandingGroundMinutes"))
        defaults.set(
            min(50, max(0, runwayPerformanceSafetyMarginPercent / 5 * 5)),
            forKey: key(user, "runwayPerformanceSafetyMarginPercent")
        )
        defaults.set(reserveMinutes, forKey: key(user, "reserveMinutes"))
        defaults.set(maximumDailyTravelMinutes, forKey: key(user, "maximumDailyTravelMinutes"))
        defaults.synchronize()
        if activate {
            self.activate(user)
        }
    }

    static func activate(_ user: FlybookUser) {
        let defaults = UserDefaults.standard
        persistentDefaults.set(user.rawValue, forKey: ETOPSSettingsKey.activeUser)
        persistentDefaults.synchronize()
        defaults.set(
            user.rawValue,
            forKey: ETOPSSettingsKey.activeUser
        )
        defaults.set(
            greenYellow(for: user),
            forKey: ETOPSSettingsKey.greenYellowMinutes
        )
        defaults.set(
            orangeRed(for: user),
            forKey: ETOPSSettingsKey.orangeRedMinutes
        )
        defaults.set(tankStopMinutes(for: user), forKey: CalculationSettingsKey.tankStopMinutes)
        defaults.set(preTakeoffGroundMinutes(for: user), forKey: CalculationSettingsKey.preTakeoffGroundMinutes)
        defaults.set(postLandingGroundMinutes(for: user), forKey: CalculationSettingsKey.postLandingGroundMinutes)
        defaults.set(
            runwayPerformanceSafetyMarginPercent(for: user),
            forKey: CalculationSettingsKey.runwayPerformanceSafetyMarginPercent
        )
        defaults.set(reserveMinutes(for: user), forKey: CalculationSettingsKey.reserveMinutes)
        defaults.set(maximumDailyTravelMinutes(for: user), forKey: CalculationSettingsKey.maxTravelMinutesUntilOvernight)
    }

    static func restorePersistentProfiles() {
        for user in FlybookUser.allCases {
            for value in [
                "greenYellowMinutes", "orangeRedMinutes", "tankStopMinutes",
                "preTakeoffGroundMinutes", "postLandingGroundMinutes",
                "runwayPerformanceSafetyMarginPercent",
                "reserveMinutes", "maximumDailyTravelMinutes"
            ] {
                migrateLegacyValue(forKey: key(user, value))
            }
        }

        let storedName = persistentDefaults.string(
            forKey: ETOPSSettingsKey.activeUser
        )
        let standardName = UserDefaults.standard.string(
            forKey: ETOPSSettingsKey.activeUser
        )
        let user = FlybookUser(rawValue: storedName ?? standardName ?? "")
            ?? .stephan
        activate(user)
    }

    private static func migrateLegacyValue(forKey profileKey: String) {
        guard persistentDefaults.object(forKey: profileKey) == nil,
              let legacyValue = UserDefaults.standard.object(forKey: profileKey)
        else { return }
        persistentDefaults.set(legacyValue, forKey: profileKey)
    }
}

enum ETOPSScale {
    static let defaultGreenYellowMinutes = 105
    static let defaultOrangeRedMinutes = 150

    static func normalized(
        greenYellow: Int,
        orangeRed: Int
    ) -> (greenYellow: Int, yellowOrange: Int, orangeRed: Int, maximum: Int) {
        let green = max(30, greenYellow)
        let red = max(green + 10, orangeRed)
        let middle = green + (red - green) / 2
        let maximum = red + max(20, (red - green) / 2)
        return (green, middle, red, maximum)
    }

    static func color(
        for travelMinutes: Int,
        greenYellow: Int,
        orangeRed: Int
    ) -> Color {
        let limits = normalized(
            greenYellow: greenYellow,
            orangeRed: orangeRed
        )

        if travelMinutes < limits.greenYellow {
            return .green
        }
        if travelMinutes < limits.yellowOrange {
            return .yellow
        }
        if travelMinutes < limits.orangeRed {
            return .orange
        }
        return .red
    }

    static func isRed(
        travelMinutes: Int,
        greenYellow: Int,
        orangeRed: Int
    ) -> Bool {
        travelMinutes >= normalized(
            greenYellow: greenYellow,
            orangeRed: orangeRed
        ).orangeRed
    }
}

struct ETOPSSetupView: View {
    @AppStorage(LandingVoucherBook.settingKey)
    private var landingVoucherBookEnabled = false

    @State
    private var greenYellowMinutes =
        ETOPSScale.defaultGreenYellowMinutes

    @State
    private var orangeRedMinutes =
        ETOPSScale.defaultOrangeRedMinutes

    @AppStorage(ETOPSSettingsKey.activeUser)
    private var activeUserRaw = FlybookUser.stephan.rawValue

    @State
    private var editedUserRaw = FlybookUser.stephan.rawValue

    @AppStorage(CalculationSettingsKey.tankStopMinutes)
    private var tankStopMinutes =
        CalculationSettings.defaultTankStopMinutes

    @AppStorage(CalculationSettingsKey.vatPercent)
    private var vatPercent =
        CalculationSettings.defaultVATPercent

    @AppStorage(CalculationSettingsKey.weekdayDiscountEnabled)
    private var weekdayDiscountEnabled =
        CalculationSettings.defaultWeekdayDiscountEnabled

    @AppStorage(CalculationSettingsKey.reserveMinutes)
    private var reserveMinutes =
        CalculationSettings.defaultReserveMinutes

    @AppStorage(CalculationSettingsKey.preTakeoffGroundMinutes)
    private var preTakeoffGroundMinutes =
        CalculationSettings.defaultPreTakeoffGroundMinutes

    @AppStorage(CalculationSettingsKey.postLandingGroundMinutes)
    private var postLandingGroundMinutes =
        CalculationSettings.defaultPostLandingGroundMinutes

    @AppStorage(CalculationSettingsKey.runwayPerformanceSafetyMarginPercent)
    private var runwayPerformanceSafetyMarginPercent =
        CalculationSettings.defaultRunwayPerformanceSafetyMarginPercent

    @AppStorage(
        CalculationSettingsKey.prepaymentDiscount15To29Enabled
    )
    private var prepaymentDiscount15To29Enabled =
        CalculationSettings
            .defaultPrepaymentDiscount15To29Enabled

    @AppStorage(
        CalculationSettingsKey.prepaymentDiscount30PlusEnabled
    )
    private var prepaymentDiscount30PlusEnabled =
        CalculationSettings
            .defaultPrepaymentDiscount30PlusEnabled

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allgemeines Setup")
                        .font(.title2.bold())
                    Text("Flugkalkulation, Anzeige und ETOPS-PIPI")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Schließen") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            settingsCard("Nutzerprofil", systemImage: "person.crop.circle") {
                HStack(spacing: 16) {
                    Picker(
                        "Nutzer",
                        selection: $editedUserRaw
                    ) {
                        ForEach(FlybookUser.allCases) { user in
                            Text(user.rawValue).tag(user.rawValue)
                        }
                    }
                    .frame(width: 180)

                    Button("Profil speichern") {
                        saveProfile(activate: false)
                    }
                    .buttonStyle(.bordered)

                    Button("Speichern und aktivieren") {
                        saveAndActivateProfile()
                    }
                    .buttonStyle(.borderedProminent)

                    if editedUserRaw == activeUserRaw {
                        Label(
                            "Aktiv",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                    }
                }
            }

            settingsCard("Gutscheinheft", systemImage: "book.closed.fill") {
                HStack(spacing: 12) {
                    Toggle(
                        "Gutscheinheft \(LandingVoucherBook.yearLabel)",
                        isOn: $landingVoucherBookEnabled
                    )
                    .toggleStyle(.checkbox)
                    .font(.headline)
                    Text("gültig bis \(LandingVoucherBook.validUntilLabel)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FlybookColor.muted)
                    Spacer()
                }
            }

            settingsCard("ETOPS-PIPI", systemImage: "clock.badge.exclamationmark") {
                VStack(alignment: .leading, spacing: 14) {
                    thresholdRow(
                        title: "ETOPS PIPI gelb",
                        minutes: $greenYellowMinutes,
                        color: .yellow
                    )

                    thresholdRow(
                        title: "ETOPS PIPI rot",
                        minutes: $orangeRedMinutes,
                        color: .red
                    )

                    Text("Die Zeiten beziehen sich auf die berechnete Dauer eines einzelnen Fluglegs einschließlich Windeinfluss.")
                        .font(.caption)
                        .foregroundStyle(FlybookColor.muted)
                }
            }

            settingsCard("Flugkalkulation", systemImage: "function") {
                VStack(alignment: .leading, spacing: 14) {
                    calculationTimeRow(
                        title: "Tankstoppzeit",
                        minutes: $tankStopMinutes,
                        range: 0...180,
                        step: 5
                    )

                    groundTimeRow(
                        title: "Vor Start (Warmlauf/Taxi)",
                        minutes: $preTakeoffGroundMinutes
                    )

                    groundTimeRow(
                        title: "Nach Landung (Taxi)",
                        minutes: $postLandingGroundMinutes
                    )

                    runwaySafetyMarginRow

                    HStack {
                        Text("Reserve")
                            .font(.headline)
                            .frame(width: 250, alignment: .leading)

                        Picker(
                            "Reserve",
                            selection: $reserveMinutes
                        ) {
                            Text("30 min").tag(30)
                            Text("45 min").tag(45)
                            Text("60 min").tag(60)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                        Spacer()
                    }

                    Text(
                        "Blockzeit umfasst Flug- und Rollzeit, "
                        + "nicht die Standzeit beim Tankstopp."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack {
                Button("Standardwerte wiederherstellen") {
                    greenYellowMinutes =
                        ETOPSScale.defaultGreenYellowMinutes
                    orangeRedMinutes =
                        ETOPSScale.defaultOrangeRedMinutes
                    tankStopMinutes =
                        CalculationSettings.defaultTankStopMinutes
                    reserveMinutes =
                        CalculationSettings
                            .defaultReserveMinutes
                    runwayPerformanceSafetyMarginPercent =
                        CalculationSettings
                            .defaultRunwayPerformanceSafetyMarginPercent
                }
                Spacer()
            }
            }
            .padding(28)
        }
        .frame(width: 840, height: 780)
        .background(FlybookColor.background)
        .onAppear {
            editedUserRaw = activeUserRaw
            loadEditedProfile()
        }
        .onChange(of: editedUserRaw) { _ in
            loadEditedProfile()
        }
        .onChange(of: greenYellowMinutes) { newValue in
            if newValue >= orangeRedMinutes {
                orangeRedMinutes = newValue + 10
            }
        }
        .onChange(of: orangeRedMinutes) { newValue in
            if newValue <= greenYellowMinutes {
                greenYellowMinutes = max(30, newValue - 10)
            }
        }
    }

    private func settingsCard<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(FlybookColor.blue))
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(FlybookColor.navy)
                Spacer()
            }

            Divider().overlay(FlybookColor.line)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: FlybookColor.navy.opacity(0.07), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FlybookColor.line, lineWidth: 1)
        )
    }

    private func groundTimeRow(
        title: String,
        minutes: Binding<Int>
    ) -> some View {
        calculationTimeRow(
            title: title,
            minutes: minutes,
            range: 0...30,
            step: 1
        )
    }

    private var runwaySafetyMarginRow: some View {
        HStack(spacing: 18) {
            Text("Sicherheitsmarge Start/Landung")
                .font(.headline)
                .frame(width: 250, alignment: .leading)

            Slider(
                value: Binding(
                    get: { Double(runwayPerformanceSafetyMarginPercent) },
                    set: { runwayPerformanceSafetyMarginPercent = Int($0.rounded()) }
                ),
                in: 0...50,
                step: 5
            )
            .frame(width: 260)

            Text("\(runwayPerformanceSafetyMarginPercent) %")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .frame(width: 48, alignment: .trailing)

            Spacer()
        }
        .help("Wird auf Rollstrecke und 50-ft-Strecke für Start und Landung aufgeschlagen")
    }

    private func calculationTimeRow(
        title: String,
        minutes: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        HStack(spacing: 18) {
            Text(title)
                .font(.headline)
                .frame(width: 250, alignment: .leading)

            HStack(spacing: 5) {
                TextField("0", value: minutes, format: .number)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .frame(width: 74)

                Text("min")
                    .foregroundStyle(FlybookColor.muted)
                    .frame(width: 28, alignment: .leading)

                Stepper(title, value: minutes, in: range, step: step)
                    .labelsHidden()
                    .fixedSize()
            }
            Spacer()
        }
    }

    private func loadEditedProfile() {
        let user = FlybookUser(rawValue: editedUserRaw)
            ?? .stephan
        greenYellowMinutes =
            ETOPSProfileStore.greenYellow(for: user)
        orangeRedMinutes =
            ETOPSProfileStore.orangeRed(for: user)
        tankStopMinutes = ETOPSProfileStore.tankStopMinutes(for: user)
        preTakeoffGroundMinutes = ETOPSProfileStore.preTakeoffGroundMinutes(for: user)
        postLandingGroundMinutes = ETOPSProfileStore.postLandingGroundMinutes(for: user)
        runwayPerformanceSafetyMarginPercent =
            ETOPSProfileStore.runwayPerformanceSafetyMarginPercent(for: user)
        reserveMinutes = ETOPSProfileStore.reserveMinutes(for: user)
    }

    private func saveAndActivateProfile() {
        saveProfile(activate: true)
    }

    private func saveProfile(activate: Bool) {
        let user = FlybookUser(rawValue: editedUserRaw)
            ?? .stephan
        ETOPSProfileStore.save(
            user: user,
            greenYellow: greenYellowMinutes,
            orangeRed: orangeRedMinutes,
            tankStopMinutes: tankStopMinutes,
            preTakeoffGroundMinutes: preTakeoffGroundMinutes,
            postLandingGroundMinutes: postLandingGroundMinutes,
            runwayPerformanceSafetyMarginPercent:
                runwayPerformanceSafetyMarginPercent,
            reserveMinutes: reserveMinutes,
            maximumDailyTravelMinutes:
                ETOPSProfileStore.maximumDailyTravelMinutes(for: user),
            activate: activate
        )
        if activate {
            activeUserRaw = user.rawValue
        }
    }

    private var prepaymentDiscount15To29Binding:
        Binding<Bool>
    {
        Binding(
            get: {
                prepaymentDiscount15To29Enabled
            },
            set: { enabled in
                prepaymentDiscount15To29Enabled = enabled

                if enabled {
                    prepaymentDiscount30PlusEnabled = false
                }
            }
        )
    }

    private var prepaymentDiscount30PlusBinding:
        Binding<Bool>
    {
        Binding(
            get: {
                prepaymentDiscount30PlusEnabled
            },
            set: { enabled in
                prepaymentDiscount30PlusEnabled = enabled

                if enabled {
                    prepaymentDiscount15To29Enabled = false
                }
            }
        )
    }

    private func thresholdRow(
        title: String,
        minutes: Binding<Int>,
        color: Color
    ) -> some View {
        HStack(spacing: 18) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 16, height: 16)

                Text(title)
                    .font(.headline)
            }
            .frame(width: 250, alignment: .leading)

            Picker("Stunden", selection: hourBinding(minutes)) {
                ForEach(0..<10, id: \.self) { hour in
                    Text("\(hour) h").tag(hour)
                }
            }
            .labelsHidden()
            .fixedSize()

            Picker("Minuten", selection: minuteBinding(minutes)) {
                ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { minute in
                    Text(String(format: "%02d min", minute)).tag(minute)
                }
            }
            .labelsHidden()
            .fixedSize()

            Text(duration(minutes.wrappedValue))
                .font(.system(.title3, design: .monospaced).bold())
                .frame(width: 72)
            Spacer()
        }
    }

    private func hourBinding(_ minutes: Binding<Int>) -> Binding<Int> {
        Binding(
            get: { minutes.wrappedValue / 60 },
            set: { hour in
                minutes.wrappedValue = hour * 60 + minutes.wrappedValue % 60
            }
        )
    }

    private func minuteBinding(_ minutes: Binding<Int>) -> Binding<Int> {
        Binding(
            get: { (minutes.wrappedValue % 60 / 5) * 5 },
            set: { minute in
                minutes.wrappedValue = (minutes.wrappedValue / 60) * 60 + minute
            }
        )
    }

    private func duration(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
