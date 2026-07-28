import SwiftUI
import AppKit

enum TimeDisplayMode: String, CaseIterable, Identifiable {
    case local
    case utc

    var id: String { rawValue }
}

struct DestinationPage: View {
    let destination: Destination
    @StateObject private var weatherModel = WeatherViewModel()
    @StateObject private var outboundRouteWindModel = RouteWindViewModel()
    @StateObject private var returnRouteWindModel = RouteWindViewModel()
    @StateObject private var outboundEDFZWeatherModel = EDFZWeatherViewModel()
    @StateObject private var returnEDFZWeatherModel = EDFZWeatherViewModel()
    @State private var outboundFlightDate =
        Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
    @State private var returnFlightDate =
        Calendar.current.date(
            byAdding: .day,
            value: 2,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
    @State private var outboundStartText = "09:30"
    @State private var desiredHomeArrivalText = "17:00"
    @State private var outboundStops = 0
    @State private var returnStops = 0
    @State private var timeDisplayMode: TimeDisplayMode = .local

    @AppStorage(CalculationSettingsKey.tankStopMinutes)
    private var tankStopMinutes =
        CalculationSettings.defaultTankStopMinutes

    @AppStorage(CalculationSettingsKey.vatPercent)
    private var vatPercent =
        CalculationSettings.defaultVATPercent

    @AppStorage(AircraftSettingsKey.selectedAircraft)
    private var selectedAircraftRaw =
        AircraftType.a211.rawValue

    private var selectedAircraft: AircraftType {
        AircraftType(rawValue: selectedAircraftRaw)
            ?? .a211
    }

    private var hourlyRateEUR: Double {
        AircraftProfileStore.hourlyRate(
            for: selectedAircraft
        )
    }

    private var cruiseGroundSpeedKnots: Double {
        AircraftProfileStore.cruiseSpeed(
            for: selectedAircraft
        )
    }

    private var fuelConsumptionPerHour: Double {
        AircraftProfileStore.fuelConsumption(
            for: selectedAircraft
        )
    }

    private var usableFuel: Double {
        AircraftProfileStore.usableFuel(
            for: selectedAircraft
        )
    }

    @AppStorage(CalculationSettingsKey.weekdayDiscountEnabled)
    private var weekdayDiscountEnabled =
        CalculationSettings.defaultWeekdayDiscountEnabled

    @AppStorage(CalculationSettingsKey.reserveMinutes)
    private var reserveMinutes =
        CalculationSettings.defaultReserveMinutes

    @AppStorage(
        CalculationSettingsKey.maxTravelMinutesUntilOvernight
    )
    private var maxTravelMinutesUntilOvernight =
        CalculationSettings
            .defaultMaxTravelMinutesUntilOvernight

    @AppStorage(
        CalculationSettingsKey.prepaymentDiscount15To29Enabled
    )
    private var prepaymentDiscount15To29Enabled =
        CalculationSettings
            .defaultPrepaymentDiscount15To29Enabled

    @AppStorage(
        CalculationSettingsKey.prepaymentDiscount30PlusEnabled
    )
    private var prepaymentDiscount30PlusEnabled =
        CalculationSettings
            .defaultPrepaymentDiscount30PlusEnabled

    var body: some View {
        GeometryReader { geometry in
            let scale = min(
                geometry.size.width / 1800.0,
                geometry.size.height / 1200.0
            )

            pageContent
                .frame(width: 1800, height: 1200)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(
                    width: 1800 * scale,
                    height: 1200 * scale,
                    alignment: .topLeading
                )
                .position(
                    x: geometry.size.width / 2.0,
                    y: geometry.size.height / 2.0
                )
        }
        .background(FlybookColor.background)
        .id(selectedAircraftRaw)
        .task(id: weatherTaskID) {
            await weatherModel.load(
                destination: destination,
                targetInstants: weatherTargetInstants
            )
        }
        .task(id: outboundWindTaskID) {
            await outboundRouteWindModel.load(
                destination: destination,
                plannedInstant:
                    outboundWindForecastInstant
            )
        }
        .task(id: returnWindTaskID) {
            await returnRouteWindModel.load(
                destination: destination,
                plannedInstant:
                    returnWindForecastInstant
            )
        }
        .task(id: outboundEDFZWeatherTaskID) {
            await outboundEDFZWeatherModel.load(
                plannedDate: outboundFlightDate
            )
        }
        .task(id: returnEDFZWeatherTaskID) {
            await returnEDFZWeatherModel.load(
                plannedDate: returnFlightDate
            )
        }
    }

    private var outboundWindTaskID: String {
        instantTaskID(
            prefix: "out-wind",
            instant: outboundWindForecastInstant
        )
    }

    private var returnWindTaskID: String {
        instantTaskID(
            prefix: "ret-wind",
            instant: returnWindForecastInstant
        )
    }

    private var outboundEDFZWeatherTaskID: String {
        dateTaskID(prefix: "out-edfz", date: outboundFlightDate)
    }

    private var returnEDFZWeatherTaskID: String {
        dateTaskID(prefix: "ret-edfz", date: returnFlightDate)
    }

    private var weatherTaskID: String {
        let stamps = weatherTargetInstants.map { String(Int($0.timeIntervalSince1970 / 1800)) }
        return ([destination.icao] + stamps).joined(separator: "-")
    }

    private func dateTaskID(prefix: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(prefix)-\(destination.icao)-\(formatter.string(from: date))"
    }

    private func instantTaskID(
        prefix: String,
        instant: Date
    ) -> String {
        let fiveMinuteBucket =
            Int(instant.timeIntervalSince1970 / 300)

        return
            "\(prefix)-\(destination.icao)-"
            + "\(fiveMinuteBucket)-"
            + selectedAircraftRaw
    }

    private var displayTimeZone: TimeZone {
        timeDisplayMode == .utc
            ? TimeZone(secondsFromGMT: 0)!
            : DestinationTimeZone.edfz
    }

    private var outboundTravelMinutesForWeather: Int {
        FlightMath.adjustedMinutes(
            directNM: destination.directNM,
            stopCount: outboundStops,
            headwindKnots: outboundRouteWindModel.wind?.outboundHeadwindKnots,
            tankStopMinutes: tankStopMinutes,
            cruiseGroundSpeedKnots:
                cruiseGroundSpeedKnots
        )
    }

    private var returnTravelMinutesForWeather: Int {
        FlightMath.adjustedMinutes(
            directNM: destination.directNM,
            stopCount: returnStops,
            headwindKnots:
                returnRouteWindModel.wind?
                    .returnHeadwindKnots,
            tankStopMinutes: tankStopMinutes,
            cruiseGroundSpeedKnots:
                cruiseGroundSpeedKnots
        )
    }

    private var outboundStartInstant: Date {
        FlightDateTime.instant(
            date: outboundFlightDate,
            timeText: outboundStartText,
            timeZone: displayTimeZone
        ) ?? outboundFlightDate
    }

    private var outboundArrivalInstantForWeather: Date {
        outboundStartInstant.addingTimeInterval(
            TimeInterval(
                outboundTravelMinutesForWeather * 60
            )
        )
    }

    private var outboundWindForecastInstant: Date {
        temporalMidpoint(
            between: outboundStartInstant,
            and: outboundArrivalInstantForWeather
        )
    }

    private var returnArrivalInstant: Date {
        FlightDateTime.instant(
            date: returnFlightDate,
            timeText: desiredHomeArrivalText,
            timeZone: displayTimeZone
        ) ?? returnFlightDate
    }

    private var returnDepartureInstantForWeather: Date {
        returnArrivalInstant.addingTimeInterval(
            TimeInterval(
                -returnTravelMinutesForWeather * 60
            )
        )
    }

    private var returnWindForecastInstant: Date {
        temporalMidpoint(
            between: returnDepartureInstantForWeather,
            and: returnArrivalInstant
        )
    }

    private func temporalMidpoint(
        between start: Date,
        and end: Date
    ) -> Date {
        start.addingTimeInterval(
            end.timeIntervalSince(start) / 2.0
        )
    }

    private var weatherTargetInstants: [Date] {
        [outboundArrivalInstantForWeather, returnDepartureInstantForWeather]
    }

    private var pageContent: some View {
        ZStack(alignment: .topLeading) {
            FlybookColor.background

            VStack(alignment: .leading, spacing: 24) {
                header
                    .frame(
                        width: 675,
                        alignment: .leading
                    )
                    .frame(
                        minHeight: 118,
                        alignment: .topLeading
                    )

                airportSection
                    .frame(width: 675)

                flightSection
                    .frame(width: 675)

                weatherSection
                    .frame(width: 675)
            }
            .fixedSize(
                horizontal: false,
                vertical: true
            )
            .offset(x: 34, y: 28)

            VStack(spacing: 20) {
                mapAndImageSection

                fiveDayForecastSection

                FlybookCard {
                    TravelDurationBar(
                        minutes:
                            outboundTravelMinutesForWeather,
                        thresholdMinutes:
                            maxTravelMinutesUntilOvernight
                    )
                }
                .frame(height: 115)

                calculationSection
            }
            .frame(width: 1010)
            .position(x: 1260, y: 600)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(destination.name.uppercased())
                    .font(
                        .system(
                            size: destination.name.count > 16
                                ? 54
                                : 70,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(FlybookColor.navy)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )

                Text(
                    "\(destination.icao)  ·  "
                    + "\(countryFlag(destination.country))  ·  "
                    + destination.region.uppercased()
                    + "  ·  HÖHE "
                    + "\(Int(destination.elevationFeet.rounded())) FT"
                )
                .font(.system(size: 16))
                .foregroundStyle(FlybookColor.navy)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text("FLUGZEUG")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)

                Picker(
                    "Flugzeug",
                    selection: $selectedAircraftRaw
                ) {
                    ForEach(AircraftType.allCases) {
                        aircraft in
                        Text(aircraft.rawValue)
                            .tag(aircraft.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 145)
            }
            .padding(.top, 8)
        }
    }

    private func countryFlag(_ countryCode: String) -> String {
        let code = countryCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard code.count == 2 else { return code }

        let base: UInt32 = 127397
        let scalars = code.unicodeScalars.compactMap {
            UnicodeScalar(base + $0.value)
        }

        guard scalars.count == 2 else { return code }
        return String(String.UnicodeScalarView(scalars))
    }

    private var flightSection: some View {
        FlybookCard {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 18) {
                    Text("FLUGPLANUNG")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 5) {
                        Picker("Zeitbasis", selection: timeModeBinding) {
                            Text("Local Zeit").tag(TimeDisplayMode.local)
                            Text("UTC Zeit").tag(TimeDisplayMode.utc)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 160)

                        Text(
                            "Luftlinie "
                            + "\(Int(destination.directNM.rounded())) NM"
                        )
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FlybookColor.muted)
                    }
                }

                Divider()

                HStack(spacing: 14) {
                    compactDatePicker(
                        title: "HINFLUG",
                        selection: $outboundFlightDate
                    )

                    compactDatePicker(
                        title: "RÜCKFLUG",
                        selection: $returnFlightDate
                    )

                    Button("Heute") {
                        let today =
                            Calendar.current.startOfDay(
                                for: Date()
                            )
                        outboundFlightDate = today
                        returnFlightDate = today
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider()

                FlightTimePlanningRows(
                    outboundFlightDate: outboundFlightDate,
                    returnFlightDate: returnFlightDate,
                    outboundStartText: $outboundStartText,
                    desiredHomeArrivalText: $desiredHomeArrivalText,
                    outboundStops: $outboundStops,
                    returnStops: $returnStops,
                    flightTimes: destination.flightTimes,
                    outboundRouteWind: outboundRouteWindModel.wind,
                    returnRouteWind: returnRouteWindModel.wind,
                    outboundEDFZForecast: outboundEDFZWeatherModel.forecast,
                    returnEDFZForecast: returnEDFZWeatherModel.forecast,
                    outboundDestinationPressureMbar:
                        weatherModel.weather?.days.first?
                            .pressureMSLHPA
                            .map { Int($0.rounded()) },
                    returnDestinationPressureMbar:
                        weatherModel.weather?.days.dropFirst().first?
                            .pressureMSLHPA
                            .map { Int($0.rounded()) },
                    destination: destination,
                    destinationTimeZone:
                        DestinationTimeZone.value(
                            for: destination,
                            weatherTimeZone: weatherModel.weather?.timezone
                        ),
                    timeDisplayMode: timeDisplayMode,
                    tankStopMinutes: tankStopMinutes,
                    cruiseGroundSpeedKnots:
                        cruiseGroundSpeedKnots
                )
            }
        }
    }


    private func compactDatePicker(
        title: String,
        selection: Binding<Date>
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(FlybookColor.navy)

            DatePicker(
                "",
                selection: selection,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.field)
            .controlSize(.regular)
            .frame(width: 126)
        }
    }

    private var calculationSection: some View {
        FlybookCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("KALKULATION")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)

                CalculationRow(
                    title: "HINFLUG",
                    stopCount: outboundStops,
                    directNM: destination.directNM,
                    headwindKnots:
                        outboundRouteWindModel.wind?
                            .outboundHeadwindKnots,
                    tankStopMinutes: tankStopMinutes,
                    hourlyRateEUR: hourlyRateEUR,
                    vatPercent: vatPercent,
                    weekdayDiscountEnabled:
                        weekdayDiscountEnabled,
                    flightDate: outboundFlightDate,
                    cruiseGroundSpeedKnots:
                        cruiseGroundSpeedKnots,
                    fuelConsumptionPerHour:
                        fuelConsumptionPerHour,
                    reserveMinutes:
                        reserveMinutes,
                    usableFuel:
                        usableFuel,
                    prepaymentDiscount15To29Enabled:
                        prepaymentDiscount15To29Enabled,
                    prepaymentDiscount30PlusEnabled:
                        prepaymentDiscount30PlusEnabled
                )

                Divider()

                CalculationRow(
                    title: "START RÜCKFLUG",
                    stopCount: returnStops,
                    directNM: destination.directNM,
                    headwindKnots:
                        returnRouteWindModel.wind?
                            .returnHeadwindKnots,
                    tankStopMinutes: tankStopMinutes,
                    hourlyRateEUR: hourlyRateEUR,
                    vatPercent: vatPercent,
                    weekdayDiscountEnabled:
                        weekdayDiscountEnabled,
                    flightDate: returnFlightDate,
                    cruiseGroundSpeedKnots:
                        cruiseGroundSpeedKnots,
                    fuelConsumptionPerHour:
                        fuelConsumptionPerHour,
                    reserveMinutes:
                        reserveMinutes,
                    usableFuel:
                        usableFuel,
                    prepaymentDiscount15To29Enabled:
                        prepaymentDiscount15To29Enabled,
                    prepaymentDiscount30PlusEnabled:
                        prepaymentDiscount30PlusEnabled
                )

                Divider()

                CalculationTotalRow(
                    outboundStopCount: outboundStops,
                    returnStopCount: returnStops,
                    directNM: destination.directNM,
                    outboundHeadwindKnots:
                        outboundRouteWindModel.wind?
                            .outboundHeadwindKnots,
                    returnHeadwindKnots:
                        returnRouteWindModel.wind?
                            .returnHeadwindKnots,
                    hourlyRateEUR: hourlyRateEUR,
                    vatPercent: vatPercent,
                    weekdayDiscountEnabled:
                        weekdayDiscountEnabled,
                    outboundFlightDate: outboundFlightDate,
                    returnFlightDate: returnFlightDate,
                    cruiseGroundSpeedKnots:
                        cruiseGroundSpeedKnots,
                    fuelConsumptionPerHour:
                        fuelConsumptionPerHour,
                    reserveMinutes:
                        reserveMinutes,
                    usableFuel:
                        usableFuel,
                    prepaymentDiscount15To29Enabled:
                        prepaymentDiscount15To29Enabled,
                    prepaymentDiscount30PlusEnabled:
                        prepaymentDiscount30PlusEnabled
                )

            }
        }
        .frame(height: 360)
    }

    private var timeModeBinding: Binding<TimeDisplayMode> {
        Binding(
            get: { timeDisplayMode },
            set: { newMode in
                guard newMode != timeDisplayMode else { return }

                let oldZone = timeDisplayMode == .utc
                    ? TimeZone(secondsFromGMT: 0)!
                    : DestinationTimeZone.edfz
                let newZone = newMode == .utc
                    ? TimeZone(secondsFromGMT: 0)!
                    : DestinationTimeZone.edfz

                outboundStartText = convertedClock(
                    outboundStartText,
                    from: oldZone,
                    to: newZone
                )
                desiredHomeArrivalText = convertedClock(
                    desiredHomeArrivalText,
                    from: oldZone,
                    to: newZone
                )
                timeDisplayMode = newMode
            }
        )
    }

    private func convertedClock(
        _ clock: String,
        from sourceTimeZone: TimeZone,
        to destinationTimeZone: TimeZone
    ) -> String {
        guard let instant = FlightDateTime.instant(
            date: clock == outboundStartText ? outboundFlightDate : returnFlightDate,
            timeText: clock,
            timeZone: sourceTimeZone
        ) else {
            return clock
        }

        return FlightDateTime.clock(
            instant: instant,
            timeZone: destinationTimeZone
        )
    }

    private var weatherSection: some View {
        FlybookCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("WETTER AM ZIEL")
                        .font(.title3.bold())
                        .foregroundStyle(FlybookColor.navy)

        
                    Text("ICON-D2 bevorzugt")
                        .font(.caption.bold())
                        .foregroundStyle(FlybookColor.muted)

                    Button {
                        Task {
                            await weatherModel.load(
                                destination: destination,
                                targetInstants: weatherTargetInstants,
                                forceRefresh: true
                            )
                        }
                    } label: {
                        Image(
                            systemName:
                                "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Wetter aktualisieren")
                }

                Group {
                    if weatherModel.isLoading {
                        HStack {
                
                            ProgressView(
                                "Wetter wird geladen …"
                            )
                            .controlSize(.large)

                                        }
                        .frame(maxHeight: .infinity)
                    } else if let weather =
                        weatherModel.weather,
                        !weather.days.isEmpty
                    {
                        HStack(spacing: 0) {
                            LiveWeatherColumn(
                                day: weather.days[0]
                            ,
                                airportElevationFeet:
                                    destination.elevationFeet
                            )

                            Divider()

                            if weather.days.count > 1 {
                                LiveWeatherColumn(
                                    day: weather.days[1]
                                ,
                                airportElevationFeet:
                                    destination.elevationFeet
                            )
                            } else {
                                WeatherPlaceholderColumn(
                                    title: "RÜCKFLUG"
                                )
                            }
                        }
                    } else {
                        VStack(spacing: 6) {
                            Image(
                                systemName:
                                    "cloud.sun.rain"
                            )
                            .font(.system(size: 30))
                            .foregroundStyle(
                                FlybookColor.muted
                            )

                            Text(
                                weatherModel.errorMessage
                                ?? "Keine Wetterdaten verfügbar"
                            )
                            .font(
                                .system(
                                    size: 13,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                FlybookColor.muted
                            )
                            .multilineTextAlignment(.center)

                            Button("Erneut laden") {
                                Task {
                                    await weatherModel.load(
                                        destination: destination,
                                        targetInstants: weatherTargetInstants,
                                        forceRefresh: true
                                    )
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                Text("Modellprognose · kein offizielles Flugwetterbriefing")
                    .font(.system(size: 10))
                    .foregroundStyle(FlybookColor.muted)
            }
        }
    }

    private var airportSection: some View {
        FlybookCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("AIRPORT")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)

                    Spacer()

                    Text("N/A")
                        .font(.caption.bold())
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.gray))
                }

                HStack(alignment: .top, spacing: 8) {
                    AirportMetric(title: "Runway", value: "\(destination.runwayM) m")
                    AirportMetric(title: "Surface", value: destination.surface)
                    AirportMetric(title: "AVGAS", value: destination.avgas, fuelStatus: true)
                    AirportMetric(title: "UL91", value: destination.ul91, fuelStatus: true)
                    AirportMetric(title: "MOGAS", value: destination.mogas, fuelStatus: true)
                    AirportMetric(title: "PPR", value: destination.ppr)
                }
            }
        }
    }

    private var mapAndImageSection: some View {
        FlybookCard {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("EUROPA")
                        .font(.title3.bold())
                        .foregroundStyle(FlybookColor.navy)

                    DestinationMapView(
                        latitude: destination.latitude,
                        longitude: destination.longitude,
                        title: destination.name
                    )
                }
                .frame(maxWidth: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("LUFTBILD FLUGPLATZ")
                        .font(.title3.bold())
                        .foregroundStyle(FlybookColor.navy)

                    DestinationMapView(
                        latitude: destination.latitude,
                        longitude: destination.longitude,
                        title: destination.icao,
                        presentation: .airportAerial
                    )
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 430)
    }

    private var fiveDayForecastSection: some View {
        FlybookCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("WETTERVORHERSAGE 5 TAGE")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)

                    Spacer()

                    Text("ICON Seamless · DWD")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
                }

                if let forecast =
                    weatherModel.weather?.dailyForecast,
                   !forecast.isEmpty
                {
                    HStack(spacing: 10) {
                        ForEach(forecast.prefix(5)) {
                            day in
                            DailyForecastTile(day: day)
                        }
                    }
                } else if weatherModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    Text("5-Tage-Prognose nicht verfügbar")
                        .foregroundStyle(FlybookColor.muted)
                }
            }
        }
        .frame(height: 150)
    }
}
private struct DailyForecastTile: View {
    let day: DailyForecast

    var body: some View {
        VStack(spacing: 5) {
            Text(weekday)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FlybookColor.navy)

            Image(systemName: weatherSymbol)
                .font(.system(size: 27, weight: .medium))
                .symbolRenderingMode(.multicolor)
                .frame(height: 32)

            Text(
                day.maximumTemperatureCelsius.map {
                    String(format: "%.0f°", $0)
                } ?? "—"
            )
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(FlybookColor.navy)

        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.08))
        )
    }

    private var weekday: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"

        guard let date = parser.date(from: day.localDate) else {
            return day.localDate
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    private var weatherSymbol: String {
        guard let code = day.weatherCode else {
            return "questionmark.circle"
        }

        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67: return "cloud.rain.fill"
        case 71...77: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

private struct RouteWindSummary: View {
    let wind: RouteWind?
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wind")
                .foregroundStyle(FlybookColor.blue)

            if isLoading {
                Text("5.000-ft-Wind an der Streckenmitte wird geladen …")
            } else if let wind {
                Text(
                    "WIND MITTE 5.000 FT  ·  "
                    + String(format: "%03.0f° / %.0f kt", wind.directionDegrees, wind.speedKnots)
                    + "  ·  HIN " + componentText(wind.outboundHeadwindKnots)
                    + "  ·  RÜCK " + componentText(wind.returnHeadwindKnots)
                )
            } else {
                Text(errorMessage ?? "Windkompensation derzeit nicht verfügbar")
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(FlybookColor.navy)
        .lineLimit(1)
    }

    private func componentText(_ headwind: Double) -> String {
        if headwind >= 0 {
            return String(format: "GEGENWIND %.0f kt", headwind)
        }
        return String(format: "RÜCKENWIND %.0f kt", abs(headwind))
    }
}

private struct FlightTimePlanningRows: View {
    let outboundFlightDate: Date
    let returnFlightDate: Date

    @Binding var outboundStartText: String
    @Binding var desiredHomeArrivalText: String
    @Binding var outboundStops: Int
    @Binding var returnStops: Int

    let flightTimes: FlightTimes
    let outboundRouteWind: RouteWind?
    let returnRouteWind: RouteWind?
    let outboundEDFZForecast: EDFZForecast?
    let returnEDFZForecast: EDFZForecast?
    let outboundDestinationPressureMbar: Int?
    let returnDestinationPressureMbar: Int?
    let destination: Destination
    let destinationTimeZone: TimeZone
    let timeDisplayMode: TimeDisplayMode
    let tankStopMinutes: Int
    let cruiseGroundSpeedKnots: Double

    private var displayTimeZone: TimeZone {
        timeDisplayMode == .utc
            ? TimeZone(secondsFromGMT: 0)!
            : DestinationTimeZone.edfz
    }

    private var outboundTravelMinutes: Int {
        FlightMath.adjustedMinutes(
            directNM: destination.directNM,
            stopCount: outboundStops,
            headwindKnots: outboundRouteWind?.outboundHeadwindKnots,
            tankStopMinutes: tankStopMinutes,
            cruiseGroundSpeedKnots:
                cruiseGroundSpeedKnots
        )
    }

    private var returnTravelMinutes: Int {
        FlightMath.adjustedMinutes(
            directNM: destination.directNM,
            stopCount: returnStops,
            headwindKnots: returnRouteWind?.returnHeadwindKnots,
            tankStopMinutes: tankStopMinutes,
            cruiseGroundSpeedKnots:
                cruiseGroundSpeedKnots
        )
    }

    private var outboundStartInstant: Date? {
        FlightDateTime.instant(
            date: outboundFlightDate,
            timeText: outboundStartText,
            timeZone: displayTimeZone
        )
    }

    private var outboundArrivalInstant: Date? {
        outboundStartInstant?.addingTimeInterval(
            TimeInterval(outboundTravelMinutes * 60)
        )
    }

    private var homeArrivalInstant: Date? {
        FlightDateTime.instant(
            date: returnFlightDate,
            timeText: desiredHomeArrivalText,
            timeZone: displayTimeZone
        )
    }

    private var returnDepartureInstant: Date? {
        homeArrivalInstant?.addingTimeInterval(
            TimeInterval(-returnTravelMinutes * 60)
        )
    }

    private var outboundAirportSample: EDFZWeatherSample? {
        outboundEDFZForecast?.sample(nearestTo: outboundStartInstant)
    }

    private var homeArrivalAirportSample: EDFZWeatherSample? {
        returnEDFZForecast?.sample(nearestTo: homeArrivalInstant)
    }

    private var outboundStartCondition: LightCondition {
        SolarCalculator.lightCondition(
            at: outboundStartInstant,
            latitude: FlightDateTime.edfzLatitude,
            longitude: FlightDateTime.edfzLongitude,
            timeZone: DestinationTimeZone.edfz
        )
    }

    private var outboundArrivalCondition: LightCondition {
        SolarCalculator.lightCondition(
            at: outboundArrivalInstant,
            latitude: destination.latitude,
            longitude: destination.longitude,
            timeZone: destinationTimeZone
        )
    }

    private var returnDepartureCondition: LightCondition {
        SolarCalculator.lightCondition(
            at: returnDepartureInstant,
            latitude: destination.latitude,
            longitude: destination.longitude,
            timeZone: destinationTimeZone
        )
    }

    private var homeArrivalCondition: LightCondition {
        SolarCalculator.lightCondition(
            at: homeArrivalInstant,
            latitude: FlightDateTime.edfzLatitude,
            longitude: FlightDateTime.edfzLongitude,
            timeZone: DestinationTimeZone.edfz
        )
    }


    private func sunTexts(
        at instant: Date?,
        latitude: Double?,
        longitude: Double?,
        timeZone: TimeZone
    ) -> (String?, String?) {
        guard
            let instant,
            let latitude,
            let longitude,
            let events = SolarCalculator.events(
                forLocalDayContaining: instant,
                latitude: latitude,
                longitude: longitude,
                timeZone: timeZone
            )
        else {
            return (nil, nil)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"

        return (
            formatter.string(from: events.sunrise),
            formatter.string(from: events.sunset)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            FlightPlanningLine(
                directionTitle: "HINFLUG",
                showsETOPSHeader: true,
                stopCount: $outboundStops,
                travelMinutes: outboundTravelMinutes,
                directNM: destination.directNM,
                headwindKnots: outboundRouteWind?.outboundHeadwindKnots,
                tankStopMinutes: tankStopMinutes,
                cruiseGroundSpeedKnots:
                    cruiseGroundSpeedKnots,
                leadingSunriseText:
                    sunTexts(
                        at: outboundStartInstant,
                        latitude: FlightDateTime.edfzLatitude,
                        longitude: FlightDateTime.edfzLongitude,
                        timeZone: DestinationTimeZone.edfz
                    ).0,
                leadingSunsetText:
                    sunTexts(
                        at: outboundStartInstant,
                        latitude: FlightDateTime.edfzLatitude,
                        longitude: FlightDateTime.edfzLongitude,
                        timeZone: DestinationTimeZone.edfz
                    ).1,
                leadingPressureMbar:
                    outboundAirportSample?.pressureMSLHPA
                        .map { Int($0.rounded()) },
                trailingSunriseText:
                    sunTexts(
                        at: outboundArrivalInstant,
                        latitude: destination.latitude,
                        longitude: destination.longitude,
                        timeZone: destinationTimeZone
                    ).0,
                trailingSunsetText:
                    sunTexts(
                        at: outboundArrivalInstant,
                        latitude: destination.latitude,
                        longitude: destination.longitude,
                        timeZone: destinationTimeZone
                    ).1,
                trailingPressureMbar:
                    outboundDestinationPressureMbar,
                leading: {
                    EditableFlightTimeField(
                        title: "START EDFZ",
                        text: $outboundStartText,
                        symbol: "airplane.departure",
                        lightCondition:
                            outboundStartCondition,
                        airportWeather: outboundAirportSample
                    )
                },
                trailing: {
                    CalculatedFlightTime(
                        title: "ANKUNFT ZIEL",
                        value: FlightDateTime.clock(
                            instant: outboundArrivalInstant,
                            timeZone: timeDisplayMode == .utc
                                ? TimeZone(secondsFromGMT: 0)!
                                : destinationTimeZone
                        ),
                        symbol: "airplane.arrival",
                        lightCondition:
                            outboundArrivalCondition
                    )
                }
            )

            Divider()
                .padding(.vertical, 8)

            FlightPlanningLine(
                directionTitle: "RÜCKFLUG",
                showsETOPSHeader: true,
                stopCount: $returnStops,
                travelMinutes: returnTravelMinutes,
                directNM: destination.directNM,
                headwindKnots: returnRouteWind?.returnHeadwindKnots,
                tankStopMinutes: tankStopMinutes,
                cruiseGroundSpeedKnots:
                    cruiseGroundSpeedKnots,
                leadingSunriseText:
                    sunTexts(
                        at: returnDepartureInstant,
                        latitude: destination.latitude,
                        longitude: destination.longitude,
                        timeZone: destinationTimeZone
                    ).0,
                leadingSunsetText:
                    sunTexts(
                        at: returnDepartureInstant,
                        latitude: destination.latitude,
                        longitude: destination.longitude,
                        timeZone: destinationTimeZone
                    ).1,
                leadingPressureMbar:
                    returnDestinationPressureMbar,
                trailingSunriseText:
                    sunTexts(
                        at: homeArrivalInstant,
                        latitude: FlightDateTime.edfzLatitude,
                        longitude: FlightDateTime.edfzLongitude,
                        timeZone: DestinationTimeZone.edfz
                    ).0,
                trailingSunsetText:
                    sunTexts(
                        at: homeArrivalInstant,
                        latitude: FlightDateTime.edfzLatitude,
                        longitude: FlightDateTime.edfzLongitude,
                        timeZone: DestinationTimeZone.edfz
                    ).1,
                trailingPressureMbar:
                    homeArrivalAirportSample?.pressureMSLHPA
                        .map { Int($0.rounded()) },
                leading: {
                    CalculatedFlightTime(
                        title: "START ZIEL",
                        value: FlightDateTime.clock(
                            instant: returnDepartureInstant,
                            timeZone: timeDisplayMode == .utc
                                ? TimeZone(secondsFromGMT: 0)!
                                : destinationTimeZone
                        ),
                        symbol: "airplane.departure",
                        lightCondition:
                            returnDepartureCondition
                    )
                },
                trailing: {
                    EditableFlightTimeField(
                        title: "LANDUNG EDFZ",
                        text: $desiredHomeArrivalText,
                        symbol: "airplane.arrival",
                        lightCondition:
                            homeArrivalCondition,
                        airportWeather: homeArrivalAirportSample
                    )
                }
            )
        }
        .onChange(of: outboundStartText) { newValue in
            let filtered = TimeInput.filtered(newValue)

            if filtered != newValue {
                outboundStartText = filtered
            }
        }
        .onChange(of: desiredHomeArrivalText) { newValue in
            let filtered = TimeInput.filtered(newValue)

            if filtered != newValue {
                desiredHomeArrivalText = filtered
            }
        }
    }
}


private struct TimeContextInfo: View {
    let sunriseText: String?
    let sunsetText: String?
    let pressureMbar: Int?

    var body: some View {
        VStack(spacing: 2) {
            if let sunriseText, let sunsetText {
                HStack(spacing: 8) {
                    Label(
                        sunriseText,
                        systemImage: "sunrise.fill"
                    )

                    Label(
                        sunsetText,
                        systemImage: "sunset.fill"
                    )
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(FlybookColor.muted)
            }

            if let pressureMbar {
                Text("\(pressureMbar) mbar")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
            }
        }
        .frame(height: 28)
    }
}

private struct FlightPlanningLine<
    Leading: View,
    Trailing: View
>: View {
    let directionTitle: String
    let showsETOPSHeader: Bool
    @Binding var stopCount: Int
    let travelMinutes: Int
    let directNM: Double
    let headwindKnots: Double?
    let tankStopMinutes: Int
    let cruiseGroundSpeedKnots: Double
    let leadingSunriseText: String?
    let leadingSunsetText: String?
    let leadingPressureMbar: Int?
    let trailingSunriseText: String?
    let trailingSunsetText: String?
    let trailingPressureMbar: Int?

    @AppStorage(ETOPSSettingsKey.greenYellowMinutes)
    private var greenYellowMinutes =
        ETOPSScale.defaultGreenYellowMinutes

    @AppStorage(ETOPSSettingsKey.orangeRedMinutes)
    private var orangeRedMinutes =
        ETOPSScale.defaultOrangeRedMinutes

    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    private var selectedLegMinutes: Int {
        FlightMath.adjustedPerLegMinutes(
            directNM: directNM,
            stopCount: stopCount,
            headwindKnots: headwindKnots,
            tankStopMinutes: tankStopMinutes
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            StopCountSelector(selection: $stopCount)
                .frame(width: 98, height: 108)

            VStack(spacing: 5) {
                Text(directionTitle)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)

                HStack(alignment: .top, spacing: 4) {
                    VStack(spacing: 3) {
                        TimeContextInfo(
                            sunriseText: leadingSunriseText,
                            sunsetText: leadingSunsetText,
                            pressureMbar: leadingPressureMbar
                        )

                        leading
                    }
                    .frame(width: 174, alignment: .top)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FlybookColor.muted)
                        .frame(width: 18, height: 87)

                    VStack(spacing: 3) {
                        TimeContextInfo(
                            sunriseText: trailingSunriseText,
                            sunsetText: trailingSunsetText,
                            pressureMbar: trailingPressureMbar
                        )

                        trailing
                    }
                    .frame(width: 174, alignment: .top)
                }

                if let headwindKnots {
                    WindInfluenceLabel(headwindKnots: headwindKnots)
                }
            }

            VStack(spacing: 4) {
                Color.clear.frame(height: 15)

                TravelDurationBadge(minutes: travelMinutes)
                    .frame(width: 70, height: 58)
            }

            VStack(spacing: 5) {
                Text("ETOPS-\nPIPI")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(-1)
                    .frame(height: 24)

                Circle()
                    .fill(
                        ETOPSBand.color(
                            for: selectedLegMinutes,
                            greenYellowMinutes: greenYellowMinutes,
                            orangeRedMinutes: orangeRedMinutes
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                FlybookColor.navy.opacity(0.35),
                                lineWidth: 1
                            )
                    )
                    .frame(width: 16, height: 16)
            }
            .frame(width: 54)
            .help(
                "Farbe aus der berechneten Dauer des einzelnen Fluglegs"
            )
        }
    }
}




private struct CalculationTotalRow: View {
    let outboundStopCount: Int
    let returnStopCount: Int
    let directNM: Double
    let outboundHeadwindKnots: Double?
    let returnHeadwindKnots: Double?
    let hourlyRateEUR: Double
    let vatPercent: Double
    let weekdayDiscountEnabled: Bool
    let outboundFlightDate: Date
    let returnFlightDate: Date
    let cruiseGroundSpeedKnots: Double
    let fuelConsumptionPerHour: Double
    let reserveMinutes: Int
    let usableFuel: Double
    let prepaymentDiscount15To29Enabled: Bool
    let prepaymentDiscount30PlusEnabled: Bool

    private var outboundMinutes: Int {
        FlightMath.adjustedBlockMinutes(
            directNM: directNM,
            stopCount: outboundStopCount,
            headwindKnots: outboundHeadwindKnots,
            cruiseGroundSpeedKnots: cruiseGroundSpeedKnots
        )
    }

    private var returnMinutes: Int {
        FlightMath.adjustedBlockMinutes(
            directNM: directNM,
            stopCount: returnStopCount,
            headwindKnots: returnHeadwindKnots,
            cruiseGroundSpeedKnots: cruiseGroundSpeedKnots
        )
    }

    private var totalMinutes: Int {
        outboundMinutes + returnMinutes
    }

    private func weekday(_ date: Date) -> Bool {
        (2...6).contains(
            Calendar.current.component(.weekday, from: date)
        )
    }

    private func legCost(minutes: Int, date: Date) -> Double {
        let prepaymentFactor: Double

        if prepaymentDiscount15To29Enabled {
            prepaymentFactor = 0.75
        } else if prepaymentDiscount30PlusEnabled {
            prepaymentFactor = 0.85
        } else {
            prepaymentFactor = 1.0
        }

        let baseRate =
            hourlyRateEUR * prepaymentFactor

        let rate =
            weekdayDiscountEnabled && weekday(date)
                ? baseRate * 0.95
                : baseRate
        return Double(minutes) / 60.0 * rate
            * (1.0 + max(0, vatPercent) / 100.0)
    }

    private var totalRequiredFuel: Double {
        let blockFuel =
            Double(totalMinutes)
            * fuelConsumptionPerHour
            / 60.0

        let reserveFuel =
            fuelConsumptionPerHour
            * Double(reserveMinutes)
            / 60.0

        return blockFuel + reserveFuel
    }

    private var totalCost: Double {
        legCost(minutes: outboundMinutes, date: outboundFlightDate)
        + legCost(minutes: returnMinutes, date: returnFlightDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("GESAMT")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(FlybookColor.navy)

            HStack(spacing: 10) {
                totalBox(
                    title: "BLOCKZEIT GESAMT",
                    value: String(
                        format: "%d:%02d",
                        totalMinutes / 60,
                        totalMinutes % 60
                    )
                )

                totalBox(
                    title: "BENÖTIGTER KRAFTSTOFF",
                    value: String(
                        format: "%.1f",
                        totalRequiredFuel
                    )
                )

                totalBox(
                    title: "KOSTEN GESAMT",
                    value: totalCost.formatted(
                        .currency(code: "EUR")
                            .locale(Locale(identifier: "de_DE"))
                            .precision(.fractionLength(2))
                    )
                )
            }
        }
    }

    private func totalBox(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FlybookColor.muted)
            Text(value)
                .font(
                    .system(
                        size: 22,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .foregroundStyle(FlybookColor.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(FlybookColor.blue.opacity(0.12))
        )
    }
}

private struct CalculationRow: View {
    let title: String
    let stopCount: Int
    let directNM: Double
    let headwindKnots: Double?
    let tankStopMinutes: Int
    let hourlyRateEUR: Double
    let vatPercent: Double
    let weekdayDiscountEnabled: Bool
    let flightDate: Date
    let cruiseGroundSpeedKnots: Double
    let fuelConsumptionPerHour: Double
    let reserveMinutes: Int
    let usableFuel: Double
    let prepaymentDiscount15To29Enabled: Bool
    let prepaymentDiscount30PlusEnabled: Bool

    private var blockMinutes: Int {
        FlightMath.adjustedBlockMinutes(
            directNM: directNM,
            stopCount: stopCount,
            headwindKnots: headwindKnots,
            cruiseGroundSpeedKnots:
                cruiseGroundSpeedKnots
        )
    }

    private var isWeekday: Bool {
        let weekday = Calendar.current.component(
            .weekday,
            from: flightDate
        )
        return (2...6).contains(weekday)
    }

    private var discountApplies: Bool {
        weekdayDiscountEnabled && isWeekday
    }

    private var prepaymentFactor: Double {
        if prepaymentDiscount15To29Enabled {
            return 0.75
        }

        if prepaymentDiscount30PlusEnabled {
            return 0.85
        }

        return 1.0
    }

    private var netHourlyRateEUR: Double {
        let afterPrepayment =
            hourlyRateEUR * prepaymentFactor

        return discountApplies
            ? afterPrepayment * 0.95
            : afterPrepayment
    }

    private var costBeforeVATEUR: Double {
        Double(blockMinutes) / 60.0
            * netHourlyRateEUR
    }

    private var costEUR: Double {
        costBeforeVATEUR
            * (1.0 + max(0, vatPercent) / 100.0)
    }

    private var stopLabel: String {
        switch stopCount {
        case 0:
            return "Nonstop"
        case 1:
            return "1 Stopp"
        default:
            return "2 Stopps"
        }
    }

    private var blockTimeText: String {
        String(
            format: "%d:%02d",
            blockMinutes / 60,
            blockMinutes % 60
        )
    }

    private var requiredFuel: Double {
        let blockFuel =
            Double(blockMinutes)
            * fuelConsumptionPerHour
            / 60.0

        let reserveFuel =
            fuelConsumptionPerHour
            * Double(reserveMinutes)
            / 60.0

        return blockFuel + reserveFuel
    }

    private var requiredFuelText: String {
        String(format: "%.1f", requiredFuel)
    }

    private var fuelResultColor: Color {
        guard usableFuel > 0 else {
            return requiredFuel > 0
                ? .red
                : .green
        }

        let percentage =
            requiredFuel / usableFuel * 100.0

        if percentage < 90 {
            return .green
        }

        if percentage < 100 {
            return .yellow
        }

        return .red
    }

    private var costText: String {
        costEUR.formatted(
            .currency(code: "EUR")
                .locale(Locale(identifier: "de_DE"))
                .precision(.fractionLength(2))
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FlybookColor.navy)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(stopLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FlybookColor.muted)

                    if prepaymentDiscount15To29Enabled {
                        Text("25 % Vorauszahlungsrabatt")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.green)
                    } else if prepaymentDiscount30PlusEnabled {
                        Text("15 % Vorauszahlungsrabatt")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.green)
                    }

                    if discountApplies {
                        Text("5 % Wochentagsrabatt")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.green)
                    }
                }
            }

            HStack(spacing: 10) {
                valueBox(
                    title: "BLOCKZEIT",
                    value: blockTimeText
                )

                valueBox(
                    title: "BENÖTIGTER KRAFTSTOFF",
                    value: requiredFuelText,
                    valueColor: fuelResultColor
                )

                valueBox(
                    title: "KOSTEN",
                    value: costText
                )
            }
        }
    }

    private func valueBox(
        title: String,
        value: String,
        valueColor: Color = FlybookColor.navy
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FlybookColor.muted)

            Text(value)
                .font(
                    .system(
                        size: 22,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.08))
        )
    }
}

private struct WindInfluenceLabel: View {
    let headwindKnots: Double

    private var isHeadwind: Bool {
        headwindKnots >= 0
    }

    private var label: String {
        let value = Int(abs(headwindKnots).rounded())
        return isHeadwind
            ? "Gegenwind \(value) kt"
            : "Rückenwind \(value) kt"
    }

    var body: some View {
        Text(label)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(
                isHeadwind ? Color.red : Color.green
            )
            .lineLimit(1)
    }
}

private struct TravelDurationBadge: View {
    let minutes: Int

    var body: some View {
        VStack(spacing: 3) {
            Text(FlightMath.duration(minutes))
                .font(
                    .system(
                        size: 18,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .foregroundStyle(FlybookColor.blue)

            Text("REISEZEIT")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(FlybookColor.muted)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .background(FlybookColor.blue.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(FlybookColor.blue.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .help("Gesamtreisezeit für die gewählte Anzahl Zwischenstopps")
    }
}

private struct StopCountSelector: View {
    @Binding var selection: Int

    private let options: [(value: Int, label: String)] = [
        (0, "NONSTOP"),
        (1, "1 STOP"),
        (2, "2 STOPS")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(
                                selection == option.value
                                    ? FlybookColor.blue
                                    : Color.white
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        FlybookColor.navy,
                                        lineWidth: 1.5
                                    )
                            )
                            .frame(width: 16, height: 16)

                        Text(option.label)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(FlybookColor.navy)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .frame(height: 36)
                }
                .buttonStyle(.plain)
            }
        }
    }
}


private struct FlightTimeBox: View {
    let value: String
    let symbol: String
    let lightCondition: LightCondition
    var editable = false

    private var fillColor: Color {
        switch lightCondition {
        case .daylight, .unavailable:
            return Color.white
        case .civilTwilight:
            return Color.yellow.opacity(0.34)
        case .night:
            return Color.red.opacity(0.28)
        }
    }

    private var borderColor: Color {
        switch lightCondition {
        case .daylight:
            return FlybookColor.navy
        case .civilTwilight:
            return Color.orange
        case .night:
            return Color.red
        case .unavailable:
            return FlybookColor.muted
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))

            Text(value)
                .font(
                    .system(
                        size: 22,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .frame(width: 82)

            if editable {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(FlybookColor.muted)
                    .frame(width: 10)
            } else {
                Color.clear.frame(width: 10, height: 1)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(fillColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(FlybookColor.navy)
    }
}

private struct EditableFlightTimeField: View {
    let title: String
    @Binding var text: String
    let symbol: String
    let lightCondition: LightCondition
    let airportWeather: EDFZWeatherSample?

    @State private var isTimeEditorPresented = false
    @State private var selectedHour = 9
    @State private var selectedMinute = 30

    private var currentMinutes: Int {
        TimeInput.minutes(from: text) ?? 570
    }

    private func openTimeEditor() {
        let minutes = currentMinutes
        selectedHour = (minutes / 60) % 24
        selectedMinute = minutes % 60
        isTimeEditorPresented = true
    }

    private func applyTime() {
        text = String(
            format: "%02d:%02d",
            selectedHour,
            selectedMinute
        )
        isTimeEditorPresented = false
    }

    var body: some View {
        VStack(spacing: 4) {
            Button(action: openTimeEditor) {
                FlightTimeBox(
                    value: text,
                    symbol: symbol,
                    lightCondition: lightCondition,
                    editable: true
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 174, height: 43)
            .help("Uhrzeit auswählen")
            .popover(
                isPresented: $isTimeEditorPresented,
                arrowEdge: .bottom
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(FlybookColor.navy)

                    HStack(spacing: 8) {
                        Picker("Stunde", selection: $selectedHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(String(format: "%02d", hour))
                                    .tag(hour)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 82)

                        Text(":")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(FlybookColor.navy)

                        Picker("Minute", selection: $selectedMinute) {
                            ForEach(0..<60, id: \.self) { minute in
                                Text(String(format: "%02d", minute))
                                    .tag(minute)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 82)
                    }

                    HStack {
                        Button("Abbrechen") {
                            isTimeEditorPresented = false
                        }

                        Spacer()

                        Button("Übernehmen") {
                            applyTime()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(16)
                .frame(width: 230)
            }

            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(FlybookColor.muted)

            EDFZRunwayPressureRow(sample: airportWeather)
        }
        .foregroundStyle(FlybookColor.navy)
    }
}


private struct EDFZRunwayPressureRow: View {
    let sample: EDFZWeatherSample?

    private var runway: String {
        guard
            let direction = sample?.windDirectionDegrees,
            let speed = sample?.windSpeedKnots,
            speed >= 0.5
        else {
            return "—"
        }
        return EDFZRunway.activeRunway(
            windFromDegrees: direction,
            speedKnots: speed
        )
    }

    private var wind: String {
        guard
            let rawDirection = sample?.windDirectionDegrees,
            let rawSpeed = sample?.windSpeedKnots
        else {
            return "—/—"
        }

        var direction = Int(rawDirection.rounded()) % 360
        if direction == 0 && rawDirection > 0 {
            direction = 360
        }
        let speed = max(0, Int(rawSpeed.rounded()))
        return "\(direction)/\(speed)"
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "road.lanes")
                    .font(.system(size: 16, weight: .bold))
                Text(runway)
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(FlybookColor.navy)

            Text(wind)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(FlybookColor.muted)
                .lineLimit(1)
        }
        .frame(width: 174, height: 22, alignment: .center)
        .help("Aktive Piste und prognostizierter Wind in Grad/Knoten")
    }
}

private struct CalculatedFlightTime: View {
    let title: String
    let value: String
    let symbol: String
    let lightCondition: LightCondition

    var body: some View {
        VStack(spacing: 4) {
            FlightTimeBox(
                value: value,
                symbol: symbol,
                lightCondition: lightCondition
            )
            .frame(width: 174, height: 43)

            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(FlybookColor.muted)
        }
        .foregroundStyle(FlybookColor.navy)
    }
}

private struct WeatherPlaceholderColumn: View {
    let title: String

    var body: some View {
        VStack(spacing: 13) {
            Text(title)
                .font(.headline)
                .foregroundStyle(FlybookColor.navy)

            Text("12:00 LCL")
                .font(.caption)
                .foregroundStyle(FlybookColor.muted)

            Text("Wetterdaten werden\nbeim Abruf geladen")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FlybookColor.muted)
                .multilineTextAlignment(.center)
                .frame(height: 60)

            HStack {
                VStack {
                    Text("BODEN")
                    Image(systemName: "wind")
                    Text("N/A")
                }

                Spacer()

                VStack {
                    Text("5.000 FT AGL")
                    Image(systemName: "wind")
                    Text("N/A")
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(FlybookColor.navy)

            Text("Sunrise —  ·  Sunset —")
                .font(.caption)
                .foregroundStyle(FlybookColor.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
    }
}

private struct AirportMetric: View {
    let title: String
    let value: String
    var fuelStatus = false

    private var valueColor: Color {
        guard fuelStatus else { return FlybookColor.navy }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized == "ja" || normalized == "yes" { return .green }
        if normalized == "nein" || normalized == "no" { return .red }
        return FlybookColor.navy
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .bold))

            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(FlybookColor.navy)
        .frame(maxWidth: .infinity)
    }
}

private struct WeekendRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: "circle")
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            Text(value)
        }
        .foregroundStyle(FlybookColor.navy)
    }
}

private struct LiveWeatherColumn: View {
    let day: ForecastDay
    let airportElevationFeet: Double

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.displayDay)
                        .font(.system(size: 15, weight: .bold))

                    Text(displayDate)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FlybookColor.navy)

                    Text(day.localTime)
                        .font(.system(size: 10))
                        .foregroundStyle(FlybookColor.muted)
                }

                Spacer()

                FlightCategoryBadge(day: day)
            }

            weatherSummary

            Divider()
                .overlay(FlybookColor.line.opacity(0.85))

            windSummary

            densityAltitudeSummary

        }
        .foregroundStyle(FlybookColor.navy)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
    }

    private var weatherSummary: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(
                day.temperatureCelsius.map {
                    String(format: "%.0f°", $0)
                } ?? "—"
            )
            .font(.system(size: 27, weight: .bold))

            Image(systemName: weatherSymbol(day.weatherCode))
                .font(.system(size: 28, weight: .medium))
                .symbolRenderingMode(.multicolor)
                .frame(width: 38)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(weatherDescription(day.weatherCode))
                    .font(.system(size: 11, weight: .semibold))

            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.gray.opacity(0.10))
        )
    }

    private var windSummary: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(classicWindText)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(FlybookColor.navy)

            WindBarbShape(
                directionDegrees:
                    day.surfaceWind.directionDegrees ?? 0,
                speedKnots:
                    day.surfaceWind.speedKnots ?? 0
            )
            .stroke(
                day.surfaceWind.speedKnots == nil
                    ? FlybookColor.muted
                    : FlybookColor.navy,
                style: StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(width: 52, height: 32)
            .offset(y: -11)
        }
    }

    private var classicWindText: String {
        let direction = Int(
            day.surfaceWind.directionDegrees ?? 0
                .rounded()
        )
        let speed = Int(
            day.surfaceWind.speedKnots ?? 0
                .rounded()
        )
        let gust = Int(
            day.windGustKnots ?? 0
                .rounded()
        )

        let directionText = String(
            format: "%03d",
            direction
        )

        if gust > speed {
            return "\(directionText)/\(speed) gust \(gust)"
        }

        return "\(directionText)/\(speed)"
    }



    private var densityAltitudeSummary: some View {
        HStack {
            Text("DENSITY ALTITUDE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FlybookColor.muted)

            Spacer()

            Text(densityAltitudeText)
                .font(
                    .system(
                        size: 13,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .foregroundStyle(FlybookColor.navy)
        }
        .padding(.horizontal, 10)
    }

    private var densityAltitudeText: String {
        guard
            let temperature = day.temperatureCelsius,
            let pressure = day.pressureMSLHPA
        else {
            return "—"
        }

        let pressureAltitude =
            airportElevationFeet
            + (1013.25 - pressure) * 30.0

        let isaTemperature =
            15.0 - 1.98 * (pressureAltitude / 1000.0)

        let densityAltitude =
            pressureAltitude
            + 120.0 * (temperature - isaTemperature)

        return String(
            format: "%.0f ft",
            densityAltitude
        )
    }

    private var displayDate: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"

        guard let date = parser.date(from: day.localDate) else {
            return day.localDate
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    private func weatherSymbol(_ code: Int?) -> String {
        guard let code else { return "questionmark.circle" }
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67: return "cloud.rain.fill"
        case 71...77: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    private func weatherDescription(_ code: Int?) -> String {
        guard let code else { return "—" }
        switch code {
        case 0: return "Klar"
        case 1, 2: return "Leicht bewölkt"
        case 3: return "Bedeckt"
        case 45, 48: return "Nebel"
        case 51...57: return "Nieselregen"
        case 61...67: return "Regen"
        case 71...77: return "Schnee"
        case 80...82: return "Schauer"
        case 95...99: return "Gewitter"
        default: return "Wetter"
        }
    }
}

private struct FlightCategoryBadge: View {
    let day: ForecastDay

    private var color: Color {
        switch day.category {
        case .vfr: return .green
        case .mvfr: return .blue
        case .ifr: return .red
        case .lifr: return .purple
        case .unavailable: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(day.category.rawValue)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(color))

            if let categoryReason {
                Text(categoryReason)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var categoryReason: String? {
        guard day.category == .mvfr
            || day.category == .ifr
            || day.category == .lifr
        else {
            return nil
        }

        let visibilitySM = day.visibilityMeters.map {
            $0 / 1609.344
        }

        switch day.category {
        case .lifr:
            if let ceiling = day.ceilingFeetAGL, ceiling < 500 {
                return String(format: "Ceiling %.0f ft", ceiling)
            }
            if let visibilitySM, visibilitySM < 1 {
                return String(format: "Sicht %.1f SM", visibilitySM)
            }

        case .ifr:
            if let ceiling = day.ceilingFeetAGL, ceiling < 1000 {
                return String(format: "Ceiling %.0f ft", ceiling)
            }
            if let visibilitySM, visibilitySM < 3 {
                return String(format: "Sicht %.1f SM", visibilitySM)
            }

        case .mvfr:
            if let ceiling = day.ceilingFeetAGL, ceiling <= 3000 {
                return String(format: "Ceiling %.0f ft", ceiling)
            }
            if let visibilitySM, visibilitySM <= 5 {
                return String(format: "Sicht %.1f SM", visibilitySM)
            }

        default:
            break
        }

        return nil
    }
}

private struct WindBarbView: View {
    let title: String
    let wind: WindSample

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))

            WindBarbShape(
                directionDegrees: wind.directionDegrees ?? 0,
                speedKnots: wind.speedKnots ?? 0
            )
            .stroke(
                wind.speedKnots == nil ? FlybookColor.muted : FlybookColor.navy,
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 52, height: 42)

            Text(wind.speedKnots.map { String(format: "%.0f kt", $0) } ?? "N/A")
                .font(.system(size: 10, weight: .bold))
        }
    }
}

private struct WindBarbShape: Shape {
    let directionDegrees: Double
    let speedKnots: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY + 9)
        let length = min(rect.width, rect.height) * 0.72
        let radians = (directionDegrees - 90.0) * .pi / 180.0
        let tip = CGPoint(
            x: center.x + cos(radians) * length,
            y: center.y + sin(radians) * length
        )

        path.move(to: center)
        path.addLine(to: tip)

        let roundedSpeed = max(0, Int((speedKnots / 5.0).rounded()) * 5)
        var remaining = roundedSpeed
        var position = tip
        let backwards = CGVector(dx: -cos(radians) * 6, dy: -sin(radians) * 6)
        let barbAngle = radians + 60.0 * .pi / 180.0

        while remaining >= 50 {
            let next = CGPoint(x: position.x + backwards.dx * 2, y: position.y + backwards.dy * 2)
            let flag = CGPoint(x: position.x + cos(barbAngle) * 15, y: position.y + sin(barbAngle) * 15)
            path.move(to: position)
            path.addLine(to: flag)
            path.addLine(to: next)
            remaining -= 50
            position = next
        }

        while remaining >= 10 {
            let end = CGPoint(x: position.x + cos(barbAngle) * 14, y: position.y + sin(barbAngle) * 14)
            path.move(to: position)
            path.addLine(to: end)
            position = CGPoint(x: position.x + backwards.dx, y: position.y + backwards.dy)
            remaining -= 10
        }

        if remaining >= 5 {
            let end = CGPoint(x: position.x + cos(barbAngle) * 8, y: position.y + sin(barbAngle) * 8)
            path.move(to: position)
            path.addLine(to: end)
        }

        return path
    }
}

private struct ResourceImage: View {
    let name: String
    let extensionName: String
    let subdirectory: String
    let fallbackText: String

    var body: some View {
        Group {
            if let url = Bundle.module.url(
                forResource: name,
                withExtension: extensionName,
                subdirectory: subdirectory
            ),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                ZStack {
                    Color.gray.opacity(0.12)
                    Text(fallbackText)
                        .foregroundStyle(FlybookColor.muted)
                }
            }
        }
    }
}
