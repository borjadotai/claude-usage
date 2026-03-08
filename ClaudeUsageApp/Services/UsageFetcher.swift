import Combine
import Foundation

@MainActor
final class UsageFetcher: NSObject, ObservableObject {
    @Published private(set) var state: UsageState = .loading

    private var sessionKey: String?
    private var orgId: String?
    private var pollTimer: Timer?
    private var failureCount = 0

    private let pollIntervals: [TimeInterval] = [300, 600, 1200, 3600]

    func markNotLoggedIn() {
        state = .notLoggedIn
    }

    func start(sessionKey: String) {
        print("[Fetcher] Starting with key prefix: \(sessionKey.prefix(15))...")
        self.sessionKey = sessionKey
        state = .loading
        fetchUsage()
    }

    func refresh() {
        print("[Fetcher] Manual refresh")
        guard sessionKey != nil else { return }
        state = .loading
        fetchUsage()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func fetchUsage() {
        guard let sessionKey else {
            state = .error("No session key")
            return
        }

        Task {
            do {
                // Cache org ID across fetches
                if orgId == nil {
                    orgId = try await fetchOrganizationId(sessionKey: sessionKey)
                    print("[Fetcher] Got org ID: \(orgId!)")
                }

                let url = URL(string: "https://claude.ai/api/organizations/\(orgId!)/usage")!
                let data = try await makeRequest(url: url, sessionKey: sessionKey)
                let usage = try parseUsageResponse(data)
                print("[Fetcher] 5h: \(usage.fiveHour.utilization)%, 7d: \(usage.sevenDay.utilization)%")
                failureCount = 0
                state = .loaded(usage)
                schedulePoll()
            } catch FetchError.unauthorized {
                print("[Fetcher] Session expired")
                NotificationCenter.default.post(name: .sessionExpired, object: nil)
            } catch {
                print("[Fetcher] Error: \(error)")
                failureCount += 1
                state = .error(error.localizedDescription)
                schedulePoll()
            }
        }
    }

    private func fetchOrganizationId(sessionKey: String) async throws -> String {
        let url = URL(string: "https://claude.ai/api/organizations")!
        let data = try await makeRequest(url: url, sessionKey: sessionKey)
        guard let orgs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let firstOrg = orgs.first,
              let uuid = firstOrg["uuid"] as? String else {
            throw FetchError.parseError("Could not parse organization ID")
        }
        return uuid
    }

    private func parseUsageResponse(_ data: Data) throws -> UsageData {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FetchError.parseError("Invalid JSON")
        }

        guard let fiveHour = parseWindow(json["five_hour"]),
              let sevenDay = parseWindow(json["seven_day"]) else {
            throw FetchError.parseError("Missing five_hour or seven_day")
        }

        let sevenDaySonnet = parseWindow(json["seven_day_sonnet"])
        let sevenDayOpus = parseWindow(json["seven_day_opus"])

        var extraUsage: ExtraUsage? = nil
        if let extra = json["extra_usage"] as? [String: Any] {
            extraUsage = ExtraUsage(
                isEnabled: extra["is_enabled"] as? Bool ?? false,
                monthlyLimit: extra["monthly_limit"] as? Int ?? 0,
                usedCredits: extra["used_credits"] as? Double ?? 0
            )
        }

        return UsageData(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            sevenDaySonnet: sevenDaySonnet,
            sevenDayOpus: sevenDayOpus,
            extraUsage: extraUsage,
            fetchedAt: Date()
        )
    }

    private func parseWindow(_ value: Any?) -> UsageWindow? {
        guard let dict = value as? [String: Any],
              let utilization = dict["utilization"] as? Double,
              let resetStr = dict["resets_at"] as? String else {
            return nil
        }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let resetDate = fmt.date(from: resetStr) ?? Date().addingTimeInterval(5 * 3600)
        return UsageWindow(utilization: utilization, resetsAt: resetDate)
    }

    // MARK: - HTTP

    private func makeRequest(url: URL, sessionKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.networkError("Invalid response")
        }

        print("[Fetcher] \(url.path) -> HTTP \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw FetchError.unauthorized
        case 429:
            throw FetchError.rateLimited
        default:
            throw FetchError.httpError(httpResponse.statusCode)
        }
    }

    private func schedulePoll() {
        pollTimer?.invalidate()
        let interval = pollIntervals[min(failureCount, pollIntervals.count - 1)]
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetchUsage()
            }
        }
        pollTimer?.tolerance = 30
    }
}

enum FetchError: LocalizedError {
    case unauthorized, cloudflareChallenge, rateLimited
    case httpError(Int)
    case networkError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Session expired"
        case .cloudflareChallenge: return "Cloudflare challenge"
        case .rateLimited: return "Rate limited"
        case .httpError(let code): return "HTTP \(code)"
        case .networkError(let msg): return msg
        case .parseError(let msg): return msg
        }
    }
}

extension Notification.Name {
    static let sessionExpired = Notification.Name("com.claudeusage.sessionExpired")
}
