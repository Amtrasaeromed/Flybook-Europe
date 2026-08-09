import SwiftUI

enum FlybookColor {
    static let navy = Color(red: 0.03, green: 0.18, blue: 0.34)
    static let blue = Color(red: 0.29, green: 0.57, blue: 0.85)
    static let muted = Color(red: 0.40, green: 0.47, blue: 0.53)
    static let line = Color(red: 0.84, green: 0.87, blue: 0.89)
    static let background = Color(red: 0.985, green: 0.985, blue: 0.975)
}

extension RunwayCrosswindWarning {
    var recommendationBackgroundColor: Color {
        switch self {
        case .none: return Color.green.opacity(0.24)
        case .yellow: return Color.orange.opacity(0.32)
        case .red: return Color.red.opacity(0.38)
        }
    }
}

enum FlightPlanningWindLevel: Equatable {
    case normal
    case yellow
    case red
}

enum FlightPlanningWeatherStyle {
    static func windLevel(
        steadyWindKnots: Double?
    ) -> FlightPlanningWindLevel {
        guard let steadyWindKnots else { return .normal }
        if steadyWindKnots >= 20 { return .red }
        if steadyWindKnots >= 15 { return .yellow }
        return .normal
    }

    static func windBackgroundColor(
        steadyWindKnots: Double?
    ) -> Color {
        switch windLevel(steadyWindKnots: steadyWindKnots) {
        case .normal:
            return Color(red: 0.92, green: 0.97, blue: 1.0)
        case .yellow:
            return Color.yellow.opacity(0.42)
        case .red:
            return Color.red.opacity(0.32)
        }
    }
}

enum DisplayUnitSystem: String, CaseIterable, Identifiable {
    case eu = "EU"
    case us = "US"

    var id: String { rawValue }

    var pickerSymbol: String {
        switch self {
        case .eu: return "🇪🇺"
        case .us: return "🇺🇸"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .eu: return "Europäische Einheiten"
        case .us: return "US-Einheiten"
        }
    }
}

enum UnitSystemSettingsKey {
    static let displaySystem = "flybookDisplayUnitSystem"
}

enum AviationWeatherText {
    static func cloudAndVisibility(
        lowCloudCoverPercent: Double?,
        lowestCloudBaseFeet: Double?,
        visibilityMeters: Double?,
        unitSystem: DisplayUnitSystem
    ) -> String {
        let cloud = cloudAmount(lowCloudCoverPercent)
        let showsCloudBase = (lowCloudCoverPercent ?? 0) >= 12.5
        let base = showsCloudBase
            ? lowestCloudBaseFeet.map {
                "\(Int(($0 / 100).rounded()) * 100)"
            }
            : nil
        let cloudText = base.map { "\(cloud) \($0)" } ?? cloud

        guard let visibilityMeters else {
            return "\(cloudText) / —"
        }

        let visibilityText: String
        switch unitSystem {
        case .eu:
            let kilometers = visibilityMeters / 1000
            if kilometers >= 10 {
                visibilityText = "10km+"
            } else if kilometers >= 1 {
                visibilityText = String(format: "%.0fkm", kilometers)
            } else {
                visibilityText = String(format: "%.1fkm", kilometers)
            }
        case .us:
            let statuteMiles = visibilityMeters / 1609.344
            if statuteMiles >= 10 {
                visibilityText = "10SM+"
            } else {
                visibilityText = String(format: "%.1fSM", statuteMiles)
            }
        }
        return "\(cloudText) / \(visibilityText)"
    }

    private static func cloudAmount(_ percent: Double?) -> String {
        guard let percent else { return "—" }
        switch percent {
        case ..<12.5: return "SKC"
        case ..<37.5: return "FEW"
        case ..<62.5: return "SCT"
        case ..<87.5: return "BKN"
        default: return "OVC"
        }
    }
}

enum RepresentativeDailyWeatherSymbol {
    private enum Kind {
        case clear
        case partlyCloudy
        case overcast
        case fog
        case drizzle
        case rain
        case snow
        case heavyRain
        case thunderstorm
    }

    private struct Sample {
        let score: Double
        let kind: Kind
    }

    static func systemName(
        morningCode: Int?,
        middayCode: Int?,
        eveningCode: Int?,
        fallbackDailyCode: Int?
    ) -> String {
        var samples = [morningCode, middayCode, eveningCode]
            .compactMap { code in
                code.map { sample(for: $0) }
            }
        if samples.isEmpty, let fallbackDailyCode {
            samples = [sample(for: fallbackDailyCode)]
        }
        guard !samples.isEmpty else { return "questionmark.circle" }

        let average = samples.map(\.score).reduce(0, +)
            / Double(samples.count)
        let snowCount = samples.filter { $0.kind == .snow }.count
        let liquidCount = samples.filter {
            $0.kind == .drizzle
                || $0.kind == .rain
                || $0.kind == .heavyRain
        }.count
        let fogCount = samples.filter { $0.kind == .fog }.count

        switch average {
        case ..<0.25:
            return "sun.max.fill"
        case ..<1.5:
            return "cloud.sun.fill"
        case ..<2.5:
            return "cloud.fill"
        case ..<3.5:
            return fogCount >= 2
                ? "cloud.fog.fill"
                : "cloud.drizzle.fill"
        case ..<4.5:
            return snowCount > liquidCount
                ? "cloud.snow.fill"
                : "cloud.rain.fill"
        case ..<5.5:
            return snowCount > liquidCount
                ? "cloud.snow.fill"
                : "cloud.heavyrain.fill"
        default:
            return "cloud.bolt.rain.fill"
        }
    }

    private static func sample(for code: Int) -> Sample {
        switch code {
        case 0:
            return Sample(score: 0, kind: .clear)
        case 1:
            return Sample(score: 0.5, kind: .partlyCloudy)
        case 2:
            return Sample(score: 1, kind: .partlyCloudy)
        case 3:
            return Sample(score: 2, kind: .overcast)
        case 45, 48:
            return Sample(score: 2.75, kind: .fog)
        case 51...57:
            return Sample(score: 3, kind: .drizzle)
        case 61...67:
            return Sample(score: 4, kind: .rain)
        case 71...77, 85, 86:
            return Sample(score: 4, kind: .snow)
        case 80...82:
            return Sample(score: 5, kind: .heavyRain)
        case 95...99:
            return Sample(score: 6, kind: .thunderstorm)
        default:
            return Sample(score: 2, kind: .overcast)
        }
    }
}

struct FlybookCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(FlybookColor.line, lineWidth: 1.5)
            )
    }
}

struct MetricView: View {
    let title: String
    let value: String
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(
                    highlighted ? FlybookColor.blue : FlybookColor.navy
                )

            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(FlybookColor.navy)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DigitalClockView: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))

                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(FlybookColor.navy, lineWidth: 1.5)
                    )
            }

            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(FlybookColor.muted)
        }
        .foregroundStyle(FlybookColor.navy)
    }
}

struct TravelDurationBar: View {
    let minutes: Int
    let thresholdMinutes: Int

    private var safeThreshold: Int {
        max(30, thresholdMinutes)
    }

    private var maximumMinutes: Int {
        safeThreshold * 4
    }

    private var markerFraction: CGFloat {
        max(
            0,
            min(
                1,
                CGFloat(minutes)
                    / CGFloat(maximumMinutes)
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("EMPFOHLENE REISEDAUER")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(FlybookColor.navy)

            GeometryReader { geometry in
                let barHeight: CGFloat = 10
                let barCenterY: CGFloat =
                    barHeight / 2.0

                let markerX = min(
                    max(
                        geometry.size.width
                            * markerFraction,
                        9
                    ),
                    geometry.size.width - 9
                )

                ZStack(alignment: .topLeading) {
                    LinearGradient(
                        colors: [
                            Color(
                                red: 0.74,
                                green: 0.89,
                                blue: 0.98
                            ),
                            FlybookColor.blue,
                            FlybookColor.navy
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: barHeight)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 7)
                    )

                    ForEach(1...3, id: \.self) {
                        boundary in
                        Rectangle()
                            .fill(FlybookColor.line)
                            .frame(
                                width: 1,
                                height: 22
                            )
                            .offset(
                                x: geometry.size.width
                                    * CGFloat(boundary)
                                    / 4.0,
                                y: barHeight
                            )
                    }

                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: 6
                            )
                            .stroke(
                                FlybookColor.navy,
                                lineWidth: 2
                            )
                        )
                        .frame(width: 16, height: 23)
                        .position(
                            x: markerX,
                            y: barCenterY
                        )
                }
            }
            .frame(height: 30)

            HStack(spacing: 0) {
                Text("Tagestrip")
                Spacer()
                Text("1 Übernachtung")
                Spacer()
                Text("2 Übernachtungen")
                Spacer()
                Text("3 Übernachtungen")
            }
            .font(.system(size: 10))
            .foregroundStyle(FlybookColor.navy)
        }
        .help(
            "Grenzen: "
            + "\(FlightMath.duration(safeThreshold)), "
            + "\(FlightMath.duration(safeThreshold * 2)), "
            + "\(FlightMath.duration(safeThreshold * 3))"
        )
    }
}

enum ETOPSBand {
    static func color(
        for travelMinutes: Int,
        greenYellowMinutes: Int,
        orangeRedMinutes: Int
    ) -> Color {
        ETOPSScale.color(
            for: travelMinutes,
            greenYellow: greenYellowMinutes,
            orangeRed: orangeRedMinutes
        )
    }
}

struct ETOPSBar: View {
    @AppStorage(ETOPSSettingsKey.greenYellowMinutes)
    private var greenYellowMinutes = ETOPSScale.defaultGreenYellowMinutes

    @AppStorage(ETOPSSettingsKey.orangeRedMinutes)
    private var orangeRedMinutes = ETOPSScale.defaultOrangeRedMinutes

    let nonstopMinutes: Int
    let oneStopPerLegMinutes: Int
    let twoStopPerLegMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ETOPS PIPI")
                .font(.title3.bold())
                .foregroundStyle(FlybookColor.navy)

            GeometryReader { geometry in
                let barY: CGFloat = 28

                ZStack(alignment: .topLeading) {
                    let limits = ETOPSScale.normalized(
                        greenYellow: greenYellowMinutes,
                        orangeRed: orangeRedMinutes
                    )

                    HStack(spacing: 0) {
                        Color.green
                            .frame(
                                width: geometry.size.width
                                    * CGFloat(limits.greenYellow)
                                    / CGFloat(limits.maximum)
                            )

                        Color.yellow
                            .frame(
                                width: geometry.size.width
                                    * CGFloat(limits.yellowOrange - limits.greenYellow)
                                    / CGFloat(limits.maximum)
                            )

                        Color.orange
                            .frame(
                                width: geometry.size.width
                                    * CGFloat(limits.orangeRed - limits.yellowOrange)
                                    / CGFloat(limits.maximum)
                            )

                        Color.red
                    }
                    .frame(height: 20)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 7)
                    )
                    .offset(y: barY - 10)

                    ETOPSMarker(
                        label: "2 STOPS",
                        minutes: twoStopPerLegMinutes,
                        width: geometry.size.width,
                        barCenterY: barY,
                        maximumMinutes: limits.maximum,
                        labelOffsetY: 43
                    )

                    ETOPSMarker(
                        label: "1 STOP",
                        minutes: oneStopPerLegMinutes,
                        width: geometry.size.width,
                        barCenterY: barY,
                        maximumMinutes: limits.maximum,
                        labelOffsetY: 43
                    )

                    ETOPSMarker(
                        label: "NON-STOP",
                        minutes: nonstopMinutes,
                        width: geometry.size.width,
                        barCenterY: barY,
                        maximumMinutes: limits.maximum,
                        labelOffsetY: 43
                    )
                }
            }
            .frame(height: 102)
        }
    }
}

private struct ETOPSMarker: View {
    let label: String
    let minutes: Int
    let width: CGFloat
    let barCenterY: CGFloat
    let maximumMinutes: Int
    let labelOffsetY: CGFloat

    private var markerX: CGFloat {
        let raw = width * CGFloat(minutes) / CGFloat(max(maximumMinutes, 1))
        return min(max(raw, 9), width - 9)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(FlybookColor.navy, lineWidth: 2))
                .frame(width: 18, height: 36)
                .position(x: markerX, y: barCenterY)

            VStack(spacing: 1) {
                Text(FlightMath.duration(minutes)).font(.system(size: 13, weight: .bold))
                Text(label).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(FlybookColor.navy)
            .frame(width: 88)
            .position(
                x: markerX,
                y: barCenterY + labelOffsetY
            )
        }
    }
}
