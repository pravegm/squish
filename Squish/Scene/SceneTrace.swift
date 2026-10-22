import Foundation
import QuartzCore

/// Startup timing marks for CI (demo runs only): `SQUISH-T scene <step> at X.XXs`, measured from the first mark
/// (the start of `PressScene.init`, which runs just before the director's launch clock starts).
/// Nonisolated so detached build tasks can mark their own steps.
enum SceneTrace {
    static let enabled: Bool = DemoScenario.current != nil
    static let origin: Double = CACurrentMediaTime()

    static func mark(_ step: String) {
        guard enabled else { return }
        print(String(format: "SQUISH-T scene %@ at %.2fs", step, CACurrentMediaTime() - origin))
    }

    /// Runs `body` and logs how long it took (main-thread cost hunting).
    @discardableResult
    static func measure<T>(_ step: String, _ body: () throws -> T) rethrows -> T {
        guard enabled else { return try body() }
        let start = CACurrentMediaTime()
        let result = try body()
        print(String(format: "SQUISH-T scene %@ took %.0f ms (at %.2fs)", step, (CACurrentMediaTime() - start) * 1000,
                     CACurrentMediaTime() - origin))
        return result
    }
}
