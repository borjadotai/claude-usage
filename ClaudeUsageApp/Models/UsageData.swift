import Foundation

struct UsageWindow: Sendable {
    let utilization: Double   // percentage 0-100
    let resetsAt: Date

    var resetDescription: String {
        let secs = resetsAt.timeIntervalSinceNow
        guard secs > 0 else { return "Resetting soon" }
        let h = Int(secs) / 3600
        let m = (Int(secs) % 3600) / 60
        if h >= 24 {
            let d = h / 24
            let rh = h % 24
            return "Resets in \(d)d \(rh)h"
        }
        return h > 0 ? "Resets in \(h)h \(m)m" : "Resets in \(m)m"
    }
}

struct ExtraUsage: Sendable {
    let isEnabled: Bool
    let monthlyLimit: Int
    let usedCredits: Double
}

struct UsageData: Sendable {
    let fiveHour: UsageWindow
    let sevenDay: UsageWindow
    let sevenDaySonnet: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let extraUsage: ExtraUsage?
    let fetchedAt: Date

    /// The most relevant utilization to show in menu bar (highest of 5h or 7d)
    var primaryUtilization: Double {
        max(fiveHour.utilization, sevenDay.utilization)
    }
}

enum UsageState: Sendable {
    case notLoggedIn
    case loading
    case loaded(UsageData)
    case error(String)
}
