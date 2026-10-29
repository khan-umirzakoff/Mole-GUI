import Foundation
import Darwin

/// A Mole run that did not end cleanly: it exited with an error code or was stopped.
struct MoleError: LocalizedError {
    let code: Int32
    let message: String

    var errorDescription: String? {
        message.isEmpty ? "Mole stopped with code \(code)." : message
    }
}

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
        env.removeValue(forKey: "MOLE_DRY_RUN")
        return env
    }

    // MARK: - Process bookkeeping

    /// Every Mole process the app started, so none outlives the app.
    nonisolated(unsafe) private static var livePIDs = Set<pid_t>()
    private static let liveLock = NSLock()

    static func track(pid: pid_t) { liveLock.withLock { _ = livePIDs.insert(pid) } }
    static func untrack(pid: pid_t) { liveLock.withLock { _ = livePIDs.remove(pid) } }

    /// Stops every Mole process the app started, for good: Burrow is going away and nothing
    /// may keep running (or keep waiting at a prompt) without it. Interactive Mole scripts trap
    /// TERM and HUP, so whatever survives a short grace period is killed.
    static func terminateAll() {
        let roots = liveLock.withLock { livePIDs }
        // Collect the whole tree first: children move to launchd once their parent is gone.
        let all = roots.flatMap(tree)
        guard !all.isEmpty else { return }
        all.forEach { kill($0, SIGHUP); kill($0, SIGTERM) }
        usleep(400_000)
        all.forEach { if kill($0, 0) == 0 { kill($0, SIGKILL) } }
    }

    /// Sends a signal to a process and everything it started. Mole is a shell script that
    /// runs helpers (`find`, `du`, the Go binaries); stopping only the shell would orphan them.
    static func signalTree(_ pid: pid_t, _ signal: Int32) {
        tree(pid).forEach { kill($0, signal) }
    }

    /// A process and all its descendants, deepest first.
    private static func tree(_ pid: pid_t) -> [pid_t] {
        guard pid > 0 else { return [] }
        return children(of: pid).flatMap(tree) + [pid]
    }

    private static func children(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 256)
        let bytes = proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }
        return Array(buffer.prefix(Int(bytes) / MemoryLayout<pid_t>.size)).filter { $0 > 0 }
    }

    // MARK: - Pipes

    /// Runs Mole to completion with pipes and returns stdout. `onLine` receives each stdout
    /// line on the main actor as it arrives. A non-zero exit throws `MoleError`; cancelling
    /// the task stops Mole and everything it started.
    static func capture(_ args: [String], onLine: (@MainActor (String) -> Void)? = nil) async throws -> Data {
        let p = Process()
        return try await withTaskCancellationHandler {
            try await run(p, args, onLine: onLine)
        } onCancel: {
            if p.isRunning { signalTree(p.processIdentifier, SIGTERM) }
        }
    }

    private static func run(_ p: Process, _ args: [String], onLine: (@MainActor (String) -> Void)?) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = args
            p.environment = environment(tty: false)
            p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch { cont.resume(throwing: error); return }
            let pid = p.processIdentifier
            track(pid: pid)

            // stderr is drained on its own queue so a chatty Mole can never block on a full pipe.
            let errGroup = DispatchGroup()
            nonisolated(unsafe) var errData = Data()
            DispatchQueue.global().async(group: errGroup) { errData = err.fileHandleForReading.readDataToEndOfFile() }

            DispatchQueue.global().async {
                let handle = out.fileHandleForReading
                var all = Data(), pending = Data()
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    all.append(chunk)
                    guard let onLine else { continue }
                    pending.append(chunk)
                    while let nl = pending.firstIndex(of: 0x0A) {
                        let line = String(decoding: pending[pending.startIndex..<nl], as: UTF8.self)
                        pending.removeSubrange(pending.startIndex...nl)
                        DispatchQueue.main.async { MainActor.assumeIsolated { onLine(line) } }
                    }
                }
                p.waitUntilExit()
                errGroup.wait()
                untrack(pid: pid)
                if p.terminationReason == .exit && p.terminationStatus == 0 {
                    cont.resume(returning: all)
                } else {
                    let code = p.terminationReason == .uncaughtSignal ? 128 + p.terminationStatus : p.terminationStatus
                    let text = String(decoding: errData.isEmpty ? all : errData, as: UTF8.self)
                    cont.resume(throwing: MoleError(code: code, message: TerminalText.lines(text).last ?? ""))
                }
            }
        }
    }

    static func json<T: Decodable>(_ type: T.Type, _ args: [String]) async throws -> T {
        let data = try await capture(args)
        // Mole may print a banner before the JSON; decode from the first brace or bracket.
        let start = data.firstIndex(where: { $0 == UInt8(ascii: "{") || $0 == UInt8(ascii: "[") }) ?? data.startIndex
        return try JSONDecoder().decode(T.self, from: data[start...])
    }
}
