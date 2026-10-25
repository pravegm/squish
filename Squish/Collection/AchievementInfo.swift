import Foundation

/// Player-facing copy for achievements (toasts, Settings). Game Center titles are configured
/// in App Store Connect with the same wording; IDs are `Achievement.gameCenterID`.
extension Achievement {
    var title: String {
        switch self {
        case .firstSquish: "First Squish"
        case .perfectionist: "Perfectionist"
        case .midas: "Midas"
        case .whatsInside: "What's Inside?"
        case .patience: "Patience"
        case .collector: "Collector"
        case .theSecret: "The Secret"
        case .popStar: "Pop Star"
        case .steadyHands: "Steady Hands"
        case .fullSet: "Full Set"
        }
    }

    var detail: String {
        switch self {
        case .firstSquish: "Specimen №0001. The first of many."
        case .perfectionist: "Perfect Squishes on 5 different things."
        case .midas: "Pressed a golden one. 1 in 50."
        case .whatsInside: "Found two different surprises."
        case .patience: "One press, over 30 seconds. Very zen."
        case .collector: "All 10 pressed. Shelf complete."
        case .theSecret: "Met The Unsquishable. It won."
        case .popStar: "500 bubbles popped. Lifetime."
        case .steadyHands: "Ten Perfect Squishes. Steady."
        case .fullSet: "Every object in one wing. Very curatorial."
        }
    }

    /// The Achievements tab's line before it's earned: how to get it, in plain words.
    var hint: String {
        switch self {
        case .firstSquish: "Press anything. Anything at all."
        case .perfectionist: "A Perfect Squish on 5 different things."
        case .midas: "Find a golden one. 1 in 50 presses."
        case .whatsInside: "Find two different surprises inside things."
        case .patience: "Keep one press going for 30 seconds."
        case .collector: "Press all 10 objects."
        case .theSecret: "Some things don't squish…"
        case .popStar: "Pop 500 bubbles, lifetime."
        case .steadyHands: "Ten Perfect Squishes, any objects."
        case .fullSet: "Press every object in one museum wing."
        }
    }

    /// Hidden until earned in Game Center, and only teased here.
    var isSecret: Bool { self == .theSecret }

    var symbolName: String {
        switch self {
        case .firstSquish: "1.circle.fill"
        case .perfectionist: "sparkles"
        case .midas: "crown.fill"
        case .whatsInside: "gift.fill"
        case .patience: "hourglass"
        case .collector: "square.grid.3x3.fill"
        case .theSecret: "questionmark.circle.fill"
        case .popStar: "circle.grid.3x3.fill"
        case .steadyHands: "hand.raised.fill"
        case .fullSet: "building.columns.fill"
        }
    }
}

/// Specimen copy shared by the cards, the share image and VoiceOver.
extension SpecimenRecord {
    var numberLabel: String { String(format: "№%04ld", number) }

    /// The hinge angle the object gave at, only when a real hinge made the press (and never for The Unsquishable,
    /// which doesn't give). A touch press's `failureAngle` is the engine's virtual θ, meaningless on a phone with no
    /// hinge, so every card shows tonnage instead (FOLD-REVIEW-5 N6).
    var hingeFailureAngle: Int? {
        guard madeOnHinge, kind != .unsquishable, let failureAngle else { return nil }
        return Int(failureAngle.rounded())
    }

    /// True when the object gave during the press (it has a failure point), whatever drove it.
    var gaveWay: Bool { kind != .unsquishable && failureAngle != nil }

    /// Short "where it gave" tag for one-line labels: `AT 48 TONS`, nil if it never gave. Never a hinge angle: people
    /// care how hard they pressed, not the degrees (EXPERIENCE-REVIEW-1 #4, UX-AUDIT-2 #8).
    var gaveAtTag: String? {
        gaveWay ? "AT \(tons) TONS" : nil
    }

    /// Two SF Mono data lines (VISUAL-TARGET §6.8): `CRUSHED AT 48 TONS` / `24 POPS · 8.4 S`; `PEAK 48 TONS` when
    /// nothing gave. Tonnage only, whatever drove the press (`hingeFailureAngle` stays for diagnostics).
    var labelLines: [String] {
        let first: String
        if gaveWay {
            first = "CRUSHED AT \(tons) TONS"
        } else {
            first = "PEAK \(tons) TONS"
        }
        let second = kind.breaksLine(fractureCount: fractureCount) + String(format: " · %.1f S", duration)
        return [first, second]
    }

    /// The stamp's words: the Unsquishable wins (bible §4).
    var stampText: String { kind == .unsquishable ? "PRESS 0 – BALL 1" : "PRESSED" }

    struct Trait: Identifiable, Equatable {
        enum Tone { case perfect, golden, surprise, neutral }
        var id: String { text }
        let text: String
        let systemImage: String
        let tone: Tone
    }

    /// Golden first, then Perfect, surprise; a slam is shown neutrally (never as a reward, bible §2).
    var traits: [Trait] {
        var traits: [Trait] = []
        if variant.isGolden { traits.append(Trait(text: "GOLDEN", systemImage: "crown.fill", tone: .golden)) }
        if isPerfect { traits.append(Trait(text: "PERFECT SQUISH", systemImage: "sparkles", tone: .perfect)) }
        if let surprise = variant.surprise {
            traits.append(Trait(text: surprise.title, systemImage: "gift.fill", tone: .surprise))
        }
        if wasSlammed { traits.append(Trait(text: "SLAM", systemImage: "bolt.fill", tone: .neutral)) }
        if reversals >= 2 { traits.append(Trait(text: "PUMPED ×\(reversals)", systemImage: "arrow.up.arrow.down", tone: .neutral)) }
        return traits
    }

    /// The whole card as one VoiceOver sentence.
    var accessibilitySentence: String {
        var parts: [String] = ["Specimen number \(number), \(kind.displayName)"]
        if kind == .unsquishable {
            parts.append("press nil, ball one")
            parts.append("peak \(tons) tons")
        } else if gaveWay {
            parts.append("crushed at \(tons) tons")
        } else {
            parts.append("peak \(tons) tons")
        }
        parts.append(kind.breaksLine(fractureCount: fractureCount).replacingOccurrences(of: " · ", with: ", ").lowercased())
        parts.append(String(format: "pressed in %.1f seconds", duration))
        let traitWords = traits.map { $0.text.lowercased().replacingOccurrences(of: "×", with: "times ") }
        var sentence = parts.joined(separator: ", ") + "."
        if !traitWords.isEmpty { sentence += " " + traitWords.joined(separator: ", ").capitalizedFirst + "." }
        sentence += " " + flavourLine
        return sentence
    }
}

fileprivate extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Unlock hints with live progress (UX-REVIEW-1 P1-13): "SQUISH 3 DIFFERENT THINGS · 1/3".
extension CollectionStore {
    func progressHint(for kind: ObjectKind) -> String {
        switch kind.unlockRule {
        case .open:
            return ""
        case .squishDifferentKinds(let count):
            return "Squish \(count) different things · \(min(stats.squishedKinds.count, count))/\(count)"
        case .totalPresses(let count):
            return "Squish \(count) times · \(min(totalPresses, count))/\(count)"
        case .perfectSquish:
            return "Press slowly. Never ease off."
        case .allOthers:
            // Shorter than `unlockHint` ("Some things refuse to be squished…"), which truncated in the tabletop
            // Shelf's narrow secret slot as "SOME THINGS REFUSE TO BE S…" (FOLD-REVIEW-7 N6). Two lines there.
            return Self.secretSlotHint
        }
    }

    /// The secret slot's teaser on the Shelf: two short lines at the 5-column width ("SOME THINGS" / "WON'T SQUISH…").
    nonisolated static let secretSlotHint = "Some things won't squish…"

    /// Plain unlock progress for the Tray and the press room's "Next unlock" line: what to do, how far along.
    struct UnlockProgress: Equatable {
        /// "press 3 different things".
        var task: String
        var done: Int
        var total: Int
        /// "press 3 different things · 1/3".
        var line: String { "\(task) · \(min(done, total))/\(total)" }
        var fraction: Double { total > 0 ? min(Double(done) / Double(total), 1) : 0 }
    }

    func unlockProgress(for kind: ObjectKind) -> UnlockProgress? {
        switch kind.unlockRule {
        case .open:
            return nil
        case .squishDifferentKinds(let count):
            return UnlockProgress(task: "press \(count) different things", done: stats.squishedKinds.count, total: count)
        case .totalPresses(let count):
            return UnlockProgress(task: "press \(count) times", done: totalPresses, total: count)
        case .perfectSquish:
            return UnlockProgress(task: "one slow, steady press", done: stats.perfectCount, total: 1)
        case .allOthers:
            let others = ObjectKind.allCases.filter { $0 != kind }
            return UnlockProgress(task: "press everything else", done: others.filter { stats.squishedKinds.contains($0) }.count,
                                  total: others.count)
        }
    }

    /// The locked object closest to opening, for "Next unlock: Soda Can · press 3 different things · 1/3". Nil when
    /// everything is open.
    var nextUnlock: (kind: ObjectKind, progress: UnlockProgress)? {
        let locked = ObjectKind.allCases.filter { !isUnlocked($0) }
        let ranked = locked.compactMap { kind in unlockProgress(for: kind).map { (kind: kind, progress: $0) } }
        // The secret always goes last; otherwise the one nearest done, then shelf order.
        return ranked.min { a, b in
            if a.kind.isSecret != b.kind.isSecret { return !a.kind.isSecret }
            return a.progress.fraction > b.progress.fraction
        }
    }

    /// Short lower-case form for the object chip menu's locked rows (P2-7).
    func menuHint(for kind: ObjectKind) -> String {
        switch kind.unlockRule {
        case .open: ""
        case .squishDifferentKinds(let count): "squish \(count) different things"
        case .totalPresses(let count): "squish \(count) times"
        case .perfectSquish: "press slowly, never ease off"
        case .allOthers: "some things won't squish"
        }
    }
}
