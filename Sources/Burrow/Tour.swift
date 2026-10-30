import SwiftUI

/// `-tour <folder>`: walks through every page the way a person would and saves the window about
/// 30 times a second (JPEG frames plus an ffmpeg concat list with real timings), then quits.
/// `scripts/demo-video.sh` turns the frames into the README video. It only navigates: it never
/// starts a Mole action or a scan.
@MainActor
enum Tour {
    private static let steps: [(seconds: Double, step: @MainActor (AppModel) -> Void)] = [
        (3.5, { $0.page = .overview }),
        (3.5, { $0.page = .clean }),
        (3, { $0.page = .uninstall }),
        (3, { _ in UserDefaults.standard.set(true, forKey: "uninstall.showLeftovers") }),
        (2, { _ in UserDefaults.standard.set(false, forKey: "uninstall.showLeftovers") }),
        (3, { $0.page = .optimize }),
        (3.5, { $0.page = .analyze }),
        (3, { $0.page = .projects }),
        (3, { $0.page = .installers }),
        (3, { $0.page = .slim }),
        (3, { $0.page = .history }),
        (3, { $0.page = .settings }),
        (3, { $0.page = .overview }),
    ]

    static func start(_ model: AppModel, into folder: String) {
        let dir = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let writes = DispatchGroup()
        var times: [Date] = []
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let view = NSApp.windows.first(where: \.isVisible)?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                let url = dir.appendingPathComponent(String(format: "f%05d.jpg", times.count))
                times.append(Date())
                nonisolated(unsafe) let frame = rep
                DispatchQueue.global(qos: .userInitiated).async(group: writes) {
                    try? frame.representation(using: .jpeg, properties: [.compressionFactor: 0.95])?.write(to: url)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)

        var at = 0.8
        for (seconds, step) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { MainActor.assumeIsolated { step(model) } }
            at += seconds
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + at) {
            timer.invalidate()
            // Each frame lasts until the next one was taken, so the video keeps the real pace.
            var list = "ffconcat version 1.0\n"
            for i in times.indices {
                let next = i + 1 < times.count ? times[i + 1] : times[i].addingTimeInterval(1.0 / 30)
                list += String(format: "file f%05d.jpg\nduration %.4f\n", i, next.timeIntervalSince(times[i]))
            }
            try? list.write(to: dir.appendingPathComponent("frames.ffconcat"), atomically: true, encoding: .utf8)
            writes.notify(queue: .main) { NSApp.terminate(nil) }
        }
    }
}
