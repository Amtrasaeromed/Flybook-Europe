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

    var cruiseSpeedKey: String {
        keyPrefix + ".cruiseGroundSpeedKnots"
    }

    var fuelConsumptionKey: String {
        keyPrefix + ".fuelConsumptionPerHour"
    }

    var usableFuelKey: String {
        keyPrefix + ".usableFuel"
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

    static func cruiseSpeed(
        for aircraft: AircraftType
    ) -> Double {
        storedValue(
            key: aircraft.cruiseSpeedKey,
            fallback:
                aircraft.defaultCruiseGroundSpeedKnots
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
                        "Leistungs-, Kraftstoff- und Kostendaten je Flugzeug"
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
        .frame(width: 680, height: 520)
    }
}

private struct AircraftProfileEditor: View {
    let aircraft: AircraftType

    @AppStorage private var hourlyRateEUR: Double
    @AppStorage private var cruiseSpeedKnots: Double
    @AppStorage private var fuelConsumptionPerHour: Double
    @AppStorage private var usableFuel: Double

    init(aircraft: AircraftType) {
        self.aircraft = aircraft

        _hourlyRateEUR = AppStorage(
            wrappedValue:
                aircraft.defaultHourlyRateEUR,
            aircraft.hourlyRateKey
        )

        _cruiseSpeedKnots = AppStorage(
            wrappedValue:
                aircraft.defaultCruiseGroundSpeedKnots,
            aircraft.cruiseSpeedKey
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
    }

    var body: some View {
        GroupBox(aircraft.rawValue) {
            VStack(spacing: 18) {
                profileRow(
                    title: "Stundenpreis",
                    value: $hourlyRateEUR,
                    range: 50...500,
                    step: 5,
                    suffix: "EUR / Stunde"
                )

                profileRow(
                    title: "Reisefluggeschwindigkeit",
                    value: $cruiseSpeedKnots,
                    range: 60...200,
                    step: 1,
                    suffix: "kt GS"
                )

                profileRow(
                    title: "Kraftstoffverbrauch",
                    value: $fuelConsumptionPerHour,
                    range: 0...60,
                    step: 1,
                    suffix: "/ h"
                )

                profileRow(
                    title: "Ausfliegbarer Kraftstoff",
                    value: $usableFuel,
                    range: 0...250,
                    step: 1,
                    suffix: ""
                )

                HStack {
                    Spacer()

                    Button("Profil zurücksetzen") {
                        hourlyRateEUR =
                            aircraft.defaultHourlyRateEUR
                        cruiseSpeedKnots =
                            aircraft
                                .defaultCruiseGroundSpeedKnots
                        fuelConsumptionPerHour =
                            aircraft
                                .defaultFuelConsumptionPerHour
                        usableFuel =
                            aircraft.defaultUsableFuel
                    }
                }
            }
            .padding(10)
        }
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
