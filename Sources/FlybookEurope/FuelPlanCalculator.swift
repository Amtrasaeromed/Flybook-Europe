import SwiftUI

struct FuelPlanLeg: Equatable, Identifiable {
    let id: String
    let originICAO: String
    let destinationICAO: String
    let flightMinutes: Int
    let consumptionLitersPerHour: Double

    var burnLiters: Double {
        Double(max(0, flightMinutes))
            * max(0, consumptionLitersPerHour)
            / 60
    }
}

struct FuelPlanRow: Equatable, Identifiable {
    let id: String
    let leg: FuelPlanLeg
    let minimumDepartureLiters: Double
    let minimumArrivalLiters: Double
    let plannedDepartureLiters: Double
    let plannedArrivalLiters: Double
    let refuelAfterArrivalLiters: Double
}

struct FuelPlanResult: Equatable {
    let rows: [FuelPlanRow]
    let minimumStartingFuelLiters: Double
    let minimumRefuelLiters: Double
    let finalReserveLiters: Double
    let usableFuelLiters: Double
    let hasCapacityViolation: Bool
    let hasStartingFuelShortfall: Bool
    let hasRefuelShortfall: Bool
    let hasFinalReserveShortfall: Bool
    let hasFuelExhaustion: Bool
    let hasOverfill: Bool

    var hasWarning: Bool {
        hasCapacityViolation
            || hasStartingFuelShortfall
            || hasRefuelShortfall
            || hasFinalReserveShortfall
            || hasFuelExhaustion
            || hasOverfill
    }
}

enum FuelPlanCalculator {
    static func roundedLitersForDisplay(_ value: Double) -> Int {
        if value >= 0 {
            return Int(ceil(value - 0.000_001))
        }
        return Int(floor(value + 0.000_001))
    }

    static func calculate(
        legs: [FuelPlanLeg],
        reserveMinutes: Int,
        usableFuelLiters: Double,
        startingFuelLiters: Double,
        refuelAfterLegIndex: Int?,
        refuelLiters: Double
    ) -> FuelPlanResult {
        guard !legs.isEmpty else {
            return FuelPlanResult(
                rows: [],
                minimumStartingFuelLiters: 0,
                minimumRefuelLiters: 0,
                finalReserveLiters: 0,
                usableFuelLiters: max(0, usableFuelLiters),
                hasCapacityViolation: false,
                hasStartingFuelShortfall: false,
                hasRefuelShortfall: false,
                hasFinalReserveShortfall: false,
                hasFuelExhaustion: false,
                hasOverfill: false
            )
        }

        let capacity = max(0, usableFuelLiters)
        let startFuel = max(0, startingFuelLiters)
        let addedFuel = max(0, refuelLiters)
        let validRefuelIndex = refuelAfterLegIndex.flatMap {
            legs.indices.contains($0) && $0 < legs.count - 1 ? $0 : nil
        }
        let reserveHours = Double(max(0, reserveMinutes)) / 60
        let finalReserve = legs.last.map {
            max(0, $0.consumptionLitersPerHour) * reserveHours
        } ?? 0

        var minimumDepartures = Array(repeating: 0.0, count: legs.count)
        var minimumArrivals = Array(repeating: 0.0, count: legs.count)

        func fillStage(_ range: ClosedRange<Int>) {
            let stageReserve = max(
                0,
                legs[range.upperBound].consumptionLitersPerHour
            ) * reserveHours
            var requiredArrival = stageReserve
            for index in range.reversed() {
                minimumArrivals[index] = requiredArrival
                minimumDepartures[index] = requiredArrival
                    + legs[index].burnLiters
                requiredArrival = minimumDepartures[index]
            }
        }

        if let refuelIndex = validRefuelIndex {
            fillStage(0...refuelIndex)
            fillStage((refuelIndex + 1)...(legs.count - 1))
        } else {
            fillStage(0...(legs.count - 1))
        }

        let minimumStart = minimumDepartures[0]
        let fuelAtRefuelBeforeAdding: Double
        if let refuelIndex = validRefuelIndex {
            let burnedBeforeRefuel = legs[0...refuelIndex]
                .reduce(0) { $0 + $1.burnLiters }
            fuelAtRefuelBeforeAdding = max(0, startFuel - burnedBeforeRefuel)
        } else {
            fuelAtRefuelBeforeAdding = 0
        }
        let minimumRefuel = validRefuelIndex.map {
            max(
                0,
                minimumDepartures[$0 + 1] - fuelAtRefuelBeforeAdding
            )
        } ?? 0

        var plannedFuel = startFuel
        var rows: [FuelPlanRow] = []
        var hasFuelExhaustion = false
        var hasOverfill = plannedFuel > capacity + 0.000_1

        for index in legs.indices {
            let departure = plannedFuel
            let arrival = departure - legs[index].burnLiters
            if departure + 0.000_1 < legs[index].burnLiters {
                hasFuelExhaustion = true
            }
            let addition = index == validRefuelIndex ? addedFuel : 0
            rows.append(
                FuelPlanRow(
                    id: legs[index].id,
                    leg: legs[index],
                    minimumDepartureLiters: minimumDepartures[index],
                    minimumArrivalLiters: minimumArrivals[index],
                    plannedDepartureLiters: departure,
                    plannedArrivalLiters: arrival,
                    refuelAfterArrivalLiters: addition
                )
            )
            plannedFuel = arrival + addition
            if addition > 0, plannedFuel > capacity + 0.000_1 {
                hasOverfill = true
            }
        }

        let hasCapacityViolation = minimumDepartures.contains {
            $0 > capacity + 0.000_1
        }
        let hasStartingFuelShortfall = startFuel + 0.000_1 < minimumStart
        let hasRefuelShortfall = validRefuelIndex != nil
            && addedFuel + 0.000_1 < minimumRefuel
        let finalArrival = rows.last?.plannedArrivalLiters ?? 0
        let hasFinalReserveShortfall =
            finalArrival + 0.000_1 < finalReserve

        return FuelPlanResult(
            rows: rows,
            minimumStartingFuelLiters: minimumStart,
            minimumRefuelLiters: minimumRefuel,
            finalReserveLiters: finalReserve,
            usableFuelLiters: capacity,
            hasCapacityViolation: hasCapacityViolation,
            hasStartingFuelShortfall: hasStartingFuelShortfall,
            hasRefuelShortfall: hasRefuelShortfall,
            hasFinalReserveShortfall: hasFinalReserveShortfall,
            hasFuelExhaustion: hasFuelExhaustion,
            hasOverfill: hasOverfill
        )
    }
}

struct FuelPlanCalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    let legs: [FuelPlanLeg]
    let reserveMinutes: Int
    let usableFuelLiters: Double
    let aircraftName: String
    @Binding var startingFuelLiters: Double

    @State private var refuelAfterLegIndex: Int?
    @State private var refuelLiters = 0.0
    @State private var followsMinimumRefuel = true

    private var refuelOptions: [Int] {
        guard legs.count > 1 else { return [] }
        return Array(legs.indices.dropLast()).filter {
            legs[$0].destinationICAO == legs[$0 + 1].originICAO
        }
    }

    private var result: FuelPlanResult {
        FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: reserveMinutes,
            usableFuelLiters: usableFuelLiters,
            startingFuelLiters: startingFuelLiters,
            refuelAfterLegIndex: refuelAfterLegIndex,
            refuelLiters: refuelLiters
        )
    }

    private var tableEntryCount: Int {
        result.rows.count + (refuelAfterLegIndex == nil ? 0 : 1)
    }

    private var tableLegRowHeight: CGFloat {
        tableEntryCount >= 6 ? 30 : 40
    }

    private var tableTankStopRowHeight: CGFloat {
        tableEntryCount >= 6 ? 38 : 44
    }

    private var startFuelBinding: Binding<Double> {
        Binding(
            get: { startingFuelLiters },
            set: { newValue in
                startingFuelLiters = max(0, newValue)
                if followsMinimumRefuel {
                    refuelLiters = roundedUpMinimumRefuel(
                        after: refuelAfterLegIndex,
                        startingFuel: startingFuelLiters
                    )
                }
            }
        )
    }

    private var refuelBinding: Binding<Double> {
        Binding(
            get: { refuelLiters },
            set: {
                followsMinimumRefuel = false
                refuelLiters = max(0, $0)
            }
        )
    }

    private var refuelSelectionBinding: Binding<Int?> {
        Binding(
            get: { refuelAfterLegIndex },
            set: { newValue in
                refuelAfterLegIndex = newValue
                followsMinimumRefuel = true
                refuelLiters = roundedUpMinimumRefuel(
                    after: newValue,
                    startingFuel: startingFuelLiters
                )
            }
        )
    }

    init(
        legs: [FuelPlanLeg],
        reserveMinutes: Int,
        usableFuelLiters: Double,
        aircraftName: String,
        startingFuelLiters: Binding<Double>,
        initialRefuelAfterLegIndex: Int? = nil,
        initialRefuelLiters: Double = 0
    ) {
        self.legs = legs
        self.reserveMinutes = reserveMinutes
        self.usableFuelLiters = usableFuelLiters
        self.aircraftName = aircraftName
        _startingFuelLiters = startingFuelLiters
        _refuelAfterLegIndex = State(initialValue: initialRefuelAfterLegIndex)
        _refuelLiters = State(initialValue: max(0, initialRefuelLiters))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            controls
            summary
            table
            warnings
        }
        .padding(20)
        .frame(width: 980, height: 640, alignment: .topLeading)
        .background(FlybookColor.background)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Label("TANKKALKULATOR", systemImage: "fuelpump.fill")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)
                Text(
                    "\(aircraftName) · \(Int(usableFuelLiters.rounded())) L nutzbar"
                    + " · Reserve \(reserveMinutes) min"
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FlybookColor.muted)
            }
            Spacer()
            Button("Schließen") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var controls: some View {
        HStack(alignment: .bottom, spacing: 14) {
            fuelInput(
                title: "Tankbestand beim Start in \(legs.first?.originICAO ?? "–")",
                value: startFuelBinding
            )
            Button("Minimum") {
                startingFuelLiters = roundedUp(result.minimumStartingFuelLiters)
                if followsMinimumRefuel {
                    refuelLiters = roundedUpMinimumRefuel(
                        after: refuelAfterLegIndex,
                        startingFuel: startingFuelLiters
                    )
                }
            }
            .controlSize(.small)
            Button("Voll") {
                startingFuelLiters = max(0, usableFuelLiters)
                if followsMinimumRefuel {
                    refuelLiters = roundedUpMinimumRefuel(
                        after: refuelAfterLegIndex,
                        startingFuel: startingFuelLiters
                    )
                }
            }
            .controlSize(.small)

            Divider().frame(height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text("Tankpunkt")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
                Picker("Tankpunkt", selection: refuelSelectionBinding) {
                    Text("Kein Tankstopp").tag(Int?.none)
                    ForEach(refuelOptions, id: \.self) { index in
                        Text(
                            "\(legs[index].destinationICAO) nach "
                            + "\(legs[index].originICAO)→\(legs[index].destinationICAO)"
                        )
                        .tag(Optional(index))
                    }
                }
                .labelsHidden()
                .frame(width: 210)
            }

            fuelInput(
                title: "Auffüllen am Tankpunkt",
                value: refuelBinding,
                disabled: refuelAfterLegIndex == nil
            )
            Button("Minimum") {
                followsMinimumRefuel = true
                refuelLiters = roundedUp(result.minimumRefuelLiters)
            }
            .controlSize(.small)
            .disabled(refuelAfterLegIndex == nil)
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            summaryBox(
                title: "MINDESTBESTAND START",
                value: liters(result.minimumStartingFuelLiters),
                warning: result.hasStartingFuelShortfall
            )
            summaryBox(
                title: "MINDEST-AUFFÜLLMENGE",
                value: refuelAfterLegIndex == nil
                    ? "–"
                    : liters(result.minimumRefuelLiters),
                warning: result.hasRefuelShortfall
            )
            summaryBox(
                title: "RESERVE AM ENDZIEL",
                value: liters(result.finalReserveLiters),
                warning: result.hasFinalReserveShortfall
            )
            summaryBox(
                title: "TANKKAPAZITÄT",
                value: liters(result.usableFuelLiters),
                warning: result.hasCapacityViolation || result.hasOverfill
            )
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            tableGroupHeader
            tableHeader
            Divider()
            VStack(spacing: 0) {
                ForEach(Array(result.rows.enumerated()), id: \.element.id) {
                    index, row in
                    tableRow(index: index, row: row)
                    if refuelAfterLegIndex == index {
                        Divider().overlay(FlybookColor.blue.opacity(0.55))
                        tankStopRow(after: index, row: row)
                        if index < result.rows.count - 1 {
                            Divider().overlay(FlybookColor.blue.opacity(0.55))
                        }
                    } else if index < result.rows.count - 1 {
                        Divider()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(FlybookColor.line, lineWidth: 1)
        )
        .frame(height: 310, alignment: .top)
    }

    private var tableGroupHeader: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 160, height: 20)
            tableGroupTitle("ZEIT UND VERBRAUCH", width: 162)
            tableSeparator(height: 20)
            tableGroupTitle("MINIMUM", width: 240)
            tableSeparator(height: 20)
            tableGroupTitle(
                "TATSÄCHLICHER PLAN",
                width: 242,
                emphasized: true
            )
        }
        .padding(.horizontal, 12)
        .frame(height: 25)
        .background(Color.black.opacity(0.025))
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            tableHeading("ABSCHNITT", width: 160, alignment: .leading)
            tableHeading("ZEIT", width: 62)
            tableHeading("VERBRAUCH", width: 92)
            tableSeparator(height: 26)
            tableHeading("MINIMUM T/O", width: 112)
            tableHeading("MINIMUM LDG", width: 120)
            tableSeparator(height: 26)
            tableHeading("GEPLANT T/O", width: 112, emphasized: true)
            tableHeading("GEPLANT LDG", width: 122, emphasized: true)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }

    private func tableRow(index: Int, row: FuelPlanRow) -> some View {
        let isWarning = row.plannedDepartureLiters + 0.000_1
            < row.minimumDepartureLiters
            || row.plannedArrivalLiters + 0.000_1
                < row.minimumArrivalLiters
            || row.plannedDepartureLiters > usableFuelLiters + 0.000_1
        return HStack(spacing: 8) {
            Text("\(row.leg.originICAO) → \(row.leg.destinationICAO)")
                .font(.system(size: 14, weight: .bold))
            .frame(width: 160, alignment: .leading)

            tableValue(FlightMath.duration(row.leg.flightMinutes), width: 62)
            tableValue(liters(row.leg.burnLiters), width: 92)
            tableSeparator(height: 32)
            tableValue(liters(row.minimumDepartureLiters), width: 112)
            tableValue(liters(row.minimumArrivalLiters), width: 120)
            tableSeparator(height: 32)
            tableValue(
                liters(row.plannedDepartureLiters),
                width: 112,
                emphasized: true,
                warning: row.plannedDepartureLiters + 0.000_1
                    < row.minimumDepartureLiters
                    || row.plannedDepartureLiters > usableFuelLiters + 0.000_1
            )
            tableValue(
                liters(row.plannedArrivalLiters),
                width: 122,
                emphasized: true,
                warning: row.plannedArrivalLiters + 0.000_1
                    < row.minimumArrivalLiters
            )
        }
        .foregroundStyle(FlybookColor.navy)
        .padding(.horizontal, 12)
        .frame(height: tableLegRowHeight)
        .background(isWarning ? Color.red.opacity(0.07) : Color.clear)
    }

    private func tankStopRow(after index: Int, row: FuelPlanRow) -> some View {
        let before = row.plannedArrivalLiters
        let addition = row.refuelAfterArrivalLiters
        let after = before + addition
        let nextMinimum = result.rows.indices.contains(index + 1)
            ? result.rows[index + 1].minimumDepartureLiters
            : 0
        return HStack(spacing: 12) {
            Label(
                "TANKSTOPP \(row.leg.destinationICAO)",
                systemImage: "fuelpump.fill"
            )
            .font(.system(size: 13, weight: .heavy))
            .frame(width: 160, alignment: .leading)

            tankStopValue("VORHER", value: liters(before))
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(FlybookColor.blue)
            tankStopValue("AUFFÜLLEN", value: liters(addition))
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(FlybookColor.blue)
            tankStopValue("GEPLANT T/O", value: liters(after))
            Spacer(minLength: 4)
            tankStopValue("MINIMUM T/O", value: liters(nextMinimum))
        }
        .padding(.horizontal, 12)
        .frame(height: tableTankStopRowHeight)
        .foregroundStyle(FlybookColor.navy)
        .background(FlybookColor.blue.opacity(0.12))
    }

    private func tankStopValue(_ title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
        }
    }

    @ViewBuilder
    private var warnings: some View {
        if result.hasWarning {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(warningMessages, id: \.self) { message in
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                }
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.red)
        } else {
            Label(
                "Tankplan erfüllt alle Mindestbestände einschließlich Endreserve.",
                systemImage: "checkmark.circle.fill"
            )
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.green)
        }
    }

    private var warningMessages: [String] {
        var messages: [String] = []
        if result.hasCapacityViolation {
            messages.append("Mindestens ein Abschnitt bis zum nächsten Tankpunkt überschreitet die nutzbare Tankkapazität.")
        }
        if result.hasStartingFuelShortfall {
            messages.append(
                refuelAfterLegIndex == nil
                    ? "Der gewählte Startbestand reicht nicht für die gesamte Planung einschließlich Endreserve."
                    : "Der gewählte Startbestand reicht nicht bis zum Tankpunkt einschließlich Reserve."
            )
        }
        if result.hasRefuelShortfall {
            messages.append("Die gewählte Auffüllmenge reicht ab dem Tankpunkt nicht aus.")
        }
        if result.hasFuelExhaustion {
            messages.append("Der geplante Tankbestand wird auf mindestens einem Leg negativ.")
        }
        if result.hasFinalReserveShortfall {
            messages.append("Am Endziel bleibt nicht die vorgeschriebene Reserve übrig.")
        }
        if result.hasOverfill {
            messages.append("Der geplante Tankbestand überschreitet die nutzbare Tankkapazität.")
        }
        return messages
    }

    private func fuelInput(
        title: String,
        value: Binding<Double>,
        disabled: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
                .lineLimit(1)
            HStack(spacing: 4) {
                TextField(
                    "",
                    value: value,
                    format: .number.precision(.fractionLength(1))
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.trailing)
                Text("L")
                    .font(.system(size: 12, weight: .bold))
            }
            .frame(width: 120)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private func summaryBox(
        title: String,
        value: String,
        warning: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .monospaced))
                .foregroundStyle(warning ? Color.red : FlybookColor.navy)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 57, alignment: .leading)
        .background(
            warning ? Color.red.opacity(0.09) : Color.white.opacity(0.82),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(warning ? Color.red.opacity(0.45) : FlybookColor.line)
        )
    }

    private func tableHeading(
        _ text: String,
        width: CGFloat,
        alignment: Alignment = .trailing,
        emphasized: Bool = false
    ) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(emphasized ? FlybookColor.blue : FlybookColor.muted)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }

    private func tableGroupTitle(
        _ text: String,
        width: CGFloat,
        emphasized: Bool = false
    ) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(emphasized ? FlybookColor.blue : FlybookColor.muted)
            .frame(width: width)
            .frame(height: 20)
            .background(
                emphasized ? FlybookColor.blue.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
    }

    private func tableSeparator(height: CGFloat) -> some View {
        Rectangle()
            .fill(FlybookColor.line.opacity(0.9))
            .frame(width: 1, height: height)
    }

    private func tableValue(
        _ text: String,
        width: CGFloat,
        emphasized: Bool = false,
        warning: Bool = false
    ) -> some View {
        Text(text)
            .font(
                .system(
                    size: emphasized ? 14 : 13,
                    weight: emphasized ? .heavy : .semibold,
                    design: .monospaced
                )
            )
            .foregroundStyle(
                warning ? Color.red : (emphasized ? FlybookColor.blue : FlybookColor.navy)
            )
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
            .frame(height: 30)
            .background(
                emphasized
                    ? (warning ? Color.red.opacity(0.10) : FlybookColor.blue.opacity(0.08))
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
    }

    private func roundedUpMinimumRefuel(
        after index: Int?,
        startingFuel: Double
    ) -> Double {
        let minimum = FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: reserveMinutes,
            usableFuelLiters: usableFuelLiters,
            startingFuelLiters: startingFuel,
            refuelAfterLegIndex: index,
            refuelLiters: 0
        ).minimumRefuelLiters
        return roundedUp(minimum)
    }

    private func roundedUp(_ value: Double) -> Double {
        ceil(max(0, value) - 0.000_001)
    }

    private func liters(_ value: Double) -> String {
        "\(FuelPlanCalculator.roundedLitersForDisplay(value)) L"
    }
}
