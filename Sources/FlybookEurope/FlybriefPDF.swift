import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FlybriefSnapshot {
    let title: String
    let route: String
    let flightDate: Date
    let timeBasis: String
    let planningMode: String
    let aircraft: String
    let base: String
    let legs: [FlybriefLegSnapshot]
    let createdAt: Date

    var suggestedFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = DestinationTimeZone.edfz
        formatter.dateFormat = "ddMMMyy"
        return "Flybrief \(formatter.string(from: flightDate).uppercased()) \(route).pdf"
    }
}

struct FlybriefLegSnapshot: Identifiable {
    let id: String
    let title: String
    let dateText: String
    let routeText: String
    let stopsText: String?
    let travelTimeText: String
    let blockTimeText: String
    let trackText: String
    let altitudeText: String
    let bestLevelText: String
    let routeWindText: String
    let routeWindDetail: String
    let etopsText: String
    let etopsLevel: FlybriefAlertLevel
    let routeWeather: [FlybriefRouteWeatherPoint]
    let routeWeatherSummary: String
    let departure: FlybriefEndpointSnapshot
    let arrival: FlybriefEndpointSnapshot
}

struct FlybriefEndpointSnapshot {
    let role: String
    let icao: String
    let name: String
    let timeText: String
    let operatingStatus: String
    let operatingLevel: FlybriefAlertLevel
    let referenceRunway: String
    let activeRunway: String
    let weather: FlybriefWeatherSnapshot
    let runwayWind: FlybriefRunwayWindSnapshot?
    let sunText: String
}

struct FlybriefWeatherSnapshot {
    let category: String
    let categoryLevel: FlybriefAlertLevel
    let condition: String
    let temperatureText: String
    let cloudVisibilityText: String
    let pressureText: String
    let densityAltitudeText: String
    let windText: String
    let validTimeText: String
    let warningText: String?
}

struct FlybriefRunwayWindSnapshot {
    let windDirectionDegrees: Double
    let headwindKnots: Double
    let crosswindKnots: Double
    let gustCrosswindKnots: Double?
    let crosswindComesFromRight: Bool
    let warningLevel: FlybriefAlertLevel
}

struct FlybriefRouteWeatherPoint: Identifiable {
    let id: Int
    let level: FlybriefAlertLevel
}

enum FlybriefAlertLevel {
    case neutral
    case good
    case info
    case warning
    case danger
    case severe

    var color: Color {
        switch self {
        case .neutral: return Color.gray
        case .good: return Color.green
        case .info: return FlybookColor.blue
        case .warning: return Color.orange
        case .danger: return Color.red
        case .severe: return Color.purple
        }
    }

    var paleColor: Color {
        color.opacity(self == .neutral ? 0.10 : 0.13)
    }
}

@MainActor
enum FlybriefPDFExporter {
    static let pageSize = CGSize(width: 841.89, height: 595.28)

    static func export(_ snapshot: FlybriefSnapshot) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Flybrief als PDF sichern"
        panel.prompt = "Flybrief sichern"
        panel.nameFieldStringValue = snapshot.suggestedFilename
        panel.allowedContentTypes = [.pdf]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let data = pdfData(for: snapshot)
        try data.write(to: url, options: .atomic)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return url
    }

    static func pdfData(for snapshot: FlybriefSnapshot) -> Data {
        let root = FlybriefPDFPage(snapshot: snapshot)
            .frame(width: pageSize.width, height: pageSize.height)
            .background(Color.white)
        let renderer = ImageRenderer(content: root)
        renderer.proposedSize = ProposedViewSize(
            width: pageSize.width,
            height: pageSize.height
        )
        renderer.scale = 1
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(
                consumer: consumer,
                mediaBox: &mediaBox,
                nil
              )
        else { return Data() }

        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
        return data as Data
    }
}

private struct FlybriefPDFPage: View {
    let snapshot: FlybriefSnapshot

    var body: some View {
        VStack(spacing: 8) {
            header

            VStack(spacing: 8) {
                ForEach(snapshot.legs) { leg in
                    FlybriefLegCard(leg: leg)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            footer
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .foregroundStyle(FlybookColor.navy)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title.uppercased())
                    .font(.system(size: 19, weight: .black))
                Text(snapshot.route)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }

            Spacer()

            HStack(spacing: 16) {
                headerValue("MODUS", snapshot.planningMode)
                headerValue("ZEITEN", snapshot.timeBasis)
                headerValue("FLUGZEUG", snapshot.aircraft)
                headerValue("BASIS", snapshot.base)
            }
        }
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FlybookColor.navy).frame(height: 2)
        }
    }

    private func headerValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
            Text(value)
                .font(.system(size: 9, weight: .bold))
                .lineLimit(1)
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            Text("Planungshilfe - vor dem Flug AIP, NOTAM, Wetterbriefing, Masse/Schwerpunkt und Kraftstoff prüfen.")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(FlybookColor.muted)
            Spacer()
            Text("Erstellt: " + Self.timestamp(snapshot.createdAt))
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
        }
        .padding(.top, 5)
        .overlay(alignment: .top) {
            Rectangle().fill(FlybookColor.line).frame(height: 1)
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = DestinationTimeZone.edfz
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss zzz"
        return formatter.string(from: date)
    }
}

private struct FlybriefLegCard: View {
    let leg: FlybriefLegSnapshot

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(leg.title.uppercased())
                        .font(.system(size: 11, weight: .black))
                    Text("\(leg.dateText)  \(leg.routeText)")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                }

                if let stopsText = leg.stopsText {
                    Text(stopsText)
                        .font(.system(size: 7.5, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(FlybookColor.blue.opacity(0.12)))
                }

                Spacer()

                RouteWeatherStrip(
                    points: leg.routeWeather,
                    summary: leg.routeWeatherSummary
                )
            }

            HStack(alignment: .top, spacing: 8) {
                FlybriefEndpointCard(endpoint: leg.departure)
                routeMetrics
                    .frame(width: 182)
                FlybriefEndpointCard(endpoint: leg.arrival)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(FlybookColor.blue.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(FlybookColor.navy.opacity(0.28), lineWidth: 1.2)
        )
    }

    private var routeMetrics: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                metric("REISE", leg.travelTimeText)
                metric("BLOCK", leg.blockTimeText)
            }
            HStack(spacing: 5) {
                metric("TRACK", leg.trackText)
                metric("HÖHE", leg.altitudeText)
            }
            HStack(spacing: 5) {
                metric("BEST LEVEL", leg.bestLevelText)
                metric("ETOPS-PIPI", leg.etopsText, level: leg.etopsLevel)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("STRECKENWIND")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
                Text(leg.routeWindText)
                    .font(.system(size: 10, weight: .black))
                Text(leg.routeWindDetail)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(FlybookColor.muted)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white)
            )
        }
    }

    private func metric(
        _ label: String,
        _ value: String,
        level: FlybriefAlertLevel = .neutral
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
            Text(value)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .padding(.horizontal, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(level == .neutral ? Color.white : level.paleColor)
        )
    }
}

private struct RouteWeatherStrip: View {
    let points: [FlybriefRouteWeatherPoint]
    let summary: String

    var body: some View {
        HStack(spacing: 5) {
            Text("STRECKENWETTER")
                .font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
            HStack(spacing: 3) {
                ForEach(points) { point in
                    Circle()
                        .fill(point.level.color)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.white, lineWidth: 0.7))
                }
            }
            Text(summary)
                .font(.system(size: 7, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: 190, alignment: .leading)
        }
    }
}

private struct FlybriefEndpointCard: View {
    let endpoint: FlybriefEndpointSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 5) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(endpoint.role.uppercased())
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(FlybookColor.muted)
                    Text(endpoint.icao + " · " + endpoint.name)
                        .font(.system(size: 10, weight: .black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 2)
                Text(endpoint.timeText)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
            }

            HStack(spacing: 5) {
                statusPill(endpoint.operatingStatus, level: endpoint.operatingLevel)
                statusPill(endpoint.weather.category, level: endpoint.weather.categoryLevel)
                if !endpoint.activeRunway.isEmpty {
                    statusPill("RWY " + endpoint.activeRunway, level: endpoint.runwayWind?.warningLevel ?? .neutral)
                }
            }

            HStack(alignment: .center, spacing: 6) {
                if let runwayWind = endpoint.runwayWind {
                    RunwayWindGeometryView(
                        runway: endpoint.referenceRunway,
                        windDirection: runwayWind.windDirectionDegrees,
                        activeRunway: endpoint.activeRunway,
                        emphasizesActiveRunway: true
                    )
                    .scaleEffect(0.66)
                    .frame(width: 86, height: 75)
                    .clipped()
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "road.lanes")
                            .font(.system(size: 20, weight: .bold))
                        Text(endpoint.referenceRunway.isEmpty ? "RWY -" : "RWY " + endpoint.referenceRunway)
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(FlybookColor.muted)
                    .frame(width: 86, height: 75)
                }

                VStack(alignment: .leading, spacing: 3) {
                    weatherLine(endpoint.weather.condition + "  " + endpoint.weather.temperatureText, bold: true)
                    weatherLine(endpoint.weather.cloudVisibilityText, bold: true)
                    weatherLine(endpoint.weather.windText)
                    weatherLine(endpoint.weather.pressureText + "  " + endpoint.weather.densityAltitudeText)
                    if let runwayWind = endpoint.runwayWind {
                        weatherLine(headwindText(runwayWind), bold: true)
                        weatherLine(crosswindText(runwayWind), bold: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(endpoint.sunText)
                .font(.system(size: 6.7, weight: .semibold, design: .monospaced))
                .foregroundStyle(FlybookColor.muted)
                .lineLimit(1)

            HStack {
                Text(endpoint.weather.validTimeText)
                    .font(.system(size: 6.5, weight: .semibold))
                    .foregroundStyle(FlybookColor.muted)
                Spacer()
                if let warning = endpoint.weather.warningText {
                    Text(warning)
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(Color.red)
                        .lineLimit(1)
                }
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(FlybookColor.line, lineWidth: 1)
        )
    }

    private func statusPill(
        _ text: String,
        level: FlybriefAlertLevel
    ) -> some View {
        HStack(spacing: 3) {
            Circle().fill(level.color).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 6.5, weight: .bold))
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(level.paleColor))
    }

    private func weatherLine(_ text: String, bold: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 7.5, weight: bold ? .bold : .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func headwindText(_ wind: FlybriefRunwayWindSnapshot) -> String {
        let label = wind.headwindKnots >= 0 ? "Gegenwind" : "Rückenwind"
        return "\(label) \(Int(abs(wind.headwindKnots).rounded())) kt"
    }

    private func crosswindText(_ wind: FlybriefRunwayWindSnapshot) -> String {
        let side = wind.crosswindComesFromRight ? "rechts" : "links"
        let steady = Int(wind.crosswindKnots.rounded())
        if let gust = wind.gustCrosswindKnots,
           Int(gust.rounded()) > steady {
            return "Seitenwind \(side) \(steady) G\(Int(gust.rounded())) kt"
        }
        return "Seitenwind \(side) \(steady) kt"
    }
}
