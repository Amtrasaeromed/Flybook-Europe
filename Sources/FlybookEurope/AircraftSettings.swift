import SwiftUI

enum AircraftType: String, CaseIterable, Identifiable {
    case a211 = "A211"
    case pa28160 = "PA28-160"

    var id: String { rawValue }

    private var keyPrefix: String {
        self == .a211 ? "aircraft.a211" : "aircraft.pa28160"
    }

    var hourlyRateKey: String {
        keyPrefix + ".hourlyRateEUR"
    }

    var fuelConsumptionKey: String {
        keyPrefix + ".fuelConsumptionPerHour"
    }

    var usableFuelKey: String {
        keyPrefix + ".usableFuel"
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

    var defaultClimbPerformance: ClimbPerformance {
        switch self {
        case .a211:
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
        case .pa28160:
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
                tasAt10000Feet: 116
            )
        }
        return CruisePerformance(
            powerPercent: powerPercent,
            tasAt1000Feet: 0,
            tasAt3000Feet: 0,
            tasAt5000Feet: 0,
            tasAt7000Feet: 0,
            tasAt10000Feet: 0
        )
    }
}

enum AircraftSettingsKey {
    static let selectedAircraft =
        "flybookSelectedAircraft"
}

enum AircraftProfileStore {
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

    static func usableFuel(
        for aircraft: AircraftType
    ) -> Double {
        storedValue(
            key: aircraft.usableFuelKey,
            fallback: aircraft.defaultUsableFuel
        )
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
        let fallback = aircraft.defaultCruisePerformance(powerPercent: power)
        return CruisePerformance(
            powerPercent: power,
            tasAt1000Feet: storedValue(key: aircraft.cruiseTASKey(power: power, altitude: 1000), fallback: fallback.tasAt1000Feet),
            tasAt3000Feet: storedValue(key: aircraft.cruiseTASKey(power: power, altitude: 3000), fallback: fallback.tasAt3000Feet),
            tasAt5000Feet: storedValue(key: aircraft.cruiseTASKey(power: power, altitude: 5000), fallback: fallback.tasAt5000Feet),
            tasAt7000Feet: storedValue(key: aircraft.cruiseTASKey(power: power, altitude: 7000), fallback: fallback.tasAt7000Feet),
            tasAt10000Feet: storedValue(key: aircraft.cruiseTASKey(power: power, altitude: 10000), fallback: fallback.tasAt10000Feet)
        )
    }
}

struct AircraftSetupView: View {
    @State private var selectedAircraft:
        AircraftType = .a211

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

            HStack {
                Text("Flugzeugtyp")
                    .font(.headline)

                Spacer()

                Picker(
                    "Flugzeugtyp",
                    selection: $selectedAircraft
                ) {
                    ForEach(AircraftType.allCases) {
                        aircraft in
                        Text(aircraft.rawValue)
                            .tag(aircraft)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
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

                Button("Als Standard") {
                    defaultAircraftRaw =
                        selectedAircraft.rawValue
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding(28)
        .frame(width: 760, height: 880)
    }
}

private struct AircraftProfileEditor: View {
    let aircraft: AircraftType

    @AppStorage private var hourlyRateEUR: Double
    @AppStorage private var fuelConsumptionPerHour: Double
    @AppStorage private var usableFuel: Double
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

    init(aircraft: AircraftType) {
        self.aircraft = aircraft

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

        _usableFuel = AppStorage(
            wrappedValue:
                aircraft.defaultUsableFuel,
            aircraft.usableFuelKey
        )

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
        GroupBox(aircraft.rawValue) {
            ScrollView {
                VStack(spacing: 16) {
                    GroupBox("Charter & Kraftstoff") {
                        VStack(spacing: 12) {
                            profileRow(
                                title: "Charterkosten pro Stunde",
                                value: $hourlyRateEUR,
                                range: 50...500,
                                step: 5,
                                suffix: "EUR"
                            )

                            fuelCapacityRow
                        }
                        .padding(8)
                    }

                    GroupBox("Reiseleistung") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Leistung")
                                    .font(.headline)
                                Spacer()
                                Picker("Reiseflugleistung", selection: $cruisePowerPercent) {
                                    ForEach([55, 65, 75, 85], id: \.self) { power in
                                        Text("\(power) %").tag(power)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 130)
                            }

                            CruisePerformanceEditor(
                                aircraft: aircraft,
                                powerPercent: cruisePowerPercent
                            )
                            .id(cruisePowerPercent)

                            Divider()

                            profileRow(
                                title: "Kraftstoffverbrauch",
                                value: displayedFuelConsumption,
                                range: fuelDisplayUnit == .liters ? 0...60 : 0...16,
                                step: fuelDisplayUnit == .liters ? 1 : 0.5,
                                suffix: fuelDisplayUnit == .liters ? "L / h" : "US gal / h"
                            )
                        }
                        .padding(8)
                    }

                    GroupBox("Steigflug") {
                        VStack(alignment: .leading, spacing: 12) {
                            profileRow(
                                title: "Steigfluggeschwindigkeit",
                                value: $climbSpeedKIAS,
                                range: 40...140,
                                step: 1,
                                suffix: "KIAS"
                            )

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
                            .frame(maxWidth: .infinity)
                        }
                        .padding(8)
                    }

                    HStack {
                        Spacer()

                        Button("Profil zurücksetzen") {
                        hourlyRateEUR =
                            aircraft.defaultHourlyRateEUR
                        fuelConsumptionPerHour =
                            aircraft
                                .defaultFuelConsumptionPerHour
                        usableFuel =
                            aircraft.defaultUsableFuel
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
            .padding(10)
        }
    }

    private var fuelCapacityRow: some View {
        HStack {
            Text("Ausfliegbarer Kraftstoff")
                .font(.headline)
                .frame(width: 250, alignment: .leading)

            Stepper(
                value: displayedUsableFuel,
                in: fuelDisplayUnit == .liters ? 0...250 : 0...66,
                step: fuelDisplayUnit == .liters ? 1 : 0.5
            ) {
                Text(String(format: "%.1f", displayedUsableFuel.wrappedValue))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .frame(width: 80, alignment: .trailing)
            }
            .frame(width: 155)

            Picker("Kraftstoffeinheit", selection: $fuelDisplayUnitRaw) {
                ForEach(FuelDisplayUnit.allCases) { unit in
                    Text(unit.label).tag(unit.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 145)
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
        HStack {
            Text(title)
                .font(.headline)
                .frame(
                    width: 250,
                    alignment: .leading
                )

            Stepper(
                value: value,
                in: range,
                step: step
            ) {
                Text(
                    String(
                        format: "%.0f %@",
                        value.wrappedValue,
                        suffix
                    )
                )
                .font(
                    .system(
                        size: 15,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .frame(
                    width: 180,
                    alignment: .trailing
                )
            }
            .frame(width: 250)
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

    init(aircraft: AircraftType, powerPercent: Int) {
        self.aircraft = aircraft
        self.powerPercent = powerPercent
        let values = aircraft.defaultCruisePerformance(powerPercent: powerPercent)
        _tas1000 = AppStorage(wrappedValue: values.tasAt1000Feet, aircraft.cruiseTASKey(power: powerPercent, altitude: 1000))
        _tas3000 = AppStorage(wrappedValue: values.tasAt3000Feet, aircraft.cruiseTASKey(power: powerPercent, altitude: 3000))
        _tas5000 = AppStorage(wrappedValue: values.tasAt5000Feet, aircraft.cruiseTASKey(power: powerPercent, altitude: 5000))
        _tas7000 = AppStorage(wrappedValue: values.tasAt7000Feet, aircraft.cruiseTASKey(power: powerPercent, altitude: 7000))
        _tas10000 = AppStorage(wrappedValue: values.tasAt10000Feet, aircraft.cruiseTASKey(power: powerPercent, altitude: 10000))
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Dichtehöhe").font(.caption.bold())
                Text("TAS bei \(powerPercent) %").font(.caption.bold())
            }
            tasRow("1.000 ft", value: $tas1000)
            tasRow("3.000 ft", value: $tas3000)
            tasRow("5.000 ft", value: $tas5000)
            tasRow("7.000 ft", value: $tas7000)
            tasRow("10.000 ft", value: $tas10000)
        }
        .frame(maxWidth: .infinity)
    }

    private func tasRow(_ altitude: String, value: Binding<Double>) -> some View {
        GridRow {
            Text(altitude).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 5) {
                TextField(
                    "0",
                    value: value,
                    format: .number.precision(.fractionLength(0...1))
                )
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(width: 82)
                Text("KTAS").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
