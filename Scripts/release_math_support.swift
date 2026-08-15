enum RunwayCrosswindWarning: Int, Comparable {
    case none = 0
    case yellow = 1
    case red = 2

    static func < (
        lhs: RunwayCrosswindWarning,
        rhs: RunwayCrosswindWarning
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
