import Foundation

/// Gemeinsame, bewusst schlanke Netzwerksitzung fuer flugrelevante Daten.
///
/// Eigene fachliche Caches entscheiden, wann Daten noch aktuell sind. Die
/// Sitzung begrenzt lediglich parallele Verbindungen, damit bei schwachem
/// Empfang kein Anfragestapel einen einzelnen Anbieter ueberlastet.
enum FlightNetwork {
    private static let gate = FlightRequestGate(maximumConcurrentRequests: 4)

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
