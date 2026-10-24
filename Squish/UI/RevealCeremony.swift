import SwiftUI
import UIKit

// S5 Reveal ceremony on the Fold Press (design/EXPERIENCE-PLAN.md "Reveal ceremony", UX-AUDIT-2 §4.2 S5). The reveal
// has to happen, not just be there:
//   1. the lid lifts off the print (300 ms),
//   2. a slow-mo replay of the break plays on the anvil (`FoldPressController.playBreakReplay(speed: 0.35)`),
//   3. before → after with a measurement ("36 mm → 7.4 mm"), the PRESSED stamp,
//   4. the stats count up (tons, badges),
//   5. this object's slot in the museum strip fills with a flash and a chime.
// Keep / Again / Share are up from the first frame; fold-to-keep only counts after 2.5 s (the director), with a hint.

/// A badge on the reveal ticket: a trait, an achievement or an unlock.
struct RevealBadge: Identifiable, Equatable {
    let id: String
    let text: String
    let symbol: String
    let tone: SpecimenRecord.Trait.Tone

    static func list(for outcome: RecordOutcome, specimen: SpecimenRecord) -> [RevealBadge] {
        var badges = specimen.traits.map { RevealBadge(id: "trait-\($0.text)", text: $0.text, symbol: $0.systemImage, tone: $0.tone) }
        badges += outcome.newAchievements.map {
            RevealBadge(id: "ach-\($0.rawValue)", text: $0.title.uppercased(), symbol: $0.symbolName, tone: .perfect)
        }
        badges += outcome.newlyUnlocked.map {
            RevealBadge(id: "unlock-\($0.rawValue)", text: "NEW: \($0.chipName)", symbol: "lock.open.fill", tone: .surprise)
        }
        return badges
    }
}

/// The ceremony's state, stepped by `RevealCeremony.run`.
struct CeremonyState: Equatable {
    var lidLifted = false
    var replaying = false
    var ticketIn = false
    /// 0…1: the "after" height counting down from the rest height.
    var squash: Double = 0
    var stamped = false
    var tons = 0
    var badges = 0
    var slotFilled = false
    var slotFlash = false

    static func finished(tons: Int, badges: Int) -> CeremonyState {
        CeremonyState(lidLifted: true, replaying: false, ticketIn: true, squash: 1, stamped: true, tons: tons,
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
                Text(specimen.kind.displayName.uppercased())
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(specimen.numberLabel)
                    .font(Theme.micro)
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 0)
                Text(specimen.kind.breaksLine(fractureCount: specimen.fractureCount))
                    .font(Theme.micro)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            HStack(alignment: .center, spacing: Theme.s3) {
                BeforeAfterGlyph(kind: specimen.kind, ratio: measure.before > 0 ? after / measure.before : 1)
                    .frame(width: 44, height: 26)
                Text("\(SpecimenRecord.PressedSize.mm(measure.before)) → \(SpecimenRecord.PressedSize.mm(after))")
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(state.tons)")
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(state.tons)))
                    Text("TONS")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .foregroundStyle(Theme.ink)
            }
            if !badges.isEmpty {
                HStack(spacing: 5) {
                    ForEach(shown) { badge in
                        TraitChip(text: badge.text, systemImage: badge.symbol, tone: badge.tone)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 24, alignment: .leading)
                .clipped()
            }
        }
        .padding(.horizontal, Theme.s3)
        .padding(.vertical, Theme.s2)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.paper).elevation(.e2)
        }
        .overlay(alignment: .topTrailing) {
            PressedStamp(seed: specimen.variant.seed, text: specimen.stampText)
                .scaleEffect(state.stamped ? 0.62 : 1.1)
                .opacity(state.stamped ? 1 : 0)
                .offset(x: 18, y: -22)
                .allowsHitTesting(false)
        }
        .rotationEffect(.degrees(-1.2))
        .dynamicTypeSize(...DynamicTypeSize.large)   // a fixed composition, like the card
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(specimen.accessibilitySentence) \(measure.spoken).")
    }
}

/// Before → after as two little silhouettes: the object at rest, and squashed to `ratio` of its height.
struct BeforeAfterGlyph: View {
    let kind: ObjectKind
    let ratio: Double

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ObjectSilhouette(kind: kind)
                .fill(Theme.tint(for: kind).opacity(0.45))
                .frame(width: 18, height: 22)
            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.bottom, 6)
            ObjectSilhouette(kind: kind)
                .fill(Theme.tint(for: kind))
                .frame(width: 18 * min(1.8, 1 + (1 - ratio) * 0.8), height: 22)
                .scaleEffect(x: 1, y: max(0.08, ratio), anchor: .bottom)
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
                    .frame(width: 12, height: 12)
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
                        .tracking(Theme.microTracking * 0.6)
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

/// "SLOW-MO REPLAY · 0.35×", pinned to the anvil plate's corner while the break replays.
struct ReplayTag: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.stamp).frame(width: 7, height: 7)
            Text("SLOW-MO REPLAY · 0.35×")
                .font(Theme.micro)
                .tracking(Theme.microTracking * 0.6)
        }
        .foregroundStyle(Theme.paper)
        .padding(.horizontal, Theme.s2)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.graphite.opacity(0.85)))
        .accessibilityLabel("Slow motion replay")
    }
}

enum RevealCeremony {
    /// The replay's speed (EXPERIENCE-PLAN).
    static let replaySpeed = 0.35
    /// The replay is cut off after this long, whatever it reports.
    static let replayCap = 4.5

    /// The slot chime: two high pentatonic tinks (BrandCues' musical system).
    static var slotChime: FeedbackCue {
        BrandCues.tick(BrandCues.pentatonic[7], gain: 1.6)
            .adding(BrandCues.tick(BrandCues.pentatonic[9], gain: 1.6).delayed(by: 0.09))
    }
}
