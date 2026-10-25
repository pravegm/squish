import SwiftUI
import UIKit

// S5 Reveal ceremony on the Fold Press (design/EXPERIENCE-PLAN.md "Reveal ceremony", UX-AUDIT-2 §4.2 S5). The reveal
// has to happen, not just be there:
//   1. the lid lifts off the print (300 ms): the anvil shows the final crushed specimen at once,
//   2. before → after with a measurement ("36 mm → 7.4 mm"), the PRESSED stamp,
//   3. the stats count up (tons, badges),
//   4. this object's slot in the museum strip fills with a flash and a chime.
// Keep / Again / Share are up from the first frame; fold-to-keep only counts after 2.5 s (the director), with a hint.
// The slow-mo replay of the break never plays by itself (founder, real Duo: an automatic replay read as "why is the
// object back?"). A big ▶ SLO-MO key on the anvil half plays it (`FoldPressController.playBreakReplay(speed: 0.35)`),
// framed as a film (letterbox bars, REC, a timecode, SLO-MO REPLAY); a tap skips back to the specimen; it can be
// played again any number of times (`SloMoState`, `SloMoKey`, `SloMoCinema`).

/// A badge on the reveal ticket: a trait, an achievement or an unlock.
struct RevealBadge: Identifiable, Equatable {
    let id: String
    let text: String
    let symbol: String
    let tone: SpecimenRecord.Trait.Tone

    static func list(for outcome: RecordOutcome, specimen: SpecimenRecord) -> [RevealBadge] {
        // Only what the plate doesn't already say: PERFECT is the print's stamp and GOLDEN its ribbon, an unlock has its
        // own ribbon (`UnlockRibbon`). So: a surprise found, and achievements earned.
        var badges = specimen.traits.filter { $0.tone == .surprise }.map {
            RevealBadge(id: "trait-\($0.text)", text: $0.text, symbol: $0.systemImage, tone: $0.tone)
        }
        badges += outcome.newAchievements.map {
            RevealBadge(id: "ach-\($0.rawValue)", text: $0.title.uppercased(), symbol: $0.symbolName, tone: .perfect)
        }
        return badges
    }
}

/// The ticket's small badge: an 18 pt pill, so three lines of ticket fit between the print and the crease.
struct TicketChip: View {
    let text: String
    let symbol: String
    var tone: SpecimenRecord.Trait.Tone = .perfect

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(text)
                .font(Theme.micro)
                .tracking(Theme.microTracking * 0.4)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(Capsule().fill(tone == .surprise ? Theme.rgb(0xDCEBFA) : Theme.yellowSoft))
        .overlay(Capsule().strokeBorder(tone == .surprise ? Theme.rgb(0x9CC2EA) : Theme.yellow.opacity(0.7), lineWidth: 1))
        .fixedSize()
    }
}

/// "UNLOCKED · GLASS BOTTLE": a ribbon on the print's other top corner when this press opened something.
struct UnlockRibbon: View {
    let kinds: [ObjectKind]

    var body: some View {
        if let first = kinds.first {
            HStack(spacing: 5) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("UNLOCKED · \(first.displayName.uppercased())\(kinds.count > 1 ? " +\(kinds.count - 1)" : "")".gluingDotSeparators)
                    .font(Theme.micro)
                    .tracking(Theme.microTracking * 0.6)
            }
            .foregroundStyle(Theme.graphite)
            .fixedSize()
            .padding(.horizontal, Theme.s2)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.rgb(0xDCEBFA)).elevation(.e1)
            }
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.rgb(0x9CC2EA), lineWidth: 1))
            .rotationEffect(.degrees(4))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Unlocked: \(kinds.map(\.displayName).joined(separator: ", ")).")
        }
    }
}

/// The ceremony's state, stepped by `RevealCeremony.run`.
struct CeremonyState: Equatable {
    var lidLifted = false
    var ticketIn = false
    /// 0…1: the "after" height counting down from the rest height.
    var squash: Double = 0
    var stamped = false
    var tons = 0
    var badges = 0
    var slotFilled = false
    var slotFlash = false

    static func finished(tons: Int, badges: Int) -> CeremonyState {
        CeremonyState(lidLifted: true, ticketIn: true, squash: 1, stamped: true, tons: tons,
                      badges: badges, slotFilled: true, slotFlash: false)
    }
}

/// The shade over the print that lifts off once the inner display is lit (step 1).
struct LidShade: View {
    let lifted: Bool
    /// Book pose: the lid lifts toward the leading edge; tabletop: toward the top.
    let book: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let travel = book ? proxy.size.width : proxy.size.height
            LinearGradient(colors: [Theme.rgb(0x1B1C1F), Theme.rgb(0x2B2D31)],
                           startPoint: book ? .leading : .top, endPoint: book ? .trailing : .bottom)
                .overlay(alignment: book ? .trailing : .bottom) {
                    // The lid's lip: a thin hazard line where it meets the crease.
                    Rectangle().fill(Theme.yellow.opacity(0.65))
                        .frame(width: book ? 3 : nil, height: book ? nil : 3)
                }
                .offset(x: book && lifted && !reduceMotion ? -travel : 0,
                        y: !book && lifted && !reduceMotion ? -travel : 0)
                .opacity(lifted ? 0 : 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The paper ticket under the print: name and number, before → after, tons, badges, and the stamp.
struct RevealTicket: View {
    let specimen: SpecimenRecord
    let badges: [RevealBadge]
    let state: CeremonyState

    var body: some View {
        let measure = specimen.measurement
        let after = measure.before + (measure.after - measure.before) * state.squash
        let shown = Array(badges.prefix(state.badges))
        // Three calm lines and the tons as the hero, one stamp (the print's own, on the plate above), no hinge angle:
        //   CRAYON BOX                          │  55
        //   №0001 · 8 SNAPS    [★ FIRST SQUISH] │ TONS
        //   ▱→▬  11 mm → 1.1 mm                 │
        HStack(alignment: .center, spacing: Theme.s3) {
            details(measure: measure, after: after, shown: shown)
            Rectangle().fill(Theme.paperEdge).frame(width: 1).padding(.vertical, 4)
            VStack(alignment: .center, spacing: 0) {
                Text("\(state.tons)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: Double(state.tons)))
                Text("TONS")
                    .font(Theme.micro)
                    .tracking(Theme.microTracking)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .fixedSize()
            .frame(minWidth: 64)
        }
        .padding(.horizontal, Theme.s4)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.paper).elevation(.e2)
        }
        .overlay(alignment: .leading) {
            // The ticket's spine: a thin yellow rail, like the toasts.
            Capsule().fill(Theme.yellow).frame(width: 4).padding(.vertical, 10).offset(x: 6)
        }
        .rotationEffect(.degrees(-0.8))
        .dynamicTypeSize(...DynamicTypeSize.large)   // a fixed composition, like the card
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(specimen.accessibilitySentence) \(measure.spoken).")
    }

    private func details(measure: SpecimenRecord.PressedSize, after: Double, shown: [RevealBadge]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(specimen.kind.displayName.uppercased())
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .fixedSize()
            HStack(alignment: .center, spacing: Theme.s2) {
                Text("\(specimen.numberLabel) · \(specimen.kind.breaksLine(fractureCount: specimen.fractureCount))".gluingDotSeparators)
                    .font(Theme.micro)
                    .tracking(Theme.microTracking * 0.4)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize()
                Spacer(minLength: Theme.s2)
                if !shown.isEmpty {
                    // As many whole badges as fit, then "+N MORE": never a cut-off word.
                    ViewThatFits(in: .horizontal) {
                        ForEach(Array(stride(from: shown.count, through: 1, by: -1)), id: \.self) { count in
                            badgeRow(Array(shown.prefix(count)), hidden: shown.count - count)
                        }
                        badgeRow([], hidden: shown.count)
                    }
                }
            }
            .frame(minHeight: 18)
            HStack(alignment: .center, spacing: Theme.s3) {
                BeforeAfterGlyph(kind: specimen.kind, ratio: measure.before > 0 ? after / measure.before : 1)
                    .frame(width: 66, height: 24)
                Text("\(SpecimenRecord.PressedSize.mm(measure.before)) → \(SpecimenRecord.PressedSize.mm(after))")
                    .font(.system(.headline, design: .monospaced, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                    .fixedSize()
                Spacer(minLength: 0)
            }
        }
    }

    private func badgeRow(_ list: [RevealBadge], hidden: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(list) { badge in
                TicketChip(text: badge.text, symbol: badge.symbol, tone: badge.tone)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            if hidden > 0 && list.isEmpty {
                TicketChip(text: hidden == 1 ? "1 BADGE" : "\(hidden) BADGES", symbol: "star.fill", tone: .perfect)
            } else if hidden > 0 {
                Text("+\(hidden) MORE")
                    .font(Theme.micro)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize()
            }
        }
    }
}

/// Before → after as two little silhouettes: the object at rest, and squashed to `ratio` of its height.
struct BeforeAfterGlyph: View {
    let kind: ObjectKind
    let ratio: Double

    var body: some View {
        // On a little ground line, so even a 1 mm specimen reads as a flat bar rather than nothing.
        HStack(alignment: .bottom, spacing: 3) {
            ObjectSilhouette(kind: kind)
                .fill(Theme.tint(for: kind).opacity(0.5))
                .overlay(ObjectSilhouette(kind: kind).stroke(Theme.graphite.opacity(0.3), lineWidth: 0.8))
                .frame(width: 20, height: 22)
            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.bottom, 7)
            Capsule()
                .fill(Theme.tint(for: kind))
                .overlay(Capsule().stroke(Theme.graphite.opacity(0.3), lineWidth: 0.8))
                .frame(width: 20 * min(1.6, 1 + (1 - ratio) * 0.6), height: max(3, 22 * ratio))
        }
        .padding(.bottom, 1)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.graphite.opacity(0.25)).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

/// The museum strip above the console: ten slots in museum order, this object's slot fills with a flash; on the
/// right, "FOLD TO KEEP" once fold-to-keep counts.
struct MuseumStrip: View {
    let collection: CollectionStore
    let kind: ObjectKind
    let firstOfKind: Bool
    let state: CeremonyState
    let foldToKeep: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = collection.stats.squishedKinds
        HStack(spacing: 5) {
            Text("MUSEUM")
                .font(Theme.micro)
                .tracking(Theme.microTracking)
                .foregroundStyle(Theme.paper.opacity(0.85))
            ForEach(ObjectKind.museumOrder) { item in
                let filled = pressed.contains(item) && (item != kind || !firstOfKind || state.slotFilled)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(filled ? Theme.tint(for: item) : Color.white.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(item == kind ? Theme.yellow : Color.white.opacity(0.18), lineWidth: item == kind ? 1.5 : 1))
                    .frame(width: 10, height: 10)
                    .scaleEffect(item == kind && state.slotFlash && !reduceMotion ? 1.5 : 1)
                    .shadow(color: Theme.yellow.opacity(item == kind && state.slotFlash ? 0.9 : 0), radius: 6)
            }
            Text("\(pressed.count - (firstOfKind && !state.slotFilled ? 1 : 0))/\(ObjectKind.allCases.count)")
                .font(Theme.micro)
                .foregroundStyle(Theme.paper.opacity(0.85))
                .contentTransition(.numericText())
            if foldToKeep {
                Spacer(minLength: Theme.s2)
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("FOLD TO KEEP")
                        .font(Theme.micro)
                        .tracking(Theme.microTracking * 0.4)
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(Theme.yellow)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, Theme.s3)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.graphite.opacity(0.88)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .animation(Theme.pop(reduceMotion), value: state.slotFlash)
        .animation(Theme.fade, value: foldToKeep)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Museum: \(pressed.count) of \(ObjectKind.allCases.count) objects pressed."
                            + (foldToKeep ? " Fold the phone to keep this specimen." : ""))
    }
}

// MARK: - SLO-MO, on request

/// The reveal's slow-mo replay, opt-in (founder, real Duo: the automatic replay read as "why is the object back?").
/// Pure, so the rules are tested (CollectionTests): nothing plays until the SLO-MO key is tapped; a tap on the film
/// (or its end) hands back to the crushed specimen with a settle; then the key is back, and it plays again any number
/// of times.
struct SloMoState: Equatable {
    enum Phase: Equatable {
        /// The final crushed specimen, with the key up (when there is a replay). Where every reveal starts.
        case specimen
        /// Take `take` is running, for `duration` wall-clock seconds at most.
        case playing(take: Int, duration: TimeInterval)
        /// Handing back: the bars are gone, the scene blends to the specimen and the plate settles.
        case settling(take: Int)
    }

    private(set) var phase: Phase = .specimen
    /// Films played on this reveal.
    private(set) var takes = 0

    /// The key can start a film: only on the specimen, never over a film or its hand-back.
    var canPlay: Bool { phase == .specimen }

    var isPlaying: Bool {
        if case .playing = phase { return true }
        return false
    }

    /// The take on screen (playing or settling), if any.
    var take: Int? {
        switch phase {
        case .specimen: return nil
        case .playing(let take, _), .settling(let take): return take
        }
    }

    /// The key shows when this press has a replay and the specimen is on the anvil.
    func showsKey(replayAvailable: Bool) -> Bool { replayAvailable && canPlay }

    /// The SLO-MO key was tapped and the scene was asked to play: `duration` is what it answered (nil: nothing to
    /// play, so nothing changes). Returns the take started.
    @discardableResult
    mutating func begin(duration: TimeInterval?) -> Int? {
        guard canPlay, let duration, duration > 0 else { return nil }
        takes += 1
        phase = .playing(take: takes, duration: min(duration, RevealCeremony.replayCap))
        return takes
    }

    /// A tap on the film, or its end: back to the specimen. False when `take` isn't the film running (a late timer of
    /// a skipped take does nothing).
    @discardableResult
    mutating func endFilm(take: Int) -> Bool {
        guard case .playing(let running, _) = phase, running == take else { return false }
        phase = .settling(take: take)
        return true
    }

    /// The settle has played: the key is back.
    mutating func settled(take: Int) {
        guard case .settling(let running) = phase, running == take else { return }
        phase = .specimen
    }
}

/// "▶ SLO-MO": the one way to watch the break again. A dark console key at primary size, on the anvil half next to the
/// specimen, never over it or the console row.
struct SloMoKey: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.s2) {
                Image(systemName: "play.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                Text("SLO-MO")
            }
        }
        .buttonStyle(KeycapStyle(kind: .console, tall: true))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .fixedSize()
        .accessibilityLabel("Slow-motion replay")
        .accessibilityHint("Plays the break again at a third of the speed. Tap the replay to skip back to the specimen.")
    }
}

/// The film's frame over the anvil half while the slow-mo plays, so it can't be mistaken for the object coming back:
/// letterbox bars, a blinking REC dot and a running timecode on top, SLO-MO REPLAY · 0.35× and TAP TO SKIP below, and
/// viewfinder corners round the plate. The whole frame is one tap target that skips back to the specimen.
struct SloMoCinema: View {
    /// The anvil strike plate, in this view's own coordinates (the caller frames the view on the anvil half).
    let plate: CGRect
    let started: Date
    let speed: Double
    let onSkip: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var barsIn = false

    static let barHeight: CGFloat = 36

    var body: some View {
        ZStack {
            Color.black.opacity(0.06)
            Viewfinder(plate: plate)
                .stroke(Theme.graphite.opacity(0.75), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            VStack(spacing: 0) {
                topBar
                    .offset(y: barsIn || reduceMotion ? 0 : -Self.barHeight)
                Spacer(minLength: 0)
                bottomBar
                    .offset(y: barsIn || reduceMotion ? 0 : Self.barHeight)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(perform: onSkip)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { barsIn = true }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slow-motion replay playing")
        .accessibilityHint("Double-tap to skip back to the specimen.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSkip() }
    }

    private var topBar: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: false)) { context in
            let elapsed = max(context.date.timeIntervalSince(started), 0)
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.stamp)
                    .frame(width: 9, height: 9)
                    // Blinks twice a second; steady with Reduce Motion.
                    .opacity(reduceMotion || Int(elapsed * 2) % 2 == 0 ? 1 : 0.25)
                Text("REC")
                Spacer(minLength: Theme.s2)
                Text(Self.timecode(elapsed * speed))
                    .monospacedDigit()
            }
            .font(Theme.micro)
            .tracking(Theme.microTracking)
            .foregroundStyle(Theme.paper)
            .padding(.horizontal, Theme.s4)
            .frame(maxWidth: .infinity, minHeight: Self.barHeight, maxHeight: Self.barHeight)
            .background(Color.black.opacity(0.9))
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 6) {
            Text("SLO-MO REPLAY")
                .foregroundStyle(Theme.yellow)
            Text(String(format: "· %.2g×", speed))
            Spacer(minLength: Theme.s2)
            Text("TAP TO SKIP")
                .foregroundStyle(Theme.paper.opacity(0.7))
        }
        .font(Theme.micro)
        .tracking(Theme.microTracking)
        .foregroundStyle(Theme.paper)
        .padding(.horizontal, Theme.s4)
        .frame(maxWidth: .infinity, minHeight: Self.barHeight, maxHeight: Self.barHeight)
        .background(Color.black.opacity(0.9))
    }

    /// The moment of the press on screen, as film timecode (minutes:seconds:frames at 24 fps): it creeps, because the
    /// film runs at `speed`.
    static func timecode(_ seconds: Double) -> String {
        let frames = Int(max(seconds, 0) * 24)
        return String(format: "%02d:%02d:%02d", frames / (24 * 60), (frames / 24) % 60, frames % 24)
    }
}

/// Four corner brackets just outside a rect: the viewfinder round the anvil plate.
private struct Viewfinder: Shape {
    let plate: CGRect

    func path(in rect: CGRect) -> Path {
        let frame = plate.insetBy(dx: -10, dy: -10)
        let arm = min(22, frame.width / 4, frame.height / 4)
        var path = Path()
        for (corner, dx, dy) in [(CGPoint(x: frame.minX, y: frame.minY), 1.0, 1.0),
                                 (CGPoint(x: frame.maxX, y: frame.minY), -1.0, 1.0),
                                 (CGPoint(x: frame.minX, y: frame.maxY), 1.0, -1.0),
                                 (CGPoint(x: frame.maxX, y: frame.maxY), -1.0, -1.0)] {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        }
        return path
    }
}

/// The hand-back's settle: a yellow rim that closes onto the anvil plate as the film ends.
struct SloMoSettle: View {
    /// 1 at the hand-back, eased to 0.
    let amount: Double
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Theme.yellow, lineWidth: 3)
            .scaleEffect(reduceMotion ? 1 : 1 + 0.04 * amount)
            .opacity(amount)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

enum RevealCeremony {
    /// The replay's speed (EXPERIENCE-PLAN).
    static let replaySpeed = 0.35
    /// A film is cut off after this long, whatever it reports (the ~2 s tape at 0.35× runs ~6 s).
    static let replayCap = 7.0
    /// The settle after a film: the rim's ease, then the key is back.
    static let settleMilliseconds = 550

    /// The slot chime: two high pentatonic tinks (BrandCues' musical system).
    static var slotChime: FeedbackCue {
        BrandCues.tick(BrandCues.pentatonic[7], gain: 1.6)
            .adding(BrandCues.tick(BrandCues.pentatonic[9], gain: 1.6).delayed(by: 0.09))
    }
}
