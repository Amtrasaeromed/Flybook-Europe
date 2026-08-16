import Foundation

/// Gemeinsame, bewusst schlanke Netzwerksitzung fuer flugrelevante Daten.
///
/// Eigene fachliche Caches entscheiden, wann Daten noch aktuell sind. Die
/// Sitzung begrenzt lediglich parallele Verbindungen, damit bei schwachem
/// Empfang kein Anfragestapel einen einzelnen Anbieter ueberlastet.
enum FlightNetwork {
    static var userAgent: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "development"
        return "FlybookEurope/\(version) "
            + "(+https://github.com/Amtrasaeromed/Flybook-Europe)"
    }
    private static let gate = FlightRequestGate(maximumConcurrentRequests: 4)
    private static let openMeteoGate = OpenMeteoCircuitBreaker.shared
    private static let metNorwayCache = METNorwayResponseCache.shared

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 35
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }()

    static func data(
        from url: URL,
        priority: FlightNetworkPriority = .normal
    ) async throws -> (Data, URLResponse) {
        await gate.acquire(priority: priority)
        do {
            try Task.checkCancellation()
            let result = try await session.data(from: url)
            await gate.release()
            return result
        } catch {
            await gate.release()
            throw error
        }
    }

    static func data(
        for request: URLRequest,
        priority: FlightNetworkPriority = .normal
    ) async throws
        -> (Data, URLResponse)
    {
        await gate.acquire(priority: priority)
        do {
            try Task.checkCancellation()
            let result = try await session.data(for: request)
            await gate.release()
            return result
        } catch {
            await gate.release()
            throw error
        }
    }

    /// Open-Meteo uses a shared free quota. Once the provider answers with
    /// HTTP 429, every Flybook weather path observes the same persisted
    /// cooldown instead of trying another endpoint or another batch.
    static func openMeteoData(
        from url: URL,
        priority: FlightNetworkPriority = .normal
    ) async throws -> (Data, URLResponse) {
        try await openMeteoGate.checkAvailability()
        let result = try await data(from: url, priority: priority)
        if let response = result.1 as? HTTPURLResponse,
           response.statusCode == 429 {
            await openMeteoGate.registerRateLimit(response: response)
            throw OpenMeteoAccessError.rateLimited
        }
        return result
    }

    static func metNorwayData(
        from url: URL,
        priority: FlightNetworkPriority = .normal
    ) async throws -> Data {
        try await metNorwayCache.data(from: url, priority: priority)
    }
}

enum OpenMeteoAccessError: Error {
    case rateLimited
}

actor OpenMeteoCircuitBreaker {
    static let shared = OpenMeteoCircuitBreaker()

    private let defaultsKey = "weather.openMeteoBlockedUntil"
    private var blockedUntil: Date?

    init(defaults: UserDefaults = .standard) {
        let stored = defaults.double(forKey: defaultsKey)
        blockedUntil = stored > 0
            ? Date(timeIntervalSince1970: stored)
            : nil
    }

    func checkAvailability(now: Date = Date()) throws {
        guard let blockedUntil else { return }
        if blockedUntil <= now {
            self.blockedUntil = nil
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return
        }
        throw OpenMeteoAccessError.rateLimited
    }

    func registerRateLimit(
        response: HTTPURLResponse,
        now: Date = Date()
    ) {
        let retryDate = Self.retryDate(
            header: response.value(forHTTPHeaderField: "Retry-After"),
            now: now
        ) ?? Self.startOfNextUTCDay(after: now)
        blockedUntil = max(retryDate, now.addingTimeInterval(15 * 60))
        UserDefaults.standard.set(
            blockedUntil?.timeIntervalSince1970,
            forKey: defaultsKey
        )
    }

    static func retryDate(header: String?, now: Date) -> Date? {
        guard let header else { return nil }
        if let seconds = TimeInterval(header.trimmingCharacters(
            in: .whitespacesAndNewlines
        )), seconds > 0 {
            return now.addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: header)
    }

    static func startOfNextUTCDay(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: today)!
            .addingTimeInterval(5 * 60)
    }
}

private actor METNorwayResponseCache {
    static let shared = METNorwayResponseCache()

    private struct Entry: Codable {
        let data: Data
        let retrievedAt: Date
        let expiresAt: Date
        let lastModified: String?
    }

    private var entries: [String: Entry] = [:]
    private var running: [String: Task<Data, Error>] = [:]
    private var didLoad = false

    func data(
        from url: URL,
        priority: FlightNetworkPriority
    ) async throws -> Data {
        loadIfNeeded()
        let key = url.absoluteString
        if let entry = entries[key], entry.expiresAt > Date() {
            return entry.data
        }
        if let task = running[key] { return try await task.value }
        let previous = entries[key]
        let task = Task<Data, Error> {
            var request = URLRequest(url: url)
            request.setValue(
                FlightNetwork.userAgent,
                forHTTPHeaderField: "User-Agent"
            )
            if let lastModified = previous?.lastModified {
                request.setValue(
                    lastModified,
                    forHTTPHeaderField: "If-Modified-Since"
                )
            }
            let (downloaded, response) = try await FlightNetwork.data(
                for: request,
                priority: priority
            )
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            let now = Date()
            let payload: Data
            let retrievedAt: Date
            if http.statusCode == 304, let previous {
                payload = previous.data
                retrievedAt = previous.retrievedAt
            } else {
                guard (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                payload = downloaded
                retrievedAt = now
            }
            let entry = Entry(
                data: payload,
                retrievedAt: retrievedAt,
                expiresAt: Self.httpDate(
                    http.value(forHTTPHeaderField: "Expires")
                ) ?? now.addingTimeInterval(30 * 60),
                lastModified: http.value(forHTTPHeaderField: "Last-Modified")
                    ?? previous?.lastModified
            )
            self.store(entry, for: key)
            return payload
        }
        running[key] = task
        do {
            let result = try await task.value
            running[key] = nil
            return result
        } catch {
            running[key] = nil
            throw error
        }
    }

    private func store(_ entry: Entry, for key: String) {
        entries[key] = entry
        let oldestUsefulDate = Date().addingTimeInterval(-24 * 60 * 60)
        entries = entries.filter { $0.value.expiresAt >= oldestUsefulDate }
        save()
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let data = try? Data(contentsOf: cacheURL()),
              let saved = try? JSONDecoder().decode(
                  [String: Entry].self,
                  from: data
              )
        else { return }
        let oldestUsefulDate = Date().addingTimeInterval(-24 * 60 * 60)
        entries = saved.filter { $0.value.expiresAt >= oldestUsefulDate }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: cacheURL(), options: .atomic)
    }

    private func cacheURL() -> URL {
        let root = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let directory = root
            .appendingPathComponent("Flybook Europe", isDirectory: true)
            .appendingPathComponent("WeatherCache", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("met-norway-http.json")
    }

    private static func httpDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }
}

enum FlightNetworkPriority: Int, Sendable {
    case low = 0
    case normal = 1
    case high = 2
}

private actor FlightRequestGate {
    private struct Waiter {
        let priority: FlightNetworkPriority
        let order: UInt64
        let continuation: CheckedContinuation<Void, Never>
    }

    private let maximumConcurrentRequests: Int
    private var activeRequests = 0
    private var nextOrder: UInt64 = 0
    private var waiters: [Waiter] = []

    init(maximumConcurrentRequests: Int) {
        self.maximumConcurrentRequests = maximumConcurrentRequests
    }

    func acquire(priority: FlightNetworkPriority) async {
        guard activeRequests >= maximumConcurrentRequests else {
            activeRequests += 1
            return
        }

        let order = nextOrder
        nextOrder &+= 1
        await withCheckedContinuation { continuation in
            waiters.append(
                Waiter(
                    priority: priority,
                    order: order,
                    continuation: continuation
                )
            )
        }
    }

    func release() {
        guard !waiters.isEmpty else {
            activeRequests = max(0, activeRequests - 1)
            return
        }

        let nextIndex = waiters.indices.max { first, second in
            let lhs = waiters[first]
            let rhs = waiters[second]
            if lhs.priority != rhs.priority {
                return lhs.priority.rawValue < rhs.priority.rawValue
            }
            return lhs.order > rhs.order
        }!
        let next = waiters.remove(at: nextIndex)
        // Der frei gewordene Slot wird direkt weitergereicht; activeRequests
        // bleibt dadurch unveraendert und kann die Obergrenze nie uebersteigen.
        next.continuation.resume()
    }
}
