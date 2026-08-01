import SwiftUI

private struct AlternateAirport: Identifiable {
    var id: String { reference.icao }
    let reference: AirportReference
    let runwayA: Int
    let runwayB: Int
    let runwayLengthMeters: Int

    var runwayDescription: String {
        String(format: "%02d/%02d", runwayA / 10, runwayB / 10)
            + " · \(runwayLengthMeters) m"
    }
}

private extension AlternateAirport {
    static let airports: [AlternateAirport] = [
        AlternateAirport(
            reference: .edfz,
            runwayA: 70,
            runwayB: 250,
            runwayLengthMeters: 1000
        ),
        AlternateAirport(
            reference: AirportReference(
                icao: "EDFE",
                name: "Frankfurt-Egelsbach",
                latitude: 49.9608,
                longitude: 8.6436,
                elevationFeet: 385,
                timeZone: TimeZone(identifier: "Europe/Berlin")!
            ),
            runwayA: 80,
            runwayB: 260,
            runwayLengthMeters: 1400
        ),
        AlternateAirport(
            reference: AirportReference(
                icao: "EDFM",
                name: "Mannheim City",
                latitude: 49.4727,
                longitude: 8.5143,
                elevationFeet: 309,
                timeZone: TimeZone(identifier: "Europe/Berlin")!
            ),
            runwayA: 90,
            runwayB: 270,
            runwayLengthMeters: 1066
        ),
        AlternateAirport(
            reference: AirportReference(
                icao: "EDRK",
                name: "Koblenz-Winningen",
                latitude: 50.3256,
                longitude: 7.5286,
                elevationFeet: 640,
                timeZone: TimeZone(identifier: "Europe/Berlin")!
            ),
            runwayA: 60,
            runwayB: 240,
            runwayLengthMeters: 1175
        ),
        AlternateAirport(
            reference: AirportReference(
                icao: "EDRY",
                name: "Speyer",
                latitude: 49.3047,
                longitude: 8.4514,
                elevationFeet: 312,
                timeZone: TimeZone(identifier: "Europe/Berlin")!
            ),
            runwayA: 160,
            runwayB: 340,
            runwayLengthMeters: 1000
        )
    ]
}

struct AlternatesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var forecastTime = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ALTERNATES")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)
                    Text("Heimatflugplatz und festgelegte Ausweichflugplätze")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FlybookColor.muted)
                }

                Spacer()

                Button("Schließen") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PROGNOSEZEIT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(FlybookColor.muted)
                    Text(formattedForecastTime)
                        .font(
                            .system(
                                size: 16,
                                weight: .bold,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(FlybookColor.navy)
                    Text("Ortszeit EDFZ")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FlybookColor.muted)
                }
                .frame(width: 185, alignment: .leading)

                ForEach(ForecastOffset.allCases) { offset in
                    Button(offset.title) {
                        forecastTime = Date().addingTimeInterval(
                            TimeInterval(offset.minutes * 60)
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(
                        isSelected(offset)
                            ? FlybookColor.blue
                            : FlybookColor.muted.opacity(0.55)
                    )
                }

                Spacer()
            }

            HStack(alignment: .top, spacing: 10) {
                ForEach(AlternateAirport.airports) { airport in
                    AlternateAirportColumn(
                        airport: airport,
                        forecastTime: forecastTime
                    )
                }
            }
        }
        .padding(22)
        .frame(minWidth: 1180, minHeight: 570)
        .background(FlybookColor.background)
    }

    private var formattedForecastTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = DestinationTimeZone.edfz
        formatter.dateFormat = "EEE, dd.MM.yyyy · HH:mm"
        return formatter.string(from: forecastTime)
    }

    private func isSelected(_ offset: ForecastOffset) -> Bool {
        let difference = forecastTime.timeIntervalSinceNow / 60
        return abs(difference - Double(offset.minutes)) < 2
    }
}

private enum ForecastOffset: Int, CaseIterable, Identifiable {
    case now = 0
    case thirty = 30
    case sixty = 60
    case ninety = 90

    var id: Int { rawValue }
    var minutes: Int { rawValue }

    var title: String {
        switch self {
        case .now: return "Jetzt"
        case .thirty: return "30 Minuten"
        case .sixty: return "60 Minuten"
        case .ninety: return "90 Minuten"
        }
    }
}

private struct AlternateAirportColumn: View {
    let airport: AlternateAirport
    let forecastTime: Date
    @StateObject private var weatherModel = EDFZWeatherViewModel()

    private var sample: EDFZWeatherSample? {
        weatherModel.forecast?.sample(nearestTo: forecastTime)
    }

    private var recommendation: RunwayRecommendation? {
        guard let direction = sample?.windDirectionDegrees,
              let speed = sample?.windSpeedKnots
        else { return nil }
        return RunwayRecommendation.best(
            windFromDegrees: direction,
            speedKnots: speed,
            runwayA: airport.runwayA,
            runwayB: airport.runwayB
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            airportHeader
                .frame(height: 72)

            Divider()

            metricRow(
                title: "PISTE",
                value: airport.runwayDescription
            )
            .frame(height: 66)

            Divider()

            recommendedRunwayRow
                .frame(height: 105)

            Divider()

            AlternateWeatherBlock(
                sample: sample,
                isLoading: weatherModel.isLoading,
                errorMessage: weatherModel.errorMessage
            )
            .frame(height: 205)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(FlybookColor.navy.opacity(0.16), lineWidth: 1)
        )
        .task(id: forecastTime) {
            await weatherModel.load(
                plannedDate: forecastTime,
                airport: airport.reference
            )
        }
    }

    private var airportHeader: some View {
        VStack(spacing: 4) {
            Text(airport.reference.icao)
                .font(.system(size: 19, weight: .bold, design: .monospaced))
                .foregroundStyle(FlybookColor.blue)
            Text(airport.reference.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(FlybookColor.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
    }

    private func metricRow(title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(FlybookColor.navy)
        }
    }

    private var recommendedRunwayRow: some View {
        VStack(spacing: 7) {
            Text("EMPFOHLENE PISTE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FlybookColor.muted)

            Text(recommendation?.runwayLabel ?? "—")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(FlybookColor.navy)

            HStack(spacing: 12) {
                component(
                    symbol: "arrow.down",
                    value: recommendation?.headwindKnots,
                    color: .green,
                    help: "Gegenwindkomponente"
                )
                component(
                    symbol:
                        recommendation?.crosswindSymbol
                        ?? "arrow.left.and.right",
                    value: recommendation?.crosswindKnots,
                    color: .orange,
                    help: "Seitenwindkomponente"
                )
            }
        }
    }

    private func component(
        symbol: String,
        value: Double?,
        color: Color,
        help: String
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(value.map { String(format: "%.0f kt", $0) } ?? "—")
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(color)
        .help(help)
    }
}

private struct RunwayRecommendation {
    let runwayLabel: String
    let headwindKnots: Double
    let crosswindKnots: Double
    let crosswindComesFromRight: Bool

    var crosswindSymbol: String {
        crosswindComesFromRight ? "arrow.left" : "arrow.right"
    }

    static func best(
        windFromDegrees: Double,
        speedKnots: Double,
        runwayA: Int,
        runwayB: Int
    ) -> RunwayRecommendation {
        let candidates = [runwayA, runwayB].map { heading in
            let difference = signedAngularDifference(
                windFromDegrees,
                Double(heading)
            )
            return (
                heading: heading,
                headwind: speedKnots * cos(difference * .pi / 180),
                signedCrosswind:
                    speedKnots * sin(difference * .pi / 180)
            )
        }
        let selected = candidates.max { $0.headwind < $1.headwind }!
        return RunwayRecommendation(
            runwayLabel: String(format: "%02d", selected.heading / 10),
            headwindKnots: max(0, selected.headwind),
            crosswindKnots: abs(selected.signedCrosswind),
            crosswindComesFromRight: selected.signedCrosswind > 0
        )
    }

    private static func signedAngularDifference(
        _ first: Double,
        _ second: Double
    ) -> Double {
        var difference = (first - second)
            .truncatingRemainder(dividingBy: 360)
        if difference > 180 { difference -= 360 }
        if difference < -180 { difference += 360 }
        return difference
    }
}

private struct AlternateWeatherBlock: View {
    let sample: EDFZWeatherSample?
    let isLoading: Bool
    let errorMessage: String?
    @AppStorage(UnitSystemSettingsKey.displaySystem)
    private var displayUnitSystemRaw = DisplayUnitSystem.eu.rawValue

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let sample {
                VStack(spacing: 12) {
                    weatherRow(
                        title: "WIND",
                        value: windText(sample)
                    )
                    weatherRow(
                        title: "WOLKEN / SICHT",
                        value: cloudVisibilityText(sample)
                    )
                    categoryBadge(sample.category)
                }
                .padding(12)
            } else {
                Text(errorMessage ?? "Wetter nicht verfügbar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FlybookColor.muted)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.07))
    }

    private func weatherRow(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(FlybookColor.navy)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private func categoryBadge(_ category: FlightCategory) -> some View {
        Text(category.rawValue)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(categoryColor(category))
            .clipShape(Capsule())
    }

    private func windText(_ sample: EDFZWeatherSample) -> String {
        guard let direction = sample.windDirectionDegrees,
              let speed = sample.windSpeedKnots
        else { return "--- / --" }
        var roundedDirection =
            (Int((direction / 10).rounded()) * 10) % 360
        if roundedDirection == 0 && direction > 0 {
            roundedDirection = 360
        }
        var result = String(
            format: "%03d / %02d",
            roundedDirection,
            max(0, Int(speed.rounded()))
        )
        if let gust = sample.windGustKnots, gust - speed >= 10 {
            result += String(format: " G%02d", max(0, Int(gust.rounded())))
        }
        return result
    }

    private func cloudVisibilityText(_ sample: EDFZWeatherSample) -> String {
        AviationWeatherText.cloudAndVisibility(
            lowCloudCoverPercent: sample.lowCloudCoverPercent,
            lowestCloudBaseFeet: sample.lowestCloudBaseFeetAGL,
            visibilityMeters: sample.visibilityMeters,
            unitSystem:
                DisplayUnitSystem(rawValue: displayUnitSystemRaw) ?? .eu
        )
    }

    private func categoryColor(_ category: FlightCategory) -> Color {
        switch category {
        case .vfr: return .green
        case .mvfr: return .blue
        case .ifr: return .red
        case .lifr: return .purple
        case .unavailable: return .gray
        }
    }
}
