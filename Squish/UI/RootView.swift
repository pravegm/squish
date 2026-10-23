import StoreKit
import SwiftUI
import UIKit

/// The Press screen (bible §5 screen 1) and the host for every other screen.
/// Layout (VISUAL-TARGET §6.1): the 45–80% stage band is sacred. Idle chrome is only the console
/// (object chip + Shelf key) in the 86–95% band, shown while an object can be chosen; Settings lives in the Shelf.
/// During a press: zero UI except captions and the failure flash. One-time tips use the 80–86% toast band.
struct RootView: View {
    @State private var director = PressDirector()
    @State private var tips = TipCenter()
    @State private var sheet: RootSheet?
    @State private var revealVisible = false
    @State private var collecting = false
    @State private var flyTarget: CGPoint?
    @State private var shelfKeyFrame: CGRect = .zero
    @State private var shelfHop = 0
    @State private var shelfBump = 0
    @State private var accessibleStep = 0
    @State private var touchedOnce = false
    @State private var uiCollected = false
    @State private var pendingCoach: String?
    @State private var demoCover: CoverView.Content?
    /// Fold Press: the platen's monoprint, captured once as the press seals, for the cover's sealed card.
    @State private var coverPrint: UIImage?
    @AppStorage("squish.askedForReview") private var askedForReview = false
    @AppStorage("squish.shelfDiscovered") private var shelfDiscovered = false
    /// Remembered once a hinge has ever reported, so a Duo never gets non-Duo copy (UX-REVIEW-1 P1-16).
    @AppStorage("squish.hasHinge") private var hasHinge = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.requestReview) private var requestReview

    enum RootSheet: Identifiable, Equatable {
        case shelf(ShelfView.Tab, demoDetail: UUID?, demoSettings: Bool)

        var id: String { "shelf" }
    }

    var body: some View {
        GeometryReader { proxy in
            let bands = ScreenBands(proxy, hinge: director.hingeAvailable || hasHinge)
            ZStack {
                // Behind the RealityView: the current gel wall colour, so launch and rotation flashes match (§3.4).
                Theme.gel(for: director.currentKind, golden: director.variant.isGolden)
                    .ignoresSafeArea()
                    .animation(reduceMotion ? nil : Theme.gelCrossfade, value: director.currentKind)

                stage(height: bands.fullHeight)

                FailureFlash(count: director.failureFlashCount)

                if !director.usesFoldPress {
                    // Fold Press teaches with its own sheen sweep and grip glows (FOLD-REVIEW-1 #14).
                    PressHints(director: director)
                    // P-48 touch press: the ram handle on the crosshead, at rest (FOLD-REVIEW-5 N6, screenshots.md P1).
                    PinchHandle(director: director, suppressed: revealVisible || collecting || isCoverUp || bands.isLandscape)
                }

                if director.settings.showCaptions && director.revealed == nil {
                    CaptionOverlay(caption: director.caption, kind: director.currentKind)
                }

                if (director.canChooseObject || collecting || consoleHoldsChip) && !isCoverUp {
                    console(bands)
                        .transition(.opacity)
                }

                if revealVisible, let outcome = director.revealed {
                    RevealCardView(
                        outcome: outcome,
                        collection: director.collection,
                        trace: director.trace(for: outcome.specimen),
                        collecting: collecting,
                        flyTarget: flyTarget,
                        hinge: bands.hinge,
                        foldPress: director.usesFoldPress,
                        onNext: { collect { director.next() } },
                        onAgain: { collect { director.again() } }
                    )
                    .id(outcome.specimen.id)
                    .transition(.opacity)
                }

                if let tip = tips.current, showsTips {
                    // Portrait: the 80–86% band (bottom half on a Duo). Book pose: the right half, clear of the crease.
                    // Fold Press: one line in the fold toast slot (platen foot / under the print), never the crown.
                    let tipFrame = tipPlacement(bands)
                    TipToast(tip: tip, compact: director.usesFoldPress)
                        .frame(width: tipFrame.width)
                        .position(x: tipFrame.midX, y: tipFrame.midY)
                        .onTapGesture { tips.dismissAll() }
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .id(tip.id)
                }

                if isCoverUp {
                    CoverView(
                        content: coverContent,
                        recent: Array(director.collection.specimens.prefix(3)),
                        currentKind: director.currentKind,
                        thumbnail: { director.collection.thumbnail(for: $0) },
                        reservesClockColumn: director.isShowingCover,
                        unlockedKinds: ObjectKind.allCases.filter { director.collection.isUnlocked($0) },
                        onQueue: coverQueue,
                        showsSafetyLine: tips.current?.kind == .safety,
                        sealedPrint: coverPrint
                    )
                    .transition(.opacity)
                }
            }
            .animation(Theme.fade, value: director.canChooseObject)
            .animation(Theme.fade, value: isCoverUp)
            .animation(Theme.pop(reduceMotion), value: tips.current)
        }
        .modifier(HingeReader(
            onUpdate: { angle, closed in director.hingeUpdate(angle: angle, closed: closed) },
            onUnavailable: { director.hingeUnavailable() }
        ))
        .onAppear(perform: launch)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { director.sceneBecameActive() }
        }
        .onChange(of: reduceMotion) { _, value in director.reduceMotion = value }
        .onChange(of: director.settings.hapticsLevel) { _, level in UIFeel.enabled = level != .off }
        .onChange(of: pressedPastContact) { _, pressed in
            // Sheets close only once the ram really touches the object, not on a 4° wobble (P2-10).
            if pressed { sheet = nil }
        }
        .onChange(of: director.engine.phase) { _, phase in
            if phase == .pressing { pressStarted() }
        }
        .onChange(of: director.isShowingCover) { _, covered in
            if covered { sheet = nil }
        }
        .onChange(of: coverIsSealed, initial: true) { _, sealed in
            coverPrint = sealed ? sealedPrintTeaser() : nil
        }
        .onChange(of: director.hingeAvailable) { _, available in
            if available { hingeArrived() }
        }
        .onChange(of: needsOpening) { _, needed in
            if needed { scheduleOpenUp() } else { tips.dismiss(.openUp) }
        }
        .onChange(of: director.coachHint) { _, hint in
            guard let hint else { return }
            pendingCoach = hint.text
            showPendingTips()
        }
        .onChange(of: director.canChooseObject) { _, canChoose in
            if canChoose { showPendingTips() }
        }
        .onChange(of: director.revealed?.specimen.id) { old, new in
            // Collected by the hinge (fold or close) rather than a keycap.
            if old != nil && new == nil {
                if uiCollected { uiCollected = false } else { didCollect() }
            }
        }
        .task(id: director.revealed?.specimen.id) {
            await stageReveal()
        }
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
        // ICON DEMO: `-squishDemo icon` shows only the app icon art, a full-width square centred on black, for
        // ci/screenshots.sh to crop into AppIcon-1024.png. DEBUG only (DemoScenario.current is nil in release).
        .overlay {
            if DemoScenario.current?.has("icon") == true {
                GeometryReader { geo in
                    ZStack {
                        Color.black
                        AppIconArt()
                            .frame(width: geo.size.width, height: geo.size.width)
                    }
                }
                .ignoresSafeArea()
            }
        }
        // ICON DEMO end
        .preferredColorScheme(.light)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Stage

    /// iPhone Duo: the two halves of the screen are the press (FOLD-PRESS.md). Every other iPhone: the P-48 machine.
    @ViewBuilder private var stageContent: some View {
        if director.usesFoldPress {
            FoldPressView(director: director)
        } else {
            PressSceneView(director: director)
        }
    }

    private func stage(height: CGFloat) -> some View {
        stageContent
            .ignoresSafeArea()
            .accessibilityIgnoresInvertColors(true)
            .gesture(touchPress(height: height), including: director.usesTouchPress ? .all : .none)
            .accessibilityElement()
            .accessibilityLabel("Press. \(director.currentKind.displayName) on the anvil.")
            .accessibilityValue(pressValue)
            .accessibilityHint(director.usesTouchPress
                               ? "Swipe up to press down, swipe down to ease off."
                               : "Fold your iPhone closed, slowly, to press. Open it again to see what's left.")
            .accessibilityAdjustableAction { direction in
                guard director.usesTouchPress, director.revealed == nil else { return }
                switch direction {
                case .increment: adjustAccessiblePress(by: 1)
                case .decrement: adjustAccessiblePress(by: -1)
                @unknown default: break
                }
            }
    }

    /// Pinch Press (UX-REVIEW-1 P0-2): the drag is scaled to the room left below the finger, so a press can
    /// always finish wherever it starts — including on the object itself. The end of the room is just past seal.
    private func touchPress(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !touchedOnce {
                    touchedOnce = true
                    tips.dismiss(.dragDown)
                }
                let room = min(max(height * 0.93 - value.startLocation.y, 160), height * 0.5)
                let sealFraction = (180 - director.engine.config.endAngle) / 180 + 0.04
                director.virtualPress(max(0, value.translation.height) / room * sealFraction)
            }
            .onEnded { _ in
                director.virtualRelease()
            }
    }

    /// VoiceOver value from the real press depth (P1-11).
    private var pressValue: String {
        let engine = director.engine
        switch engine.phase {
        case .sealed, .revealing: return "Sealed"
        case .idle, .armed, .pressing: break
        }
        if engine.measuredDepth < engine.mapping.contactT {
            return engine.measuredDepth > 0.01 ? "Approaching" : "Ready"
        }
        let compression = engine.measuredCompression
        return compression < 0.02 ? "Touching" : "\(Int((compression * 100).rounded())) percent squished"
    }

    /// VoiceOver press: step 1 is contact, then each swipe adds 12.5% compression; step 9 seals.
    private func adjustAccessiblePress(by delta: Int) {
        let config = director.engine.mapping
        accessibleStep = min(max(accessibleStep + delta, 0), 9)
        guard accessibleStep > 0 else {
            director.virtualRelease()
            return
        }
        let compression = Double(accessibleStep - 1) / 8
        let depth = min(1, config.contactT + (1 - config.contactT) * compression)
        let angle = PressMapping.angle(forDepth: depth, start: config.armAngleMax, config: config)
        director.virtualPress((180 - angle) / 180 + (accessibleStep == 9 ? 0.04 : 0))
        if accessibleStep >= 9 {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                director.virtualRelease()
                accessibleStep = 0
            }
        }
    }

    private var pressedPastContact: Bool {
        director.engine.measuredDepth >= director.engine.mapping.contactT || director.engine.phase == .sealed
    }

    // MARK: - Console (86–95%, or the right 22% column in landscape)

    /// Where one-time tips go: the Fold Press toast slot (the same one the reveal's toasts use, off the crown
    /// strip's gauge and hinge readout, FOLD-REVIEW-4 F4), the 80–86% band in portrait, or the right half in
    /// landscape (clear of the crease). Width is never below 300 pt.
    private func tipPlacement(_ bands: ScreenBands) -> CGRect {
        if director.usesFoldPress {
            return bands.foldToastSlot
        }
        if bands.isLandscape {
            let width = max(300, bands.fullWidth * 0.5 - ScreenBands.creaseHalf - bands.margin * 2)
            let center = CGPoint(x: bands.x(0.75), y: bands.size.height * 0.62)
            return CGRect(x: center.x - width / 2, y: center.y - 26, width: width, height: 52)
        }
        let width = min(420, bands.size.width - bands.margin * 2)
        return CGRect(x: bands.size.width / 2 - width / 2, y: bands.y(0.83) - 26, width: width, height: 52)
    }

    @ViewBuilder
    private func console(_ bands: ScreenBands) -> some View {
        // Tabletop (and non-folding phones): a fixed-width console in the 86–95% band, i.e. on the bottom plate's
        // outer edge on a Duo, far from the crease. Book pose: the right 22% column, right of the crease.
        // Fold Press: one row inside the bezel's 62 pt console band (FoldLayout.consoleBand), leaving the
        // pilot lamp at its far end uncovered (FOLD-REVIEW-1 #5).
        let foldBand = director.usesFoldPress ? bands.local(bands.foldLayout.consoleBand) : nil
        let width = foldBand.map { min($0.width - Theme.s3 * 2 - 36, 455) }
            ?? (bands.isLandscape ? max(180, bands.fullWidth * 0.22) : min(bands.size.width - bands.margin * 2, 440))
        let chrome = IdleConsole(director: director, landscape: bands.isLandscape && foldBand == nil, hop: shelfHop,
                                 bump: shelfBump,
                                 shelfOnly: collecting,
                                 chipOnly: consoleHoldsChip && !director.canChooseObject && !collecting,
                                 onShelf: openShelf,
                                 onShelfFrame: { shelfKeyFrame = $0 },
                                 width: width)
        if let foldBand {
            chrome
                .position(x: foldBand.minX + Theme.s3 + width / 2, y: foldBand.midY)
        } else if bands.isLandscape {
            chrome
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, bands.margin)
                .padding(.bottom, Theme.s4)
        } else {
            chrome
                .position(x: bands.size.width / 2, y: bands.y(0.905))
        }
    }

    /// Fold Press, mid-press (FOLD-REVIEW-3 N16): the object chip stays in the console, dimmed and inert, so the
    /// console band isn't empty graphite and every pressing frame says what's on the anvil. Not during the reveal
    /// (its own keys own the band) and never on the P-48, whose press keeps zero chrome.
    private var consoleHoldsChip: Bool {
        director.usesFoldPress && director.revealed == nil && !revealVisible
    }

    private func openShelf() {
        shelfDiscovered = true
        sheet = .shelf(.objects, demoDetail: nil, demoSettings: false)
    }

    // MARK: - Sheets (§6.7)

    @ViewBuilder
    private func sheetContent(_ item: RootSheet) -> some View {
        switch item {
        case let .shelf(tab, demoDetail, demoSettings):
            ShelfView(director: director, initialTab: tab, demoDetail: demoDetail, demoSettings: demoSettings)
                // On a Duo the medium detent's top edge would sit in the crease (P1-19).
                .presentationDetents([hasHinge ? .fraction(0.45) : .medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.sheetRadius)
                .presentationBackground { AlbumPage() }
                .presentationContentInteraction(.scrolls)
                .sheetTypeCap()
                .creaseSafe()
        }
    }

    // MARK: - Reveal

    /// The card waits ~0.8 s so the ram lifts first (0.3 s under Reduce Motion), and for the specimen photo,
    /// so the peak moment never swaps a placeholder for the real thing (P1-1).
    private func stageReveal() async {
        guard let outcome = director.revealed else {
            revealVisible = false
            collecting = false
            flyTarget = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 800))
        var waited = 0
        while director.collection.specimen(withID: outcome.specimen.id)?.thumbnailFile == nil && waited < 700 {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            waited += 50
        }
        guard !Task.isCancelled, director.revealed != nil else { return }
        tips.dismissAll()
        revealVisible = true
        accessibleStep = 0
        await askForReviewIfDue()
    }

    /// Once, after a reveal, after about 10 presses (bible §11). Never mid-press, never in demo runs.
    private func askForReviewIfDue() async {
        guard !askedForReview, director.completedPresses >= 10, DemoScenario.current == nil else { return }
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled, director.revealed != nil else { return }
        askedForReview = true
        requestReview()
    }

    /// Collect (P1-2): the reveal actions fade, the Shelf key appears on the console, the card flies into it,
    /// the key sinks in and its count rolls, then the next object is placed.
    private func collect(_ action: @escaping () -> Void) {
        guard !collecting else { return }
        withAnimation(.easeOut(duration: 0.15)) { collecting = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90)) // let the Shelf key lay out
            let target = CGPoint(x: shelfKeyFrame.midX, y: shelfKeyFrame.midY)
            withAnimation(reduceMotion ? Theme.fade : .spring(response: 0.38, dampingFraction: 0.72)) { flyTarget = target }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 230 : 400))
            uiCollected = true
            revealVisible = false
            flyTarget = nil
            action()
            collecting = false
            didCollect()
        }
    }

    /// After any collect (keycap or hinge): land the card in the Shelf, then queue gentle one-time tips.
    private func didCollect() {
        shelfBump += 1
        GameCenter.shared.firstRunFinished()
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        // After the second press the Shelf key hops once so people discover the collection (bible §3.2 step 8).
        if !shelfDiscovered && director.completedPresses >= 2 {
            shelfDiscovered = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                shelfHop += 1
            }
        }
        showPendingTips()
    }

    // MARK: - Tips (UX-REVIEW-1 §6.3)

    private var isDemo: Bool { DemoScenario.current != nil }

    private var showsTips: Bool {
        !isCoverUp && !revealVisible && director.revealed == nil && director.engine.phase != .pressing
            && director.engine.phase != .sealed
    }

    /// Hinge present, idle because it's folded below the arming angle (P1-15).
    private var needsOpening: Bool {
        director.hingeAvailable && !director.usesTouchPress && !director.isShowingCover && director.revealed == nil
            && director.engine.phase == .idle && director.engine.angle < director.engine.config.armAngleMin
    }

    private func scheduleOpenUp() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if needsOpening { tips.show(tips.openUp()) }
        }
    }

    private func hingeArrived() {
        hasHinge = true
        tips.dismiss(.dragDown)
        guard !isDemo, !director.settings.hasSeenSafetyHint else { return }
        // Duo only (P1-5): shown until the first press starts; marked seen once it has been up 3 s.
        let tip = tips.safety()
        tips.show(tip)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if tips.current?.id == tip.id { markSafetySeen() }
        }
    }

    private func markSafetySeen() {
        guard !director.settings.hasSeenSafetyHint else { return }
        director.settings.hasSeenSafetyHint = true
        director.settings.save()
    }

    private func pressStarted() {
        if tips.current?.kind == .safety { markSafetySeen() }
        tips.dismissAll()
    }

    /// Coaching and the one-time sound tip wait for a calm, idle moment (never during a press or the reveal).
    private func showPendingTips() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard director.canChooseObject, !revealVisible, tips.current == nil else { return }
            if let line = pendingCoach {
                pendingCoach = nil
                tips.show(tips.coach(line))
            } else if !isDemo, director.completedPresses >= 1, !TipCenter.hasShown(.sound) {
                TipCenter.markShown(.sound)
                tips.show(tips.sound(soundOff: !director.settings.soundEnabled))
            }
        }
    }

    /// Touch press, first run: if nothing has been touched after 8 s, one "DRAG DOWN" tip until the first touch.
    private func scheduleDragHint(after delay: Duration) {
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard director.usesTouchPress, !hasHinge, !touchedOnce, director.completedPresses == 0,
                  director.revealed == nil, tips.current == nil else { return }
            if !isDemo { TipCenter.markShown(.dragDown) }
            tips.show(tips.dragDown())
        }
    }

    // MARK: - Cover

    private var isCoverUp: Bool { director.isShowingCover || demoCover != nil }

    /// Cover chips queue the next object; hidden while a reveal is still pending (no dead chips, P0-4).
    private var coverQueue: ((ObjectKind) -> Void)? {
        guard director.revealed == nil else { return nil }
        let director = director
        return { kind in
            UIFeel.tick()
            director.queue(kind)
        }
    }

    private var coverIsSealed: Bool {
        if case .sealed = coverContent { return true }
        return false
    }

    /// The cover's teaser (FOLD-REVIEW-3 N16): the print the platen took of this press, exactly as it lies on the
    /// lid (`FoldPlaten.printImage()`, the same image the collection card's diptych uses). Fold Press only: the
    /// P-48 has no platen print, and a demo cover has none yet, so both keep the silhouette teaser.
    private func sealedPrintTeaser() -> UIImage? {
        guard director.usesFoldPress, demoCover == nil, let image = director.fold.platen.printImage() else { return nil }
        return UIImage(cgImage: image, scale: 2, orientation: .up)
    }

    private var coverContent: CoverView.Content {
        if let demoCover { return demoCover }
        if director.engine.phase == .sealed, let result = director.engine.lastResult {
            // A provisional record, so the cover shows exactly the tonnage the card will.
            let provisional = SpecimenRecord(
                id: UUID(), number: director.completedPresses + 1, kind: result.kind, date: Date(),
                variant: PressVariant(kind: result.kind, seed: result.seed),
                fractureCount: result.fractureCount, maxCompression: result.maxCompression,
                failureAngle: result.failureAngle, duration: result.duration,
                isPerfect: result.isPerfect, wasSlammed: result.wasSlammed, reversals: result.reversals
            )
            return .sealed(kind: result.kind, tons: provisional.tons)
        }
        return .idle
    }

    // MARK: - Launch

    private func launch() {
        director.reduceMotion = reduceMotion
        UIFeel.enabled = director.settings.hapticsLevel != .off
        director.start()

        if let demo = DemoScenario.current {
            runDemo(demo)
            return
        }
        if director.hingeAvailable { hingeArrived() }
        // The crosshead's Pinch Press handle says "drag down" from the first frame (`PinchHandle`), so the toast is
        // only a late fallback for someone who still hasn't touched anything.
        if !TipCenter.hasShown(.dragDown) { scheduleDragHint(after: .seconds(20)) }
    }

    /// UI demo keys for CI screenshots (see ci/scenarios.txt): `shelf[=squished]`, `detail`, `settings`, `cover[=sealed]`.
    /// `launch` no longer raises the DRAG DOWN toast: frame 01 shows the handle on the machine instead, with the
    /// anvil clear (FOLD-REVIEW-5 N6: "`01` has a coach card and no visible handle").
    private func runDemo(_ demo: DemoScenario) {
        if demo.has("cover") {
            demoCover = demo.string("cover") == "sealed" ? .sealed(kind: demo.object ?? .rubberDuck, tons: 48) : .idle
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            if demo.has("settings") {
                sheet = .shelf(.objects, demoDetail: nil, demoSettings: true)
            } else if demo.has("detail") {
                let best = ObjectKind.allCases.compactMap { director.collection.best(for: $0) }
                    .first { $0.variant.isGolden } ?? director.collection.specimens.first
                sheet = .shelf(.objects, demoDetail: best?.id, demoSettings: false)
            } else if demo.has("shelf") {
                sheet = .shelf(demo.string("shelf") == "squished" ? .squished : .objects, demoDetail: nil, demoSettings: false)
            }
        }
    }
}
