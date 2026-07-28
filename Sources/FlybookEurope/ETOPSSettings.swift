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

enum CalculationSettingsKey {
    static let tankStopMinutes =
        "flybookTankStopMinutes"
    static let vatPercent =
        "flybookVATPercent"
    static let weekdayDiscountEnabled =
        "flybookWeekdayDiscountEnabled"
    static let reserveMinutes =
        "flybookReserveMinutes"
    static let maxTravelMinutesUntilOvernight =
        "flybookMaxTravelMinutesUntilOvernight"
    static let prepaymentDiscount15To29Enabled =
        "flybookPrepaymentDiscount15To29Enabled"
    static let prepaymentDiscount30PlusEnabled =
        "flybookPrepaymentDiscount30PlusEnabled"
}

enum CalculationSettings {
    static let defaultTankStopMinutes = 60
    static let defaultVATPercent = 7.0
    static let defaultWeekdayDiscountEnabled = true
    static let defaultReserveMinutes = 45
    static let defaultMaxTravelMinutesUntilOvernight = 105
    static let defaultPrepaymentDiscount15To29Enabled = false
    static let defaultPrepaymentDiscount30PlusEnabled = false
}

enum ETOPSSettingsKey {
    static let greenYellowMinutes = "etopsGreenYellowMinutes"
    static let orangeRedMinutes = "etopsOrangeRedMinutes"
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
}

struct ETOPSSetupView: View {
    @AppStorage(ETOPSSettingsKey.greenYellowMinutes)
    private var greenYellowMinutes =
        ETOPSScale.defaultGreenYellowMinutes

    @AppStorage(ETOPSSettingsKey.orangeRedMinutes)
    private var orangeRedMinutes =
        ETOPSScale.defaultOrangeRedMinutes

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

    @AppStorage(
        CalculationSettingsKey.maxTravelMinutesUntilOvernight
    )
    private var maxTravelMinutesUntilOvernight =
        CalculationSettings
            .defaultMaxTravelMinutesUntilOvernight

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

    @AppStorage(PressureSettingsKey.displayUnit)
    private var pressureDisplayUnitRaw =
        PressureDisplayUnit.mbar.rawValue

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ETOPS-PIPI Setup")
                        .font(.title2.bold())
                    Text("Grenzen für die farbliche Bewertung der Dauer eines einzelnen Fluglegs")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Schließen") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            HStack {
                Text("Luftdruckanzeige")
                    .font(.headline)
                Spacer()
                Picker(
                    "Luftdruckanzeige",
                    selection: $pressureDisplayUnitRaw
                ) {
                    ForEach(PressureDisplayUnit.allCases) { unit in
                        Text(unit.label).tag(unit.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            thresholdRow(
                title: "Grenze Grün → Gelb",
                minutes: $greenYellowMinutes,
                color: .green
            )

            thresholdRow(
                title: "Grenze Orange → Rot",
                minutes: $orangeRedMinutes,
                color: .red
            )

            let limits = ETOPSScale.normalized(
                greenYellow: greenYellowMinutes,
                orangeRed: orangeRedMinutes
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("Automatisch interpolierte Skala")
                    .font(.headline)

                HStack(spacing: 0) {
                    Color.green
                    Color.yellow
                    Color.orange
                    Color.red
                }
                .frame(height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack {
                    Text("Grün bis \(duration(limits.greenYellow))")
                    Spacer()
                    Text("Gelb/Orange bei \(duration(limits.yellowOrange))")
                    Spacer()
                    Text("Rot ab \(duration(limits.orangeRed))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text("Die Grenze Gelb → Orange wird genau zwischen den beiden eingegebenen Grenzen interpoliert. Die Farbpunkte im Flugfeld werden aus der berechneten Dauer eines einzelnen Fluglegs bestimmt. Bei Nonstop gilt die gesamte Flugzeit als ein Leg; bei einem oder zwei Stopps wird die reine Flugzeit ohne Bodenstopps gleichmäßig auf zwei beziehungsweise drei Legs verteilt. Der Windeinfluss wird richtungsabhängig berücksichtigt.")
                .font(.callout)
                .foregroundStyle(.secondary)


            GroupBox("FLUGKALKULATION") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Tankstoppzeit")
                            .font(.headline)
                            .frame(
                                width: 190,
                                alignment: .leading
                            )

                        Stepper(
                            value: $tankStopMinutes,
                            in: 0...180,
                            step: 5
                        ) {
                            Text(
                                "\(tankStopMinutes) Minuten"
                            )
                            .frame(
                                width: 120,
                                alignment: .trailing
                            )
                        }
                    }

HStack {
                        Text("Mehrwertsteuer")
                            .font(.headline)
                            .frame(
                                width: 190,
                                alignment: .leading
                            )

                        Stepper(
                            value: $vatPercent,
                            in: 0...25,
                            step: 1
                        ) {
                            Text(
                                String(
                                    format: "%.0f %%",
                                    vatPercent
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
                                width: 120,
                                alignment: .trailing
                            )
                        }
                        .frame(width: 190)

                        Text("%")
                            .foregroundStyle(.secondary)
                    }

HStack {
                        Text("Reserve")
                            .font(.headline)
                            .frame(
                                width: 190,
                                alignment: .leading
                            )

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
                    }

HStack {
                        Text("Max. Reisezeit bis Übernachtung")
                            .font(.headline)
                            .frame(
                                width: 250,
                                alignment: .leading
                            )

                        Picker(
                            "Stunden",
                            selection:
                                maxTravelHoursBinding
                        ) {
                            ForEach(0...6, id: \.self) {
                                hour in
                                Text("\(hour) h")
                                    .tag(hour)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)

                        Picker(
                            "Minuten",
                            selection:
                                maxTravelMinutesBinding
                        ) {
                            ForEach(
                                Array(
                                    stride(
                                        from: 0,
                                        through: 55,
                                        by: 5
                                    )
                                ),
                                id: \.self
                            ) { minute in
                                Text(
                                    String(
                                        format: "%02d min",
                                        minute
                                    )
                                )
                                .tag(minute)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 105)

                        Text(
                            duration(
                                maxTravelMinutesUntilOvernight
                            )
                        )
                        .font(
                            .system(
                                size: 15,
                                weight: .bold,
                                design: .monospaced
                            )
                        )
                        .frame(width: 60)
                    }


                    VStack(alignment: .leading, spacing: 8) {
                        Text("Discount Vorauszahlung")
                            .font(.headline)

                        Toggle(
                            "15–29 Tage: 25 %",
                            isOn:
                                prepaymentDiscount15To29Binding
                        )
                        .toggleStyle(.checkbox)

                        Toggle(
                            "ab 30 Tagen: 15 %",
                            isOn:
                                prepaymentDiscount30PlusBinding
                        )
                        .toggleStyle(.checkbox)
                    }

                    Toggle(
                        "Discount Wochentag (5 % Montag–Freitag)",
                        isOn: $weekdayDiscountEnabled
                    )
                    .toggleStyle(.checkbox)

                    Text(
                        "Blockzeit umfasst Flug- und Rollzeit, "
                        + "nicht die Standzeit beim Tankstopp."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(8)
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
                    vatPercent =
                        CalculationSettings.defaultVATPercent
                    weekdayDiscountEnabled =
                        CalculationSettings
                            .defaultWeekdayDiscountEnabled
                    reserveMinutes =
                        CalculationSettings
                            .defaultReserveMinutes
                    maxTravelMinutesUntilOvernight =
                        CalculationSettings
                            .defaultMaxTravelMinutesUntilOvernight
                    prepaymentDiscount15To29Enabled =
                        CalculationSettings
                            .defaultPrepaymentDiscount15To29Enabled
                    prepaymentDiscount30PlusEnabled =
                        CalculationSettings
                            .defaultPrepaymentDiscount30PlusEnabled
                }
                Spacer()
            }
            }
            .padding(28)
        }
        .frame(width: 780, height: 720)
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

    private var maxTravelHoursBinding: Binding<Int> {
        Binding(
            get: {
                maxTravelMinutesUntilOvernight / 60
            },
            set: { hours in
                let minutes =
                    maxTravelMinutesUntilOvernight % 60

                maxTravelMinutesUntilOvernight =
                    max(30, hours * 60 + minutes)
            }
        )
    }

    private var maxTravelMinutesBinding: Binding<Int> {
        Binding(
            get: {
                maxTravelMinutesUntilOvernight % 60
            },
            set: { minutes in
                let hours =
                    maxTravelMinutesUntilOvernight / 60

                maxTravelMinutesUntilOvernight =
                    max(30, hours * 60 + minutes)
            }
        )
    }

    private func thresholdRow(
        title: String,
        minutes: Binding<Int>,
        color: Color
    ) -> some View {
        HStack(spacing: 18) {
            Circle()
                .fill(color)
                .frame(width: 16, height: 16)

            Text(title)
                .font(.headline)
                .frame(width: 190, alignment: .leading)

            Picker("Stunden", selection: hourBinding(minutes)) {
                ForEach(0..<10, id: \.self) { hour in
                    Text("\(hour) h").tag(hour)
                }
            }
            .labelsHidden()
            .frame(width: 90)

            Picker("Minuten", selection: minuteBinding(minutes)) {
                ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { minute in
                    Text(String(format: "%02d min", minute)).tag(minute)
                }
            }
            .labelsHidden()
            .frame(width: 105)

            Text(duration(minutes.wrappedValue))
                .font(.system(.title3, design: .monospaced).bold())
                .frame(width: 72)
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
