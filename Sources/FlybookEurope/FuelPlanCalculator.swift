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
    let stageBurnLiters: Double
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

struct FuelPlanTransfer: Equatable {
    let airportICAO: String
    let refuelLiters: Double
}

enum FuelPlanFuelAvailability: Equatable {
    case available
    case unknown
    case unavailable

    init(_ rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if value.hasPrefix("nein") || value == "no" {
            self = .unavailable
        } else if value == "?" || value.isEmpty {
            self = .unknown
        } else {
            self = .available
        }
    }
}

struct FuelPlanAirportFuelData {
    let country: String
    let avgasAvailability: String
    let ul91Availability: String
    let mogasAvailability: String
    let avgasPriceEUR: Double?
    let ul91PriceEUR: Double?
    let mogasPriceEUR: Double?
    let vatPercent: Double?

    func availability(for fuel: AircraftFuelType) -> FuelPlanFuelAvailability {
        switch fuel {
        case .avgas: return FuelPlanFuelAvailability(avgasAvailability)
        case .ul91: return FuelPlanFuelAvailability(ul91Availability)
        case .ul94: return .unknown
        case .mogas: return FuelPlanFuelAvailability(mogasAvailability)
        }
    }

    func price(for fuel: AircraftFuelType) -> Double? {
        switch fuel {
        case .avgas: return avgasPriceEUR
        case .ul91: return ul91PriceEUR
        case .ul94: return nil
        case .mogas: return mogasPriceEUR
        }
    }

    var isForeign: Bool {
        !["DE", "DEUTSCHLAND"].contains(country.uppercased())
    }
}

struct FuelPlanConfirmation: Equatable {
    let aircraftName: String
    let reserveMinutes: Int
    let usableFuelLiters: Double
    let startingFuelLiters: Double
    let refuelAfterLegIndex: Int?
    let refuelLiters: Double
    let airportNames: [String: String]
    let result: FuelPlanResult
    let confirmedAt: Date

    func matches(
        legs: [FuelPlanLeg],
        reserveMinutes: Int,
        usableFuelLiters: Double,
        aircraftName: String,
        startingFuelLiters: Double,
        charterRefuelLiters: Double,
        charterRefuelAirportICAO: String
    ) -> Bool {
        let transfer = FuelPlanCalculator.transfer(
            legs: legs,
            refuelAfterLegIndex: refuelAfterLegIndex,
            refuelLiters: refuelLiters
        )
        return result.rows.map(\.leg) == legs
            && self.reserveMinutes == reserveMinutes
            && abs(self.usableFuelLiters - usableFuelLiters) < 0.000_1
            && self.aircraftName == aircraftName
            && abs(self.startingFuelLiters - startingFuelLiters) < 0.000_1
            && abs((transfer?.refuelLiters ?? 0) - charterRefuelLiters)
                < 0.000_1
            && (transfer?.airportICAO ?? "") == charterRefuelAirportICAO
    }
}

enum FuelPlanCalculator {
    static func roundedLitersForDisplay(_ value: Double) -> Int {
        if value >= 0 {
            return Int(ceil(value - 0.000_001))
        }
        return Int(floor(value + 0.000_001))
    }

    static func transfer(
        legs: [FuelPlanLeg],
        refuelAfterLegIndex: Int?,
        refuelLiters: Double
    ) -> FuelPlanTransfer? {
        guard let index = refuelAfterLegIndex,
              legs.indices.contains(index),
              index < legs.count - 1
        else { return nil }
        return FuelPlanTransfer(
            airportICAO: legs[index].destinationICAO,
            refuelLiters: max(0, refuelLiters)
        )
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

        // Der sichtbare Tankplan rechnet bewusst nur mit konservativen ganzen
        // Litern: Verbrauch und Reserve aufwärts, vorhandener Kraftstoff
        // abwärts. So stimmt jede angezeigte Subtraktion exakt und bleibt auf
        // der sicheren Seite.
        let capacity = floor(max(0, usableFuelLiters) + 0.000_001)
        let startFuel = floor(max(0, startingFuelLiters) + 0.000_001)
        let addedFuel = floor(max(0, refuelLiters) + 0.000_001)
        let burns = legs.map {
            Double(roundedLitersForDisplay($0.burnLiters))
        }
        let validRefuelIndex = refuelAfterLegIndex.flatMap {
            legs.indices.contains($0) && $0 < legs.count - 1 ? $0 : nil
        }
        let reserveHours = Double(max(0, reserveMinutes)) / 60
        let finalReserve = legs.last.map {
            ceil(max(0, $0.consumptionLitersPerHour) * reserveHours - 0.000_001)
        } ?? 0

        var minimumDepartures = Array(repeating: 0.0, count: legs.count)
        var minimumArrivals = Array(repeating: 0.0, count: legs.count)

        func fillStage(_ range: ClosedRange<Int>) {
            let stageReserve = ceil(max(
                0,
                legs[range.upperBound].consumptionLitersPerHour
            ) * reserveHours - 0.000_001)
            var requiredArrival = stageReserve
            for index in range.reversed() {
                minimumArrivals[index] = requiredArrival
                minimumDepartures[index] = requiredArrival
                    + burns[index]
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
                .indices.reduce(0) { $0 + burns[$1] }
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
        var stageBurn = 0.0

        for index in legs.indices {
            let departure = plannedFuel
            let arrival = departure - burns[index]
            stageBurn += burns[index]
            if departure + 0.000_1 < burns[index] {
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
                    refuelAfterArrivalLiters: addition,
                    stageBurnLiters: stageBurn
                )
            )
            plannedFuel = arrival + addition
            if addition > 0, plannedFuel > capacity + 0.000_1 {
                hasOverfill = true
            }
            if index == validRefuelIndex {
                stageBurn = 0
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
    let airportNames: [String: String]
    let airportFuelData: [String: FuelPlanAirportFuelData]
    let preferredFuel: AircraftFuelType
    let homeReferencePriceEUR: Double?
    @Binding var startingFuelLiters: Double
    @Binding var charterRefuelLiters: Double
    @Binding var charterRefuelAirportICAO: String
    @Binding var selectedFuelRaw: String
    let onConfirm: (FuelPlanConfirmation) -> Void

    @State private var refuelAfterLegIndex: Int?
    @State private var refuelLiters = 0.0
    @State private var followsMinimumRefuel = true
    @State private var didTransferRefuel = false

    private var refuelOptions: [Int] {
        guard legs.count > 1 else { return [] }
        return Array(legs.indices.dropLast()).filter {
            legs[$0].destinationICAO == legs[$0 + 1].originICAO
        }
    }

    private var selectedFuel: AircraftFuelType {
        AircraftFuelType(rawValue: selectedFuelRaw) ?? preferredFuel
    }

    private var selectedRefuelAirportICAO: String? {
        guard let index = refuelAfterLegIndex, legs.indices.contains(index)
        else { return nil }
        return legs[index].destinationICAO
    }

    private var selectedAirportFuelData: FuelPlanAirportFuelData? {
        selectedRefuelAirportICAO.flatMap { airportFuelData[$0] }
    }

    private var selectedFuelAvailability: FuelPlanFuelAvailability {
        selectedAirportFuelData?.availability(for: selectedFuel) ?? .unknown
    }

    private var preferredFuelAvailability: FuelPlanFuelAvailability {
        selectedAirportFuelData?.availability(for: preferredFuel) ?? .unknown
    }

    private var refuelSurchargeEUR: Double? {
        guard refuelAfterLegIndex != nil else { return 0 }
        guard selectedFuelAvailability != .unavailable,
              let data = selectedAirportFuelData
        else { return nil }
        return CharterMath.refuelLoss(
            grossPricePerLiter: data.price(for: selectedFuel),
            homeReferencePerLiter: homeReferencePriceEUR,
            liters: refuelLiters,
            destinationVATPercent: data.vatPercent,
            isForeign: data.isForeign
        )
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
            get: { floor(max(0, startingFuelLiters) + 0.000_001) },
            set: { newValue in
                startingFuelLiters = floor(max(0, newValue) + 0.000_001)
                didTransferRefuel = false
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
            get: { ceil(max(0, refuelLiters) - 0.000_001) },
            set: {
                followsMinimumRefuel = false
                refuelLiters = ceil(max(0, $0) - 0.000_001)
                didTransferRefuel = false
            }
        )
    }

    private var refuelSelectionBinding: Binding<Int?> {
        Binding(
            get: { refuelAfterLegIndex },
            set: { newValue in
                refuelAfterLegIndex = newValue
                followsMinimumRefuel = true
                didTransferRefuel = false
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
        airportNames: [String: String] = [:],
        airportFuelData: [String: FuelPlanAirportFuelData] = [:],
        preferredFuel: AircraftFuelType = .mogas,
        homeReferencePriceEUR: Double? = nil,
        startingFuelLiters: Binding<Double>,
        charterRefuelLiters: Binding<Double> = .constant(0),
        charterRefuelAirportICAO: Binding<String> = .constant(""),
        selectedFuelRaw: Binding<String> = .constant(AircraftFuelType.mogas.rawValue),
        initialRefuelAfterLegIndex: Int? = nil,
        initialRefuelLiters: Double = 0,
        onConfirm: @escaping (FuelPlanConfirmation) -> Void = { _ in }
    ) {
        self.legs = legs
        self.reserveMinutes = reserveMinutes
        self.usableFuelLiters = usableFuelLiters
        self.aircraftName = aircraftName
        self.airportNames = airportNames
        self.airportFuelData = airportFuelData
        self.preferredFuel = preferredFuel
        self.homeReferencePriceEUR = homeReferencePriceEUR
        _startingFuelLiters = startingFuelLiters
        _charterRefuelLiters = charterRefuelLiters
        _charterRefuelAirportICAO = charterRefuelAirportICAO
        _selectedFuelRaw = selectedFuelRaw
        self.onConfirm = onConfirm
        _refuelAfterLegIndex = State(initialValue: initialRefuelAfterLegIndex)
        _refuelLiters = State(initialValue: max(0, initialRefuelLiters))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            controls
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
            Button {
                let transfer = FuelPlanCalculator.transfer(
                    legs: legs,
                    refuelAfterLegIndex: refuelAfterLegIndex,
                    refuelLiters: refuelLiters
                )
                charterRefuelLiters = transfer?.refuelLiters ?? 0
                charterRefuelAirportICAO = transfer?.airportICAO ?? ""
                onConfirm(
                    FuelPlanConfirmation(
                        aircraftName: aircraftName,
                        reserveMinutes: reserveMinutes,
                        usableFuelLiters: usableFuelLiters,
                        startingFuelLiters: startingFuelLiters,
                        refuelAfterLegIndex: refuelAfterLegIndex,
                        refuelLiters: refuelLiters,
                        airportNames: airportNames,
                        result: result,
                        confirmedAt: Date()
                    )
                )
                didTransferRefuel = true
            } label: {
                Label(
                    didTransferRefuel
                        ? "Tankberechnung übernommen"
                        : "Tankberechnung übernehmen",
                    systemImage: didTransferRefuel
                        ? "checkmark.circle.fill"
                        : "arrow.down.to.line.compact"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(legs.isEmpty)
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
                didTransferRefuel = false
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
                didTransferRefuel = false
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
                Text("Refueling-Stop")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
                Picker("Refueling-Stop", selection: refuelSelectionBinding) {
                    Text("Kein Refueling-Stop").tag(Int?.none)
                    ForEach(refuelOptions, id: \.self) { index in
                        Text(legs[index].destinationICAO).tag(Optional(index))
                    }
                }
                .labelsHidden()
                .frame(width: 210)
            }
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
                        tankStopRow(row: row)
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
        .frame(height: 385, alignment: .top)
    }

    private var tableGroupHeader: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: 190, height: 20)
            tableGroupTitle("MINIMUM", width: 209)
            tableSeparator(height: 20)
            tableGroupTitle(
                "PLAN",
                width: 235,
                emphasized: true
            )
            tableSeparator(height: 20)
            tableGroupTitle("VERBRAUCH", width: 80)
            tableGroupTitle("ZEIT", width: 52)
            tableSeparator(height: 20)
            tableGroupTitle("MEHRPREIS", width: 78)
        }
        .padding(.horizontal, 12)
        .frame(height: 25)
        .background(Color.black.opacity(0.025))
    }

    private var tableHeader: some View {
        HStack(spacing: 6) {
            tableHeading("ABSCHNITT", width: 190, alignment: .leading)
            tableHeading("MINIMUM T/O", width: 98)
            tableHeading("MINIMUM LDG", width: 105)
            tableSeparator(height: 26)
            tableHeading("GEPLANT T/O", width: 100, emphasized: true)
            Color.clear.frame(width: 18, height: 1)
            tableHeading("GEPLANT LDG", width: 105, emphasized: true)
            tableSeparator(height: 26)
            tableHeading("LEG / GESAMT", width: 80)
            tableHeading("ZEIT", width: 52)
            tableSeparator(height: 26)
            tableHeading("BETRAG", width: 78)
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
        return HStack(spacing: 6) {
            Text("\(row.leg.originICAO) → \(row.leg.destinationICAO)")
                .font(.system(size: 14, weight: .bold))
            .frame(width: 190, alignment: .leading)

            tableValue(
                liters(row.minimumDepartureLiters),
                width: 98,
                minimumTakeoff: true
            )
            tableValue(liters(row.minimumArrivalLiters), width: 105)
            tableSeparator(height: 32)
            tableValue(
                liters(row.plannedDepartureLiters),
                width: 100,
                emphasized: true,
                warning: row.plannedDepartureLiters + 0.000_1
                    < row.minimumDepartureLiters
                    || row.plannedDepartureLiters > usableFuelLiters + 0.000_1
            )
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(FlybookColor.blue)
                .frame(width: 18)
            tableValue(
                liters(row.plannedArrivalLiters),
                width: 105,
                emphasized: true,
                warning: row.plannedArrivalLiters + 0.000_1
                    < row.minimumArrivalLiters
            )
            tableSeparator(height: 32)
            tableValue(stageBurnText(row), width: 80)
            tableValue(FlightMath.duration(row.leg.flightMinutes), width: 52)
            tableSeparator(height: 32)
            Color.clear.frame(width: 78, height: 1)
        }
        .foregroundStyle(FlybookColor.navy)
        .padding(.horizontal, 12)
        .frame(height: tableLegRowHeight)
        .background(isWarning ? Color.red.opacity(0.07) : Color.clear)
    }

    private func tankStopRow(row: FuelPlanRow) -> some View {
        HStack(spacing: 6) {
            Label(
                refuelingStopName(for: row.leg.destinationICAO),
                systemImage: "fuelpump.fill"
            )
            .font(.system(size: 13, weight: .heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .foregroundStyle(refuelingAirportColor)
            .help(fuelAvailabilityWarning ?? "Bevorzugter Kraftstoff verfügbar")
            .frame(width: 190, alignment: .leading)

            fuelPicker
                .frame(width: 98)
            Color.clear.frame(width: 105, height: 1)
            tableSeparator(height: 32)
            refuelPlanControl(row: row)
                .frame(width: 235)
            tableSeparator(height: 32)
            Color.clear.frame(width: 80, height: 1)
            Color.clear.frame(width: 52, height: 1)
            tableSeparator(height: 32)
            refuelSurchargeView.frame(width: 78)
        }
        .padding(.horizontal, 12)
        .frame(height: tableTankStopRowHeight)
        .background(FlybookColor.blue.opacity(0.12))
    }

    private var fuelPicker: some View {
        Picker("Kraftstoff", selection: $selectedFuelRaw) {
            ForEach(AircraftFuelType.allCases) { fuel in
                Text(fuel.rawValue).tag(fuel.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.mini)
        .onChange(of: selectedFuelRaw) { _ in didTransferRefuel = false }
    }

    private var refuelingAirportColor: Color {
        switch preferredFuelAvailability {
        case .available: return FlybookColor.navy
        case .unknown: return .orange
        case .unavailable: return .red
        }
    }

    private var fuelAvailabilityWarning: String? {
        guard refuelAfterLegIndex != nil else { return nil }
        switch preferredFuelAvailability {
        case .available:
            return nil
        case .unknown:
            return "Verfügbarkeit von (preferredFuel.rawValue) ist an diesem Tankstopp unbekannt."
        case .unavailable:
            return "Bevorzugter Kraftstoff (preferredFuel.rawValue) ist an diesem Tankstopp nicht verfügbar."
        }
    }

    @ViewBuilder
    private var refuelSurchargeView: some View {
        if let amount = refuelSurchargeEUR {
            Text(amount <= 0.004 ? "0 €" : currency(amount))
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(amount > 0.004 ? Color.red : FlybookColor.navy)
        } else {
            Text("?")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.orange)
        }
    }

    private func currency(_ amount: Double) -> String {
        amount.rounded(.toNearestOrAwayFromZero).formatted(
            .currency(code: "EUR")
                .locale(Locale(identifier: "de_DE"))
                .precision(.fractionLength(0))
        )
    }

    private func refuelPlanControl(row: FuelPlanRow) -> some View {
        HStack(spacing: 5) {
            TextField(
                "",
                value: refuelBinding,
                format: .number.precision(.fractionLength(0))
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13, weight: .heavy, design: .monospaced))
            .multilineTextAlignment(.trailing)
            .frame(width: 54)
            Text("L")
                .font(.system(size: 11, weight: .bold))
            Button("Minimum") {
                followsMinimumRefuel = true
                refuelLiters = roundedUp(result.minimumRefuelLiters)
                didTransferRefuel = false
            }
            .controlSize(.mini)
            Button("Voll") {
                followsMinimumRefuel = false
                refuelLiters = floor(
                    max(0, usableFuelLiters - row.plannedArrivalLiters)
                )
                didTransferRefuel = false
            }
            .controlSize(.mini)
        }
    }

    private func refuelingStopName(for icao: String) -> String {
        guard let name = airportNames[icao], !name.isEmpty else { return icao }
        let conciseName = name
            .split(separator: "/", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? name
        return "\(icao) - \(conciseName)"
    }

    private func stageBurnText(_ row: FuelPlanRow) -> String {
        let leg = FuelPlanCalculator.roundedLitersForDisplay(
            row.leg.burnLiters
        )
        let stage = FuelPlanCalculator.roundedLitersForDisplay(
            row.stageBurnLiters
        )
        return "\(leg) / \(stage) L"
    }

    @ViewBuilder
    private var warnings: some View {
        if result.hasWarning || fuelAvailabilityWarning != nil {
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
        if let fuelAvailabilityWarning {
            messages.append(fuelAvailabilityWarning)
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
                    format: .number.precision(.fractionLength(0))
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
        minimumTakeoff: Bool = false,
        warning: Bool = false
    ) -> some View {
        Text(text)
            .font(
                .system(
                    size: emphasized || minimumTakeoff ? 14 : 13,
                    weight: emphasized || minimumTakeoff ? .heavy : .semibold,
                    design: .monospaced
                )
            )
            .foregroundStyle(
                warning
                    ? Color.red
                    : (emphasized ? FlybookColor.blue : FlybookColor.navy)
            )
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
            .frame(height: 30)
            .background(
                warning
                    ? Color.red.opacity(0.10)
                    : (minimumTakeoff
                        ? Color.yellow.opacity(0.24)
                        : (emphasized
                            ? FlybookColor.blue.opacity(0.08)
                            : Color.clear)),
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
