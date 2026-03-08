import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem
    private var cancellable: AnyCancellable?
    private var currentState: UsageState = .loading
    private var popover: NSPopover

    var onRefresh: (() -> Void)?
    var onRelogin: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        super.init()

        popover.delegate = self

        if let button = statusItem.button {
            button.image = Self.claudeIcon()
            button.imagePosition = .imageLeading
            button.title = " …"
            button.target = self
            button.action = #selector(togglePopover)
        }

        updatePopoverContent()
    }

    func bind(to fetcher: UsageFetcher) {
        cancellable = fetcher.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.update(state: state)
            }
    }

    private func update(state: UsageState) {
        currentState = state
        updateButton(state: state)
        if popover.isShown {
            updatePopoverContent()
        }
    }

    private func updateButton(state: UsageState) {
        guard let button = statusItem.button else { return }
        switch state {
        case .notLoggedIn:
            button.title = " ?"
        case .loading:
            button.title = " …"
        case .loaded(let data):
            let pct = Int(data.fiveHour.utilization)
            let color: NSColor = pct < 50
                ? NSColor(red: 0.1, green: 0.6, blue: 0.2, alpha: 1.0)
                : (pct < 80
                    ? NSColor(red: 0.85, green: 0.5, blue: 0.0, alpha: 1.0)
                    : NSColor(red: 0.75, green: 0.1, blue: 0.1, alpha: 1.0))
            button.image = Self.claudeIcon(color: color)
            button.title = " \(pct)%"
        case .error:
            button.title = " !"
        }
    }

    private func updatePopoverContent() {
        let view = PopoverContentView(
            state: currentState,
            onRefresh: { [weak self] in self?.onRefresh?() },
            onRelogin: { [weak self] in
                self?.popover.close()
                self?.onRelogin?()
            },
            onQuit: { NSApp.terminate(nil) }
        )
        let host = NSHostingController(rootView: view)
        host.view.fittingSize  // force layout
        popover.contentSize = host.view.fittingSize
        popover.contentViewController = host
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.close()
        } else if let button = statusItem.button {
            updatePopoverContent()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    static func claudeIcon(color: NSColor? = nil) -> NSImage {
        let s: CGFloat = 16
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            let cx = rect.midX, cy = rect.midY
            let rays: [(angle: CGFloat, len: CGFloat)] = [
                (-90, 6.5), (-55, 5.5), (-20, 6.0), (15, 5.8), (45, 6.2),
                (80, 5.5), (115, 6.0), (150, 5.8), (185, 5.2), (225, 5.5),
            ]
            let strokeColor = color ?? NSColor.black
            ctx.setLineCap(.round)
            ctx.setStrokeColor(strokeColor.cgColor)
            ctx.setFillColor(strokeColor.cgColor)
            ctx.setLineWidth(1.8)
            for r in rays {
                let a = r.angle * .pi / 180
                ctx.move(to: CGPoint(x: cx + cos(a) * 1.2, y: cy + sin(a) * 1.2))
                ctx.addLine(to: CGPoint(x: cx + cos(a) * r.len, y: cy + sin(a) * r.len))
            }
            ctx.strokePath()
            ctx.fillEllipse(in: CGRect(x: cx - 1.5, y: cy - 1.5, width: 3, height: 3))
            return true
        }
        img.isTemplate = color == nil
        return img
    }
}

// MARK: - SwiftUI Popover Content

struct PopoverContentView: View {
    let state: UsageState
    let onRefresh: () -> Void
    let onRelogin: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch state {
            case .notLoggedIn:
                statusRow(icon: "person.crop.circle.badge.questionmark", text: "Not logged in", color: .secondary)
            case .loading:
                statusRow(icon: "arrow.triangle.2.circlepath", text: "Fetching usage…", color: .secondary)
            case .loaded(let data):
                loadedContent(data: data)
            case .error(let msg):
                statusRow(icon: "exclamationmark.triangle", text: msg, color: .red)
            }

            Divider().padding(.vertical, 4)

            HStack(spacing: 12) {
                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Spacer()

                Button(action: onRelogin) {
                    Label("Re-login", systemImage: "person.crop.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button(action: onQuit) {
                    Label("Quit", systemImage: "xmark.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .padding(.top, 4)
        }
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func loadedContent(data: UsageData) -> some View {
        HStack {
            Image(systemName: "chart.bar.fill")
                .foregroundColor(.accentColor)
            Text("Claude Usage")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(data.fetchedAt, style: .relative)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)

        usageRow(title: "5-Hour Window", percent: data.fiveHour.utilization, resetText: data.fiveHour.resetDescription)

        Divider().padding(.horizontal, 16).padding(.vertical, 6)

        usageRow(title: "7-Day Window", percent: data.sevenDay.utilization, resetText: data.sevenDay.resetDescription)

        if let sonnet = data.sevenDaySonnet, sonnet.utilization > 0 {
            modelRow(name: "Sonnet", percent: sonnet.utilization)
        }
        if let opus = data.sevenDayOpus, opus.utilization > 0 {
            modelRow(name: "Opus", percent: opus.utilization)
        }

        if let extra = data.extraUsage, extra.isEnabled {
            Divider().padding(.horizontal, 16).padding(.vertical, 6)
            extraUsageRow(extra: extra)
        }
    }

    private func usageRow(title: String, percent: Double, resetText: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(percent))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(colorFor(percent: percent))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colorFor(percent: percent))
                        .frame(width: geo.size.width * min(CGFloat(percent) / 100.0, 1.0))
                }
            }
            .frame(height: 6)
            Text(resetText).font(.system(size: 10)).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
    }

    private func modelRow(name: String, percent: Double) -> some View {
        HStack {
            Text("  \(name)").font(.system(size: 11)).foregroundColor(.secondary)
            Spacer()
            Text("\(Int(percent))%").font(.system(size: 11, design: .rounded)).foregroundColor(colorFor(percent: percent))
        }
        .padding(.horizontal, 16).padding(.top, 2)
    }

    private func extraUsageRow(extra: ExtraUsage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Extra Usage").font(.system(size: 12, weight: .medium))
                Spacer()
                if extra.usedCredits > 0 {
                    Text(String(format: "$%.2f", extra.usedCredits / 100.0))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                } else {
                    Text("None used").font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            Text(String(format: "Monthly limit: $%.0f", Double(extra.monthlyLimit) / 100.0))
                .font(.system(size: 10)).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
    }

    private func statusRow(icon: String, text: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(color)
            Text(text).font(.system(size: 13)).foregroundColor(color)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func colorFor(percent: Double) -> Color {
        percent < 50 ? .green : (percent < 80 ? .orange : .red)
    }
}
