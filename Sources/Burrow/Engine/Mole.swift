import Foundation

/// Locates the Mole engine bundled inside the app and runs its non-interactive commands.
enum Mole {
    /// `Contents/Resources/mole` inside the app; `Vendor/mole` when run with `swift run`.
    static let root: URL = {
        if let res = Bundle.main.resourceURL?.appendingPathComponent("mole"),
           FileManager.default.fileExists(atPath: res.appendingPathComponent("mole").path) {
            return res
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Vendor/mole")
    }()

    static var executable: String { root.appendingPathComponent("mole").path }

    static var version: String {
        (try? String(contentsOf: root.appendingPathComponent("VERSION"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
    }

    /// Environment for every Mole run: a predictable PATH and no inherited terminal quirks.
    static func environment(tty: Bool) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        env["TERM"] = tty ? "xterm-256color" : "dumb"
        if !tty { env["NO_COLOR"] = "1" }
        env.removeValue(forKey: "MO_DEBUG")
        return env
    }

    /// Every Mole process the app started, so none outlives the app.
    nonisolated(unsafe) private static var live = Set<Process>()
    private static let liveLock = NSLock()

    static func track(_ p: Process) { liveLock.withLock { _ = live.insert(p) } }
    static func untrack(_ p: Process) { liveLock.withLock { _ = live.remove(p) } }
    nonisolated(unsafe) private static var livePIDs = Set<pid_t>()
    static func track(pid: pid_t) { liveLock.withLock { _ = livePIDs.insert(pid) } }
    static func untrack(pid: pid_t) { liveLock.withLock { _ = livePIDs.remove(pid) } }

    static func terminateAll() {
        liveLock.withLock {
            live.forEach { if $0.isRunning { $0.terminate() } }
            livePIDs.forEach { kill($0, SIGTERM) }
        }
    }

    /// Runs Mole to completion with pipes and returns stdout. Cancelling the task stops Mole.
    static func capture(_ args: [String]) async throws -> Data {
        let p = Process()
        return try await withTaskCancellationHandler {
            try await run(p, args)
        } onCancel: {
            if p.isRunning { p.terminate() }
        }
    }

    private static func run(_ p: Process, _ args: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = args
            p.environment = environment(tty: false)
            p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch { cont.resume(throwing: error); return }
            track(p)
            DispatchQueue.global().async {
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                untrack(p)
                cont.resume(returning: data)
            }
        }
    }

    static func json<T: Decodable>(_ type: T.Type, _ args: [String]) async throws -> T {
        let data = try await capture(args)
        // Mole may print a banner before the JSON; decode from the first brace or bracket.
        let start = data.firstIndex(where: { $0 == UInt8(ascii: "{") || $0 == UInt8(ascii: "[") }) ?? data.startIndex
        return try JSONDecoder().decode(T.self, from: data[start...])
    }

    /// Streams stdout line by line until the process ends or `stop()` is called.
    final class LineStream {
        private let process = Process()

        init(_ args: [String], onLine: @escaping (String) -> Void) {
            process.executableURL = URL(fileURLWithPath: Mole.executable)
            process.arguments = args
            process.environment = Mole.environment(tty: false)
            let out = Pipe()
            process.standardOutput = out
            process.standardError = FileHandle.nullDevice
            var buffer = Data()
            out.fileHandleForReading.readabilityHandler = { h in
                let chunk = h.availableData
                if chunk.isEmpty { h.readabilityHandler = nil; return }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                    buffer.removeSubrange(buffer.startIndex...nl)
                    DispatchQueue.main.async { onLine(line) }
                }
            }
            try? process.run()
            Mole.track(process)
        }

        func stop() {
            if process.isRunning { process.terminate() }
            Mole.untrack(process)
        }
        deinit { stop() }
    }
}
