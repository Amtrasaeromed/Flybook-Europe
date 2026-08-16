import AppKit
import PDFKit
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
    let fuelPlan: FuelPlanConfirmation?
    let createdAt: Date

    var suggestedFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = DestinationTimeZone.edfz
        formatter.dateFormat = "ddMMMyy"
        return "Flybrief \(formatter.string(from: flightDate).uppercased()) \(route).pdf"
    }
}

struct FlybriefPreviewDocument: Identifiable {
    let id = UUID()
    let snapshot: FlybriefSnapshot
    let data: Data
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
    let altitudeWindsText: String
    let departure: FlybriefEndpointSnapshot
    let arrival: FlybriefEndpointSnapshot
    let segments: [FlybriefSegmentSnapshot]
    let alternates: [FlybriefAlternateSnapshot]
}

struct FlybriefSegmentSnapshot: Identifiable {
    let id: String
    let title: String
    let routeText: String
    let blockTimeText: String
    let trackText: String
    let routeWindText: String
    let routeWindDetail: String
    let routeWeather: [FlybriefRouteWeatherPoint]
    let routeWeatherSummary: String
    let altitudeWindsText: String
    let departure: FlybriefEndpointSnapshot
    let arrival: FlybriefEndpointSnapshot
}

struct FlybriefEndpointSnapshot {
    let role: String
    let icao: String
    let name: String
    let openingHoursText: String?
    let timeText: String
    let operatingStatus: String
    let operatingLevel: FlybriefAlertLevel
    let referenceRunway: String
    let activeRunway: String
    let runwayPerformance: FlybriefRunwayPerformanceSnapshot?
    let weather: FlybriefWeatherSnapshot
    let runwayWind: FlybriefRunwayWindSnapshot?
    let sunText: String
}

struct FlybriefRunwayPerformanceSnapshot {
    let label: String
    let rollMeters: Int
    let rollPercentage: Int?
    let over50FeetMeters: Int
    let over50FeetPercentage: Int?
    let weightKilograms: Int
}

struct FlybriefSegmentWeight: Equatable {
    let takeoffKilograms: Double
    let landingKilograms: Double
}

enum FlybriefWeightMath {
    static func progression(
        initialTakeoffKilograms: Double,
        flightMinutes: [Int],
        consumptionLitersPerHour: Double,
        fuelDensityKilogramsPerLiter: Double,
        refuelLitersAfterSegment: [Double] = []
    ) -> [FlybriefSegmentWeight] {
        var takeoff = max(1, initialTakeoffKilograms)
        return flightMinutes.enumerated().map { index, minutes in
            let burnedLiters = CharterMath.actualFuelBurnLiters(
                minutes: minutes,
                consumptionLitersPerHour: consumptionLitersPerHour
            )
            let landing = max(
                1,
                takeoff - burnedLiters * max(0, fuelDensityKilogramsPerLiter)
            )
            let result = FlybriefSegmentWeight(
                takeoffKilograms: takeoff,
                landingKilograms: landing
            )
            let refuel = refuelLitersAfterSegment.indices.contains(index)
                ? max(0, refuelLitersAfterSegment[index])
                : 0
            takeoff = landing + refuel * max(0, fuelDensityKilogramsPerLiter)
            return result
        }
    }
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

struct FlybriefAlternateSnapshot: Identifiable {
    var id: String { icao }
    let icao: String
    let name: String
    let distanceNM: Double
    let flightTimeText: String
    let fuelLiters: Int
    let runwayLengthMeters: Int
    let surface: String
    let runwayDirection: String
    let preferredRunway: String?
    let weatherText: String
    let weatherCategory: String
    let weatherCondition: String
    let weatherCloudVisibility: String
    let weatherWind: String
    let weatherLevel: FlybriefAlertLevel
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
    static let pageSize = CGSize(width: 595.28, height: 841.89)

    static func export(_ snapshot: FlybriefSnapshot) throws -> URL? {
        try save(
            pdfData(for: snapshot),
            suggestedFilename: snapshot.suggestedFilename
        )
    }

    static func save(
        _ data: Data,
        suggestedFilename: String
    ) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Flybrief als PDF sichern"
        panel.prompt = "Flybrief sichern"
        panel.nameFieldStringValue = suggestedFilename
        panel.allowedContentTypes = [.pdf]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        try data.write(to: url, options: .atomic)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return url
    }

    static func pdfData(for snapshot: FlybriefSnapshot) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(
                consumer: consumer,
                mediaBox: &mediaBox,
                nil
              )
        else { return Data() }

        let pageGroups = pageLegGroups(for: snapshot)
        let pageCount = pageGroups.count + (snapshot.fuelPlan == nil ? 0 : 1)
        for (index, legs) in pageGroups.enumerated() {
            let root = FlybriefPDFPage(
                snapshot: snapshot,
                legs: legs,
                pageNumber: index + 1,
                pageCount: pageCount
            )
            .frame(width: pageSize.width, height: pageSize.height)
            .background(Color.white)
            let renderer = ImageRenderer(content: root)
            renderer.proposedSize = ProposedViewSize(
                width: pageSize.width,
                height: pageSize.height
            )
            renderer.scale = 1
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        if let fuelPlan = snapshot.fuelPlan {
            let root = FlybriefFuelPlanPDFPage(
                snapshot: snapshot,
                fuelPlan: fuelPlan,
                pageNumber: pageCount,
                pageCount: pageCount
            )
            .frame(width: pageSize.width, height: pageSize.height)
            .background(Color.white)
            let renderer = ImageRenderer(content: root)
            renderer.proposedSize = ProposedViewSize(
                width: pageSize.width,
                height: pageSize.height
            )
            renderer.scale = 1
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }

    static func pageLegGroups(
        for snapshot: FlybriefSnapshot
    ) -> [[FlybriefLegSnapshot]] {
        let totalRouteLegs = snapshot.legs.reduce(0) { partial, leg in
            partial + max(1, leg.segments.count)
        }
        if snapshot.planningMode == FlightPlanningMode.multiStop.rawValue,
           totalRouteLegs <= 4,
           snapshot.legs.allSatisfy(\.alternates.isEmpty) {
            return snapshot.legs.isEmpty ? [] : [snapshot.legs]
        }
        return snapshot.legs.map { [$0] }
    }
}

struct FlybriefPDFPreview: View {
    let document: FlybriefPreviewDocument
    let onSaveError: (Error) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FLYBRIEF-VORSCHAU")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)
                    Text(document.snapshot.route)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(FlybookColor.muted)
                }

                Spacer()

                Button("Zurück") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    savePDF()
                } label: {
                    Label("Als PDF speichern", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(FlybookColor.navy)
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            FlybriefPDFKitView(data: document.data)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 650, idealHeight: 900)
    }

    private func savePDF() {
        do {
            if try FlybriefPDFExporter.save(
                document.data,
                suggestedFilename: document.snapshot.suggestedFilename
            ) != nil {
                dismiss()
            }
        } catch {
            onSaveError(error)
        }
    }
}

private struct FlybriefPDFKitView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard view.document?.dataRepresentation() != data else { return }
        view.document = PDFDocument(data: data)
        view.autoScales = true
    }
}

private struct FlybriefPDFPage: View {
    let snapshot: FlybriefSnapshot
    let legs: [FlybriefLegSnapshot]
    let pageNumber: Int
    let pageCount: Int

    var body: some View {
        VStack(spacing: 10) {
            header

            VStack(spacing: 8) {
                ForEach(legs) { leg in
                    FlybriefLegCard(
                        leg: leg,
                        sharesPage: legs.count > 1
                    )
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            footer
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .foregroundStyle(FlybookColor.navy)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(snapshot.title.uppercased())
                    .font(.system(size: 22, weight: .black))
                Text(snapshot.route)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                Spacer()
                Text(Self.date(snapshot.flightDate))
                    .font(.system(size: 10, weight: .black, design: .monospaced))
            }

            HStack(spacing: 0) {
                headerValue("MODUS", snapshot.planningMode)
                Spacer()
                headerValue("ZEITEN", snapshot.timeBasis)
                Spacer()
                headerValue("FLUGZEUG", snapshot.aircraft)
                Spacer()
                headerValue("BASIS", snapshot.base)
            }
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FlybookColor.navy).frame(height: 2)
        }
    }

    private func headerValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
            Text(value)
                .font(.system(size: 9.5, weight: .bold))
                .lineLimit(1)
        }
    }

    private static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = DestinationTimeZone.edfz
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            Text("Planungshilfe - vor dem Flug AIP, NOTAM, Wetterbriefing, Masse/Schwerpunkt und Kraftstoff prüfen.")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(FlybookColor.muted)
            Spacer()
            Text("Seite \(pageNumber)/\(pageCount)")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .padding(.trailing, 12)
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

private struct FlybriefFuelPlanPDFPage: View {
    let snapshot: FlybriefSnapshot
    let fuelPlan: FuelPlanConfirmation
    let pageNumber: Int
    let pageCount: Int

    var body: some View {
        VStack(spacing: 9) {
            header
            summary
            fuelTable
            status
            releaseNotes
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .foregroundStyle(FlybookColor.navy)
        .background(Color.white)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("FLYBOOK DISPATCH")
                        .font(.system(size: 7, weight: .black))
                        .tracking(1.3)
                    Text("FUELPLAN / OPERATIONAL RELEASE")
                        .font(.system(size: 18, weight: .black))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(snapshot.route)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                    Text("RELEASED " + timestamp(fuelPlan.confirmedAt))
                        .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                }
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(FlybookColor.navy)

            HStack(spacing: 0) {
                headerValue("FLUGZEUG", fuelPlan.aircraftName)
                Spacer()
                headerValue("ROUTE", snapshot.route)
                Spacer()
                headerValue("RESERVE POLICY", "\(fuelPlan.reserveMinutes) MIN")
                Spacer()
                headerValue("TIME BASIS", snapshot.timeBasis.uppercased())
                Spacer()
                headerValue("STATUS", fuelPlan.result.hasWarning ? "CHECK" : "RELEASED")
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color.black.opacity(0.045))
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var summary: some View {
        HStack(spacing: 8) {
            summaryBox(
                "RELEASE FUEL",
                liters(fuelPlan.startingFuelLiters),
                emphasized: true
            )
            summaryBox(
                "MINIMUM T/O",
                liters(fuelPlan.result.minimumStartingFuelLiters)
            )
            summaryBox(
                "TRIP FUEL",
                liters(plannedTripFuel)
            )
            summaryBox(
                "PLAN REFUEL",
                plannedRefuelTotal <= 0
                    ? "–"
                    : liters(plannedRefuelTotal)
            )
            summaryBox(
                "RESERVE ZIEL",
                liters(fuelPlan.result.finalReserveLiters)
            )
        }
    }

    private var fuelTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("OPERATIONAL FUEL SCHEDULE")
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.8)
                Spacer()
                Text("ALL VALUES LITRES · CONSERVATIVE WHOLE-LITRE PLAN")
                    .font(.system(size: 5.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(FlybookColor.muted)
            }
            .padding(.horizontal, 10)
            .frame(height: 25)

            HStack(spacing: 4) {
                heading("ABSCHNITT", width: 110, alignment: .leading)
                heading("MINIMUM T/O", width: 65)
                heading("MINIMUM LDG", width: 65)
                heading("PLAN T/O → LDG", width: 115)
                heading("LEG / GESAMT", width: 85)
                heading("ZEIT", width: 48)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(FlybookColor.navy)

            ForEach(Array(fuelPlan.result.rows.enumerated()), id: \.element.id) {
                index, row in
                fuelRow(row, index: index)
                if row.refuelAfterArrivalLiters > 0 {
                    refuelRow(row)
                }
                if index < fuelPlan.result.rows.count - 1 {
                    Divider()
                }
            }
        }
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(FlybookColor.navy.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func fuelRow(_ row: FuelPlanRow, index: Int) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: 5) {
                Text(String(format: "%02d", index + 1))
                    .foregroundStyle(FlybookColor.muted)
                Text("\(row.leg.originICAO) → \(row.leg.destinationICAO)")
            }
            .font(.system(size: 8.3, weight: .black, design: .monospaced))
            .frame(width: 110, alignment: .leading)
            value(liters(row.minimumDepartureLiters), width: 65, minimum: true)
            value(liters(row.minimumArrivalLiters), width: 65)
            value(
                "\(liters(row.plannedDepartureLiters)) → "
                    + liters(row.plannedArrivalLiters),
                width: 115,
                plan: true
            )
            value(
                "\(rounded(row.leg.burnLiters)) / "
                    + "\(rounded(row.stageBurnLiters)) L",
                width: 85
            )
            value(FlightMath.duration(row.leg.flightMinutes), width: 48)
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(index.isMultiple(of: 2) ? Color.white : Color.black.opacity(0.018))
    }

    private func refuelRow(_ row: FuelPlanRow) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "fuelpump.fill")
                VStack(alignment: .leading, spacing: 1) {
                    Text("REFUEL ACTION")
                        .font(.system(size: 5.8, weight: .black))
                    Text(refuelAirportName(row.leg.destinationICAO))
                        .font(.system(size: 8, weight: .black))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: 248, alignment: .leading)

            value(
                "MIN \(liters(minimumRefuel(for: row))) · PLAN \(liters(row.refuelAfterArrivalLiters))",
                width: 115,
                plan: true
            )
            Color.clear.frame(width: 85, height: 1)
            Color.clear.frame(width: 48, height: 1)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(FlybookColor.blue.opacity(0.14))
    }

    private var plannedRefuelTotal: Double {
        fuelPlan.result.rows.reduce(0) {
            $0 + $1.refuelAfterArrivalLiters
        }
    }

    private var plannedTripFuel: Double {
        fuelPlan.result.rows.reduce(0) { $0 + $1.leg.burnLiters }
    }

    private func minimumRefuel(for row: FuelPlanRow) -> Double {
        guard let index = fuelPlan.result.rows.firstIndex(where: { $0.id == row.id }) else {
            return 0
        }
        return fuelPlan.result.minimumRefuelLitersByLegIndex[index] ?? 0
    }

    private var status: some View {
        Label(
            fuelPlan.result.hasWarning
                ? "Bestätigter Tankplan enthält eine Unterdeckung oder Kapazitätswarnung."
                : "Bestätigter Tankplan erfüllt alle Mindestbestände einschließlich Endreserve.",
            systemImage: fuelPlan.result.hasWarning
                ? "exclamationmark.triangle.fill"
                : "checkmark.circle.fill"
        )
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(fuelPlan.result.hasWarning ? Color.red : Color.green)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill((fuelPlan.result.hasWarning ? Color.red : Color.green).opacity(0.07))
        )
    }

    private var releaseNotes: some View {
        HStack(spacing: 8) {
            releaseNote("CAPACITY", liters(fuelPlan.usableFuelLiters))
            releaseNote("FINAL PLAN", fuelPlan.result.rows.last.map { liters($0.plannedArrivalLiters) } ?? "–")
            releaseNote("RESERVE", liters(fuelPlan.result.finalReserveLiters))
            VStack(alignment: .leading, spacing: 3) {
                Text("PIC ACCEPTANCE")
                    .font(.system(size: 6.2, weight: .black))
                    .foregroundStyle(FlybookColor.muted)
                Rectangle()
                    .fill(FlybookColor.navy.opacity(0.45))
                    .frame(height: 1)
                Text("SIGN / TIME")
                    .font(.system(size: 5.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(FlybookColor.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(height: 42)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(FlybookColor.line))
        }
    }

    private func releaseNote(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 6.2, weight: .black))
                .foregroundStyle(FlybookColor.muted)
            Text(text)
                .font(.system(size: 9, weight: .black, design: .monospaced))
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .padding(.horizontal, 8)
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(FlybookColor.line))
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            Text(
                "Planungshilfe – Tankplan vor dem Flug gegen Flughandbuch, "
                    + "Betankung und tatsächliche Flugbedingungen prüfen."
            )
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(FlybookColor.muted)
            Spacer()
            Text("Seite \(pageNumber)/\(pageCount)")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
        }
        .padding(.top, 5)
        .overlay(alignment: .top) {
            Rectangle().fill(FlybookColor.line).frame(height: 1)
        }
    }

    private func headerValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
            Text(value)
                .font(.system(size: 9.5, weight: .bold))
                .lineLimit(1)
        }
    }

    private func summaryBox(
        _ title: String,
        _ text: String,
        emphasized: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
            Text(text)
                .font(.system(size: 13, weight: .black, design: .monospaced))
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .padding(.horizontal, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    emphasized
                        ? Color.yellow.opacity(0.22)
                        : FlybookColor.blue.opacity(0.08)
                )
        )
    }

    private func heading(
        _ text: String,
        width: CGFloat,
        alignment: Alignment = .trailing
    ) -> some View {
        Text(text)
            .font(.system(size: 6.5, weight: .black))
            .foregroundStyle(Color.white)
            .frame(width: width, alignment: alignment)
    }

    private func value(
        _ text: String,
        width: CGFloat,
        minimum: Bool = false,
        plan: Bool = false
    ) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .black, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: width, height: 27, alignment: .trailing)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        minimum
                            ? Color.yellow.opacity(0.20)
                            : plan
                                ? FlybookColor.blue.opacity(0.10)
                                : Color.clear
                    )
            )
    }

    private func refuelAirportName(_ icao: String) -> String {
        guard let name = fuelPlan.airportNames[icao], !name.isEmpty else {
            return icao
        }
        let conciseName = name
            .split(separator: "/", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? name
        return "\(icao) - \(conciseName)"
    }

    private func rounded(_ value: Double) -> Int {
        FuelPlanCalculator.roundedLitersForDisplay(value)
    }

    private func liters(_ value: Double) -> String {
        "\(rounded(value)) L"
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = DestinationTimeZone.edfz
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter.string(from: date)
    }
}

private struct FlybriefLegCard: View {
    let leg: FlybriefLegSnapshot
    let sharesPage: Bool

    var body: some View {
        VStack(spacing: 7) {
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

                VStack(alignment: .leading, spacing: 1.5) {
                    RouteWeatherStrip(
                        points: leg.routeWeather,
                        summary: leg.routeWeatherSummary
                    )
                    Text(leg.altitudeWindsText)
                        .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                        .foregroundStyle(FlybookColor.muted)
                        .lineLimit(1)
                }
            }

            routeMetrics

            if leg.segments.count > 1 {
                VStack(spacing: 7) {
                    ForEach(leg.segments) { segment in
                        FlybriefSegmentCard(
                            segment: segment,
                            dense: sharesPage || leg.segments.count > 2
                        )
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    FlybriefEndpointCard(
                        endpoint: leg.departure,
                        compact: sharesPage,
                        dense: sharesPage
                    )
                    FlybriefEndpointCard(
                        endpoint: leg.arrival,
                        compact: sharesPage,
                        dense: sharesPage
                    )
                }
            }

            FlybriefAlternatesMemo(
                destinationICAO: leg.arrival.icao,
                alternates: leg.alternates,
                dense: sharesPage || leg.segments.count > 1
            )
        }
        .padding(sharesPage ? 7 : 10)
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
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                metric("GESAMTREISE", leg.travelTimeText)
                metric("GESAMTBLOCK", leg.blockTimeText)
                metric("GESAMT TRACK", leg.trackText)
                metric("ETOPS-PIPI MAX", leg.etopsText, level: leg.etopsLevel)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("HÖHE")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
                Text(leg.altitudeText)
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                Text("BEST")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
                Text(leg.bestLevelText)
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                Rectangle()
                    .fill(FlybookColor.line)
                    .frame(width: 1, height: 13)
                Text("STRECKENWIND")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
                Text(leg.routeWindText)
                    .font(.system(size: 10.5, weight: .black))
                Text(leg.routeWindDetail)
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(FlybookColor.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
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
                .font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
            Text(value)
                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 31, alignment: .leading)
        .padding(.horizontal, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(level == .neutral ? Color.white : level.paleColor)
        )
    }
}

private struct FlybriefAlternatesMemo: View {
    let destinationICAO: String
    let alternates: [FlybriefAlternateSnapshot]
    let dense: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 2 : 3) {
            HStack(spacing: 5) {
                Image(systemName: "airplane.circle.fill")
                    .foregroundStyle(FlybookColor.blue)
                Text("ALTERNATES FÜR \(destinationICAO)")
                    .font(.system(size: dense ? 6.5 : 7.5, weight: .black))
                Text("Schnell-Memo · Entfernung und Flugzeit ab Ziel")
                    .font(.system(size: dense ? 5.5 : 6.5, weight: .semibold))
                    .foregroundStyle(FlybookColor.muted)
                Spacer()
            }

            if alternates.isEmpty {
                Text("Keine Alternate-Daten verfügbar")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(FlybookColor.muted)
            } else {
                alternateHeader
                ForEach(alternates.prefix(3)) { alternate in
                    alternateRow(alternate)
                }
            }
        }
        .padding(.horizontal, dense ? 5 : 7)
        .padding(.vertical, dense ? 4 : 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(FlybookColor.blue.opacity(0.32), lineWidth: 1)
        )
    }

    private var alternateHeader: some View {
        HStack(spacing: 4) {
            headerCell("ICAO", width: 32, alignment: .leading)
            headerCell("FLUGPLATZ", width: 138, alignment: .leading)
            headerCell("DIST", width: 40)
            headerCell("FLUGZEIT", width: 42)
            headerCell("SPRIT", width: 32)
            headerCell("RWY", width: 64)
            headerCell("LÄNGE", width: 46)
            headerCell("BELAG", width: 54, alignment: .leading)
        }
        .padding(.vertical, 1.5)
        .background(Color.black.opacity(0.035))
    }

    private func headerCell(
        _ text: String,
        width: CGFloat,
        alignment: Alignment = .trailing
    ) -> some View {
        Text(text)
            .font(.system(size: dense ? 4.8 : 5.5, weight: .black))
            .foregroundStyle(FlybookColor.muted)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }

    private func alternateRow(_ alternate: FlybriefAlternateSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0.5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(alternate.icao)
                    .font(.system(size: dense ? 6.8 : 8, weight: .black, design: .monospaced))
                    .foregroundStyle(FlybookColor.blue)
                    .frame(width: 32, alignment: .leading)
                Text(alternate.name)
                    .font(.system(size: dense ? 6.2 : 7.2, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: 138, alignment: .leading)
                Text("\(Int(alternate.distanceNM.rounded())) NM")
                    .font(.system(size: dense ? 6.2 : 7, weight: .black, design: .monospaced))
                    .frame(width: 40, alignment: .trailing)
                Text(alternate.flightTimeText)
                    .font(.system(size: dense ? 6.2 : 7, weight: .black, design: .monospaced))
                    .frame(width: 42, alignment: .trailing)
                Text("\(alternate.fuelLiters) L")
                    .font(.system(size: dense ? 6.2 : 7, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.green)
                    .frame(width: 32, alignment: .trailing)
                alternateRunway(alternate)
                    .frame(width: 64, alignment: .trailing)
                Text("\(alternate.runwayLengthMeters) m")
                    .font(.system(size: dense ? 6.2 : 7, weight: .black, design: .monospaced))
                    .frame(width: 46, alignment: .trailing)
                Text(alternate.surface)
                    .font(.system(size: dense ? 6 : 6.8, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: 54, alignment: .leading)
            }

            HStack(spacing: 4) {
                Color.clear.frame(width: 32, height: 1)
                HStack(spacing: 2) {
                    Circle()
                        .fill(alternate.weatherLevel.color)
                        .frame(width: 4, height: 4)
                    weatherCell(alternate.weatherCategory, width: 34)
                    weatherCell(alternate.weatherCondition, width: 58)
                    weatherCell(alternate.weatherCloudVisibility, width: 160)
                }
                .frame(width: 264, alignment: .leading)
                weatherCell(alternate.weatherWind, width: 64)
                Color.clear.frame(width: 104, height: 1)
            }
        }
        .padding(.vertical, 0.5)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FlybookColor.line.opacity(0.45))
                .frame(height: 0.5)
        }
    }

    private func alternateRunway(
        _ alternate: FlybriefAlternateSnapshot
    ) -> some View {
        HStack(spacing: 1) {
            Text("RWY")
                .foregroundStyle(FlybookColor.muted)
            let ends = alternate.runwayDirection.split(separator: "/").map(String.init)
            ForEach(Array(ends.enumerated()), id: \.offset) { index, end in
                if index > 0 {
                    Text("/")
                        .foregroundStyle(FlybookColor.navy)
                }
                Text(end)
                    .foregroundStyle(
                        alternate.preferredRunway?.uppercased() == end.uppercased()
                            ? Color.white
                            : FlybookColor.navy
                    )
                    .padding(.horizontal, 1.5)
                    .padding(.vertical, 0.5)
                    .background(
                        Capsule().fill(
                            alternate.preferredRunway?.uppercased() == end.uppercased()
                                ? FlybookColor.blue
                                : Color.clear
                        )
                    )
            }
        }
        .font(.system(size: dense ? 5.8 : 6.7, weight: .black, design: .monospaced))
        .lineLimit(1)
    }

    private func weatherCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: dense ? 5.7 : 6.5, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .frame(width: width, alignment: .leading)
    }
}

private struct FlybriefSegmentCard: View {
    let segment: FlybriefSegmentSnapshot
    let dense: Bool

    var body: some View {
        VStack(spacing: dense ? 3 : 5) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(segment.title.uppercased())
                    .font(.system(size: dense ? 7 : 8, weight: .black))
                    .foregroundStyle(FlybookColor.blue)
                Text(segment.routeText)
                    .font(.system(size: dense ? 8.5 : 9.5, weight: .black, design: .monospaced))
                Text("BLOCK " + segment.blockTimeText)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                Text("TRACK " + segment.trackText)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                Spacer(minLength: 2)
                VStack(alignment: .leading, spacing: 1) {
                    RouteWeatherStrip(
                        points: segment.routeWeather,
                        summary: segment.routeWeatherSummary
                    )
                    Text(segment.altitudeWindsText)
                        .font(.system(size: dense ? 5.7 : 6.4, weight: .bold, design: .monospaced))
                        .foregroundStyle(FlybookColor.muted)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("Wind " + segment.routeWindText + " · " + segment.routeWindDetail)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(FlybookColor.muted)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }

            HStack(alignment: .top, spacing: 8) {
                FlybriefEndpointCard(
                    endpoint: segment.departure,
                    compact: true,
                    dense: dense
                )
                FlybriefEndpointCard(
                    endpoint: segment.arrival,
                    compact: true,
                    dense: dense
                )
            }
        }
        .padding(dense ? 5 : 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.72)))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(FlybookColor.blue.opacity(0.24), lineWidth: 1)
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
    var compact = false
    var dense = false

    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 2 : 4) {
            HStack(alignment: .top, spacing: 5) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(endpoint.role.uppercased())
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(FlybookColor.muted)
                    Text(endpoint.icao + " · " + endpoint.name)
                        .font(.system(size: dense ? 9 : 10.5, weight: .black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let openingHoursText = endpoint.openingHoursText {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                            Text(openingHoursText)
                                .lineLimit(1)
                        }
                        .font(.system(size: dense ? 5.8 : 6.8, weight: .semibold))
                        .foregroundStyle(FlybookColor.muted)
                    }
                }
                Spacer(minLength: 2)
                Text(endpoint.timeText)
                    .font(.system(size: dense ? 10.5 : 13, weight: .black, design: .monospaced))
            }

            HStack(spacing: 5) {
                statusPill(endpoint.operatingStatus, level: endpoint.operatingLevel)
                statusPill(endpoint.weather.category, level: endpoint.weather.categoryLevel)
                if !endpoint.activeRunway.isEmpty {
                    statusPill("RWY " + endpoint.activeRunway, level: endpoint.runwayWind?.warningLevel ?? .neutral)
                }
            }

            if let performance = endpoint.runwayPerformance {
                HStack(spacing: 2) {
                    if performance.label == "LDG" {
                        Text("50ft:")
                        performanceValue(
                            meters: performance.over50FeetMeters,
                            percentage: performance.over50FeetPercentage,
                            isFiftyFeet: true
                        )
                        Text("/ LDG Roll")
                        performanceValue(
                            meters: performance.rollMeters,
                            percentage: performance.rollPercentage
                        )
                    } else {
                        Text(performance.label + " Roll")
                        performanceValue(
                            meters: performance.rollMeters,
                            percentage: performance.rollPercentage
                        )
                        Text("/ 50ft:")
                        performanceValue(
                            meters: performance.over50FeetMeters,
                            percentage: performance.over50FeetPercentage,
                            isFiftyFeet: true
                        )
                    }
                    Text("/ \(performance.weightKilograms)kg")
                }
                    .font(.system(size: dense ? 6.2 : 7.4, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            HStack(alignment: .center, spacing: 6) {
                if let runwayWind = endpoint.runwayWind {
                    RunwayWindGeometryView(
                        runway: endpoint.referenceRunway,
                        windDirection: runwayWind.windDirectionDegrees,
                        activeRunway: endpoint.activeRunway,
                        emphasizesActiveRunway: true
                    )
                    .scaleEffect(dense ? 0.49 : (compact ? 0.67 : 0.79))
                    .frame(
                        width: dense ? 68 : (compact ? 90 : 104),
                        height: dense ? 56 : (compact ? 76 : 94)
                    )
                    .clipped()
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "road.lanes")
                            .font(.system(size: 20, weight: .bold))
                        Text(endpoint.referenceRunway.isEmpty ? "RWY -" : "RWY " + endpoint.referenceRunway)
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(FlybookColor.muted)
                    .frame(
                        width: dense ? 68 : (compact ? 90 : 104),
                        height: dense ? 56 : (compact ? 76 : 94)
                    )
                }

                VStack(alignment: .leading, spacing: dense ? 1 : 3) {
                    weatherLine(endpoint.weather.condition + "  " + endpoint.weather.temperatureText, bold: true)
                    weatherLine(endpoint.weather.cloudVisibilityText, bold: true)
                    airportWindLine(endpoint.weather.windText)
                    weatherLine(endpoint.weather.pressureText + "  " + endpoint.weather.densityAltitudeText)
                    if let runwayWind = endpoint.runwayWind {
                        weatherLine(headwindText(runwayWind), bold: true)
                        weatherLine(crosswindText(runwayWind), bold: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(endpoint.sunText)
                .font(.system(size: dense ? 6 : 7.2, weight: .semibold, design: .monospaced))
                .foregroundStyle(FlybookColor.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack {
                Text(endpoint.weather.validTimeText)
                    .font(.system(size: dense ? 6 : 7, weight: .semibold))
                    .foregroundStyle(FlybookColor.muted)
                Spacer()
                if let warning = endpoint.weather.warningText {
                    Text(warning)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.red)
                        .lineLimit(1)
                }
            }
        }
        .padding(dense ? 5 : 7)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(FlybookColor.line, lineWidth: 1)
        )
    }

    private func performanceValue(
        meters: Int,
        percentage: Int?,
        isFiftyFeet: Bool = false
    ) -> some View {
        Text(
            "\(meters)m"
                + (percentage.map { " (\($0)%)" } ?? "")
        )
        .foregroundStyle(performanceColor(percentage, isFiftyFeet: isFiftyFeet))
    }

    private func performanceColor(_ percentage: Int?, isFiftyFeet: Bool) -> Color {
        guard let percentage else { return FlybookColor.navy }
        if isFiftyFeet {
            return percentage >= 100 ? .red : FlybookColor.navy
        }
        if percentage >= 75 { return .red }
        if percentage >= 50 { return .orange }
        return FlybookColor.navy
    }

    private func statusPill(
        _ text: String,
        level: FlybriefAlertLevel
    ) -> some View {
        HStack(spacing: 3) {
            Circle().fill(level.color).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: dense ? 6.2 : 7, weight: .bold))
                .lineLimit(1)
        }
        .padding(.horizontal, dense ? 4 : 5)
        .padding(.vertical, dense ? 1.5 : 2.5)
        .background(Capsule().fill(level.paleColor))
    }

    private func weatherLine(_ text: String, bold: Bool = false) -> some View {
        Text(text)
            .font(.system(size: dense ? 7.1 : 8.3, weight: bold ? .bold : .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func airportWindLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: dense ? 8 : 9.4, weight: .black, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, dense ? 4 : 6)
            .padding(.vertical, dense ? 2 : 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(FlybookColor.blue.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(FlybookColor.navy.opacity(0.72), lineWidth: 1.2)
            )
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
