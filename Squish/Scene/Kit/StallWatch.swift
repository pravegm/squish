import Foundation
import QuartzCore

#if DEBUG
/// Demo runs only (CI's simulator passes): a watchdog for the main thread. A background thread checks a heartbeat the
/// main run loop beats every 0.25 s; when it has been silent for `threshold` seconds it interrupts the main thread
/// (SIGUSR2) and the main thread prints its own call stack, `SQUISH-STALL …`, then carries on. Repeats every
/// `repeatEvery` seconds of the same stall, so a long stall shows where it is spending its time. Launch QA P0: the Duo
/// pass built the jelly's view in 145 s on the main thread, while the same code took 217 ms on the iPhone simulator.
enum StallWatch {
    static let threshold: Double = 2
    static let repeatEvery: Double = 6

    /// What the main thread said it was doing last (a breadcrumb, printed with every stall).
    nonisolated(unsafe) static var step = "launch"
    nonisolated(unsafe) private static var lastBeat = CACurrentMediaTime()
    nonisolated(unsafe) private static var started = false
    nonisolated(unsafe) private static var mainThread: pthread_t?
    nonisolated(unsafe) private static var stalledSince: Double?

    /// Starts the watch (once). Call on the main thread.
    static func start() {
        guard !started, DemoScenario.current != nil, Thread.isMainThread else { return }
        started = true
        mainThread = pthread_self()
        signal(SIGUSR2) { _ in
            let stack = Thread.callStackSymbols.prefix(40).joined(separator: "\n  ")
            print("SQUISH-STALL main stack (step: \(StallWatch.step)):\n  \(stack)")
        }
        let beat = Timer(timeInterval: 0.25, repeats: true) { _ in StallWatch.lastBeat = CACurrentMediaTime() }
        RunLoop.main.add(beat, forMode: .common)
        let watcher = Thread {
            var lastReport = 0.0
            while true {
                Thread.sleep(forTimeInterval: 0.5)
                let now = CACurrentMediaTime()
                let silent = now - lastBeat
                if silent < threshold {
                    if let since = stalledSince {
                        print(String(format: "SQUISH-STALL over after %.1fs (step: %@)", now - since, step))
                        stalledSince = nil
                    }
                    continue
                }
                if stalledSince == nil { stalledSince = lastBeat }
                guard now - lastReport >= repeatEvery, let main = mainThread else { continue }
                lastReport = now
                print(String(format: "SQUISH-STALL main silent %.1fs (step: %@)", silent, step))
                pthread_kill(main, SIGUSR2)
            }
        }
        watcher.name = "StallWatch"
        watcher.qualityOfService = .utility
        watcher.start()
    }
}
#else
enum StallWatch {
    static var step: String {
        get { "" }
        set { _ = newValue }
    }
    static func start() {}
}
#endif
