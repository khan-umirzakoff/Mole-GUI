import AppKit
import SwiftUI

/// Notices an app being deleted while Burrow runs and offers what it left behind in a small panel
/// at the top of the screen. Moving them to the Trash goes through the same fresh scan the
/// Leftovers list uses.
@MainActor
final class RemovalWatcher {
    /// The Settings switch, on by default. While on, Burrow keeps running after its window closes.
    static let enabledKey = "offerLeftovers"
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    private let store: LeftoverStore
    private var stream: FSEventStreamRef?
    /// Ids already offered in this removal; forgotten when the app comes back.
    private var offered = Set<String>()
    private var panel: NSPanel?
    private var shown = Set<String>()

    init(store: LeftoverStore) { self.store = store }

    /// FSEvents, not a folder watch: it sees apps inside vendor folders and folders made later.
    /// The watcher lives as long as the app, so the stream holds it unretained.
    func start() {
        store.watchApps()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            let watcher = Unmanaged<RemovalWatcher>.fromOpaque(info!).takeUnretainedValue()
            MainActor.assumeIsolated { _ = Task { await watcher.check() } }
        }
        // 1.5 s latency: a move fires several events, looked at once things settle.
        guard let stream = FSEventStreamCreate(nil, callback, &context,
                                               ["/Applications", home + "/Applications", home + "/.Trash"] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.5,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func check() async {
        await store.refreshIfAppsChanged()
        offered.formIntersection(store.removed.keys)
        let current = Set((store.leftovers ?? []).map(\.id))
        // An offer whose app came back (or whose files went) is no longer true.
        if panel != nil, shown.isDisjoint(with: current) { hide() }
        offerPending()
    }

    private func offerPending() {
        guard Self.enabled, panel == nil else { return }
        let fresh = (store.leftovers ?? []).filter { store.removed[$0.bundleID.lowercased()] != nil && !offered.contains($0.id) }
        guard !fresh.isEmpty else { return }
        offered.formUnion(fresh.map(\.id))
        show(fresh)
    }

    private func show(_ leftovers: [Leftover]) {
        let view = RemovalOffer(leftovers: leftovers, removedAt: leftovers.map { store.removed[$0.bundleID.lowercased()] },
                                clean: { [store] in
                                    let failed = await store.trash(leftovers)
                                    let gone = leftovers.flatMap(\.items).filter { !FileManager.default.fileExists(atPath: $0.path) }
                                    return (gone.map(\.bytes).reduce(0, +), failed.count)
                                },
                                close: { [weak self] in self?.hide() })
        let host = NSHostingView(rootView: view.padding(30).preferredColorScheme(.dark))
        host.frame.size = host.fittingSize
        let panel = NSPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        guard let screen = NSScreen.main?.visibleFrame else { return }
        // Top right, just under the menu bar; the padding holds the card's glow.
        let end = NSPoint(x: screen.maxX - host.frame.width + 12, y: screen.maxY - host.frame.height + 22)
        let still = Motion.reduced
        panel.setFrameOrigin(still ? end : NSPoint(x: end.x, y: end.y + 16))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(end)
        }
        self.panel = panel
        shown = Set(leftovers.map(\.id))
    }

    private func hide() {
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
            if !Motion.reduced { panel.animator().setFrameOrigin(NSPoint(x: panel.frame.minX + 16, y: panel.frame.minY)) }
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            // Apps deleted while this panel was up get their own offer now.
            MainActor.assumeIsolated { self?.offerPending() }
        })
    }
}

private struct RemovalOffer: View {
    let leftovers: [Leftover]
    let removedAt: [String?]
    /// Moves them to the Trash; returns the bytes that went and how many items could not.
    let clean: () async -> (moved: Int64, failed: Int)
    let close: () -> Void

    private enum Step { case offer, cleaning, done(moved: Int64, failed: Int) }
    @ViewState private var step = Step.offer
    @ViewState private var hovering = false

    private var bytes: Int64 { leftovers.map(\.bytes).reduce(0, +) }
    private var title: String {
        leftovers.count == 1 ? "\(name(0)) was removed" : "\(leftovers.count) apps were removed"
    }
    private var detail: String {
        switch step {
        case .offer, .cleaning:
            let kinds = Set(leftovers.flatMap(\.kinds)).map(\.rawValue).sorted().joined(separator: ", ").lowercased()
            return "It left \(bytes.bytesText) behind: \(kinds)."
        case .done(_, let failed) where failed > 0:
            return "\(failed) item\(failed == 1 ? "" : "s") could not be moved. Open Burrow to see them."
        case .done(let moved, _) where moved == 0:
            return "Nothing was moved: the app is back, or its files are in use again."
        case .done(let moved, _):
            return "Moved \(moved.bytesText) to the Trash. You can put it back from there."
        }
    }

    /// The app as it now sits in the Trash, for its icon.
    private var icon: String? {
        guard leftovers.count == 1 else { return nil }
        if let app = leftovers[0].trashedApp { return app }
        guard let old = removedAt[0] else { return nil }
        let trashed = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            .appendingPathComponent((old as NSString).lastPathComponent).path
        return FileManager.default.fileExists(atPath: trashed) ? trashed : nil
    }

    private func name(_ i: Int) -> String {
        if let path = removedAt[i] { return ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
        return leftovers[i].name
    }

    var body: some View {
        GlowCard(glow: .ember, style: .rim, padding: 18) {
            HStack(spacing: 14) {
                if let app = icon {
                    AppIcon(path: app, size: 44)
                } else {
                    Image(systemName: "shippingbox").font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Glow.ember.color)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Glow.ember.color.opacity(0.16)))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                    Text(detail).caption().lineLimit(3)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 210, alignment: .leading)
                Spacer(minLength: 4)
                switch step {
                case .offer:
                    VStack(spacing: 8) {
                        Button { cleanUp() } label: { Text("Move to Trash").frame(width: 96) }.buttonStyle(.pill)
                        Button(action: close) { Text("Not now").frame(width: 96) }.buttonStyle(.pillSecondary)
                    }
                    .fixedSize()
                case .cleaning:
                    ProgressView().controlSize(.small).frame(width: 120)
                case .done:
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.accent)
                        .frame(width: 120)
                }
            }
        }
        .frame(width: 450)
        .fixedSize(horizontal: false, vertical: true)
        // A close button on hover, as on a notification.
        .overlay(alignment: .topLeading) {
            if hovering, case .offer = step {
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18))
                        .symbolRenderingMode(.palette).foregroundStyle(.black, .white)
                }
                .buttonStyle(.plain).offset(x: -6, y: -6)
                .accessibilityLabel("Close")
            }
        }
        .onHover { hovering = $0 }
        // Gone after a while if nobody answers; the Leftovers list still has them.
        .task {
            try? await Task.sleep(for: .seconds(45))
            if case .offer = step { close() }
        }
    }

    private func cleanUp() {
        step = .cleaning
        Task {
            let result = await clean()
            step = .done(moved: result.moved, failed: result.failed)
            try? await Task.sleep(for: .seconds(result.failed == 0 && result.moved > 0 ? 2.5 : 6))
            close()
        }
    }
}
