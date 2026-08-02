import Foundation

enum CharterMath {
    static func commercialDecimalHours(minutes: Int) -> Double {
        ceil(Double(max(0, minutes)) / 6.0) / 10.0
    }

    static func refuelLoss(
        grossPricePerLiter: Double?,
        homeReferencePerLiter: Double?,
        liters: Double,
        destinationVATPercent: Double,
        isForeign: Bool
    ) -> Double? {
        guard let grossPricePerLiter, let homeReferencePerLiter else {
            return nil
        }
        let reimbursablePerLiter = isForeign
            ? min(
                grossPricePerLiter / (1 + max(0, destinationVATPercent) / 100),
                homeReferencePerLiter
            )
            : min(grossPricePerLiter, homeReferencePerLiter)
        return max(
            0,
            (grossPricePerLiter - reimbursablePerLiter) * max(0, liters)
        )
    }
}
