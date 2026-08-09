import Foundation

enum CharterFuelStatus: Equatable {
    case standard
    case sufficient
    case warning
    case critical
}

enum CharterMath {
    static func commercialDecimalHours(minutes: Int) -> Double {
        ceil(Double(max(0, minutes)) / 6.0) / 10.0
    }

    static func commercialCost(minutes: Int, hourlyRateEUR: Double) -> Double {
        commercialDecimalHours(minutes: minutes) * max(0, hourlyRateEUR)
    }

    static func combinedTotalCost(
        charterCostEUR: Double,
        landingFeesEUR: Double,
        includeLandingFees: Bool
    ) -> Double {
        max(0, charterCostEUR)
            + (includeLandingFees ? max(0, landingFeesEUR) : 0)
    }

    /// Commercial block time is rounded for every flight separately. Adding
    /// raw minutes first can otherwise make 1.3 h + 1.2 h appear as 2.4 h and
    /// disagree with both the two displayed rows and their charter cost.
    static func commercialTotalDecimalHours(legMinutes: [Int]) -> Double {
        legMinutes.reduce(0) {
            $0 + commercialDecimalHours(minutes: $1)
        }
    }

    static func commercialEquivalentMinutes(legMinutes: [Int]) -> Int {
        Int(round(commercialTotalDecimalHours(legMinutes: legMinutes) * 60))
    }

    static func requiredReserveLiters(
        outboundConsumptionPerHour: Double,
        returnConsumptionPerHour: Double?,
        reserveMinutes: Int,
        outboundReserveIsReused: Bool
    ) -> Double {
        let hours = Double(max(0, reserveMinutes)) / 60
        let outbound = max(0, outboundConsumptionPerHour) * hours
        guard let returnConsumptionPerHour else { return outbound }
        let inbound = max(0, returnConsumptionPerHour) * hours
        return outboundReserveIsReused
            ? max(outbound, inbound)
            : outbound + inbound
    }

    static func suggestedRefuelLiters(
        startingFuelLiters: Double,
        firstLegBlockFuelLiters: Double,
        firstLegRequiredFuelLiters: Double,
        secondLegRequiredFuelLiters: Double,
        remainingFirstLegFuelIsAvailable: Bool
    ) -> Double {
        let firstLegFuelDeduction = remainingFirstLegFuelIsAvailable
            ? firstLegBlockFuelLiters
            : firstLegRequiredFuelLiters
        let remainingAfterFirstLeg = max(
            0,
            startingFuelLiters - firstLegFuelDeduction
        )
        return max(0, secondLegRequiredFuelLiters - remainingAfterFirstLeg)
    }

    static func fuelStatus(
        totalRequiredFuelLiters: Double,
        usableFuelLiters: Double,
        startingFuelLiters: Double,
        estimatedFuelAtTripEndWithoutRefuelLiters: Double,
        refuelEnabled: Bool,
        refuelLiters: Double,
        minimumRequiredRefuelLiters: Double,
        estimatedFuelAtTripEndLiters: Double
    ) -> CharterFuelStatus {
        guard usableFuelLiters > 0 else {
            return totalRequiredFuelLiters > 0 ? .critical : .standard
        }
        if refuelEnabled {
            if refuelLiters + 0.0001 < minimumRequiredRefuelLiters
                || estimatedFuelAtTripEndLiters < -0.0001
            {
                return .critical
            }
            if estimatedFuelAtTripEndLiters <= usableFuelLiters * 0.10 {
                return .warning
            }
            return .sufficient
        }
        guard startingFuelLiters + 0.0001 >= totalRequiredFuelLiters else {
            return .critical
        }
        if estimatedFuelAtTripEndWithoutRefuelLiters
            <= usableFuelLiters * 0.10
        {
            return .warning
        }
        return .sufficient
    }

    static func refuelLoss(
        grossPricePerLiter: Double?,
        homeReferencePerLiter: Double?,
        liters: Double,
        destinationVATPercent: Double?,
        isForeign: Bool
    ) -> Double? {
        guard let grossPricePerLiter, let homeReferencePerLiter else {
            return nil
        }
        guard !isForeign || destinationVATPercent != nil else { return nil }
        let reimbursablePerLiter = isForeign
            ? min(
                grossPricePerLiter / (1 + max(0, destinationVATPercent ?? 0) / 100),
                homeReferencePerLiter
            )
            : min(grossPricePerLiter, homeReferencePerLiter)
        return max(
            0,
            (grossPricePerLiter - reimbursablePerLiter) * max(0, liters)
        )
    }
}
