import SwiftUI
import UIKit

/// The reveal (VISUAL-TARGET §6.8, bible §3.1 beats 11–12). Portrait: the 3:4 specimen card drops into the
/// 6–44% band (over the lifted ram, so the flattened object stays visible on the anvil), one toast at a time
/// in 80–86%, and Again / Share / Next keycaps on the console (86–95%). Landscape: card in the left 30% column,
/// console in the right 22% column. On collect, the card flies into the Shelf key (which RootView mounts).
struct RevealCardView: View {
    let outcome: RecordOutcome
    let collection: CollectionStore
    /// Hinge trace for the share clip, when one is stored for this specimen.
    let trace: PressTrace?
    /// Next/Again was tapped: the actions fade and the console's Shelf key appears.
    let collecting: Bool
    /// Global centre of the Shelf key once the card should fly into it.
    let flyTarget: CGPoint?
    /// Foldable: keep the card off the crease.
    var hinge = false
    /// iPhone Duo Fold Press: the reveal is the FOLD-PRESS §6.3 diptych (print on the platen, specimen on the
    /// anvil), so no card covers them; the card appears only for the collect flight.
    var foldPress = false
    /// Fold Press: returns once the inner display is lit for this reveal (`FoldPressController.revealLit`). The
    /// toasts wait for it, so they never play on a dark panel (FOLD-REVIEW-7 N10). Unused off the Fold Press.
    var revealLit: @MainActor () async -> Void = {}
    let onNext: () -> Void
    let onAgain: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var share = SpecimenShareModel()
    @State private var cardIn = false
    @State private var toastIndex = -1
    @State private var actionsIn = false
    @AccessibilityFocusState private var focusNext: Bool

    /// The live record (it gains its thumbnail ~1 s after the reveal).
    private var specimen: SpecimenRecord { collection.specimen(withID: outcome.specimen.id) ?? outcome.specimen }

    private struct Toast: Identifiable {
        let id: String
        let title: String
        let detail: String
        let glyph: ToastView.Glyph
        let accent: Color
    }

    private var toasts: [Toast] {
        // `-squishDemo …;notoasts` (store capture, FOLD-REVIEW-4 F4): the reveal stays clean.
        if RevealToastDemo.hidesToasts { return [] }
        var list: [Toast] = []
        // The first Perfect Squish ever explains itself (P1-13).
        if outcome.specimen.isPerfect && collection.stats.perfectCount == 1 {
            list.append(Toast(id: "perfect", title: "PERFECT SQUISH", detail: "Slow, steady, no second thoughts.",
                              glyph: .symbol("sparkles"), accent: Theme.yellow))
        }
        list += outcome.newlyUnlocked.map { kind in
            Toast(id: "unlock-\(kind.rawValue)", title: "NEW OBJECT UNLOCKED",
                  detail: "\(kind.displayName) · up next", glyph: .object(kind), accent: Theme.tint(for: kind))
        }
        list += outcome.newAchievements.map { achievement in
            Toast(id: "ach-\(achievement.rawValue)", title: "ACHIEVEMENT · \(achievement.title.uppercased())",
                  detail: achievement.detail, glyph: .symbol(achievement.symbolName), accent: Theme.yellow)
        }
        return list
    }

    var body: some View {
        GeometryReader { proxy in
            let bands = ScreenBands(proxy, hinge: hinge)
            let origin = proxy.frame(in: .global).origin
            if foldPress {
                diptych(bands, origin: origin)
            } else if bands.isLandscape {
                landscape(bands, origin: origin)
            } else {
                portrait(bands, origin: origin)
            }
        }
        .modifier(SpecimenSharingChrome(model: share))
        .onAppear(perform: choreograph)
    }

    // MARK: Layouts

    private func portrait(_ bands: ScreenBands, origin: CGPoint) -> some View {
        // Width per VISUAL-REVIEW-1 #12 (min 84%, 340 pt); height fits the 6–44% band and stays clear of the crease.
        let top = bands.y(0.06)
        let width = min(bands.fullWidth * 0.84, 340)
        let height = min(bands.topBandBottom - top, width * 1.15)
        let center = CGPoint(x: bands.size.width / 2, y: top + height / 2)
        return ZStack {
            card(width: width, height: height, center: center, origin: origin)
                .position(center)
            toastSlot()
                .frame(maxWidth: 420)
                .padding(.horizontal, bands.margin)
                .position(x: bands.size.width / 2, y: bands.y(0.83))
            actions(landscape: false)
                .frame(maxWidth: 460)
                .padding(.horizontal, bands.margin)
                .position(x: bands.size.width / 2, y: bands.y(0.905))
        }
    }

    private func landscape(_ bands: ScreenBands, origin: CGPoint) -> some View {
        // Left column, never reaching the book-pose crease.
        var columnWidth = bands.fullWidth * 0.30
        if let crease = bands.crease { columnWidth = min(columnWidth, crease.minX - bands.margin) }
        let width = max(160, columnWidth - bands.margin)
        let height = min(bands.size.height - Theme.s5, width * 1.25)
        let consoleWidth = bands.fullWidth * 0.22
        let center = CGPoint(x: bands.margin + width / 2, y: bands.size.height / 2)
        return ZStack(alignment: .topLeading) {
            card(width: width, height: height, center: center, origin: origin)
                .position(center)
            VStack(alignment: .trailing, spacing: Theme.s3) {
                Spacer(minLength: 0)
                toastSlot()
                    .frame(width: max(300, consoleWidth)) // toasts are never narrower than 300 pt
                actions(landscape: true)
                    .frame(width: consoleWidth)
            }
            .padding(.bottom, Theme.s4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, bands.margin)
        }
    }

    /// Fold Press reveal (FOLD-PRESS §6.3, FOLD-REVIEW-1 #4–5). The scene keeps the monoprint on the platen
    /// (with its PRESSED stamp) and the flattened specimen on the anvil; the UI adds only a paper label under the
    /// platen plate, one single-line toast in the fold toast slot (never the crown strip: its gauge, lamps and
    /// hinge readout go green and freeze at the reveal, FOLD-REVIEW-4 F4), and Again · Share · Next in the console.
    private func diptych(_ bands: ScreenBands, origin: CGPoint) -> some View {
        let layout = bands.foldLayout
        let plate = bands.local(layout.strikePlate(platen: true))
        let console = bands.local(layout.consoleBand)
        let toastFrame = bands.foldToastSlot
        // Leave the pilot lamp (far end of the console) uncovered.
        let actionsWidth = min(console.width - Theme.s3 * 2 - 36, 455)
        let cardWidth = min(plate.width, 250)
        let cardHeight = min(plate.height + 60, cardWidth * 1.2)
        let cardCenter = CGPoint(x: plate.midX, y: plate.midY)
        return ZStack {
            // The diptych folded into one card, shown only while it flies into the Shelf key.
            card(width: cardWidth, height: cardHeight, center: cardCenter, origin: origin, onlyWhileCollecting: true)
                .position(cardCenter)
            // The caption gets the platen field's width (minus 24 pt each side), not the plate's, and the ribbon
            // lives on the plate's corner instead of sharing its row, so nothing truncates (FOLD-REVIEW-2 #6).
            let field = bands.local(layout.platenField)
            printLabel
                .frame(maxWidth: max(240, field.width - 48))
                .fixedSize(horizontal: false, vertical: true)
                .position(x: plate.midX, y: plate.maxY + 24)
            ribbon
                .opacity(cardIn && !collecting ? 1 : 0)
                .position(x: plate.maxX - 36, y: plate.minY + 4)
            toastSlot(compact: true)
                .frame(width: toastFrame.width)
                .position(x: toastFrame.midX, y: toastFrame.midY)
            foldActions
                .frame(width: actionsWidth)
                .position(x: console.minX + Theme.s3 + actionsWidth / 2, y: console.midY)
        }
    }

    /// "RUBBER DUCK · 1 HONK · 1 SEAM POP · AT 63°" in Mono 12 on a paper tag. Never truncates: it wraps to a
    /// second line before it would shrink below legibility.
    private var printLabel: some View {
        Text(foldLabelText)
            .font(Theme.label)
            .tracking(0.3)
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.9)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.paper).elevation(.e1)
            }
            .rotationEffect(.degrees(-1.5))
        .opacity(cardIn && !collecting ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(specimen.accessibilitySentence)
        .accessibilitySortPriority(2)
    }

    private var foldLabelText: String {
        var parts = [specimen.kind.displayName.uppercased(), specimen.kind.breaksLine(fractureCount: specimen.fractureCount)]
        // "AT 66°", not a bare "66°": the number is the hinge angle it gave at (FOLD-REVIEW-4 F13). Degrees only when a
        // real hinge made the press; a touch press says "AT 48 TONS" (FOLD-REVIEW-5 N6).
        if let tag = specimen.gaveAtTag { parts.append(tag) }
        return parts.joined(separator: " · ")
    }

    /// One row of 44 pt keys in the 62 pt console band; Next is the only yellow.
    private var foldActions: some View {
        HStack(spacing: Theme.s2) {
            Button(action: onAgain) {
                KeyLabel(title: "Again", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(KeycapStyle(kind: .console, fullWidth: true, compact: true))
            .accessibilityHint("Press another \(outcome.specimen.kind.displayName).")

            Button(action: shareDefault) {
                KeyLabel(title: "Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(KeycapStyle(kind: .console, fullWidth: true, compact: true))
            .disabled(share.isExporting)
            .contextMenu {
                if let trace {
                    Button("Share Clip", systemImage: "film") { share.shareClip(trace: trace, specimen: specimen) }
                }
                Button("Share Still", systemImage: "photo") { shareStill() }
            }
            .accessibilityActions {
                Button("Share still") { shareStill() }
            }

            Button(action: onNext) {
                KeyLabel(title: "Next", systemImage: "arrow.right", iconTrailing: true)
            }
            .buttonStyle(KeycapStyle(kind: .primary, fullWidth: true, compact: true))
            .accessibilityFocused($focusNext)
            .accessibilityHint("Collects this specimen. Or just fold the phone again.")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .disabled(collecting)
        .opacity(actionsIn && !collecting ? 1 : 0)
    }

    // MARK: Card

    private func card(width: CGFloat, height: CGFloat, center: CGPoint, origin: CGPoint,
                      onlyWhileCollecting: Bool = false) -> some View {
        let flight: CGSize = flyTarget.map {
            CGSize(width: $0.x - (origin.x + center.x), height: $0.y - (origin.y + center.y))
        } ?? .zero
        let flying = flyTarget != nil
        let tilt = Double(Int(specimen.variant.seed % 11) - 5) * 0.5
        let visible = onlyWhileCollecting ? collecting : cardIn
        return SpecimenCardView(specimen: specimen, thumbnail: collection.thumbnail(for: specimen),
                                style: .reveal, animateStamp: !onlyWhileCollecting)
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) { if !onlyWhileCollecting { ribbon } }
            .scaleEffect(flying && !reduceMotion ? 0.16 : 1)
            .rotationEffect(.degrees(flying && !reduceMotion ? tilt : 0))
            .offset(reduceMotion ? .zero : flight)
            .opacity(visible && !(flying && reduceMotion) ? 1 : 0)
            .accessibilityHidden(onlyWhileCollecting)
            .offset(y: cardIn || reduceMotion ? 0 : -60)
            .rotationEffect(.degrees(cardIn || reduceMotion ? 0 : -3))
            .accessibilitySortPriority(2)
    }

    /// Golden and surprises say so on the card (the "GOLDEN!" caption is never visible during the reveal, P1-20);
    /// otherwise NEW BEST / NEW ON THE SHELF.
    @ViewBuilder
    private var ribbon: some View {
        let text: String? = {
            if outcome.specimen.variant.isGolden { return "GOLDEN · 1 IN 50" }
            if outcome.isNewBest { return outcome.specimen.isPerfect ? "NEW BEST" : "NEW ON THE SHELF" }
            return nil
        }()
        if let text {
            Text(text)
                .font(Theme.micro)
                .tracking(Theme.microTracking)
                .foregroundStyle(Theme.graphite)
                .padding(.horizontal, Theme.s2)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(outcome.specimen.variant.isGolden ? Theme.goldSoft : Theme.yellow)
                        .elevation(.e1)
                }
                .topHighlight(cornerRadius: 6)
                .rotationEffect(.degrees(-5))
                // Sits on the card's top edge, 8 pt lower than before, so it stays out of the 0–6% band.
                .offset(x: Theme.s3, y: 0)
                .accessibilityHidden(true)
        }
    }

    // MARK: Toasts (one at a time)

    @ViewBuilder
    private func toastSlot(compact: Bool = false) -> some View {
        let list = toasts
        ZStack {
            if toastIndex >= 0 && toastIndex < list.count && !collecting {
                let toast = list[toastIndex]
                ToastView(title: toast.title, detail: toast.detail, glyph: toast.glyph, accent: toast.accent, compact: compact)
                    .id(toast.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minHeight: compact ? 48 : 52)
    }

    // MARK: Actions

    private func actions(landscape: Bool) -> some View {
        let layout = landscape ? AnyLayout(VStackLayout(alignment: .trailing, spacing: Theme.s3))
                               : AnyLayout(HStackLayout(spacing: Theme.s3))
        return layout {
            Button(action: onAgain) {
                KeyLabel(title: "Again", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(KeycapStyle(kind: .secondary))
            .accessibilityHint("Press another \(outcome.specimen.kind.displayName).")

            // One tap shares the clip when there is one (bible §10); the still is in the context menu.
            Button(action: shareDefault) {
                KeyLabel(title: "Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(KeycapStyle(kind: .secondary))
            .disabled(share.isExporting)
            .contextMenu {
                if let trace {
                    Button("Share Clip", systemImage: "film") { share.shareClip(trace: trace, specimen: specimen) }
                }
                Button("Share Still", systemImage: "photo") { shareStill() }
            }
            .accessibilityHint(trace == nil ? "Shares a picture of this card." : "Shares a short clip of this press.")
            .accessibilityActions {
                Button("Share still") { shareStill() }
            }

            Button(action: onNext) {
                KeyLabel(title: "Next", systemImage: "arrow.right", iconTrailing: true)
            }
            .buttonStyle(KeycapStyle(kind: .primary, fullWidth: !landscape))
            .accessibilityFocused($focusNext)
            .accessibilityHint(outcome.newlyUnlocked.first.map { "Puts the \($0.displayName) on the anvil." }
                               ?? "Collects this card and puts the next object on the anvil.")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .disabled(collecting)
        .opacity(actionsIn && !collecting ? 1 : 0)
        .offset(y: actionsIn || reduceMotion ? 0 : 24)
    }

    private func shareDefault() {
        if let trace {
            share.shareClip(trace: trace, specimen: specimen)
        } else {
            shareStill()
        }
    }

    private func shareStill() {
        share.shareImage(specimen: specimen, thumbnail: collection.thumbnail(for: specimen))
    }

    // MARK: Choreography (§6.8)

    /// When the card (or, in Fold Press, the print label) has finished appearing, counted from `onAppear`:
    /// the drop starts at 100 ms and its spring (response 0.5) has visibly settled ~0.9 s later.
    private static let cardSettledMilliseconds = 1_000
    /// Reduce Motion: the card fades in with `Theme.fade` (0.22 s).
    private static let cardFadedMilliseconds = 220
    /// Toasts are held this long after the reveal has settled, so the first thing the player sees is their
    /// specimen, not a banner over the lamps and nameplate (FOLD-REVIEW-3 N8).
    private static let toastHoldMilliseconds = 1_500
    /// Each toast is up this long, the last one included, then leaves (FOLD-REVIEW-4 F4: none stays for good).
    private static let toastVisibleMilliseconds = 3_000
    /// The pause between one toast leaving and the next arriving, so the exit transition can play.
    private static let toastGapMilliseconds = 300

    /// Fold Press: the toasts never wait longer than this for the inner display to light (a missed light event, or a
    /// reveal that began lit, must not hold them for good).
    private static let lightTimeout: Duration = .seconds(3)

    private func choreograph() {
        if foldPress {
            // FOLD-REVIEW-7 N10: the print label and keys are up in the same frame as the diptych, with no drop or fade,
            // so the inner display relights on a finished reveal.
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                cardIn = true
                actionsIn = true
            }
        }
        Task { @MainActor in
            if foldPress {
                // Already in (above).
            } else if reduceMotion {
                // Shorter reveal (bible §6.4): card and actions together.
                withAnimation(Theme.fade) {
                    cardIn = true
                    actionsIn = true
                }
                try? await Task.sleep(for: .milliseconds(Self.cardFadedMilliseconds))
            } else {
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(Theme.cardDrop(reduceMotion)) { cardIn = true }
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation(Theme.settle(reduceMotion)) { actionsIn = true }
                try? await Task.sleep(for: .milliseconds(Self.cardSettledMilliseconds - 600))
            }
            // Toasts wait for the settled reveal, then come one at a time, 3 s each; the last one leaves too.
            let count = toasts.count
            guard count > 0 else { return }
            if foldPress {
                // The hold starts when the panel is lit, not while it's dark (at most `lightTimeout`).
                await Self.waitForLight(revealLit, timeout: Self.lightTimeout)
                guard !Task.isCancelled, !collecting else { return }
            }
            try? await Task.sleep(for: .milliseconds(Self.toastHoldMilliseconds))
            for index in 0..<count {
                if index > 0 { try? await Task.sleep(for: .milliseconds(Self.toastGapMilliseconds)) }
                guard !Task.isCancelled, !collecting else { return }
                withAnimation(Theme.pop(reduceMotion)) { toastIndex = index }
                if index == 0 { UIFeel.success() }
                #if DEBUG
                if DemoScenario.current != nil { print("SQUISH-T toast shown \(index + 1)/\(count)") }   // ci verify pass
                #endif
                try? await Task.sleep(for: .milliseconds(Self.toastVisibleMilliseconds))
                guard !Task.isCancelled else { return }
                withAnimation(Theme.fade) { toastIndex = -1 }
            }
        }
        if UIAccessibility.isVoiceOverRunning {
            let announcement = ([specimen.accessibilitySentence] + toasts.map { "\($0.title.capitalized). \($0.detail)" })
                .joined(separator: " ")
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                UIAccessibility.post(notification: .announcement, argument: announcement)
                // Move focus to Next so the user doesn't have to hunt for it (P1-10).
                try? await Task.sleep(for: .milliseconds(150))
                focusNext = true
            }
        }
    }

    /// Returns when `lit` returns or after `timeout`, whichever is first. Not a task group: `lit` waits on a
    /// continuation that ignores cancellation, and a group would wait for it to finish, timeout or not.
    @MainActor
    private static func waitForLight(_ lit: @escaping @MainActor () async -> Void, timeout: Duration) async {
        let latch = RevealLightLatch()
        Task { @MainActor in
            await lit()
            latch.open()
        }
        Task { @MainActor in
            try? await Task.sleep(for: timeout)
            latch.open()
        }
        await latch.wait()
    }
}

/// Opens once; `wait()` returns when it has opened (at once if it already has). Main actor only.
@MainActor
private final class RevealLightLatch {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    func open() {
        guard !isOpen else { return }
        isOpen = true
        waiter?.resume()
        waiter = nil
    }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiter = continuation
        }
    }
}

/// `-squishDemo …;notoasts` (FOLD-REVIEW-4 F4, N8 "seed CI"): no reveal toasts (perfect, unlock, achievement), so
/// store shots and CI reveals show the lamps and the hinge readout. Read here, from the same launch argument
/// `DemoScenario` parses (`key=value;key`), so DemoMode.swift doesn't change. DEBUG only: always false in Release.
enum RevealToastDemo {
    static let hidesToasts: Bool = {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "squishDemo") else { return false }
        return raw.split(separator: ";").contains { part in
            part.split(separator: "=", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) } == "notoasts"
        }
        #else
        return false
        #endif
    }()
}
