import SwiftUI

enum AircraftFuelType: String, CaseIterable, Identifiable {
    case avgas = "AVGAS 100LL"
    case ul91 = "UL91"
    case ul94 = "UL94"
    case mogas = "MOGAS"
    var id: String { rawValue }
}

struct AircraftType: RawRepresentable, Hashable, Identifiable {
    let rawValue: String

    init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    private init(_ rawValue: String) { self.rawValue = rawValue }

    static let a211 = AircraftType("A211")
    static let pa28160 = AircraftType("PA28-160")
    static var allCases: [AircraftType] { AircraftRegistry.allAircraft }

    var id: String { rawValue }
    var displayName: String { AircraftRegistry.name(for: self) }

    private var keyPrefix: String {
        if self == .a211 { return "aircraft.a211" }
        if self == .pa28160 { return "aircraft.pa28160" }
        return "aircraft.custom.\(rawValue)"
    }

    var hourlyRateKey: String {
        keyPrefix + ".hourlyRateEUR"
    }

    var fuelConsumptionKey: String {
        keyPrefix + ".fuelConsumptionPerHour"
    }
    var fixedFuelConsumptionEnabledKey: String {
        keyPrefix + ".fixedFuelConsumptionEnabled"
    }

    var usableFuelKey: String {
        keyPrefix + ".usableFuel"
    }
    var mtowKey: String { keyPrefix + ".mtowKilograms" }
    var increasedNoiseProtectionKey: String {
        keyPrefix + ".increasedNoiseProtection"
    }
    var assignedBaseKey: String { keyPrefix + ".assignedBase" }
    var preferredFuelKey: String { keyPrefix + ".preferredFuel" }
    func approvedFuelKey(_ fuel: AircraftFuelType) -> String {
        keyPrefix + ".approvedFuel." + fuel.rawValue
    }

    var climbSpeedKey: String { keyPrefix + ".climbSpeedKIAS" }
    func climbTimeKey(_ altitude: Int) -> String {
        keyPrefix + ".climbTime\(altitude)Minutes"
    }
    func climbDistanceKey(_ altitude: Int) -> String {
        keyPrefix + ".climbDistance\(altitude)NM"
    }
    var cruisePowerKey: String { keyPrefix + ".cruisePowerPercent" }
    func cruiseTASKey(power: Int, altitude: Int) -> String {
        keyPrefix + ".cruise.\(power).tas\(altitude)"
    }
    func cruiseFuelKey(power: Int, altitude: Int) -> String {
        keyPrefix + ".cruise.\(power).fuel\(altitude)"
    }

    var defaultHourlyRateEUR: Double {
        self == .a211 ? 145 : 180
    }

    var defaultCruiseGroundSpeedKnots: Double {
        self == .a211 ? 105 : 110
    }

    var defaultFuelConsumptionPerHour: Double {
        self == .a211 ? 25 : 35
    }

    var defaultUsableFuel: Double {
        self == .a211 ? 100 : 180
    }

    var defaultMTOWKilograms: Double { self == .a211 ? 750 : 0 }
    var defaultIncreasedNoiseProtection: Bool { self == .a211 }
    var defaultPreferredFuel: AircraftFuelType { self == .a211 ? .mogas : .avgas }
    func defaultFuelApproval(_ fuel: AircraftFuelType) -> Bool {
        self == .a211
            ? (fuel == .avgas || fuel == .mogas)
            : fuel == .avgas
    }

    var defaultClimbPerformance: ClimbPerformance {
        if self == .a211 {
            // Aus dem A211-Leistungsdiagramm (Windstille) abgelesen.
            return ClimbPerformance(
                speedKIAS: 65,
                timeAt1000FeetMinutes: 1.5,
                distanceAt1000FeetNM: 1.6,
                timeAt3000FeetMinutes: 4.8,
                distanceAt3000FeetNM: 5.5,
                timeAt5000FeetMinutes: 8.8,
                distanceAt5000FeetNM: 9.7,
                timeAt7000FeetMinutes: 13.0,
                distanceAt7000FeetNM: 15.4,
                timeAt10000FeetMinutes: 23.2,
                distanceAt10000FeetNM: 27.2
            )
        } else {
            // Bewusst leer, bis typenspezifische Handbuchwerte eingetragen sind.
            return ClimbPerformance(
                speedKIAS: 75,
                timeAt1000FeetMinutes: 0,
                distanceAt1000FeetNM: 0,
                timeAt3000FeetMinutes: 0,
                distanceAt3000FeetNM: 0,
                timeAt5000FeetMinutes: 0,
                distanceAt5000FeetNM: 0,
                timeAt7000FeetMinutes: 0,
                distanceAt7000FeetNM: 0,
                timeAt10000FeetMinutes: 0,
                distanceAt10000FeetNM: 0
            )
        }
    }

    func defaultCruisePerformance(powerPercent: Int) -> CruisePerformance {
        if self == .a211 && powerPercent == 65 {
            return CruisePerformance(
                powerPercent: 65,
                tasAt1000Feet: 107,
                tasAt3000Feet: 109,
                tasAt5000Feet: 111,
                tasAt7000Feet: 113,
                tasAt10000Feet: 116,
                fuelAt1000FeetPerHour: 25,
                fuelAt3000FeetPerHour: 25,
                fuelAt5000FeetPerHour: 25,
                fuelAt7000FeetPerHour: 25,
                fuelAt10000FeetPerHour: 25
            )
        }
        return CruisePerformance(
            powerPercent: powerPercent,
            tasAt1000Feet: 0,
            tasAt3000Feet: 0,
            tasAt5000Feet: 0,
            tasAt7000Feet: 0,
            tasAt10000Feet: 0,
            fuelAt1000FeetPerHour: defaultFuelConsumptionPerHour,
            fuelAt3000FeetPerHour: defaultFuelConsumptionPerHour,
            fuelAt5000FeetPerHour: defaultFuelConsumptionPerHour,
            fuelAt7000FeetPerHour: defaultFuelConsumptionPerHour,
            fuelAt10000FeetPerHour: defaultFuelConsumptionPerHour
        )
    }
}

enum AircraftRegistry {
    private static let namesKey = "aircraftRegistry.customNames"

    private static var customNames: [String: String] {
        get {
            UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String] ?? [:]
        }
        set { UserDefaults.standard.set(newValue, forKey: namesKey) }
    }

    static var allAircraft: [AircraftType] {
        [.a211, .pa28160] + customNames.keys.sorted {
            (customNames[$0] ?? $0).localizedCaseInsensitiveCompare(customNames[$1] ?? $1) == .orderedAscending
        }.compactMap(AircraftType.init(rawValue:))
    }

    static func name(for aircraft: AircraftType) -> String {
        if aircraft == .a211 { return "DEUKS" }
        if aircraft == .pa28160 { return "DETIK" }
        return customNames[aircraft.rawValue] ?? aircraft.rawValue
    }

    static func add(named name: String) -> AircraftType? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        guard let aircraft = AircraftType(
            rawValue: "custom-\(UUID().uuidString)"
        ) else { return nil }
        var names = customNames
        names[aircraft.rawValue] = clean
        customNames = names
        return aircraft
    }

    static func rename(_ aircraft: AircraftType, to name: String) {
        guard aircraft != .a211, aircraft != .pa28160 else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var names = customNames
        names[aircraft.rawValue] = clean
        customNames = names
    }

    static func remove(_ aircraft: AircraftType) {
        guard aircraft != .a211, aircraft != .pa28160 else { return }
        var names = customNames
        names.removeValue(forKey: aircraft.rawValue)
        customNames = names
    }

    static func isCustom(_ aircraft: AircraftType) -> Bool {
        aircraft != .a211 && aircraft != .pa28160
    }
}

enum AircraftSettingsKey {
    static let selectedAircraft =
        "flybookSelectedAircraft"
}

enum AircraftProfileStore {
    /// Imports the DEZHS POH climb chart once for the existing aircraft profile.
    /// Values are cumulative from 0 ft pressure altitude and are read from the
    /// wind-calm, 750 kg chart. Per operator choice, Vy remains 65 KIAS at all
    /// configured altitude points.
    static func installDEZHSClimbChartIfNeeded() {
        let defaults = UserDefaults.standard
        guard let aircraft = AircraftRegistry.allAircraft.first(where: {
            AircraftRegistry.name(for: $0)
                .caseInsensitiveCompare("DEZHS") == .orderedSame
        }) else { return }

        let migrationKey = "aircraft.dezhsClimbChart65KIAS.v1."
            + aircraft.rawValue
        guard !defaults.bool(forKey: migrationKey) else { return }

        defaults.set(65.0, forKey: aircraft.climbSpeedKey)
        let chart: [(Int, Double, Double)] = [
            (1_000, 1.5, 1.6),
            (3_000, 4.8, 5.5),
            (5_000, 8.8, 9.7),
            (7_000, 13.0, 15.4),
            (10_000, 23.2, 27.2)
        ]
        for (altitude, minutes, distanceNM) in chart {
            defaults.set(minutes, forKey: aircraft.climbTimeKey(altitude))
            defaults.set(distanceNM, forKey: aircraft.climbDistanceKey(altitude))
        }
        defaults.set(true, forKey: migrationKey)
    }

    /// Imports the 65-percent cruise TAS curve from the DEZHS POH once.
    /// The source chart contains speed only, so stored fuel-flow values are
    /// deliberately left untouched.
    static func installDEZHS65PercentCruiseChartIfNeeded() {
        let defaults = UserDefaults.standard
        guard let aircraft = AircraftRegistry.allAircraft.first(where: {
            AircraftRegistry.name(for: $0)
                .caseInsensitiveCompare("DEZHS") == .orderedSame
        }) else { return }

        let migrationKey = "aircraft.dezhsCruise65Percent.v1."
            + aircraft.rawValue
        guard !defaults.bool(forKey: migrationKey) else { return }

        defaults.set(65, forKey: aircraft.cruisePowerKey)
        let chart: [(Int, Double)] = [
            (1_000, 107),
            (3_000, 109),
            (5_000, 111),
            (7_000, 113),
            (10_000, 116)
        ]
        for (altitude, ktas) in chart {
            defaults.set(
                ktas,
                forKey: aircraft.cruiseTASKey(
                    power: 65,
                    altitude: altitude
                )
            )
        }
        defaults.set(true, forKey: migrationKey)
    }

    /// Uses the POH 75-percent fuel-flow column for the DEZHS 65-percent
    /// cruise profile as a conservative planning assumption. At 7,000 ft the
    /// value is interpolated between 6,000 and 8,000 ft. Since the POH no
    /// longer publishes 75 percent at 10,000 ft, the last available 8,000-ft
    /// fuel flow is carried forward for planning only.
    static func installDEZHSConservativeCruiseFuelIfNeeded() {
        let defaults = UserDefaults.standard
        guard let aircraft = AircraftRegistry.allAircraft.first(where: {
            AircraftRegistry.name(for: $0)
                .caseInsensitiveCompare("DEZHS") == .orderedSame
        }) else { return }

        let migrationKey = "aircraft.dezhsCruise65FuelFrom75.v1."
            + aircraft.rawValue
        guard !defaults.bool(forKey: migrationKey) else { return }

        let chart: [(Int, Double)] = [
            (1_000, 21.5),
            (3_000, 21.5),
            (5_000, 21.5),
            (7_000, 23.75),
            (10_000, 23.5)
        ]
        for (altitude, litersPerHour) in chart {
            defaults.set(
                litersPerHour,
                forKey: aircraft.cruiseFuelKey(
                    power: 65,
                    altitude: altitude
                )
            )
        }
        defaults.set(true, forKey: migrationKey)
    }

    /// Uses the DEUKS POH 75-percent fuel-flow column in its 65-percent
    /// cruise profile as a conservative planning value. Intermediate Flybook
    /// altitude points are linearly interpolated. At 10,000 ft, where 75
    /// percent is no longer published, the final 8,000-ft value is retained.
    static func installDEUKSConservativeCruiseFuelIfNeeded() {
        let defaults = UserDefaults.standard
        let aircraft = AircraftType.a211
        let migrationKey = "aircraft.deuksCruise65FuelFrom75.v1"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let chart: [(Int, Double)] = [
            (1_000, 21.15),
            (3_000, 21.4),
            (5_000, 21.9),
            (7_000, 22.65),
            (10_000, 23.0)
        ]
        for (altitude, litersPerHour) in chart {
            defaults.set(
                litersPerHour,
                forKey: aircraft.cruiseFuelKey(
                    power: 65,
                    altitude: altitude
                )
            )
        }
        defaults.set(true, forKey: migrationKey)
    }

    /// Imports the DETIK 65-percent cruise-speed curve from the POH. The
    /// scanned chart publishes KTAS only; existing fuel-flow data remains
    /// unchanged.
    static func installDETIK65PercentCruiseChartIfNeeded() {
        let defaults = UserDefaults.standard
        let aircraft = AircraftType.pa28160
        let migrationKey = "aircraft.detikCruise65Percent.v1"
        guard !defaults.bool(forKey: migrationKey) else { return }

        defaults.set(65, forKey: aircraft.cruisePowerKey)
        let chart: [(Int, Double)] = [
            (1_000, 104),
            (3_000, 106),
            (5_000, 107.5),
            (7_000, 109),
            (10_000, 111)
        ]
        for (altitude, ktas) in chart {
            defaults.set(
                ktas,
                forKey: aircraft.cruiseTASKey(
                    power: 65,
                    altitude: altitude
                )
            )
        }
        defaults.set(true, forKey: migrationKey)
    }

    /// Imports the DETIK ISA climb table. Cumulative times are obtained by
    /// integrating the linearly changing ISA climb rate in each 1,000-ft
    /// interval. Distance follows the Flybook convention of using Vy (79 kt)
    /// as climb ground speed.
    static func installDETIKISAClimbPerformanceIfNeeded() {
        let defaults = UserDefaults.standard
        let aircraft = AircraftType.pa28160
        let migrationKey = "aircraft.detikISAClimbPerformance.v1"
        guard !defaults.bool(forKey: migrationKey) else { return }

        defaults.set(79.0, forKey: aircraft.climbSpeedKey)
        let chart: [(Int, Double, Double)] = [
            (1_000, 1.6, 2.1),
            (3_000, 5.3, 7.0),
            (5_000, 9.8, 12.9),
            (7_000, 15.6, 20.6),
            (10_000, 29.6, 39.0)
        ]
        for (altitude, minutes, distanceNM) in chart {
            defaults.set(minutes, forKey: aircraft.climbTimeKey(altitude))
            defaults.set(distanceNM, forKey: aircraft.climbDistanceKey(altitude))
        }
        defaults.set(true, forKey: migrationKey)
    }

    private static func storedValue(
        key: String,
        fallback: Double
    ) -> Double {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else {
            return fallback
        }
        return defaults.double(forKey: key)
    }

    static func hourlyRate(
        for aircraft: AircraftType
    ) -> Double {
        storedValue(
            key: aircraft.hourlyRateKey,
            fallback: aircraft.defaultHourlyRateEUR
        )
    }

    static func fuelConsumption(
        for aircraft: AircraftType
    ) -> Double {
        storedValue(
            key: aircraft.fuelConsumptionKey,
            fallback:
                aircraft.defaultFuelConsumptionPerHour
        )
    }

    static func fixedFuelConsumptionIsEnabled(
        for aircraft: AircraftType
    ) -> Bool {
        UserDefaults.standard.bool(
            forKey: aircraft.fixedFuelConsumptionEnabledKey
        )
    }

    static func fuelConsumption(
        for aircraft: AircraftType,
        atPressureAltitudeFeet altitude: Double
    ) -> Double {
        let fixed = fuelConsumption(for: aircraft)
        guard !fixedFuelConsumptionIsEnabled(for: aircraft) else {
            return fixed
        }
        return cruisePerformance(for: aircraft)
            .fuelConsumptionPerHour(atPressureAltitudeFeet: altitude)
            ?? fixed
    }

    static func usableFuel(
        for aircraft: AircraftType
    ) -> Double {
        storedValue(
            key: aircraft.usableFuelKey,
            fallback: aircraft.defaultUsableFuel
        )
    }

    static func mtowKilograms(for aircraft: AircraftType) -> Double {
        storedValue(key: aircraft.mtowKey, fallback: aircraft.defaultMTOWKilograms)
    }

    static func assignedBase(for aircraft: AircraftType) -> FlybookBase {
        let raw = UserDefaults.standard.string(forKey: aircraft.assignedBaseKey)
        return raw.flatMap(FlybookBase.init(rawValue:)) ?? .lsvMainz
    }

    static func aircraft(for base: FlybookBase) -> [AircraftType] {
        AircraftType.allCases.filter { assignedBase(for: $0) == base }
    }

    static func hasIncreasedNoiseProtection(
        for aircraft: AircraftType
    ) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(
            forKey: aircraft.increasedNoiseProtectionKey
        ) != nil else {
            return aircraft.defaultIncreasedNoiseProtection
        }
        return defaults.bool(forKey: aircraft.increasedNoiseProtectionKey)
    }

    static func preferredFuel(for aircraft: AircraftType) -> AircraftFuelType {
        let raw = UserDefaults.standard.string(forKey: aircraft.preferredFuelKey)
        let stored = raw.flatMap(AircraftFuelType.init(rawValue:))
        if let stored, isApproved(stored, for: aircraft) { return stored }
        // Fehlt noch ein gespeicherter Profilwert, muss der im Flugzeugprofil
        // definierte Referenzkraftstoff gelten. Die Reihenfolge der
        // zugelassenen Sorten (AVGAS steht dort zuerst) darf die
        // Tankzuzahlung nicht unbemerkt verändern.
        if isApproved(aircraft.defaultPreferredFuel, for: aircraft) {
            return aircraft.defaultPreferredFuel
        }
        return approvedFuels(for: aircraft).first
            ?? aircraft.defaultPreferredFuel
    }

    static func isApproved(_ fuel: AircraftFuelType, for aircraft: AircraftType) -> Bool {
        let key = aircraft.approvedFuelKey(fuel)
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return aircraft.defaultFuelApproval(fuel)
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func approvedFuels(for aircraft: AircraftType) -> [AircraftFuelType] {
        AircraftFuelType.allCases.filter { isApproved($0, for: aircraft) }
    }

    static func climbPerformance(for aircraft: AircraftType) -> ClimbPerformance {
        let defaults = aircraft.defaultClimbPerformance
        return ClimbPerformance(
            speedKIAS: storedValue(key: aircraft.climbSpeedKey, fallback: defaults.speedKIAS),
            timeAt1000FeetMinutes: storedValue(key: aircraft.climbTimeKey(1000), fallback: defaults.timeAt1000FeetMinutes),
            distanceAt1000FeetNM: storedValue(key: aircraft.climbDistanceKey(1000), fallback: defaults.distanceAt1000FeetNM),
            timeAt3000FeetMinutes: storedValue(key: aircraft.climbTimeKey(3000), fallback: defaults.timeAt3000FeetMinutes),
            distanceAt3000FeetNM: storedValue(key: aircraft.climbDistanceKey(3000), fallback: defaults.distanceAt3000FeetNM),
            timeAt5000FeetMinutes: storedValue(key: aircraft.climbTimeKey(5000), fallback: defaults.timeAt5000FeetMinutes),
            distanceAt5000FeetNM: storedValue(key: aircraft.climbDistanceKey(5000), fallback: defaults.distanceAt5000FeetNM),
            timeAt7000FeetMinutes: storedValue(key: aircraft.climbTimeKey(7000), fallback: defaults.timeAt7000FeetMinutes),
            distanceAt7000FeetNM: storedValue(key: aircraft.climbDistanceKey(7000), fallback: defaults.distanceAt7000FeetNM),
            timeAt10000FeetMinutes: storedValue(key: aircraft.climbTimeKey(10000), fallback: defaults.timeAt10000FeetMinutes),
            distanceAt10000FeetNM: storedValue(key: aircraft.climbDistanceKey(10000), fallback: defaults.distanceAt10000FeetNM)
        )
    }

    static func cruisePowerPercent(for aircraft: AircraftType) -> Int {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: aircraft.cruisePowerKey) != nil else {
            return 65
        }
        return defaults.integer(forKey: aircraft.cruisePowerKey)
    }

    static func cruisePerformance(for aircraft: AircraftType) -> CruisePerformance {
        let power = cruisePowerPercent(for: aircraft)
        return cruisePerformance(for: aircraft, powerPercent: power)
    }

    static func cruisePerformance(
        for aircraft: AircraftType,
        powerPercent power: Int
    ) -> CruisePerformance {
        let fallback = aircraft.defaultCruisePerformance(powerPercent: power)
        return CruisePerformance(
            powerPercent: power,
            tasAt1000Feet: storedValue(key: aircraft.cruiseTASKey(power: power, altitude: 1000), fallback: fallback.tasAt1000Feet),
            tasAt3000Feet: storedValue(key: aircraft.cruiseTASKey(power: power, altitude: 3000), fallback: fallback.tasAt3000Feet),
            tasAt5000Feet: storedValue(key: aircraft.cruiseTASKey(power: power, altitude: 5000), fallback: fallback.tasAt5000Feet),
            tasAt7000Feet: storedValue(key: aircraft.cruiseTASKey(power: power, altitude: 7000), fallback: fallback.tasAt7000Feet),
            tasAt10000Feet: storedValue(key: aircraft.cruiseTASKey(power: power, altitude: 10000), fallback: fallback.tasAt10000Feet),
            fuelAt1000FeetPerHour: storedValue(key: aircraft.cruiseFuelKey(power: power, altitude: 1000), fallback: fallback.fuelAt1000FeetPerHour),
            fuelAt3000FeetPerHour: storedValue(key: aircraft.cruiseFuelKey(power: power, altitude: 3000), fallback: fallback.fuelAt3000FeetPerHour),
            fuelAt5000FeetPerHour: storedValue(key: aircraft.cruiseFuelKey(power: power, altitude: 5000), fallback: fallback.fuelAt5000FeetPerHour),
            fuelAt7000FeetPerHour: storedValue(key: aircraft.cruiseFuelKey(power: power, altitude: 7000), fallback: fallback.fuelAt7000FeetPerHour),
            fuelAt10000FeetPerHour: storedValue(key: aircraft.cruiseFuelKey(power: power, altitude: 10000), fallback: fallback.fuelAt10000FeetPerHour)
        )
    }
}

struct AircraftSetupView: View {
    @State private var selectedAircraft:
        AircraftType = .a211
    @State private var aircraftName = AircraftType.a211.displayName
    @State private var createsAircraft = false
    @State private var registryRevision = UUID()
    @FocusState private var aircraftNameIsFocused: Bool

    @AppStorage(AircraftSettingsKey.selectedAircraft)
    private var defaultAircraftRaw =
        AircraftType.a211.rawValue

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Flugzeugkonfiguration")
                        .font(.title2.bold())

                    Text(
                        "Leistungs-, Kraftstoff- und Charterkostendaten je Flugzeug"
                    )
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Schließen") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 12) {
                Image(systemName: "airplane.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(FlybookColor.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("FLUGZEUG")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(FlybookColor.muted)
                    Text(selectedAircraft.displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)
                }

                Spacer()

                Picker(
                    "Flugzeugtyp",
                    selection: $selectedAircraft
                ) {
                    ForEach(AircraftType.allCases) {
                        aircraft in
                        Text(aircraft.displayName)
                            .tag(aircraft)
                    }
                }
                .labelsHidden()
                .frame(width: 190)

                Menu {
                    Button("Neues Flugzeug", systemImage: "plus") {
                        createsAircraft = true
                        aircraftName = ""
                        DispatchQueue.main.async {
                            aircraftNameIsFocused = true
                        }
                    }
                    Button("Flugzeug entfernen", systemImage: "trash", role: .destructive) {
                        if defaultAircraftRaw == selectedAircraft.rawValue {
                            defaultAircraftRaw = AircraftType.a211.rawValue
                        }
                        AircraftRegistry.remove(selectedAircraft)
                        selectedAircraft = .a211
                        aircraftName = selectedAircraft.displayName
                        createsAircraft = false
                        registryRevision = UUID()
                    }
                    .disabled(!AircraftRegistry.isCustom(selectedAircraft))
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(FlybookColor.line, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .id(registryRevision)

            if createsAircraft || AircraftRegistry.isCustom(selectedAircraft) {
                HStack(spacing: 12) {
                    Text(createsAircraft ? "Neues Flugzeug" : "Bezeichnung")
                        .font(.headline)
                        .foregroundStyle(FlybookColor.navy)
                        .frame(width: 160, alignment: .leading)
                    TextField("Flugzeugbezeichnung", text: $aircraftName)
                        .textFieldStyle(.roundedBorder)
                        .focused($aircraftNameIsFocused)
                        .onSubmit { saveAircraft() }
                    Button("Speichern") {
                        saveAircraft()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(aircraftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if createsAircraft {
                        Button("Abbrechen") {
                            createsAircraft = false
                            aircraftName = selectedAircraft.displayName
                        }
                    }
                }
            }

            AircraftProfileEditor(
                aircraft: selectedAircraft
            )
            .id(selectedAircraft)

            HStack {
                Text(
                    defaultAircraftRaw == selectedAircraft.rawValue
                        ? "Aktuelles Standardflugzeug"
                        : ""
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Profil speichern") {
                    UserDefaults.standard.synchronize()
                }
                .buttonStyle(.bordered)

                Button("Als Standard") {
                    defaultAircraftRaw =
                        selectedAircraft.rawValue
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding(28)
        .frame(width: 900, height: 920)
        .background(FlybookColor.background)
        .background(KeyWindowActivator())
        .onChange(of: selectedAircraft) { aircraft in
            guard !createsAircraft else { return }
            aircraftName = aircraft.displayName
        }
    }

    private func saveAircraft() {
        if createsAircraft {
            guard let aircraft = AircraftRegistry.add(named: aircraftName) else { return }
            selectedAircraft = aircraft
            defaultAircraftRaw = aircraft.rawValue
            createsAircraft = false
        } else {
            AircraftRegistry.rename(selectedAircraft, to: aircraftName)
        }
        aircraftName = selectedAircraft.displayName
        registryRevision = UUID()
    }
}

private struct KeyWindowActivator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            view.window?.makeKeyAndOrderFront(nil)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct AircraftProfileEditor: View {
    let aircraft: AircraftType

    @AppStorage private var assignedBaseRaw: String
    @AppStorage private var hourlyRateEUR: Double
    @AppStorage private var fuelConsumptionPerHour: Double
    @AppStorage private var fixedFuelConsumptionEnabled: Bool
    @AppStorage private var usableFuel: Double
    @AppStorage private var mtowKilograms: Double
    @AppStorage private var increasedNoiseProtection: Bool
    @AppStorage private var preferredFuelRaw: String
    @AppStorage private var avgasApproved: Bool
    @AppStorage private var ul91Approved: Bool
    @AppStorage private var ul94Approved: Bool
    @AppStorage private var mogasApproved: Bool
    @AppStorage private var climbSpeedKIAS: Double
    @AppStorage private var cruisePowerPercent: Int
    @AppStorage private var climbTime1000Minutes: Double
    @AppStorage private var climbDistance1000NM: Double
    @AppStorage private var climbTime3000Minutes: Double
    @AppStorage private var climbDistance3000NM: Double
    @AppStorage private var climbTime5000Minutes: Double
    @AppStorage private var climbDistance5000NM: Double
    @AppStorage private var climbTime7000Minutes: Double
    @AppStorage private var climbDistance7000NM: Double
    @AppStorage private var climbTime10000Minutes: Double
    @AppStorage private var climbDistance10000NM: Double
    @AppStorage(CalculationSettingsKey.fuelDisplayUnit)
    private var fuelDisplayUnitRaw = FuelDisplayUnit.liters.rawValue

    private var fuelDisplayUnit: FuelDisplayUnit {
        FuelDisplayUnit(rawValue: fuelDisplayUnitRaw) ?? .liters
    }

    private var displayedUsableFuel: Binding<Double> {
        convertedFuelBinding($usableFuel)
    }

    private var displayedFuelConsumption: Binding<Double> {
        convertedFuelBinding($fuelConsumptionPerHour)
    }

    private var approvedFuelTypes: [AircraftFuelType] {
        AircraftFuelType.allCases.filter { fuel in
            switch fuel {
            case .avgas: return avgasApproved
            case .ul91: return ul91Approved
            case .ul94: return ul94Approved
            case .mogas: return mogasApproved
            }
        }
    }

    init(aircraft: AircraftType) {
        self.aircraft = aircraft

        _assignedBaseRaw = AppStorage(
            wrappedValue: FlybookBase.lsvMainz.rawValue,
            aircraft.assignedBaseKey
        )

        _hourlyRateEUR = AppStorage(
            wrappedValue:
                aircraft.defaultHourlyRateEUR,
            aircraft.hourlyRateKey
        )

        _fuelConsumptionPerHour = AppStorage(
            wrappedValue:
                aircraft.defaultFuelConsumptionPerHour,
            aircraft.fuelConsumptionKey
        )
        _fixedFuelConsumptionEnabled = AppStorage(
            wrappedValue: false,
            aircraft.fixedFuelConsumptionEnabledKey
        )

        _usableFuel = AppStorage(
            wrappedValue:
                aircraft.defaultUsableFuel,
            aircraft.usableFuelKey
        )
        _mtowKilograms = AppStorage(wrappedValue: aircraft.defaultMTOWKilograms, aircraft.mtowKey)
        _increasedNoiseProtection = AppStorage(wrappedValue: aircraft.defaultIncreasedNoiseProtection, aircraft.increasedNoiseProtectionKey)
        _preferredFuelRaw = AppStorage(wrappedValue: aircraft.defaultPreferredFuel.rawValue, aircraft.preferredFuelKey)
        _avgasApproved = AppStorage(wrappedValue: aircraft.defaultFuelApproval(.avgas), aircraft.approvedFuelKey(.avgas))
        _ul91Approved = AppStorage(wrappedValue: aircraft.defaultFuelApproval(.ul91), aircraft.approvedFuelKey(.ul91))
        _ul94Approved = AppStorage(wrappedValue: aircraft.defaultFuelApproval(.ul94), aircraft.approvedFuelKey(.ul94))
        _mogasApproved = AppStorage(wrappedValue: aircraft.defaultFuelApproval(.mogas), aircraft.approvedFuelKey(.mogas))

        let climb = aircraft.defaultClimbPerformance
        _cruisePowerPercent = AppStorage(
            wrappedValue: 65,
            aircraft.cruisePowerKey
        )
        _climbSpeedKIAS = AppStorage(wrappedValue: climb.speedKIAS, aircraft.climbSpeedKey)
        _climbTime1000Minutes = AppStorage(wrappedValue: climb.timeAt1000FeetMinutes, aircraft.climbTimeKey(1000))
        _climbDistance1000NM = AppStorage(wrappedValue: climb.distanceAt1000FeetNM, aircraft.climbDistanceKey(1000))
        _climbTime3000Minutes = AppStorage(wrappedValue: climb.timeAt3000FeetMinutes, aircraft.climbTimeKey(3000))
        _climbDistance3000NM = AppStorage(wrappedValue: climb.distanceAt3000FeetNM, aircraft.climbDistanceKey(3000))
        _climbTime5000Minutes = AppStorage(wrappedValue: climb.timeAt5000FeetMinutes, aircraft.climbTimeKey(5000))
        _climbDistance5000NM = AppStorage(wrappedValue: climb.distanceAt5000FeetNM, aircraft.climbDistanceKey(5000))
        _climbTime7000Minutes = AppStorage(wrappedValue: climb.timeAt7000FeetMinutes, aircraft.climbTimeKey(7000))
        _climbDistance7000NM = AppStorage(wrappedValue: climb.distanceAt7000FeetNM, aircraft.climbDistanceKey(7000))
        _climbTime10000Minutes = AppStorage(wrappedValue: climb.timeAt10000FeetMinutes, aircraft.climbTimeKey(10000))
        _climbDistance10000NM = AppStorage(wrappedValue: climb.distanceAt10000FeetNM, aircraft.climbDistanceKey(10000))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                    settingsCard("Zuordnung", systemImage: "building.2") {
                        HStack(spacing: 18) {
                            Text("Basis / Verein")
                                .font(.headline)
                                .frame(width: 260, alignment: .leading)
                            Picker("Basis / Verein", selection: $assignedBaseRaw) {
                                ForEach(FlybookBase.allCases) { base in
                                    Text(base.rawValue).tag(base.rawValue)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                            .frame(width: 240, alignment: .leading)
                            Spacer()
                        }
                    }

                    settingsCard("Charterkosten", systemImage: "eurosign.circle") {
                        VStack(alignment: .leading, spacing: 12) {
                            profileRow(
                                title: "Charterkosten pro Stunde",
                                value: $hourlyRateEUR,
                                range: 50...500,
                                step: 1,
                                suffix: "EUR"
                            )
                        }
                    }

                    settingsCard("Gewicht & Lärm", systemImage: "scalemass") {
                        VStack(alignment: .leading, spacing: 12) {
                            profileRow(
                                title: "MTOW",
                                value: $mtowKilograms,
                                range: 0...5_000,
                                step: 1,
                                suffix: "kg"
                            )

                            HStack(spacing: 18) {
                                Text("Erhöhter Schallschutz")
                                    .font(.headline)
                                    .frame(width: 260, alignment: .leading)
                                Toggle("Erfüllt", isOn: $increasedNoiseProtection)
                                Spacer()
                            }
                        }
                    }

                    settingsCard("Kraftstoff", systemImage: "fuelpump") {
                        VStack(alignment: .leading, spacing: 12) {
                            fuelCapacityRow

                            HStack(spacing: 18) {
                                Text("Bevorzugte Kraftstoffsorte")
                                    .font(.headline)
                                    .frame(width: 260, alignment: .leading)
                                Picker("Bevorzugte Kraftstoffsorte", selection: $preferredFuelRaw) {
                                    ForEach(approvedFuelTypes) { fuel in
                                        Text(fuel.rawValue).tag(fuel.rawValue)
                                    }
                                }
                                .labelsHidden()
                                .fixedSize()
                                .frame(width: 190, alignment: .leading)
                                Spacer()
                            }

                            HStack(spacing: 18) {
                                Text("Zugelassen")
                                    .font(.headline)
                                    .frame(width: 260, alignment: .leading)
                                Toggle("AVGAS", isOn: $avgasApproved)
                                Toggle("UL91", isOn: $ul91Approved)
                                Toggle("UL94", isOn: $ul94Approved)
                                Toggle("MOGAS", isOn: $mogasApproved)
                                Spacer()
                            }
                            .onChange(of: avgasApproved) { _ in normalizeFuelSelection(changed: .avgas) }
                            .onChange(of: ul91Approved) { _ in normalizeFuelSelection(changed: .ul91) }
                            .onChange(of: ul94Approved) { _ in normalizeFuelSelection(changed: .ul94) }
                            .onChange(of: mogasApproved) { _ in normalizeFuelSelection(changed: .mogas) }
                        }
                    }

                    settingsCard("Climb Performance", systemImage: "arrow.up.right") {
                        VStack(alignment: .leading, spacing: 12) {
                            profileRow(
                                title: "Vy",
                                value: $climbSpeedKIAS,
                                range: 40...140,
                                step: 1,
                                suffix: "KIAS"
                            )

                            Text("Vy wird im Rechenmodell als Groundspeed im Steigflug verwendet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Kennlinie ab 0 ft Druckhöhe")
                                .font(.headline)

                            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                                GridRow {
                                    Text("Druckhöhe").font(.caption.bold())
                                    Text("Zeit ab 0 ft").font(.caption.bold())
                                    Text("Strecke ab 0 ft").font(.caption.bold())
                                }
                                climbTableRow("1.000 ft", time: $climbTime1000Minutes, distance: $climbDistance1000NM)
                                climbTableRow("3.000 ft", time: $climbTime3000Minutes, distance: $climbDistance3000NM)
                                climbTableRow("5.000 ft", time: $climbTime5000Minutes, distance: $climbDistance5000NM)
                                climbTableRow("7.000 ft", time: $climbTime7000Minutes, distance: $climbDistance7000NM)
                                climbTableRow("10.000 ft", time: $climbTime10000Minutes, distance: $climbDistance10000NM)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    settingsCard("Cruise Performance", systemImage: "airplane") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 18) {
                                Text("Freier Spritverbrauch")
                                    .font(.headline)
                                    .frame(width: 260, alignment: .leading)
                                TextField(
                                    "0,0",
                                    value: $fuelConsumptionPerHour,
                                    format: .number.precision(.fractionLength(1))
                                )
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .frame(width: 90)
                                Text("L/h")
                                    .foregroundStyle(.secondary)
                                Toggle(
                                    "Faustformel aktiv",
                                    isOn: $fixedFuelConsumptionEnabled
                                )
                                .toggleStyle(.checkbox)
                                Spacer()
                            }

                            Text(
                                fixedFuelConsumptionEnabled
                                    ? "Flybook rechnet in allen Höhen mit diesem festen Wert."
                                    : "Flybook interpoliert den Verbrauch aus den Handbuchwerten der gewählten Flughöhe."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            HStack {
                                Text("Leistung")
                                    .font(.headline)
                                    .frame(width: 260, alignment: .leading)
                                Picker("Reiseflugleistung", selection: $cruisePowerPercent) {
                                    ForEach([55, 65, 75, 85], id: \.self) { power in
                                        Text("\(power) %").tag(power)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 130)
                                Spacer()
                            }

                            CruisePerformanceEditor(
                                aircraft: aircraft,
                                powerPercent: cruisePowerPercent
                            )
                            .id(cruisePowerPercent)
                        }
                    }

                    HStack {
                        Spacer()

                        Button("Profil zurücksetzen") {
                        hourlyRateEUR =
                            aircraft.defaultHourlyRateEUR
                        fuelConsumptionPerHour =
                            aircraft
                                .defaultFuelConsumptionPerHour
                        fixedFuelConsumptionEnabled = false
                        usableFuel =
                            aircraft.defaultUsableFuel
                        mtowKilograms = aircraft.defaultMTOWKilograms
                        increasedNoiseProtection = aircraft.defaultIncreasedNoiseProtection
                        preferredFuelRaw = aircraft.defaultPreferredFuel.rawValue
                        avgasApproved = aircraft.defaultFuelApproval(.avgas)
                        ul91Approved = aircraft.defaultFuelApproval(.ul91)
                        ul94Approved = aircraft.defaultFuelApproval(.ul94)
                        mogasApproved = aircraft.defaultFuelApproval(.mogas)
                        let climb = aircraft.defaultClimbPerformance
                        climbSpeedKIAS = climb.speedKIAS
                        climbTime1000Minutes = climb.timeAt1000FeetMinutes
                        climbDistance1000NM = climb.distanceAt1000FeetNM
                        climbTime3000Minutes = climb.timeAt3000FeetMinutes
                        climbDistance3000NM = climb.distanceAt3000FeetNM
                        climbTime5000Minutes = climb.timeAt5000FeetMinutes
                        climbDistance5000NM = climb.distanceAt5000FeetNM
                        climbTime7000Minutes = climb.timeAt7000FeetMinutes
                        climbDistance7000NM = climb.distanceAt7000FeetNM
                        climbTime10000Minutes = climb.timeAt10000FeetMinutes
                        climbDistance10000NM = climb.distanceAt10000FeetNM
                        }
                    }
            }
        }
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 2)
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

            Divider()
                .overlay(FlybookColor.line)

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
                .allowsHitTesting(false)
        )
    }

    private func normalizeFuelSelection(changed fuel: AircraftFuelType) {
        if approvedFuelTypes.isEmpty {
            switch fuel {
            case .avgas: avgasApproved = true
            case .ul91: ul91Approved = true
            case .ul94: ul94Approved = true
            case .mogas: mogasApproved = true
            }
        }
        if !approvedFuelTypes.contains(where: { $0.rawValue == preferredFuelRaw }),
           let first = approvedFuelTypes.first {
            preferredFuelRaw = first.rawValue
        }
    }

    private var fuelCapacityRow: some View {
        HStack(spacing: 18) {
            Text("Ausfliegbarer Kraftstoff")
                .font(.headline)
                .frame(width: 260, alignment: .leading)

            HStack(spacing: 4) {
                TextField(
                    "0,0",
                    value: displayedUsableFuel,
                    format: .number.precision(.fractionLength(1))
                )
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .frame(width: 88)

                Stepper(
                    "Kraftstoffmenge",
                    value: displayedUsableFuel,
                    in: fuelDisplayUnit == .liters ? 0...250 : 0...66,
                    step: fuelDisplayUnit == .liters ? 1 : 0.5
                )
                .labelsHidden()
                .fixedSize()
            }
            .frame(width: 132, alignment: .leading)

            Picker("Kraftstoffeinheit", selection: $fuelDisplayUnitRaw) {
                ForEach(FuelDisplayUnit.allCases) { unit in
                    Text(unit.label).tag(unit.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 145)
            Spacer()
        }
    }

    private func convertedFuelBinding(_ liters: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { fuelDisplayUnit.fromLiters(liters.wrappedValue) },
            set: { displayed in
                liters.wrappedValue = fuelDisplayUnit == .liters
                    ? displayed
                    : displayed * 3.785_411_784
            }
        )
    }

    private func climbTableRow(
        _ altitude: String,
        time: Binding<Double>,
        distance: Binding<Double>
    ) -> some View {
        GridRow {
            Text(altitude).font(.system(size: 13, weight: .semibold))
            compactValueField(value: time, suffix: "min")
            compactValueField(value: distance, suffix: "NM")
        }
    }

    private func compactValueField(
        value: Binding<Double>,
        suffix: String
    ) -> some View {
        HStack(spacing: 5) {
            TextField(
                "0,0",
                value: value,
                format: .number.precision(.fractionLength(1))
            )
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .frame(width: 82)

            Text(suffix)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 135, alignment: .leading)
    }

    private func profileRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        suffix: String
    ) -> some View {
        HStack(spacing: 18) {
            Text(title)
                .font(.headline)
                .frame(
                    width: 260,
                    alignment: .leading
                )

            HStack(spacing: 6) {
                TextField(
                    "0",
                    value: value,
                    format: .number.precision(.fractionLength(0))
                )
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .frame(width: 88)

                Text(suffix)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FlybookColor.navy)
                    .frame(width: 42, alignment: .leading)

                Stepper(title, value: value, in: range, step: step)
                    .labelsHidden()
                    .fixedSize()
            }
            .frame(width: 180, alignment: .leading)
            Spacer()
        }
    }
}

private struct CruisePerformanceEditor: View {
    let aircraft: AircraftType
    let powerPercent: Int

    @AppStorage private var tas1000: Double
    @AppStorage private var tas3000: Double
    @AppStorage private var tas5000: Double
    @AppStorage private var tas7000: Double
    @AppStorage private var tas10000: Double
    @AppStorage private var fuel1000: Double
    @AppStorage private var fuel3000: Double
    @AppStorage private var fuel5000: Double
    @AppStorage private var fuel7000: Double
    @AppStorage private var fuel10000: Double
    @AppStorage(CalculationSettingsKey.fuelDisplayUnit)
    private var fuelDisplayUnitRaw = FuelDisplayUnit.liters.rawValue

    private var fuelDisplayUnit: FuelDisplayUnit {
        FuelDisplayUnit(rawValue: fuelDisplayUnitRaw) ?? .liters
    }

    init(aircraft: AircraftType, powerPercent: Int) {
        self.aircraft = aircraft
        self.powerPercent = powerPercent
        let values = aircraft.defaultCruisePerformance(powerPercent: powerPercent)
        _tas1000 = AppStorage(wrappedValue: values.tasAt1000Feet, aircraft.cruiseTASKey(power: powerPercent, altitude: 1000))
        _tas3000 = AppStorage(wrappedValue: values.tasAt3000Feet, aircraft.cruiseTASKey(power: powerPercent, altitude: 3000))
        _tas5000 = AppStorage(wrappedValue: values.tasAt5000Feet, aircraft.cruiseTASKey(power: powerPercent, altitude: 5000))
        _tas7000 = AppStorage(wrappedValue: values.tasAt7000Feet, aircraft.cruiseTASKey(power: powerPercent, altitude: 7000))
        _tas10000 = AppStorage(wrappedValue: values.tasAt10000Feet, aircraft.cruiseTASKey(power: powerPercent, altitude: 10000))
        _fuel1000 = AppStorage(wrappedValue: values.fuelAt1000FeetPerHour, aircraft.cruiseFuelKey(power: powerPercent, altitude: 1000))
        _fuel3000 = AppStorage(wrappedValue: values.fuelAt3000FeetPerHour, aircraft.cruiseFuelKey(power: powerPercent, altitude: 3000))
        _fuel5000 = AppStorage(wrappedValue: values.fuelAt5000FeetPerHour, aircraft.cruiseFuelKey(power: powerPercent, altitude: 5000))
        _fuel7000 = AppStorage(wrappedValue: values.fuelAt7000FeetPerHour, aircraft.cruiseFuelKey(power: powerPercent, altitude: 7000))
        _fuel10000 = AppStorage(wrappedValue: values.fuelAt10000FeetPerHour, aircraft.cruiseFuelKey(power: powerPercent, altitude: 10000))
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Druckhöhe").font(.caption.bold())
                Text("TAS bei \(powerPercent) %").font(.caption.bold())
                Text("Verbrauch").font(.caption.bold())
            }
            tasRow("1.000 ft", tas: $tas1000, fuel: $fuel1000)
            tasRow("3.000 ft", tas: $tas3000, fuel: $fuel3000)
            tasRow("5.000 ft", tas: $tas5000, fuel: $fuel5000)
            tasRow("7.000 ft", tas: $tas7000, fuel: $fuel7000)
            tasRow("10.000 ft", tas: $tas10000, fuel: $fuel10000)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tasRow(
        _ altitude: String,
        tas: Binding<Double>,
        fuel: Binding<Double>
    ) -> some View {
        GridRow {
            Text(altitude).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 5) {
                TextField(
                    "0",
                    value: tas,
                    format: .number.precision(.fractionLength(0...1))
                )
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(width: 82)
                Text("KTAS").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
                TextField(
                    "0,0",
                    value: displayedFuelBinding(fuel),
                    format: .number.precision(.fractionLength(1))
                )
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(width: 82)
                Text(fuelDisplayUnit == .liters ? "L/h" : "gal/h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func displayedFuelBinding(_ liters: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { fuelDisplayUnit.fromLiters(liters.wrappedValue) },
            set: { displayed in
                liters.wrappedValue = fuelDisplayUnit == .liters
                    ? displayed
                    : displayed * 3.785_411_784
            }
        )
    }
}
