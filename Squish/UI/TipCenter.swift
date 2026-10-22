import Observation
import SwiftUI
import UIKit

/// One calm toast at a time in the 80–86% band (VISUAL-TARGET §6.1), never during a press or the reveal.
/// Copy from UX-REVIEW-1 §6.3. One-time tips remember themselves in UserDefaults.
struct SquishTip: Identifiable, Equatable {
    enum Kind: String { case safety, sound, coach, openUp, dragDown }

    let kind: Kind
    let id: Int
    let title: String
    let detail: String
    let symbol: String
    let accent: Color
    /// Auto-dismiss after this many seconds once on screen; nil = until its condition clears.
    let lifetime: Double?

    static func == (lhs: SquishTip, rhs: SquishTip) -> Bool { lhs.id == rhs.id }
}

@MainActor
@Observable
final class TipCenter {
    private(set) var current: SquishTip?
    @ObservationIgnored private var counter = 0
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    // MARK: Catalogue

    func safety() -> SquishTip {
        make(.safety, "ON-SCREEN ONLY", "Never close your phone on real things.", "hand.raised.fill", Theme.stamp, nil)
    }

    func sound(soundOff: Bool) -> SquishTip {
        make(.sound, "SOUND ON?",
             soundOff ? "Sound is off in Settings. Squish is half sound." : "Squish is half sound. Unmute for the full crunch.",
             "speaker.wave.2.fill", Theme.yellow, 4)
    }

    func coach(_ line: String) -> SquishTip {
        make(.coach, "SLOW IS SMOOTH", line, "tortoise.fill", Theme.yellow, 2.5)
    }

    func openUp() -> SquishTip {
        make(.openUp, "OPEN IT UP", "Open your iPhone flat to start a press.", "arrow.up.and.down", Theme.graphite, nil)
    }

    func dragDown() -> SquishTip {
        make(.dragDown, "DRAG DOWN", "Pull the press down. Slower is nicer.", "hand.draw.fill", Theme.yellow, nil)
    }

    // MARK: Presenting

    func show(_ tip: SquishTip) {
        dismissTask?.cancel()
        current = tip
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: "\(tip.title.capitalized). \(tip.detail)")
        }
        if let lifetime = tip.lifetime {
            let id = tip.id
            dismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(lifetime))
                guard !Task.isCancelled, let self, self.current?.id == id else { return }
                self.current = nil
            }
        }
    }

    func dismiss(_ kind: SquishTip.Kind) {
        guard current?.kind == kind else { return }
        dismissTask?.cancel()
        current = nil
    }

    func dismissAll() {
        dismissTask?.cancel()
        current = nil
    }

    var isShowing: Bool { current != nil }

    // MARK: One-time memory

    static func hasShown(_ kind: SquishTip.Kind) -> Bool {
        UserDefaults.standard.bool(forKey: "squish.tip.\(kind.rawValue)")
    }

    static func markShown(_ kind: SquishTip.Kind) {
        UserDefaults.standard.set(true, forKey: "squish.tip.\(kind.rawValue)")
    }

    private func make(_ kind: SquishTip.Kind, _ title: String, _ detail: String, _ symbol: String, _ accent: Color,
                      _ lifetime: Double?) -> SquishTip {
        counter += 1
        return SquishTip(kind: kind, id: counter, title: title, detail: detail, symbol: symbol, accent: accent, lifetime: lifetime)
    }
}
