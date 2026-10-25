import Foundation
import Testing
@testable import Squish

/// Launch QA round (press engineer): trace files, the pending sealed press, shut hysteresis, holding, slam / Perfect
/// across input rates, arming after a quick reopen, bad hinge samples, and hinge presence on the cover.
@MainActor
struct LaunchQATests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("squish-qa-\(UUID().uuidString)",
                                                                                 isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func trace(_ kind: ObjectKind = .egg) -> PressTrace {
        PressTrace(kind: kind, variant: PressVariant(kind: kind, seed: 7),
                   samples: [.init(time: 0, angle: 180, closed: false), .init(time: 1, angle: 5, closed: true)],
                   usesVirtualHinge: false, config: .standard)
    }

    // MARK: 7. Trace files are deleted with their specimens

    @Test func traceStoreDeletesAndPrunes() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TraceStore(directory: dir)
        let keep = UUID(), drop = UUID(), stray = UUID()
        store.save(trace(), for: keep)
        store.save(trace(), for: drop)
        store.save(trace(), for: stray)
        try "x".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        #expect(store.load(drop) != nil)
        TraceStore.delete(drop, in: dir)
        #expect(store.load(drop) == nil)
        TraceStore.delete(UUID(), in: dir)   // no file: a no-op
        #expect(TraceStore.prune(keeping: [keep], in: dir) == 1)
        #expect(store.load(keep) != nil && store.load(stray) == nil)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("notes.txt").path))
    }
}
