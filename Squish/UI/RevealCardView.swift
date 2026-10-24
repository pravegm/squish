import SwiftUI
import UIKit

/// The reveal (VISUAL-TARGET §6.8, bible §3.1 beats 11–12, EXPERIENCE-PLAN "Reveal ceremony").
/// - iPhone Duo (Fold Press): the diptych stays on the plates (print on the lid, specimen on the anvil) and the S5
///   ceremony plays over it: the lid lifts, the break replays in slow motion, then before → after, the stamp, the
///   stats and the museum slot (`RevealCeremony.swift`). Keep / Again / Share (and ⚙) sit in the console band.
/// - Other iPhones (P-48): the 3:4 specimen card drops into the 6–44% band, one toast at a time in 80–86%, and the keys
///   on the console. Landscape: card in the left 30% column, console in the right 22% column.
/// On collect, the card flies into the Shelf key (which RootView mounts).
struct RevealCardView: View {
    let outcome: RecordOutcome
    let collection: CollectionStore
    /// Hinge trace for the share clip, when one is stored for this specimen.
    let trace: PressTrace?
    /// Keep/Again was tapped: the actions fade and the console's Shelf key appears.
    let collecting: Bool
    /// Global centre of the Shelf key once the card should fly into it.
    let flyTarget: CGPoint?
    /// Foldable: keep the card off the crease.
    var hinge = false
    /// iPhone Duo Fold Press: the reveal is the diptych plus the ceremony; the card appears only for the collect flight.
    var foldPress = false
    /// Fold Press: returns once the inner display is lit for this reveal (`FoldPressController.revealLit`).
    var revealLit: @MainActor () async -> Void = {}
    /// Fold Press: starts the slow-mo replay of the break; its duration, or nil when there's nothing to replay.
    var playReplay: @MainActor () -> TimeInterval? = { nil }
    /// Ends a running replay early (Keep or Again tapped mid-replay).
    var stopReplay: @MainActor () -> Void = {}
    /// Fold-to-keep counts now (the director, 2.5 s into the lit ceremony): show the hint.
    var foldToKeep = false
    /// The very first reveal: no toasts (EXPERIENCE-PLAN decision 6: ask for nothing before the first reveal is done).
    var firstReveal = false
    /// UI ceremony sound and touch (the museum slot's chime).
    var playCue: @MainActor (FeedbackCue) -> Void = { _ in }
    let onKeep: () -> Void
    let onAgain: () -> Void
    var onSettings: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var share = SpecimenShareModel()
    @State private var cardIn = false
    @State private var toastIndex = -1
    @State private var actionsIn = false
    @State private var ceremony = CeremonyState()
    /// Captured at the reveal: was this the first card of its kind (its museum slot fills now)?
    @State private var firstOfKind = false
    @AccessibilityFocusState private var focusKeep: Bool

    /// The live record (it gains its thumbnail ~1 s after the reveal).
    private var specimen: SpecimenRecord { collection.specimen(withID: outcome.specimen.id) ?? outcome.specimen }

    private var badges: [RevealBadge] { RevealBadge.list(for: outcome, specimen: outcome.specimen) }

    /// Store passes and CI demo frames (`notoasts`): the ceremony is shown finished at once, so frames are deterministic.
    private var instantCeremony: Bool { RevealToastDemo.hidesToasts }

    private struct Toast: Identifiable {
        let id: String
        let title: String
        let detail: String
        let glyph: ToastView.Glyph
        let accent: Color
    }

    private var toasts: [Toast] {
        // `-squishDemo …;notoasts` (store capture, FOLD-REVIEW-4 F4): the reveal stays clean. The Fold ceremony shows
        // its badges on the ticket instead, and the first reveal of all asks for nothing.
        if RevealToastDemo.hidesToasts || foldPress || firstReveal { return [] }
        var list: [Toast] = []
        // The first Perfect Squish ever explains itself (P1-13).
        if outcome.specimen.isPerfect && collection.stats.perfectCount == 1 {
            list.append(Toast(id: "perfect", title: "PERFECT SQUISH", detail: "Slow, steady, no second thoughts.",
                              glyph: .symbol("sparkles"), accent: Theme.yellow))
        }
        list += outcome.newlyUnlocked.map { kind in
            Toast(id: "unlock-\(kind.rawValue)", title: "NEW IN THE MUSEUM",
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
        // Cancelled when the reveal goes (Keep, Again, a fold), so nothing plays on after it.
        .task {
            if !foldPress {
                await runCardReveal()
            } else if !instantCeremony {
                await runCeremony()
            }
        }
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

    /// Fold Press reveal (FOLD-PRESS §6.3 + the S5 ceremony). The scene keeps the monoprint on the platen and the
    /// flattened specimen on the anvil; the UI lays the lid shade over the print, the replay tag on the anvil plate, the
    /// ticket under the print, the museum strip above the console, and the keys in the console band.
    private func diptych(_ bands: ScreenBands, origin: CGPoint) -> some View {
        let layout = bands.foldLayout
        let plate = bands.local(layout.strikePlate(platen: true))
        let anvilPlate = bands.local(layout.strikePlate(platen: false))
        let console = bands.local(layout.consoleBand)
        let field = bands.local(layout.platenField)
        // Under the print: down to the crease (tabletop) or the platen page's foot band (book).
        let floor = bands.local(layout.platenFoot ?? layout.creaseRect).minY - 8
        let ticketTop = plate.maxY + 10
        let ticketWidth = min(field.width - 32, 520)
        // Leave the pilot lamp (far end of the console) uncovered.
        let actionsWidth = min(console.width - Theme.s3 * 2 - 36, 455)
        let cardWidth = min(plate.width, 250)
        let cardHeight = min(plate.height + 60, cardWidth * 1.2)
        let cardCenter = CGPoint(x: plate.midX, y: plate.midY)
        return ZStack {
            LidShade(lifted: ceremony.lidLifted, book: layout.isBook)
                .frame(width: field.width, height: field.height)
                .clipped()
                .position(x: field.midX, y: field.midY)
            // The diptych folded into one card, shown only while it flies into the Shelf key.
            card(width: cardWidth, height: cardHeight, center: cardCenter, origin: origin, onlyWhileCollecting: true)
                .position(cardCenter)
            if ceremony.replaying {
                ReplayTag()
                    .position(x: anvilPlate.minX + 92, y: anvilPlate.minY + 16)
                    .transition(.opacity)
            }
            RevealTicket(specimen: specimen, badges: badges, state: ceremony)
                .frame(width: ticketWidth)
                .fixedSize(horizontal: false, vertical: true)
                .position(x: plate.midX, y: min(ticketTop + 44, (ticketTop + floor) / 2 + 4))
                .opacity(ceremony.ticketIn && !collecting ? 1 : 0)
                .offset(y: ceremony.ticketIn || reduceMotion ? 0 : -14)
                .accessibilitySortPriority(2)
            ribbon
                .opacity(ceremony.ticketIn && !collecting ? 1 : 0)
                .position(x: plate.maxX - 36, y: plate.minY + 4)
            MuseumStrip(collection: collection, kind: outcome.specimen.kind, firstOfKind: firstOfKind, state: ceremony,
                        foldToKeep: foldToKeep && !collecting)
                .frame(maxWidth: actionsWidth)
                .position(x: console.minX + Theme.s3 + actionsWidth / 2, y: console.minY - 16)
                .opacity(collecting ? 0 : 1)
            foldActions
                .frame(width: actionsWidth)
                .position(x: console.minX + Theme.s3 + actionsWidth / 2, y: console.midY)
        }
    }

    /// One row of 44 pt keys in the 62 pt console band: ⚙ · Again · Share · Keep. Keep is the only yellow.
    private var foldActions: some View {
        HStack(spacing: Theme.s2) {
            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(.subheadline, weight: .semibold))
            }
            .buttonStyle(KeycapStyle(kind: .console, round: true))
            .accessibilityLabel("Settings")

            Button(action: again) {
                Text("Again")
            }
            .buttonStyle(KeycapStyle(kind: .console, fullWidth: true, compact: true))
            .accessibilityHint("Press another \(outcome.specimen.kind.displayName).")

            Button(action: shareDefault) {
                Text("Share")
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

            Button(action: keep) {
                KeyLabel(title: "Keep", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(KeycapStyle(kind: .primary, fullWidth: true, compact: true))
            .accessibilityFocused($focusKeep)
            .accessibilityHint("Files this specimen on the Shelf and puts the next object on the anvil. Or fold the phone.")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .disabled(collecting)
        .opacity(actionsIn && !collecting ? 1 : 0)
    }

    private func keep() {
        stopReplay()
        onKeep()
    }

    private func again() {
        stopReplay()
        onAgain()
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

    // MARK: Toasts (one at a time, P-48 only)

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

    // MARK: Actions (P-48)

    private func actions(landscape: Bool) -> some View {
        let layout = landscape ? AnyLayout(VStackLayout(alignment: .trailing, spacing: Theme.s3))
                               : AnyLayout(HStackLayout(spacing: Theme.s3))
        return layout {
            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(.subheadline, weight: .semibold))
            }
            .buttonStyle(KeycapStyle(kind: .secondary, round: true))
            .accessibilityLabel("Settings")

            Button(action: onAgain) {
                Text("Again")
            }
            .buttonStyle(KeycapStyle(kind: .secondary))
            .accessibilityHint("Press another \(outcome.specimen.kind.displayName).")

            // One tap shares the clip when there is one (bible §10); the still is in the context menu.
            Button(action: shareDefault) {
                Text("Share")
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

            Button(action: onKeep) {
                KeyLabel(title: "Keep", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(KeycapStyle(kind: .primary, fullWidth: !landscape))
            .accessibilityFocused($focusKeep)
            .accessibilityHint(outcome.newlyUnlocked.first.map { "Files this card and puts the \($0.displayName) on the anvil." }
                               ?? "Files this card on the Shelf and puts the next object on the anvil.")
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

    /// When the card has finished appearing, counted from `onAppear`: the drop starts at 100 ms and its spring
    /// (response 0.5) has visibly settled ~0.9 s later.
    private static let cardSettledMilliseconds = 1_000
    /// Reduce Motion: the card fades in with `Theme.fade` (0.22 s).
    private static let cardFadedMilliseconds = 220
    /// Toasts are held this long after the reveal has settled, so the first thing the player sees is their specimen.
    private static let toastHoldMilliseconds = 1_500
    /// Each toast is up this long, the last one included, then leaves (FOLD-REVIEW-4 F4: none stays for good).
    private static let toastVisibleMilliseconds = 3_000
    /// The pause between one toast leaving and the next arriving, so the exit transition can play.
    private static let toastGapMilliseconds = 300

    /// Fold Press: the ceremony never waits longer than this for the inner display to light.
    private static let lightTimeout: Duration = .seconds(3)

    private func choreograph() {
        firstOfKind = collection.pressCount(of: outcome.specimen.kind) <= 1
        if foldPress {
            // FOLD-REVIEW-7 N10: the keys are up in the same frame as the diptych, with no fade, so the inner display
            // relights on a reveal you can act on. The lid shade is drawn too: it lifts once the panel is lit.
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                cardIn = true
                actionsIn = true
                if instantCeremony {
                    ceremony = .finished(tons: outcome.specimen.tons, badges: badges.count)
                }
            }
        }
        if UIAccessibility.isVoiceOverRunning {
            let announcement = ([specimen.accessibilitySentence, specimen.measurement.spoken + "."]
                                + toasts.map { "\($0.title.capitalized). \($0.detail)" })
                .joined(separator: " ")
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                UIAccessibility.post(notification: .announcement, argument: announcement)
                // Move focus to Keep so the user doesn't have to hunt for it (P1-10).
                try? await Task.sleep(for: .milliseconds(150))
                focusKeep = true
            }
        }
    }

    /// S5 on the Fold Press, step by step (see `RevealCeremony.swift`).
    private func runCeremony() async {
        await Self.waitForLight(revealLit, timeout: Self.lightTimeout)
        guard !Task.isCancelled, !collecting else { return }
        // 1. The lid lifts off the print.
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeIn(duration: 0.3)) { ceremony.lidLifted = true }
        guard await pause(320) else { return }
        // 2. The slow-mo replay of the break, pushing in on the anvil.
        if let duration = playReplay() {
            withAnimation(Theme.fade) { ceremony.replaying = true }
            guard await pause(Int(min(duration, RevealCeremony.replayCap) * 1000)) else { return }
            withAnimation(Theme.fade) { ceremony.replaying = false }
            guard !collecting else { return }
        }
        // 3. Before → after, then the stamp.
        withAnimation(Theme.cardDrop(reduceMotion)) { ceremony.ticketIn = true }
        guard await pause(220) else { return }
        if reduceMotion {
            ceremony.squash = 1
        } else {
            for step in 1...12 {
                ceremony.squash = Double(step) / 12
                guard await pause(40) else { return }
            }
        }
        guard await pause(160) else { return }
        withAnimation(Theme.stampFall(reduceMotion)) { ceremony.stamped = true }
        UIFeel.press()
        // 4. The stats count up: tons, then the badges one by one.
        let tons = outcome.specimen.tons
        if reduceMotion {
            ceremony.tons = tons
        } else {
            for step in 1...10 {
                withAnimation(.easeOut(duration: 0.05)) { ceremony.tons = tons * step / 10 }
                guard await pause(45) else { return }
            }
        }
        for index in 0..<badges.count {
            guard await pause(200) else { return }
            withAnimation(Theme.pop(reduceMotion)) { ceremony.badges = index + 1 }
            UIFeel.tick()
        }
        // 5. The museum slot fills, with a flash and a chime.
        guard await pause(240) else { return }
        withAnimation(Theme.pop(reduceMotion)) {
            ceremony.slotFilled = true
            ceremony.slotFlash = true
        }
        playCue(RevealCeremony.slotChime)
        #if DEBUG
        if DemoScenario.current != nil {   // ci verify pass: the finished ceremony, from the app's own window
            print("SQUISH-T toast shown 1/1 (reveal ceremony done, \(badges.count) badge(s))")
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                DemoCapture.window("toast-shot")
            }
        }
        #endif
        guard await pause(420) else { return }
        withAnimation(Theme.fade) { ceremony.slotFlash = false }
    }

    /// The P-48 card: drop, keys, then toasts one at a time (none on the first reveal).
    private func runCardReveal() async {
        if reduceMotion {
            // Shorter reveal (bible §6.4): card and actions together.
            withAnimation(Theme.fade) {
                cardIn = true
                actionsIn = true
            }
            guard await pause(Self.cardFadedMilliseconds) else { return }
        } else {
            guard await pause(100) else { return }
            withAnimation(Theme.cardDrop(reduceMotion)) { cardIn = true }
            guard await pause(500) else { return }
            withAnimation(Theme.settle(reduceMotion)) { actionsIn = true }
            guard await pause(Self.cardSettledMilliseconds - 600) else { return }
        }
        let count = toasts.count
        guard count > 0 else { return }
        guard await pause(Self.toastHoldMilliseconds) else { return }
        for index in 0..<count {
            if index > 0 { guard await pause(Self.toastGapMilliseconds) else { return } }
            guard !Task.isCancelled, !collecting else { return }
            withAnimation(Theme.pop(reduceMotion)) { toastIndex = index }
            if index == 0 { UIFeel.success() }
            #if DEBUG
            if DemoScenario.current != nil {   // ci verify pass
                print("SQUISH-T toast shown \(index + 1)/\(count)")
                if index == 0 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(600))   // past the pop-in
                        DemoCapture.window("toast-shot")
                    }
                }
            }
            #endif
            guard await pause(Self.toastVisibleMilliseconds) else { return }
            guard !Task.isCancelled else { return }
            withAnimation(Theme.fade) { toastIndex = -1 }
        }
    }

    /// Sleeps; false when the reveal has gone (the `.task` was cancelled) and the ceremony should stop.
    private func pause(_ milliseconds: Int) async -> Bool {
        try? await Task.sleep(for: .milliseconds(milliseconds))
        return !Task.isCancelled
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

/// `-squishDemo …;notoasts` (FOLD-REVIEW-4 F4, N8 "seed CI"): no reveal toasts (perfect, unlock, achievement), and the
/// Fold ceremony is shown finished at once, so store shots and CI reveals are deterministic. Read here, from the same
/// launch argument `DemoScenario` parses (`key=value;key`), so DemoMode.swift doesn't change. DEBUG only.
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
