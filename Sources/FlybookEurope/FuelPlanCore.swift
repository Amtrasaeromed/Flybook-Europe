import Foundation

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
    let minimumRefuelLitersByLegIndex: [Int: Double]
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

struct FuelActualRow: Equatable, Identifiable {
    let id: String
    let leg: FuelPlanLeg
    let actualDepartureLiters: Double
    let actualArrivalLiters: Double
    let requiredRefuelAfterArrivalLiters: Double
    let arrivalWasMeasured: Bool
}

struct FuelActualResult: Equatable {
    let rows: [FuelActualRow]
    let actualStartingFuelLiters: Double
    let finalFuelLiters: Double
    let hasFuelExhaustion: Bool
    let hasFinalReserveShortfall: Bool
    let hasOverfill: Bool

    var hasWarning: Bool {
        hasFuelExhaustion || hasFinalReserveShortfall || hasOverfill
    }
}

enum FuelActualCalculator {
    /// Recalculates the live fuel state from measured checkpoints. Between
    /// measurements the conservative planned leg burn remains authoritative.
    /// At selected fuel stops the required quantity is derived again from the
    /// plan minimum, so extra fuel found before departure reduces later uplift.
    static func calculate(
        plan: FuelPlanResult,
        actualStartingFuelLiters: Double,
        actualArrivalOverridesByLegIndex: [Int: Double],
        refuelAfterLegIndices: Set<Int>
    ) -> FuelActualResult {
        let capacity = floor(max(0, plan.usableFuelLiters) + 0.000_001)
        var currentFuel = floor(max(0, actualStartingFuelLiters) + 0.000_001)
        var rows: [FuelActualRow] = []
        var hasFuelExhaustion = false
        var hasOverfill = currentFuel > capacity + 0.000_1

        for index in plan.rows.indices {
            let planned = plan.rows[index]
            let burn = Double(
                FuelPlanCalculator.roundedLitersForDisplay(
                    planned.leg.burnLiters
                )
            )
            let calculatedArrival = currentFuel - burn
            let measured = actualArrivalOverridesByLegIndex[index].map {
                floor(max(0, $0) + 0.000_001)
            }
            let actualArrival = measured ?? calculatedArrival
            if currentFuel + 0.000_1 < burn || calculatedArrival < -0.000_1 {
                hasFuelExhaustion = true
            }

            let requiredRefuel: Double
            if refuelAfterLegIndices.contains(index),
               plan.rows.indices.contains(index + 1) {
                requiredRefuel = ceil(max(
                    0,
                    plan.rows[index + 1].minimumDepartureLiters
                        - max(0, actualArrival)
                ) - 0.000_001)
            } else {
                requiredRefuel = 0
            }

            rows.append(FuelActualRow(
                id: planned.id,
                leg: planned.leg,
                actualDepartureLiters: currentFuel,
                actualArrivalLiters: actualArrival,
                requiredRefuelAfterArrivalLiters: requiredRefuel,
                arrivalWasMeasured: measured != nil
            ))
            currentFuel = actualArrival + requiredRefuel
            if currentFuel > capacity + 0.000_1 { hasOverfill = true }
        }

        let finalFuel = rows.last?.actualArrivalLiters ?? currentFuel
        return FuelActualResult(
            rows: rows,
            actualStartingFuelLiters: floor(
                max(0, actualStartingFuelLiters) + 0.000_001
            ),
            finalFuelLiters: finalFuel,
            hasFuelExhaustion: hasFuelExhaustion,
            hasFinalReserveShortfall:
                finalFuel + 0.000_1 < plan.finalReserveLiters,
            hasOverfill: hasOverfill
        )
    }
}

enum FuelPlanCalculator {
    static func refuelCandidateIndices(legs: [FuelPlanLeg]) -> [Int] {
        guard legs.count > 1 else { return [] }
        return Array(legs.indices.dropLast()).filter {
            legs[$0].destinationICAO == legs[$0 + 1].originICAO
        }
    }

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
        calculate(
            legs: legs,
            reserveMinutes: reserveMinutes,
            usableFuelLiters: usableFuelLiters,
            startingFuelLiters: startingFuelLiters,
            refuelsByLegIndex: refuelAfterLegIndex.map { [$0: refuelLiters] } ?? [:]
        )
    }

    static func calculate(
        legs: [FuelPlanLeg],
        reserveMinutes: Int,
        usableFuelLiters: Double,
        startingFuelLiters: Double,
        refuelsByLegIndex: [Int: Double]
    ) -> FuelPlanResult {
        guard !legs.isEmpty else {
            return FuelPlanResult(
                rows: [],
                minimumStartingFuelLiters: 0,
                minimumRefuelLiters: 0,
                minimumRefuelLitersByLegIndex: [:],
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
        let burns = legs.map {
            Double(roundedLitersForDisplay($0.burnLiters))
        }
        let validRefuelIndices = refuelsByLegIndex.keys.filter {
            legs.indices.contains($0) && $0 < legs.count - 1
        }.sorted()
        let additions = validRefuelIndices.reduce(into: [Int: Double]()) {
            $0[$1] = floor(max(0, refuelsByLegIndex[$1] ?? 0) + 0.000_001)
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

        var stageStart = 0
        for refuelIndex in validRefuelIndices {
            fillStage(stageStart...refuelIndex)
            stageStart = refuelIndex + 1
        }
        if stageStart < legs.count {
            fillStage(stageStart...(legs.count - 1))
        }

        let minimumStart = minimumDepartures[0]

        var plannedFuel = startFuel
        var rows: [FuelPlanRow] = []
        var minimumRefuels: [Int: Double] = [:]
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
            let addition = additions[index] ?? 0
            if validRefuelIndices.contains(index) {
                minimumRefuels[index] = max(
                    0,
                    minimumDepartures[index + 1] - max(0, arrival)
                )
            }
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
            if validRefuelIndices.contains(index) {
                stageBurn = 0
            }
        }

        let hasCapacityViolation = minimumDepartures.contains {
            $0 > capacity + 0.000_1
        }
        let hasStartingFuelShortfall = startFuel + 0.000_1 < minimumStart
        let hasRefuelShortfall = validRefuelIndices.contains { index in
            (additions[index] ?? 0) + 0.000_1 < (minimumRefuels[index] ?? 0)
        }
        let finalArrival = rows.last?.plannedArrivalLiters ?? 0
        let hasFinalReserveShortfall =
            finalArrival + 0.000_1 < finalReserve

        return FuelPlanResult(
            rows: rows,
            minimumStartingFuelLiters: minimumStart,
            minimumRefuelLiters: validRefuelIndices.first.flatMap {
                minimumRefuels[$0]
            } ?? 0,
            minimumRefuelLitersByLegIndex: minimumRefuels,
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
