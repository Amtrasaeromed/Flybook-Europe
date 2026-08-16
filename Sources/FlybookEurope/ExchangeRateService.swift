import Foundation

struct CHFToEURExchangeRate: Codable, Equatable {
    /// Euro for one Swiss franc.
    let euroPerCHF: Double
    /// Reference date published by the ECB (`yyyy-MM-dd`).
    let referenceDate: String
    /// Time at which Flybook retrieved this quote.
    let fetchedAt: Date

    var localizedReferenceDate: String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.timeZone = TimeZone(secondsFromGMT: 0)
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: referenceDate) else {
            return referenceDate
        }
        let output = DateFormatter()
        output.locale = Locale(identifier: "de_DE")
        output.timeZone = TimeZone(secondsFromGMT: 0)
        output.dateFormat = "dd.MM.yyyy"
        return output.string(from: date)
    }
}

enum ECBExchangeRateParser {
    static func chfToEUR(from data: Data, fetchedAt: Date) -> CHFToEURExchangeRate? {
        let delegate = ECBExchangeRateXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(),
              let chfPerEUR = delegate.chfPerEUR,
              chfPerEUR.isFinite,
              chfPerEUR > 0,
              !delegate.referenceDate.isEmpty
        else { return nil }
        return CHFToEURExchangeRate(
            euroPerCHF: 1 / chfPerEUR,
            referenceDate: delegate.referenceDate,
            fetchedAt: fetchedAt
        )
    }
}

private final class ECBExchangeRateXMLDelegate: NSObject, XMLParserDelegate {
    var referenceDate = ""
    var chfPerEUR: Double?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if let time = attributeDict["time"], !time.isEmpty {
            referenceDate = time
        }
        if attributeDict["currency"] == "CHF",
           let text = attributeDict["rate"],
           let value = Double(text) {
            chfPerEUR = value
        }
    }
}

actor ExchangeRateService {
    static let shared = ExchangeRateService()

    private static let endpoint = URL(
        string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml"
    )!
    private static let cacheKey = "exchangeRate.ecb.chfToEur.v1"
    private var memoryCache: CHFToEURExchangeRate?

    func currentCHFToEUR(
        forceRefresh: Bool = false,
        now: Date = Date()
    ) async -> CHFToEURExchangeRate? {
        if memoryCache == nil {
            memoryCache = Self.loadCachedQuote()
        }
        if !forceRefresh,
           let quote = memoryCache,
           Calendar.current.isDate(quote.fetchedAt, inSameDayAs: now) {
            return quote
        }

        do {
            var request = URLRequest(url: Self.endpoint)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(
                "FlybookEurope/1.0 (+https://github.com/Amtrasaeromed/Flybook-Europe)",
                forHTTPHeaderField: "User-Agent"
            )
            let (data, response) = try await FlightNetwork.data(
                for: request,
                priority: .normal
            )
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let quote = ECBExchangeRateParser.chfToEUR(
                    from: data,
                    fetchedAt: now
                  )
            else { return nil }
            memoryCache = quote
            Self.store(quote)
            return quote
        } catch {
            // A stale rate must never silently become today's conversion.
            return nil
        }
    }

    private static func loadCachedQuote() -> CHFToEURExchangeRate? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            return nil
        }
        return try? JSONDecoder().decode(CHFToEURExchangeRate.self, from: data)
    }

    private static func store(_ quote: CHFToEURExchangeRate) {
        guard let data = try? JSONEncoder().encode(quote) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}

@MainActor
final class ExchangeRateViewModel: ObservableObject {
    @Published private(set) var chfToEUR: CHFToEURExchangeRate?
    @Published private(set) var isLoading = false

    func refreshIfNeeded(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        chfToEUR = await ExchangeRateService.shared.currentCHFToEUR(
            forceRefresh: forceRefresh
        )
        isLoading = false
    }
}
