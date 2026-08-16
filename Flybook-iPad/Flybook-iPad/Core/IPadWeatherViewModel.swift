import Foundation

struct IPadDailyWeather: Identifiable, Hashable {
    let date: Date
    let symbolName: String
    let periodSymbolNames: [String]
    let minimumTemperature: Int?
    let maximumTemperature: Int?
    let maximumWindKnots: Int?
    let maximumFogRisk: Int?
    let hourlyWindKnots: [Double?]
    let hourlyFogRisk: [Int?]
    var id: Date { date }
}

@MainActor
final class IPadWeatherViewModel: ObservableObject {
    @Published private(set) var departureSample: EDFZWeatherSample?
    @Published private(set) var arrivalSample: EDFZWeatherSample?
    @Published private(set) var days: [IPadDailyWeather] = []
    @Published private(set) var sourceLabel = "ICON-SEAMLESS"
    @Published private(set) var isLoading = false

    func load(
        departureAirport: Airport,
        arrivalAirport: Airport,
        departure: Date,
        arrival: Date,
        overviewAirport: Airport,
        forceRefresh: Bool = false
    ) async {
        isLoading = true
        defer { isLoading = false }
        async let departureForecast = try? EDFZWeatherService.shared.forecast(
            plannedDate: departure,
            airport: departureAirport.sharedReference,
            forceRefresh: forceRefresh
        )
        async let arrivalForecast = try? EDFZWeatherService.shared.forecast(
            plannedDate: arrival,
            airport: arrivalAirport.sharedReference,
            forceRefresh: forceRefresh
        )
        let overviewDates = (0..<5).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: .now)
        }
        var forecasts: [EDFZForecast] = []
        await withTaskGroup(of: EDFZForecast?.self) { group in
            for date in overviewDates {
                group.addTask {
                    try? await EDFZWeatherService.shared.forecast(
                        plannedDate: date,
                        airport: overviewAirport.sharedReference,
                        forceRefresh: forceRefresh
                    )
                }
            }
            for await forecast in group {
                if let forecast { forecasts.append(forecast) }
            }
        }
        let dep = await departureForecast
        let arr = await arrivalForecast
        departureSample = dep?.sample(nearestTo: departure)
        arrivalSample = arr?.sample(nearestTo: arrival)
        if let source = dep?.source ?? arr?.source ?? forecasts.first?.source {
            sourceLabel = Self.sourceLabel(source)
        }
        days = overviewDates.map { date in
            let calendar = Self.calendar(for: overviewAirport)
            let samples = forecasts
                .flatMap(\.samples)
                .filter { calendar.isDate($0.validTime, inSameDayAs: date) }
            return Self.dailySummary(date: date, samples: samples, calendar: calendar)
        }
    }

    private static func calendar(for airport: Airport) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: airport.timeZoneIdentifier) ?? .current
        return calendar
    }

    private static func sourceLabel(_ source: EDFZForecastSource) -> String {
        switch source {
        case .iconSeamless(.dedicatedDWD): return "ICON-SEAMLESS · DWD"
        case .iconSeamless(.genericForecast): return "ICON-SEAMLESS · RESERVE"
        case .bestMatch: return "BEST MATCH · FALLBACK"
        case .metNorway: return "MET NORWAY · FALLBACK"
        case .mosmix: return "DWD MOSMIX · FALLBACK"
        }
    }

    private static func dailySummary(
        date: Date,
        samples: [EDFZWeatherSample],
        calendar: Calendar
    ) -> IPadDailyWeather {
        func nearest(hour: Int) -> EDFZWeatherSample? {
            samples.min {
                abs((calendar.component(.hour, from: $0.validTime)) - hour)
                    < abs((calendar.component(.hour, from: $1.validTime)) - hour)
            }
        }
        let representative = [8, 14, 20].compactMap(nearest)
        let daytime = samples.filter {
            (6...22).contains(calendar.component(.hour, from: $0.validTime))
        }
        let temperatures = samples.compactMap(\.temperatureCelsius)
        func sample(hour: Int) -> EDFZWeatherSample? {
            daytime.min {
                abs(calendar.component(.hour, from: $0.validTime) - hour)
                    < abs(calendar.component(.hour, from: $1.validTime) - hour)
            }
        }
        let hourlySamples = Array(6...22).map(sample)
        let hourlyWind = hourlySamples.map { $0?.windSpeedKnots }
        let hourlyFog = hourlySamples.map { sample -> Int? in
            guard let sample else { return nil }
            guard let temperature = sample.temperatureCelsius,
                  let dewPoint = sample.dewPointCelsius,
                  let wind = sample.windSpeedKnots,
                  let visibility = sample.visibilityMeters,
                  let lowCloud = sample.lowCloudCoverPercent
            else { return nil }
            // Diese Näherung gehört ausschließlich zum validierten
            // 5-Tages-Nebel-/Tiefwolken-Risikomodell. Sie wird weder als
            // Planungs-Ceiling angezeigt noch zur Flugkategorie erklärt.
            let riskCeiling = lowCloud >= 62.5
                ? max(0, temperature - dewPoint) * 400
                : 10_000
            return FogRiskModel.calculate(
                FogRiskInput(
                    temperatureC: temperature,
                    dewPointC: dewPoint,
                    windKt: wind,
                    visibilityKm: visibility / 1_000,
                    lowCloudPercent: lowCloud,
                    ceilingFt: riskCeiling,
                    totalCloudPercent: sample.totalCloudCoverPercent ?? 0
                )
            )?.score
        }
        return IPadDailyWeather(
            date: date,
            symbolName: representativeSymbol(codes: representative.compactMap(\.weatherCode)),
            periodSymbolNames: [8, 14, 20].map { hour in
                weatherSymbol(code: nearest(hour: hour)?.weatherCode)
            },
            minimumTemperature: temperatures.min().map { Int($0.rounded()) },
            maximumTemperature: temperatures.max().map { Int($0.rounded()) },
            maximumWindKnots: hourlyWind.compactMap { $0 }.max().map { Int($0.rounded()) },
            maximumFogRisk: hourlyFog.compactMap { $0 }.max(),
            hourlyWindKnots: hourlyWind,
            hourlyFogRisk: hourlyFog
        )
    }

    private static func representativeSymbol(codes: [Int]) -> String {
        guard !codes.isEmpty else { return "questionmark.circle" }
        func score(_ code: Int) -> Double {
            switch code {
            case 0: return 0
            case 1, 2: return 1
            case 3: return 2
            case 45, 48, 51, 53, 55: return 3
            case 56, 57, 61, 63, 66, 71, 73, 77, 80, 81, 85: return 4
            case 65, 67, 75, 82, 86: return 5
            case 95, 96, 99: return 6
            default: return 2
            }
        }
        let average = codes.map(score).reduce(0, +) / Double(codes.count)
        switch average {
        case ..<0.25: return "sun.max.fill"
        case ..<1.5: return "cloud.sun.fill"
        case ..<2.5: return "cloud.fill"
        case ..<3.5: return "cloud.fog.fill"
        case ..<5.5: return "cloud.rain.fill"
        default: return "cloud.bolt.rain.fill"
        }
    }

    private static func weatherSymbol(code: Int?) -> String {
        guard let code else { return "questionmark.circle" }
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}
